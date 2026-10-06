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
    /// Called when one of several Editor routes for the same Project left the path (not an Editor exit).
    @ObservationIgnored var onProjectEditorRouteInstanceRemoved: ((UUID) -> Void)?

    var path: [Route] = [] {
        didSet {
            // Per-route identity: any route whose count on the path changed gets a new generation (sheets, pickers and
            // view disappearance never change the path). Updated before any removal callback runs.
            for route in Set(oldValue).union(path) where oldValue.filter({ $0 == route }).count != path.filter({ $0 == route }).count {
                routeGenerations[route, default: 0] += 1
            }
            let before = Set(oldValue.compactMap(Self.editorProjectID))
            let after = Set(path.compactMap(Self.editorProjectID))
            for projectID in before.subtracting(after) {
                onProjectEditorRouteRemoved?(projectID)
            }
            // An Editor route instance left while another Editor for the same Project stays on the path: no Editor exit,
            // but an operation started from the removed instance must still see its route go (D7b §4).
            for projectID in before.intersection(after)
            where oldValue.filter({ $0 == .projectEditor(projectID) }).count > path.filter({ $0 == .projectEditor(projectID) }).count {
                onProjectEditorRouteInstanceRemoved?(projectID)
            }
            let projectsBefore = oldValue.filter { $0 == .projectsEntry }.count
            let projectsAfter = path.filter { $0 == .projectsEntry }.count
            if projectsAfter < projectsBefore { onProjectsEntryRouteRemoved?() }
        }
    }

    /// Changes for a route whenever its count on the path changes — never for sheets, pickers or view appearance,
    /// which do not change the path (ADR-050 050-D D7b §4 route identity).
    @ObservationIgnored private var routeGenerations: [Route: Int] = [:]

    var projectsEntryGeneration: Int { routeGenerations[.projectsEntry, default: 0] }

    /// A liveness check for an operation started from `route` now: false once that route was removed (or replaced by a
    /// new one). An operation started while the route is not on the path stays live until the route's count changes.
    func routeProbe(for route: Route) -> () -> Bool {
        let generation = routeGenerations[route, default: 0]
        let wasOnPath = path.contains(route)
        return { [weak self] in
            guard let self else { return false }
            return self.routeGenerations[route, default: 0] == generation && (!wasOnPath || self.path.contains(route))
        }
    }

    func projectsEntryRouteProbe() -> () -> Bool { routeProbe(for: .projectsEntry) }

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
