import Observation
import SwiftData

@Observable
@MainActor
final class AppEnvironment {
    let router: AppRouter
    let projectRepository: any ProjectRepository
    let modelContainer: ModelContainer

    init(
        router: AppRouter = AppRouter(),
        modelContainer: ModelContainer = MellowModelContainer.shared
    ) {
        self.router = router
        self.modelContainer = modelContainer
        self.projectRepository = SwiftDataProjectRepository(
            modelContext: modelContainer.mainContext
        )
    }
}
