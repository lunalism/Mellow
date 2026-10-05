import CoreGraphics
import Foundation
import Observation

/// Per-clip thumbnail presentation state. Presentation only — never persisted. Derived-data failure
/// (`.unavailable`) and structural media unavailability (`.mediaUnavailable`, ADR-040) are distinct
/// states: the first is "the file is there but no frame could be made", the second is "there is no
/// file to read" and it is never requested again while it holds.
enum ClipThumbnailPresentation: Equatable {
    case loading
    case ready(CGImage)
    /// Generation failed (unreadable / no frame / generation error) for media that structurally
    /// exists. The Clip keeps its slot; the view shows a calm neutral placeholder.
    case unavailable
    /// The Clip's Project-owned media is missing (`ClipAvailability.unavailable`). Derived from the
    /// availability state, not from a thumbnail result; no thumbnail is requested for it.
    case mediaUnavailable

    static func == (lhs: ClipThumbnailPresentation, rhs: ClipThumbnailPresentation) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading), (.unavailable, .unavailable), (.mediaUnavailable, .mediaUnavailable): return true
        case (.ready(let a), .ready(let b)): return a === b
        default: return false
        }
    }
}

/// Recoverable, dismissible outcome of an Editor mutation (ARCHITECTURE §57). The Editor still shows
/// the last confirmed state; nothing was published for the failed edit.
enum ProjectEditorMessage: Equatable {
    /// Undo / Redo could not even build the target state (before any save attempt).
    case undoFailed
    case redoFailed
    /// `priorConfirmed` after a thrown save of Reorder / Delete / Undo / Redo (owner decision 2026-10-05):
    /// acknowledgement only, never used for a successful save or an uncertain outcome.
    case changesNotSaved
    /// `priorConfirmed` after a thrown save of Add / Replace (ADR-050 050-D D8.5a P6): acknowledgement only.
    case addNotSaved
    case replaceNotSaved
    /// Clip acquisition (Add, ADR-037 — and Replace, ADR-040, which reuses the SAME preparation
    /// outcomes and copy): the typed outcomes of Select Clips, one message per operation.
    case addRequiresImportPreparation(Phase5ReadyVerdict.PreparationReason)
    case addInvalidMedia
    case addInsufficientStorage
    case addFailed
    /// Replace (ADR-040) generic failure: the original unavailable Clip is exactly as it was.
    case replaceFailed

    var title: String {
        switch self {
        case .undoFailed: return "실행 취소하지 못했어요."
        case .redoFailed: return "다시 실행하지 못했어요."
        case .changesNotSaved: return "변경사항을 저장하지 못했어요"
        case .addNotSaved: return "영상을 추가하지 못했어요"
        case .replaceNotSaved: return "클립을 교체하지 못했어요"
        case .addRequiresImportPreparation(let reason): return ProjectMediaValidationCopy.preparationTitle(reason)
        case .addInvalidMedia: return ProjectMediaValidationCopy.invalidMediaTitle
        case .addInsufficientStorage: return ProjectMediaValidationCopy.insufficientStorageTitle
        case .addFailed: return "클립을 추가하지 못했어요."
        case .replaceFailed: return "클립을 교체하지 못했어요"
        }
    }
    var message: String {
        switch self {
        case .addRequiresImportPreparation(let reason): return ProjectMediaValidationCopy.preparationMessage(reason)
        case .addInvalidMedia: return ProjectMediaValidationCopy.invalidMediaMessage
        case .addInsufficientStorage: return ProjectMediaValidationCopy.insufficientStorageMessage
        case .addFailed, .replaceFailed: return "다시 시도해주세요. 프로젝트는 그대로 있어요."
        case .changesNotSaved, .addNotSaved, .replaceNotSaved: return "프로젝트에 변경사항이 저장되지 않았어요."
        case .undoFailed, .redoFailed: return "다시 시도해주세요."
        }
    }
}

/// Why the Editor is locked and must be left for the Projects screen (ADR-050 050-D D8.5a P2 / P3 and the
/// owner's Editor decisions of 2026-10-05). While set, every mutation entry point is refused; there is no
/// automatic reload — the user returns to Projects and reopens through the gated load (empty history).
enum EditorReconciliation: Equatable {
    /// U1: the save returned but its result could not be confirmed (`committedUnverified`).
    case saveUnverified
    /// U2: the save threw and nothing could be confirmed (`indeterminate`).
    case saveIndeterminate
    /// Before any save: the stored Project differs from this Editor's state, or could not be read.
    case recheckRequired
    /// Before any save: the Project row is gone.
    case projectMissing

    static let returnAction = "프로젝트 화면으로"

    var title: String {
        switch self {
        case .saveUnverified: return "저장 확인이 필요해요"
        case .saveIndeterminate: return "저장 결과를 확인하지 못했어요"
        case .recheckRequired: return "프로젝트를 다시 확인해주세요"
        case .projectMissing: return "프로젝트를 찾을 수 없어요"
        }
    }

    var message: String {
        switch self {
        case .saveUnverified: return "변경사항은 저장되었지만 지금은 확인하지 못했어요. 프로젝트 화면에서 다시 열어 확인해주세요."
        case .saveIndeterminate: return "변경사항이 저장되었는지 지금은 알 수 없어요. 프로젝트 화면에서 다시 열어 확인해주세요."
        case .recheckRequired: return "프로젝트 화면에서 다시 열어 확인해주세요."
        case .projectMissing: return "프로젝트 화면에서 다시 확인해주세요."
        }
    }
}

