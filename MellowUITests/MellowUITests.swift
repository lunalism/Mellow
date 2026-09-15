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

    // Phase 5 STEP 4: existing-project Editor foundation, reached through deterministic test routing
    // (production Recent-item navigation is intentionally unchanged in this slice).
    @MainActor
    func testProjectEditorOpensSeededProjectAndSelectsClips() throws {
        let app = cameraTestApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestOpenEditor"])
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

    // Phase 5 STEP 5: dedicated `프로젝트` screen (ADR-035 destination, ADR-036 two-action content),
    // reached only through deterministic DEBUG routing (`Camera → .projectsEntry`). Production Camera
    // `Projects` still opens Recent Projects in this slice.
    @MainActor
    func testProjectsScreenWithoutSavedProjectDisablesLoadExisting() throws {
        let app = cameraTestApp(["-uiTestSkipOnboarding", "-uiTestProjectsEntry"])
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
        let app = cameraTestApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestProjectsEntry"])
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
        let app = cameraTestApp(["-uiTestSkipOnboarding", "-uiTestSeedEditorProject", "-uiTestProjectsEntry"])
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
        let app = cameraTestApp()
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
