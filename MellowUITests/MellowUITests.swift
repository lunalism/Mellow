import XCTest

final class MellowUITests: XCTestCase {
    @MainActor
    private func cameraTestApp(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestCamera"] + arguments
        return app
    }

    /// Historical Phase 2/3 regressions (and cleanup through the Recent browser) keep the transitional
    /// Camera → Recent path via a DEBUG-only argument; canonical production routing goes to `프로젝트`.
    @MainActor
    private func legacyRecentApp(_ arguments: [String] = []) -> XCUIApplication {
        cameraTestApp(["-uiTestLegacyRecentProjects"] + arguments)
    }

    // MARK: - Root flow

    @MainActor
    func testFirstRunOnboardingLeadsDirectlyToCamera() throws {
        let app = cameraTestApp(["-cameraNotDetermined", "-micNotDetermined", "-photosAddNotDetermined", "-uiTestResetOnboarding"])
        app.launch()

        XCTAssertTrue(app.staticTexts["permissionOnboardingTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["permissionOnboardingTitle"].label, "Before you start")
        XCTAssertFalse(app.otherElements["cameraShell"].exists, "Camera must not precede onboarding")

        // One screen: Camera row visible; later rows and Start Mellow hidden until each decision.
        XCTAssertTrue(app.buttons["permissionAllow-camera"].exists)
        XCTAssertFalse(app.buttons["permissionAllow-microphone"].exists, "Microphone hidden before Camera decision")
        XCTAssertFalse(app.buttons["permissionAllow-photos"].exists)
        XCTAssertFalse(app.buttons["startMellow"].exists)
        try auditAndCapture(app, name: "Onboarding Camera Only")

        app.buttons["permissionAllow-camera"].tap()
        XCTAssertTrue(app.buttons["permissionAllow-microphone"].waitForExistence(timeout: 3), "Camera decision reveals Microphone")
        XCTAssertTrue(app.otherElements["permissionRow-camera"].exists, "Camera row remains visible")
        XCTAssertFalse(app.buttons["permissionAllow-photos"].exists, "Photos hidden before Microphone decision")
        XCTAssertFalse(app.buttons["startMellow"].exists)

        app.buttons["permissionAllow-microphone"].tap()
        XCTAssertTrue(app.buttons["permissionAllow-photos"].waitForExistence(timeout: 3), "Microphone decision reveals Photos")
        XCTAssertFalse(app.buttons["startMellow"].exists, "Start hidden before Photos decision")
        try auditAndCapture(app, name: "Onboarding All Rows")

        app.buttons["permissionAllow-photos"].tap()
        XCTAssertTrue(app.buttons["startMellow"].waitForExistence(timeout: 3), "Photos decision reveals Start Mellow")
        // No page navigation ever happened: one title throughout.
        XCTAssertEqual(app.staticTexts.matching(identifier: "permissionOnboardingTitle").count, 1)
        app.buttons["startMellow"].tap()

        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["formatTitle"].exists)
        try auditAndCapture(app, name: "First Run Camera")

        app.terminate()
        // Relaunch without the reset hook: persisted completion, not the hook, suppresses onboarding.
        app.launchArguments = ["-uiTestCamera", "-cameraNotDetermined", "-micNotDetermined", "-photosAddNotDetermined"]
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
        let app = legacyRecentApp()
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
        let app = legacyRecentApp(["-uiTestSeedPortrait"])
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
        let app = legacyRecentApp(["-uiTestSeedLandscape"])
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

    // Phase 5 STEP 4: existing-project Editor foundation, reached through deterministic test routing
    // (production Recent-item navigation is intentionally unchanged in this slice).
    @MainActor
    func testProjectEditorOpensSeededProjectAndSelectsClips() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestOpenEditor"])
        app.launch()

        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["projectEditorPreview"].exists)
        XCTAssertTrue(app.staticTexts["projectTotalDuration"].exists)

        // Three ordered clip items appear.
        let clip1 = app.buttons["editorClip-1"]
        let clip2 = app.buttons["editorClip-2"]
        let clip3 = app.buttons["editorClip-3"]
        XCTAssertTrue(clip1.waitForExistence(timeout: 2))
        XCTAssertTrue(clip2.exists)
        XCTAssertTrue(clip3.exists)

        // First clip selected initially; selection is semantic (accessibility value), not colour-only.
        XCTAssertEqual(clip1.value as? String, "Selected")
        XCTAssertEqual(clip2.value as? String, "Not selected")

        // Selecting another clip changes selection.
        clip2.tap()
        XCTAssertEqual(clip2.value as? String, "Selected")
        XCTAssertEqual(clip1.value as? String, "Not selected")

        try auditAndCapture(app, name: "Project Editor Shell")

        // Back returns safely to the Camera root.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))

        // Clean up the seeded project so it does not leak into other tests' shared container.
        removeProjects(in: app)
    }

    // MARK: - Phase 5 STEP 8: immersive Editor + bottom timeline (deterministic fixture thumbnails)

