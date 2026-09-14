import Foundation
import OSLog

enum MellowLog {
    static let app = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.example.Mellow",
        category: "app"
    )
    /// Structured, low-volume recording pipeline events (finalize/validate/save). Never logs media
    /// contents; no per-frame/progress spam.
    static let recording = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.example.Mellow",
        category: "recording"
    )
}
