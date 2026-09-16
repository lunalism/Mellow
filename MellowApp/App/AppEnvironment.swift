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
    let projectComposition: ProjectCompositionCoordinator
    let projectMediaStore: any ProjectMediaStoring
    let projectStorageGate: any ProjectStorageGating
    /// Editor clip thumbnails (ARCHITECTURE §56): Project-owned committed media only, memory cache.
    let clipThumbnails: any ClipThumbnailProviding
    /// Production Select-Clips boundary (system Photos picker) hosted by the Projects screen.
    let photosVideoSelector: PhotosVideoSelector
    /// Production `프로젝트` screen state (ADR-036): canonical saved-Project lookup + Select Clips.
    let projectsEntry: ProjectsEntryModel
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

    #if DEBUG
    /// STEP 5 deterministic Projects Entry model (DEBUG/UI tests only). Built only for
    /// `-uiTestProjectsEntry`; production Camera `Projects` navigation is untouched by this.
    private(set) var uiTestProjectsEntry: ProjectsEntryModel?
    /// The last intent the Projects Entry delivered, exposed so a UI test can observe it without
    /// any Project being created or replaced.
    private(set) var uiTestProjectsEntryIntent: String?
    /// STEP 6C manual physical-review route (`-uiTestProjectsEntryRealMedia`): the real production
    /// Photos picker bridge hosted by the DEBUG Projects screen. Nil on the deterministic route.
    private(set) var uiTestRealMediaSelector: PhotosVideoSelector?
    /// `-uiTestLegacyRecentProjects`: routes the Camera `Projects` control to the transitional Recent
    /// browser so historical Phase 2/3 regressions keep their exact semantics. Never Release.
    var usesLegacyRecentProjects: Bool { arguments.contains("-uiTestLegacyRecentProjects") }
    #endif

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
        // Fake mode returns no thumbnail, so the UI-test preview tile keeps its placeholder look.
        let thumbnails: any RecordingThumbnailGenerating = fakeMode
            ? FakeRecordingThumbnailGenerator() : AVAssetRecordingThumbnailGenerator()
        #else
        let microphone: any MicrophoneAuthorizationProviding = AVMicrophoneAuthorization()
        let photosSaver: any PhotosLibrarySaving = PHPhotosLibrarySaver()
        let inspector: any RecordingMediaInspecting = AVAssetRecordingMediaInspector()
        let thumbnails: any RecordingThumbnailGenerating = AVAssetRecordingThumbnailGenerator()
        #endif
        self.microphone = microphone
        self.photosSaver = photosSaver
        self.mediaInspector = inspector
        recording = RecordingCoordinator(
            service: cameraService,
            staging: stagingStore,
            photos: photosSaver,
            inspector: inspector,
            thumbnails: thumbnails,
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
        #if DEBUG
        // `-uiTestEditorSaveFailure`: every whole-Project autosave (`update`) fails, so the Editor's
        // rollback paths (reorder / delete / undo) can be exercised deterministically. Seeding and
        // reads go through unchanged.
        self.projectRepository = arguments.contains("-uiTestEditorSaveFailure")
            ? UpdateFailingProjectRepository(inner: repository) : repository
        #else
        self.projectRepository = repository
        #endif
        // Phase 5 Select-Clips composition (ADR-034 §2 / ADR-020 / ADR-024). The UI-test harness
        // injects a fake gate so deterministic scenarios never depend on the simulator's disk.
        let projectMediaStore = ProjectMediaStore()
        self.projectMediaStore = projectMediaStore
        let volumeGate = VolumeProjectStorageGate(
            capacity: { await projectMediaStore.usableCapacityBytes() },
            safetyReserveBytes: ProjectCompositionPolicy.materializationSafetyReserveBytes
        )
        #if DEBUG
        let projectStorageGate: any ProjectStorageGating = arguments.contains("-uiTestProjectsEntry")
            ? FakeProjectStorageGate(verdict: .sufficient) : volumeGate
        #else
        let projectStorageGate: any ProjectStorageGating = volumeGate
        #endif
        self.projectStorageGate = projectStorageGate
        self.projectComposition = ProjectCompositionCoordinator(
            repository: repository,
            mediaStore: projectMediaStore,
            validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()),
            storage: projectStorageGate
        )
        self.home = HomeModel(repository: repository, router: router)
        let photosVideoSelector = PhotosVideoSelector()
        self.photosVideoSelector = photosVideoSelector
        // The Projects screen stays below the Editor so Back returns Editor → 프로젝트 → Camera.
        self.projectsEntry = ProjectsEntryModel(
            composition: projectComposition,
            mediaStore: projectMediaStore,
            mediaSelector: photosVideoSelector,
            storageGate: projectStorageGate,
            onContinueEditing: { projectID in router.path.append(.projectEditor(projectID)) },
            onProjectCommitted: { projectID in router.path.append(.projectEditor(projectID)) }
        )

        #if DEBUG
        Self.seedUITestProjects(arguments: arguments, repository: repository)
        let seededEditorClipIDs = Self.seedEditorProjectAndRouteIfNeeded(arguments: arguments, repository: repository, router: router)
        // The seeded editor project has no media, so its thumbnails come from a deterministic fake
        // (`-uiTestThumbnailFailure=<position>` scripts one placeholder). Every other route — including
        // the STEP 6 fixture composition — uses the production service against real committed media.
        if let seededEditorClipIDs {
            var script: [UUID: FakeClipThumbnailProvider.Outcome] = [:]
            for (index, id) in seededEditorClipIDs.enumerated() { script[id] = .image(seed: index) }
            let failing = arguments.first { $0.hasPrefix("-uiTestThumbnailFailure=") }?
                .replacingOccurrences(of: "-uiTestThumbnailFailure=", with: "")
            if let failing, let position = Int(failing), seededEditorClipIDs.indices.contains(position - 1) {
                script[seededEditorClipIDs[position - 1]] = .failure(.mediaMissing)
            }
            clipThumbnails = FakeClipThumbnailProvider(script: script)
        } else {
            clipThumbnails = ClipThumbnailService(resolver: projectMediaStore)
        }
        routeToUITestProjectsEntryIfNeeded()
        routeToUITestProjectsEntryRealMediaIfNeeded()
        #else
        clipThumbnails = ClipThumbnailService(resolver: projectMediaStore)
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

    /// STEP 4 deterministic editor routing (DEBUG/UI-tests only). Seeds one Portrait project with a
    /// few placeholder clips and, when requested, opens it directly in the Project Editor. This
    /// exposes the editor without changing production Recent-item navigation (which two completed
    /// Phase 2/3 regression tests still depend on). Returns the seeded clip ids in logical order, or
    /// nil when nothing was seeded.
    @discardableResult
    private static func seedEditorProjectAndRouteIfNeeded(
        arguments: [String],
        repository: any ProjectRepository,
        router: AppRouter
    ) -> [UUID]? {
        // `-uiTestReopenEditorProject`: STEP 9 persistence check — relaunch WITHOUT reseeding, open the
        // saved Project as-is (the previous launch's reorder must still be there) and keep the fake
        // thumbnails bound to its existing clip ids.
        if arguments.contains("-uiTestReopenEditorProject") {
            guard let saved = try? repository.recentProjects().first else { return nil }
            router.path = [.projectEditor(saved.id)]
            return saved.clips.map(\.id)
        }
        guard arguments.contains("-uiTestSeedEditorProject") else { return nil }
        // Start from a clean store so the seeded editor project is deterministic and independent of
        // any leftover shared-container state from earlier tests.
        if let existing = try? repository.recentProjects() {
            for project in existing { try? repository.deleteProject(id: project.id) }
        }
        let projectID = UUID()
        // Default three clips; `-uiTestSeedEditorClips=N` seeds N (cycling the same durations) so the
        // timeline's horizontal overflow can be exercised deterministically.
        let baseDurations: [MediaTime] = [.seconds(2), .seconds(3), .seconds(1)]
        let requestedCount = arguments.first { $0.hasPrefix("-uiTestSeedEditorClips=") }
            .flatMap { Int($0.replacingOccurrences(of: "-uiTestSeedEditorClips=", with: "")) } ?? baseDurations.count
        let durations = (0..<max(1, requestedCount)).map { baseDurations[$0 % baseDurations.count] }
        let clips: [VlogClip] = durations.enumerated().compactMap { index, duration in
            guard let path = try? RelativeMediaPath("seed/editor-clip-\(index).mov") else { return nil }
            return try? VlogClip(
                projectID: projectID,
                sourceKind: .recorded,
                mediaRelativePath: path,
                sourceDuration: duration,
                trimDuration: duration,
                sortOrder: index
            )
        }
        guard let project = try? VlogProject(id: projectID, orientation: .portrait9x16, clips: clips) else { return nil }
        try? repository.create(project)
        if arguments.contains("-uiTestOpenEditor") {
            router.path = [.projectEditor(projectID)]
        }
        return project.clips.map(\.id)
    }
    #endif

    #if DEBUG
    /// STEP 5/6 deterministic Projects Entry routing (DEBUG/UI tests only), `-uiTestProjectsEntry`.
    /// Pushes the dedicated ADR-035 `프로젝트` screen (`Camera → .projectsEntry`) without touching
    /// production `Projects` navigation. Alone it starts from an empty store (no saved Project);
    /// combined with `-uiTestSeedEditorProject` the seeded project is the saved Project.
    ///
    /// Select Clips is driven by a deterministic fake selector chosen with `-uiTestMediaSelection`
    /// (`cancel` | `ready` | `ready2` | `tooLong` | `corrupt` | `fail`; default `cancel`). Fixture
    /// media is generated at launch under the temporary directory; the real Photos picker is never
    /// automated. Intents are also recorded in `uiTestProjectsEntryIntent`.
    private func routeToUITestProjectsEntryIfNeeded() {
        guard arguments.contains("-uiTestProjectsEntry") else { return }
        if !arguments.contains("-uiTestSeedEditorProject"), let existing = try? projectRepository.recentProjects() {
            for project in existing { try? projectRepository.deleteProject(id: project.id) }
        }
        let selector = FakeProjectMediaSelector(script: .cancel)
        uiTestProjectsEntry = ProjectsEntryModel(
            composition: projectComposition,
            mediaStore: projectMediaStore,
            mediaSelector: selector,
            storageGate: projectStorageGate,
            onContinueEditing: { [weak self] projectID in
                // The Projects screen stays below the Editor so Back returns to `프로젝트`.
                self?.router.path.append(.projectEditor(projectID))
            },
            onNewProject: { [weak self] intent in
                switch intent {
                case .fresh: self?.uiTestProjectsEntryIntent = "newProject-fresh"
                case .replacingSaved(let id): self?.uiTestProjectsEntryIntent = "newProject-replace-\(id.uuidString)"
                }
            },
            onProjectCommitted: { [weak self] projectID in
                self?.router.path.append(.projectEditor(projectID))
            }
        )
        router.path = [.projectsEntry]
        let arguments = self.arguments
        selector.pendingScript = Task { await Self.makeUITestSelectionScript(arguments: arguments) }
    }

    /// STEP 6C manual physical-review route (DEBUG only), `-uiTestProjectsEntryRealMedia`. Pushes the
    /// same `.projectsEntry` screen but with the REAL production Phase-5 dependencies: the system
    /// Photos picker (`PhotosVideoSelector`), `VolumeProjectStorageGate` with the approved 100 MiB
    /// reserve, `ProjectMediaStore`, the AVAsset validator, the composition coordinator and the
    /// SwiftData repository. Nothing is seeded, faked or cleared; persistence is whatever the device
    /// holds. Never used by automated UI tests; never compiled into Release.
    private func routeToUITestProjectsEntryRealMediaIfNeeded() {
        guard arguments.contains("-uiTestProjectsEntryRealMedia"), uiTestProjectsEntry == nil else { return }
        let selector = PhotosVideoSelector()
        uiTestRealMediaSelector = selector
        uiTestProjectsEntry = ProjectsEntryModel(
            composition: projectComposition,
            mediaStore: projectMediaStore,
            mediaSelector: selector,
            storageGate: projectStorageGate,
            onContinueEditing: { [weak self] projectID in
                self?.router.path.append(.projectEditor(projectID))
            },
            onProjectCommitted: { [weak self] projectID in
                self?.router.path.append(.projectEditor(projectID))
            }
        )
        router.path = [.projectsEntry]
    }

    private static func makeUITestSelectionScript(arguments: [String]) async -> FakeProjectMediaSelector.Script {
        let mode = arguments.first { $0.hasPrefix("-uiTestMediaSelection=") }?
            .replacingOccurrences(of: "-uiTestMediaSelection=", with: "") ?? "cancel"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UITestFixtures", isDirectory: true)
        func fixture(_ name: String, seconds: Double) async -> URL? {
            let url = directory.appendingPathComponent(name).appendingPathExtension("mov")
            do { try await FixtureVideoWriter.write(to: url, seconds: seconds); return url } catch { return nil }
        }
        switch mode {
        case "ready":
            return await fixture("ready-a", seconds: 2).map { .fixtures([$0]) } ?? .fail
        case "ready2":
            if let a = await fixture("ready-a", seconds: 2), let b = await fixture("ready-b", seconds: 3) { return .fixtures([a, b]) }
            return .fail
        case "tooLong":
            return await fixture("too-long", seconds: 7).map { .fixtures([$0]) } ?? .fail
        case "corrupt":
            let url = directory.appendingPathComponent("corrupt").appendingPathExtension("mov")
            return (try? FixtureVideoWriter.writeCorrupt(to: url)) != nil ? .fixtures([url]) : .fail
        case "fail":
            return .fail
        default:
            return .cancel
        }
    }
    #endif

    private static func persistPermissionOnboardingCompleted(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: PermissionOnboardingStorage.key)
    }
}

#if DEBUG
/// UI-test double: forwards everything except `update`, which always fails.
@MainActor
private final class UpdateFailingProjectRepository: ProjectRepository {
    private let inner: any ProjectRepository
    struct SaveFailure: Error {}
    init(inner: any ProjectRepository) { self.inner = inner }
    func create(_ project: VlogProject) throws { try inner.create(project) }
    func project(id: UUID) throws -> VlogProject? { try inner.project(id: id) }
    func recentProjects() throws -> [VlogProject] { try inner.recentProjects() }
    func update(_ project: VlogProject) throws { throw SaveFailure() }
    func finalizeDeletedClip(projectID: UUID, clipID: UUID) throws { try inner.finalizeDeletedClip(projectID: projectID, clipID: clipID) }
    func deleteProject(id: UUID) throws { try inner.deleteProject(id: id) }
}
#endif
