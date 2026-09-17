import CoreGraphics
import Foundation
import Observation

/// Presentation-ready representative state of the V1 saved Project (ADR-034 §7, ARCHITECTURE §56
/// "Representative Source Selection"). Derived, never persisted: Project-oriented surfaces (the
/// Projects screen visual) consume it. It never owns the Camera content slot (ADR-041).
enum ProjectRepresentativeState: Equatable {
    /// No saved editable Project.
    case noProject
    /// A saved Project exists. `thumbnail` is the representative Clip's frame once generated; nil
    /// means "show the neutral Project placeholder" (no usable source, not yet generated, or the
    /// generation failed — none of which says anything about the Project or its Clips).
    case project(id: UUID, thumbnail: CGImage?)

    var savedProjectID: UUID? {
        if case .project(let id, _) = self { return id }
        return nil
    }
    var thumbnail: CGImage? {
        if case .project(_, let image) = self { return image }
        return nil
    }

    static func == (lhs: ProjectRepresentativeState, rhs: ProjectRepresentativeState) -> Bool {
        switch (lhs, rhs) {
        case (.noProject, .noProject): return true
        case (.project(let a, let x), .project(let b, let y)): return a == b && x === y
        default: return false
        }
    }
}

/// Owns the derived representative state of the saved Project (Phase 5 STEP 14).
///
/// Selection is the domain rule `RepresentativeThumbnailSource`: the FIRST active Clip in CURRENT
/// logical order whose committed media is available (`ClipAvailabilityChecking`, STEP 13). Pending /
/// deleted Clips are never candidates, unavailable Clips are skipped for this purpose only, and a
/// Project with no usable source keeps the neutral placeholder. The thumbnail comes from the STEP 8
/// `ClipThumbnailProviding` boundary (Project-owned committed media, effective-range midpoint, memory
/// cache, in-flight coalescing) — no second thumbnail framework.
///
/// Stale-result protection: a generated image is published only if its `ClipThumbnailRequest`
/// (Project + Clip identity + media path + trim range + pixel budget) is still exactly the current
/// representative request at the moment it arrives; every refresh re-derives that request from the
/// repository, so reorder / delete / undo / redo / replace / availability change / Safe Atomic
/// Replacement / Project deletion all invalidate late results by identity, never by index. The
/// identity carries what the effective edit state models today (trim range); Phase 7 extends the
/// same request boundary when Framing / an edit revision become real — consumers never key by index.
/// Views consume the published state only; they hold no Project-domain selection logic.
@Observable
@MainActor
final class ProjectRepresentativeModel {
    /// Pixel budget of the Projects-screen representative visual (DESIGN §11: 80 × 80 pt rounded
    /// square, aspect fill) at the iPhone 3× scale. Fixed, so the request identity is stable.
    static let thumbnailPixelSize = ClipThumbnailPixelSize(points: CGSize(width: 80, height: 80), scale: 3)

    private(set) var state: ProjectRepresentativeState = .noProject
    /// Identity of the current representative thumbnail (nil = no usable source / no Project).
    private(set) var currentRequest: ClipThumbnailRequest?
    /// Number of completed refreshes (tests / diagnostics only).
    private(set) var refreshCount = 0

    @ObservationIgnored private let savedProject: @MainActor () throws -> VlogProject?
    @ObservationIgnored private let availability: any ClipAvailabilityChecking
    @ObservationIgnored private let thumbnails: any ClipThumbnailProviding
    @ObservationIgnored private let lifecycle: ProjectLifecycleOperationGate?
    /// Refresh generation: only the newest refresh may publish a SELECTION; images are additionally
    /// validated by request identity.
    private var generation = 0
    /// Small session cache keyed by request identity, so returning to a previously shown
    /// representative (reorder back, Undo) never flickers through the placeholder. Disposable.
    private var images: [ClipThumbnailRequest: CGImage] = [:]
    private var imageOrder: [ClipThumbnailRequest] = []
    private static let imageCacheLimit = 8

