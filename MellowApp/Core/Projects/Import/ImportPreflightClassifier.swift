import Foundation

// Phase 6 Photos-import preflight decision core (ADR-042 R1–R4, ADR-043 R1, ADR-044 R1, ADR-045,
// ADR-046 §8, ADR-048, ADR-049). Pure and deterministic: no I/O, no AVFoundation, no file URL.
// Verdict precedence is exactly duration → readable / video / protected → container → codec family
// → orientation → working-raster feasibility → audio facts → normalization reasons → aperture /
// tone-map path; an earlier rejection always wins and none of the gates is a normalization reason.

/// One canonical reason a source is excluded before any media operation. User-facing copy is
/// mapped elsewhere (ADR-042 R2–R4, ADR-043 R1, ADR-044 R1); this layer carries no strings.
enum ImportPreflightRejection: Error, Hashable, Sendable {
    case durationBelowMinimum
    case durationAboveMaximum
    case invalidDuration
    case unreadable
    case noVideoTrack
    case protectedContent
    case unsupportedContainer(ImportContainer)
    case unsupportedCodec(ImportVideoCodec)
    case nonPortraitPresentation(ImportPresentationOrientation)
    /// ADR-048: portrait by ADR-043, but the ADR-047 even-aligned output raster would not be
    /// strictly portrait (e.g. 1080×1081 → 1080×1080). Not a non-portrait source.
    case unsupportedWorkingRaster(presentationWidth: Int, presentationHeight: Int)
    /// ADR-048: an audio track whose facts cannot be relied on.
    case unsupportedAudioFacts(ImportAudioFactsProblem)
    /// ADR-049 Case D: normalization is required, but no approved render path preserves this
    /// source — a non-full clean aperture whose colour is not proven SDR Rec.709, or aperture
    /// evidence too unreliable to choose a path. A V1 technical boundary, not a statement that the
    /// media is invalid; it reuses the invalid / unsupported family.
    case unsupportedApertureNormalization(ImportApertureNormalizationProblem)
    /// ADR-049 Revision 1 Decision B: normalization is required, but the preferred transform is not
    /// a bakeable axis-aligned mapping (shear, arbitrary-angle rotation, non-finite or
    /// non-invertible). A V1 technical boundary; it reuses the invalid / unsupported family.
    case unsupportedNormalizationTransform
}

/// Why ADR-049 step 8 found no approved render path. Diagnostic only; no user copy.
enum ImportApertureNormalizationProblem: Error, Hashable, Sendable, CaseIterable {
    /// The aperture facts needed to choose a path are missing or unusable, in any description.
    case unreliableAperture
    /// The video format descriptions disagree on aperture class, encoded raster, clean aperture or
    /// pixel aspect, so no single plan describes every frame (ADR-049 Revision 1 Decision A).
    case descriptionsDisagree
    /// A non-full aperture where any description has HDR, wide-colour, unknown or otherwise unproven
    /// SDR colour: only the built-in compositor may tone-map, and it cannot render a non-full
    /// aperture whole.
    case colorNotProvenSDRRec709
}

/// What every video format description of a track agrees on (ADR-049 Revision 1 Decision A). The
/// one pure rule used by preflight, plan construction and the normalizer's runtime re-check.
struct ImportDescriptionConsensus: Hashable, Sendable {
    /// `.full` or `.nonFull`, carrying the first description's geometry; every other description is
    /// compatible with it.
    let aperture: ImportApertureFacts
    /// True only when each description independently proves SDR Rec.709.
    let everyDescriptionProvenSDRRec709: Bool

