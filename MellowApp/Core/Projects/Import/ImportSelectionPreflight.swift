import Foundation

// Phase 6 Step 3 — the selection preflight boundary (ADR-042 R3 / R4 §7, ADR-043 R1, ADR-044 R1,
// ADR-046 §6, ARCHITECTURE §38 steps 1–2). One shared component turns an ordered list of
// app-controlled candidates into the Accepted Set (fast-path + normalization-required) and the
// per-item exclusions, and names the ONE notice category the completed operation may show. It
// inspects and classifies only: no copy, move, delete, materialize, normalize, storage estimate,
// project mutation or user copy lives here. It is not yet called by any production flow.

// MARK: - Candidate

/// Opaque identity of one candidate inside one selection operation. Distinct from any Photos
/// asset, clip or project identity — those do not exist at this boundary.
struct ImportCandidateID: Hashable, Sendable {
    let rawValue: UUID
    init() { rawValue = UUID() }
    init(rawValue: UUID) { self.rawValue = rawValue }
}

/// One already-transferred, app-controlled local file offered to preflight. The caller owns the
/// file for the operation's lifetime; preflight never copies, moves, deletes or writes it, and
/// nothing about the URL (name, extension) influences eligibility. `SelectedVideoSource` is not
/// reused here: it identifies a source by URL alone and carries the Phase 5 reserve-guard byte
/// count, while this boundary needs a stable per-occurrence identity and reads bytes as facts.
struct ImportCandidate: Hashable, Sendable {
    let id: ImportCandidateID
    let url: URL

    init(id: ImportCandidateID = ImportCandidateID(), url: URL) {
        self.id = id
        self.url = url
    }
}

/// Which approved notice semantics the completed operation uses. Approved copy differs only
/// between a multi-item session (aggregated, per-item exclusion — Select Clips / Editor Add) and a
/// single-candidate operation (individual rejection — a single chosen item or Replace); the caller
/// declares which one its session is.
enum ImportSelectionContext: Hashable, Sendable {
    case multipleItems
    case singleCandidate
}

// MARK: - Results

/// What the future preparation operation does with an accepted item (ADR-045 §2). Both paths are
/// members of the Accepted Set; neither is an exclusion.
enum ImportPreparationPath: Hashable, Sendable {
    case fastPathCopy
    case normalizationRequired(reasons: [ImportNormalizationReason])
}

/// An accepted candidate with everything preparation needs without re-inspecting.
struct ImportAcceptedItem: Hashable, Sendable {
    let candidate: ImportCandidate
    let facts: ImportSourceFacts
    let verdict: ImportPreflightVerdict
    let sourceDuration: MediaTime
    let preparationPath: ImportPreparationPath

    /// Only the preflight in this file builds accepted items, and only from a non-rejected verdict:
    /// the stored verdict is re-derived from the path + duration so the two can never disagree, and
    /// no constructor exists through which a rejection could become an accepted item.
    fileprivate init(candidate: ImportCandidate, facts: ImportSourceFacts, sourceDuration: MediaTime, preparationPath: ImportPreparationPath) {
        self.candidate = candidate
        self.facts = facts
        self.sourceDuration = sourceDuration
        self.preparationPath = preparationPath
        switch preparationPath {
        case .fastPathCopy:
            verdict = .readyFastPath(sourceDuration: sourceDuration)
        case .normalizationRequired(let reasons):
            verdict = .normalizationRequired(reasons: reasons, sourceDuration: sourceDuration)
        }
    }
}

/// The approved semantic families of a per-item exclusion. Every classifier rejection maps to
/// exactly one; the exact rejection is kept alongside so nothing is lost.
enum ImportExclusionCategory: Hashable, Sendable, CaseIterable {
    case durationBelowMinimum
    case durationAboveMaximum
    /// Malformed / unreadable / unsupported media (ADR-042 R4 §5): invalid duration, unreadable,
    /// no video track, protected content, unsupported container (ADR-044), unsupported codec
    /// (ADR-046). Deliberately one family — there is no container- or codec-specific category.
    case invalidOrUnsupportedMedia
    /// Landscape and square are one non-portrait presentation (ADR-043 R1).
    case nonPortraitPresentation

