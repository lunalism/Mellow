import Foundation
import Observation
import OSLog

/// The Phase 6 import dependencies (Select Clips and Editor Add / Replace): the media store (workspace, excluded-source removal, workspace release),
/// the selection preflight and the internal single-attempt coordinator the Retry controller drives.
@MainActor
struct ImportFlowServices {
    let store: ProjectMediaStore
    let preflight: ImportSelectionPreflight
    let attempts: any ImportAttemptRunning
}

/// Presentation state for the Phase 5 Projects screen (ADR-034 semantics, ADR-035 destination,
/// ADR-036 two-action content).
///
/// A short decision surface: `새 프로젝트 시작` (always) and `기존 프로젝트 불러오기` (enabled only
/// while a saved Project exists). Saved-Project lookup policy stays in `ProjectCompositionCoordinator`;
/// this model only turns that answer into presentation state and delivers user intents to its owner.
///
/// STEP 5 is intent-only: the model never creates, deletes or replaces a Project and never touches
/// media. The confirmed new-project intent is handed to the owner, who (in a later slice) runs the
/// actual composition / Safe Atomic Replacement flow.
@Observable
@MainActor
final class ProjectsEntryModel {
    /// What the owner should do with a confirmed `새 프로젝트 시작`.
    enum NewProjectIntent: Equatable {
        /// No saved Project exists; nothing needs replacing.
        case fresh
        /// The user confirmed replacing the given saved Project.
        case replacingSaved(UUID)
    }

    /// Non-success outcome of a Select-Clips attempt, shown as one alert with a single `확인`; the user
    /// stays on the Projects screen. Media validation copy comes from `ProjectMediaValidationCopy`
    /// (shared with the Editor's Add Clips); save-outcome copy is ADR-050 050-D D8.5a P3 / P6 and the
    /// remaining Select Clips cases are the owner-approved copy of 2026-10-05.
    enum CompositionMessage: Equatable {
        /// Valid media that is not Phase-5-ready; the copy is reason-specific and never names the
        /// implementation (no roadmap phases, no HDR / transcoding / frame-rate terms).
        case requiresImportPreparation(Phase5ReadyVerdict.PreparationReason)
        case invalidMedia
        /// The Phase 5 commit-time final guard (unchanged copy).
        case insufficientStorage
        /// Copy admission (ADR-050 050-C C0 / C0a) refused an incoming file: ADR-042 R4 §4 acknowledgement.
        case importStorageInsufficient
        /// Before any save, the saved-Project state could not be read.
        case projectInspectionFailed
        /// The Project being replaced is gone or no longer current; nothing was created instead.
        case replacementTargetInvalidated
        /// Any other failure before the save attempt (workspace, transfer, materialization, metadata).
        case preparationFailed
        /// U1: the save returned but could not be confirmed (`committedUnverified`).
        case saveUnverified
        /// U2: the save threw and nothing could be confirmed (`indeterminate`).
        case saveIndeterminate
        /// P6: the save threw and the prior state is confirmed (`priorConfirmed`) — acknowledgement only. (Retired from
        /// Select Clips by the Phase 6 path, where `priorConfirmed` is retried under D7a; kept for the legacy coordinator.)
        case notSaved
        /// The consolidated exclusion notice or single-candidate rejection (ADR-042 R2–R4, ADR-043 R1, ADR-044 R1).
        case selectionNotice(ImportSelectionNotice)
        /// D7b §1: a retained source became invalid before a Retry.
        case sourceUnavailableForRetry
        /// D7a §5 U3: restoration / cleanup could not be verified (not committed); no Retry.
        case cleanupUnresolved