    /// Every description must have reliable aperture facts, the same full / non-full class, the
    /// same encoded raster and pixel aspect, and the same clean aperture within the accepted
    /// 0.001-sample comparison. A single description is the one-element case; none is unreliable.
    static func evaluate(_ descriptions: [ImportVideoDescriptionFacts]) -> Result<ImportDescriptionConsensus, ImportApertureNormalizationProblem> {
        guard let first = descriptions.first, let reference = first.aperture.geometry else { return .failure(.unreliableAperture) }
        for description in descriptions {
            guard let geometry = description.aperture.geometry else { return .failure(.unreliableAperture) }
            guard sameClass(description.aperture, first.aperture), compatible(geometry, reference) else { return .failure(.descriptionsDisagree) }
        }
        return .success(ImportDescriptionConsensus(aperture: first.aperture, everyDescriptionProvenSDRRec709: descriptions.allSatisfy(\.isProvenSDRRec709)))
    }

    private static func sameClass(_ lhs: ImportApertureFacts, _ rhs: ImportApertureFacts) -> Bool {
        switch (lhs, rhs) {
        case (.full, .full), (.nonFull, .nonFull): return true
        case (.full, _), (.nonFull, _), (.unreliable, _): return false
        }
    }

    /// One plan describes both: identical encoded raster and pixel aspect, clean aperture within
    /// `ImportApertureFacts.fullApertureTolerance` in every component.
    static func compatible(_ lhs: ImportApertureGeometry, _ rhs: ImportApertureGeometry) -> Bool {
        let tolerance = ImportApertureFacts.fullApertureTolerance
        let a = lhs.cleanAperture, b = rhs.cleanAperture
        return lhs.encodedWidth == rhs.encodedWidth && lhs.encodedHeight == rhs.encodedHeight
            && lhs.pixelAspectRatio == rhs.pixelAspectRatio
            && abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

/// How a normalization-required source is rendered (ADR-049 Decision 2). Both paths produce the
/// same canonical working-media output and pass the same validation.
enum WorkingMediaRenderPath: Hashable, Sendable {
    /// Case B — full clean aperture: AVFoundation's built-in compositor with a layer instruction
    /// (ADR-045 §4), the only approved HDR / wide-colour tone-mapping mechanism.
    case builtInToneMap
    /// Case C — non-full clean aperture, colour proven SDR Rec.709: geometry-only rendering of the
    /// whole aperture. No tone mapping happens on this path.
    case sdrApertureGeometry
}

/// Why audio facts are unreliable (ADR-048 Decision 1). Diagnostic only; no user copy.
enum ImportAudioFactsProblem: Hashable, Sendable, CaseIterable {
    /// No audio track reported, yet audio format facts exist.
    case contradictoryTrackFacts
    /// An audio track exists but no format description could be read.
    case missingFormatFacts
    /// The subtype is absent or unavailable: all-zero, or not a faithful four-byte subtype.
    case malformedFormatID
    case invalidSampleRate
    case invalidChannelCount
}

/// The ADR-048 audio verdict for one source. `.unreliable` is a preflight rejection; the other
/// cases are eligible and tell the plan whether audio passes through or is transcoded.
enum ImportAudioAssessment: Hashable, Sendable {
    case noAudio
    /// Format ID exactly `aac ` (`kAudioFormatMPEG4AAC`).
    case passthroughAAC
    /// Any other reliably inspected format ID, including other AAC-family IDs (`aach`, `aacp`, …).
    case transcode(sourceChannelCount: Int)
    case unreliable(ImportAudioFactsProblem)
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
/// HDR / color → frame rate → raster → audio transcode (ADR-048).
enum ImportNormalizationReason: Hashable, Sendable {
    case hdr(signals: [ImportHDRSignal])
    case frameRate(nominal: Float)
    case raster(presentationWidth: Int, presentationHeight: Int)
    /// Reliably identified audio whose format ID is not `aac `. May be the only reason; the output
    /// still satisfies the full working-media video contract (no audio-only remux path).
    case audioTranscode
}

enum ImportPreflightVerdict: Hashable, Sendable {
    /// Phase-5-ready: copied into project-owned media without re-encoding.
    case readyFastPath(sourceDuration: MediaTime)
    /// Eligible, but must pass through the working-media normalizer for the listed reasons, on the
    /// render path ADR-049 step 8 chose.
    case normalizationRequired(reasons: [ImportNormalizationReason], renderPath: WorkingMediaRenderPath, sourceDuration: MediaTime)
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
    /// ADR-048: the only audio format ID that passes through; exact, case-sensitive.
    static let passthroughAudioFormatID = "aac "
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
        //    Every video format description must be a supported family; the first unsupported one in
        //    source order is reported. A track with no description reports `.unknown` (the first
        //    description's facts default to it).
        if let unsupported = facts.videoDescriptions.first(where: { !$0.videoCodec.isSupportedFamily }) {
            return .rejected(.unsupportedCodec(unsupported.videoCodec))
        }

        // 5. Presentation orientation (ADR-043 R1): strict height > width after the transform.
        let orientation = facts.presentationOrientation
        guard orientation == .portrait else { return .rejected(.nonPortraitPresentation(orientation)) }

        // 6. Working-raster feasibility (ADR-048 Decision 2): the shared ADR-047 calculation must
        //    yield a strictly portrait even-aligned output. Never repaired, never non-portrait.
        let size = facts.presentationSize
        guard let raster = WorkingMediaRasterPolicy.plan(forPresentation: WorkingMediaRaster(width: size.width, height: size.height)), raster.isFeasible else {
            return .rejected(.unsupportedWorkingRaster(presentationWidth: size.width, presentationHeight: size.height))
        }

        // 7. Audio facts (ADR-048 Decision 1).
        let audio = assessAudio(facts)
        if case .unreliable(let problem) = audio { return .rejected(.unsupportedAudioFacts(problem)) }

        // 8. Normalization reasons (ADR-045 §2, ADR-048), canonical order.
        var reasons: [ImportNormalizationReason] = []
        let signals = hdrSignals(in: facts)
        if !signals.isEmpty { reasons.append(.hdr(signals: signals)) }
        if facts.nominalFrameRate > ImportPreflightPolicy.maximumNominalFrameRate {
            reasons.append(.frameRate(nominal: facts.nominalFrameRate))
        }
        if exceeds1080pClass(width: size.width, height: size.height) {
            reasons.append(.raster(presentationWidth: size.width, presentationHeight: size.height))
        }
        if case .transcode = audio { reasons.append(.audioTranscode) }

        // 9. Aperture / tone-map path (ADR-049 step 8). No reason → fast path whatever the aperture
        //    (the aperture is never a reason). With reasons, the path follows from the aperture and
        //    proven colour; a combination no approved path preserves is rejected, and no reason can
        //    override that rejection.
        //    ADR-049 Revision 1: with reasons, every video format description must agree and the
        //    transform must be bakeable before a path is chosen. Without reasons neither is
        //    consulted — the source is copied, not rendered.
        guard !reasons.isEmpty else { return .readyFastPath(sourceDuration: sourceDuration) }
        switch renderPath(facts) {
        case .success(let path):
            return .normalizationRequired(reasons: reasons, renderPath: path, sourceDuration: sourceDuration)
        case .failure(let rejection):
            return .rejected(rejection)
        }
    }

    /// ADR-049 (incl. Revision 1) for a source that needs normalization: description consensus, then
    /// transform eligibility, then the path from the agreed aperture and colour.
    static func renderPath(_ facts: ImportSourceFacts) -> Result<WorkingMediaRenderPath, ImportPreflightRejection> {
        let consensus: ImportDescriptionConsensus
        switch ImportDescriptionConsensus.evaluate(facts.videoDescriptions) {
        case .success(let agreed): consensus = agreed
        case .failure(let problem): return .failure(.unsupportedApertureNormalization(problem))
        }
        guard ImportNormalizationTransform.isEligible(facts.preferredTransform) else { return .failure(.unsupportedNormalizationTransform) }
        switch consensus.aperture {
        case .full:
            return .success(.builtInToneMap)
        case .nonFull:
            return consensus.everyDescriptionProvenSDRRec709
                ? .success(.sdrApertureGeometry)
                : .failure(.unsupportedApertureNormalization(.colorNotProvenSDRRec709))
        case .unreliable:
            return .failure(.unsupportedApertureNormalization(.unreliableAperture))
        }
    }

    /// Deduplicated, canonically ordered HDR signals, unioned over every video format description
    /// of the track (a later description can introduce the only signal), so the result does not
    /// depend on description order. `ancillaryHDRMetadata` and `minimumFrameDuration` are
    /// intentionally not consulted; unknown bit depth / profile and full range signal nothing.
    static func hdrSignals(in facts: ImportSourceFacts) -> [ImportHDRSignal] {
        var set = Set<ImportHDRSignal>()
        for description in facts.videoDescriptions {
            if description.transferFunction == .hlg { set.insert(.hlgTransfer) }
            if description.transferFunction == .pq { set.insert(.pqTransfer) }
            if description.colorPrimaries == .rec2020 { set.insert(.rec2020Primaries) }
            if description.ycbcrMatrix == .rec2020 { set.insert(.rec2020Matrix) }
            if let bpc = description.bitsPerComponent, bpc > 8 { set.insert(.bitDepthAbove8) }
            if description.highBitDepthProfile == .yes { set.insert(.highBitDepthProfile) }
            if description.hasDolbyVisionConfiguration { set.insert(.dolbyVision) }
        }
        return set.sorted()
    }

    /// 1080p-class bounding box on the transformed presentation raster: long edge ≤ 1920 and
    /// short edge ≤ 1080. This only decides *whether* normalization is needed; output dimensions
    /// come from `WorkingMediaRasterPolicy` (ADR-047: never upscaled).
    static func exceeds1080pClass(width: Int, height: Int) -> Bool {
        let long = max(width, height), short = min(width, height)
        return long > ImportPreflightPolicy.maximumLongEdge || short > ImportPreflightPolicy.maximumShortEdge
    }

    /// ADR-048 Decision 1. Checks run in a fixed order and nothing is repaired: contradictory track
    /// facts, missing format facts, absent (all-zero) subtype, sample rate, channel count. The subtype
    /// comparison is on the raw four bytes, so it is exact and case-sensitive; only `aac ` passes
    /// through and every other nonzero subtype, printable or not, is transcoded.
    static func assessAudio(_ facts: ImportSourceFacts) -> ImportAudioAssessment {
        guard facts.hasAudioTrack else {
            return facts.audio == nil ? .noAudio : .unreliable(.contradictoryTrackFacts)
        }
        guard let audio = facts.audio else { return .unreliable(.missingFormatFacts) }
        guard let subtype = rawFormatID(audio.fourCC), subtype != 0 else { return .unreliable(.malformedFormatID) }
        guard audio.sampleRate.isFinite, audio.sampleRate > 0 else { return .unreliable(.invalidSampleRate) }
        guard audio.channelCount > 0 else { return .unreliable(.invalidChannelCount) }
        return subtype == rawFormatID(ImportPreflightPolicy.passthroughAudioFormatID)
            ? .passthroughAAC
            : .transcode(sourceChannelCount: audio.channelCount)
    }

    /// The raw four-byte subtype behind a format ID string. The inspector renders each subtype byte
    /// as one ISO Latin-1 scalar (U+0000–U+00FF), which is lossless, so any nonzero value is a
    /// reliably identified format whether or not it is printable (ADR-048). `nil` when the string is
    /// not exactly four such scalars; the caller treats `nil` and `0` as absent.
    static func rawFormatID(_ fourCC: String) -> UInt32? {
        let scalars = Array(fourCC.unicodeScalars)
        guard scalars.count == 4, scalars.allSatisfy({ $0.value <= 0xFF }) else { return nil }
        return scalars.reduce(0) { ($0 << 8) | $1.value }
    }
}
