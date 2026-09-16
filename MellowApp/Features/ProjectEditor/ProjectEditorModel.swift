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

/// Recoverable outcome of a reorder whose autosave did not land (ARCHITECTURE §57). The committed
/// order was restored before this is shown; nothing else about the Project changed.
enum ClipReorderMessage: Equatable {
    case saveFailed

    var title: String { "순서를 저장하지 못했어요." }
    var message: String { "다시 시도해주세요." }
}

/// Presentation state for the Phase 5 Project Editor (ADR-034).
///
/// Holds one loaded Project, its ordered clips, total duration, the selected clip and the per-clip
/// thumbnail presentation. STEP 8 added asynchronous thumbnail loading with identity-based
/// stale-result protection; STEP 9 adds clip reorder (long press + drag and the non-drag Move
/// Earlier / Move Later actions) with autosave through the repository. There is still no delete,
/// undo, add clip or playback — those belong to later slices.
///
/// Reorder state is deliberately small and explicit: `project` is the committed order, `previewOrder`
/// the temporary order shown while a drag is in flight, `draggingClipID` the lifted Clip. Nothing is
/// written until the drop; cancel simply drops the preview.
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
    /// True while a reorder is being written; a second commit is refused rather than raced.
    private(set) var isCommittingReorder = false
    /// Incremented once per successful reorder-mode activation — the haptic trigger and the only
    /// observable of the activation event.
    private(set) var reorderActivationCount = 0
    /// Recoverable autosave failure to present; the order has already been rolled back.
    var reorderMessage: ClipReorderMessage?

    init(project: VlogProject, repository: any ProjectRepository, thumbnails: any ClipThumbnailProviding) {
        self.project = project
        self.repository = repository
        self.thumbnails = thumbnails
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
        guard draggingClipID == nil, !isCommittingReorder, project.clips.contains(where: { $0.id == clipID }) else { return false }
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
    /// Synchronous on the Main Actor, so two commits can never interleave; `isCommittingReorder`
    /// additionally refuses a re-entrant commit from inside the repository call.
    @discardableResult
    private func reorder(clipID: UUID, toIndex index: Int) -> Bool {
        guard !isCommittingReorder else { return false }
        var updated = project
        do { try updated.reorderClip(id: clipID, toIndex: index) } catch { return false }
        guard updated.clips.map(\.id) != project.clips.map(\.id) else { return false }

        let previous = project
        isCommittingReorder = true
        defer { isCommittingReorder = false }
        project = updated
        selectedClipID = clipID
        do {
            try repository.update(updated)
            guard let stored = try repository.project(id: updated.id), stored.clips == updated.clips else {
                throw ProjectRepositoryError.invalidPersistedMetadata
            }
            #if DEBUG
            MellowLog.app.info("Project editor reorder saved \(updated.id.uuidString, privacy: .public) order=\(updated.clips.map(\.sortOrder).description, privacy: .public)")
            #endif
            return true
        } catch {
            project = previous
            MellowLog.app.error("Project editor reorder save failed \(updated.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            reorderMessage = .saveFailed
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
