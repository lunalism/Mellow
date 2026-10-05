import AVFoundation
import Foundation

// ADR-050 Units 050-A / 050-B and the 050-C calculation policy (partially accepted 2026-10-02):
// the pure Import storage estimate and capacity check. Exact checked integer arithmetic over the
// rational source duration; no floating point, no media, no filesystem. Every value is a policy
// estimate, not a proven upper bound, and the reserve is not guaranteed to cover unmeasured risks.
// Nothing here is wired to the picker, the normalizer, the repository or any UI yet.

enum ImportStoragePolicy {
    /// 050-A `R_video`: empirical normalized-output rate (Step 5A sample maximum, rounded up).
    static let videoBytesPerSecond: Int64 = 7_500_000
    /// 050-A `m = 1/2`, applied to the video term as the factor `(1 + m) = 3/2`.
    static let videoMarginNumerator: Int64 = 3
    static let videoMarginDenominator: Int64 = 2
    /// 050-A `C_out`: container / allocation allowance per normalized output file.
    static let outputFileAllowanceBytes: Int64 = 2_097_152
    /// 050-A `R_tx`: `audioTranscode` allowance rate, twice the ADR-048 AAC-LC request.
    static let transcodeAudioBytesPerSecond: Int64 = 32_000
    /// 050-A priming + final-frame padding for transcoded audio: `3136 / 48000 s`.
    static let transcodeAudioPaddingSamples: Int64 = 3_136
    static let transcodeAudioSampleRate: Int64 = 48_000
    /// 050-A `D_bound`: ADR-045 §7 output-duration tolerance `+ 1/30 s`.
    static let outputDurationToleranceDenominator: Int64 = 30
    /// 050-B `W_save` / `W_row`.
    static let metadataBytesPerSave: Int64 = 196_608
    static let metadataBytesPerRow: Int64 = 512
    /// 050-C Import Safety Reserve (Import-only; never the Phase 5 100 MiB reserve).
    static let importSafetyReserveBytes: Int64 = 268_435_456
}

enum ImportStorageEstimateError: Error, Hashable, Sendable {
    case nonPositiveDuration
    case negativeByteCount
    case negativeRowCount
    case arithmeticOverflow
    /// An internal exact-rational value was outside its domain (negative numerator or non-positive
    /// denominator). Not reachable from validated public inputs; reported instead of mislabelled.
    case invalidRational
    /// AAC passthrough is planned but `S_audio` is unavailable: fail closed (050-A — never a pass, never zero).
    case sourceAudioPayloadUnavailable
}

/// How a normalized output's audio is estimated (050-A).
enum ImportOutputAudioEstimate: Hashable, Sendable {
    /// No output audio track.
    case none
    /// AAC passthrough: the source audio track's sample-data payload bytes, supplied explicitly by
    /// the caller. Never the whole source file size.
    case passthrough(sourcePayloadBytes: Int64)
    /// ADR-048 `audioTranscode` to AAC-LC 48 kHz.
    case transcode
}

/// One Accepted Set item as the estimate sees it.
enum ImportStorageItem: Hashable, Sendable {
    /// Fast path: materialized by same-volume rename, so it adds no output bytes.
    case ready
    /// Normalization still to run.
    case normalized(sourceDuration: MediaTime, audio: ImportOutputAudioEstimate)
    /// Normalization output already written: it is existing occupancy, never counted again.
    case normalizedOutputWritten
}

/// One normalized output's estimate with every policy term kept visible.
struct ImportNormalizedOutputEstimate: Hashable, Sendable {
    /// `ceil(R_video × D_bound)`.
    let videoBaseBytes: Int64
    /// `ceil(R_video × D_bound × 3/2) − videoBaseBytes`.
    let videoMarginBytes: Int64
    let audioBytes: Int64
    let fileAllowanceBytes: Int64

    var videoBytes: Int64 { videoBaseBytes + videoMarginBytes }
    var totalBytes: Int64 { videoBytes + audioBytes + fileAllowanceBytes }