/// The acquisition boundary the Editor's Add Clips (ADR-037) and Replace (ADR-040) use: the same
/// selector / store / gate / validator chain as Select Clips, scoped to the loaded Project. Absent
/// (nil) only in unit tests that never acquire.
@MainActor
struct EditorClipAcquisition {
    let mediaStore: any ProjectMediaStoring
    let mediaSelector: any ProjectMediaSelecting
    let storageGate: any ProjectStorageGating
    let appender: ProjectClipAppendCoordinator
    /// The shared Project lifecycle gate (ADR-039): target revalidation, materialisation and the commit
    /// run inside it. Must be the app's single instance, the same one cleanup / composition use.
    let lifecycle: ProjectLifecycleOperationGate
    #if DEBUG
    /// UI-test seam (`-uiTestCrashAfterAddMaterialize`): runs right after the batch is materialised
    /// and before it is committed — the STEP 12B crash window. Nil in every production path.
    var debugAfterMaterialize: (@MainActor () -> Void)? = nil
    #endif
}

/// The persistent, editor-relevant state one edit changes (ADR-038): the durable clip sets and the
/// selection. Deliberately excludes transient state (thumbnails, drag preview, messages, commit
/// flags, the history itself) and the Project's identity / timestamps — a restore re-applies these
/// sets to the *current* Project with a fresh `updatedAt`, never an old one.
struct EditorEditState: Equatable, Sendable {
    let clips: [VlogClip]
    let deletedClips: [VlogClip]
    let selectedClipID: UUID?

    init(project: VlogProject, selectedClipID: UUID?) {
        clips = project.clips
        deletedClips = project.deletedClips
        self.selectedClipID = selectedClipID
    }
}

/// One successful, persisted Editor edit in the session history (ADR-038): the state before and
/// after, plus what kind of edit it was (for the Undo / Redo hints). Value-only, metadata-only —
/// no media bytes, no images, no closures — so an unbounded session history is cheap.
struct EditorHistoryEntry: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case reorder
        case delete
        case add
        /// ADR-040: one unavailable Clip replaced by one NEW Clip in the same logical slot.
        case replace

        /// Short Korean description used in accessibility hints ("클립 삭제 실행 취소").
        var description: String {
            switch self {
            case .reorder: return "클립 순서 변경"
            case .delete: return "클립 삭제"
            case .add: return "클립 추가"
            case .replace: return "클립 교체"
            }
        }
    }

    let kind: Kind
    let before: EditorEditState
    let after: EditorEditState
}

/// Which acquisition transaction owns the picker right now (ADR-037 Add / ADR-040 Replace). One at a
/// time: the two flows share one selector session and one commit path, never two picker presentations.
enum EditorClipAcquisitionMode: Equatable, Sendable {
    case add
    case replace(UUID)
}

/// Presentation state for the Phase 5 Project Editor (ADR-034).
///
/// Holds one loaded Project, its ordered clips, total duration, the selected clip, the per-clip
/// thumbnail presentation and the per-clip derived media availability. STEP 8 added asynchronous
/// thumbnail loading with identity-based stale-result protection; STEP 9 added clip reorder (long
/// press + drag and the non-drag Move Earlier / Move Later actions) with autosave; STEP 10 adds
/// logical Clip delete (ADR-021, durable pending deletion) and the session-local Undo / Redo history
/// (ADR-038); STEP 11 Add Clips (ADR-037); STEP 13 derived unavailability + user-driven Replace
/// (ADR-040). There is still no playback.
///
/// Reorder state is deliberately small and explicit: `project` is the committed state, `previewOrder`
/// the temporary order shown while a drag is in flight, `draggingClipID` the lifted Clip. Nothing is
/// written until the drop; cancel simply drops the preview. Every mutation (reorder, delete, undo,
/// redo, add, replace) commits through the shared lifecycle gate and ONE inner commit path (ADR-050
/// 050-D D8.5a P1 / P7, accepted 2026-10-05): fresh prior read compared with this Editor's state →
/// update expectation → save → fresh observation → classification. Nothing is published before the
/// outcome is `completed`; only then do the state and its single history transition change together.
@Observable
@MainActor
final class ProjectEditorModel {
    /// Point size of one timeline cell (compact 9:16); the pixel budget is derived from it and the
    /// display scale. Presentation constant only — it takes part in the request identity, nothing else.
    static let thumbnailPointSize = CGSize(width: 44, height: 78)

    /// The committed Project: always equal to what the repository last confirmed (or the loaded value).
    private(set) var project: VlogProject
    @ObservationIgnored private let repository: any ProjectRepository
    @ObservationIgnored private let thumbnails: any ClipThumbnailProviding
    @ObservationIgnored private let acquisition: EditorClipAcquisition?
    /// The app's single shared lifecycle gate (ADR-039); every Editor commit runs inside it.
    @ObservationIgnored private let lifecycle: ProjectLifecycleOperationGate
    /// Derived media availability (ADR-040). Nil (unit tests that never load) = every Clip available.
    @ObservationIgnored private let availabilityChecker: (any ClipAvailabilityChecking)?
    private(set) var selectedClipID: UUID?
    private(set) var thumbnailStates: [UUID: ClipThumbnailPresentation] = [:]
    /// Availability by Clip identity, evaluated on load and whenever the active set changes; never
    /// persisted. Entries are kept for Clips that left the active set (a pending Clip that Undo brings
    /// back is re-evaluated by the next load anyway). Absent = not yet evaluated = treated as available.
    private(set) var availabilityByClipID: [UUID: ClipAvailability] = [:]
    /// Identity of the availability evaluation in flight; a result from an older evaluation is stale.
    private var availabilityGeneration = 0
    /// Display scale of the active load; part of every current request identity. Nil while no load
    /// is active, which makes every late result stale.
    private var activeThumbnailScale: CGFloat?

