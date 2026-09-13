import XCTest

final class MellowUITests: XCTestCase {
    @MainActor
    private func cameraTestApp(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestCamera"] + arguments
        return app
    }

    // MARK: - Root flow

    @MainActor
    func testFirstRunOnboardingLeadsDirectlyToCamera() throws {
        let app = cameraTestApp(["-cameraNotDetermined", "-uiTestResetOnboarding"])
        app.launch()

        XCTAssertTrue(app.staticTexts["permissionOnboardingTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["permissionOnboardingTitle"].label, "Before you start")
        XCTAssertFalse(app.otherElements["cameraShell"].exists, "Camera must not precede onboarding")
        app.buttons["permissionOnboardingContinue"].tap()

        // Onboarding hands straight to the root Camera; no format chooser in between.
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["formatTitle"].exists)
        try auditAndCapture(app, name: "First Run Camera")

        app.terminate()
        // Relaunch without the reset hook: persisted completion, not the hook, suppresses onboarding.
        app.launchArguments = ["-uiTestCamera", "-cameraNotDetermined"]
        app.launch()
        XCTAssertFalse(app.staticTexts["permissionOnboardingTitle"].exists)
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))

        app.terminate()
        let existingAuthorizedApp = cameraTestApp(["-uiTestSkipOnboarding"])
        existingAuthorizedApp.launch()
        XCTAssertFalse(existingAuthorizedApp.staticTexts["permissionOnboardingTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(existingAuthorizedApp.otherElements["cameraShell"].exists)
        existingAuthorizedApp.terminate()
    }

    @MainActor
    func testLaunchAloneDoesNotPersistEmptyProject() throws {
        let app = cameraTestApp()
        launchToCamera(app)
        removeProjects(in: app)

        // Reaching the root Camera repeatedly must never accumulate zero-clip projects.
        for _ in 0..<3 {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        }
        openProjects(in: app)
        XCTAssertTrue(app.staticTexts["emptyRecent"].exists, "App launch must not persist a project")
        XCTAssertEqual(projectButtons(in: app).count, 0)
        try auditAndCapture(app, name: "Empty Recent After Launches")
        backToCamera(in: app)
    }

    @MainActor
    func testRootCameraChromeHasProjectsAndNoBackRoute() throws {
        let app = cameraTestApp()
        launchToCamera(app)

        let projects = app.buttons["projects"]
        XCTAssertTrue(projects.exists)
        XCTAssertTrue(projects.isHittable)
        XCTAssertGreaterThanOrEqual(projects.frame.width, 44)
        XCTAssertGreaterThanOrEqual(projects.frame.height, 44)
        // Projects sits in the upper trailing chrome, above the controls.
        XCTAssertGreaterThan(projects.frame.midX, app.frame.midX)
        XCTAssertLessThan(projects.frame.midY, app.frame.height / 2)

        // The root Camera is the application root: no Back to a removed format chooser.
        XCTAssertEqual(app.navigationBars.buttons.matching(identifier: "BackButton").count, 0)
        XCTAssertFalse(app.buttons["continueProject"].exists)
        XCTAssertFalse(app.staticTexts["formatTitle"].exists)
        XCTAssertFalse(app.buttons["portrait9x16"].exists)
        XCTAssertFalse(app.buttons["landscape16x9"].exists)
        try auditAndCapture(app, name: "Root Camera Chrome")
    }

    @MainActor
    func testProjectsNavigationAndExistingProjectBackSemantics() throws {
        let app = cameraTestApp(["-uiTestSeedPortrait"])
        launchToCamera(app)

        openProjects(in: app)
        XCTAssertEqual(projectButtons(in: app).count, 1)
        try auditAndCapture(app, name: "Recent From Camera")

        projectButtons(in: app).firstMatch.tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        // An existing project keeps a Back affordance returning to Recent Projects.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Recent Projects"].waitForExistence(timeout: 3))

        backToCamera(in: app)
        removeProjects(in: app)
    }

    @MainActor
    func testExistingLandscapeProjectIsRefusedWithoutMutation() throws {
        let app = cameraTestApp(["-uiTestSeedLandscape"])
        launchToCamera(app)
        openProjects(in: app)
        XCTAssertEqual(projectButtons(in: app).count, 1)

        projectButtons(in: app).firstMatch.tap()
        // V1 refuses landscape capture instead of silently reinterpreting the project as portrait.
        XCTAssertTrue(app.otherElements["unsupportedCapture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cameraShutter"].exists)
        try auditAndCapture(app, name: "Unsupported Landscape Project")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Recent Projects"].waitForExistence(timeout: 3))
        // The persisted orientation is untouched by opening it.
        XCTAssertEqual(projectButtons(in: app).count, 1)
        backToCamera(in: app)
        removeProjects(in: app)
    }

    // MARK: - Portrait camera

    @MainActor
    func testPortraitCameraFullBleedAndFraming() throws {
        let app = cameraTestApp()
        launchToCamera(app)

        let shell = app.otherElements["cameraShell"]
        let appFrame = app.frame
        XCTAssertGreaterThan(shell.frame.width, appFrame.width * 0.9)
        XCTAssertGreaterThan(shell.frame.height, appFrame.height * 0.9)
        XCTAssertGreaterThan(appFrame.height, appFrame.width, "V1 capture is portrait only")
        try auditAndCapture(app, name: "Portrait Camera Full Bleed")
    }

    @MainActor
    func testCameraControlsAndDurationSelector() throws {
        let app = cameraTestApp()
        launchToCamera(app)
        XCTAssertEqual(app.alerts.count, 0, "Mock authorization must avoid system permission alerts")

        let shutter = app.buttons["cameraShutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        XCTAssertTrue(shutter.isEnabled)
        let picker = app.otherElements["durationPicker"]
        XCTAssertTrue(picker.exists)
        XCTAssertGreaterThanOrEqual(picker.frame.height, 44)
        XCTAssertGreaterThanOrEqual(picker.frame.width, 170)
        XCTAssertEqual(picker.label, "Duration")
        XCTAssertEqual(picker.value as? String, "3 seconds", "default remains 3s")

        // Tapping the visible side values selects them; the window recentres each time.
        tapPickerSide(picker, .right); expectDuration(picker, 4)
        tapPickerSide(picker, .right); expectDuration(picker, 5)
        tapPickerSide(picker, .right); expectDuration(picker, 5, "upper clamp: nothing past 5s")
        tapPickerSide(picker, .left); expectDuration(picker, 4)

        // Dragging snaps exactly one second per gesture, in either direction, clamped at 1s.
        picker.swipeLeft(); expectDuration(picker, 5)
        picker.swipeRight(); expectDuration(picker, 4)
        picker.swipeRight(); expectDuration(picker, 3)
        picker.swipeRight(); expectDuration(picker, 2)
        picker.swipeRight(); expectDuration(picker, 1)
        picker.swipeRight(); expectDuration(picker, 1, "lower clamp: nothing below 1s")
        picker.swipeLeft(); expectDuration(picker, 2)
        tapPickerSide(picker, .right); expectDuration(picker, 3)

        let flip = app.buttons["cameraSwitch"]
        XCTAssertTrue(flip.isEnabled)
        flip.tap()
        XCTAssertEqual(flip.value as? String, "Front camera")
        flip.tap()
        XCTAssertEqual(flip.value as? String, "Rear camera")

        let preview = app.otherElements["cameraShell"]
        preview.pinch(withScale: 4, velocity: 2)
        expectZoom(preview, "2.0×")
        // A pinch-close starts at the element's outer bounds, which on the full-bleed layout is the
        // overlay control row; those touches belong to the controls. The clamp back to 1.0× through a
        // real gesture is covered by testCameraAccessibilityLargeText, where controls sit below the
        // preview, and the clamp itself by CameraModelTests.

        XCTAssertTrue(app.otherElements["projectContent"].exists)
        try auditAndCapture(app, name: "Camera Controls")

        XCUIDevice.shared.press(.home)
        app.activate()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
    }

    @MainActor
    func testRotateGuidanceDisablesCapture() throws {
        let app = cameraTestApp(["-cameraMismatch"])
        launchToCamera(app)
        XCTAssertTrue(app.staticTexts["cameraMismatch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cameraShutter"].isEnabled)
        XCTAssertTrue(app.buttons["cameraSwitch"].isEnabled)
        try auditAndCapture(app, name: "Rotate Your iPhone")
    }

    @MainActor
    func testCameraDeniedRestrictedAndFailureStates() throws {
        for argument in ["-cameraDenied", "-cameraRestricted", "-cameraFailure"] {
            let app = cameraTestApp([argument])
            launchToCamera(app)
            XCTAssertFalse(app.buttons["cameraShutter"].isEnabled)
            XCTAssertEqual(app.alerts.count, 0)
            XCTAssertFalse(app.buttons["cameraSwitch"].isEnabled)
            if argument == "-cameraFailure" {
                XCTAssertTrue(app.buttons["Try Again"].exists)
            } else {
                XCTAssertTrue(app.buttons["openSettings"].isHittable)
            }
            // Projects access stays reachable even when capture is unavailable.
            XCTAssertTrue(app.buttons["projects"].exists)
            try auditAndCapture(app, name: argument)
            app.terminate()
        }
    }

    // MARK: - Accessibility

    @MainActor
    func testCameraAccessibilityLargeText() throws {
        let app = cameraTestApp(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        launchToCamera(app)
        let preview = app.otherElements["cameraShell"]
        // Controls sit below the preview at this size, so both pinch directions reach the gesture.
        preview.pinch(withScale: 4, velocity: 2)
        expectZoom(preview, "2.0×")
        preview.pinch(withScale: 0.2, velocity: -2)
        expectZoom(preview, "1.0×")
        app.swipeUp()
        // The picker scales only modestly at accessibility sizes and stays a single operable row.
        let picker = app.otherElements["durationPicker"]
        XCTAssertTrue(picker.isHittable)
        XCTAssertGreaterThanOrEqual(picker.frame.height, 44)
        XCTAssertEqual(picker.value as? String, "3 seconds")
        tapPickerSide(picker, .left); expectDuration(picker, 2)
        tapPickerSide(picker, .left); expectDuration(picker, 1)
        tapPickerSide(picker, .right); expectDuration(picker, 2)
        picker.swipeLeft(); expectDuration(picker, 3)
        try auditAndCapture(app, name: "Accessibility Camera")
    }

    @MainActor
    func testAccessibilityRecentAndDeleteConfirmation() throws {
        let app = cameraTestApp(["-uiTestSeedPortrait"])
        launchToCamera(app)
        openProjects(in: app)
        XCTAssertTrue(projectButtons(in: app).firstMatch.isHittable)
        try auditAndCapture(app, name: "Recent Projects")

        options(in: app).firstMatch.tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete vlog?"].waitForExistence(timeout: 3))
        try auditAndCapture(app, name: "Delete Confirmation")
        app.alerts.buttons["Cancel"].tap()
        XCTAssertEqual(projectButtons(in: app).count, 1)

        options(in: app).firstMatch.tap()
        app.buttons["Delete"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertEqual(projectButtons(in: app).count, 0)
        backToCamera(in: app)
    }

    @MainActor
    func testAccessibilityDynamicTypeRecent() throws {
        let app = cameraTestApp([
            "-uiTestSeedPortrait",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        launchToCamera(app)
        openProjects(in: app)
        XCTAssertTrue(projectButtons(in: app).firstMatch.isHittable)
        try auditAndCapture(app, name: "Accessibility Recent")
        backToCamera(in: app)
        removeProjects(in: app)
    }

    // MARK: - Helpers

    private enum PickerSide { case left, right }

    /// The picker is one adjustable accessibility element, so side values are reached by position:
    /// the selected value is centred and its neighbours sit one 40pt slot to either side of a
    /// 184pt window, i.e. at roughly 28% / 72% of the width.
    @MainActor
    private func tapPickerSide(_ picker: XCUIElement, _ side: PickerSide) {
        picker.coordinate(withNormalizedOffset: CGVector(dx: side == .left ? 52.0 / 184 : 132.0 / 184, dy: 0.5)).tap()
    }

    @MainActor
    private func expectDuration(_ picker: XCUIElement, _ seconds: Int, _ note: String = "") {
        let expected = "\(seconds) second\(seconds == 1 ? "" : "s")"
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed,
                       "picker at \(String(describing: picker.value)) instead of \(expected). \(note)")
    }

    /// Zoom is applied through an async hop, so the clamped value settles after the gesture ends.
    @MainActor
    private func expectZoom(_ preview: XCUIElement, _ expected: String) {
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected),
            object: preview
        )
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed,
                       "zoom settled at \(String(describing: preview.value)) instead of \(expected)")
    }

    @MainActor
    private func auditAndCapture(_ app: XCUIApplication, name: String) throws {
        capture(app, name: name)
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription])
    }

    @MainActor
    private func launchToCamera(_ app: XCUIApplication) {
        app.launch()
        if app.staticTexts["permissionOnboardingTitle"].waitForExistence(timeout: 1) {
            app.buttons["permissionOnboardingContinue"].tap()
        }
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openProjects(in app: XCUIApplication) {
        app.buttons["projects"].tap()
        XCTAssertTrue(app.navigationBars["Recent Projects"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func backToCamera(in app: XCUIApplication) {
        if app.navigationBars["Recent Projects"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func projectButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'project-'"))
    }

    @MainActor
    private func options(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'options-'"))
    }

    @MainActor
    private func removeProjects(in app: XCUIApplication) {
        // Only the dedicated test Simulator's app container is used by this suite.
        if !app.navigationBars["Recent Projects"].exists, app.buttons["projects"].exists {
            openProjects(in: app)
        }
        while options(in: app).count > 0 {
            if !options(in: app).firstMatch.isHittable { app.swipeUp() }
            options(in: app).firstMatch.tap()
            app.buttons["Delete"].tap()
            app.alerts.buttons["Delete"].tap()
        }
        backToCamera(in: app)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        // Capture the whole display; app.screenshot() can crop rotated landscape bounds.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
