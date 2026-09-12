import Foundation
import OSLog

enum MellowLog {
    static let app = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.example.Mellow",
        category: "app"
    )
}