    /// Only the estimator builds this, after proving `totalBytes` cannot overflow.
    fileprivate init(videoBaseBytes: Int64, videoMarginBytes: Int64, audioBytes: Int64, fileAllowanceBytes: Int64) {
        self.videoBaseBytes = videoBaseBytes
        self.videoMarginBytes = videoMarginBytes
        self.audioBytes = audioBytes
        self.fileAllowanceBytes = fileAllowanceBytes
    }
}

/// The repository save sequence of one operation (050-B row counts; pending-deleted rows included).
enum ImportMetadataOperation: Hashable, Sendable {
    /// Select Clips new Project: `create(B)`, rows = n.
    case createProject(newClips: Int)
    /// Select Clips `.replacingSaved`: `create(B)` rows = n, then delete of A rows = D_replaced.
    case replacingSaved(newClips: Int, replacedDurableClips: Int)
    /// Editor Add: one `update` rewriting every durable clip, rows = D_existing + n.
    case add(existingDurableClips: Int, newClips: Int)
    /// Editor Replace: one `update`, rows = D_existing + 1.
    case replace(existingDurableClips: Int)

    /// Rows written or deleted by each repository save, in order. Every input count must be ≥ 0.
    func rowsPerSave() throws(ImportStorageEstimateError) -> [Int] {
        func count(_ values: Int...) throws(ImportStorageEstimateError) -> Int {
            var total = 0
            for value in values {
                guard value >= 0 else { throw ImportStorageEstimateError.negativeRowCount }
                let (sum, overflow) = total.addingReportingOverflow(value)
                guard !overflow else { throw ImportStorageEstimateError.arithmeticOverflow }
                total = sum
            }
            return total
        }
        switch self {
        case .createProject(let n): return [try count(n)]
        case .replacingSaved(let n, let replaced): return [try count(n), try count(replaced)]
        case .add(let existing, let n): return [try count(existing, n)]
        case .replace(let existing): return [try count(existing, 1)]
        }
    }
}

struct ImportMetadataEstimate: Hashable, Sendable {
    let saveCount: Int
    let rowCount: Int
    let bytes: Int64
}

/// Additional bytes on one volume plus the reserve, with each part distinguishable.
struct ImportStorageRequirement: Hashable, Sendable {
    let outputBytes: Int64
    let metadataBytes: Int64
    let reserveBytes: Int64

    var additionalBytes: Int64 { outputBytes + metadataBytes }
    var requiredBytes: Int64 { additionalBytes + reserveBytes }

    /// Only the estimator builds this, after proving `requiredBytes` cannot overflow.
    fileprivate init(outputBytes: Int64, metadataBytes: Int64, reserveBytes: Int64) {
        self.outputBytes = outputBytes
        self.metadataBytes = metadataBytes
        self.reserveBytes = reserveBytes
    }
}

enum ImportStorageCheck: Hashable, Sendable {
    case sufficient(requiredBytes: Int64, usableBytes: Int64)
    case insufficient(requiredBytes: Int64, usableBytes: Int64)
    /// Capacity could not be read (or was negative): never a pass.
    case capacityUnknown(requiredBytes: Int64)
    /// The estimate itself could not be computed: never a pass.
    case invalidEstimate(ImportStorageEstimateError)

    var passes: Bool {
        if case .sufficient = self { return true }
        return false
    }
}

enum ImportStorageEstimator {
    // MARK: Output audio input (050-A / OA-4)

    /// The estimate's audio input from the ACTUAL normalization plan's audio strategy and the measured
    /// source payload. The plan decides (never "non-AAC" alone): no output audio → `.none`; transcode →
    /// the accepted transcode estimate; AAC passthrough → the measured `S_audio` (max of the track's stored
    /// and delivered bytes), and without a measurement the estimate fails closed.
    static func outputAudio(for strategy: WorkingMediaAudioStrategy, sourcePayload: ImportAudioPayloadMeasurement) throws(ImportStorageEstimateError) -> ImportOutputAudioEstimate {
        switch strategy {
        case .none:
            return .none
        case .transcode:
            return .transcode
        case .passthroughAAC:
            // S_audio = max(stored, delivered) of the selected track (OA-4 clarification 2026-10-05).
            guard let bytes = sourcePayload.sAudioBytes else { throw .sourceAudioPayloadUnavailable }
            guard bytes >= 0 else { throw .negativeByteCount }
            return .passthrough(sourcePayloadBytes: bytes)
        }
    }

