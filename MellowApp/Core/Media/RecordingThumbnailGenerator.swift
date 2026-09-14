import AVFoundation
import CoreGraphics

/// Produces one small representative frame from a finalized staging clip, for the camera preview
/// tile (Phase 4 visual feedback only — no Clip Review, no project). It reads ONLY the app-private
/// staging movie URL; it never touches the Photos library, so add-only access is preserved.
@MainActor
protocol RecordingThumbnailGenerating: AnyObject {
    /// Returns a representative frame, or nil if one cannot be produced. Never throws: thumbnail
    /// generation is best-effort and must never affect the recording/save outcome.
    func thumbnail(for url: URL) async -> CGImage?
}

@MainActor
final class AVAssetRecordingThumbnailGenerator: RecordingThumbnailGenerating {
    /// Upper bound for the decoded frame. The tile is tiny, so a full-resolution decode is wasted
    /// work and memory; AVAssetImageGenerator scales down while preserving aspect ratio.
    private let maximumPixelSize: CGSize

    init(maximumPixelSize: CGSize = CGSize(width: 320, height: 320)) {
        self.maximumPixelSize = maximumPixelSize
    }

    func thumbnail(for url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        // Portrait recordings carry their orientation in the track transform; apply it so the tile
        // matches playback rather than showing a rotated frame.
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumPixelSize
        // A representative early frame. Loose tolerances let AVFoundation return the nearest decoded
        // keyframe instead of scanning for an exact time.
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        // The async API performs the decode off the main thread; awaiting only suspends here. Any
        // failure (unreadable file, no video track) resolves to nil and is swallowed by design.
        do {
            let (image, _) = try await generator.image(at: time)
            return image
        } catch {
            return nil
        }
    }
}
