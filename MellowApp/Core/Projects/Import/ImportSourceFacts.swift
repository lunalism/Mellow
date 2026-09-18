import CoreGraphics
import Foundation

// Phase 6 Photos-import preflight facts (ADR-045 §11, ADR-046). Pure value types: nothing here
// loads media, and no file URL / filename / extension exists in the model, so none can influence
// eligibility. An inspector (Step 2) fills these from the actual media; the classifier consumes them.

/// Actual container identity read from the file's own `ftyp` brands — never from the extension.
enum ImportContainer: Hashable, Sendable {
    case quickTime
    /// Any ISO Base Media brand set that is not QuickTime (`isom`, `mp42`, `3gp4`, `M4V `, …).
    case isoBaseMedia(brands: [String])
    /// A reliably identified non-ISO container (identifier kept for diagnostics).
    case other(String)
    /// No `ftyp` box or no reliable identification.
    case unknown
}

/// Reliably inspected video codec family (ADR-046 §3 / §4). Derived from the video track's format
/// description media subtype only; container, filename and Photos metadata never participate.
enum ImportVideoCodec: Hashable, Sendable {
    case h264(fourCC: String)
    case hevc(fourCC: String)
    /// Reliably identified but outside the V1 families (ProRes, ProRes RAW, MJPEG, …).
    case unsupported(fourCC: String)
    /// No format description or an empty / unreadable subtype.
    case unknown

    static let h264FourCCs: Set<String> = ["avc1", "avc3"]
    static let hevcFourCCs: Set<String> = ["hvc1", "hev1"]

    /// Maps a media-subtype FourCC to its family. Anything not in the approved alias sets is
    /// `.unsupported`; an empty identifier is `.unknown`.
    static func classify(fourCC: String) -> ImportVideoCodec {
        let code = fourCC.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return .unknown }
        if h264FourCCs.contains(fourCC) { return .h264(fourCC: fourCC) }
        if hevcFourCCs.contains(fourCC) { return .hevc(fourCC: fourCC) }
        return .unsupported(fourCC: fourCC)
    }

    var isSupportedFamily: Bool {
        switch self {
        case .h264, .hevc: return true
        case .unsupported, .unknown: return false
        }
    }
}

/// Exact source duration. `MediaTime` cannot represent an invalid / indefinite / non-numeric
/// duration, so that state is modelled explicitly instead of being coerced to a number.
enum ImportSourceDuration: Hashable, Sendable {
    case exact(MediaTime)
    case invalid
}

enum ImportColorPrimaries: Hashable, Sendable { case rec709, rec2020, other(String), unknown }
enum ImportTransferFunction: Hashable, Sendable { case rec709, hlg, pq, other(String), unknown }
enum ImportYCbCrMatrix: Hashable, Sendable { case rec709, rec2020, other(String), unknown }

/// A three-state fact for flags the media may not expose (bit depth, profile, range).
enum ImportKnownFlag: Hashable, Sendable { case yes, no, unknown }

/// Metadata that accompanies HDR content but is NOT an HDR signal on its own (ADR-045 §2,
/// ADR-046): iPhone SDR captures carry Ambient Viewing Environment too.
enum ImportAncillaryHDRMetadata: String, Hashable, Sendable, CaseIterable, Comparable {
    case ambientViewingEnvironment
    case masteringDisplayColorVolume
    case contentLightLevel

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum ImportPresentationOrientation: Hashable, Sendable { case portrait, landscape, square }

/// The track's preferred transform as plain values so the facts stay `Hashable` / `Sendable`
/// without leaning on CoreGraphics conformances. Built from and convertible to `CGAffineTransform`.
struct ImportAffineTransform: Hashable, Sendable {
    var a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double

    static let identity = ImportAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    init(_ t: CGAffineTransform) {
        self.init(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty)
    }

    var cgAffineTransform: CGAffineTransform { CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
    var determinant: Double { a * d - b * c }
}

struct ImportAudioFacts: Hashable, Sendable {
    var fourCC: String
    var sampleRate: Double
    var channelCount: Int
}

/// Immutable facts about one inspected Photos source. Geometry, orientation and mirroring are
/// derived here from `naturalSize` + `preferredTransform` (ADR-043 Revision 1) so every consumer
/// shares one deterministic rule.
struct ImportSourceFacts: Hashable, Sendable {
    // Media validity
    var duration: ImportSourceDuration
    var isReadable: Bool
    var isPlayable: Bool
    var isExportable: Bool
    var hasProtectedContent: Bool
    var hasVideoTrack: Bool
    var hasAudioTrack: Bool

    // Identity-independent format facts
    var container: ImportContainer
    var videoCodec: ImportVideoCodec

    // Geometry (raw, as inspected)
    var naturalWidth: Int
    var naturalHeight: Int
    var preferredTransform: ImportAffineTransform

    // Video characteristics
    var nominalFrameRate: Float
    var minimumFrameDuration: MediaTime?
    var bitsPerComponent: Int?
    var highBitDepthProfile: ImportKnownFlag
    var fullRangeVideo: ImportKnownFlag
    var colorPrimaries: ImportColorPrimaries
    var transferFunction: ImportTransferFunction
    var ycbcrMatrix: ImportYCbCrMatrix
    var hasDolbyVisionConfiguration: Bool
    var ancillaryHDRMetadata: Set<ImportAncillaryHDRMetadata>

    // Later-stage facts (storage estimate, immutability evidence); not used for eligibility
    var audio: ImportAudioFacts?
    var byteCount: Int64
    var modificationDate: Date?

    // MARK: Derived geometry

    /// Presentation size = the standardized bounding box of the natural-size rectangle after the
    /// preferred transform, rounded to whole pixels (rasters are integral; 90° rotations swap the
    /// edges exactly). Never `naturalSize` alone.
    var presentationSize: (width: Int, height: Int) {
        let rect = CGRect(x: 0, y: 0, width: CGFloat(naturalWidth), height: CGFloat(naturalHeight))
            .applying(preferredTransform.cgAffineTransform)
            .standardized
        return (Int(rect.width.rounded()), Int(rect.height.rounded()))
    }

    var presentationOrientation: ImportPresentationOrientation {
        let size = presentationSize
        if size.height > size.width { return .portrait }
        if size.height < size.width { return .landscape }
        return .square
    }

    /// Diagnostic only: a negative determinant means the transform flips one axis. Mirroring by
    /// itself never changes the orientation verdict.
    var isMirrored: Bool { preferredTransform.determinant < 0 }
}