    // MARK: Normalized output (050-A)

    static func normalizedOutput(sourceDuration: MediaTime, audio: ImportOutputAudioEstimate) throws(ImportStorageEstimateError) -> ImportNormalizedOutputEstimate {
        guard sourceDuration.value > 0 else { throw ImportStorageEstimateError.nonPositiveDuration }
        // D_bound = sourceDuration + 1/30 s, kept as a reduced exact rational so large timescales
        // (e.g. nanosecond CMTime) never overflow an intermediate product.
        let bound = try ImportStorageRatio(sourceDuration.value, Int64(sourceDuration.timescale))
            .adding(try ImportStorageRatio(1, ImportStoragePolicy.outputDurationToleranceDenominator))
        let video = try bound.scaled(by: ImportStoragePolicy.videoBytesPerSecond)
        let base = video.ceiling
        let withMargin = try video.scaled(by: ImportStoragePolicy.videoMarginNumerator, over: ImportStoragePolicy.videoMarginDenominator).ceiling

        let audioBytes: Int64
        switch audio {
        case .none:
            audioBytes = 0
        case .passthrough(let payload):
            guard payload >= 0 else { throw ImportStorageEstimateError.negativeByteCount }
            audioBytes = payload
        case .transcode:
            let padding = try ImportStorageRatio(ImportStoragePolicy.transcodeAudioPaddingSamples, ImportStoragePolicy.transcodeAudioSampleRate)
            audioBytes = try bound.adding(padding).scaled(by: ImportStoragePolicy.transcodeAudioBytesPerSecond).ceiling
        }

        let estimate = ImportNormalizedOutputEstimate(
            videoBaseBytes: base,
            videoMarginBytes: withMargin - base,
            audioBytes: audioBytes,
            fileAllowanceBytes: ImportStoragePolicy.outputFileAllowanceBytes
        )
        _ = try add(try add(estimate.videoBytes, estimate.audioBytes), estimate.fileAllowanceBytes)
        return estimate
    }

    /// Output bytes still to be written for these items. Ready items and outputs already on disk add 0.
    static func remainingOutputBytes(_ items: [ImportStorageItem]) throws(ImportStorageEstimateError) -> Int64 {
        var total: Int64 = 0
        for item in items {
            guard case .normalized(let duration, let audio) = item else { continue }
            total = try add(total, try normalizedOutput(sourceDuration: duration, audio: audio).totalBytes)
        }
        return total
    }

    // MARK: Metadata (050-B)

    static func metadata(_ operation: ImportMetadataOperation) throws(ImportStorageEstimateError) -> ImportMetadataEstimate {
        let saves = try operation.rowsPerSave()
        var bytes: Int64 = 0, rows = 0
        for rowCount in saves {
            rows = try add(rows, rowCount)
            bytes = try add(bytes, try add(ImportStoragePolicy.metadataBytesPerSave, try mul(ImportStoragePolicy.metadataBytesPerRow, Int64(rowCount))))
        }
        return ImportMetadataEstimate(saveCount: saves.count, rowCount: rows, bytes: bytes)
    }

    // MARK: Requirement and check (050-C calculation policy)

    /// Requirement for writes to ONE volume. Callers pass only that volume's additional writes and
    /// never add bytes already on disk (they are reflected in the capacity reading).
    static func requirement(outputBytes: Int64, metadataBytes: Int64) throws(ImportStorageEstimateError) -> ImportStorageRequirement {
        guard outputBytes >= 0, metadataBytes >= 0 else { throw ImportStorageEstimateError.negativeByteCount }
        let requirement = ImportStorageRequirement(outputBytes: outputBytes, metadataBytes: metadataBytes, reserveBytes: ImportStoragePolicy.importSafetyReserveBytes)
        _ = try add(try add(outputBytes, metadataBytes), requirement.reserveBytes)
        return requirement
    }

