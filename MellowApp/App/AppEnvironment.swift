import AVFoundation
import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class AppEnvironment {
    private enum PermissionOnboardingStorage {
        static let key = "com.mellow.permissionOnboardingCompleted"
    }

    let router: AppRouter
    let projectRepository: any ProjectRepository
    let home: HomeModel
    let modelContainer: ModelContainer
    let cameraService: any CameraCaptureService

    private(set) var permissionOnboardingCompleted: Bool
    private let arguments: [String]
    private var prewarmTask: Task<Void, Never>?

    var shouldShowPermissionOnboarding: Bool {
        !permissionOnboardingCompleted
    }

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
                orientation: FakeCameraOrientationSource(posture)
            )
        }
        #endif
        #endif
        return CameraModel(
            projectOrientation: projectOrientation,
            service: cameraService,
            orientation: DeviceCameraOrientationSource()
        )
    }

    func completePermissionOnboarding() async {
        guard !permissionOnboardingCompleted else {
            prewarmCameraIfNeeded()
            return
        }
        // Explanation is complete first; permission itself is requested only on this explicit user action.
        let authorization = await cameraService.resolveAuthorization()
        permissionOnboardingCompleted = true
        Self.persistPermissionOnboardingCompleted(true)
        if authorization == .authorized {
            await cameraService.prepare()
        }
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
        }

        let router = router ?? AppRouter()
        self.router = router
        self.modelContainer = modelContainer

        if arguments.contains("-uiTestCamera") {
            cameraService = Self.makeFakeCameraService(arguments: arguments)
        } else {
            cameraService = AVFoundationCameraService()
        }

        let persisted = UserDefaults.standard.bool(forKey: PermissionOnboardingStorage.key)
        let known = Self.knownCameraAuthorization(arguments: arguments, service: cameraService) != .notDetermined
        let onboardingCompleted = persisted || known || arguments.contains("-uiTestSkipOnboarding")
        permissionOnboardingCompleted = onboardingCompleted
        Self.persistPermissionOnboardingCompleted(onboardingCompleted)

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
        return fake
        #else
        return AVFoundationCameraService()
        #endif
    }

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
