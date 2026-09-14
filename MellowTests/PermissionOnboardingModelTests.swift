import XCTest
@testable import Mellow

@MainActor
final class PermissionOnboardingModelTests: XCTestCase {
    private func make(camera: CameraAuthorization = .notDetermined,
                      micStatus: MicrophoneAuthorization = .notDetermined,
                      micGrant: Bool = true,
                      photosStatus: PhotosAddAuthorization = .notDetermined,
                      photosGrant: Bool = true)
    -> (PermissionOnboardingModel, () -> Int) {
        let cam = FakeCameraCaptureService(authorization: camera)
        cam.grantOnRequest = true
        let mic = FakeMicrophoneAuthorization(authorization: micStatus); mic.grantOnRequest = micGrant
        let photos = FakePhotosLibrarySaver(authorization: photosStatus); photos.grantOnRequest = photosGrant
        var finished = 0
        let model = PermissionOnboardingModel(cameraService: cam, microphoneProvider: mic, photosSaver: photos) { finished += 1 }
        return (model, { finished })
    }

    func testFreshScreenRevealsOnlyCameraUntilEachDecision() async {
        let (m, _) = make()
        XCTAssertFalse(m.showsMicrophoneRow)
        XCTAssertFalse(m.showsPhotosRow)
        XCTAssertFalse(m.showsStart)

        await m.requestCamera()
        XCTAssertEqual(m.camera, .authorized)
        XCTAssertTrue(m.showsMicrophoneRow)
        XCTAssertFalse(m.showsPhotosRow, "Photos hidden until Microphone decided")
        XCTAssertFalse(m.showsStart)

        await m.requestMicrophone()
        XCTAssertTrue(m.showsPhotosRow)
        XCTAssertFalse(m.showsStart, "Start hidden until Photos decided")

        await m.requestPhotos()
        XCTAssertTrue(m.showsStart)
    }

    func testEachRowRequestsOnlyItsOwnPermissionAndNeverAutoAdvances() async {
        let cam = FakeCameraCaptureService(authorization: .notDetermined)
        let mic = FakeMicrophoneAuthorization(authorization: .notDetermined)
        let photos = FakePhotosLibrarySaver(authorization: .notDetermined)
        let model = PermissionOnboardingModel(cameraService: cam, microphoneProvider: mic, photosSaver: photos) {}
        await model.requestCamera()
        XCTAssertTrue(cam.calls.contains("authorize"))
        XCTAssertEqual(mic.requestCount, 0, "Camera request must not touch Microphone")
        XCTAssertEqual(photos.requestCount, 0, "Camera request must not touch Photos")
        await model.requestMicrophone()
        XCTAssertEqual(mic.requestCount, 1)
        XCTAssertEqual(photos.requestCount, 0)
        await model.requestPhotos()
        XCTAssertEqual(photos.requestCount, 1)
    }

    func testMicrophoneDeniedRevealsPhotosAndStillReachesStart() async {
        let (m, _) = make(micGrant: false)
        await m.requestCamera()
        await m.requestMicrophone()
        XCTAssertEqual(m.microphone, .denied)
        XCTAssertTrue(m.showsPhotosRow, "denial still resolves the row")
        await m.requestPhotos()
        XCTAssertTrue(m.showsStart, "Microphone denial does not block Start Mellow")
    }

    func testDeniedPermissionsAreNotRePrompted() async {
        let mic = FakeMicrophoneAuthorization(authorization: .denied)
        let photos = FakePhotosLibrarySaver(authorization: .denied)
        let cam = FakeCameraCaptureService(authorization: .denied)
        let model = PermissionOnboardingModel(cameraService: cam, microphoneProvider: mic, photosSaver: photos) {}
        await model.requestCamera()
        await model.requestMicrophone()
        await model.requestPhotos()
        XCTAssertEqual(mic.requestCount, 0, "denied is not re-requested")
        XCTAssertEqual(photos.requestCount, 0)
        XCTAssertTrue(model.showsStart, "all decided (denied) → Start available")
    }

    func testMigrationWithCameraAlreadyAuthorizedRevealsMicrophoneImmediately() async {
        let (m, _) = make(camera: .authorized)
        XCTAssertEqual(m.camera, .authorized)
        XCTAssertTrue(m.cameraResolved)
        XCTAssertTrue(m.showsMicrophoneRow, "already-authorized Camera reveals Microphone at load")
        XCTAssertFalse(m.showsPhotosRow)
    }

    func testPreAuthorizedLaterPermissionsDoNotRevealAheadOfCamera() async {
        // Regression: a pre-authorized Microphone/Photos must not surface Photos or Start while
        // Camera is still undecided. The chain reveals strictly in order.
        let (m, _) = make(micStatus: .authorized, photosStatus: .authorized)
        XCTAssertFalse(m.showsMicrophoneRow, "Camera undecided → nothing past it")
        XCTAssertFalse(m.showsPhotosRow)
        XCTAssertFalse(m.showsStart)
        await m.requestCamera()
        // Now Camera is resolved; the already-authorized rows cascade into view together.
        XCTAssertTrue(m.showsMicrophoneRow)
        XCTAssertTrue(m.showsPhotosRow)
        XCTAssertTrue(m.showsStart)
    }

    func testStartOnlyFiresWhenAllResolved() async {
        let (m, finishedCount) = make()
        m.start()
        XCTAssertEqual(finishedCount(), 0, "Start does nothing before Photos is decided")
        await m.requestCamera(); await m.requestMicrophone(); await m.requestPhotos()
        m.start()
        XCTAssertEqual(finishedCount(), 1, "Start Mellow leaves onboarding exactly once")
    }
}
