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

    var path: [Route] = [] {
        didSet {
            let before = Set(oldValue.compactMap(Self.editorProjectID))
            let after = Set(path.compactMap(Self.editorProjectID))
            for projectID in before.subtracting(after) {
                onProjectEditorRouteRemoved?(projectID)
            }
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
