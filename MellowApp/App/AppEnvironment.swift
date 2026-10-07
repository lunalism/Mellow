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
    /// ADR-039 shared critical section: cleanup ↔ composition / replacement ↔ Editor Project load.
    let projectLifecycle: ProjectLifecycleOperationGate
    /// Deferred physical cleanup of known pending Clips (ADR-039): Editor exit + app startup only.
    let projectCleanup: ProjectMediaCleanupCoordinator
    /// Startup-only orphan media / Project directory / workspace recovery (ADR-039 STEP 12B).
    let projectRecovery: ProjectStartupRecoveryCoordinator
    let projectMediaStore: any ProjectMediaStoring
    /// The same store, concretely: the Phase 6 import services need its attempt / workspace surface.
    private let importMediaStore: ProjectMediaStore
    let projectStorageGate: any ProjectStorageGating
    /// Editor clip thumbnails (ARCHITECTURE §56): Project-owned committed media only, memory cache.
    let clipThumbnails: any ClipThumbnailProviding
    /// Editor derived Clip availability (ADR-040): the read-only committed-media resolver, or the
    /// deterministic fake on the seeded UI-test Editor routes (whose Clips never have files).
    let clipAvailability: any ClipAvailabilityChecking
    /// Production Select-Clips boundary (system Photos picker) hosted by the Projects screen.
    let photosVideoSelector: PhotosVideoSelector
    /// Production Add-Clips picker hosted by the Editor (ADR-037); its own instance so the Projects
    /// screen's picker host below in the navigation stack never competes for presentation. Nil when
    /// a DEBUG fake drives the Editor's acquisition.
    let editorPhotosSelector: PhotosVideoSelector?
    /// The Editor's Add Clips boundary: same store / gate / validator chain as Select Clips.
    let editorClipAcquisition: EditorClipAcquisition
    /// Production `프로젝트` screen state (ADR-036): canonical saved-Project lookup + Select Clips.
    let projectsEntry: ProjectsEntryModel
    /// Derived representative state of the saved Project (Phase 5 STEP 14): consumed by the Projects
    /// screen visual (ADR-041: never the Camera content slot); refreshed on state boundaries, never polled.
    let projectRepresentative: ProjectRepresentativeModel
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

    #if DEBUG
    /// `-uiTestEditorGateHold=<ms>`: before each Reorder / Delete / Undo / Redo enters the shared lifecycle gate,
    /// a separate holder takes that real gate for `ms` milliseconds (released on its own, never left held), so a
    /// UI test can observe a queued edit. DEBUG / simulator UI tests only.
    var uiTestEditorGateHoldMilliseconds: Int? {
        arguments.first { $0.hasPrefix("-uiTestEditorGateHold=") }
            .flatMap { Int($0.replacingOccurrences(of: "-uiTestEditorGateHold=", with: "")) }
            .flatMap { $0 > 0 ? $0 : nil }
    }
    #endif
    private var prewarmTask: Task<Void, Never>?

    #if DEBUG
    /// STEP 5 deterministic Projects Entry model (DEBUG/UI tests only). Built only for
    /// `-uiTestProjectsEntry`; production Camera `Projects` navigation is untouched by this.
    private(set) var uiTestProjectsEntry: ProjectsEntryModel?
    /// The last intent the Projects Entry delivered, exposed so a UI test can observe it without
    /// any Project being created or replaced.
    private(set) var uiTestProjectsEntryIntent: String?
    /// The launch's physical-device import controls (nil unless requested), shared by every real-picker import route so
    /// each scripted count is consumed once per launch.
    private var deviceImportControls: UITestDeviceImportControls?
    /// STEP 6C manual physical-review route (`-uiTestProjectsEntryRealMedia`): the real production
    /// Photos picker bridge hosted by the DEBUG Projects screen. Nil on the deterministic route.
    private(set) var uiTestRealMediaSelector: PhotosVideoSelector?
    /// `-uiTestCleanupDiagnostics`: cumulative cleanup counters surfaced as a tiny overlay so UI tests
    /// can observe that a pass completed (no production surface exists for cleanup, by design).
    private(set) var uiTestCleanupSummary: String?
    /// `-uiTestCleanupDiagnostics`: STEP 12B counters + the post-maintenance existence of every
    /// seeded recovery fixture (`-uiTestSeed…` arguments), so UI tests can assert removal /
    /// preservation without touching the filesystem themselves.
    private(set) var uiTestRecoverySummary: String?
    /// `-uiTestRepresentativeDiagnostics`: the current representative selection (saved Project prefix,
    /// representative Clip duration, thumbnail readiness) as a tiny overlay so UI tests can assert the
    /// derived state without reading pixels. Never Release.
    private(set) var uiTestRepresentativeSummary: String?
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
        // `-uiTestEditorSaveUnverified`: saves land, but every post-save observation is unreadable, so the
        // Editor's reconciliation lock (ADR-050 050-D D8.5a P2) can be driven on the simulator store.
        let sessionRepository: any ProjectRepository
        if arguments.contains("-uiTestEditorSaveFailure") {
            sessionRepository = UpdateFailingProjectRepository(inner: repository)
        } else if arguments.contains("-uiTestEditorSaveUnverified") {
            sessionRepository = UnverifiedSaveProjectRepository(inner: repository)
        } else {
            sessionRepository = repository
        }
        #else
        let sessionRepository: any ProjectRepository = repository
        #endif
        self.projectRepository = sessionRepository
        // Phase 5 Select-Clips composition (ADR-034 §2 / ADR-020 / ADR-024). The UI-test harness
        // injects a fake gate so deterministic scenarios never depend on the simulator's disk.
        let projectMediaStore = ProjectMediaStore()
        self.projectMediaStore = projectMediaStore
        self.importMediaStore = projectMediaStore
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
        // ADR-050 050-C C0: the per-file copy admission of the selection boundary (source bytes + 256 MiB Import
        // reserve on the transfer directory's volume). The gate above stays the Phase 5 commit-time final guard.
        #if DEBUG
        let transferAdmission: any ProjectStorageGating = arguments.contains("-uiTestProjectsEntry")
            ? FakeProjectStorageGate(verdict: .sufficient) : ImportTransferCopyGate.transferVolume()
        #else
        let transferAdmission: any ProjectStorageGating = ImportTransferCopyGate.transferVolume()
        #endif
        let projectLifecycle = ProjectLifecycleOperationGate()
        // Phase 6 imports in an Editor, so an Editor-route removal can let them finish before Editor-exit cleanup.
        let importActivity = ImportOperationActivity()
        let editorRouteProbe: (UUID) -> () -> Bool = { [router] projectID in router.routeProbe(for: .projectEditor(projectID)) }
        // The real-picker import services. In DEBUG the physical-device failure controls attach only when one of their
        // launch arguments is present (`UITestDeviceImportControls`); otherwise these are the production services.
        #if DEBUG
        let deviceImportControls = UITestDeviceImportControls(arguments: arguments)
        self.deviceImportControls = deviceImportControls
        #endif
        func productionImportServices(_ repository: any ProjectRepository) -> ImportFlowServices {
            #if DEBUG
            if let deviceImportControls {
                return deviceImportControls.services(repository: repository, store: projectMediaStore, lifecycle: projectLifecycle)
            }
            #endif
            return Self.makeImportFlowServices(repository: repository, store: projectMediaStore, lifecycle: projectLifecycle)
        }
        self.projectLifecycle = projectLifecycle
        self.projectComposition = ProjectCompositionCoordinator(
            repository: repository,
            mediaStore: projectMediaStore,
            validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()),
            storage: projectStorageGate,
            lifecycle: projectLifecycle
        )
        self.home = HomeModel(repository: repository, router: router, lifecycle: projectLifecycle)
        let photosVideoSelector = PhotosVideoSelector()
        self.photosVideoSelector = photosVideoSelector
        let appender = ProjectClipAppendCoordinator(
            mediaStore: projectMediaStore,
            validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()),
            storage: projectStorageGate
        )
        #if DEBUG
        // `-uiTestEditorAddSelection=<cancel|ready|ready2|tooLong|corrupt|fail>`: a deterministic fake
        // selector (fixture media generated after launch) and a sufficient storage gate drive the
        // Editor's "+" so the real Photos picker is never automated. Production is untouched.
        if arguments.contains(where: { $0.hasPrefix("-uiTestEditorAddSelection=") }) {
            let fake = FakeProjectMediaSelector(script: .cancel)
            let launchArguments = arguments
            fake.pendingScript = Task { await AppEnvironment.makeUITestSelectionScript(arguments: launchArguments, key: "-uiTestEditorAddSelection=") }
            self.editorPhotosSelector = nil
            var acquisition = EditorClipAcquisition(
                mediaStore: projectMediaStore, mediaSelector: fake,
                storageGate: FakeProjectStorageGate(verdict: .sufficient),
                appender: ProjectClipAppendCoordinator(
                    mediaStore: projectMediaStore,
                    validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()),
                    storage: FakeProjectStorageGate(verdict: .sufficient)
                ),
                lifecycle: projectLifecycle
            )
            // `-uiTestCrashAfterAddMaterialize`: the STEP 12B crash window — the batch's files exist
            // under the Project, no row references them yet, and the process dies before commit.
            if arguments.contains("-uiTestCrashAfterAddMaterialize") {
                acquisition.debugAfterMaterialize = { exit(0) }
            } else {
                // Phase 6 Add / Replace with the real normalizer (optionally delayed / failing via UI-test seams).
                acquisition.importServices = Self.makeImportFlowServices(repository: sessionRepository, store: projectMediaStore, lifecycle: projectLifecycle,
                                                                         normalizer: UITestScriptedNormalizer(arguments: arguments))
                acquisition.importActivity = importActivity
                acquisition.makeRouteProbe = editorRouteProbe
            }
            self.editorClipAcquisition = acquisition
        } else {
            let editorSelector = PhotosVideoSelector()
            self.editorPhotosSelector = editorSelector
            self.editorClipAcquisition = EditorClipAcquisition(mediaStore: projectMediaStore, mediaSelector: editorSelector, storageGate: transferAdmission, appender: appender, lifecycle: projectLifecycle,
                                                               importServices: productionImportServices(sessionRepository),
                                                               importActivity: importActivity, makeRouteProbe: editorRouteProbe)
        }
        #else
        let editorSelector = PhotosVideoSelector()
        self.editorPhotosSelector = editorSelector
        self.editorClipAcquisition = EditorClipAcquisition(mediaStore: projectMediaStore, mediaSelector: editorSelector, storageGate: transferAdmission, appender: appender, lifecycle: projectLifecycle,
                                                               importServices: Self.makeImportFlowServices(repository: sessionRepository, store: projectMediaStore, lifecycle: projectLifecycle),
                                                               importActivity: importActivity, makeRouteProbe: editorRouteProbe)
        #endif
        // The Projects screen stays below the Editor so Back returns Editor → 프로젝트 → Camera.
        self.projectsEntry = ProjectsEntryModel(
            composition: projectComposition,
            mediaStore: projectMediaStore,
            mediaSelector: photosVideoSelector,
            storageGate: transferAdmission,
            importServices: productionImportServices(repository),
            routeProbe: { [router] in router.projectsEntryRouteProbe() },
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
            // `-uiTestUnavailableClips=<1-based positions>`: exactly those seeded Clips (by identity,
            // resolved at launch) are structurally unavailable; every other Clip — including a Clip
            // added or created by Replace during the test — is available. Never Release.
            let positions = arguments.first { $0.hasPrefix("-uiTestUnavailableClips=") }?
                .replacingOccurrences(of: "-uiTestUnavailableClips=", with: "")
                .split(separator: ",").compactMap { Int($0) } ?? []
            let unavailable = Set(positions.compactMap { seededEditorClipIDs.indices.contains($0 - 1) ? seededEditorClipIDs[$0 - 1] : nil })
            clipAvailability = FakeClipAvailabilityChecker(unavailableClipIDs: unavailable)
        } else {
            clipThumbnails = ClipThumbnailService(resolver: projectMediaStore)
            clipAvailability = CommittedMediaAvailabilityChecker(resolver: projectMediaStore)
        }
        #else
        clipThumbnails = ClipThumbnailService(resolver: projectMediaStore)
        clipAvailability = CommittedMediaAvailabilityChecker(resolver: projectMediaStore)
        #endif

        // Phase 5 STEP 14: representative thumbnail of the saved Project. Same saved-Project rule as the
        // Projects screen, same availability checker and thumbnail boundary as the Editor (fakes on the
        // seeded UI-test routes), reads behind the lifecycle gate so an Editor-exit refresh sees the
        // reconciled Project.
        let composition = projectComposition
        self.projectRepresentative = ProjectRepresentativeModel(
            savedProject: { try composition.lastSavedProject() },
            availability: clipAvailability,
            thumbnails: clipThumbnails,
            lifecycle: projectLifecycle
        )

        // ADR-039 deferred physical cleanup. The thumbnail service is the only media reader today and
        // gates cleanup through `awaitIdle`; a live Editor session is "the route is on the stack".
        // Trigger A: the Editor route leaves the path → one pass for that Project, never awaited by
        // navigation. Trigger B: app startup → one pass per durable Project (below).
        let consumers: any ProjectMediaConsumerGating = (clipThumbnails as? any ProjectMediaConsumerGating) ?? IdleProjectMediaConsumersFallback()
        let projectCleanup = ProjectMediaCleanupCoordinator(
            repository: projectRepository,
            mediaStore: projectMediaStore,
            consumers: consumers,
            lifecycle: projectLifecycle,
            isEditorSessionLive: { [router] projectID in router.hasLiveProjectEditor(for: projectID) }
        )
        self.projectCleanup = projectCleanup
        let productionProjectsEntry = projectsEntry
        router.onProjectsEntryRouteRemoved = { productionProjectsEntry.originatingRouteRemoved() }
        router.onProjectEditorRouteInstanceRemoved = { [importActivity] projectID in importActivity.routeRemoved(projectID: projectID) }
        router.onProjectEditorRouteRemoved = { [projectCleanup, importActivity] projectID in
            // Editor decision 3 (2026-10-06): a Phase 6 import for this Project first finishes its outcome processing and
            // attempt cleanup (an unanswerable Retry wait ends now); only then does the gated Editor-exit cleanup run. The
            // wait never holds the lifecycle gate.
            importActivity.routeRemoved(projectID: projectID)
            guard importActivity.isActive(projectID: projectID) else {
                projectCleanup.scheduleReconcile(projectID: projectID)
                return
            }
            Task { @MainActor in
                await importActivity.waitUntilIdle(projectID: projectID)
                projectCleanup.scheduleReconcile(projectID: projectID)
            }
        }
        self.projectRecovery = ProjectStartupRecoveryCoordinator(
            repository: projectRepository,
            store: projectMediaStore,
            lifecycle: projectLifecycle,
            isEditorSessionLive: { [router] projectID in router.hasLiveProjectEditor(for: projectID) }
        )
        #if DEBUG
        configureUITestCleanupSeams()
        configureUITestRepresentativeDiagnostics()
        routeToUITestProjectsEntryIfNeeded()
        routeToUITestProjectsEntryRealMediaIfNeeded()
        seedUITestRecoveryFixturesIfNeeded()
        #endif
        scheduleStartupMaintenance()

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

    /// ADR-039 startup maintenance, one deterministic flow, never awaited by the Camera:
    /// abandoned-workspace sweep → STEP 12A known-pending cleanup → STEP 12B orphan recovery. Each
    /// step takes the lifecycle gate in narrow sections, so an Editor load or a composition queued
    /// meanwhile only waits for the section that is running. `CaptureStaging` is not part of this;
    /// `runStagingRecovery` (Phase 4) owns it.
    private func scheduleStartupMaintenance() {
        let cleanup = projectCleanup, recovery = projectRecovery
        Task { @MainActor [weak self] in
            #if DEBUG
            await self?.writeUITestRecoveryFixtures()
            await self?.removeUITestActiveClipMediaIfRequested()
            #endif
            var report = await recovery.sweepAbandonedWorkspaces()
            _ = await cleanup.reconcileAll()
            report = report + (await recovery.recoverOrphans())
            #if DEBUG
            self?.publishUITestRecoverySummary(report)
            #endif
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
        // `-uiTestReopenProjectsEntry`: STEP 12A startup-reconciliation check — relaunch WITHOUT
        // reseeding and WITHOUT an Editor route (so startup cleanup is not skipped for a live
        // session), landing on the production 프로젝트 screen whose 기존 프로젝트 불러오기 opens the
        // saved Project as-is.
        if arguments.contains("-uiTestReopenProjectsEntry") {
            guard let saved = try? repository.recentProjects().first else { return nil }
            router.path = [.projectsEntry]
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
        // Canonical committed paths (no file behind them — thumbnails are faked): a deleted seeded
        // clip is "pending + file already absent", which STEP 12A cleanup finalizes.
        let clips: [VlogClip] = durations.enumerated().compactMap { index, duration in
            let clipID = UUID()
            guard let path = try? ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID) else { return nil }
            return try? VlogClip(
                id: clipID,
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
        // `-uiTestProjectsLookupFailures=<n>`: the first n saved-Project lookups of this screen fail, so the
        // unknown state and its explicit reload can be driven on the simulator store (never a device store).
        var composition = projectComposition
        if let failures = arguments.first(where: { $0.hasPrefix("-uiTestProjectsLookupFailures=") })
            .flatMap({ Int($0.replacingOccurrences(of: "-uiTestProjectsLookupFailures=", with: "")) }), failures > 0 {
            composition = ProjectCompositionCoordinator(
                repository: LookupFailingProjectRepository(inner: projectRepository, failures: failures),
                mediaStore: projectMediaStore,
                validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()),
                storage: projectStorageGate,
                lifecycle: projectLifecycle
            )
        }
        uiTestProjectsEntry = ProjectsEntryModel(
            composition: composition,
            mediaStore: projectMediaStore,
            mediaSelector: selector,
            storageGate: projectStorageGate,
            importServices: Self.makeImportFlowServices(
                repository: projectRepository, store: importMediaStore, lifecycle: projectLifecycle,
                normalizer: UITestScriptedNormalizer(arguments: arguments)),
            routeProbe: { [router] in router.projectsEntryRouteProbe() },
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
        registerProjectsRouteRemovalListeners()
        router.path = [.projectsEntry]
        let arguments = self.arguments
        selector.pendingScript = Task { await Self.makeUITestSelectionScript(arguments: arguments) }
    }

    /// Real-picker import services for routes built after init, with the same shared device controls as the production routes.
    private func realPickerImportServices(_ repository: any ProjectRepository) -> ImportFlowServices {
        if let deviceImportControls {
            return deviceImportControls.services(repository: repository, store: importMediaStore, lifecycle: projectLifecycle)
        }
        return Self.makeImportFlowServices(repository: repository, store: importMediaStore, lifecycle: projectLifecycle)
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
            storageGate: ImportTransferCopyGate.transferVolume(),
            importServices: realPickerImportServices(projectRepository),
            routeProbe: { [router] in router.projectsEntryRouteProbe() },
            onContinueEditing: { [weak self] projectID in
                self?.router.path.append(.projectEditor(projectID))
            },
            onProjectCommitted: { [weak self] projectID in
                self?.router.path.append(.projectEditor(projectID))
            }
        )
        registerProjectsRouteRemovalListeners()
        router.path = [.projectsEntry]
    }

    /// Both Projects models hear real Projects-route removal; each decides by its own operation / route identity.
    private func registerProjectsRouteRemovalListeners() {
        let production = projectsEntry, uiEntry = uiTestProjectsEntry
        router.onProjectsEntryRouteRemoved = {
            production.originatingRouteRemoved()
            uiEntry?.originatingRouteRemoved()
        }
    }

    /// STEP 12A deterministic seams (DEBUG / UI tests only). `-uiTestCleanupDiagnostics` surfaces
    /// cumulative pass counters; `-uiTestCleanupDelay=<ms>` holds every pass inside its critical
    /// section for that long (proves Back is non-blocking and that an Editor reopen waits).
    private func configureUITestCleanupSeams() {
        if let delay = arguments.first(where: { $0.hasPrefix("-uiTestCleanupDelay=") })
            .flatMap({ Int($0.replacingOccurrences(of: "-uiTestCleanupDelay=", with: "")) }), delay > 0 {
            projectCleanup.debugHold = { try? await Task.sleep(for: .milliseconds(delay)) }
        }
        if let delay = arguments.first(where: { $0.hasPrefix("-uiTestRecoveryDelay=") })
            .flatMap({ Int($0.replacingOccurrences(of: "-uiTestRecoveryDelay=", with: "")) }), delay > 0 {
            projectRecovery.debugHold = { try? await Task.sleep(for: .milliseconds(delay)) }
        }
        guard arguments.contains("-uiTestCleanupDiagnostics") else { return }
        var removed = 0, absent = 0, finalized = 0, deferred = 0, passes = 0
        uiTestCleanupSummary = "cleanup passes=0 removed=0 absent=0 finalized=0 deferred=0"
        projectCleanup.onReport = { [weak self] report in
            guard !report.skippedForLiveEditor else { return }
            passes += 1
            removed += report.removedFiles.count
            absent += report.alreadyAbsent.count
            finalized += report.finalized.count
            deferred += report.deferred.count
            self?.uiTestCleanupSummary = "cleanup passes=\(passes) removed=\(removed) absent=\(absent) finalized=\(finalized) deferred=\(deferred)"
        }
    }

    /// STEP 14 diagnostics (DEBUG / UI tests only): mirrors the representative model's published state
    /// into a text overlay whenever it changes. Observation-driven, no polling.
    private func configureUITestRepresentativeDiagnostics() {
        guard arguments.contains("-uiTestRepresentativeDiagnostics") else { return }
        observeRepresentativeForUITests()
    }

    private func observeRepresentativeForUITests() {
        let summary = withObservationTracking {
            Self.representativeSummary(projectRepresentative.state, request: projectRepresentative.currentRequest)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeRepresentativeForUITests() }
        }
        uiTestRepresentativeSummary = summary
    }

    private static func representativeSummary(_ state: ProjectRepresentativeState, request: ClipThumbnailRequest?) -> String {
        switch state {
        case .noProject:
            return "representative project=none clip=none thumbnail=none"
        case .project(let id, let thumbnail):
            let clip = request.map { ClipDurationText.string($0.trimDuration) } ?? "none"
            return "representative project=\(id.uuidString.prefix(8)) clip=\(clip) thumbnail=\(thumbnail == nil ? "placeholder" : "ready")"
        }
    }

    /// STEP 12B deterministic fixtures (DEBUG / UI tests only), all created under the Mellow root
    /// BEFORE startup maintenance runs, so the very first launch pass has something to recover:
    /// `-uiTestSeedOrphanMedia` (canonical unreferenced `<UUID>.mov` in the saved Project),
    /// `-uiTestSeedOrphanProjectDir` (canonical `Projects/<UUID>/Media/<UUID>.mov` with no row),
    /// `-uiTestSeedAbandonedWorkspace` (canonical `ProjectWorkspace/<UUID>/x.mov`),
    /// `-uiTestSeedNoncanonicalFixtures` (`Projects/not-a-project/`, `Projects/<P>/Media/readme.txt`,
    /// `Projects/<P>/Extras/note.txt`, `ProjectWorkspace/stale-op/`). `-uiTestRemoveNoncanonicalFixtures`
    /// deletes exactly those noncanonical fixtures again (physical-device cleanup) — the only path
    /// that ever removes them, since recovery must not.
    private var uiTestRecoveryFixtures: [(label: String, relativePath: String)] = []

    private func seedUITestRecoveryFixturesIfNeeded() {
        let savedProjectID = (try? projectRepository.recentProjects().first?.id)
        var fixtures: [(String, String)] = []
        if arguments.contains("-uiTestSeedOrphanMedia"), let pid = savedProjectID {
            fixtures.append(("orphanMedia", "Projects/\(pid.uuidString)/Media/\(UUID().uuidString).mov"))
        }
        if arguments.contains("-uiTestSeedOrphanProjectDir") {
            fixtures.append(("orphanDir", "Projects/\(UUID().uuidString)/Media/\(UUID().uuidString).mov"))
        }
        if arguments.contains("-uiTestSeedAbandonedWorkspace") {
            fixtures.append(("workspace", "ProjectWorkspace/\(UUID().uuidString)/\(UUID().uuidString).mov"))
        }
        let noncanonical: [(String, String)] = {
            var list = [("nonUUIDDir", "Projects/not-a-project/orphan.mov"), ("staleWorkspace", "ProjectWorkspace/stale-op/x.mov")]
            if let pid = savedProjectID {
                list.append(("sidecar", "Projects/\(pid.uuidString)/Media/readme.txt"))
                list.append(("extras", "Projects/\(pid.uuidString)/Extras/note.txt"))
            }
            return list
        }()
        if arguments.contains("-uiTestSeedNoncanonicalFixtures") { fixtures += noncanonical }
        if arguments.contains("-uiTestRemoveNoncanonicalFixtures") {
            let store = projectMediaStore as? ProjectMediaStore
            Task { for (_, path) in noncanonical { await store?.debugRemoveFixture(relativePath: path) } }
            return
        }
        uiTestRecoveryFixtures = fixtures
    }

    /// ADR-040 physical-review fixture primitive (DEBUG only), `-uiTestRemoveActiveClipMedia=<clipUUID>` together with
    /// `-uiTestRemoveActiveClipMediaProject=<projectUUID>` (required, so the destructive step is scoped to an explicitly
    /// named disposable Project; nothing happens without it or when the Clip belongs to another Project):
    /// removes ONLY the canonical committed media file of that one ACTIVE Clip so the Editor derives
    /// it as unavailable, and never touches metadata. The Clip must exist, be active in its Project
    /// (found by identity across the durable Projects) and reference exactly its canonical path;
    /// otherwise nothing happens. Built on the same exact-match, symlink-refusing store primitive
    /// cleanup uses — no directory removal, no container wipe, no Baseline identity hard-coded.
    /// Runs once at startup before maintenance (12A / 12B never touch an active Clip either way).
    private func removeUITestActiveClipMediaIfRequested() async {
        guard arguments.contains(where: { $0.hasPrefix(UITestActiveClipMediaRemoval.clipKey) }) else { return }
        guard let store = projectMediaStore as? ProjectMediaStore else { return }
        let projects = (try? projectRepository.recentProjects()) ?? []
        let canonical: RelativeMediaPath, projectID: UUID, clipID: UUID, label: String
        switch UITestActiveClipMediaRemoval.decide(arguments: arguments, projects: projects) {
        case .refused(let reason, let clipLabel):
            MellowLog.app.error("UI-test unavailable fixture refused: clip=\(clipLabel, privacy: .public) \(String(describing: reason), privacy: .public)")
            return
        case .remove(let path, let owner, let id):
            (canonical, projectID, clipID, label) = (path, owner, id, String(id.uuidString.prefix(8)))
        }
        do {
            try await store.removeCommittedMedia(canonical, projectID: projectID, clipID: clipID)
            MellowLog.app.info("UI-test unavailable fixture applied: clip=\(label, privacy: .public) media removed, metadata kept active")
        } catch {
            MellowLog.app.error("UI-test unavailable fixture failed: clip=\(label, privacy: .public) \(String(describing: error), privacy: .public)")
        }
    }

    /// Writes the recorded fixtures; awaited by the startup maintenance Task before its first step.
    private func writeUITestRecoveryFixtures() async {
        guard let store = projectMediaStore as? ProjectMediaStore else { return }
        for (_, path) in uiTestRecoveryFixtures { try? await store.debugWriteFixture(relativePath: path) }
    }

    private func publishUITestRecoverySummary(_ report: ProjectStartupRecoveryReport) {
        guard arguments.contains("-uiTestCleanupDiagnostics") else { return }
        let fixtures = uiTestRecoveryFixtures
        guard let store = projectMediaStore as? ProjectMediaStore else { return }
        Task { @MainActor [weak self] in
            var parts = ["recovery ws=\(report.workspacesRemoved) dirs=\(report.orphanProjectDirsRemoved) media=\(report.orphanMediaRemoved) referenced=\(report.preservedReferenced) noncanonical=\(report.noncanonicalPreserved) failures=\(report.workspaceFailures + report.orphanProjectDirFailures + report.orphanMediaFailures)"]
            for (label, path) in fixtures {
                let exists = await store.debugFixtureExists(relativePath: path)
                parts.append("\(label)=\(exists ? "present" : "absent")")
            }
            self?.uiTestRecoverySummary = parts.joined(separator: " ")
        }
    }

    #endif

    /// The Phase 6 import services for Select Clips and Editor Add / Replace (ADR-050 050-C / 050-D): the real selection preflight and the internal
    /// attempt coordinator over the shared repository, media store and lifecycle gate; C1 / C2 / C3 / CR read the
    /// Mellow-root volume (unknown capacity fails closed).
    static func makeImportFlowServices(repository: any ProjectRepository, store: ProjectMediaStore, lifecycle: ProjectLifecycleOperationGate,
                                              normalizer: any WorkingMediaNormalizing = AVFoundationWorkingMediaNormalizer()) -> ImportFlowServices {
        ImportFlowServices(
            store: store,
            preflight: ImportSelectionPreflight(inspector: AVAssetImportSourceInspector()),
            attempts: ImportAttemptCoordinator(repository: repository, mediaStore: store, normalizer: normalizer, lifecycle: lifecycle,
                                               capacity: { await store.rootUsableCapacity() }))
    }

    #if DEBUG
    private static func makeUITestSelectionScript(arguments: [String], key: String = "-uiTestMediaSelection=") async -> FakeProjectMediaSelector.Script {
        let mode = arguments.first { $0.hasPrefix(key) }?
            .replacingOccurrences(of: key, with: "") ?? "cancel"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UITestFixtures", isDirectory: true)
        func fixture(_ name: String, seconds: Double, fps: Int32 = 30) async -> URL? {
            let url = directory.appendingPathComponent(name).appendingPathExtension("mov")
            do { try await FixtureVideoWriter.write(to: url, seconds: seconds, fps: fps); return url } catch { return nil }
        }
        switch mode {
        case "normalized":   // one 60 fps item: normalization-required (Phase 6 preparation)
            return await fixture("norm-a", seconds: 2, fps: 60).map { .fixtures([$0]) } ?? .fail
        case "mixed":        // ready + two normalization items (2/2 position)
            if let a = await fixture("ready-a", seconds: 2), let b = await fixture("norm-a", seconds: 2, fps: 60),
               let c = await fixture("norm-b", seconds: 1.5, fps: 60) { return .fixtures([a, b, c]) }
            return .fail
        case "short":        // a single 0.5 s item: below the 1.0 s minimum
            return await fixture("short", seconds: 0.5).map { .fixtures([$0]) } ?? .fail
        case "shortAndReady": // a short item is excluded; the ready one is created, then the notice
            if let a = await fixture("short", seconds: 0.5), let b = await fixture("ready-a", seconds: 2) { return .fixtures([a, b]) }
            return .fail
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
/// UI-test double: the first `failures` `recentProjects()` lookups throw; everything else forwards.
@MainActor
private final class LookupFailingProjectRepository: ProjectRepository {
    private let inner: any ProjectRepository
    private var remainingFailures: Int
    struct LookupFailure: Error {}
    init(inner: any ProjectRepository, failures: Int) { self.inner = inner; remainingFailures = failures }
    func create(_ project: VlogProject) throws { try inner.create(project) }
    func project(id: UUID) throws -> VlogProject? { try inner.project(id: id) }
    func recentProjects() throws -> [VlogProject] {
        if remainingFailures > 0 { remainingFailures -= 1; throw LookupFailure() }
        return try inner.recentProjects()
    }
    func update(_ project: VlogProject) throws { try inner.update(project) }
    func finalizeDeletedClip(projectID: UUID, clipID: UUID) throws { try inner.finalizeDeletedClip(projectID: projectID, clipID: clipID) }
    func deleteProject(id: UUID) throws { try inner.deleteProject(id: id) }
    func replaceProject(previousID: UUID, with project: VlogProject) throws { try inner.replaceProject(previousID: previousID, with: project) }
    func observePersistedProject(id: UUID) -> ObservedProjectRecord { inner.observePersistedProject(id: id) }
    func observePersistedState(for expectation: ProjectSaveExpectation) -> PersistedStateObservation { inner.observePersistedState(for: expectation) }
    func observeCurrentProjectID() -> ObservedCurrentProject { inner.observeCurrentProjectID() }
}

/// UI-test double: forwards everything; a post-save observation reports every Project unreadable. It rewrites
/// EVERY `observePersistedState` call, so Select Clips under this seam would also see unverifiable saves.
@MainActor
private final class UnverifiedSaveProjectRepository: ProjectRepository {
    private let inner: any ProjectRepository
    init(inner: any ProjectRepository) { self.inner = inner }
    func create(_ project: VlogProject) throws { try inner.create(project) }
    func project(id: UUID) throws -> VlogProject? { try inner.project(id: id) }
    func recentProjects() throws -> [VlogProject] { try inner.recentProjects() }
    func update(_ project: VlogProject) throws { try inner.update(project) }
    func finalizeDeletedClip(projectID: UUID, clipID: UUID) throws { try inner.finalizeDeletedClip(projectID: projectID, clipID: clipID) }
    func deleteProject(id: UUID) throws { try inner.deleteProject(id: id) }
    func replaceProject(previousID: UUID, with project: VlogProject) throws { try inner.replaceProject(previousID: previousID, with: project) }
    func observePersistedProject(id: UUID) -> ObservedProjectRecord { inner.observePersistedProject(id: id) }
    func observePersistedState(for expectation: ProjectSaveExpectation) -> PersistedStateObservation {
        let observed = inner.observePersistedState(for: expectation)
        return PersistedStateObservation(projects: observed.projects.mapValues { _ in .unreadable }, createdIdentityHolders: observed.createdIdentityHolders)
    }
    func observeCurrentProjectID() -> ObservedCurrentProject { inner.observeCurrentProjectID() }
}

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
    func replaceProject(previousID: UUID, with project: VlogProject) throws { try inner.replaceProject(previousID: previousID, with: project) }
    func observePersistedProject(id: UUID) -> ObservedProjectRecord { inner.observePersistedProject(id: id) }
    func observePersistedState(for expectation: ProjectSaveExpectation) -> PersistedStateObservation { inner.observePersistedState(for: expectation) }
    func observeCurrentProjectID() -> ObservedCurrentProject { inner.observeCurrentProjectID() }
}
#endif

/// Used only if the thumbnail provider in use does not read Project media (a DEBUG fake): there is
/// then no active media consumer to wait for. The production `ClipThumbnailService` always gates.
private struct IdleProjectMediaConsumersFallback: ProjectMediaConsumerGating {
    func awaitIdle(for paths: Set<RelativeMediaPath>, timeout: Duration) async -> Bool { true }
}
