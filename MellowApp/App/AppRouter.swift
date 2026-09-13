import Foundation
import Observation

@Observable
@MainActor
final class AppRouter {
    enum Route: Hashable {
        case recent
        case camera(UUID)
    }

    var path: [Route] = []
}
