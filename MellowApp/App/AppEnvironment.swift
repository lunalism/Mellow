import Observation
import SwiftData

@Observable
@MainActor
final class AppEnvironment {
    let router: AppRouter
    let projectRepository: any ProjectRepository
    let home: HomeModel
    let modelContainer: ModelContainer

    init(
        router: AppRouter? = nil,
        modelContainer: ModelContainer = MellowModelContainer.shared
    ) {
        let router = router ?? AppRouter()
        self.router = router
        self.modelContainer = modelContainer
        let repository = SwiftDataProjectRepository(
            modelContext: modelContainer.mainContext
        )
        self.projectRepository = repository
        self.home = HomeModel(repository: repository, router: router)
    }
}
