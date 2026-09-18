#if DEBUG
import CoreGraphics
import CoreMedia
import Foundation

// MARK: - Phase 6 Technical Device Spike (DEBUG-only, disposable)
//
// Pure, testable policy candidates under evaluation for the Phase 6 Technical Decision Gate.
// Nothing here is production behavior: the accepted validator (`Phase5ReadyMediaValidator`) is
// untouched, no Project / Clip rows are created, and the whole `Spike/` directory is meant to be
// deleted before Phase 6 production implementation.

/// Exact `CMTime` eligibility against the inclusive 1.0–5.0 s product boundary (ADR-042).
/// No `Double`, no frame tolerance: `CMTimeCompare` on the rational value.
enum Phase6SpikeDurationEligibility: Equatable {
    case eligible
    case belowMinimum
    case aboveMaximum
    case invalid

    static let minimum = CMTime(value: 1, timescale: 1)
    static let maximum = CMTime(value: 5, timescale: 1)

    static func classify(_ duration: CMTime) -> Phase6SpikeDurationEligibility {
        // Invalid / indefinite / infinite compare as "greater" in CMTimeCompare — guard first.
        guard duration.isNumeric else { return .invalid }
        if CMTimeCompare(duration, minimum) < 0 { return .belowMinimum }
        if CMTimeCompare(duration, maximum) > 0 { return .aboveMaximum }
        return .eligible
    }
}

/// 1080p-class bounding-box working raster: scale DOWN only so long edge ≤ 1920 and short edge
/// ≤ 1080, keep the full presentation frame (no crop / pad), round each dimension to even.
enum Phase6SpikeRaster {
    static let maximumLongEdge: CGFloat = 1920
    static let maximumShortEdge: CGFloat = 1080

    static func scale(forPresentation size: CGSize) -> CGFloat {
        let long = max(size.width, size.height), short = min(size.width, size.height)
        guard long > 0, short > 0 else { return 1 }
        return min(1, maximumLongEdge / long, maximumShortEdge / short)
    }

    static func boundingBox(forPresentation size: CGSize) -> CGSize {
        let s = scale(forPresentation: size)
        return CGSize(width: even(size.width * s), height: even(size.height * s))
    }

    /// Largest even integer ≤ value (never exceeds the scaled size, so an odd-sized source is never
    /// upscaled by a pixel; at most 1 px is dropped per edge). Minimum 2.
    static func even(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded(.down) * 2)
    }
}

/// ADR-043 Revision 1 orientation eligibility: presentation geometry after `preferredTransform`,
/// strictly `height > width`. Landscape (`<`) and square (`==`) are ONE non-portrait category that is
/// preflight-unsupported — never a normalization reason, never copied / remuxed / normalized, never
/// converted, cropped, padded or rotated. `naturalSize` alone must never decide.
enum Phase6SpikeOrientationEligibility: Equatable {
    case portrait
    case nonPortrait(NonPortraitShape)

    enum NonPortraitShape: String, Equatable { case landscape, square }

    static func presentationSize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let presented = naturalSize.applying(preferredTransform)
        return CGSize(width: abs(presented.width), height: abs(presented.height))
    }

    static func classify(presentationSize p: CGSize) -> Phase6SpikeOrientationEligibility {
        if p.height > p.width { return .portrait }
        return .nonPortrait(p.height == p.width ? .square : .landscape)
    }

    static func classify(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> Phase6SpikeOrientationEligibility {
        classify(presentationSize: presentationSize(naturalSize: naturalSize, preferredTransform: preferredTransform))
    }

    var isEligible: Bool { self == .portrait }
}

/// Container identity from the ISO BMFF `ftyp` box (major / compatible brands). AVFoundation opens
/// files by content, so the file-name extension proves nothing — this is what the spike reports.
enum Phase6SpikeContainer: String, Equatable {
    case quickTime = "QuickTime (qt  )"
    case mp4 = "MP4 / ISO BMFF"
    case unknown = "unknown"

    static func sniff(headerBytes data: Data) -> (container: Phase6SpikeContainer, brands: String) {
        guard data.count >= 12 else { return (.unknown, "") }
        let bytes = [UInt8](data)
        guard String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" else { return (.unknown, "no ftyp") }
        let boxSize = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        let end = min(bytes.count, max(12, boxSize))
        var brands: [String] = []
        var index = 8
        while index + 4 <= end {
            if index == 12 { index += 4; continue } // minor version
            brands.append(String(bytes: bytes[index..<index + 4], encoding: .ascii) ?? "????")
            index += 4
        }
        let joined = brands.joined(separator: ",")
        if brands.first == "qt  " || brands.contains("qt  ") { return (.quickTime, joined) }
        return (brands.isEmpty ? .unknown : .mp4, joined)
    }
}