    // MARK: Reorder state

    /// The Clip currently lifted by a long press, or nil when no reorder is in progress.
    private(set) var draggingClipID: UUID?
    /// Temporary logical order shown during the drag (Clip ids). Nil outside a drag. Never persisted
    /// as such — only the drop turns it into a committed order.
    private(set) var previewOrder: [UUID]?
    /// True from the moment an edit is requested until its outcome is applied — including the wait for
    /// the lifecycle gate, which is not guaranteed to be short. Every other mutation and drag is refused
    /// meanwhile, and leaving the Editor is disabled (`isNavigationLocked`).
    private(set) var isCommittingMutation = false
    /// Set when the Editor can no longer present its state as the saved one; never cleared by this model.
    private(set) var reconciliation: EditorReconciliation?
    /// Incremented once per successful reorder-mode activation — the haptic trigger and the only
    /// observable of the activation event.
    private(set) var reorderActivationCount = 0
    /// Recoverable autosave failure to present; the committed state has already been rolled back.
    var editorMessage: ProjectEditorMessage?
    #if DEBUG
    /// UI-test seam (`-uiTestEditorGateHold=<ms>`): awaited after the in-flight flag is set and before the gate
    /// is requested. Nil in every production path; absent from Release.
    @ObservationIgnored var debugBeforeEditGate: (@MainActor () async -> Void)?
    #endif

    // MARK: Session history (ADR-038)

    /// Chronological edit history of THIS Editor session: `undoStack.last` is the most recent
    /// successful edit, `redoStack.last` the most recently undone one. In memory only — a new model
    /// (reopened Editor, relaunch) starts empty while the durable Project stays as last autosaved.
    /// Unbounded for the session: entries hold clip metadata values only (no media, no images).
    private(set) var undoStack: [EditorHistoryEntry] = []
    private(set) var redoStack: [EditorHistoryEntry] = []

    /// Non-nil from the acquisition tap ("+" or `클립 교체`) until that transaction resolves (picker
    /// open, transferring, validating, materialising, committing). Every other mutation — and a
    /// second acquisition of either kind — is refused meanwhile, so two pickers can never be presented.
    private(set) var acquisitionMode: EditorClipAcquisitionMode?

    /// `lifecycle` must be the app's shared gate (the acquisition boundary carries the same instance). Unit
    /// tests that pass neither get a private gate in DEBUG only; Release requires the shared one.
    init(project: VlogProject, repository: any ProjectRepository, thumbnails: any ClipThumbnailProviding, acquisition: EditorClipAcquisition? = nil, availability: (any ClipAvailabilityChecking)? = nil, lifecycle: ProjectLifecycleOperationGate? = nil) {
        self.project = project
        self.repository = repository
        self.thumbnails = thumbnails
        self.acquisition = acquisition
        if let lifecycle, let acquisition {
            precondition(lifecycle === acquisition.lifecycle, "the Editor and its acquisition boundary must share one lifecycle gate")
        }
        #if DEBUG
        self.lifecycle = lifecycle ?? acquisition?.lifecycle ?? ProjectLifecycleOperationGate()
        #else
        guard let gate = lifecycle ?? acquisition?.lifecycle else { preconditionFailure("ProjectEditorModel needs the shared lifecycle gate") }
        self.lifecycle = gate
        #endif
        self.availabilityChecker = availability
        // Default selection: the first clip when the project has clips, otherwise none.
        self.selectedClipID = project.clips.first?.id
    }

    /// Clips in the order the timeline shows: the temporary preview order during a drag, otherwise
    /// the committed logical order (`VlogProject` keeps `clips` sorted by `sortOrder`).
    var orderedClips: [VlogClip] {
        guard let previewOrder else { return project.clips }
        let byID = Dictionary(uniqueKeysWithValues: project.clips.map { ($0.id, $0) })
        return previewOrder.compactMap { byID[$0] }
    }

    /// Committed logical order, unaffected by any drag preview.
    var committedClips: [VlogClip] { project.clips }

    /// True while any acquisition (Add or Replace) is in flight.
    var isAcquiringClips: Bool { acquisitionMode != nil }
    var isAddingClips: Bool { acquisitionMode == .add }
    var isReplacingClip: Bool {
        if case .replace = acquisitionMode { return true }
        return false
    }

    /// No mutation may start while another (including an acquisition) is in flight, a clip is lifted, or
    /// the Editor requires reconciliation.
    private var isMutationBlocked: Bool { isCommittingMutation || isAcquiringClips || draggingClipID != nil || reconciliation != nil }
    /// Back / navigation out of the Editor is unavailable only while an edit is being committed.
    var isNavigationLocked: Bool { isCommittingMutation }

    var canUndo: Bool { !undoStack.isEmpty && !isMutationBlocked }
    var canRedo: Bool { !redoStack.isEmpty && !isMutationBlocked }
    /// "+" is a production control whenever an acquisition boundary exists (always in the app).
    var supportsAddingClips: Bool { acquisition != nil }
    var canAddClips: Bool { supportsAddingClips && !isMutationBlocked }
    /// Replace (ADR-040) exists ONLY for a selected Clip whose media is structurally unavailable;
    /// healthy Clips never expose it in Phase 5.
    var canReplaceSelectedClip: Bool {
        guard supportsAddingClips, let selectedClipID, availability(for: selectedClipID).isUnavailable else { return false }
        return !isMutationBlocked
    }
    var isSelectedClipUnavailable: Bool {
        guard let selectedClipID else { return false }
        return availability(for: selectedClipID).isUnavailable
    }
    /// The edit Undo would reverse / Redo would reapply (accessibility hints).
    var undoTarget: EditorHistoryEntry.Kind? { undoStack.last?.kind }
    var redoTarget: EditorHistoryEntry.Kind? { redoStack.last?.kind }

