import Observation

@Observable
final class AppEnvironment {
    let router: AppRouter

    init(router: AppRouter = AppRouter()) {
        self.router = router
    }
}
