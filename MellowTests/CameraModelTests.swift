import XCTest
@testable import Mellow

@MainActor
final class CameraModelTests: XCTestCase {
    private func make(_ service: FakeCameraCaptureService? = nil,
                      project: ProjectOrientation = .portrait9x16,
                      posture: CameraDeviceOrientation = .portrait) -> (CameraModel, FakeCameraOrientationSource) {
        let source = FakeCameraOrientationSource(posture)
        let camera = service ?? FakeCameraCaptureService()
        let recording = RecordingCoordinator(
            service: camera,
            staging: RecordingStagingStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("CameraModelTests-\(UUID().uuidString)")),
            photos: FakePhotosLibrarySaver(),
            inspector: FakeRecordingMediaInspector(),
            haptics: FakeCompletionHaptic(),
            backgroundTasks: ImmediateBackgroundTaskRunner()
        )
        let model = CameraModel(projectOrientation: project, service: camera, orientation: source,
                                recording: recording, microphone: FakeMicrophoneAuthorization())
        return (model, source)
    }

    func testAuthorizationStatesAndOrdering() async {
        for authorization in CameraAuthorization.allCases {
            let service = FakeCameraCaptureService(authorization: authorization)
            let (model, _) = make(service)
            model.enter(active: true)
            await model.waitForLifecycle()
            if authorization == .denied || authorization == .restricted {
                XCTAssertEqual(model.readiness, authorization == .denied ? .denied : .restricted)
                XCTAssertEqual(service.calls, ["authorize", "stop"])
                XCTAssertFalse(model.canFlip)
            } else {
                XCTAssertEqual(service.calls, ["authorize", "prepare", "audioOn", "start"])
                XCTAssertEqual(model.readiness, .ready)
            }
            model.leave(); await model.waitForLifecycle()
        }
    }
    func testPendingPermissionDoesNotConfigureBeforeActualResult() async {
        let service = FakeCameraCaptureService(authorization: .notDetermined)
        service.authorizationSuspended = true
        let (model, _) = make(service)
        model.enter(active: true)
        for _ in 0..<20 where service.calls.isEmpty { await Task.yield() }
        XCTAssertEqual(model.readiness, .permissionPending)
        XCTAssertEqual(service.calls, ["authorize"])
        service.completeAuthorization(.authorized)
        await model.waitForLifecycle()
        XCTAssertEqual(service.calls, ["authorize", "prepare", "audioOn", "start"])
        XCTAssertEqual(model.readiness, .ready)
        model.leave(); await model.waitForLifecycle()
    }
    func testLeavingDuringPermissionDoesNotStartCamera() async {
        let service = FakeCameraCaptureService(authorization: .notDetermined)
        service.authorizationSuspended = true
        let (model, _) = make(service)
        model.enter(active: true)
        for _ in 0..<20 where service.calls.isEmpty { await Task.yield() }
        model.leave()
        service.completeAuthorization(.authorized)
        await model.waitForLifecycle()
        XCTAssertFalse(service.calls.contains("prepare"))
        XCTAssertFalse(service.calls.contains("start"))
        XCTAssertEqual(model.readiness, .inactive)
    }
    func testSessionStartsOnlyWhenActive() async {
        let service = FakeCameraCaptureService(authorization: .authorized)
        let (model, _) = make(service)
        model.enter(active: false)
        await model.waitForLifecycle()
        XCTAssertEqual(service.calls, ["stop"])
        XCTAssertEqual(model.readiness, .inactive)
        model.setActive(true)
        await model.waitForLifecycle()
        XCTAssertEqual(service.calls, ["stop", "authorize", "prepare", "audioOn", "start"])
        XCTAssertEqual(model.readiness, .ready)
        model.setActive(false)
        await model.waitForLifecycle()
        XCTAssertEqual(service.calls.last, "stop")
        model.leave()
        await model.waitForLifecycle()
    }
    func testDeniedPermissionResult() async {
        let service = FakeCameraCaptureService(authorization: .notDetermined)
        service.grantOnRequest = false
        let (model, _) = make(service)
        model.enter(active: true); await model.waitForLifecycle()
        XCTAssertEqual(model.readiness, .denied)
        XCTAssertEqual(service.calls, ["authorize", "stop"])
        model.leave(); await model.waitForLifecycle()
    }
    func testFailureCannotBeOverwrittenByOrientation() async {
        let service = FakeCameraCaptureService()
        service.preparationFailure = .configurationFailed
        let (model, source) = make(service)
        model.enter(active: true); await model.waitForLifecycle()
        source.send(.landscapeLeft); source.send(.portrait)
        XCTAssertEqual(model.readiness, .failed(.configurationFailed))
        XCTAssertFalse(service.calls.contains("start"))
        service.preparationFailure = nil
        model.retry(); await model.waitForLifecycle()
        XCTAssertEqual(model.readiness, .ready)
        service.fail(.runtimeFailure)
        source.send(.portrait)
        XCTAssertEqual(model.readiness, .failed(.runtimeFailure))
        model.leave(); await model.waitForLifecycle()
    }
    func testWideCameraRequirementAndDiscoveredFlipCapability() async {
        let service = FakeCameraCaptureService()
        service.rearWideAvailable = false
        let (model, _) = make(service)
        XCTAssertFalse(model.canFlip)
        model.enter(active: true); await model.waitForLifecycle()
        XCTAssertEqual(model.readiness, .unavailable)
        XCTAssertNil(model.sessionState.deviceKind)
        service.rearWideAvailable = true
        service.frontAvailable = false
        model.retry(); await model.waitForLifecycle()
        XCTAssertEqual(model.sessionState.deviceKind, .wideAngle)
        XCTAssertFalse(model.canFlip)
        await model.flip()
        XCTAssertFalse(service.calls.contains("switch"))
        model.leave(); await model.waitForLifecycle()
    }
    func testDefinitePosturesDecideReadinessAndProjectStaysImmutable() async {
        for project in ProjectOrientation.allCases {
            let (model, source) = make(project: project)
            model.enter(active: true); await model.waitForLifecycle()
            for posture in CameraDeviceOrientation.allCases where posture.isDefinite {
                source.send(posture)
                let eligible = project == .portrait9x16 ? posture == .portrait : [.landscapeLeft, .landscapeRight].contains(posture)
                XCTAssertEqual(model.readiness, eligible ? .ready : .mismatch, "\(project) \(posture)")
                XCTAssertEqual(model.capturePosture, posture)
                XCTAssertEqual(model.projectOrientation, project)
            }
            model.leave(); await model.waitForLifecycle()
        }
    }
    func testInitialUnknownPostureIsProvisionalPortraitNotAMismatch() async {
        // UIDevice reports .unknown until the first physical rotation; launching upright must not
        // demand a rotation before Portrait is recognised.
        let (portrait, _) = make(project: .portrait9x16, posture: .unknown)
        portrait.enter(active: true); await portrait.waitForLifecycle()
        XCTAssertNil(portrait.stablePosture)
        XCTAssertEqual(portrait.capturePosture, .portrait)
        XCTAssertEqual(portrait.readiness, .ready)
        portrait.leave(); await portrait.waitForLifecycle()

        // A landscape project under the same provisional posture is a genuine mismatch.
        let (landscape, _) = make(project: .landscape16x9, posture: .unknown)
        landscape.enter(active: true); await landscape.waitForLifecycle()
        XCTAssertEqual(landscape.readiness, .mismatch)
        landscape.leave(); await landscape.waitForLifecycle()
    }
    func testProvisionalPostureFollowsInterfaceOrientationUntilDeviceReports() async {
        let (model, source) = make(project: .portrait9x16, posture: .unknown)
        model.enter(active: true); await model.waitForLifecycle()
        model.updateInterface(.landscapeLeft)
        XCTAssertEqual(model.capturePosture, .landscapeRight, "interface and device landscape sides are inverted")
        XCTAssertEqual(model.readiness, .mismatch)
        model.updateInterface(.portrait)
        XCTAssertEqual(model.readiness, .ready)
        // Once the device reports a definite posture, the interface no longer stands in.
        source.send(.landscapeLeft)
        model.updateInterface(.portrait)
        XCTAssertEqual(model.readiness, .mismatch)
        model.leave(); await model.waitForLifecycle()
    }
    func testIndefinitePosturesPreserveLastStablePostureAndNeverPresentRotateOnTheirOwn() async {
        let (model, source) = make(project: .portrait9x16, posture: .portrait)
        model.enter(active: true); await model.waitForLifecycle()
        XCTAssertEqual(model.readiness, .ready)
        for posture in [CameraDeviceOrientation.unstable, .faceUp, .faceDown, .unknown] {
            source.send(posture)
            XCTAssertEqual(model.deviceOrientation, posture)
            XCTAssertEqual(model.stablePosture, .portrait)
            XCTAssertEqual(model.readiness, .ready, "\(posture) must not present Rotate your iPhone after upright Portrait")
        }
        source.send(.landscapeLeft)
        XCTAssertEqual(model.readiness, .mismatch)
        source.send(.faceUp)
        XCTAssertEqual(model.stablePosture, .landscapeLeft, "face up preserves the last definite posture")
        XCTAssertEqual(model.readiness, .mismatch)
        source.send(.portrait)
        XCTAssertEqual(model.readiness, .ready, "returning upright recovers readiness")
        model.leave(); await model.waitForLifecycle()
    }
    func testInterfaceAndPresentationAreIndependentOfPhysicalEligibility() async {
        let (model, source) = make(project: .landscape16x9, posture: .landscapeLeft)
        model.enter(active: true); await model.waitForLifecycle()
        model.updateInterface(.portrait)
        XCTAssertEqual(model.presentation.angle, 90)
        XCTAssertEqual(model.readiness, .ready)
        model.updateInterface(.landscapeRight)
        XCTAssertEqual(model.presentation.angle, 0)
        model.updateInterface(.landscapeLeft)
        XCTAssertEqual(model.presentation.angle, 180)
        model.updateInterface(.unknown)
        XCTAssertEqual(model.presentation.angle, 180)
        source.send(.faceDown)
        // Face down keeps the last definite landscape posture; presentation is untouched either way.
        XCTAssertEqual(model.readiness, .ready)
        XCTAssertEqual(model.presentation.angle, 180)
        source.send(.portrait)
        XCTAssertEqual(model.readiness, .mismatch)
        XCTAssertEqual(model.presentation.angle, 180)
        model.leave(); await model.waitForLifecycle()
    }
    func testBackgroundForegroundLeavingAndReentry() async {
        let service = FakeCameraCaptureService()
        let (model, _) = make(service)
        model.enter(active: true); await model.waitForLifecycle()
        XCTAssertTrue(service.state.isRunning)
        await model.flip()
        await model.zoom(to: 2)
        model.setActive(false); await model.waitForLifecycle()
        XCTAssertFalse(service.state.isRunning)
        XCTAssertEqual(model.readiness, .inactive)
        model.setActive(true); await model.waitForLifecycle()
        XCTAssertEqual(model.readiness, .ready)
        XCTAssertEqual(model.sessionState.position, .front)
        XCTAssertTrue(model.presentation.mirrored)
        model.leave(); await model.waitForLifecycle()
        model.setActive(true); await model.waitForLifecycle()
        XCTAssertFalse(service.state.isRunning)
        model.enter(active: true); await model.waitForLifecycle()
        XCTAssertEqual(model.readiness, .ready)
        model.leave(); await model.waitForLifecycle()
    }
    func testInterruptionRecoveryHonorsVisibility() async {
        let service = FakeCameraCaptureService()
        let (model, _) = make(service)
        model.enter(active: true); await model.waitForLifecycle()
        service.interrupt()
        XCTAssertEqual(model.readiness, .interrupted)
        XCTAssertFalse(model.canFlip)
        service.endInterruption()
        XCTAssertEqual(model.readiness, .ready)
        service.interrupt()
        model.leave(); await model.waitForLifecycle()
        service.endInterruption()
        XCTAssertFalse(service.state.isRunning)
        XCTAssertEqual(model.readiness, .inactive)
    }
    func testSwitchMirroringAndZoomClamp() async {
        let service = FakeCameraCaptureService()
        let (model, _) = make(service)
        model.enter(active: true); await model.waitForLifecycle()
        XCTAssertTrue(model.canFlip)
        XCTAssertFalse(model.presentation.mirrored)
        await model.zoom(to: 8)
        XCTAssertEqual(model.sessionState.zoom, 2)
        await model.zoom(to: 0.1)
        XCTAssertEqual(model.sessionState.zoom, 1)
        await model.zoom(to: 1.4)
        XCTAssertEqual(model.sessionState.zoom, 1.4)
        await model.flip()
        XCTAssertEqual(model.sessionState.position, .front)
        XCTAssertTrue(model.presentation.mirrored)
        XCTAssertFalse(model.canZoom)
        await model.zoom(to: 2)
        XCTAssertEqual(model.sessionState.zoom, 1)
        await model.flip()
        XCTAssertFalse(model.presentation.mirrored)
        XCTAssertEqual(model.projectOrientation, .portrait9x16)
        XCTAssertEqual(CameraZoomPolicy.clamp(.nan), 1)
        model.leave(); await model.waitForLifecycle()
    }
    func testDurationPickerStepsOneSecondAndClampsToRange() {
        XCTAssertEqual(CameraDuration.three.advanced(by: 1), .four)
        XCTAssertEqual(CameraDuration.three.advanced(by: -1), .two)
        XCTAssertEqual(CameraDuration.five.advanced(by: 1), .five, "upper clamp")
        XCTAssertEqual(CameraDuration.one.advanced(by: -1), .one, "lower clamp")
        XCTAssertEqual(CameraDuration.one.advanced(by: 9), .five)
        XCTAssertEqual(CameraDuration.five.advanced(by: -9), .one)
        XCTAssertEqual(CameraDuration.four.advanced(by: 0), .four)
    }
    func testDurationPickerWindowKeepsSelectionCentred() {
        XCTAssertEqual(CameraDuration.three.visibleWindow, [.two, .three, .four], "default 2s [3s] 4s")
        XCTAssertEqual(CameraDuration.two.visibleWindow, [.one, .two, .three])
        XCTAssertEqual(CameraDuration.four.visibleWindow, [.three, .four, .five])
        XCTAssertEqual(CameraDuration.one.visibleWindow, [nil, .one, .two], "1s sits centred with no left neighbour")
        XCTAssertEqual(CameraDuration.five.visibleWindow, [.four, .five, nil])
        for duration in CameraDuration.allCases { XCTAssertEqual(duration.visibleWindow[1], duration) }
        XCTAssertEqual(CameraDuration.one.accessibilityValueText, "1 second")
        XCTAssertEqual(CameraDuration.three.accessibilityValueText, "3 seconds")
    }
    func testDurationSelectionIsFeatureStateOnly() {
        let service = FakeCameraCaptureService()
        let (model, _) = make(service)
        XCTAssertEqual(model.selectedDuration, .three)
        for duration in CameraDuration.allCases { model.selectedDuration = duration; XCTAssertEqual(model.selectedDuration, duration) }
        // VoiceOver adjustment and drag snapping route through the same clamped stepping.
        model.selectedDuration = model.selectedDuration.advanced(by: 1)
        model.selectedDuration = model.selectedDuration.advanced(by: -9)
        XCTAssertEqual(model.selectedDuration, .one)
        XCTAssertTrue(service.calls.isEmpty, "duration changes must never reach the camera service")
    }
}
