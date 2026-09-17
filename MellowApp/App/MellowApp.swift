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
                .preferredColorScheme(uiTestColorScheme)
        }
        .modelContainer(environment.modelContainer)
    }

    /// UI-test appearance seam (`-uiTestAppearance=dark|light`): pins the scene's colour scheme so an
    /// accessibility audit can run deterministically in either appearance. Nil (production and every
    /// other launch) leaves the system appearance in charge. Never affects Release builds.
    private var uiTestColorScheme: ColorScheme? {
        #if DEBUG
        let value = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-uiTestAppearance=") }?
            .replacingOccurrences(of: "-uiTestAppearance=", with: "")
        switch value {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
        #else
        return nil
        #endif
    }
}
