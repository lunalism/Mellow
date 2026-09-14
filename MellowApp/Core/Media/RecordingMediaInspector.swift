import AVFoundation

/// What validation needs to know about a finalized staging file.
struct RecordingMediaInfo: Equatable, Sendable {
    var isPlayable: Bool
    var hasVideoTrack: Bool
    var duration: TimeInterval
}

protocol RecordingMediaInspecting: Sendable {
    func inspect(_ url: URL) async -> RecordingMediaInfo
}

/// Reads the actual media timeline through AVURLAsset; UI elapsed time never decides validity.
struct AVAssetRecordingMediaInspector: RecordingMediaInspecting {
    func inspect(_ url: URL) async -> RecordingMediaInfo {
        let asset = AVURLAsset(url: url)
        do {
            let (playable, duration, tracks) = try await asset.load(.isPlayable, .duration, .tracks)
            let hasVideo = tracks.contains { $0.mediaType == .video }
            let seconds = duration.isNumeric ? duration.seconds : 0
            return RecordingMediaInfo(isPlayable: playable, hasVideoTrack: hasVideo, duration: seconds)
        } catch {
            return RecordingMediaInfo(isPlayable: false, hasVideoTrack: false, duration: 0)
        }
    }
}
