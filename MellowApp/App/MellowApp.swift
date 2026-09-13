import SwiftUI
import SwiftData

@main
@MainActor
struct MellowApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            HomeView(model: environment.home)
                .environment(environment)
        }
        .modelContainer(environment.modelContainer)
    }
}