    var canDeleteSelectedClip: Bool {
        selectedClip != nil && !isMutationBlocked
    }

    var totalDuration: MediaTime { project.totalDuration }

    var selectedClip: VlogClip? {
        guard let selectedClipID else { return nil }
        return project.clips.first { $0.id == selectedClipID }
    }

    /// Selects a clip by identity. Ignores ids that are not part of this project; never mutates the
    /// persisted project and never touches thumbnail state.
    func select(_ clipID: UUID) {
        // Not a mutation, but a locked or in-flight timeline keeps its selection (the outcome sets it).
        guard reconciliation == nil, !isCommittingMutation, project.clips.contains(where: { $0.id == clipID }) else { return }
        selectedClipID = clipID
    }

    // MARK: - Reorder (STEP 9)

    /// Enters reorder mode for `clipID` after the long press: the Clip is lifted and selected, the
    /// preview order starts equal to the committed order. Refused (false) for unknown clips, while a
    /// commit is in flight, or while another Clip is already lifted.
    @discardableResult
    func beginReorder(clipID: UUID) -> Bool {
        guard !isMutationBlocked, project.clips.contains(where: { $0.id == clipID }) else { return false }
        draggingClipID = clipID
        previewOrder = project.clips.map(\.id)
        selectedClipID = clipID
        reorderActivationCount += 1
        return true
    }

    /// Moves the lifted Clip to `index` in the preview order only. Repository untouched.
    func previewReorder(toIndex index: Int) {
        guard let draggingClipID, var order = previewOrder, let from = order.firstIndex(of: draggingClipID) else { return }
        let to = min(max(index, 0), order.count - 1)
        guard from != to else { return }
        order.remove(at: from)
        order.insert(draggingClipID, at: to)
        previewOrder = order
    }

    /// Index of the lifted Clip in the preview order, or nil when nothing is lifted.
    var dragTargetIndex: Int? {
        guard let draggingClipID, let previewOrder else { return nil }
        return previewOrder.firstIndex(of: draggingClipID)
    }

    /// Drops the lifted Clip: commits the preview order through the single reorder path when it
    /// differs from the committed order; a drop at the original position writes nothing. The preview
    /// ends at once and the committed order stays visible until the save is `completed` (no optimistic
    /// publish). Selection stays on the dropped Clip either way. Synchronous so the gesture can settle at
    /// once: the in-flight flag is reserved here, before the returned task awaits the gate.
    @discardableResult
    func commitReorder() -> Task<Bool, Never>? {
        guard let clipID = draggingClipID, let index = dragTargetIndex else { return nil }
        draggingClipID = nil
        previewOrder = nil
        guard !isMutationBlocked, let updated = reordered(clipID: clipID, toIndex: index) else { return nil }
        isCommittingMutation = true
        return Task { await runReservedEdit(updated, selecting: clipID, transition: .push(.reorder), label: "reorder") }
    }

    /// Abandons the drag (gesture cancelled, interruption, screen left): the committed order is
    /// simply shown again; nothing was written. Selection stays on the Clip.
    func cancelReorder() {
        draggingClipID = nil
        previewOrder = nil
    }

    func canMoveEarlier(_ clipID: UUID) -> Bool {
        guard let index = project.clips.firstIndex(where: { $0.id == clipID }) else { return false }
        return index > 0
    }

    func canMoveLater(_ clipID: UUID) -> Bool {
        guard let index = project.clips.firstIndex(where: { $0.id == clipID }) else { return false }
        return index < project.clips.count - 1
    }

    /// Non-drag accessibility reorder: index N → N-1 through the same commit path as a drop.
    /// Returns the new 1-based position once the save is `completed`, nil when refused or not saved.
    @discardableResult
    func moveClipEarlier(id clipID: UUID) async -> Int? {
        guard canMoveEarlier(clipID), let index = project.clips.firstIndex(where: { $0.id == clipID }) else { return nil }
        return await reorder(clipID: clipID, toIndex: index - 1) ? index : nil
    }

    /// Non-drag accessibility reorder: index N → N+1 through the same commit path as a drop.
    @discardableResult
    func moveClipLater(id clipID: UUID) async -> Int? {
        guard canMoveLater(clipID), let index = project.clips.firstIndex(where: { $0.id == clipID }) else { return nil }
        return await reorder(clipID: clipID, toIndex: index + 1) ? index + 2 : nil
    }

    /// The one reorder path (drag drop and accessibility actions both end here): the new order is
    /// computed on a copy (`VlogProject.reorderClip` normalises `sortOrder` 0…n-1); the same order writes
    /// nothing; otherwise it is committed through the gated edit path.
    @discardableResult
    private func reorder(clipID: UUID, toIndex index: Int) async -> Bool {
        guard !isMutationBlocked, let updated = reordered(clipID: clipID, toIndex: index) else { return false }
        return await runEdit(updated, selecting: clipID, transition: .push(.reorder), label: "reorder")
    }

    /// The committed Project with `clipID` moved to `index`, or nil when invalid or unchanged.
    private func reordered(clipID: UUID, toIndex index: Int) -> VlogProject? {
        var updated = project
        do { try updated.reorderClip(id: clipID, toIndex: index) } catch { return nil }
        return updated.clips.map(\.id) != project.clips.map(\.id) ? updated : nil
    }

    // MARK: - Delete (STEP 10, ADR-021)