/// The intended Phase 6 route for one inspected item (candidate predicate, not production).
/// ADR-044: only an actual QuickTime Movie container is eligible; there is no remux / rewrap route.
enum Phase6SpikePath: String, Equatable {
    case readyQuickTimeFastPath = "Ready QuickTime · fast path (copy)"
    case normalizeH264 = "Normalize → H.264 8-bit 709 QuickTime"
    case preflightInvalid = "Preflight invalid"
    /// ADR-044: actual MP4 / ISO BMFF, other non-QuickTime, or reliably unknown container. Decided
    /// from the `ftyp` brands read from the file, never from the extension. No copy / normalization.
    case preflightUnsupportedContainer = "Preflight unsupported · non-QuickTime container"
    /// ADR-043 Revision 1: landscape / square presentation. Distinct from `preflightInvalid` (media
    /// problem) and from every normalization reason; the converter never receives such an item.
    case preflightUnsupportedNonPortrait = "Preflight unsupported · non-portrait presentation"

    /// True only for the two routes that may run a media operation in the spike.
    var mayRunMediaOperation: Bool {
        switch self {
        case .readyQuickTimeFastPath, .normalizeH264: return true
        case .preflightInvalid, .preflightUnsupportedContainer, .preflightUnsupportedNonPortrait: return false
        }
    }
}

/// Facts the path classifier needs (a subset of the full inspection report).
struct Phase6SpikeClassificationInput: Equatable {
    var duration: CMTime
    var isReadable: Bool
    var isPlayable: Bool
    var hasProtectedContent: Bool
    var hasVideoTrack: Bool
    var container: Phase6SpikeContainer
    var videoCodec: String          // fourcc, e.g. "avc1", "hvc1", "hev1"
    var bitsPerComponent: Int?      // nil when the SDK does not expose it (H.264 commonly nil)
    var profileIsHighBitDepth: Bool // hvcC Main10 / avcC High10 etc.
    var presentationSize: CGSize
    var nominalFrameRate: Float
    var transferFunction: String?
    var colorPrimaries: String?
    var ycbcrMatrix: String? = nil
    /// `dvcC` / `dvvC` / `dvwC` sample-description atom present (Dolby Vision configuration).
    var hasDolbyVisionConfiguration: Bool = false
    /// Diagnostic only. `minFrameDuration` is the SHORTEST frame in the track (AVAssetTrack.h: "the
    /// minimum duration of the track's frames"); iPhone captures routinely contain one short frame
    /// (e.g. 19/600 s in a 29.987 fps track), so disagreement with `nominalFrameRate` does not prove
    /// variable frame rate and must never make an otherwise-ready source require normalization.
    var isVariableFrameRateSuspected: Bool

    var reasons: [String] = []
}

enum Phase6SpikePathClassifier {
    static let maximumFrameRate: Float = 30

