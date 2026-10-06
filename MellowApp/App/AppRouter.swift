import Foundation
import Observation

@Observable
@MainActor
final class AppRouter {
    enum Route: Hashable {
        case recent
        case camera(UUID)
        /// Phase 5 dedicated Projects screen (ADR-035). Canonical: Camera → 프로젝트 → Project Editor.
        case projectsEntry
        case projectEditor(UUID)
    }

    /// Called once per Project whose `.projectEditor` route left the path (Back, pop, path reset).
    /// This is the canonical "Editor session ended" boundary (ADR-039): a sheet or picker presented
    /// over the Editor does not change the path, so it never fires for those. Set by the app
    /// environment; nil in isolation (tests) means nothing listens.
    @ObservationIgnored var onProjectEditorRouteRemoved: ((UUID) -> Void)?

    /// Called when a Projects route left the path (never for sheets, pickers or view disappearance). Listeners decide
    /// with their own operation / route identity whether it was theirs (ADR-050 050-D D7b §4 clarification).
    @ObservationIgnored var onProjectsEntryRouteRemoved: (() -> Void)?

    var path: [Route] = [] {
        didSet {
            let before = Set(oldValue.compactMap(Self.editorProjectID))
            let after = Set(path.compactMap(Self.editorProjectID))
            for projectID in before.subtracting(after) {
                onProjectEditorRouteRemoved?(projectID)
            }
            let projectsBefore = oldValue.filter { $0 == .projectsEntry }.count
            let projectsAfter = path.filter { $0 == .projectsEntry }.count
            if projectsBefore != projectsAfter {
                projectsEntryGeneration += 1
                if projectsAfter < projectsBefore { onProjectsEntryRouteRemoved?() }
            }
        }
    }

    /// Changes whenever a Projects route is added to or removed from the path — never for sheets, pickers or view
    /// appearance, which do not change the path (ADR-050 050-D D7b §4 route identity).
    @ObservationIgnored private(set) var projectsEntryGeneration = 0

    /// A liveness check for an operation started from the Projects screen now: false once that Projects route was
    /// removed (or replaced by a new one). An operation started while no Projects route is on the path stays live
    /// until the path's Projects routes change.
    func projectsEntryRouteProbe() -> () -> Bool {
        let generation = projectsEntryGeneration
        let wasOnPath = path.contains(.projectsEntry)
        return { [weak self] in
            guard let self else { return false }
            return self.projectsEntryGeneration == generation && (!wasOnPath || self.path.contains(.projectsEntry))
        }
    }

    /// Leaves the Editor for `projectID`: removes its route and everything above it, so the screen below
    /// (the Projects screen on the canonical stack) is shown again. The usual route-removal boundary fires.
    func leaveProjectEditor(_ projectID: UUID) {
        guard let index = path.lastIndex(of: .projectEditor(projectID)) else { return }
        path.removeSubrange(index...)
    }

    /// True while an Editor route for the Project is on the stack — a live Editor session.
    func hasLiveProjectEditor(for projectID: UUID) -> Bool {
        path.contains(.projectEditor(projectID))
    }

    private static func editorProjectID(_ route: Route) -> UUID? {
        if case .projectEditor(let id) = route { return id }
        return nil
    }
}