    /// Logically deletes the selected Clip: it leaves the active timeline at once, the Total drops,
    /// selection falls to the Clip now at its position (else the previous one, else none) and the
    /// edit enters the session history. Metadata and media stay durable (pending deletion). Nothing
    /// is hidden unless the pending-deletion state was written and read back.
    @discardableResult
    func deleteSelectedClip() async -> Bool {
        guard let clipID = selectedClipID else { return false }
        return await deleteClip(id: clipID)
    }

    @discardableResult
    func deleteClip(id clipID: UUID) async -> Bool {
        guard !isMutationBlocked, let index = project.clips.firstIndex(where: { $0.id == clipID }) else { return false }
        var updated = project
        do { try updated.deleteClip(id: clipID) } catch { return false }
        let selection: UUID?
        if selectedClipID == clipID {
            selection = updated.clips.indices.contains(index) ? updated.clips[index].id : updated.clips.last?.id
        } else {
            selection = selectedClipID
        }
        return await runEdit(updated, selecting: selection, transition: .push(.delete), label: "delete")
    }

    // MARK: - Add Clips (ADR-037)

    /// "+": system picker → transfer → validate ALL → materialise ALL into this Project's media
    /// directory → append after the last active Clip in picker order → one autosave + read-back →
    /// ONE history entry → first added Clip selected. Cancel and every failure leave the Project,
    /// history, selection and existing media untouched; files this operation created are removed
    /// again when the failure precedes the save attempt, and preserved after it (ADR-050 050-D D8.0).
    /// Returns the number of Clips added (0 on cancel / failure).
    @discardableResult
    func addClips() async -> Int {
        guard let acquisition, canAddClips else { return 0 }
        acquisitionMode = .add
        defer { acquisitionMode = nil }
        return await acquireAndCommit(using: acquisition, replacing: nil, failure: .addFailed)?.count ?? 0
    }

    // MARK: - Replace (STEP 13, ADR-040)

    /// `클립 교체` on the selected, structurally unavailable Clip B: system picker (exactly ONE
    /// video) → transfer → validate → materialise ONE new Clip D into this Project's media directory
    /// → `VlogProject.replaceClip` (B becomes durable pending, D takes B's exact logical index with a
    /// NEW identity, `.imported`, trim reset, no framing) → one autosave + read-back → ONE `.replace`
    /// history entry → D selected. Cancel and every failure leave B, the Project, history, selection
    /// and existing media exactly as before; a D file created before a failure that precedes the save
    /// attempt is removed at once, and preserved after a save attempt. Undo / Redo of the entry go
    /// through the general history (B ↔ D swap identities, no picker, no copy). Returns the new Clip's
    /// id on success.
    @discardableResult
    func replaceSelectedClip() async -> UUID? {
        guard let acquisition, let targetID = selectedClipID, canReplaceSelectedClip else { return nil }
        acquisitionMode = .replace(targetID)
        defer { acquisitionMode = nil }
        return await acquireAndCommit(using: acquisition, replacing: targetID, failure: .replaceFailed)?.first?.id
    }

    /// The one acquisition path Add and Replace share (ADR-037 / ADR-040): workspace → selector
    /// session → reserve guard + validation, all OUTSIDE the lifecycle gate (the workspace is
    /// protected by the store's live-workspace registry) → then, INSIDE the shared lifecycle gate:
    /// prior check → materialise → the inner commit. The in-flight flag (navigation lock) is set before
    /// the gate is awaited. The workspace is always discarded here. Returns the committed new Clips
    /// (picker order), or nil on cancel / failure.
    private func acquireAndCommit(using acquisition: EditorClipAcquisition, replacing targetID: UUID?, failure: ProjectEditorMessage) async -> [VlogClip]? {
        guard let workspace = try? await acquisition.mediaStore.beginWorkspace() else {
            editorMessage = failure
            return nil
        }
        var committed: [VlogClip]?
        if let validated = await selectAndValidate(using: acquisition, workspace: workspace, selectionLimit: targetID == nil ? nil : 1, failure: failure) {
            let base = project, baseSelection = selectedClipID
            isCommittingMutation = true
            committed = await lifecycle.withExclusiveAccess {
                await materializeAndCommit(validated, using: acquisition, base: base, baseSelection: baseSelection, replacing: targetID, failure: failure)
            }
            isCommittingMutation = false
        }
        await acquisition.mediaStore.discard(workspace)
        return committed
    }

    /// Selector session (`selectionLimit` bounds the picker) → `ProjectClipAppendCoordinator.validate`.
    /// Cancel is silent; every other outcome maps to the canonical Select-Clips copy, with `failure` as
    /// the operation's generic message. Creates nothing under the Project directory.
    private func selectAndValidate(using acquisition: EditorClipAcquisition, workspace: ProjectMediaWorkspace, selectionLimit: Int?, failure: ProjectEditorMessage) async -> ProjectClipAppendCoordinator.ValidatedSources? {
        let sources: [SelectedVideoSource]
        switch await acquisition.mediaSelector.selectVideos(into: workspace, store: acquisition.mediaStore, admission: acquisition.storageGate, selectionLimit: selectionLimit) {
        case .cancelled:
            return nil
        case .insufficientStorage:
            editorMessage = .addInsufficientStorage
            return nil
        case .failed:
            editorMessage = failure
            return nil
        case .selected(let selected):
            sources = selected
        }
        if let selectionLimit, sources.count > selectionLimit {
            // A boundary that returned more than the session allowed: nothing was materialised yet.
            editorMessage = failure
            return nil
        }
        switch await acquisition.appender.validate(sources) {
        case .ready(let validated): return validated
        case .requiresImportPreparation(let reason): editorMessage = .addRequiresImportPreparation(reason)
        case .invalidMedia: editorMessage = .addInvalidMedia
        case .insufficientStorage: editorMessage = .addInsufficientStorage
        case .failed: editorMessage = failure
        }
        return nil
    }

