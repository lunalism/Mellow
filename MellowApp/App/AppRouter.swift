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

    var path: [Route] = []
}