        var title: String {
            switch self {
            case .requiresImportPreparation(let reason): return ProjectMediaValidationCopy.preparationTitle(reason)
            case .invalidMedia: return ProjectMediaValidationCopy.invalidMediaTitle
            case .insufficientStorage, .importStorageInsufficient: return ProjectMediaValidationCopy.insufficientStorageTitle
            case .projectInspectionFailed: return "프로젝트를 확인하지 못했어요"
            case .replacementTargetInvalidated: return "프로젝트를 교체하지 못했어요"
            case .preparationFailed: return "영상을 준비하지 못했어요"
            case .saveUnverified: return "저장 확인이 필요해요"
            case .saveIndeterminate: return "저장 결과를 확인하지 못했어요"
            case .notSaved: return "프로젝트를 만들지 못했어요"
            case .selectionNotice(let notice): return notice.title
            case .sourceUnavailableForRetry: return "영상을 다시 선택해주세요"
            case .cleanupUnresolved: return "영상을 준비하지 못했어요"
            }
        }
        var message: String {
            switch self {
            case .requiresImportPreparation(let reason): return ProjectMediaValidationCopy.preparationMessage(reason)
            case .invalidMedia: return ProjectMediaValidationCopy.invalidMediaMessage
            case .insufficientStorage: return ProjectMediaValidationCopy.insufficientStorageMessage
            case .importStorageInsufficient: return ProjectMediaValidationCopy.importStorageInsufficientMessage
            case .projectInspectionFailed: return "프로젝트 화면에서 다시 확인해주세요."
            case .replacementTargetInvalidated: return "교체하려던 프로젝트를 찾을 수 없어요."
            case .preparationFailed: return "영상을 다시 선택해주세요."
            case .saveUnverified: return "새 프로젝트는 저장되었지만 지금은 확인하지 못했어요. 프로젝트 화면에서 다시 확인해주세요."
            case .saveIndeterminate: return "새 프로젝트가 만들어졌는지 지금은 알 수 없어요. 다시 만들기 전에 프로젝트 화면에서 확인해주세요."
            case .notSaved: return "새 프로젝트가 저장되지 않았어요."
            case .selectionNotice(let notice): return notice.message
            case .sourceUnavailableForRetry: return "선택한 영상을 더 이상 사용할 수 없어요."
            case .cleanupUnresolved: return "프로젝트에 변경사항이 저장되지 않았어요. 영상을 다시 선택해주세요."
            }
        }
    }

    /// Result of the last saved-Project lookup. A failed lookup is `unknown` — never "no saved Project"
    /// (ADR-050 050-D D8.5a P5): creating and opening stay disabled until a later lookup succeeds.
    enum SavedProjectLookup: Equatable {
        /// No lookup has run yet; actions stay disabled until the first one succeeds.
        case notLoaded
        /// The lookup succeeded: the saved Project's ID, or nil when there is none.
        case loaded(UUID?)
        case unknown
    }

    /// Copy for the `unknown` lookup state (owner-approved 2026-10-05; action name accepted in D8.5a P5).
    enum UnknownLookupCopy {
        static let title = "프로젝트를 불러오지 못했어요"
        static let message = "저장된 프로젝트를 확인할 수 없어요. 다시 불러와주세요."
        static let reloadAction = "다시 불러오기"
    }

    /// Refreshed by `load()`; never mutated by intents. The screen shows no Project metadata (ADR-036),
    /// so the lookup result alone is the whole state.
    private(set) var lookup: SavedProjectLookup = .notLoaded
    /// True while the ADR-034 replacement confirmation is on screen.
    var isReplacementConfirmationPresented = false
    /// True from picker presentation until the operation reaches a terminal state (including while it waits for an
    /// explicit Retry). Back is hidden meanwhile (D7b §4).
    var isComposing: Bool { isSelecting || importPresenter.isActive }
    private var isSelecting = false
    var compositionMessage: CompositionMessage?
    /// The shared Phase 6 operation state (sheet, Retry, cancellation, route removal).
    let importPresenter = ImportOperationPresenter()
    /// Non-nil while the Blocking Preparation Sheet is shown (only when the Accepted Set has normalization items).
    var preparation: ImportPreparationProgress? { importPresenter.preparation }
    /// True after `취소` on the sheet until the attempt's own outcome processing finished.
    var isCancellingPreparation: Bool { importPresenter.isCancellingPreparation }
    /// An operation waiting for an explicit `다시 시도` / `취소`.
    var retryPrompt: ImportRetryPrompt? {
        get { importPresenter.retryPrompt }
        set { importPresenter.retryPrompt = newValue }
    }
    /// A confirmed new Project whose navigation waits for the exclusion notice to be acknowledged.
    private var pendingCommittedProjectID: UUID?