    /// Runs INSIDE the lifecycle gate (never acquires it). The fresh prior state must equal this Editor's
    /// base exactly BEFORE anything is materialised; a stale, unreadable or missing Project stops here and
    /// locks the Editor. A batch that fails before the save attempt is removed again; from the save attempt
    /// on it is preserved for every non-`completed` outcome (ADR-050 050-D D8.0 / P6) — no rollback-to-
    /// workspace, no same-set Retry.
    private func materializeAndCommit(_ validated: ProjectClipAppendCoordinator.ValidatedSources, using acquisition: EditorClipAcquisition, base: VlogProject, baseSelection: UUID?, replacing targetID: UUID?, failure: ProjectEditorMessage) async -> [VlogClip]? {
        guard let prior = verifiedPriorInsideGate(base: base, label: targetID == nil ? "add" : "replace") else { return nil }
        // The Replace target is an active Clip of the verified base (and therefore of the store).
        if let targetID, !base.clips.contains(where: { $0.id == targetID }) {
            editorMessage = failure
            return nil
        }
        // Cardinality is the model's rule, not the picker's: Replace needs exactly one source.
        if targetID != nil, validated.sources.count != 1 {
            editorMessage = failure
            return nil
        }
        guard case .ready(let newClips) = await acquisition.appender.materialize(validated, for: base) else {
            editorMessage = failure
            return nil
        }
        #if DEBUG
        acquisition.debugAfterMaterialize?()
        #endif
        var updated = base
        do {
            if let targetID { try updated.replaceClip(id: targetID, with: newClips[0]) } else { try updated.appendClips(newClips) }
        } catch {
            await acquisition.appender.discard(newClips)
            editorMessage = failure
            return nil
        }
        let result = commitInsideGate(
            updated, prior: prior, base: base, baseSelection: baseSelection, selecting: newClips.first?.id,
            transition: .push(targetID == nil ? .add : .replace),
            notSaved: targetID == nil ? .addNotSaved : .replaceNotSaved,
            label: targetID == nil ? "add" : "replace"
        )
        if result == .lockedBeforeSave {
            // No save was attempted: the batch is still this operation's own (pre-save cleanup).
            await acquisition.appender.discard(newClips)
            return nil
        }
        guard result == .completed else {
            MellowLog.app.info("Project editor preserved acquired media after a non-completed save project=\(String(base.id.uuidString.prefix(8)), privacy: .public)")
            return nil
        }
        return newClips
    }

    // MARK: - Undo / Redo (ADR-038)

    /// Reverses the most recent successful edit: its BEFORE state (clip sets + selection) is
    /// re-applied to the current Project as a new save. Only a `completed` save moves the entry to the
    /// Redo stack (with the state, in one step); otherwise state and stacks are unchanged.
    @discardableResult
    func undo() async -> Bool {
        guard canUndo, let entry = undoStack.last else { return false }
        guard let target = restoredState(entry.before, failure: .undoFailed) else { return false }
        return await runEdit(target.project, selecting: target.selection, transition: .undo, label: "undo")
    }

    /// Re-applies the most recently undone edit (its AFTER state) as a new save; the entry moves back
    /// to the Undo stack only when the save is `completed`.
    @discardableResult
    func redo() async -> Bool {
        guard canRedo, let entry = redoStack.last else { return false }
        guard let target = restoredState(entry.after, failure: .redoFailed) else { return false }
        return await runEdit(target.project, selecting: target.selection, transition: .redo, label: "redo")
    }

    /// Builds a captured state onto the CURRENT Project (same identity, orientation, createdAt; fresh
    /// `updatedAt`). A captured selection that is no longer active falls back to the first active Clip.
    ///
    /// History never forgets durable media: a Clip the current Project owns but the target state
    /// does not know (it was added by an edit that is now being undone) is kept as a pending-
    /// deleted, inactive Clip with its position recorded (ADR-037 / ADR-038) — recoverable by Redo,
    /// visible to the future cleanup slice, never an orphaned file, never physically removed here.
    private func restoredState(_ state: EditorEditState, failure: ProjectEditorMessage) -> (project: VlogProject, selection: UUID?)? {
        let restored: VlogProject
        do {
            let known = Set(state.clips.map(\.id) + state.deletedClips.map(\.id))
            let unknown = project.durableClips.filter { !known.contains($0.id) }.map(\.id)
            var retained: [VlogClip] = []
            if !unknown.isEmpty {
                var working = project
                for id in unknown where working.clips.contains(where: { $0.id == id }) { try working.deleteClip(id: id) }
                retained = working.deletedClips.filter { unknown.contains($0.id) }
            }
            restored = try VlogProject(
                id: project.id, createdAt: project.createdAt, updatedAt: .now, orientation: project.orientation,
                clips: state.clips, deletedClips: state.deletedClips + retained
            )
        } catch {
            editorMessage = failure
            return nil
        }
        let selection = state.selectedClipID.flatMap { id in restored.clips.contains { $0.id == id } ? id : nil } ?? restored.clips.first?.id
        return (project: restored, selection: selection)
    }

    // MARK: - Gated commit (ADR-050 050-D D8.0 / D8.5a P1 · P2 · P4 · P7)

    /// How a `completed` save changes the session history — applied exactly once, together with the state.
    private enum HistoryTransition {
        /// A new edit: push one entry, abandon the Redo branch.
        case push(EditorHistoryEntry.Kind)
        /// Move the newest Undo entry to the Redo stack.
        case undo
        /// Move the newest Redo entry back to the Undo stack.
        case redo
    }

