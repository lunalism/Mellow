import Foundation
import Observation

@Observable
@MainActor
final class AppRouter {
    enum Route: Hashable {
        case recent
        case camera(UUID)
        case projectEditor(UUID)
    }

    var path: [Route] = []
}
