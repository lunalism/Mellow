import Foundation

// Phase 6 Photos-import preflight decision core (ADR-042 R1–R4, ADR-043 R1, ADR-044 R1, ADR-045,
// ADR-046 §8). Pure and deterministic: no I/O, no AVFoundation, no file URL. Verdict precedence is
// exactly duration → readable / video / protected → container → codec family → orientation →
// normalization reasons; an earlier rejection always wins and none of gates 1–5 is a
// normalization reason.

/// One canonical reason a source is excluded before any media operation. User-facing copy is
/// mapped elsewhere (ADR-042 R2–R4, ADR-043 R1, ADR-044 R1); this layer carries no strings.
enum ImportPreflightRejection: Hashable, Sendable {
    case durationBelowMinimum
    case durationAboveMaximum
    case invalidDuration
    case unreadable
    case noVideoTrack
    case protectedContent
    case unsupportedContainer(ImportContainer)
    case unsupportedCodec(ImportVideoCodec)
    case nonPortraitPresentation(ImportPresentationOrientation)
}

/// Normalization-triggering HDR / high-bit-depth signals (ADR-045 §2). Ancillary metadata
/// (AVE / MDCV / CLLI) is deliberately absent — it never triggers.
enum ImportHDRSignal: String, Hashable, Sendable, CaseIterable, Comparable {
    case hlgTransfer
    case pqTransfer
    case rec2020Primaries
    case rec2020Matrix
    case bitDepthAbove8
    case highBitDepthProfile
    case dolbyVision

    /// Canonical order = declaration order, so a reason built from any input ordering is identical.
    static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Why an eligible source must be normalized. Reasons are reported in canonical order:
/// HDR / color → frame rate → raster.
enum ImportNormalizationReason: Hashable, Sendable {
    case hdr(signals: [ImportHDRSignal])
    case frameRate(nominal: Float)
    case raster(presentationWidth: Int, presentationHeight: Int)
}

enum ImportPreflightVerdict: Hashable, Sendable {
    /// Phase-5-ready: copied into project-owned media without re-encoding.
    case readyFastPath(sourceDuration: MediaTime)
    /// Eligible, but must pass through the working-media normalizer for the listed reasons.
    case normalizationRequired(reasons: [ImportNormalizationReason], sourceDuration: MediaTime)
    /// Excluded before any media operation.
    case rejected(ImportPreflightRejection)
}

/// Approved constants. Duration bounds are product boundaries (ADR-042: exact, inclusive, no
/// frame tolerance). The frame-rate threshold is the ADR-045 technical boundary that tolerates
/// nominal-rate metadata noise around 30 fps (29.97 / 29.987 / 30.0 stay ready; 59.94 / 60 normalize).
enum ImportPreflightPolicy {
    static let minimumDuration = MediaTime.seconds(1)
    static let maximumDuration = MediaTime.seconds(5)
    static let maximumNominalFrameRate: Float = 30.5
    static let maximumLongEdge = 1920
    static let maximumShortEdge = 1080
}

enum ImportPreflightClassifier {
    static func classify(_ facts: ImportSourceFacts) -> ImportPreflightVerdict {
        // 1. Duration (ADR-042): exact rational comparison against the inclusive 1.0–5.0 s bounds.
        let sourceDuration: MediaTime
        switch facts.duration {
        case .invalid:
            return .rejected(.invalidDuration)
        case .exact(let duration):
            guard duration.value > 0 else { return .rejected(.invalidDuration) }
            if duration < ImportPreflightPolicy.minimumDuration { return .rejected(.durationBelowMinimum) }
            if ImportPreflightPolicy.maximumDuration < duration { return .rejected(.durationAboveMaximum) }
            sourceDuration = duration
        }

        // 2. Basic media validity.
        guard facts.isReadable else { return .rejected(.unreadable) }
        guard facts.hasVideoTrack else { return .rejected(.noVideoTrack) }
        guard !facts.hasProtectedContent else { return .rejected(.protectedContent) }

        // 3. Actual container (ADR-044): only QuickTime; no remux route exists.
        guard facts.container == .quickTime else { return .rejected(.unsupportedContainer(facts.container)) }

        // 4. Codec family (ADR-046): only H.264 / HEVC; never a normalization reason.
        guard facts.videoCodec.isSupportedFamily else { return .rejected(.unsupportedCodec(facts.videoCodec)) }

        // 5. Presentation orientation (ADR-043 R1): strict height > width after the transform.
        let orientation = facts.presentationOrientation
        guard orientation == .portrait else { return .rejected(.nonPortraitPresentation(orientation)) }

        // 6. Normalization reasons (ADR-045 §2), canonical order.
        var reasons: [ImportNormalizationReason] = []
        let signals = hdrSignals(in: facts)
        if !signals.isEmpty { reasons.append(.hdr(signals: signals)) }
        if facts.nominalFrameRate > ImportPreflightPolicy.maximumNominalFrameRate {
            reasons.append(.frameRate(nominal: facts.nominalFrameRate))
        }
        let size = facts.presentationSize
        if exceeds1080pClass(width: size.width, height: size.height) {
            reasons.append(.raster(presentationWidth: size.width, presentationHeight: size.height))
        }
        return reasons.isEmpty
            ? .readyFastPath(sourceDuration: sourceDuration)
            : .normalizationRequired(reasons: reasons, sourceDuration: sourceDuration)
    }

    /// Deduplicated, canonically ordered HDR signals. `ancillaryHDRMetadata` and
    /// `minimumFrameDuration` are intentionally not consulted.
    static func hdrSignals(in facts: ImportSourceFacts) -> [ImportHDRSignal] {
        var set = Set<ImportHDRSignal>()
        if facts.transferFunction == .hlg { set.insert(.hlgTransfer) }
        if facts.transferFunction == .pq { set.insert(.pqTransfer) }
        if facts.colorPrimaries == .rec2020 { set.insert(.rec2020Primaries) }
        if facts.ycbcrMatrix == .rec2020 { set.insert(.rec2020Matrix) }
        if let bpc = facts.bitsPerComponent, bpc > 8 { set.insert(.bitDepthAbove8) }
        if facts.highBitDepthProfile == .yes { set.insert(.highBitDepthProfile) }
        if facts.hasDolbyVisionConfiguration { set.insert(.dolbyVision) }
        return set.sorted()
    }

    /// 1080p-class bounding box on the transformed presentation raster: long edge ≤ 1920 and
    /// short edge ≤ 1080. This only decides *whether* normalization is needed; output dimensions,
    /// scaling and the pending upscaling policy belong to the normalizer.
    static func exceeds1080pClass(width: Int, height: Int) -> Bool {
        let long = max(width, height), short = min(width, height)
        return long > ImportPreflightPolicy.maximumLongEdge || short > ImportPreflightPolicy.maximumShortEdge
    }
}
