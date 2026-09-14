import AVFoundation
import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class AppEnvironment {
    private enum PermissionOnboardingStorage {
        /// Phase 3 first-run flag (Camera only) — now "version 1 complete".
        static let key = "com.mellow.permissionOnboardingCompleted"
        /// Highest onboarding version the user has completed. Version 2 adds Microphone + Photos Add.
        static let versionKey = "com.mellow.permissionOnboardingVersion"
        static let currentVersion = 2
    }

    let router: AppRouter
    let projectRepository: any ProjectRepository
    let home: HomeModel
    let modelContainer: ModelContainer
    let cameraService: any CameraCaptureService
    let microphone: any MicrophoneAuthorizationProviding
    let photosSaver: any PhotosLibrarySaving
    let recording: RecordingCoordinator
    @ObservationIgnored private let stagingStore: any RecordingStagingStoring
    @ObservationIgnored private let mediaInspector: any RecordingMediaInspecting

    private(set) var permissionOnboardingCompleted: Bool
    /// The single-screen onboarding model, created only while onboarding is shown.
    private(set) var permissionOnboarding: PermissionOnboardingModel?
    private let arguments: [String]
    private var prewarmTask: Task<Void, Never>?

    var shouldShowPermissionOnboarding: Bool { !permissionOnboardingCompleted }

    func makeCameraModel(orientation projectOrientation: ProjectOrientation) -> CameraModel {
        #if DEBUG
        #if targetEnvironment(simulator)
        if arguments.contains("-uiTestCamera") {
            // A definite landscape posture is the only state that presents "Rotate your iPhone".
            let posture: CameraDeviceOrientation = arguments.contains("-cameraMismatch") ? .landscapeLeft :
                (projectOrientation == .portrait9x16 ? .portrait : .landscapeLeft)
            return CameraModel(
                projectOrientation: projectOrientation,
                service: cameraService,
                orientation: FakeCameraOrientationSource(posture),
                recording: recording,
                microphone: microphone
            )
        }
        #endif
        #endif
        return CameraModel(
            projectOrientation: projectOrientation,
            service: cameraService,
            orientation: DeviceCameraOrientationSource(),
            recording: recording,
            microphone: microphone
        )
    }

    /// Start Mellow: leaves onboarding for the Portrait Camera, persists completion (version 2),
    /// and kicks off prewarm + staging recovery. Requests no further permissions.
    private func finishPermissionOnboarding() {
        guard !permissionOnboardingCompleted else { return }
        permissionOnboardingCompleted = true
        permissionOnboarding = nil
        Self.persistPermissionOnboardingCompleted(true)
        UserDefaults.standard.set(PermissionOnboardingStorage.currentVersion, forKey: PermissionOnboardingStorage.versionKey)
        prewarmCameraIfNeeded()
        runStagingRecovery()
    }

    func prewarmCameraIfNeeded() {
        prewarmTask?.cancel()
        prewarmTask = Task { [weak self] in
            guard let self else { return }
            guard permissionOnboardingCompleted else { return }
            guard knownCameraAuthorization() == .authorized else { return }
            // The service gates prepare() on its own resolved authorization; syncing it first is
            // what makes prewarming effective on every later launch. Already-authorized status
            // means this resolves without presenting a system prompt.
            guard await cameraService.resolveAuthorization() == .authorized else { return }
            await cameraService.prepare()
            #if DEBUG
            MellowLog.app.info("Camera prewarm phase: \(String(describing: self.cameraService.state.phase), privacy: .public)")
            #endif
        }
    }

    init(
        router: AppRouter? = nil,
        modelContainer: ModelContainer = MellowModelContainer.shared
    ) {
        arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTestResetOnboarding") {
            UserDefaults.standard.removeObject(forKey: PermissionOnboardingStorage.key)
            UserDefaults.standard.removeObject(forKey: PermissionOnboardingStorage.versionKey)
        }
        #if DEBUG
        if arguments.contains("-uiTestOnboardingV1Complete") {
            // Simulates a Phase 3 install upgrading to Phase 4.
            UserDefaults.standard.set(true, forKey: PermissionOnboardingStorage.key)
            UserDefaults.standard.removeObject(forKey: PermissionOnboardingStorage.versionKey)
        }
        #endif

        let router = router ?? AppRouter()
        self.router = router
        self.modelContainer = modelContainer

        if arguments.contains("-uiTestCamera") {
            cameraService = Self.makeFakeCameraService(arguments: arguments)
        } else {
            cameraService = AVFoundationCameraService()
        }

        let stagingStore = RecordingStagingStore()
        self.stagingStore = stagingStore
        #if DEBUG
        let fakeMode = arguments.contains("-uiTestCamera")
        let microphone: any MicrophoneAuthorizationProviding = fakeMode
            ? Self.makeFakeMicrophone(arguments: arguments) : AVMicrophoneAuthorization()
        let photosSaver: any PhotosLibrarySaving = fakeMode
            ? Self.makeFakePhotosSaver(arguments: arguments) : PHPhotosLibrarySaver()
        let inspector: any RecordingMediaInspecting
        if fakeMode, let fakeService = cameraService as? FakeCameraCaptureService {
            let fakeInspector = FakeRecordingMediaInspector()
            fakeInspector.durationProvider = { [fakeService] in fakeService.recordedDuration }
            inspector = fakeInspector
        } else {
            inspector = AVAssetRecordingMediaInspector()
        }
        #else
        let microphone: any MicrophoneAuthorizationProviding = AVMicrophoneAuthorization()
        let photosSaver: any PhotosLibrarySaving = PHPhotosLibrarySaver()
        let inspector: any RecordingMediaInspecting = AVAssetRecordingMediaInspector()
        #endif
        self.microphone = microphone
        self.photosSaver = photosSaver
        self.mediaInspector = inspector
        recording = RecordingCoordinator(
            service: cameraService,
            staging: stagingStore,
            photos: photosSaver,
            inspector: inspector,
            haptics: UIKitCompletionHaptic(),
            backgroundTasks: UIApplicationBackgroundTaskRunner()
        )

        let persistedV1 = UserDefaults.standard.bool(forKey: PermissionOnboardingStorage.key)
        let cameraKnown = Self.knownCameraAuthorization(arguments: arguments, service: cameraService) != .notDetermined
        let skip = arguments.contains("-uiTestSkipOnboarding")
        let v1Complete = persistedV1 || cameraKnown || skip
        let persistedVersion = UserDefaults.standard.integer(forKey: PermissionOnboardingStorage.versionKey)
        let v2Complete = skip || persistedVersion >= PermissionOnboardingStorage.currentVersion

        // One progressive-reveal onboarding screen. It is shown when the user still has an
        // undecided permission relevant to this version: a fresh install (Camera undecided) or a
        // Phase 3 → Phase 4 migration where Microphone or Photos Add is still notDetermined. The
        // same screen serves both; already-authorized rows simply render "Allowed".
        let anyUndecided = cameraService.authorization == .notDetermined
            || microphone.authorization == .notDetermined
            || photosSaver.authorization == .notDetermined
        let needsOnboarding = !v2Complete && anyUndecided
        let onboardingCompleted = !needsOnboarding
        permissionOnboardingCompleted = onboardingCompleted
        if v1Complete { Self.persistPermissionOnboardingCompleted(true) }
        if onboardingCompleted {
            UserDefaults.standard.set(PermissionOnboardingStorage.currentVersion, forKey: PermissionOnboardingStorage.versionKey)
        }

        let repository = SwiftDataProjectRepository(
            modelContext: modelContainer.mainContext
        )
        self.projectRepository = repository
        self.home = HomeModel(repository: repository, router: router)

        #if DEBUG
        Self.seedUITestProjects(arguments: arguments, repository: repository)
        #endif

        MellowLog.app.info("Permission onboarding completed: \(onboardingCompleted, privacy: .public)")

        if onboardingCompleted {
            prewarmCameraIfNeeded()
            runStagingRecovery()
        } else {
            permissionOnboarding = PermissionOnboardingModel(
                cameraService: cameraService,
                microphoneProvider: microphone,
                photosSaver: photosSaver,
                onFinish: { [weak self] in self?.finishPermissionOnboarding() }
            )
        }
    }

    /// Best-effort recovery of crash-left staging clips (ADR-033); saves only when Photos
    /// actually succeeds, deletes corrupt or sub-second leftovers, retains the rest.
    private func runStagingRecovery() {
        let recovery = RecordingRecovery(staging: stagingStore, inspector: mediaInspector, photos: photosSaver)
        Task { @MainActor in
            let report = await recovery.run()
            if !report.saved.isEmpty || !report.deleted.isEmpty || !report.retained.isEmpty {
                MellowLog.app.info("Staging recovery saved=\(report.saved.count, privacy: .public) deleted=\(report.deleted.count, privacy: .public) retained=\(report.retained.count, privacy: .public)")
            }
        }
    }

    private func knownCameraAuthorization() -> CameraAuthorization {
        Self.knownCameraAuthorization(arguments: arguments, service: cameraService)
    }

    /// Static so `init` can consult authorization before every stored property is assigned.
    private static func knownCameraAuthorization(
        arguments: [String],
        service: any CameraCaptureService
    ) -> CameraAuthorization {
        #if DEBUG
        if arguments.contains("-uiTestCamera") {
            return service.authorization
        }
        #endif
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .restricted
        }
    }

    private static func makeFakeCameraService(arguments: [String]) -> any CameraCaptureService {
        #if DEBUG
        let fake = FakeCameraCaptureService(authorization: fakeCameraAuthorization(arguments: arguments))
        fake.grantOnRequest = !arguments.contains("-cameraDenyOnRequest")
        fake.rearWideAvailable = !arguments.contains("-cameraMissingWide")
        fake.frontAvailable = !arguments.contains("-cameraMissingFront")
        if arguments.contains("-cameraFailure") { fake.preparationFailure = .configurationFailed }
        fake.advancesRecordedDurationInRealTime = true
        fake.capsBelowMinimum = arguments.contains("-recordingTooShort")
        return fake
        #else
        return AVFoundationCameraService()
        #endif
    }

    #if DEBUG
    private static func makeFakeMicrophone(arguments: [String]) -> any MicrophoneAuthorizationProviding {
        let status: MicrophoneAuthorization = arguments.contains("-micDenied") ? .denied
            : arguments.contains("-micRestricted") ? .restricted
            : arguments.contains("-micNotDetermined") ? .notDetermined : .authorized
        let fake = FakeMicrophoneAuthorization(authorization: status)
        fake.grantOnRequest = !arguments.contains("-micDenyOnRequest")
        return fake
    }
    private static func makeFakePhotosSaver(arguments: [String]) -> any PhotosLibrarySaving {
        let status: PhotosAddAuthorization = arguments.contains("-photosAddDenied") ? .denied
            : arguments.contains("-photosAddRestricted") ? .restricted
            : arguments.contains("-photosAddNotDetermined") ? .notDetermined : .authorized
        let fake = FakePhotosLibrarySaver(authorization: status)
        fake.grantOnRequest = !arguments.contains("-photosAddDenyOnRequest")
        fake.saveFails = arguments.contains("-photosSaveFails")
        return fake
    }
    #endif

    private static func fakeCameraAuthorization(arguments: [String]) -> CameraAuthorization {
        #if DEBUG
        if arguments.contains("-cameraDenied") { return .denied }
        if arguments.contains("-cameraRestricted") { return .restricted }
        if arguments.contains("-cameraNotDetermined") { return .notDetermined }
        return .authorized
        #else
        return .authorized
        #endif
    }

    #if DEBUG
    /// UI-test-only seeding. Real project creation is owned by the recording phase; this keeps the
    /// Recent / existing-project navigation testable now that V1 has no creation UI. It never runs
    /// without an explicit launch argument, so an ordinary launch still persists nothing.
    private static func seedUITestProjects(arguments: [String], repository: any ProjectRepository) {
        var orientations: [ProjectOrientation] = []
        if arguments.contains("-uiTestSeedPortrait") { orientations.append(.portrait9x16) }
        if arguments.contains("-uiTestSeedLandscape") { orientations.append(.landscape16x9) }
        guard !orientations.isEmpty else { return }
        for orientation in orientations {
            guard let project = try? VlogProject(orientation: orientation) else { continue }
            try? repository.create(project)
        }
    }
    #endif

    private static func persistPermissionOnboardingCompleted(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: PermissionOnboardingStorage.key)
    }
}