    private let composition: ProjectCompositionCoordinator
    private let importServices: ImportFlowServices?
    private let routeProbe: () -> () -> Bool
    private let mediaStore: any ProjectMediaStoring
    private let mediaSelector: any ProjectMediaSelecting
    /// Pre-copy admission gate handed to the selector (same policy instance the coordinator uses).
    private let storageGate: any ProjectStorageGating
    private let onContinueEditing: (UUID) -> Void
    private let onNewProject: (NewProjectIntent) -> Void
    private let onProjectCommitted: (UUID) -> Void

    init(
        composition: ProjectCompositionCoordinator,
        mediaStore: any ProjectMediaStoring,
        mediaSelector: any ProjectMediaSelecting,
        storageGate: any ProjectStorageGating,
        importServices: ImportFlowServices? = nil,
        routeProbe: @escaping () -> () -> Bool = { { true } },
        onContinueEditing: @escaping (UUID) -> Void,
        onNewProject: @escaping (NewProjectIntent) -> Void = { _ in },
        onProjectCommitted: @escaping (UUID) -> Void
    ) {
        self.composition = composition
        self.importServices = importServices
        self.routeProbe = routeProbe
        self.mediaStore = mediaStore
        self.mediaSelector = mediaSelector
        self.storageGate = storageGate
        self.onContinueEditing = onContinueEditing
        self.onNewProject = onNewProject
        self.onProjectCommitted = onProjectCommitted
    }

    /// The current V1 saved Project's ID — only from a successful lookup.
    var savedProjectID: UUID? {
        if case .loaded(let id) = lookup { return id }
        return nil
    }
    var hasSavedProject: Bool { savedProjectID != nil }
    var isLookupUnknown: Bool { lookup == .unknown }
    /// `새 프로젝트 시작` needs a successful lookup (P5) and no composition in flight.
    var canStartNewProject: Bool {
        guard case .loaded = lookup else { return false }
        return !isComposing
    }

    /// Resolves the saved Project through the coordinator's read-only lookup. A lookup failure is
    /// `unknown` (logged), never "no saved Project"; it never creates anything and never retries by
    /// itself — `다시 불러오기` (`reload()`) is the explicit retry.
    func load() {
        do {
            lookup = .loaded(try composition.lastSavedProject()?.id)
            #if DEBUG
            MellowLog.app.info("Projects entry saved project: \(self.savedProjectID?.uuidString ?? "none", privacy: .public)")
            #endif
        } catch {
            let details = error as NSError
            MellowLog.app.error("Projects entry lookup failed: domain=\(details.domain, privacy: .public), code=\(details.code)")
            lookup = .unknown
        }
    }

    /// `다시 불러오기`: one explicit lookup attempt.
    func reload() {
        load()
    }

    /// `기존 프로젝트 불러오기`: delivers the exact saved Project ID as the navigation identity.
    /// No-op without a successfully looked-up saved Project (the control is disabled then).
    func continueEditing() {
        // D7b §4: no Editor while an import operation runs or waits (it may be replacing this very Project).
        guard !isComposing, let savedProjectID else { return }
        onContinueEditing(savedProjectID)
    }

    /// `새 프로젝트 시작`: with a saved Project this first asks for replacement confirmation;
    /// without one the fresh Select-Clips flow starts immediately. Refused unless the last lookup
    /// succeeded.
    func requestNewProject() {
        guard canStartNewProject else { return }
        if hasSavedProject {
            isReplacementConfirmationPresented = true
        } else {
            onNewProject(.fresh)
            Task { await runSelectClips(.fresh) }
        }
    }

    /// `취소`: closes the confirmation and leaves the saved Project untouched.
    func cancelReplacement() {
        isReplacementConfirmationPresented = false
    }

    /// `새 프로젝트 만들기`: closes the confirmation, delivers the confirmed intent and starts the
    /// Select-Clips flow. The saved Project is not touched here — Safe Atomic Replacement happens in
    /// the coordinator only after the replacement Project is fully committed.
    func confirmReplacement() {
        isReplacementConfirmationPresented = false
        guard case .loaded = lookup else { return }
        let intent: NewProjectIntent = savedProjectID.map(NewProjectIntent.replacingSaved) ?? .fresh
        onNewProject(intent)
        Task { await runSelectClips(intent) }
    }

