import Foundation

// Phase 6 Step 4A — the deterministic normalization plan for one accepted, normalization-required
// item (ADR-045 §2 / §3 / §7, ADR-047 Decision 1, ADR-048, ADR-049). Pure: it consumes the Step 3 accepted
// item and never opens, copies, decodes, encodes or publishes media. The AVFoundation normalizer
// (Step 4B) configures itself from a plan; it does not re-derive any of these facts. Product
// eligibility (raster feasibility, audio reliability) is decided by preflight, never here.

enum WorkingMediaAudioStrategy: Hashable, Sendable {
    /// The source has no audio track; the output has none either and no silence is synthesized.
    case none
    /// The source `aac ` track is carried without re-encoding (ADR-045 §3, ADR-048).
    case passthroughAAC
    /// Any other reliably inspected format is transcoded with these settings (ADR-048).
    case transcode(WorkingMediaAudioTranscodeSettings)
}

/// Why no plan exists. These guard construction invariants only: in the normal pipeline preflight
/// has already rejected every ineligible source, so none of them is a product-level rejection.
/// No case carries user copy.
enum WorkingMediaPlanError: Error, Hashable, Sendable {
    /// The item is a fast-path copy; normalization never applies to it (ADR-045 §6).
    case fastPathItem
    case emptyNormalizationReasons
    /// The facts do not pass preflight (forged input; Step 3 never accepts such an item).
    case rejectedByPreflight(ImportPreflightRejection)
    /// The path's reasons, render path or duration disagree with the preflight verdict for the same
    /// facts, or a derived value contradicts that verdict.
    case preflightMismatch
}

/// Immutable facts the normalizer needs. Only `WorkingMediaPlanBuilder` constructs one, so every
/// plan carries the canonical contract and validated, mutually consistent facts.
struct WorkingMediaNormalizationPlan: Hashable, Sendable {
    let contract: SDRWorkingMediaContract
    /// Canonical order exactly as Step 3 reported it (HDR → frame rate → raster → audio transcode).
    /// An `.audioTranscode`-only plan still produces the full canonical video output.
    let reasons: [ImportNormalizationReason]
    /// ADR-049: the built-in tone-mapping compositor (full aperture) or geometry-only SDR rendering
    /// (non-full aperture). It never changes raster, cadence, audio, duration or validation.
    let renderPath: WorkingMediaRenderPath
    /// The source's encoded raster, clean aperture and pixel aspect ratio, as preflight judged them.
    let aperture: ImportApertureGeometry
    let sourceDuration: MediaTime
    let acceptedOutputDuration: ClosedRange<MediaTime>
    /// The transform the presentation raster was derived from; it is baked into pixels and the
    /// output carries `contract.outputTransform` (identity).
    let sourcePresentationTransform: ImportAffineTransform
    /// The same `WorkingMediaRasterPolicy` result preflight judged feasible.
    let raster: WorkingMediaRasterPlan
    /// Resolved per ADR-048 Decision 3; never shorter than 1/30 s.
    let outputFrameDuration: MediaTime
    let audio: WorkingMediaAudioStrategy

    fileprivate init(
        reasons: [ImportNormalizationReason], renderPath: WorkingMediaRenderPath, aperture: ImportApertureGeometry,
        sourceDuration: MediaTime, sourcePresentationTransform: ImportAffineTransform,
        raster: WorkingMediaRasterPlan, outputFrameDuration: MediaTime, audio: WorkingMediaAudioStrategy
    ) {
        contract = .canonical
        self.reasons = reasons
        self.renderPath = renderPath
        self.aperture = aperture
        self.sourceDuration = sourceDuration
        acceptedOutputDuration = contract.acceptedOutputDuration(forSource: sourceDuration)
        self.sourcePresentationTransform = sourcePresentationTransform
        self.raster = raster
        self.outputFrameDuration = outputFrameDuration
        self.audio = audio
    }
}

enum WorkingMediaPlanBuilder {
    /// The production entry point: a Step 3 accepted item, whose path is authoritative.
    static func plan(for item: ImportAcceptedItem) throws -> WorkingMediaNormalizationPlan {
        try plan(preparationPath: item.preparationPath, facts: item.facts, sourceDuration: item.sourceDuration)
    }

    /// The same validation over the item's parts. Every input is re-checked against the preflight
    /// verdict for `facts`, so no combination a caller can assemble yields a plan that Step 3 would
    /// not have produced.
    static func plan(preparationPath: ImportPreparationPath, facts: ImportSourceFacts, sourceDuration: MediaTime) throws -> WorkingMediaNormalizationPlan {
        guard let (reasons, renderPath) = preparationPath.normalization else { throw WorkingMediaPlanError.fastPathItem }
        guard !reasons.isEmpty else { throw WorkingMediaPlanError.emptyNormalizationReasons }

        switch ImportPreflightClassifier.classify(facts) {
        case .rejected(let rejection):
            throw WorkingMediaPlanError.rejectedByPreflight(rejection)
        case .readyFastPath:
            throw WorkingMediaPlanError.preflightMismatch
        case .normalizationRequired(let verdictReasons, let verdictPath, let verdictDuration):
            guard verdictReasons == reasons, verdictPath == renderPath, verdictDuration == sourceDuration else {
                throw WorkingMediaPlanError.preflightMismatch
            }
        }
        // Step 8 chose a path, so the aperture is reliable; the guard only keeps construction total.
        guard let aperture = facts.aperture.geometry else { throw WorkingMediaPlanError.preflightMismatch }

        // Preflight passed, so the shared raster plan exists and is feasible; the guard only keeps
        // construction total.
        let size = facts.presentationSize
        guard let raster = WorkingMediaRasterPolicy.plan(forPresentation: WorkingMediaRaster(width: size.width, height: size.height)),
              raster.isFeasible
        else { throw WorkingMediaPlanError.preflightMismatch }

        let contract = SDRWorkingMediaContract.canonical
        let audio: WorkingMediaAudioStrategy
        switch ImportPreflightClassifier.assessAudio(facts) {
        case .noAudio:
            audio = .none
        case .passthroughAAC:
            audio = .passthroughAAC
        case .transcode(let channelCount):
            guard let settings = contract.audioTranscodeSettings(sourceChannelCount: channelCount) else { throw WorkingMediaPlanError.preflightMismatch }
            audio = .transcode(settings)
        case .unreliable:
            throw WorkingMediaPlanError.preflightMismatch
        }

        return WorkingMediaNormalizationPlan(
            reasons: reasons, renderPath: renderPath, aperture: aperture,
            sourceDuration: sourceDuration, sourcePresentationTransform: facts.preferredTransform,
            raster: raster,
            outputFrameDuration: contract.outputFrameDuration(sourceMinimumFrameDuration: facts.minimumFrameDuration, nominalFrameRate: facts.nominalFrameRate),
            audio: audio
        )
    }
}