    static func classify(_ i: Phase6SpikeClassificationInput) -> (path: Phase6SpikePath, reasons: [String]) {
        var reasons: [String] = []
        switch Phase6SpikeDurationEligibility.classify(i.duration) {
        case .invalid: return (.preflightInvalid, ["duration not numeric"])
        case .belowMinimum: return (.preflightInvalid, ["duration < 1.0 s"])
        case .aboveMaximum: return (.preflightInvalid, ["duration > 5.0 s"])
        case .eligible: break
        }
        guard i.isReadable else { return (.preflightInvalid, ["not readable"]) }
        guard i.hasVideoTrack else { return (.preflightInvalid, ["no video track"]) }
        if i.hasProtectedContent { return (.preflightInvalid, ["protected content"]) }
        // ADR-044: container eligibility is decided on the sniffed brands only (extension is not
        // authoritative) and before any normalization reasoning; MP4 and unknown are both unsupported.
        switch i.container {
        case .quickTime: break
        case .mp4: return (.preflightUnsupportedContainer, ["actual container is MP4 / ISO BMFF (\(i.videoCodec)); QuickTime Movie required (ADR-044), no remux"])
        case .unknown: return (.preflightUnsupportedContainer, ["container brand unknown / not reliably QuickTime; QuickTime Movie required (ADR-044)"])
        }
        // ADR-043 Revision 1: orientation is decided on presentation geometry only, before any
        // normalization reasoning, so a non-portrait source can never become normalization-required.
        if case .nonPortrait(let shape) = Phase6SpikeOrientationEligibility.classify(presentationSize: i.presentationSize) {
            return (.preflightUnsupportedNonPortrait, ["non-portrait presentation (\(shape.rawValue)) \(Int(i.presentationSize.width))×\(Int(i.presentationSize.height)); presentationHeight > presentationWidth required"])
        }
        if !i.isPlayable { reasons.append("isPlayable == false") }

        // Any reliable HDR / Dolby Vision signal is a normalization reason (never fast-path copy).
        var hdrSignals: [String] = []
        if i.transferFunction == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) { hdrSignals.append("HLG transfer") }
        if i.transferFunction == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) { hdrSignals.append("PQ transfer") }
        if i.colorPrimaries == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String) { hdrSignals.append("Rec.2020 primaries") }
        if i.ycbcrMatrix == (kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String) { hdrSignals.append("Rec.2020 matrix") }
        if (i.bitsPerComponent ?? 8) > 8 { hdrSignals.append("\(i.bitsPerComponent ?? 0)-bit") }
        if i.profileIsHighBitDepth { hdrSignals.append("10-bit profile") }
        if i.hasDolbyVisionConfiguration { hdrSignals.append("Dolby Vision config atom") }
        if !hdrSignals.isEmpty { reasons.append("HDR / >8-bit (\(hdrSignals.joined(separator: ", ")))") }
        let long = max(i.presentationSize.width, i.presentationSize.height)
        let short = min(i.presentationSize.width, i.presentationSize.height)
        if long > Phase6SpikeRaster.maximumLongEdge || short > Phase6SpikeRaster.maximumShortEdge { reasons.append("raster > 1080p-class") }
        if i.nominalFrameRate > maximumFrameRate + 0.5 { reasons.append("frame rate > 30") }
        // `isVariableFrameRateSuspected` is intentionally NOT a trigger (see the field's comment).
        let codecReady = i.videoCodec == "avc1" || i.videoCodec == "hvc1" || i.videoCodec == "hev1"
        if !codecReady { reasons.append("codec \(i.videoCodec) not in pass-through set") }

        if !reasons.isEmpty {
            return (.normalizeH264, reasons)
        }
        return (.readyQuickTimeFastPath, [])
    }
}

/// Pure acceptance contract for a normalized SDR output (diagnostic gate, not production). An
/// output is a valid SDR result only when it is a QuickTime H.264 8-bit file tagged
/// Rec.709 / Rec.709 / Rec.709 with NO remaining HLG / PQ / Rec.2020 / Dolby Vision / HDR
/// metadata signaling, an identity transform, a portrait presentation and <= 30 fps. Tags alone do
/// not prove tone-mapping quality — that needs the on-device A/B visual check.
enum Phase6SpikeSDROutputContract {
    static let requiredPrimaries = kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String
    static let requiredTransfer = kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String
    static let requiredMatrix = kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String

    struct Facts: Equatable {
        var container: Phase6SpikeContainer
        var videoCodec: String
        var profileDescription: String
        var profileIsHighBitDepth: Bool
        var bitsPerComponent: Int?
        var colorPrimaries: String?
        var transferFunction: String?
        var ycbcrMatrix: String?
        var hdrMetadataNotes: [String]
        var preferredTransform: CGAffineTransform
        var presentationSize: CGSize
        var nominalFrameRate: Float
        var isReadable: Bool
        var isPlayable: Bool
        var hasVideoTrack: Bool
    }

