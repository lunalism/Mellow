import SwiftUI
import SwiftData

@main
@MainActor
struct MellowApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            MellowBootstrapView()
                .environment(environment)
        }
        .modelContainer(environment.modelContainer)
    }
}

private struct MellowBootstrapView: View {
    var body: some View {
        Text("Mellow")
    }
}
