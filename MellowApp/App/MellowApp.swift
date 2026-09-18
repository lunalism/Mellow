import SwiftUI
import SwiftData

@main
@MainActor
struct MellowApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            if isPhase6MediaSpike {
                #if DEBUG
                // Phase 6 Technical Device Spike: DEBUG-only diagnostic surface, reachable solely via
                // `-Phase6MediaSpike`. Replaces the root so no Camera / Projects UI is entered; never
                // touches Project media, SwiftData rows or Photos originals. Remove with `Spike/`.
                Phase6MediaSpikeView()
                #endif
            } else {
                HomeView(model: environment.home)
                    .environment(environment)
                    .preferredColorScheme(uiTestColorScheme)
            }
        }
        .modelContainer(environment.modelContainer)
    }

    private var isPhase6MediaSpike: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-Phase6MediaSpike")
        #else
        return false
        #endif
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
