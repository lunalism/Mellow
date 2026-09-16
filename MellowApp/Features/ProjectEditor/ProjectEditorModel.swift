import CoreGraphics
import Foundation
import Observation

/// Per-clip thumbnail presentation state. Presentation only — never persisted, never a statement
/// about Clip availability (ADR-026 unavailable-media handling is a later slice).
enum ClipThumbnailPresentation: Equatable {
    case loading
    case ready(CGImage)
    /// Generation failed (missing / unreadable / no frame). The Clip keeps its slot; the view shows a
    /// calm neutral placeholder.
    case unavailable

    static func == (lhs: ClipThumbnailPresentation, rhs: ClipThumbnailPresentation) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading), (.unavailable, .unavailable): return true
        case (.ready(let a), .ready(let b)): return a === b
        default: return false
        }
    }
}

/// Recoverable outcome of an Editor mutation whose autosave did not land (ARCHITECTURE §57). The
/// committed state was restored before this is shown; nothing else about the Project changed.
enum ProjectEditorMessage: Equatable {
    case reorderSaveFailed
    case deleteSaveFailed
    case undoFailed
    case redoFailed
    /// Add Clips (ADR-037): the same typed outcomes and copy as Select Clips, one message per batch.
    case addRequiresImportPreparation(Phase5ReadyVerdict.PreparationReason)
    case addInvalidMedia
    case addInsufficientStorage
    case addFailed

    var title: String {
        switch self {
        case .reorderSaveFailed: return "순서를 저장하지 못했어요."
        case .deleteSaveFailed: return "클립을 삭제하지 못했어요."
        case .undoFailed: return "실행 취소하지 못했어요."
        case .redoFailed: return "다시 실행하지 못했어요."
        case .addRequiresImportPreparation(let reason): return ProjectMediaValidationCopy.preparationTitle(reason)
        case .addInvalidMedia: return ProjectMediaValidationCopy.invalidMediaTitle
        case .addInsufficientStorage: return ProjectMediaValidationCopy.insufficientStorageTitle
        case .addFailed: return "클립을 추가하지 못했어요."
        }
    }
    var message: String {
        switch self {
        case .addRequiresImportPreparation(let reason): return ProjectMediaValidationCopy.preparationMessage(reason)
        case .addInvalidMedia: return ProjectMediaValidationCopy.invalidMediaMessage
        case .addInsufficientStorage: return ProjectMediaValidationCopy.insufficientStorageMessage
        case .addFailed: return "다시 시도해주세요. 프로젝트는 그대로 있어요."
        default: return "다시 시도해주세요."
        }
    }
}

/// The acquisition boundary the Editor's Add Clips uses (ADR-037): the same selector / store /
/// gate / validator chain as Select Clips, scoped to appending to the loaded Project. Absent (nil)
/// only in unit tests that never add.
@MainActor
struct EditorClipAcquisition {
    let mediaStore: any ProjectMediaStoring
    let mediaSelector: any ProjectMediaSelecting
    let storageGate: any ProjectStorageGating
    let appender: ProjectClipAppendCoordinator
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

        /// Short Korean description used in accessibility hints ("클립 삭제 실행 취소").
        var description: String {
            switch self {
            case .reorder: return "클립 순서 변경"
            case .delete: return "클립 삭제"
            case .add: return "클립 추가"
            }
        }
    }

    let kind: Kind
    let before: EditorEditState
    let after: EditorEditState
}

