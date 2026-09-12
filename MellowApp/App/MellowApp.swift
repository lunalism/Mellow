import SwiftUI

@main
struct MellowApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            MellowBootstrapView()
                .environment(environment)
        }
    }
}

private struct MellowBootstrapView: View {
    var body: some View {
        Text("Mellow")
    }
}