    static func requirement(remaining items: [ImportStorageItem], metadata operation: ImportMetadataOperation?) throws(ImportStorageEstimateError) -> ImportStorageRequirement {
        let outputBytes = try remainingOutputBytes(items)
        var metadataBytes: Int64 = 0
        if let operation { metadataBytes = try metadata(operation).bytes }
        return try requirement(outputBytes: outputBytes, metadataBytes: metadataBytes)
    }

    /// Additional + reserve ≤ usable passes (equality passes). Unknown or negative capacity never passes.
    static func check(_ requirement: ImportStorageRequirement, usableCapacityBytes: Int64?) -> ImportStorageCheck {
        let required = requirement.requiredBytes
        guard let usable = usableCapacityBytes, usable >= 0 else { return .capacityUnknown(requiredBytes: required) }
        return required <= usable ? .sufficient(requiredBytes: required, usableBytes: usable) : .insufficient(requiredBytes: required, usableBytes: usable)
    }

    /// Computes the requirement, then reads capacity from the injected provider. The closure can only
    /// throw an estimate error (typed throws), which is returned as-is without reading capacity.
    static func check(
        requirement compute: () throws(ImportStorageEstimateError) -> ImportStorageRequirement,
        capacity: () async -> Int64?
    ) async -> ImportStorageCheck {
        let requirement: ImportStorageRequirement
        do { requirement = try compute() } catch { return .invalidEstimate(error) }
        return check(requirement, usableCapacityBytes: await capacity())
    }

    // MARK: Checked arithmetic

    private static func mul(_ a: Int64, _ b: Int64) throws(ImportStorageEstimateError) -> Int64 {
        let (r, o) = a.multipliedReportingOverflow(by: b)
        guard !o else { throw ImportStorageEstimateError.arithmeticOverflow }
        return r
    }

    private static func add(_ a: Int64, _ b: Int64) throws(ImportStorageEstimateError) -> Int64 {
        let (r, o) = a.addingReportingOverflow(b)
        guard !o else { throw ImportStorageEstimateError.arithmeticOverflow }
        return r
    }

    private static func add(_ a: Int, _ b: Int) throws(ImportStorageEstimateError) -> Int {
        let (r, o) = a.addingReportingOverflow(b)
        guard !o else { throw ImportStorageEstimateError.arithmeticOverflow }
        return r
    }

}

/// A non-negative exact rational, always reduced. Factors are cancelled before every multiplication,
/// and any product that still overflows throws instead of wrapping or rounding.
struct ImportStorageRatio {
    let numerator: Int64
    let denominator: Int64

    init(_ numerator: Int64, _ denominator: Int64) throws(ImportStorageEstimateError) {
        guard numerator >= 0, denominator > 0 else { throw ImportStorageEstimateError.invalidRational }
        let g = ImportStorageRatio.gcd(numerator, denominator)
        self.numerator = numerator / g
        self.denominator = denominator / g
    }

    var ceiling: Int64 {
        let quotient = numerator / denominator
        return numerator % denominator == 0 ? quotient : quotient + 1
    }

    func adding(_ other: ImportStorageRatio) throws(ImportStorageEstimateError) -> ImportStorageRatio {
        let g = ImportStorageRatio.gcd(denominator, other.denominator)
        let lcm = try ImportStorageRatio.mul(denominator / g, other.denominator)
        let lhs = try ImportStorageRatio.mul(numerator, lcm / denominator)
        let rhs = try ImportStorageRatio.mul(other.numerator, lcm / other.denominator)
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw ImportStorageEstimateError.arithmeticOverflow }
        return try ImportStorageRatio(sum, lcm)
    }

    /// `self × factor / divisor` with cross-cancellation first.
    func scaled(by factor: Int64, over divisor: Int64 = 1) throws(ImportStorageEstimateError) -> ImportStorageRatio {
        // Validated before any gcd / division so `Int64.min / -1` can never trap.
        guard factor >= 0, divisor > 0 else { throw ImportStorageEstimateError.invalidRational }
        let g1 = ImportStorageRatio.gcd(factor, denominator), g2 = ImportStorageRatio.gcd(numerator, divisor)
        return try ImportStorageRatio(try ImportStorageRatio.mul(factor / g1, numerator / g2), try ImportStorageRatio.mul(denominator / g1, divisor / g2))
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var (x, y) = (a, b)
        while y != 0 { (x, y) = (y, x % y) }
        return x == 0 ? 1 : x
    }

    private static func mul(_ a: Int64, _ b: Int64) throws(ImportStorageEstimateError) -> Int64 {
        let (r, o) = a.multipliedReportingOverflow(by: b)
        guard !o else { throw ImportStorageEstimateError.arithmeticOverflow }
        return r
    }
}