/// Presentation state for the Phase 5 Project Editor (ADR-034).
///
/// Holds one loaded Project, its ordered clips, total duration, the selected clip and the per-clip
/// thumbnail presentation. STEP 8 added asynchronous thumbnail loading with identity-based
/// stale-result protection; STEP 9 added clip reorder (long press + drag and the non-drag Move
/// Earlier / Move Later actions) with autosave; STEP 10 adds logical Clip delete (ADR-021, durable
/// pending deletion) and the session-local Undo / Redo history (ADR-038). There is still no
/// physical cleanup, add clip or playback.
///
/// Reorder state is deliberately small and explicit: `project` is the committed state, `previewOrder`
/// the temporary order shown while a drag is in flight, `draggingClipID` the lifted Clip. Nothing is
/// written until the drop; cancel simply drops the preview. Every mutation (reorder, delete, undo,
/// redo) goes through one synchronous commit path: apply on a copy → write → read back → publish,
/// or roll back and surface a recoverable message. Only a successful edit enters the history.
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
    private(set) var selectedClipID: UUID?
    private(set) var thumbnailStates: [UUID: ClipThumbnailPresentation] = [:]
    /// Display scale of the active load; part of every current request identity. Nil while no load
    /// is active, which makes every late result stale.
    private var activeThumbnailScale: CGFloat?

    // MARK: Reorder state

    /// The Clip currently lifted by a long press, or nil when no reorder is in progress.
    private(set) var draggingClipID: UUID?
    /// Temporary logical order shown during the drag (Clip ids). Nil outside a drag. Never persisted
    /// as such — only the drop turns it into a committed order.
    private(set) var previewOrder: [UUID]?
    /// True while a mutation (reorder / delete / undo) is being written; a second commit is refused
    /// rather than raced.
    private(set) var isCommittingMutation = false
    /// Incremented once per successful reorder-mode activation — the haptic trigger and the only
    /// observable of the activation event.
    private(set) var reorderActivationCount = 0
    /// Recoverable autosave failure to present; the committed state has already been rolled back.
    var editorMessage: ProjectEditorMessage?

    // MARK: Session history (ADR-038)

    /// Chronological edit history of THIS Editor session: `undoStack.last` is the most recent
    /// successful edit, `redoStack.last` the most recently undone one. In memory only — a new model
    /// (reopened Editor, relaunch) starts empty while the durable Project stays as last autosaved.
    /// Unbounded for the session: entries hold clip metadata values only (no media, no images).
    private(set) var undoStack: [EditorHistoryEntry] = []
    private(set) var redoStack: [EditorHistoryEntry] = []

    /// True from "+" until the Add batch resolves (picker open, transferring, validating,
    /// materialising, committing). Every other mutation is refused meanwhile.
    private(set) var isAddingClips = false

    init(project: VlogProject, repository: any ProjectRepository, thumbnails: any ClipThumbnailProviding, acquisition: EditorClipAcquisition? = nil) {
        self.project = project
        self.repository = repository
        self.thumbnails = thumbnails
        self.acquisition = acquisition
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

    /// No mutation may start while another (including an Add batch) is in flight or a clip is lifted.
    private var isMutationBlocked: Bool { isCommittingMutation || isAddingClips || draggingClipID != nil }

    var canUndo: Bool { !undoStack.isEmpty && !isMutationBlocked }
    var canRedo: Bool { !redoStack.isEmpty && !isMutationBlocked }
    /// "+" is a production control whenever an acquisition boundary exists (always in the app).
    var supportsAddingClips: Bool { acquisition != nil }
    var canAddClips: Bool { supportsAddingClips && !isMutationBlocked }
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
        guard project.clips.contains(where: { $0.id == clipID }) else { return }
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
    /// differs from the committed order; a drop at the original position writes nothing.
    /// Selection stays on the dropped Clip either way.
    func commitReorder() {
        guard let clipID = draggingClipID, let index = dragTargetIndex else { return }
        draggingClipID = nil
        previewOrder = nil
        reorder(clipID: clipID, toIndex: index)
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
    /// Returns the new 1-based position on success, nil when refused or unchanged.
    @discardableResult
    func moveClipEarlier(id clipID: UUID) -> Int? {
        guard canMoveEarlier(clipID), let index = project.clips.firstIndex(where: { $0.id == clipID }) else { return nil }
        return reorder(clipID: clipID, toIndex: index - 1) ? index : nil
    }

    /// Non-drag accessibility reorder: index N → N+1 through the same commit path as a drop.
    @discardableResult
    func moveClipLater(id clipID: UUID) -> Int? {
        guard canMoveLater(clipID), let index = project.clips.firstIndex(where: { $0.id == clipID }) else { return nil }
        return reorder(clipID: clipID, toIndex: index + 1) ? index + 2 : nil
    }

    /// The one reorder + autosave path (drag drop and accessibility actions both end here).
    ///
    /// 1. Compute the new order on a copy (`VlogProject.reorderClip` normalises `sortOrder` 0…n-1).
    /// 2. Same order → no mutation, no write.
    /// 3. Publish the new committed order, write it with `repository.update` — the clip set is
    ///    identical, so the repository's clip reconciliation removes nothing — and read it back.
    /// 4. On any failure or read-back mismatch: restore the previous committed order, keep the
    ///    selection, surface a recoverable message. Nothing partial is ever left behind.
    ///
    /// Synchronous on the Main Actor, so two commits can never interleave; `isCommittingMutation`
    /// additionally refuses a re-entrant commit from inside the repository call.
    @discardableResult
    private func reorder(clipID: UUID, toIndex index: Int) -> Bool {
        guard !isMutationBlocked else { return false }
        var updated = project
        do { try updated.reorderClip(id: clipID, toIndex: index) } catch { return false }
        guard updated.clips.map(\.id) != project.clips.map(\.id) else { return false }
        return commitEdit(.reorder, updated, selecting: clipID, failure: .reorderSaveFailed, label: "reorder")
    }

    // MARK: - Delete (STEP 10, ADR-021)

    /// Logically deletes the selected Clip: it leaves the active timeline at once, the Total drops,
    /// selection falls to the Clip now at its position (else the previous one, else none) and the
    /// edit enters the session history. Metadata and media stay durable (pending deletion). Nothing
    /// is hidden unless the pending-deletion state was written and read back.
    @discardableResult
    func deleteSelectedClip() -> Bool {
        guard let clipID = selectedClipID else { return false }
        return deleteClip(id: clipID)
    }

    @discardableResult
    func deleteClip(id clipID: UUID) -> Bool {
        guard !isMutationBlocked, let index = project.clips.firstIndex(where: { $0.id == clipID }) else { return false }
        var updated = project
        do { try updated.deleteClip(id: clipID) } catch { return false }
        let selection: UUID?
        if selectedClipID == clipID {
            selection = updated.clips.indices.contains(index) ? updated.clips[index].id : updated.clips.last?.id
        } else {
            selection = selectedClipID
        }
        return commitEdit(.delete, updated, selecting: selection, failure: .deleteSaveFailed, label: "delete")
    }

    // MARK: - Add Clips (ADR-037)

    /// "+": system picker → transfer → validate ALL → materialise ALL into this Project's media
    /// directory → append after the last active Clip in picker order → one autosave + read-back →
    /// ONE history entry → first added Clip selected. Cancel and every failure leave the Project,
    /// history, selection and existing media untouched; files this operation created are removed
    /// again. Returns the number of Clips added (0 on cancel / failure).
    @discardableResult
    func addClips() async -> Int {
        guard let acquisition, canAddClips else { return 0 }
        isAddingClips = true
        defer { isAddingClips = false }
        guard let workspace = try? await acquisition.mediaStore.beginWorkspace() else {
            editorMessage = .addFailed
            return 0
        }
        let added = await addClips(using: acquisition, workspace: workspace)
        await acquisition.mediaStore.discard(workspace)
        return added
    }

    private func addClips(using acquisition: EditorClipAcquisition, workspace: ProjectMediaWorkspace) async -> Int {
        let sources: [SelectedVideoSource]
        switch await acquisition.mediaSelector.selectVideos(into: workspace, store: acquisition.mediaStore, admission: acquisition.storageGate) {
        case .cancelled:
            return 0
        case .insufficientStorage:
            editorMessage = .addInsufficientStorage
            return 0
        case .failed:
            editorMessage = .addFailed
            return 0
        case .selected(let selected):
            sources = selected
        }
        let newClips: [VlogClip]
        switch await acquisition.appender.prepareClips(for: project, sources: sources) {
        case .ready(let clips):
            newClips = clips
            #if DEBUG
            acquisition.debugAfterMaterialize?()
            #endif
        case .requiresImportPreparation(let reason): editorMessage = .addRequiresImportPreparation(reason); return 0
        case .invalidMedia: editorMessage = .addInvalidMedia; return 0
        case .insufficientStorage: editorMessage = .addInsufficientStorage; return 0
        case .failed: editorMessage = .addFailed; return 0
        }
        var updated = project
        do { try updated.appendClips(newClips) } catch {
            await acquisition.appender.discard(newClips)
            editorMessage = .addFailed
            return 0
        }
        guard commitEdit(.add, updated, selecting: newClips.first?.id, failure: .addFailed, label: "add") else {
            // Never committed and referenced by nothing durable: safe to remove these files now.
            await acquisition.appender.discard(newClips)
            return 0
        }
        return newClips.count
    }

    // MARK: - Undo / Redo (ADR-038)

    /// Reverses the most recent successful edit: its BEFORE state (clip sets + selection) is
    /// re-applied to the current Project as a new autosave. On success the entry moves to the
    /// Redo stack; on failure nothing changes (state, stacks) and a recoverable message is shown.
    @discardableResult
    func undo() -> Bool {
        guard canUndo, let entry = undoStack.last else { return false }
        guard commitHistory(entry.before, failure: .undoFailed, label: "undo") else { return false }
        undoStack.removeLast()
        redoStack.append(entry)
        return true
    }

    /// Re-applies the most recently undone edit (its AFTER state) as a new autosave; the entry
    /// moves back to the Undo stack. Failure leaves state and stacks untouched.
    @discardableResult
    func redo() -> Bool {
        guard canRedo, let entry = redoStack.last else { return false }
        guard commitHistory(entry.after, failure: .redoFailed, label: "redo") else { return false }
        redoStack.removeLast()
        undoStack.append(entry)
        return true
    }

    /// A history-capable edit: commit, then (only on success) push one entry and discard any Redo
    /// future — a new edit after Undo abandons the undone branch.
    private func commitEdit(_ kind: EditorHistoryEntry.Kind, _ updated: VlogProject, selecting selection: UUID?, failure: ProjectEditorMessage, label: StaticString) -> Bool {
        let before = EditorEditState(project: project, selectedClipID: selectedClipID)
        guard commit(updated, selecting: selection, failure: failure, label: label) else { return false }
        undoStack.append(EditorHistoryEntry(kind: kind, before: before, after: EditorEditState(project: project, selectedClipID: selectedClipID)))
        redoStack.removeAll()
        return true
    }

    /// Restores a captured state onto the CURRENT Project (same identity, orientation, createdAt;
    /// fresh `updatedAt`) through the common commit path. A captured selection that is no longer
    /// active falls back to the first active Clip.
    ///
    /// History never forgets durable media: a Clip the current Project owns but the target state
    /// does not know (it was added by an edit that is now being undone) is kept as a pending-
    /// deleted, inactive Clip with its position recorded (ADR-037 / ADR-038) — recoverable by Redo,
    /// visible to the future cleanup slice, never an orphaned file, never physically removed here.
    private func commitHistory(_ state: EditorEditState, failure: ProjectEditorMessage, label: StaticString) -> Bool {
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
            return false
        }
        let selection = state.selectedClipID.flatMap { id in restored.clips.contains { $0.id == id } ? id : nil } ?? restored.clips.first?.id
        return commit(restored, selecting: selection, failure: failure, label: label)
    }

    /// The one autosave path for every Editor mutation: publish the new committed state, write it,
    /// read it back and compare the durable clip sets; on any failure or mismatch restore the
    /// previous state and selection and surface a recoverable message. Nothing partial is ever left.
    private func commit(_ updated: VlogProject, selecting selection: UUID?, failure: ProjectEditorMessage, label: StaticString) -> Bool {
        let previous = project
        let previousSelection = selectedClipID
        isCommittingMutation = true
        defer { isCommittingMutation = false }
        project = updated
        selectedClipID = selection
        do {
            try repository.update(updated)
            guard let stored = try repository.project(id: updated.id),
                  stored.clips == updated.clips, stored.deletedClips == updated.deletedClips else {
                throw ProjectRepositoryError.invalidPersistedMetadata
            }
            #if DEBUG
            MellowLog.app.info("Project editor \(label, privacy: .public) saved \(updated.id.uuidString, privacy: .public) active=\(updated.clips.count, privacy: .public) pendingDeleted=\(updated.deletedClips.count, privacy: .public)")
            #endif
            return true
        } catch {
            project = previous
            selectedClipID = previousSelection
            MellowLog.app.error("Project editor \(label, privacy: .public) save failed \(updated.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            editorMessage = failure
            return false
        }
    }

    // MARK: - Thumbnails

    func thumbnail(for clipID: UUID) -> ClipThumbnailPresentation {
        thumbnailStates[clipID] ?? .loading
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

    /// Requests every not-yet-ready thumbnail in logical order and publishes each result as it
    /// arrives. Runs until all requests settle or the caller is cancelled (the view's `.task`), so no
    /// generation work outlives the screen. Generation itself happens inside the service, off the
    /// Main Actor.
    func loadThumbnails(displayScale: CGFloat) async {
        activeThumbnailScale = displayScale
        let requests = orderedClips.compactMap { clip -> ClipThumbnailRequest? in
            if case .ready = thumbnail(for: clip.id) { return nil }
            return currentThumbnailRequest(for: clip.id)
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
        guard request.projectID == project.id, currentThumbnailRequest(for: request.clipID) == request else { return }
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