    private enum CommitResult: Equatable {
        case completed, notSaved, locked
        /// Locked before any save attempt (no valid expectation): files this operation created are still its own.
        case lockedBeforeSave
    }

    /// Gate-acquiring entry for Reorder / Delete / Undo / Redo. The in-flight flag is set before the gate
    /// is awaited (blocking every other mutation, drag and navigation) and cleared once the outcome is
    /// applied. Returns true only for a `completed` save.
    private func runEdit(_ updated: VlogProject, selecting selection: UUID?, transition: HistoryTransition, label: StaticString) async -> Bool {
        guard !isMutationBlocked else { return false }
        isCommittingMutation = true
        return await runReservedEdit(updated, selecting: selection, transition: transition, label: label)
    }

    /// The edit after its in-flight flag was reserved (synchronously, by the caller).
    private func runReservedEdit(_ updated: VlogProject, selecting selection: UUID?, transition: HistoryTransition, label: StaticString) async -> Bool {
        defer { isCommittingMutation = false }
        let base = project, baseSelection = selectedClipID
        #if DEBUG
        // UI-test seam: lets another holder take the shared gate first, so the edit visibly waits for it.
        await debugBeforeEditGate?()
        #endif
        return await lifecycle.withExclusiveAccess {
            guard let prior = verifiedPriorInsideGate(base: base, label: label) else { return false }
            return commitInsideGate(updated, prior: prior, base: base, baseSelection: baseSelection, selecting: selection,
                                    transition: transition, notSaved: .changesNotSaved, label: label) == .completed
        }
    }

    /// INSIDE the gate: the fresh prior read (OD-10) must equal the Editor's base exactly (full state,
    /// timestamps included). Otherwise the Editor is locked before any save or materialisation — stale or
    /// unreadable → `recheckRequired` (never claiming the store is unchanged), absent → `projectMissing`.
    private func verifiedPriorInsideGate(base: VlogProject, label: StaticString) -> VlogProject? {
        let short = String(base.id.uuidString.prefix(8))
        switch repository.observePersistedProject(id: base.id) {
        case .present(let stored) where ProjectStateSnapshot(stored) == ProjectStateSnapshot(base):
            return stored
        case .present:
            MellowLog.app.error("Project editor \(label, privacy: .public) stopped project=\(short, privacy: .public) reason=stale")
            reconciliation = .recheckRequired
        case .unreadable:
            MellowLog.app.error("Project editor \(label, privacy: .public) stopped project=\(short, privacy: .public) reason=priorUnreadable")
            reconciliation = .recheckRequired
        case .absent:
            MellowLog.app.error("Project editor \(label, privacy: .public) stopped project=\(short, privacy: .public) reason=projectAbsent")
            reconciliation = .projectMissing
        }
        return nil
    }

    /// The ONE inner commit every Editor mutation uses. Assumes the lifecycle gate is held and never
    /// acquires it. Builds the update expectation from the verified prior, saves once, observes (OD-10)
    /// and classifies (D8.0) with no suspension point, then applies the outcome:
    /// `completed` (also after a thrown save, P4) → the intended state and its history transition are
    /// published together; `priorConfirmed` → state and history unchanged, acknowledgement-only copy;
    /// `committedUnverified` / `indeterminate` → the Editor locks for reconciliation (P2), media preserved.
    private func commitInsideGate(_ updated: VlogProject, prior: VlogProject, base: VlogProject, baseSelection: UUID?, selecting selection: UUID?, transition: HistoryTransition, notSaved: ProjectEditorMessage, label: StaticString) -> CommitResult {
        assert(lifecycle.isHeld, "the Editor commit runs inside the shared lifecycle gate")
        let short = String(updated.id.uuidString.prefix(8))
        let expectation: ProjectSaveExpectation
        do { expectation = try ProjectSaveExpectation.update(from: prior, to: updated) } catch {
            reconciliation = .recheckRequired
            return .lockedBeforeSave
        }
        guard expectation.isStructurallyValid, !expectation.isIndistinguishable else {
            reconciliation = .recheckRequired
            return .lockedBeforeSave
        }
        var saveError: Error?
        do { try repository.update(updated) } catch { saveError = error }
        let observation = repository.observePersistedState(for: expectation)
        switch ProjectSaveOutcomeClassifier.classify(saveError == nil ? .succeeded : .threw, expectation: expectation, observation: observation) {
        case .completed:
            if let saveError {
                MellowLog.app.error("Project editor \(label, privacy: .public) completed despite save error project=\(short, privacy: .public): \(String(describing: saveError), privacy: .public)")
            }
            // State and history change together, synchronously: no observer sees one without the other.
            let after = EditorEditState(project: updated, selectedClipID: selection)
            project = updated
            selectedClipID = selection
            switch transition {
            case .push(let kind):
                undoStack.append(EditorHistoryEntry(kind: kind, before: EditorEditState(project: base, selectedClipID: baseSelection), after: after))
                redoStack.removeAll()
            case .undo:
                redoStack.append(undoStack.removeLast())
            case .redo:
                undoStack.append(redoStack.removeLast())
            }
            #if DEBUG
            MellowLog.app.info("Project editor \(label, privacy: .public) saved \(updated.id.uuidString, privacy: .public) active=\(updated.clips.count, privacy: .public) pendingDeleted=\(updated.deletedClips.count, privacy: .public)")
            #endif
            return .completed
        case .priorConfirmed:
            MellowLog.app.error("Project editor \(label, privacy: .public) not saved project=\(short, privacy: .public): \(String(describing: saveError), privacy: .public)")
            editorMessage = notSaved
            return .notSaved
        case .committedUnverified(let reason):
            MellowLog.app.error("Project editor \(label, privacy: .public) save unverified project=\(short, privacy: .public) reason=\(String(describing: reason), privacy: .public)")
            reconciliation = .saveUnverified
            return .locked
        case .indeterminate(let reason):
            MellowLog.app.error("Project editor \(label, privacy: .public) save indeterminate project=\(short, privacy: .public) reason=\(String(describing: reason), privacy: .public)")
            reconciliation = .saveIndeterminate
            return .locked
        }
    }