    /// Three thumbnail cells in a leading-aligned timeline inside the bottom dock, duration
    /// overlays, quiet Total, tap Clip 2 → selected outline; dark workspace even in a Light app.
    @MainActor
    func testEditorTimelineShowsOrderedThumbnailsWithSelection() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestOpenEditor"])
        app.launch()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["editorDock"].exists)

        let clips = (1...3).map { app.buttons["editorClip-\($0)"] }
        for clip in clips { XCTAssertTrue(clip.waitForExistence(timeout: 2)) }
        XCTAssertFalse(app.buttons["editorClip-4"].exists)
        for (index, clip) in clips.enumerated() {
            expectLabel(clip, "Clip \(index + 1) of 3, \(["2.0s", "3.0s", "1.0s"][index])")
            XCTAssertGreaterThanOrEqual(clip.frame.width, 44)
            XCTAssertGreaterThanOrEqual(clip.frame.height, 44)
            XCTAssertEqual(clip.frame.width, 44, accuracy: 3, "compact 44×78 timeline cells")
            XCTAssertEqual(clip.frame.height, 78, accuracy: 3)
        }
        // Leading-aligned logical order, never centred: the first cell sits in the left part of the
        // dock right after the reserved add slot, and the group is left-heavy.
        let dock = app.otherElements["editorDock"]
        let preview = app.otherElements["projectEditorPreview"]
        XCTAssertLessThan(clips[0].frame.minX, clips[1].frame.minX)
        XCTAssertLessThan(clips[1].frame.minX, clips[2].frame.minX)
        // DEBUG staging: the 40 pt Add reference precedes the strip (leading 10 + 40 + 8 = 58).
        XCTAssertEqual(clips[0].frame.minX - dock.frame.minX, 58, accuracy: 4, "timeline starts right after the staged add slot")
        XCTAssertGreaterThan(dock.frame.maxX - clips[2].frame.maxX, clips[0].frame.minX - dock.frame.minX,
                             "a short project is leading-aligned, not centred")
        // Compact dock (~100 pt) directly below the full-height preview canvas, near the bottom.
        XCTAssertEqual(dock.frame.height, 100, accuracy: 6, "compact dock")
        XCTAssertGreaterThanOrEqual(dock.frame.minY, preview.frame.maxY - 1)
        XCTAssertLessThan(dock.frame.minY - preview.frame.maxY, 14, "preview and dock read as one editor")
        XCTAssertGreaterThan(dock.frame.maxY, app.frame.height * 0.85)
        // The preview canvas owns almost everything between the navigation bar and the dock.
        XCTAssertGreaterThan(preview.frame.height, app.frame.height * 0.6)
        XCTAssertGreaterThan(preview.frame.width, app.frame.width * 0.95, "no card inset")
        XCTAssertFalse(app.staticTexts["Timeline"].exists, "no Timeline heading")
        XCTAssertGreaterThan(app.staticTexts["projectTotalDuration"].frame.minX, dock.frame.midX, "quiet trailing total")
        XCTAssertTrue(app.staticTexts["projectTotalDuration"].exists)
        XCTAssertEqual(app.staticTexts["projectTotalDuration"].label, "Total duration 6.0s")

        XCTAssertEqual(clips[0].value as? String, "Selected")
        XCTAssertEqual(clips[1].value as? String, "Not selected")
        try auditAndCapture(app, name: "editor-timeline-v4-selected-first")

        clips[1].tap()
        XCTAssertEqual(clips[1].value as? String, "Selected")
        XCTAssertEqual(clips[0].value as? String, "Not selected")
        XCTAssertEqual(clips[2].value as? String, "Not selected")
        expectLabel(clips[0], "Clip 1 of 3, 2.0s")
        expectLabel(clips[1], "Clip 2 of 3, 3.0s")
        XCTAssertEqual(preview.label, "Preview, selected clip 2")
        try auditAndCapture(app, name: "editor-timeline-v4-selected-second")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        removeProjects(in: app)
    }

    /// One thumbnail failure → neutral placeholder stays in the same timeline slot, selection untouched.
    @MainActor
    func testEditorTimelineKeepsFailedThumbnailInPlace() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestOpenEditor", "-uiTestThumbnailFailure=2"])
        app.launch()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))

        let clip1 = app.buttons["editorClip-1"], clip2 = app.buttons["editorClip-2"], clip3 = app.buttons["editorClip-3"]
        XCTAssertTrue(clip3.waitForExistence(timeout: 2))
        expectLabel(clip1, "Clip 1 of 3, 2.0s")
        expectLabel(clip2, "Clip 2 of 3, 3.0s, thumbnail unavailable")
        expectLabel(clip3, "Clip 3 of 3, 1.0s")
        XCTAssertLessThan(clip1.frame.minX, clip2.frame.minX)
        XCTAssertLessThan(clip2.frame.minX, clip3.frame.minX)
        XCTAssertEqual(clip2.frame.width, clip1.frame.width, accuracy: 1, "same geometry as a healthy cell")
        XCTAssertEqual(clip1.value as? String, "Selected", "a failed thumbnail never changes selection")
        XCTAssertEqual(app.staticTexts["projectTotalDuration"].label, "Total duration 6.0s", "the clip keeps its slot and its duration")
        clip2.tap()
        XCTAssertEqual(clip2.value as? String, "Selected")
        clip1.tap()
        XCTAssertEqual(clip1.value as? String, "Selected")
        try auditAndCapture(app, name: "editor-timeline-v4-failure")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        removeProjects(in: app)
    }

    /// Many clips: the timeline overflows and scrolls horizontally; order and selection survive.
    @MainActor
    func testEditorTimelineScrollsWithManyClips() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestOpenEditor", "-uiTestSeedEditorClips=9"])
        app.launch()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        let first = app.buttons["editorClip-1"], last = app.buttons["editorClip-9"]
        XCTAssertTrue(first.waitForExistence(timeout: 2))
        expectLabel(first, "Clip 1 of 9, 2.0s")
        XCTAssertEqual(first.value as? String, "Selected")
        XCTAssertEqual(app.staticTexts["projectTotalDuration"].label, "Total duration 18.0s")
        try auditAndCapture(app, name: "editor-timeline-v4-many-clips")

        // The last cell is off-screen until the timeline is scrolled; scrolling never reorders.
        XCTAssertFalse(last.exists && last.isHittable)
        var attempts = 0
        while !(last.exists && last.isHittable), attempts < 4 { app.buttons["editorClip-3"].swipeLeft(); attempts += 1 }
        XCTAssertTrue(last.isHittable)
        last.tap()
        XCTAssertEqual(last.value as? String, "Selected")
        XCTAssertEqual(app.otherElements["projectEditorPreview"].label, "Preview, selected clip 9")
        XCTAssertLessThan(app.buttons["editorClip-8"].frame.minX, last.frame.minX)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        removeProjects(in: app)
    }

    /// Production-equivalent presentation (`-uiTestProductionTimeline` = Release, no staged Add
    /// visual): the timeline starts at the dock's leading inset — no dead button, no empty slot.
    @MainActor
    func testEditorTimelineProductionHasNoLeadingAddSlot() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestOpenEditor", "-uiTestProductionTimeline"])
        app.launch()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        let dock = app.otherElements["editorDock"]
        let clip1 = app.buttons["editorClip-1"]
        XCTAssertTrue(app.buttons["editorClip-3"].waitForExistence(timeout: 2))
        expectLabel(clip1, "Clip 1 of 3, 2.0s")
        XCTAssertEqual(clip1.frame.minX - dock.frame.minX, 10, accuracy: 4, "first clip sits at the dock's leading inset")
        XCTAssertEqual(clip1.frame.width, 44, accuracy: 3)
        XCTAssertEqual(dock.frame.height, 100, accuracy: 6, "dock geometry unchanged")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add'")).count, 0, "no dead Add control")
        XCTAssertEqual(clip1.value as? String, "Selected")
        try auditAndCapture(app, name: "editor-timeline-v4-production-no-add-slot")

        // Many-clip scrolling is unaffected by the missing slot.
        app.terminate()
        let many = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestOpenEditor", "-uiTestProductionTimeline", "-uiTestSeedEditorClips=9"])
        many.launch()
        XCTAssertTrue(many.buttons["editorClip-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(many.buttons["editorClip-1"].frame.minX - many.otherElements["editorDock"].frame.minX, 10, accuracy: 4)
        let last = many.buttons["editorClip-9"]
        var attempts = 0
        while !(last.exists && last.isHittable), attempts < 4 { many.buttons["editorClip-3"].swipeLeft(); attempts += 1 }
        XCTAssertTrue(last.isHittable)
        last.tap()
        XCTAssertEqual(last.value as? String, "Selected")

        many.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(many.otherElements["cameraShell"].waitForExistence(timeout: 5))
        removeProjects(in: many)
    }

    /// The timeline stays a stable control surface at the largest accessibility size; audited.
    @MainActor
    func testEditorTimelineUsableUnderDynamicType() throws {
        let app = legacyRecentApp([
            "-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestOpenEditor",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        app.launch()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        let clip1 = app.buttons["editorClip-1"], clip2 = app.buttons["editorClip-2"], clip3 = app.buttons["editorClip-3"]
        XCTAssertTrue(clip3.waitForExistence(timeout: 2))
        expectLabel(clip1, "Clip 1 of 3, 2.0s")
        XCTAssertTrue(clip1.isHittable)
        XCTAssertTrue(clip2.isHittable)
        XCTAssertGreaterThanOrEqual(clip1.frame.height, 44)
        XCTAssertGreaterThanOrEqual(clip1.frame.width, 44)
        XCTAssertLessThan(clip1.frame.minX, clip2.frame.minX)
        clip3.tap()
        XCTAssertEqual(clip3.value as? String, "Selected")
        XCTAssertTrue(app.staticTexts["projectTotalDuration"].exists)
        try auditAndCapture(app, name: "editor-timeline-v4-xxxl")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        removeProjects(in: app)
    }

    // MARK: - Phase 5 STEP 9: long-press drag reorder + autosave

    /// A B C → long-press C, drag before A, release → C A B; selection follows C; Total unchanged;
    /// the order survives leaving the Editor, relaunching the process and reopening the store.
    @MainActor
    func testEditorLongPressDragReordersAndPersists() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestOpenEditor", "-uiTestProductionTimeline"])
        app.launch()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        let clip1 = app.buttons["editorClip-1"], clip2 = app.buttons["editorClip-2"], clip3 = app.buttons["editorClip-3"]
        XCTAssertTrue(clip3.waitForExistence(timeout: 2))
        expectLabel(clip1, "Clip 1 of 3, 2.0s")
        expectLabel(clip3, "Clip 3 of 3, 1.0s")
        XCTAssertEqual(app.staticTexts["projectTotalDuration"].label, "Total duration 6.0s")
        try auditAndCapture(app, name: "editor-reorder-idle")

        // A short tap only selects — it never lifts or moves a clip.
        clip2.tap()
        XCTAssertEqual(clip2.value as? String, "Selected")
        expectLabel(clip2, "Clip 2 of 3, 3.0s")

        // Long press C, drag it left past A's leading edge, release.
        let target = clip1.coordinate(withNormalizedOffset: CGVector(dx: -0.1, dy: 0.5))
        clip3.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.7, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)

        expectLabel(clip1, "Clip 1 of 3, 1.0s")
        expectLabel(clip2, "Clip 2 of 3, 2.0s")
        expectLabel(clip3, "Clip 3 of 3, 3.0s")
        XCTAssertEqual(clip1.value as? String, "Selected", "selection follows the dragged clip")
        XCTAssertEqual(clip2.value as? String, "Not selected")
        XCTAssertEqual(app.otherElements["projectEditorPreview"].label, "Preview, selected clip 1")
        XCTAssertEqual(app.staticTexts["projectTotalDuration"].label, "Total duration 6.0s", "reorder never changes the total")
        // Exact V4.1 geometry after the drop: no lingering lift.
        XCTAssertEqual(clip1.frame.width, 44, accuracy: 3)
        XCTAssertEqual(clip1.frame.height, 78, accuracy: 3)
        XCTAssertLessThan(clip1.frame.minX, clip2.frame.minX)
        XCTAssertLessThan(clip2.frame.minX, clip3.frame.minX)
        try auditAndCapture(app, name: "editor-reorder-after-drop")

        // Leave and reopen the Editor in the same process (Load Existing Project).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        app.terminate()

        // Relaunch without reseeding: the persisted order is what the store reopened with.
        let relaunched = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestReopenEditorProject", "-uiTestProductionTimeline"])
        relaunched.launch()
        XCTAssertTrue(relaunched.otherElements["projectEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(relaunched.buttons["editorClip-3"].waitForExistence(timeout: 2))
        expectLabel(relaunched.buttons["editorClip-1"], "Clip 1 of 3, 1.0s")
        expectLabel(relaunched.buttons["editorClip-2"], "Clip 2 of 3, 2.0s")
        expectLabel(relaunched.buttons["editorClip-3"], "Clip 3 of 3, 3.0s")
        XCTAssertEqual(relaunched.staticTexts["projectTotalDuration"].label, "Total duration 6.0s")

        // A second reorder after reopen: drag the (now) first clip after the last one → A B C again.
        let end = relaunched.buttons["editorClip-3"].coordinate(withNormalizedOffset: CGVector(dx: 1.1, dy: 0.5))
        relaunched.buttons["editorClip-1"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.7, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        expectLabel(relaunched.buttons["editorClip-1"], "Clip 1 of 3, 2.0s")
        expectLabel(relaunched.buttons["editorClip-2"], "Clip 2 of 3, 3.0s")
        expectLabel(relaunched.buttons["editorClip-3"], "Clip 3 of 3, 1.0s")
        XCTAssertEqual(relaunched.buttons["editorClip-3"].value as? String, "Selected")

        relaunched.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(relaunched.otherElements["cameraShell"].waitForExistence(timeout: 5))
        removeProjects(in: relaunched)
    }

    /// Mid-drag presentation (deterministic DEBUG freeze, no touch): the lifted clip sits above its
    /// neighbours which have reflowed, the dock geometry is unchanged. Visual evidence only.
    @MainActor
    func testEditorReorderDraggingPresentation() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestOpenEditor", "-uiTestProductionTimeline", "-uiTestFreezeReorderDrag=3,20"])
        app.launch()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        // Clip 3 (1.0s) is lifted and previewed at position 1 (the lifted cell rides under the
        // finger and is not an accessibility element while lifted); the others have made room.
        expectLabel(app.buttons["editorClip-2"], "Clip 2 of 3, 2.0s")
        expectLabel(app.buttons["editorClip-3"], "Clip 3 of 3, 3.0s")
        XCTAssertEqual(app.buttons["editorClip-2"].value as? String, "Not selected")
        XCTAssertEqual(app.otherElements["editorDock"].frame.height, 100, accuracy: 6, "dock is stable while dragging")
        XCTAssertEqual(app.staticTexts["projectTotalDuration"].label, "Total duration 6.0s")
        capture(app, name: "editor-reorder-dragging")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        removeProjects(in: app)
    }

    /// Nine clips: drag the first clip to the trailing edge — the timeline auto-scrolls while the
    /// finger holds at the edge so a far insertion target is reachable; the order lands, selection
    /// follows the dragged clip, and the layout does not collapse.
    @MainActor
    func testEditorReorderWithManyClipsReachesFarTargetThroughEdgeScroll() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestOpenEditor", "-uiTestProductionTimeline", "-uiTestSeedEditorClips=9"])
        app.launch()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        let strip = app.descendants(matching: .any)["clipThumbnailStrip"]
        let first = app.buttons["editorClip-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 2))
        XCTAssertTrue(strip.exists)
        expectLabel(first, "Clip 1 of 9, 2.0s")
        XCTAssertEqual(app.staticTexts["projectTotalDuration"].label, "Total duration 18.0s")
        XCTAssertFalse(app.buttons["editorClip-9"].exists && app.buttons["editorClip-9"].isHittable, "the last cell starts off-screen")

        // Hold the lifted clip inside the trailing edge band long enough for auto-scroll to reach
        // the end of the timeline, then release.
        let edge = strip.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5)).withOffset(CGVector(dx: -12, dy: 0))
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.7, thenDragTo: edge, withVelocity: .slow, thenHoldForDuration: 3.0)

        // The 2.0s clip (formerly first) is now last; the former second clip leads.
        let last = app.buttons["editorClip-9"]
        XCTAssertTrue(last.waitForExistence(timeout: 3))
        expectLabel(last, "Clip 9 of 9, 2.0s")
        expectLabel(app.buttons["editorClip-8"], "Clip 8 of 9, 1.0s")
        XCTAssertEqual(last.value as? String, "Selected", "selection follows the dragged clip")
        XCTAssertEqual(app.otherElements["projectEditorPreview"].label, "Preview, selected clip 9")
        XCTAssertEqual(app.staticTexts["projectTotalDuration"].label, "Total duration 18.0s")
        XCTAssertEqual(app.otherElements["editorDock"].frame.height, 100, accuracy: 6, "no layout collapse")
        XCTAssertEqual(last.frame.height, 78, accuracy: 3)
        try auditAndCapture(app, name: "editor-reorder-many-clips")

        // Leading clip after the move is the former second (3.0s).
        var attempts = 0
        while !(first.exists && first.isHittable), attempts < 4 { app.buttons["editorClip-7"].swipeRight(); attempts += 1 }
        expectLabel(first, "Clip 1 of 9, 3.0s")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        removeProjects(in: app)
    }

    // Phase 5 STEP 5: dedicated `프로젝트` screen (ADR-035 destination, ADR-036 two-action content),
    // reached only through deterministic DEBUG routing (`Camera → .projectsEntry`). Production Camera
    // `Projects` still opens Recent Projects in this slice.
    @MainActor
    func testProjectsScreenWithoutSavedProjectDisablesLoadExisting() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestProjectsEntry"])
        app.launch()

        // A pushed NavigationStack destination: navigation title + Back, no modal sheet.
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "projectsEntry").firstMatch.exists)
        XCTAssertEqual(app.navigationBars["프로젝트"].buttons.count, 1, "standard Back only")
        XCTAssertEqual(app.sheets.count, 0)

        // Neutral placeholder visual + no-project copy above two centered choices; loading is
        // visible but unavailable without a saved Project.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "projectsEntryVisual-placeholder").firstMatch.exists)
        XCTAssertEqual(app.staticTexts["projectsEntryHeadline"].label, "아직 프로젝트가 없어요")
        XCTAssertEqual(app.staticTexts["projectsEntrySupporting"].label, "촬영한 순간들을 골라\n첫 번째 Vlog를 만들어보세요.")
        let startNew = app.buttons["startNewProject"]
        let loadExisting = app.buttons["loadExistingProject"]
        XCTAssertTrue(startNew.exists)
        XCTAssertEqual(startNew.label, "새 프로젝트 시작")
        XCTAssertTrue(startNew.isEnabled)
        XCTAssertTrue(loadExisting.exists)
        XCTAssertEqual(loadExisting.label, "기존 프로젝트 불러오기")
        XCTAssertFalse(loadExisting.isEnabled, "no saved Project → 기존 프로젝트 불러오기 disabled")
        assertNoProjectSummaryUI(in: app)
        try auditAndCapture(app, name: "Projects Screen Final No Project")

        // The intent is delivered to the DEBUG harness; no confirmation and no Project creation.
        startNew.tap()
        let intent = app.staticTexts["projectsEntryIntent"]
        XCTAssertTrue(intent.waitForExistence(timeout: 3))
        XCTAssertEqual(intent.label, "newProject-fresh")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.navigationBars["프로젝트"].exists, "harness stays on the Projects screen")

        // Back returns to the Camera root; Recent proves nothing was created.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        openProjects(in: app)
        XCTAssertTrue(app.staticTexts["emptyRecent"].waitForExistence(timeout: 3), "no Project was created")
        backToCamera(in: app)
    }

    @MainActor
    func testProjectsScreenLoadExistingOpensSavedProjectEditorDirectly() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestProjectsEntry"])
        app.launch()

        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sheets.count, 0)
        // Saved-project visual slot (placeholder fallback until the Thumbnail slice) + saved copy.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'projectsEntryVisual-'")).firstMatch.exists)
        XCTAssertEqual(app.staticTexts["projectsEntryHeadline"].label, "이어서 만들래요?")
        XCTAssertEqual(app.staticTexts["projectsEntrySupporting"].label, "마지막으로 저장한 프로젝트가 있어요.")
        let startNew = app.buttons["startNewProject"]
        let loadExisting = app.buttons["loadExistingProject"]
        XCTAssertTrue(startNew.exists)
        XCTAssertEqual(startNew.label, "새 프로젝트 시작", "plus icon is decorative")
        XCTAssertTrue(startNew.isEnabled)
        XCTAssertTrue(loadExisting.exists)
        XCTAssertEqual(loadExisting.label, "기존 프로젝트 불러오기")
        XCTAssertTrue(loadExisting.isEnabled, "saved Project → 기존 프로젝트 불러오기 enabled")
        assertNoProjectSummaryUI(in: app)
        try auditAndCapture(app, name: "Projects Screen Final Saved Project")

        // Loading pushes the exact saved (3-clip) Project Editor directly — no list or card between.
        loadExisting.tap()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["projectEditorPreview"].exists)
        XCTAssertTrue(app.buttons["editorClip-1"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["editorClip-3"].exists)
        XCTAssertFalse(app.otherElements["projectEditorUnavailable"].exists)

        // Back once → 프로젝트 (the Projects screen stayed below the Editor); Back again → Camera.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["loadExistingProject"].isEnabled)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        openProjects(in: app)
        XCTAssertEqual(projectButtons(in: app).count, 1, "loading deletes nothing")
        removeProjects(in: app)
    }

    @MainActor
    func testProjectsScreenReplacementConfirmationCancelAndConfirmDoNotMutate() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestProjectsEntry"])
        app.launch()

        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        let startNew = app.buttons["startNewProject"]
        XCTAssertTrue(startNew.exists)
        startNew.tap()

        // Camera → Projects screen → alert: a single native confirmation, no sheet underneath.
        let alert = app.alerts["새 프로젝트를 시작할까요?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.staticTexts["새 프로젝트를 만들면 마지막으로 저장한 프로젝트가 교체됩니다."].exists)
        XCTAssertTrue(alert.buttons["취소"].exists)
        XCTAssertTrue(alert.buttons["새 프로젝트 만들기"].exists)
        try auditAndCapture(app, name: "Projects Screen Final Replacement Confirmation")

        // Cancel: the confirmation closes, the Projects screen stays, nothing is delivered.
        alert.buttons["취소"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))
        XCTAssertTrue(app.navigationBars["프로젝트"].exists)
        XCTAssertTrue(app.buttons["loadExistingProject"].isEnabled, "saved Project still loadable")
        XCTAssertFalse(app.staticTexts["projectsEntryIntent"].exists)

        // Confirm: only the confirmed intent is delivered; the saved Project is untouched.
        startNew.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["새 프로젝트 만들기"].tap()
        let intent = app.staticTexts["projectsEntryIntent"]
        XCTAssertTrue(intent.waitForExistence(timeout: 3))
        XCTAssertTrue(intent.label.hasPrefix("newProject-replace-"), "intent names the Project it would replace")
        XCTAssertTrue(app.navigationBars["프로젝트"].exists)
        XCTAssertTrue(app.buttons["loadExistingProject"].isEnabled, "saved Project still loadable after confirm")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        openProjects(in: app)
        XCTAssertEqual(projectButtons(in: app).count, 1, "no replacement, no creation in STEP 5")
        removeProjects(in: app)
    }

    // MARK: - Phase 5 STEP 7: production Camera → 프로젝트 routing (no DEBUG routing arguments)

    @MainActor
    func testCameraProjectsControlOpensCanonicalProjectsScreenWithoutCreatingProject() throws {
        let app = cameraTestApp(["-uiTestSkipOnboarding", "-uiTestProjectsEntry"])
        app.launch() // clears the shared store, then we leave the DEBUG-pushed screen
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        app.terminate()

        let normal = cameraTestApp(["-uiTestSkipOnboarding"])
        normal.launch()
        XCTAssertTrue(normal.otherElements["cameraShell"].waitForExistence(timeout: 5))
        XCTAssertFalse(normal.navigationBars["프로젝트"].exists, "launch never pushes Projects by itself")

        // Normal Projects control → canonical 프로젝트 screen, never the transitional Recent browser.
        normal.buttons["projects"].tap()
        XCTAssertTrue(normal.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        XCTAssertFalse(normal.navigationBars["Recent Projects"].exists)
        XCTAssertEqual(normal.staticTexts["projectsEntryHeadline"].label, "아직 프로젝트가 없어요")
        XCTAssertTrue(normal.buttons["startNewProject"].isEnabled)
        XCTAssertFalse(normal.buttons["loadExistingProject"].isEnabled)
        try auditAndCapture(normal, name: "Production Projects Entry")

        // Back → the same Camera; opening Projects again still shows no Project (nothing was created).
        normal.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(normal.otherElements["cameraShell"].waitForExistence(timeout: 5))
        normal.buttons["projects"].tap()
        XCTAssertTrue(normal.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        XCTAssertFalse(normal.buttons["loadExistingProject"].isEnabled, "opening Projects creates nothing")
        normal.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(normal.otherElements["cameraShell"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCameraProjectsControlLoadsSavedProjectAndBackChainIsStable() throws {
        // Seeded saved Project, then the normal (non-DEBUG-routed) launch.
        let app = cameraTestApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject"])
        app.launch()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        app.buttons["projects"].tap()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["projectsEntryHeadline"].label, "이어서 만들래요?")
        XCTAssertTrue(app.buttons["loadExistingProject"].isEnabled)

        // Load Existing → exact seeded Project (3 clips); Back → 프로젝트 → Camera; saved state persists.
        app.buttons["loadExistingProject"].tap()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editorClip-3"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["loadExistingProject"].isEnabled, "saved state refreshed on return")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["cameraShutter"].exists, "same Camera root after the round trip")

        // Relaunch → Camera → Projects → still the saved state (canonical lookup, no cache).
        app.terminate()
        app.launch()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        app.buttons["projects"].tap()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["loadExistingProject"].isEnabled)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        assertPersistedProjectCountAfterRelaunch(1)
    }

    // MARK: - Phase 5 STEP 6: Select Clips composition (deterministic fake selection, never the real picker)

    @MainActor
    func testSelectClipsFreshSuccessOpensNewProjectEditor() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestProjectsEntry", "-uiTestMediaSelection=ready2"])
        app.launch()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["loadExistingProject"].isEnabled)

        app.buttons["startNewProject"].tap()
        // Two ready fixtures → one Portrait Project with two ordered clips, opened directly.
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["editorClip-1"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["editorClip-2"].exists)
        XCTAssertFalse(app.buttons["editorClip-3"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        // Back → 프로젝트, where the new Project is now loadable; Back → Camera; exactly one Project exists.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["loadExistingProject"].isEnabled)
        XCTAssertEqual(app.staticTexts["projectsEntryHeadline"].label, "이어서 만들래요?")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        // The committed Project survives a relaunch (transitional Recent reflects persisted state).
        assertPersistedProjectCountAfterRelaunch(1)
    }

    @MainActor
    func testSelectClipsCancelStaysOnProjectsWithoutProject() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestProjectsEntry", "-uiTestMediaSelection=cancel"])
        app.launch()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        app.buttons["startNewProject"].tap()
        XCTAssertTrue(app.staticTexts["projectsEntryIntent"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 1), "cancel is silent")
        XCTAssertTrue(app.navigationBars["프로젝트"].exists)
        XCTAssertFalse(app.buttons["loadExistingProject"].isEnabled, "still no saved Project")
        XCTAssertTrue(app.buttons["startNewProject"].isEnabled, "retry possible")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        openProjects(in: app)
        XCTAssertTrue(app.staticTexts["emptyRecent"].waitForExistence(timeout: 3))
        backToCamera(in: app)
    }

    @MainActor
    func testSelectClipsRequiresPreparationShowsMessageWithoutProject() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestProjectsEntry", "-uiTestMediaSelection=tooLong"])
        app.launch()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        app.buttons["startNewProject"].tap()

        let alert = app.alerts["영상이 너무 길어요"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20))
        XCTAssertTrue(alert.staticTexts["현재는 5초 이하의 영상을 프로젝트에 추가할 수 있어요."].exists)
        try auditAndCapture(app, name: "Select Clips Requires Preparation")
        alert.buttons["확인"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))
        XCTAssertTrue(app.navigationBars["프로젝트"].exists)
        XCTAssertTrue(app.buttons["startNewProject"].isEnabled, "retry possible")
        XCTAssertFalse(app.buttons["loadExistingProject"].isEnabled, "no Project created")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        openProjects(in: app)
        XCTAssertTrue(app.staticTexts["emptyRecent"].waitForExistence(timeout: 3))
        backToCamera(in: app)
    }

    @MainActor
    func testSelectClipsReplacementCancelKeepsProjectALoadable() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestProjectsEntry", "-uiTestMediaSelection=cancel"])
        app.launch()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        app.buttons["startNewProject"].tap()
        let confirm = app.alerts["새 프로젝트를 시작할까요?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.buttons["새 프로젝트 만들기"].tap()
        // The (fake) picker is cancelled after the confirmation: A stays and stays loadable.
        XCTAssertTrue(app.staticTexts["projectsEntryIntent"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["loadExistingProject"].isEnabled)
        app.buttons["loadExistingProject"].tap()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editorClip-3"].waitForExistence(timeout: 2), "A (3 clips) opens unchanged")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        openProjects(in: app)
        XCTAssertEqual(projectButtons(in: app).count, 1)
        removeProjects(in: app)
    }

    @MainActor
    func testSelectClipsReplacementSuccessPromotesBAndRetiresA() throws {
        let app = legacyRecentApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestProjectsEntry", "-uiTestMediaSelection=ready"])
        app.launch()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 5))
        app.buttons["startNewProject"].tap()
        let confirm = app.alerts["새 프로젝트를 시작할까요?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.buttons["새 프로젝트 만들기"].tap()

        // B (one clip) is committed and opened; A (three clips) is no longer the saved Project.
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["editorClip-1"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["editorClip-2"].exists)
        XCTAssertFalse(app.buttons["editorClip-3"].exists, "this is B, not A")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 3))
        app.buttons["loadExistingProject"].tap()
        XCTAssertTrue(app.otherElements["projectEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editorClip-1"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["editorClip-3"].exists, "Load Existing now opens B")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["프로젝트"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        // Exactly one saved Project persists: A was retired only after B was committed.
        assertPersistedProjectCountAfterRelaunch(1)
    }

    /// Relaunches without any seeding / clearing argument and counts what the persisted store holds,
    /// then removes it so the shared container stays clean for other tests.
    @MainActor
    private func assertPersistedProjectCountAfterRelaunch(_ expected: Int) {
        let app = legacyRecentApp(["-uiTestSkipOnboarding"])
        app.launch()
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
        openProjects(in: app)
        XCTAssertEqual(projectButtons(in: app).count, expected)
        removeProjects(in: app)
    }

    /// ADR-036: the Projects screen carries no list, card or Project metadata.
    @MainActor
    private func assertNoProjectSummaryUI(in app: XCUIApplication) {
        for text in ["최근 프로젝트", "마지막 프로젝트", "이어서 편집"] {
            XCTAssertFalse(app.staticTexts[text].exists, "\(text) must not appear on the Projects screen")
        }
        XCTAssertFalse(app.buttons["recentProjectCard"].exists)
        XCTAssertFalse(app.buttons["continueEditing"].exists)
        let metadata = NSPredicate(format: "label CONTAINS '클립' OR label CONTAINS '초' OR label MATCHES '.*[0-9]+월 [0-9]+일.*'")
        XCTAssertEqual(app.staticTexts.matching(metadata).count, 0, "no date / clip count / duration on the Projects screen")
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

    @MainActor
    func testPermissionRowGeometryStableAcrossStateChange() throws {
        let app = cameraTestApp(["-cameraNotDetermined", "-micNotDetermined", "-photosAddNotDetermined", "-uiTestResetOnboarding"])
        app.launch()
        XCTAssertTrue(app.staticTexts["permissionOnboardingTitle"].waitForExistence(timeout: 3))

        func height(_ identifier: String) -> CGFloat { app.otherElements[identifier].frame.height }
        func settle() { Thread.sleep(forTimeInterval: 0.6) }

        // Camera row height in the unresolved (Allow) state.
        let cameraRow = app.otherElements["permissionRow-camera"]
        XCTAssertTrue(cameraRow.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["permissionAllow-camera"].exists)
        settle()
        let cameraBefore = height("permissionRow-camera")
        let cameraWidthBefore = cameraRow.frame.width

        // Resolve Camera → it flips to "Allowed" and the Microphone row is revealed. Both samples are
        // taken in the same in-flow regime (a later row still unresolved), so the comparison isolates
        // the authorization state change from the one-off layout shift that happens when the whole
        // sequence finally completes and Start Mellow appears.
        app.buttons["permissionAllow-camera"].tap()
        XCTAssertTrue(app.buttons["permissionAllow-microphone"].waitForExistence(timeout: 3))
        settle()
        let cameraAfter = height("permissionRow-camera")
        XCTAssertEqual(cameraAfter, cameraBefore, accuracy: 0.5, "Camera card height changed on Allow → Allowed")
        XCTAssertEqual(app.otherElements["permissionRow-camera"].frame.width, cameraWidthBefore, accuracy: 0.5)

        // "Allowed" shares the title's top row: same vertical band as the title, and one subheadline
        // line (never the "Al-/lowed" vertical wrap).
        let resolvedRow = app.otherElements["permissionRow-camera"]
        let cameraTitle = resolvedRow.staticTexts["Camera"]
        let cameraState = resolvedRow.descendants(matching: .any)["permissionState-camera"].firstMatch
        XCTAssertTrue(cameraState.waitForExistence(timeout: 2))
        XCTAssertEqual(cameraState.frame.midY, cameraTitle.frame.midY, accuracy: 6,
                       "Allowed status is not on the title's top row")
        XCTAssertLessThan(cameraState.frame.height, 30, "Allowed wrapped to more than one line")
        // Purpose keeps its own line below at full column width.
        XCTAssertTrue(resolvedRow.staticTexts["Capture your moments"].exists)

        // Microphone: unresolved vs resolved, both in the same in-flow regime.
        let micBefore = height("permissionRow-microphone")
        app.buttons["permissionAllow-microphone"].tap()
        XCTAssertTrue(app.buttons["permissionAllow-photos"].waitForExistence(timeout: 3))
        settle()
        let micAfter = height("permissionRow-microphone")
        XCTAssertEqual(micAfter, micBefore, accuracy: 0.5, "Microphone card height changed on resolve")

        // The three unresolved rows all share one height, so state does not vary geometry per row.
        let photosBefore = height("permissionRow-photos")
        XCTAssertEqual(micBefore, cameraBefore, accuracy: 0.5, "unresolved rows differ in height")
        XCTAssertEqual(photosBefore, cameraBefore, accuracy: 0.5, "unresolved rows differ in height")

        // Resolve the last permission and let the completed layout settle.
        app.buttons["permissionAllow-photos"].tap()
        XCTAssertTrue(app.buttons["startMellow"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1.0)

        // All three resolved rows share one compact resting height, and resolving never made a card
        // taller than its unresolved state — the exact defect under review.
        let cameraResolved = height("permissionRow-camera")
        let micResolved = height("permissionRow-microphone")
        let photosResolved = height("permissionRow-photos")
        XCTAssertEqual(cameraResolved, micResolved, accuracy: 0.5, "resolved rows differ in height")
        XCTAssertEqual(micResolved, photosResolved, accuracy: 0.5, "resolved rows differ in height")
        XCTAssertLessThanOrEqual(photosResolved, cameraBefore + 0.5, "resolved card grew taller than unresolved")
        try auditAndCapture(app, name: "Onboarding Resolved Rows")
    }

    @MainActor
    func testPermissionRowsRemainValidAtAccessibilitySize() throws {
        let app = cameraTestApp([
            "-cameraNotDetermined", "-micNotDetermined", "-photosAddNotDetermined", "-uiTestResetOnboarding",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        app.launch()
        XCTAssertTrue(app.staticTexts["permissionOnboardingTitle"].waitForExistence(timeout: 3))

        // At the largest accessibility size the row may grow and wrap, but it must stay laid out,
        // operable, and free of clipping — the Allow control and title remain within the card.
        let cameraRow = app.otherElements["permissionRow-camera"]
        XCTAssertTrue(cameraRow.waitForExistence(timeout: 2))
        let allow = app.buttons["permissionAllow-camera"]
        XCTAssertTrue(allow.isHittable)
        XCTAssertTrue(cameraRow.frame.contains(allow.frame.origin), "Allow control clipped out of the card")

        // Resolving still reveals the next row and surfaces an accessible status.
        allow.tap()
        XCTAssertTrue(app.buttons["permissionAllow-microphone"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["permissionState-camera"].firstMatch.exists)
        try auditAndCapture(app, name: "Onboarding Accessibility Size")
    }

    // MARK: - Recording (Phase 4)

    @MainActor
    func testShutterRecordsStopsAndResetsToIdle() throws {
        let app = legacyRecentApp()
        launchToCamera(app)
        waitUntilRecordReady(app)
        waitUntilRecordReady(app)
        let shutter = app.buttons["cameraShutter"]
        XCTAssertEqual(shutter.label, "Record", "idle shutter")
        XCTAssertTrue(shutter.isEnabled)
        XCTAssertFalse(app.buttons["microphoneMuted"].exists, "authorized microphone shows no muted control")

        shutter.tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Stop recording'"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 3), .completed)
        // Controls are locked while the clip is in flight; the shutter stays the Stop action.
        XCTAssertFalse(app.otherElements["durationPicker"].isEnabled)
        XCTAssertFalse(app.buttons["cameraSwitch"].isEnabled)
        XCTAssertFalse(app.buttons["projects"].isEnabled)
        XCTAssertTrue(shutter.isEnabled)
        // Disabled controls dim to 0.35 while recording (standard iOS); that legitimately trips
        // the contrast audit, so capture without it. Idle-state contrast is audited elsewhere.
        capture(app, name: "Recording Ring")

        sleep(2) // past the 1s minimum, under the 3s default maximum
        shutter.tap()
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Record'"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 5), .completed, "manual stop ≥1s saves and returns to idle")
        XCTAssertFalse(app.otherElements["recordingFailure"].exists)
        XCTAssertTrue(app.otherElements["durationPicker"].isEnabled)
        XCTAssertTrue(app.buttons["cameraSwitch"].isEnabled)
        XCTAssertTrue(app.buttons["projects"].isEnabled)

        // Recording never creates a project.
        openProjects(in: app)
        XCTAssertTrue(app.staticTexts["emptyRecent"].exists, "a saved clip must not create a project")
        backToCamera(in: app)
    }

    @MainActor
    func testAutoStopAtSelectedMaximum() throws {
        let app = cameraTestApp()
        launchToCamera(app)
        let picker = app.otherElements["durationPicker"]
        tapPickerSide(picker, .left); expectDuration(picker, 2)
        waitUntilRecordReady(app)
        let shutter = app.buttons["cameraShutter"]
        shutter.tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Stop recording'"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 3), .completed)
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Record'"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 6), .completed, "pipeline maximum stops the clip without a tap")
        XCTAssertFalse(app.otherElements["recordingFailure"].exists)
    }

    @MainActor
    func testStopUnderOneSecondShowsTooShortAndDiscards() throws {
        let app = cameraTestApp(["-recordingTooShort"])
        launchToCamera(app)
        waitUntilRecordReady(app)
        let shutter = app.buttons["cameraShutter"]
        shutter.tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Stop recording'"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 3), .completed)
        sleep(1)
        shutter.tap()
        let notice = app.staticTexts["recordingNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertEqual(notice.label, "Too short — 1s minimum")
        try auditAndCapture(app, name: "Too Short Caption")
        XCTAssertEqual(shutter.label, "Record")
        XCTAssertFalse(app.otherElements["recordingFailure"].exists)
    }

    @MainActor
    func testMicrophoneDeniedShowsMutedStateAndStillRecords() throws {
        let app = cameraTestApp(["-micDenied"])
        launchToCamera(app)
        let muted = app.buttons["microphoneMuted"]
        XCTAssertTrue(muted.exists)
        XCTAssertGreaterThanOrEqual(muted.frame.width, 44)
        XCTAssertGreaterThanOrEqual(muted.frame.height, 44)
        XCTAssertLessThan(muted.frame.midX, app.frame.midX, "upper-leading")
        XCTAssertEqual(muted.value as? String, "Not allowed")
        try auditAndCapture(app, name: "Microphone Muted")

        let shutter = app.buttons["cameraShutter"]
        XCTAssertTrue(shutter.isEnabled, "microphone denial never blocks video")
        waitUntilRecordReady(app)
        shutter.tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Stop recording'"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 3), .completed)
        XCTAssertTrue(muted.exists, "muted state stays visible while recording")
        XCTAssertFalse(muted.isEnabled, "but it cannot reconfigure audio mid-clip")
        sleep(2)
        shutter.tap()
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Record'"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 5), .completed)
    }

    @MainActor
    func testMicrophoneUndeterminedTapRequestsAndClearsMutedState() throws {
        let app = cameraTestApp(["-micNotDetermined", "-uiTestSkipOnboarding"])
        launchToCamera(app)
        let muted = app.buttons["microphoneMuted"]
        XCTAssertTrue(muted.waitForExistence(timeout: 3))
        muted.tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: muted)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 3), .completed, "granting the microphone removes the muted state")
    }

    @MainActor
    func testPhotosAddDeniedBlocksSaveWithSettingsRecovery() throws {
        let app = cameraTestApp(["-photosAddDenied", "-uiTestSkipOnboarding"])
        launchToCamera(app)
        waitUntilRecordReady(app)
        app.buttons["cameraShutter"].tap()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Couldn’t save clip"].exists)
        XCTAssertEqual(app.buttons["cameraShutter"].label, "Record", "no recording started")
        try auditAndCapture(app, name: "Photos Add Denied")
        app.buttons["dismissRecordingFailure"].tap()
        XCTAssertFalse(app.buttons["dismissRecordingFailure"].exists)
    }

    @MainActor
    func testPhotosSaveFailureIsRecoverableAndNotSuccess() throws {
        let app = cameraTestApp(["-photosSaveFails"])
        launchToCamera(app)
        waitUntilRecordReady(app)
        let shutter = app.buttons["cameraShutter"]
        shutter.tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Stop recording'"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 3), .completed)
        sleep(2)
        shutter.tap()
        XCTAssertTrue(app.buttons["dismissRecordingFailure"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Couldn’t save clip"].exists)
        XCTAssertFalse(app.buttons["openSettings"].exists, "a plain save failure offers no Settings action")
        try auditAndCapture(app, name: "Photos Save Failed")
        app.buttons["dismissRecordingFailure"].tap()
        XCTAssertEqual(shutter.label, "Record")
    }

    @MainActor
    func testExistingInstallGetsCompactAdditionalPermissionsOnly() throws {
        let app = cameraTestApp(["-uiTestOnboardingV1Complete", "-micNotDetermined", "-photosAddNotDetermined"])
        app.launch()
        // Same single screen; Camera already Allowed, Microphone revealed immediately, no replay.
        XCTAssertTrue(app.buttons["permissionAllow-microphone"].waitForExistence(timeout: 3), "Camera already Allowed → Microphone revealed at load")
        XCTAssertFalse(app.buttons["permissionAllow-camera"].exists, "Camera is not re-requested")
        XCTAssertFalse(app.buttons["permissionAllow-photos"].exists, "Photos hidden before Microphone decision")
        let granted = advanceOnboarding(app)
        XCTAssertEqual(granted, ["microphone", "photos"])
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-uiTestCamera"]
        app.launch()
        XCTAssertFalse(app.staticTexts["permissionOnboardingTitle"].waitForExistence(timeout: 2), "version 2 persisted")
        XCTAssertTrue(app.otherElements["cameraShell"].exists)

        // Already-denied Phase 4 permissions are never re-prompted.
        app.terminate()
        app.launchArguments = ["-uiTestCamera", "-uiTestOnboardingV1Complete", "-micDenied", "-photosAddDenied"]
        app.launch()
        XCTAssertFalse(app.staticTexts["permissionOnboardingTitle"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["cameraShell"].exists)
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
        let app = legacyRecentApp(["-uiTestSeedPortrait"])
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
        let app = legacyRecentApp([
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

    /// Thumbnail state is part of the cell label ("…, loading" / "…, thumbnail unavailable"), so
    /// waiting for the exact label proves the asynchronous state settled.
    @MainActor
    private func expectLabel(_ element: XCUIElement, _ expected: String) {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed,
                       "label is \(element.label) instead of \(expected)")
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
        advanceOnboarding(app)
        XCTAssertTrue(app.otherElements["cameraShell"].waitForExistence(timeout: 5))
    }

    /// Single-screen onboarding: grant each revealed row in turn, then Start Mellow. Rows that are
    /// already resolved (migration) are skipped. Returns the row identifiers that were granted.
    @MainActor
    @discardableResult
    private func advanceOnboarding(_ app: XCUIApplication) -> [String] {
        guard app.staticTexts["permissionOnboardingTitle"].waitForExistence(timeout: 1) else { return [] }
        var granted: [String] = []
        for id in ["camera", "microphone", "photos"] {
            let allow = app.buttons["permissionAllow-\(id)"]
            if allow.waitForExistence(timeout: 2) {
                allow.tap()
                granted.append(id)
                let resolved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: allow)
                _ = XCTWaiter.wait(for: [resolved], timeout: 3)
            }
        }
        let start = app.buttons["startMellow"]
        if start.waitForExistence(timeout: 3) { start.tap() }
        return granted
    }

    @MainActor
    private func waitUntilRecordReady(_ app: XCUIApplication) {
        let shutter = app.buttons["cameraShutter"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND label == 'Record'"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 6), .completed, "camera did not become ready to record")
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