    init(_ rejection: ImportPreflightRejection) {
        switch rejection {
        case .durationBelowMinimum: self = .durationBelowMinimum
        case .durationAboveMaximum: self = .durationAboveMaximum
        case .invalidDuration, .unreadable, .noVideoTrack, .protectedContent, .unsupportedContainer, .unsupportedCodec:
            self = .invalidOrUnsupportedMedia
        case .nonPortraitPresentation: self = .nonPortraitPresentation
        }
    }
}

struct ImportExcludedItem: Hashable, Sendable {
    let candidate: ImportCandidate
    let facts: ImportSourceFacts
    let rejection: ImportPreflightRejection
    var category: ImportExclusionCategory { ImportExclusionCategory(rejection) }
}

/// The single notice a completed operation may show (at most one, no counts). Cancellation and
/// failure are thrown, never a notice, so they suppress it by construction (ADR-042 R4 §6).
enum ImportSelectionNotice: Hashable, Sendable {
    // Multi-item session (ADR-042 R3 / R4 §6, ADR-043 R1, ADR-044 R1)
    case shortItemsExcluded
    case longItemsExcluded
    case shortAndLongItemsExcluded
    case invalidOrUnsupportedItemsExcluded
    case nonPortraitItemsExcluded
    /// Any combination that spans more than one family (duration / invalid-unsupported /
    /// non-portrait). The exact members remain available on the excluded items.
    case mixedItemsExcluded

    // Single-candidate operation (ADR-042 R2, ADR-043 R1, ADR-044 R1)
    case candidateBelowMinimum
    case candidateAboveMaximum
    case candidateInvalidOrUnsupported
    case candidateNonPortrait

    /// Pure derivation from the ordered exclusions of a completed operation.
    static func derive(context: ImportSelectionContext, excluded: [ImportExcludedItem]) -> ImportSelectionNotice? {
        guard let first = excluded.first else { return nil }
        switch context {
        case .singleCandidate:
            switch first.category {
            case .durationBelowMinimum: return .candidateBelowMinimum
            case .durationAboveMaximum: return .candidateAboveMaximum
            case .invalidOrUnsupportedMedia: return .candidateInvalidOrUnsupported
            case .nonPortraitPresentation: return .candidateNonPortrait
            }
        case .multipleItems:
            let categories = Set(excluded.map(\.category))
            if categories == [.durationBelowMinimum] { return .shortItemsExcluded }
            if categories == [.durationAboveMaximum] { return .longItemsExcluded }
            if categories == [.durationBelowMinimum, .durationAboveMaximum] { return .shortAndLongItemsExcluded }
            if categories == [.invalidOrUnsupportedMedia] { return .invalidOrUnsupportedItemsExcluded }
            if categories == [.nonPortraitPresentation] { return .nonPortraitItemsExcluded }
            return .mixedItemsExcluded
        }
    }
}

/// The complete result of one preflight over one selection. `accepted` and `excluded` each keep
/// the candidates' original relative order; together they cover every input exactly once.
struct ImportSelectionPreflightOutcome: Hashable, Sendable {
    let context: ImportSelectionContext
    let accepted: [ImportAcceptedItem]
    let excluded: [ImportExcludedItem]
    let notice: ImportSelectionNotice?

    /// True when preparation would have to run the normalizer for at least one accepted item —
    /// the Blocking Preparation Sheet condition (ADR-042 R4 §1).
    var requiresNormalization: Bool {
        accepted.contains { if case .normalizationRequired = $0.preparationPath { return true } else { return false } }
    }
}

