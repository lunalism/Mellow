import Foundation

/// Best-effort launch-time recovery of crash-left staging files (ADR-033). The directory
/// listing is the only durable identity; there is no manifest.
struct RecordingRecoveryReport: Equatable, Sendable {
    var saved: [URL] = []
    var retained: [URL] = []
    var deleted: [URL] = []
}

@MainActor
struct RecordingRecovery {
    let staging: any RecordingStagingStoring
    let inspector: any RecordingMediaInspecting
    let photos: any PhotosLibrarySaving
    /// Files newer than this may belong to a recording in progress and are left alone.
    var minimumAge: TimeInterval = 5

    @discardableResult
    func run(now: Date = Date()) async -> RecordingRecoveryReport {
        var report = RecordingRecoveryReport()
        for url in await staging.stagedFiles() {
            if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               now.timeIntervalSince(modified) < minimumAge {
                continue
            }
            let info = await inspector.inspect(url)
            let verdict = RecordingPolicy.judge(duration: info.duration, selectedMaximum: RecordingPolicy.absoluteMaximumDuration)
            guard info.isPlayable, info.hasVideoTrack, verdict != .tooShort else {
                await staging.remove(url)
                report.deleted.append(url)
                continue
            }
            guard photos.authorization == .authorized else { report.retained.append(url); continue }
            do {
                try await photos.save(videoAt: url)
                await staging.remove(url)
                report.saved.append(url)
            } catch {
                report.retained.append(url)
            }
        }
        return report
    }
}