    /// Select Clips. With `importServices` (production and every DEBUG route since 2026-10-06) this is the Phase 6
    /// path; without it the legacy Phase 5 composition path runs, which is now reachable only from its existing tests.
    func runSelectClips(_ intent: NewProjectIntent) async {
        if let importServices { await runPhase6SelectClips(intent, services: importServices) } else { await runLegacySelectClips(intent) }
    }

    /// Phase 6 Select Clips (ADR-042 R2–R4, ADR-043 R1, ADR-044 R1, ADR-046, ADR-050 050-C / 050-D D7a / D7b / D8.5b):
    /// workspace → system selection with C0 / C0a → preflight with per-item exclusion (inclusive 1.0–5.0 s) → the
    /// excluded sources are removed → `ImportRetryController` (C1, preparation with C2, commit with C3, Retry with
    /// CR) → presentation. The legacy commit-time final guard does not run on this path (D7b §3). Cancel goes
    /// through the controller, which waits for the attempt's safe outcome processing.
    private func runPhase6SelectClips(_ intent: NewProjectIntent, services: ImportFlowServices) async {
        guard !isComposing else { return }
        isSelecting = true
        let isRouteLive = routeProbe()
        defer { isSelecting = false }
        guard let workspace = try? await services.store.beginWorkspace() else {
            present(.preparationFailed, isRouteLive)
            return
        }
        let sources: [SelectedVideoSource]
        switch await mediaSelector.selectVideos(into: workspace, store: services.store, admission: storageGate) {
        case .cancelled:
            await services.store.discard(workspace)
            return
        case .insufficientStorage:
            await services.store.discard(workspace)
            present(.importStorageInsufficient, isRouteLive)
            return
        case .failed:
            await services.store.discard(workspace)
            present(.preparationFailed, isRouteLive)
            return
        case .selected(let selected):
            sources = selected
        }
        guard !sources.isEmpty else {
            await services.store.discard(workspace)
            return
        }

        // Preflight: per-item classification in selection order (a single chosen item is a single-candidate operation).
        let candidates = sources.map { ImportCandidate(url: $0.url) }
        let preflight: ImportSelectionPreflightOutcome
        do {
            preflight = try await services.preflight.run(candidates, context: candidates.count == 1 ? .singleCandidate : .multipleItems)
        } catch {
            MellowLog.app.error("Select Clips preflight failed: \(String(describing: error), privacy: .public)")
            await services.store.discard(workspace)
            present(.preparationFailed, isRouteLive)
            return
        }
        // Excluded items never enter the Accepted Set; their Mellow-owned copies go before C1 (050-C).
        for excluded in preflight.excluded where await !services.store.removeWorkspaceFile(excluded.candidate.url, in: workspace) {
            MellowLog.app.error("Select Clips excluded source could not be removed; it stays with the workspace")
        }
        guard !preflight.accepted.isEmpty else {
            await services.store.discard(workspace)
            if let notice = preflight.notice { present(.selectionNotice(notice), isRouteLive) }
            return
        }
        var plans: [ImportCandidateID: WorkingMediaNormalizationPlan] = [:]
        do {
            for item in preflight.accepted where item.preparationPath.normalization != nil { plans[item.candidate.id] = try WorkingMediaPlanBuilder.plan(for: item) }
        } catch {
            await services.store.discard(workspace)
            present(.preparationFailed, isRouteLive)
            return
        }
        let target: ImportAttemptTarget
        switch intent {
        case .fresh: target = .newProject
        case .replacingSaved(let id): target = .replacingSaved(previousID: id)
        }
        let request = ImportAttemptRequest(accepted: preflight.accepted, plans: plans, workspace: workspace, target: target)
        let normalizationIDs = preflight.accepted.filter { $0.preparationPath.normalization != nil }.map(\.candidate.id)
        let notice = preflight.notice, replacing = target != .newProject
        isSelecting = false
        // Ownership of the workspace passes to the controller here.
        await importPresenter.run(
            controller: ImportRetryController(coordinator: services.attempts, workspaces: services.store, request: request),
            normalizationIDs: normalizationIDs, isRouteLive: isRouteLive,
            onSettle: { [weak self] settlement, live in self?.present(settlement, notice: notice, replacing: replacing, live: live) })
    }