/// Why the operation as a whole could not complete. None of these is a per-item exclusion and
/// none carries user copy.
enum ImportSelectionPreflightError: Error, Equatable, Sendable {
    /// The inspector could not observe this candidate (source vanished, non-regular, asset load
    /// failed after the file proved readable, …). Not a media fact, so never an exclusion.
    case inspectionFailed(candidate: ImportCandidateID, underlying: ImportInspectionError)
    /// The inspector threw something outside its declared error type; details kept for logging.
    case unexpectedInspectionFailure(candidate: ImportCandidateID, domain: String, code: Int)
    /// `.singleCandidate` requires exactly one candidate.
    case invalidCardinality(context: ImportSelectionContext, count: Int)
    /// Two candidates share one identity. Each picker transfer yields its own adopted file and
    /// each candidate its own identity, so a repeat is a caller defect rather than a re-selection.
    case duplicateCandidateIdentity(ImportCandidateID)
}

// MARK: - Preflight

/// Sequential, deterministic orchestration: inspect → classify → partition, in input order. The
/// existing coordinators validate sequentially too, and a selection is at most a handful of
/// items; fan-out belongs to the later preparation operation if evidence ever asks for it.
struct ImportSelectionPreflight: Sendable {
    let inspector: any ImportSourceInspecting

    init(inspector: any ImportSourceInspecting) {
        self.inspector = inspector
    }

    /// Runs the whole preflight or none of it: cancellation (checked on entry and before every
    /// candidate, and propagated unchanged from the inspector) and any inspection failure throw
    /// before a result exists, so a caller can never observe a partial Accepted Set.
    func run(_ candidates: [ImportCandidate], context: ImportSelectionContext) async throws -> ImportSelectionPreflightOutcome {
        try Task.checkCancellation()
        if context == .singleCandidate, candidates.count != 1 {
            throw ImportSelectionPreflightError.invalidCardinality(context: context, count: candidates.count)
        }
        var seen = Set<ImportCandidateID>()
        for candidate in candidates where !seen.insert(candidate.id).inserted {
            throw ImportSelectionPreflightError.duplicateCandidateIdentity(candidate.id)
        }

        var accepted: [ImportAcceptedItem] = []
        var excluded: [ImportExcludedItem] = []
        for candidate in candidates {
            try Task.checkCancellation()
            let facts = try await inspect(candidate)
            // Exhaustive on purpose (no default): a new verdict case must be classified here
            // explicitly, so no candidate can ever fall out of both lists.
            switch ImportPreflightClassifier.classify(facts) {
            case .readyFastPath(let duration):
                accepted.append(ImportAcceptedItem(candidate: candidate, facts: facts, sourceDuration: duration, preparationPath: .fastPathCopy))
            case .normalizationRequired(let reasons, let duration):
                accepted.append(ImportAcceptedItem(candidate: candidate, facts: facts, sourceDuration: duration, preparationPath: .normalizationRequired(reasons: reasons)))
            case .rejected(let rejection):
                excluded.append(ImportExcludedItem(candidate: candidate, facts: facts, rejection: rejection))
            }
        }
        // Cancellation that lands during the last inspection (after the inspector's own final
        // check) must still yield no outcome and no notice, not a complete result.
        try Task.checkCancellation()
        return ImportSelectionPreflightOutcome(
            context: context,
            accepted: accepted,
            excluded: excluded,
            notice: ImportSelectionNotice.derive(context: context, excluded: excluded)
        )
    }

    private func inspect(_ candidate: ImportCandidate) async throws -> ImportSourceFacts {
        do {
            return try await inspector.inspect(url: candidate.url)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let inspection as ImportInspectionError {
            throw ImportSelectionPreflightError.inspectionFailed(candidate: candidate.id, underlying: inspection)
        } catch {
            let details = error as NSError
            throw ImportSelectionPreflightError.unexpectedInspectionFailure(candidate: candidate.id, domain: details.domain, code: details.code)
        }
    }
}