    /// - Parameters:
    ///   - savedProject: the canonical V1 saved-Project rule (`ProjectCompositionCoordinator.lastSavedProject`).
    ///   - lifecycle: when given, the Project read waits its turn behind cleanup / composition
    ///     (ADR-039), so a refresh scheduled by an Editor exit observes the reconciled Project.
    init(
        savedProject: @escaping @MainActor () throws -> VlogProject?,
        availability: any ClipAvailabilityChecking,
        thumbnails: any ClipThumbnailProviding,
        lifecycle: ProjectLifecycleOperationGate? = nil
    ) {
        self.savedProject = savedProject
        self.availability = availability
        self.thumbnails = thumbnails
        self.lifecycle = lifecycle
    }

    /// Fire-and-forget refresh for view lifecycle hooks; never blocks the caller.
    func scheduleRefresh() {
        Task { await refresh() }
    }

    /// Re-derives the representative from the CURRENT saved Project: read → first available active
    /// Clip in logical order → publish selection (placeholder or cached image) → generate the image
    /// asynchronously if not cached. Runs on every relevant state boundary (app start, scene
    /// activation, navigation outside a live Editor session); there is no timer and no polling.
    func refresh() async {
        generation += 1
        let mine = generation
        let loaded: VlogProject?
        do {
            if let lifecycle {
                loaded = try await lifecycle.withExclusiveAccess { try savedProject() }
            } else {
                loaded = try savedProject()
            }
        } catch {
            // A lookup failure is not a state change: keep what is shown and try again next time.
            let details = error as NSError
            MellowLog.app.error("Representative lookup failed: domain=\(details.domain, privacy: .public), code=\(details.code)")
            return
        }
        guard mine == generation else { return }
        guard let project = loaded else {
            publish(.noProject, request: nil, generation: mine)
            return
        }
        // Availability is asked in logical order and stops at the first usable Clip; the domain rule
        // itself stays the pure `RepresentativeThumbnailSource`.
        var usable: Set<UUID> = []
        for clip in project.clips {
            if await availability.availability(for: clip) == .available { usable.insert(clip.id); break }
            guard mine == generation else { return }
        }
        guard mine == generation else { return }
        guard let clipID = RepresentativeThumbnailSource.clipID(in: project, isUsable: { usable.contains($0.id) }),
              let clip = project.clips.first(where: { $0.id == clipID }) else {
            publish(.project(id: project.id, thumbnail: nil), request: nil, generation: mine)
            return
        }
        let request = ClipThumbnailRequest(clip: clip, maximumPixelSize: Self.thumbnailPixelSize)
        publish(.project(id: project.id, thumbnail: images[request]), request: request, generation: mine)
        guard images[request] == nil else { return }
        let thumbnails = self.thumbnails
        let outcome: Result<CGImage, Error>
        do { outcome = .success(try await thumbnails.thumbnail(for: request)) } catch { outcome = .failure(error) }
        applyThumbnailResult(outcome, for: request)
    }

    private func publish(_ newState: ProjectRepresentativeState, request: ClipThumbnailRequest?, generation mine: Int) {
        guard mine == generation else { return }
        currentRequest = request
        if newState != state { state = newState }
        refreshCount += 1
    }

    /// Identity-validated publication (ARCHITECTURE §56 late-result rule): the image lands only if the
    /// request it answers is still exactly the current representative request — same Project, same
    /// Clip identity, same media path, same trim range, same pixel budget. Anything else is a late
    /// result for a superseded selection and is dropped. A failure changes nothing: the placeholder
    /// stays, the Clip stays healthy (thumbnail failure ≠ structural unavailability, STEP 13).
    func applyThumbnailResult(_ result: Result<CGImage, Error>, for request: ClipThumbnailRequest) {
        guard case .success(let image) = result else { return }
        remember(image, for: request)
        guard request == currentRequest, case .project(let id, _) = state, id == request.projectID else { return }
        state = .project(id: id, thumbnail: image)
    }

    private func remember(_ image: CGImage, for request: ClipThumbnailRequest) {
        images[request] = image
        imageOrder.removeAll { $0 == request }
        imageOrder.append(request)
        while imageOrder.count > Self.imageCacheLimit, let oldest = imageOrder.first {
            imageOrder.removeFirst()
            images[oldest] = nil
        }
    }
}
