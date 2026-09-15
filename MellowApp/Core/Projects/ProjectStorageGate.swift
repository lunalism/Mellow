import Foundation

/// ADR-024 operation-aware preflight for Project media materialization (copy-only in Phase 5).
enum ProjectStorageVerdict: Equatable, Sendable {
    case sufficient
    /// Also the verdict when capacity cannot be inspected (usable reads as 0): never a silent pass.
    case insufficient(requiredBytes: Int64, usableBytes: Int64)
}

protocol ProjectStorageGating: Sendable {
    /// `additionalBytes` = Estimated Peak Additional Storage still to be allocated on the checked
    /// volume from the moment of the check; the gate adds the operation's Safety Reserve.
    func check(additionalBytes: Int64) async -> ProjectStorageVerdict
}

/// Required Free Space = Estimated Peak Additional Storage + Safety Reserve (ADR-024), judged against
/// the usable capacity of the volume that holds Project media.
struct VolumeProjectStorageGate: ProjectStorageGating {
    let capacity: @Sendable () async -> Int64
    let safetyReserveBytes: Int64

    static func requiredBytes(additionalBytes: Int64, safetyReserveBytes: Int64) -> Int64 {
        additionalBytes + safetyReserveBytes
    }

    func check(additionalBytes: Int64) async -> ProjectStorageVerdict {
        let usable = await capacity()
        let required = Self.requiredBytes(additionalBytes: additionalBytes, safetyReserveBytes: safetyReserveBytes)
        return usable >= required ? .sufficient : .insufficient(requiredBytes: required, usableBytes: usable)
    }
}

enum ProjectCompositionPolicy {
    /// Approved Phase-5 Project Bootstrap Materialization Safety Reserve: 100 MiB. Applies ONLY to the
    /// Phase-5-ready Select-Clips bootstrap path — not the Phase-4 Recording gate, the Phase-6 Import
    /// reserve, the Phase-9 Export reserve, nor a global threshold.
    static let materializationSafetyReserveBytes: Int64 = 100 * 1_024 * 1_024

    /// Remaining Estimated Peak Additional Storage for the *final* guard in `compose()`. The primary
    /// media-allocation preflight already ran per incoming file, before its first Mellow-owned copy
    /// (`ReceivedVideoFile.admit`: incoming size + reserve vs. current capacity). By the time `compose()`
    /// runs, every selected file has been adopted into the workspace on the checked volume and
    /// workspace → `Projects/<pid>/Media/<cid>.mov` is a same-volume atomic rename with no second
    /// copy, so no further media bytes are allocated and this guard enforces the reserve alone. Bytes
    /// already on the volume are never double-counted. (No normalization, transcode or intermediate
    /// output exists in Phase 5 — no overlap multiplier.)
    static func estimatedPeakAdditionalBytes(adoptedSourceBytes: Int64) -> Int64 {
        _ = adoptedSourceBytes // already allocated; kept for logging / a future copy-based store
        return 0
    }
}