    /// Empty = valid SDR output. Each entry is one concrete violation.
    static func problems(_ f: Facts) -> [String] {
        var out: [String] = []
        if f.container != .quickTime { out.append("container is \(f.container.rawValue), not QuickTime") }
        if !f.hasVideoTrack { out.append("no video track") }
        if !f.isReadable || !f.isPlayable { out.append("not readable/playable") }
        if f.videoCodec != "avc1" { out.append("codec \(f.videoCodec) is not H.264 (avc1)") }
        if f.profileIsHighBitDepth { out.append("high-bit-depth profile \(f.profileDescription)") }
        if let bpc = f.bitsPerComponent, bpc != 8 { out.append("\(bpc) bits per component") }
        if f.colorPrimaries != requiredPrimaries { out.append("primaries \(f.colorPrimaries ?? "untagged") != Rec.709") }
        if f.transferFunction != requiredTransfer { out.append("transfer \(f.transferFunction ?? "untagged") != Rec.709") }
        if f.ycbcrMatrix != requiredMatrix { out.append("matrix \(f.ycbcrMatrix ?? "untagged") != Rec.709") }
        if f.transferFunction == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) { out.append("HLG signaling remains") }
        if f.transferFunction == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) { out.append("PQ signaling remains") }
        if f.colorPrimaries == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String) || f.ycbcrMatrix == (kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String) { out.append("Rec.2020 signaling remains") }
        if !f.hdrMetadataNotes.isEmpty { out.append("HDR / Dolby Vision metadata remains: \(f.hdrMetadataNotes.joined(separator: "; "))") }
        if !f.preferredTransform.isIdentity { out.append("output transform is not identity") }
        if !(f.presentationSize.height > f.presentationSize.width) { out.append("output presentation is not portrait (\(Int(f.presentationSize.width))×\(Int(f.presentationSize.height)))") }
        if f.nominalFrameRate > Phase6SpikePathClassifier.maximumFrameRate + 0.5 { out.append("frame rate \(f.nominalFrameRate) > 30") }
        return out
    }
}

/// Shared, idempotent cancellation signal for one conversion run. The manual `취소` button and the
/// deterministic auto-cancel threshold both go through `requestCancel`; the first request wins and
/// is recorded, later requests only increment the counter. Safe from any thread.
final class Phase6SpikeCancellationToken: @unchecked Sendable {
    enum Source: String { case manual, automatic }

    private let lock = NSLock()
    private(set) var isCancelled = false
    private(set) var source: Source?
    private(set) var requestedAt: Date?
    private(set) var requestedProgress: Double?
    private(set) var requestCount = 0

    /// Returns true only for the request that actually cancelled the run.
    @discardableResult
    func requestCancel(source: Source, progress: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        requestCount += 1
        guard !isCancelled else { return false }
        isCancelled = true; self.source = source; requestedAt = Date(); requestedProgress = progress
        return true
    }
}

/// Deterministic cancellation trigger: fires exactly once, on the first sample-based progress
/// value at or above the threshold. OFF (nil threshold) never fires and adds no work.
enum Phase6SpikeAutoCancel {
    static let threshold = 0.35

    static func shouldFire(threshold: Double?, progress: Double, alreadyFired: Bool) -> Bool {
        guard let threshold, !alreadyFired else { return false }
        return progress >= threshold
    }
}

/// Spike-owned scratch directory: a sibling of the production `Mellow/` root, never inside it, so
/// STEP 12A / 12B never enumerate it and no canonical Project path can be touched.
struct Phase6SpikeDirectory {
    let root: URL

    static let componentName = "MellowPhase6MediaSpike"

    init(root: URL) { self.root = root }

    static func `default`() -> Phase6SpikeDirectory {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Phase6SpikeDirectory(root: support.appendingPathComponent(componentName, isDirectory: true))
    }

    var sourcesDirectory: URL { root.appendingPathComponent("sources", isDirectory: true) }
    var outputsDirectory: URL { root.appendingPathComponent("outputs", isDirectory: true) }
    /// One JSON record per attempted run (`results/<run-id>.json`), spike-only, removed by cleanup.
    var resultsDirectory: URL { root.appendingPathComponent("results", isDirectory: true) }

    /// True when `url` is inside the spike root (path-prefix check on standardized paths).
    func owns(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resultsDirectory, withIntermediateDirectories: true)
    }

    /// Idempotent: removes everything the spike created and nothing else. Missing root = success.
    @discardableResult
    func cleanup() -> (removed: Bool, error: Error?) {
        guard FileManager.default.fileExists(atPath: root.path) else { return (false, nil) }
        do { try FileManager.default.removeItem(at: root); return (true, nil) } catch { return (false, error) }
    }

    func leftovers() -> [String] {
        guard let items = try? FileManager.default.subpathsOfDirectory(atPath: root.path) else { return [] }
        return items.filter { !$0.hasSuffix("sources") && !$0.hasSuffix("outputs") && !$0.hasSuffix("results") }
    }
}
#endif
