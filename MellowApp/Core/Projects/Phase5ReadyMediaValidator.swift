import AVFoundation
import Foundation

/// What Phase-5-ready validation needs to know about a transferred source, read from the actual
/// media (never from filename, dates or heuristics).
struct ProjectMediaInfo: Equatable, Sendable {
    var isReadable: Bool
    var hasVideoTrack: Bool
    var hasAudioTrack: Bool
    var duration: TimeInterval
    /// Presentation size after the track's preferred transform (portrait clips report height > width).
    var presentationSize: CGSize
    var nominalFrameRate: Float
    var isHDR: Bool
}

protocol ProjectMediaInspecting: Sendable {
    func inspect(_ url: URL) async -> ProjectMediaInfo
}

/// Reads the real timeline / track properties through AVURLAsset.
struct AVAssetProjectMediaInspector: ProjectMediaInspecting {
    func inspect(_ url: URL) async -> ProjectMediaInfo {
        let unreadable = ProjectMediaInfo(isReadable: false, hasVideoTrack: false, hasAudioTrack: false, duration: 0, presentationSize: .zero, nominalFrameRate: 0, isHDR: false)
        let asset = AVURLAsset(url: url)
        do {
            let (readable, duration, tracks) = try await asset.load(.isReadable, .duration, .tracks)
            guard let video = tracks.first(where: { $0.mediaType == .video }) else {
                return ProjectMediaInfo(isReadable: readable, hasVideoTrack: false, hasAudioTrack: tracks.contains { $0.mediaType == .audio }, duration: duration.isNumeric ? duration.seconds : 0, presentationSize: .zero, nominalFrameRate: 0, isHDR: false)
            }
            let (naturalSize, transform, frameRate, formats) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
            let presented = naturalSize.applying(transform)
            let size = CGSize(width: abs(presented.width), height: abs(presented.height))
            let hdr = formats.contains { description in
                guard let transfer = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String else { return false }
                return transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
                    || transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
            }
            return ProjectMediaInfo(
                isReadable: readable,
                hasVideoTrack: true,
                hasAudioTrack: tracks.contains { $0.mediaType == .audio },
                duration: duration.isNumeric ? duration.seconds : 0,
                presentationSize: size,
                nominalFrameRate: frameRate,
                isHDR: hdr
            )
        } catch {
            return unreadable
        }
    }
}

/// ADR-034 §2 boundary: a source is Phase-5-ready only if it can become a `VlogClip` with no Phase-6
/// preparation. Everything that would need Phase 6/7 (segment selection, SDR conversion,
/// resolution / frame-rate normalization, framing of a non-portrait source) is `requiresImportPreparation`;
/// unreadable data is `invalid`. Validation never mutates anything.
enum Phase5ReadyVerdict: Equatable, Sendable {
    enum PreparationReason: Equatable, Sendable { case tooLong, highDynamicRange, resolution, frameRate, orientation }
    enum InvalidReason: Equatable, Sendable { case unreadable, noVideoTrack, zeroDuration }

    case ready(sourceDuration: MediaTime)
    case requiresImportPreparation(PreparationReason)
    case invalid(InvalidReason)
}

struct Phase5ReadyMediaValidator: Sendable {
    let inspector: any ProjectMediaInspecting

    /// Project working-media targets already accepted for imported clips (F-MVP-021): 1080p-class,
    /// 30 fps, SDR. Sources at or under these need no normalization; nothing above them is accepted.
    static let maximumLongEdge: CGFloat = 1920
    static let maximumShortEdge: CGFloat = 1080
    static let maximumFrameRate: Float = 30
    /// Same one-frame quantization allowance the Phase 4 capture policy applies at the 5 s stop, so a
    /// clip Mellow itself recorded at the maximum preset still reads as ready.
    static let durationTolerance: TimeInterval = RecordingPolicy.upperDurationTolerance
    private static let mediaTimescale: Int32 = 600

    func validate(_ url: URL) async -> Phase5ReadyVerdict {
        Self.judge(await inspector.inspect(url))
    }

    static func judge(_ info: ProjectMediaInfo) -> Phase5ReadyVerdict {
        guard info.isReadable else { return .invalid(.unreadable) }
        guard info.hasVideoTrack else { return .invalid(.noVideoTrack) }
        guard info.duration.isFinite, info.duration > 0 else { return .invalid(.zeroDuration) }
        // Order: the reason reported is the first Phase-6 capability the source would need.
        let maximum = Double(ClipPolicy.maximumDuration.value) / Double(ClipPolicy.maximumDuration.timescale)
        guard info.duration <= maximum + durationTolerance else { return .requiresImportPreparation(.tooLong) }
        guard !info.isHDR else { return .requiresImportPreparation(.highDynamicRange) }
        let longEdge = max(info.presentationSize.width, info.presentationSize.height)
        let shortEdge = min(info.presentationSize.width, info.presentationSize.height)
        guard longEdge <= maximumLongEdge, shortEdge <= maximumShortEdge else { return .requiresImportPreparation(.resolution) }
        guard info.nominalFrameRate <= maximumFrameRate + 0.5 else { return .requiresImportPreparation(.frameRate) }
        // V1 Projects are Portrait (ADR-032/033); a non-portrait presentation needs Phase 7 framing.
        guard info.presentationSize.height > info.presentationSize.width else { return .requiresImportPreparation(.orientation) }
        // Clamp only the tolerance overshoot so the clip metadata itself obeys the 5 s invariant.
        let seconds = min(info.duration, maximum)
        guard let duration = try? MediaTime(value: Int64((seconds * Double(mediaTimescale)).rounded()), timescale: mediaTimescale) else {
            return .invalid(.zeroDuration)
        }
        return .ready(sourceDuration: duration)
    }
}
