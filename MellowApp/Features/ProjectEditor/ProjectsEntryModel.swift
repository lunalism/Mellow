import Foundation
import Observation
import OSLog

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

    /// Non-success outcome of a Select-Clips attempt, shown as a small recoverable alert. Nothing was
    /// created and any saved Project is untouched; the user may dismiss and try again. Media
    /// validation copy comes from `ProjectMediaValidationCopy` (shared with the Editor's Add Clips).
    enum CompositionMessage: Equatable {
        /// Valid media that is not Phase-5-ready; the copy is reason-specific and never names the
        /// implementation (no roadmap phases, no HDR / transcoding / frame-rate terms).
        case requiresImportPreparation(Phase5ReadyVerdict.PreparationReason)
        case invalidMedia
        case insufficientStorage
        case failed

        var title: String {
            switch self {
            case .requiresImportPreparation(let reason): return ProjectMediaValidationCopy.preparationTitle(reason)
            case .invalidMedia: return ProjectMediaValidationCopy.invalidMediaTitle
            case .insufficientStorage: return ProjectMediaValidationCopy.insufficientStorageTitle
            case .failed: return "프로젝트를 만들지 못했어요"
            }
        }
        var message: String {
            switch self {
            case .requiresImportPreparation(let reason): return ProjectMediaValidationCopy.preparationMessage(reason)
            case .invalidMedia: return ProjectMediaValidationCopy.invalidMediaMessage
            case .insufficientStorage: return ProjectMediaValidationCopy.insufficientStorageMessage
            case .failed: return "잠시 후 다시 시도해 주세요. 저장된 프로젝트는 그대로 있어요."
            }
        }
    }

    /// The current V1 saved Project's ID, or nil. Refreshed by `load()`; never mutated by intents.
    /// The screen shows no Project metadata (ADR-036), so the ID alone is the whole state.
    private(set) var savedProjectID: UUID?
    /// True while the ADR-034 replacement confirmation is on screen.
    var isReplacementConfirmationPresented = false
    /// True from picker presentation until the composition outcome is known.
    private(set) var isComposing = false
    var compositionMessage: CompositionMessage?

    private let composition: ProjectCompositionCoordinator
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
        onContinueEditing: @escaping (UUID) -> Void,
        onNewProject: @escaping (NewProjectIntent) -> Void = { _ in },
        onProjectCommitted: @escaping (UUID) -> Void
    ) {
        self.composition = composition
        self.mediaStore = mediaStore
        self.mediaSelector = mediaSelector
        self.storageGate = storageGate
        self.onContinueEditing = onContinueEditing
        self.onNewProject = onNewProject
        self.onProjectCommitted = onProjectCommitted
    }

    var hasSavedProject: Bool { savedProjectID != nil }

    /// Resolves the saved Project through the coordinator's read-only lookup. A lookup failure is
    /// treated as "no saved Project" for presentation and logged; it never creates one.
    func load() {
        do {
            savedProjectID = try composition.lastSavedProject()?.id
            #if DEBUG
            MellowLog.app.info("Projects entry saved project: \(self.savedProjectID?.uuidString ?? "none", privacy: .public)")
            #endif
        } catch {
            let details = error as NSError
            MellowLog.app.error("Projects entry lookup failed: domain=\(details.domain, privacy: .public), code=\(details.code)")
            savedProjectID = nil
        }
    }

    /// `기존 프로젝트 불러오기`: delivers the exact saved Project ID as the navigation identity.
    /// No-op without a saved Project (the control is disabled then).
    func continueEditing() {
        guard let savedProjectID else { return }
        onContinueEditing(savedProjectID)
    }

    /// `새 프로젝트 시작`: with a saved Project this first asks for replacement confirmation;
    /// without one the fresh Select-Clips flow starts immediately.
    func requestNewProject() {
        guard !isComposing else { return }
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
        let intent: NewProjectIntent = savedProjectID.map(NewProjectIntent.replacingSaved) ?? .fresh
        onNewProject(intent)
        Task { await runSelectClips(intent) }
    }

    /// Select Clips (ADR-033 / ADR-034 §2): workspace → system selection → all-or-nothing composition
    /// → Editor. Picker cancel is a silent, normal result; every other non-success outcome shows one
    /// recoverable message. App launch, opening this screen and presenting the picker never create a
    /// Project.
    func runSelectClips(_ intent: NewProjectIntent) async {
        guard !isComposing else { return }
        isComposing = true
        defer { isComposing = false }
        guard let workspace = try? await mediaStore.beginWorkspace() else {
            compositionMessage = .failed
            return
        }
        switch await mediaSelector.selectVideos(into: workspace, store: mediaStore, admission: storageGate) {
        case .cancelled:
            await mediaStore.discard(workspace)
        case .insufficientStorage:
            // Refused before any further copy; earlier adopted files of this operation go with the workspace.
            await mediaStore.discard(workspace)
            compositionMessage = .insufficientStorage
        case .failed:
            await mediaStore.discard(workspace)
            compositionMessage = .failed
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
            case .failed:
                compositionMessage = .failed
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
}