    /// `다시 시도` on a Retry prompt.
    func retryPreparation() { importPresenter.retry() }

    /// `취소` on the sheet or on a Retry prompt (through the controller; waits for the attempt's safe processing).
    func cancelPreparation() { importPresenter.cancel() }

    /// The router reports that a Projects route left the path (D7b §4 clarification; the presenter checks identity).
    func originatingRouteRemoved() { importPresenter.originatingRouteRemoved() }

    /// Select Clips copy for a terminal settlement. Late presentation on a removed route is suppressed (D7b §4);
    /// classification and cleanup already happened.
    private func present(_ settlement: ImportOperationSettlement, notice: ImportSelectionNotice?, replacing: Bool, live: Bool) {
        switch settlement {
        case .succeeded(let commit):
            load()
            guard live else { return }
            if let notice {
                pendingCommittedProjectID = commit.project.id
                compositionMessage = .selectionNotice(notice)
            } else {
                onProjectCommitted(commit.project.id)
            }
        case .uncertain(let outcome):
            load()
            if case .committedUnverified = outcome { present(.saveUnverified, live) } else { present(.saveIndeterminate, live) }
        case .retainedUnresolved:
            present(.cleanupUnresolved, live)
        case .ended(let reason, let result, let isRetryAttempt):
            presentEnd(reason, result: result, replacing: replacing, isRetryAttempt: isRetryAttempt, live: live)
        }
    }

    private func presentEnd(_ reason: ImportRetryIneligibility, result: ImportRetryResult, replacing: Bool, isRetryAttempt: Bool, live: Bool) {
        switch reason {
        case .cancelled:
            return   // a successful cancel closes silently (D7a §5)
        case .sourceInvalidated:
            // D7b §1: a retained source that is no longer usable for a Retry — at Retry admission or during the Retry
            // attempt (the materialize recheck) — uses the approved copy; the first attempt keeps D8.5b's copy.
            if case .sourceInvalid = result { present(.sourceUnavailableForRetry, live) }
            else if isRetryAttempt { present(.sourceUnavailableForRetry, live) }
            else { present(.preparationFailed, live) }
        case .targetInvalidated:
            load()
            if case .attempted(.refused(.target(.unreadable))) = result {
                present(.projectInspectionFailed, live)        // first admission: D8.5b
            } else if replacing {
                present(.replacementTargetInvalidated, live)   // D8.5b / D7b §1
            } else {
                present(.preparationFailed, live)              // new-Project identity: no dedicated copy (D7b open item)
            }
        case .initialAdmissionRefusal:
            if case .attempted(.refused(.storage(let check))) = result, Self.isShortage(check) {
                present(.importStorageInsufficient, live)     // C1 shortage: R4 §4
            } else {
                present(.preparationFailed, live)             // estimate / state defect: never a shortage
            }
        case .nonRetryableFailure, .retryAdmissionDefect, .cleanupUnresolved, .notStarted, .operationEnded, .completed, .uncertainPersistence:
            present(.preparationFailed, live)
        }
    }

    private static func isShortage(_ check: ImportBoundaryCheckResult) -> Bool {
        switch check.outcome {
        case .insufficient, .capacityUnknown: return true
        case .sufficient, .invalidEstimate, .invalidBoundaryState: return false
        }
    }

    private func present(_ message: CompositionMessage, _ live: Bool) {
        if live { compositionMessage = message }
    }

    private func present(_ message: CompositionMessage, _ isRouteLive: () -> Bool) {
        present(message, isRouteLive())
    }

    /// The alert's `확인`. After a confirmed save with an exclusion notice, navigation happens once it is acknowledged.
    func dismissCompositionMessage() {
        compositionMessage = nil
        if let projectID = pendingCommittedProjectID {
            pendingCommittedProjectID = nil
            onProjectCommitted(projectID)
        }
    }

