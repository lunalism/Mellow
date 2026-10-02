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

/// Pixel aspect ratio as the format description states it (`hSpacing:vSpacing`). Absent means
/// square pixels.
struct ImportPixelAspectRatio: Hashable, Sendable {
    let horizontalSpacing: Int
    let verticalSpacing: Int

    static let square = ImportPixelAspectRatio(horizontalSpacing: 1, verticalSpacing: 1)
}

/// The clean aperture in encoded-sample coordinates with a top-left origin, kept exactly as the
/// format description's rational offsets resolve (fractional origins are real: an odd aperture
/// centred in an even raster starts at 0.5).
struct ImportCleanAperture: Hashable, Sendable {
    let x: Double, y: Double, width: Double, height: Double
}

/// The encoded raster, its clean aperture and pixel aspect ratio (ADR-049 Decision 1). Only
/// `ImportApertureFacts.classify` builds one, so every value is finite, positive and inside the
/// raster.
struct ImportApertureGeometry: Hashable, Sendable {
    let encodedWidth: Int
    let encodedHeight: Int
    let cleanAperture: ImportCleanAperture
    let pixelAspectRatio: ImportPixelAspectRatio

    fileprivate init(encodedWidth: Int, encodedHeight: Int, cleanAperture: ImportCleanAperture, pixelAspectRatio: ImportPixelAspectRatio) {
        self.encodedWidth = encodedWidth
        self.encodedHeight = encodedHeight
        self.cleanAperture = cleanAperture
        self.pixelAspectRatio = pixelAspectRatio
    }
}

/// Whether the clean aperture covers the whole encoded raster (ADR-049 Decision 1). It decides the
/// normalization render path only; it is never a normalization reason and never forces one.
enum ImportApertureFacts: Hashable, Sendable {
    /// Origin and size equal the encoded raster (within `fullApertureTolerance`).
    case full(ImportApertureGeometry)
    /// Any reliable aperture that differs in origin or size: a centred fractional odd aperture, an
    /// integer offset, a smaller aperture, …
    case nonFull(ImportApertureGeometry)
    /// No format description, or geometry that is non-finite, non-positive, out of range, outside
    /// the raster or otherwise unusable. No path decision can rest on it.
    case unreliable

    /// Absorbs only the representation error of Core Media's rational → floating-point conversion,
    /// in encoded samples. Far below the half-sample offset of a centred odd aperture.
    static let fullApertureTolerance = 0.001
    /// Largest encoded edge accepted as geometry evidence. Keeps every later integer conversion and
    /// Core Video allocation in range; far above any supported source.
    static let maximumEncodedEdge = 16_384

    /// `cleanAperture` nil = no clean-aperture extension, which Core Media defines as the whole
    /// encoded raster; `pixelAspectRatio` nil = no pixel-aspect extension, i.e. square pixels.
    static func classify(encodedWidth: Int, encodedHeight: Int, cleanAperture: ImportCleanAperture?, pixelAspectRatio: ImportPixelAspectRatio?) -> ImportApertureFacts {
        guard (1...maximumEncodedEdge).contains(encodedWidth), (1...maximumEncodedEdge).contains(encodedHeight) else { return .unreliable }
        let ratio = pixelAspectRatio ?? .square
        guard ratio.horizontalSpacing > 0, ratio.verticalSpacing > 0 else { return .unreliable }
        let width = Double(encodedWidth), height = Double(encodedHeight)
        let aperture = cleanAperture ?? ImportCleanAperture(x: 0, y: 0, width: width, height: height)
        let values = [aperture.x, aperture.y, aperture.width, aperture.height]
        guard values.allSatisfy(\.isFinite), aperture.width > 0, aperture.height > 0 else { return .unreliable }
        let tolerance = fullApertureTolerance
        guard aperture.x >= -tolerance, aperture.y >= -tolerance,
              aperture.x + aperture.width <= width + tolerance, aperture.y + aperture.height <= height + tolerance
        else { return .unreliable }
        let geometry = ImportApertureGeometry(encodedWidth: encodedWidth, encodedHeight: encodedHeight, cleanAperture: aperture, pixelAspectRatio: ratio)
        let isFull = abs(aperture.x) <= tolerance && abs(aperture.y) <= tolerance
            && abs(aperture.width - width) <= tolerance && abs(aperture.height - height) <= tolerance
        return isFull ? .full(geometry) : .nonFull(geometry)
    }

    /// The geometry of a reliable classification.
    var geometry: ImportApertureGeometry? {
        switch self {
        case .full(let geometry), .nonFull(let geometry): return geometry
        case .unreliable: return nil
        }
    }
}

/// The description-local facts of one video format description: everything the codec gate,
/// the HDR / >8-bit normalization reasons (ADR-045 §2) and the path decision (ADR-049 and Revision
/// 1 Decision A) read. Every description of a track is judged by these, not only the first.
struct ImportVideoDescriptionFacts: Hashable, Sendable {
    var videoCodec: ImportVideoCodec
    var bitsPerComponent: Int?
    var highBitDepthProfile: ImportKnownFlag
    var aperture: ImportApertureFacts
    var colorPrimaries: ImportColorPrimaries
    var transferFunction: ImportTransferFunction
    var ycbcrMatrix: ImportYCbCrMatrix
    var hasDolbyVisionConfiguration: Bool

