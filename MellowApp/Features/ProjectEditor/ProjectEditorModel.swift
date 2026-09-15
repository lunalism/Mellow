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

/// Presentation state for the Phase 5 Project Editor (ADR-034).
///
/// Holds one already-loaded Project, its ordered clips, total duration, the selected clip and the
/// per-clip thumbnail presentation. STEP 8 adds asynchronous thumbnail loading with identity-based
/// stale-result protection; there is still no reorder, delete, undo, autosave or playback — those
/// belong to later slices.
@Observable
@MainActor
final class ProjectEditorModel {
    /// Point size of one timeline cell (compact 9:16); the pixel budget is derived from it and the
    /// display scale. Presentation constant only — it takes part in the request identity, nothing else.
    static let thumbnailPointSize = CGSize(width: 44, height: 78)

    let project: VlogProject
    @ObservationIgnored private let thumbnails: any ClipThumbnailProviding
    private(set) var selectedClipID: UUID?
    private(set) var thumbnailStates: [UUID: ClipThumbnailPresentation] = [:]
    /// Display scale of the active load; part of every current request identity. Nil while no load
    /// is active, which makes every late result stale.
    private var activeThumbnailScale: CGFloat?

    init(project: VlogProject, thumbnails: any ClipThumbnailProviding) {
        self.project = project
        self.thumbnails = thumbnails
        // Default selection: the first clip when the project has clips, otherwise none.
        self.selectedClipID = project.clips.first?.id
    }

    /// Clips in committed logical order (`VlogProject` already keeps `clips` sorted by `sortOrder`).
    var orderedClips: [VlogClip] { project.clips }

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