    // MARK: - Availability (STEP 13, ADR-040)

    /// Derived availability of a Clip. Unknown (not yet evaluated, or no checker) = available.
    func availability(for clipID: UUID) -> ClipAvailability {
        availabilityByClipID[clipID] ?? .available
    }

    /// Evaluates availability for every ACTIVE Clip through the checker (one existence resolution per
    /// Clip, off the Main Actor, no decode, no thumbnails) and publishes each answer only if it is
    /// still current: same evaluation generation, Clip still active with the same media reference.
    /// Runs on Editor load and after every active-set change (the view's thumbnail load task), so
    /// Add / Delete / Undo / Redo / Replace re-derive it; there is no timer and no polling.
    func refreshAvailability() async {
        guard let checker = availabilityChecker else { return }
        availabilityGeneration += 1
        let generation = availabilityGeneration
        let clips = project.clips
        await withTaskGroup(of: (VlogClip, ClipAvailability).self) { group in
            for clip in clips {
                group.addTask { (clip, await checker.availability(for: clip)) }
            }
            for await (clip, availability) in group {
                applyAvailability(availability, for: clip, generation: generation)
            }
        }
    }

    private func applyAvailability(_ availability: ClipAvailability, for clip: VlogClip, generation: Int) {
        guard generation == availabilityGeneration,
              project.clips.first(where: { $0.id == clip.id })?.mediaRelativePath == clip.mediaRelativePath else { return }
        availabilityByClipID[clip.id] = availability
    }

    // MARK: - Thumbnails

    /// Presentation for a cell: structural unavailability wins over every thumbnail state (a late
    /// image can never make a known-missing Clip look ready), otherwise the thumbnail result.
    func thumbnail(for clipID: UUID) -> ClipThumbnailPresentation {
        if availability(for: clipID).isUnavailable { return .mediaUnavailable }
        return thumbnailStates[clipID] ?? .loading
    }

    /// The request identity a result must still match to be published for `clipID`. Nil when no
    /// load is active or the clip is not (any longer) part of this Project.
    func currentThumbnailRequest(for clipID: UUID) -> ClipThumbnailRequest? {
        guard let scale = activeThumbnailScale, let clip = project.clips.first(where: { $0.id == clipID }) else { return nil }
        return ClipThumbnailRequest(
            clip: clip,
            maximumPixelSize: ClipThumbnailPixelSize(points: Self.thumbnailPointSize, scale: scale)
        )
    }

    /// Re-derives availability first, then requests every not-yet-ready thumbnail of every AVAILABLE
    /// Clip in logical order and publishes each result as it arrives. A structurally unavailable Clip
    /// is never requested (no retry storm; its cell shows the unavailable presentation). Runs until
    /// all requests settle or the caller is cancelled (the view's `.task`), so no generation work
    /// outlives the screen. Generation itself happens inside the service, off the Main Actor.
    func loadThumbnails(displayScale: CGFloat) async {
        await refreshAvailability()
        guard !Task.isCancelled else { return }
        activeThumbnailScale = displayScale
        let requests = orderedClips.compactMap { clip -> ClipThumbnailRequest? in
            switch thumbnail(for: clip.id) {
            case .ready, .mediaUnavailable: return nil
            case .loading, .unavailable: return currentThumbnailRequest(for: clip.id)
            }
        }
        let thumbnails = self.thumbnails
        await withTaskGroup(of: Void.self) { group in
            for request in requests {
                group.addTask {
                    let outcome: Result<CGImage, Error>
                    do { outcome = .success(try await thumbnails.thumbnail(for: request)) } catch { outcome = .failure(error) }
                    await self.applyThumbnailResult(outcome, for: request)
                }
            }
        }
        if Task.isCancelled { stopThumbnailLoading() }
    }

    /// Ends the active load: any result that arrives afterwards is stale and dropped.
    func stopThumbnailLoading() {
        activeThumbnailScale = nil
    }

    /// Identity-aware publication (ARCHITECTURE §56 / ADR-021 late-result rule). A result is applied
    /// only if the request it answers is still exactly the current request for that Clip in this
    /// Project — same Project, same Clip identity, same media reference, trim range and pixel budget.
    /// Late or foreign results are discarded; they never overwrite another Clip's state.
    func applyThumbnailResult(_ result: Result<CGImage, Error>, for request: ClipThumbnailRequest) {
        guard request.projectID == project.id, currentThumbnailRequest(for: request.clipID) == request,
              !availability(for: request.clipID).isUnavailable else { return }
        switch result {
        case .success(let image):
            thumbnailStates[request.clipID] = .ready(image)
        case .failure(let error):
            // A cancelled request is not a failed thumbnail; the next load simply asks again.
            if let error = error as? ClipThumbnailError, error == .cancelled { return }
            if error is CancellationError { return }
            thumbnailStates[request.clipID] = .unavailable
        }
    }
}

/// Compact, locale-independent duration label for the editor shell (e.g. "2.0s").
enum ClipDurationText {
    static func string(_ time: MediaTime) -> String {
        let seconds = time.timescale > 0 ? Double(time.value) / Double(time.timescale) : 0
        return String(format: "%.1fs", seconds)
    }
}