    /// ADR-049: affirmative Rec.709 primaries, transfer and matrix and no Dolby Vision
    /// configuration (which also rules out HLG, PQ and Rec.2020). Unknown colour facts prove
    /// nothing. Bit depth is deliberately not consulted — reducing it is not tone mapping — and
    /// ancillary metadata (AVE / MDCV / CLLI) is not an HDR signal (ADR-045 §2).
    var isProvenSDRRec709: Bool {
        colorPrimaries == .rec709 && transferFunction == .rec709 && ycbcrMatrix == .rec709 && !hasDolbyVisionConfiguration
    }
}

/// ADR-049 Revision 1 Decision B: which preferred transforms a normalization may bake. One pure
/// rule shared by preflight, plan construction and the runtime check, so the runtime never refuses
/// what preflight accepted.
enum ImportNormalizationTransform {
    /// Relative tolerance for an off-axis component: |off-axis| ≤ tolerance × |on-axis| in each
    /// basis column, i.e. a deviation angle below ≈ 0.0057°. Track matrices are 16.16 fixed point
    /// (one step ≈ 1.5e-5 of a unit component), so their representation noise is inside it; a 1°
    /// rotation (tan ≈ 0.0175) or any visible shear is far outside. Relative, so a small or large
    /// valid scale never changes the angular verdict.
    static let relativeTolerance = 1e-4
    /// Each basis column's length must lie in this range: a near-zero basis is degenerate, an
    /// enormous one is not a representable presentation.
    static let scaleRange: ClosedRange<Double> = 1e-6...1e6

    /// Translation, a quarter-turn axis mapping, optional mirroring and finite non-zero axis-aligned
    /// scale (uniform or not) — and nothing else: no shear, no arbitrary-angle rotation, no
    /// non-finite or non-invertible matrix.
    static func isEligible(_ t: ImportAffineTransform) -> Bool {
        let values = [t.a, t.b, t.c, t.d, t.tx, t.ty]
        guard values.allSatisfy(\.isFinite) else { return false }
        let determinant = t.a * t.d - t.b * t.c
        guard determinant.isFinite, determinant != 0 else { return false }
        // Basis columns: x maps to (a, b), y maps to (c, d).
        let xLength = (t.a * t.a + t.b * t.b).squareRoot(), yLength = (t.c * t.c + t.d * t.d).squareRoot()
        guard scaleRange.contains(xLength), scaleRange.contains(yLength) else { return false }
        let tolerance = relativeTolerance
        let keepsAxes = abs(t.b) <= tolerance * abs(t.a) && abs(t.c) <= tolerance * abs(t.d)
        let swapsAxes = abs(t.a) <= tolerance * abs(t.b) && abs(t.d) <= tolerance * abs(t.c)
        return keepsAxes || swapsAxes
    }
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
    /// Clean aperture of the first video format description (ADR-049).
    var aperture: ImportApertureFacts
    /// Every further video format description of the selected track, in order (ADR-049 Revision 1).
    /// The first description is the one the fields above describe; most tracks have no others.
    var additionalVideoDescriptions: [ImportVideoDescriptionFacts] = []

    // Later-stage facts (storage estimate, immutability evidence); not used for eligibility
    var audio: ImportAudioFacts?
    var byteCount: Int64
    var modificationDate: Date?

    // MARK: Derived

    /// All video format descriptions of the selected track: the first (the top-level facts), then
    /// the rest. The codec gate, the HDR / >8-bit reasons and the path decision each consider every
    /// one of them (ADR-046, ADR-045 §2, ADR-049 Revision 1 Decision A).
    var videoDescriptions: [ImportVideoDescriptionFacts] {
        [ImportVideoDescriptionFacts(videoCodec: videoCodec, bitsPerComponent: bitsPerComponent, highBitDepthProfile: highBitDepthProfile,
                                     aperture: aperture, colorPrimaries: colorPrimaries, transferFunction: transferFunction,
                                     ycbcrMatrix: ycbcrMatrix, hasDolbyVisionConfiguration: hasDolbyVisionConfiguration)]
            + additionalVideoDescriptions
    }

    // MARK: Derived geometry

    /// Presentation size = the standardized bounding box of the natural-size rectangle after the
    /// preferred transform, rounded to whole pixels (rasters are integral; 90° rotations swap the
    /// edges exactly). Never `naturalSize` alone. A non-finite or out-of-range result (a malformed
    /// transform) is (0, 0) — a degenerate raster preflight rejects — never an integer-conversion trap.
    var presentationSize: (width: Int, height: Int) {
        let rect = CGRect(x: 0, y: 0, width: CGFloat(naturalWidth), height: CGFloat(naturalHeight))
            .applying(preferredTransform.cgAffineTransform)
            .standardized
        let limit = Double(Int32.max)
        guard rect.width.isFinite, rect.height.isFinite, rect.width <= limit, rect.height <= limit else { return (0, 0) }
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