// MARK: - Accepted-set composition (inputs for the 050-A / 050-B / 050-C calculation; unwired)

/// Why an accepted set could not be composed into estimate inputs. Every case fails closed.
enum ImportStorageCompositionError: Error, Hashable, Sendable {
    case estimate(ImportStorageEstimateError)
    /// Internal guard: an empty accepted set is no operation (not a 050-B policy statement).
    case emptyAcceptedSet
    case duplicateItem(ImportCandidateID)
    /// A normalization item has no plan, so its output would silently be left out.
    case missingPlan(ImportCandidateID)
    /// A plan was supplied for a fast-path item or for an ID that is not in the set.
    case unexpectedPlan(ImportCandidateID)
    /// The supplied plan is not the one the plan builder derives for that accepted item.
    case planDoesNotMatchItem(ImportCandidateID)
    case unknownItem(ImportCandidateID)
    case notANormalizationItem(ImportCandidateID)
    case outputAlreadyWritten(ImportCandidateID)
    case invalidAcceptedCount(expected: Int, actual: Int)
}

/// The Project-level shape of one import operation, from operation-local values only (no repository
/// reads). Durable row counts include pending-deleted Clips (050-B).
enum ImportStorageOperation: Equatable, Sendable {
    case createProject
    /// Select Clips `.replacingSaved`: keeps the conservative two-save metadata charge (050-B).
    case replacingSaved(previous: VlogProject)
    case add(to: VlogProject)
    /// Editor Replace: exactly one accepted item.
    case replaceClip(in: VlogProject)

    func metadataOperation(acceptedCount: Int) throws(ImportStorageCompositionError) -> ImportMetadataOperation {
        guard acceptedCount > 0 else { throw .emptyAcceptedSet }
        switch self {
        case .createProject:
            return .createProject(newClips: acceptedCount)
        case .replacingSaved(let previous):
            return .replacingSaved(newClips: acceptedCount, replacedDurableClips: previous.durableClips.count)
        case .add(let target):
            return .add(existingDurableClips: target.durableClips.count, newClips: acceptedCount)
        case .replaceClip(let target):
            guard acceptedCount == 1 else { throw .invalidAcceptedCount(expected: 1, actual: acceptedCount) }
            return .replace(existingDurableClips: target.durableClips.count)
        }
    }
}

