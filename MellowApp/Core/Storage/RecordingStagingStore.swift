import Foundation

/// Owns the app-private capture staging directory. Files here are recording infrastructure:
/// they exist from `startRecording` until Photos takes ownership or recovery discards them.
/// Never `tmp/` — crash-left files must survive to the next launch.
protocol RecordingStagingStoring: Sendable {
    func newRecordingURL() async throws -> URL
    func stagedFiles() async -> [URL]
    func remove(_ url: URL) async
    func usableCapacityBytes() async -> Int64
}

actor RecordingStagingStore: RecordingStagingStoring {
    private let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = support.appendingPathComponent("Mellow/CaptureStaging", isDirectory: true)
        }
    }

    func newRecordingURL() async throws -> URL {
        try ensureDirectory()
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
    }

    func stagedFiles() async -> [URL] {
        (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension.lowercased() == "mov" } ?? []
    }

    func remove(_ url: URL) async {
        try? fileManager.removeItem(at: url)
    }

    func usableCapacityBytes() async -> Int64 {
        try? ensureDirectory()
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func ensureDirectory() throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