    /// Legacy Select Clips (ADR-033 / ADR-034 §2): workspace → system selection → all-or-nothing composition
    /// → Editor. Picker cancel is a silent, normal result; every other non-success outcome shows one
    /// message and stays on this screen. After an inspection failure, an invalidated replacement target or
    /// a non-`completed` save outcome the saved-Project lookup runs exactly once more (D8.5a P5 / D8.5b); a
    /// failed lookup becomes `unknown`, and composition is never retried automatically. App
    /// launch, opening this screen and presenting the picker never create a Project.
    private func runLegacySelectClips(_ intent: NewProjectIntent) async {
        guard !isComposing else { return }
        isSelecting = true
        defer { isSelecting = false }
        guard let workspace = try? await mediaStore.beginWorkspace() else {
            compositionMessage = .preparationFailed
            return
        }
        switch await mediaSelector.selectVideos(into: workspace, store: mediaStore, admission: storageGate) {
        case .cancelled:
            await mediaStore.discard(workspace)
        case .insufficientStorage:
            // Refused before any further copy; earlier adopted files of this operation go with the workspace.
            await mediaStore.discard(workspace)
            compositionMessage = .importStorageInsufficient
        case .failed:
            await mediaStore.discard(workspace)
            compositionMessage = .preparationFailed
        case .selected(let sources):
            let coordinatorIntent: ProjectCompositionCoordinator.Intent
            switch intent {
            case .fresh: coordinatorIntent = .fresh
            case .replacingSaved(let id): coordinatorIntent = .replacingSaved(id)
            }
            switch await composition.compose(coordinatorIntent, sources: sources, workspace: workspace) {
            case .committed(let projectID):
                load()
                onProjectCommitted(projectID)
            case .requiresImportPreparation(let reason):
                compositionMessage = .requiresImportPreparation(reason)
            case .invalidMedia:
                compositionMessage = .invalidMedia
            case .insufficientStorage:
                compositionMessage = .insufficientStorage
            case .projectInspectionFailed:
                load()
                compositionMessage = .projectInspectionFailed
            case .replacementTargetInvalidated:
                load()
                compositionMessage = .replacementTargetInvalidated
            case .preparationFailed:
                compositionMessage = .preparationFailed
            case .committedUnverified:
                load()
                compositionMessage = .saveUnverified
            case .indeterminate:
                load()
                compositionMessage = .saveIndeterminate
            case .priorConfirmed:
                load()
                compositionMessage = .notSaved
            }
        }
    }
}

/// The one user-facing copy for Phase-5 media validation outcomes, shared by Select Clips (Projects
/// screen) and Add Clips (Editor). Reason-specific, never naming the implementation (no roadmap
/// phases, no HDR / transcoding / frame-rate terms). The 5-second Clip maximum is a Mellow product
/// rule, so its copy states the rule plainly rather than as a temporary limitation; the other
/// preparation reasons stay phrased as "not usable right now" because later import phases may
/// prepare such media.
enum ProjectMediaValidationCopy {
    static func preparationTitle(_ reason: Phase5ReadyVerdict.PreparationReason) -> String {
        switch reason {
        case .tooLong: return "영상이 너무 길어요"
        case .orientation: return "세로 영상을 선택해주세요"
        case .highDynamicRange, .resolution, .frameRate: return "이 영상은 바로 사용할 수 없어요"
        }
    }

    static func preparationMessage(_ reason: Phase5ReadyVerdict.PreparationReason) -> String {
        switch reason {
        case .tooLong: return "5초 이하의 영상을 선택해주세요."
        case .orientation: return "현재 프로젝트에서는 세로 영상을 바로 사용할 수 있어요."
        case .highDynamicRange, .resolution, .frameRate: return "다른 영상을 선택해주세요."
        }
    }

    static let invalidMediaTitle = "영상을 열 수 없어요"
    static let invalidMediaMessage = "선택한 영상을 읽을 수 없어요. 다른 영상을 골라 주세요."
    static let insufficientStorageTitle = "저장 공간이 부족해요"
    static let insufficientStorageMessage = "공간을 확보한 뒤 다시 시도해 주세요."
    /// ADR-042 Revision 4 §4 (C0 / C0a / C1 initial storage refusal); the action stays `확인`.
    static let importStorageInsufficientMessage = "영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요."
}
