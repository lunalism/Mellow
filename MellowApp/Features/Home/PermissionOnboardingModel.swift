import Foundation
import Observation

/// One-screen progressive permission onboarding (Camera → Microphone → Photos), each granted
/// individually. A permission is "resolved" once its status is anything but notDetermined; the
/// next row is revealed only then. This owns permission *presentation* — recording ownership,
/// staging and Photos-save all stay in their own services.
@MainActor
@Observable
final class PermissionOnboardingModel {
    private(set) var camera: CameraAuthorization
    private(set) var microphone: MicrophoneAuthorization
    private(set) var photos: PhotosAddAuthorization
    /// The row whose system request is currently in flight, if any.
    private(set) var requesting: Row?

    enum Row: Equatable { case camera, microphone, photos }

    @ObservationIgnored private let cameraService: any CameraCaptureService
    @ObservationIgnored private let microphoneProvider: any MicrophoneAuthorizationProviding
    @ObservationIgnored private let photosSaver: any PhotosLibrarySaving
    @ObservationIgnored private let onFinish: () -> Void

    init(
        cameraService: any CameraCaptureService,
        microphoneProvider: any MicrophoneAuthorizationProviding,
        photosSaver: any PhotosLibrarySaving,
        onFinish: @escaping () -> Void
    ) {
        self.cameraService = cameraService
        self.microphoneProvider = microphoneProvider
        self.photosSaver = photosSaver
        self.onFinish = onFinish
        camera = cameraService.authorization
        microphone = microphoneProvider.authorization
        photos = photosSaver.authorization
    }

    // A decision of any kind (allowed, denied, restricted) reveals the next row.
    var cameraResolved: Bool { camera != .notDetermined }
    var microphoneResolved: Bool { microphone != .notDetermined }
    var photosResolved: Bool { photos != .notDetermined }

    // Strict sequential reveal: a later row appears only when every earlier row is both shown and
    // resolved, so a pre-authorized permission never jumps ahead of an undecided one.
    var showsMicrophoneRow: Bool { cameraResolved }
    var showsPhotosRow: Bool { showsMicrophoneRow && microphoneResolved }
    /// Start Mellow appears only once all three have been decided. Microphone may be denied.
    var showsStart: Bool { showsPhotosRow && photosResolved }

    func requestCamera() async {
        guard camera == .notDetermined, requesting == nil else { return }
        requesting = .camera
        camera = await cameraService.resolveAuthorization()
        if camera == .authorized { await cameraService.prepare() }
        requesting = nil
    }

    func requestMicrophone() async {
        guard microphone == .notDetermined, requesting == nil else { return }
        requesting = .microphone
        microphone = await microphoneProvider.requestAccess()
        requesting = nil
    }

    func requestPhotos() async {
        guard photos == .notDetermined, requesting == nil else { return }
        requesting = .photos
        photos = await photosSaver.requestAccess()
        requesting = nil
    }

    /// Start Mellow: leaves onboarding for the Portrait Camera. Requests nothing.
    func start() {
        guard showsStart else { return }
        onFinish()
    }
}