/// One operation's accepted set as estimate inputs, with each item's remaining work explicit. Built
/// from the accepted items and the ACTUAL normalization plans; every normalization item must have its
/// plan (none may be left out), fast-path items take none and never need an audio measurement. Ready
/// items and written outputs add no output bytes; the metadata charge stays until the operation ends.
/// A calculation only: it does not accept where, when or how a check (C1 / C2 / C3) runs or is shown.
/// One set describes ONE attempt: written outputs never revert, so a retry (CR, "same as C1") builds a new
/// set. The durable row count is captured from the `VlogProject` snapshot given at construction; this
/// estimate does not establish that the snapshot is still current. It is conservative only if the rows
/// charged at the relevant save do not exceed those captured, so any future wiring must obtain or revalidate
/// these operation inputs under the appropriate serialization boundary.
struct ImportStorageWorkSet: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let id: ImportCandidateID
        /// `.ready`, `.normalized` (output still to write) or `.normalizedOutputWritten`.
        fileprivate(set) var item: ImportStorageItem
    }

    private(set) var entries: [Entry]
    let metadataOperation: ImportMetadataOperation

    init(accepted: [ImportAcceptedItem], plans: [ImportCandidateID: WorkingMediaNormalizationPlan],
         operation: ImportStorageOperation) throws(ImportStorageCompositionError) {
        var seen = Set<ImportCandidateID>()
        var entries: [Entry] = []
        for item in accepted {
            let id = item.candidate.id
            guard seen.insert(id).inserted else { throw .duplicateItem(id) }
            guard item.preparationPath.normalization != nil else {
                if plans[id] != nil { throw .unexpectedPlan(id) }
                entries.append(Entry(id: id, item: .ready))
                continue
            }
            guard let plan = plans[id] else { throw .missingPlan(id) }
            guard let derived = try? WorkingMediaPlanBuilder.plan(for: item), derived == plan else { throw .planDoesNotMatchItem(id) }
            let normalized: ImportStorageItem
            do {
                let audio = try ImportStorageEstimator.outputAudio(for: plan.audio, sourcePayload: item.facts.audioPayload)
                // Computed once here so an invalid input fails the set now, not at a later check.
                _ = try ImportStorageEstimator.normalizedOutput(sourceDuration: plan.sourceDuration, audio: audio)
                normalized = .normalized(sourceDuration: plan.sourceDuration, audio: audio)
            } catch {
                throw .estimate(error)
            }
            entries.append(Entry(id: id, item: normalized))
        }
        if let stray = plans.keys.filter({ !seen.contains($0) }).min(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            throw .unexpectedPlan(stray)
        }
        self.metadataOperation = try operation.metadataOperation(acceptedCount: accepted.count)
        self.entries = entries
    }

    /// Records that one normalization item's output is now on disk (existing occupancy from here on).
    mutating func markOutputWritten(_ id: ImportCandidateID) throws(ImportStorageCompositionError) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw .unknownItem(id) }
        switch entries[index].item {
        case .ready: throw .notANormalizationItem(id)
        case .normalizedOutputWritten: throw .outputAlreadyWritten(id)
        case .normalized: entries[index].item = .normalizedOutputWritten
        }
    }

    /// The items as the estimate sees them now, in accepted order.
    var items: [ImportStorageItem] { entries.map(\.item) }

    /// Normalization items whose output is not written yet.
    var pendingNormalizationIDs: [ImportCandidateID] {
        entries.filter { if case .normalized = $0.item { return true } else { return false } }.map(\.id)
    }

    /// Remaining output bytes + this operation's metadata, with the Import reserve kept separate
    /// (`ImportStorageRequirement`). Reuses the accepted estimator arithmetic unchanged.
    func requirement() throws(ImportStorageCompositionError) -> ImportStorageRequirement {
        do { return try ImportStorageEstimator.requirement(remaining: items, metadata: metadataOperation) } catch { throw .estimate(error) }
    }
}

// MARK: - Out-of-space classification (050-C)

enum ImportWriteFailureKind: Hashable, Sendable {
    case outOfSpace
    case other
}

/// Implemented and unwired: a typed classification only. Its logging and presentation are not a
/// separately accepted policy (they remain Proposed with the 050-C boundaries).
enum ImportWriteFailureClassifier {
    /// `.outOfSpace` when the error, or any underlying error it carries, is Cocoa
    /// `NSFileWriteOutOfSpaceError` (640), POSIX `ENOSPC`, or `AVError.diskFull`.
    static func classify(_ error: Error) -> ImportWriteFailureKind {
        isOutOfSpace(error as NSError, depth: 0) ? .outOfSpace : .other
    }

    private static let maximumDepth = 8

    private static func isOutOfSpace(_ error: NSError, depth: Int) -> Bool {
        guard depth <= maximumDepth else { return false }
        switch error.domain {
        case NSCocoaErrorDomain where error.code == NSFileWriteOutOfSpaceError: return true
        case NSPOSIXErrorDomain where error.code == Int(ENOSPC): return true
        case AVFoundationErrorDomain where error.code == AVError.Code.diskFull.rawValue: return true
        default: break
        }
        var underlying: [NSError] = []
        if let single = error.userInfo[NSUnderlyingErrorKey] as? NSError { underlying.append(single) }
        if let many = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] { underlying.append(contentsOf: many) }
        return underlying.contains { isOutOfSpace($0, depth: depth + 1) }
    }
}
