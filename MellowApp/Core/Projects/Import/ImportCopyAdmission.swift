import Foundation

// ADR-050 050-C C0 / C0a copy admission (accepted 2026-10-06 "050-C 실행 경계 승인"): before each Mellow-owned
// full copy of an incoming file — the picker transfer copy into `tmp/ProjectMediaTransfer` (C0) and, only when
// adoption's rename fails, the fallback copy into the Mellow root (C0a) — the copy's destination volume must hold
// the source's logical bytes + the 256 MiB Import reserve. Equality passes; an unknown size or capacity, invalid
// input or arithmetic overflow fails closed. The arithmetic is `ImportStorageEstimator`'s, unchanged. This is an
// admission check only: it does not prove the capacity reading is fresh or that space stays available while
// writing, and it assumes no APFS clone. The provider's own file is never counted or touched.

enum ImportCopyBoundary: Hashable, Sendable {
    /// C0: immediately before Mellow copies the provider-supplied file into its transfer directory.
    case c0TransferCopy
    /// C0a: immediately before `adopt` falls back from rename to copy (Mellow-root volume).
    case c0aAdoptionCopyFallback
}

/// Typed reason for a copy-admission refusal (logged without paths; never user copy).
enum ImportCopyRefusalReason: Hashable, Sendable {
    case sourceSizeUnknown
    /// No admission gate was published for the transfer.
    case admissionUnavailable
    case insufficient
    case capacityUnknown
    /// Invalid input or arithmetic overflow.
    case invalidEstimate
}

enum ImportCopyAdmission {
    /// The file's logical size (`fileSizeKey`), or nil when it cannot be read or is negative.
    static func sourceByteCount(of url: URL) -> Int64? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size >= 0 else { return nil }
        return Int64(size)
    }

    /// The usable capacity of the volume holding `location` through the existing convention
    /// (`volumeAvailableCapacityForImportantUsage`); nil when it cannot be read or is negative. Not a freshness claim.
    static func usableCapacity(forVolumeOf location: URL) -> Int64? {
        guard let value = try? location.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
              value >= 0 else { return nil }
        return value
    }

    /// `sourceBytes + Reserve_import <= usable` through `ImportStorageEstimator.requirement` / `check`. Unknown capacity
    /// is `capacityUnknown`; overflow or invalid input is `invalidEstimate`; an unknown size (nil) also refuses as an
    /// invalid estimate — callers report it as `ImportCopyRefusalReason.sourceSizeUnknown`. Only `.sufficient` admits.
    static func check(sourceBytes: Int64?, usableCapacity: Int64?) -> ImportStorageCheck {
        guard let sourceBytes else { return .invalidEstimate(.negativeByteCount) }
        do {
            let requirement = try ImportStorageEstimator.requirement(outputBytes: sourceBytes, metadataBytes: 0)
            return ImportStorageEstimator.check(requirement, usableCapacityBytes: usableCapacity)
        } catch {
            return .invalidEstimate(error)
        }
    }

    /// The typed refusal reason of a check; nil when it admits.
    static func refusalReason(_ check: ImportStorageCheck) -> ImportCopyRefusalReason? {
        switch check {
        case .sufficient: return nil
        case .insufficient: return .insufficient
        case .capacityUnknown: return .capacityUnknown
        case .invalidEstimate: return .invalidEstimate
        }
    }

    /// The selector-facing verdict for a check (`ProjectStorageVerdict` has no "unknown": an unreadable capacity
    /// reports `usableBytes` 0, an unknown requirement `requiredBytes` 0 — both refusals, as in Phase 5).
    static func verdict(_ check: ImportStorageCheck) -> ProjectStorageVerdict {
        switch check {
        case .sufficient: return .sufficient
        case .insufficient(let required, let usable): return .insufficient(requiredBytes: required, usableBytes: usable)
        case .capacityUnknown(let required): return .insufficient(requiredBytes: required, usableBytes: 0)
        case .invalidEstimate: return .insufficient(requiredBytes: 0, usableBytes: 0)
        }
    }
}

/// C0 as the selection boundary's per-file admission (`ProjectMediaSelecting`'s `admission`): the incoming byte
/// count + the Import reserve against the TRANSFER directory's volume. Replaces the Phase 5 pre-copy admission
/// (100 MiB reserve) there only; the Phase 5 commit-time final guard keeps its own gate and reserve.
struct ImportTransferCopyGate: ProjectStorageGating {
    /// The usable capacity of the volume that receives the transfer copy; nil = unknown (fails closed).
    let capacity: @Sendable () async -> Int64?

    /// Production: the volume holding `ReceivedVideoFile.transferDirectory` (read through its existing parent, the app's
    /// temporary directory), so the gate and the copy destination are the same location by construction.
    static func transferVolume() -> ImportTransferCopyGate {
        ImportTransferCopyGate { ImportCopyAdmission.usableCapacity(forVolumeOf: ReceivedVideoFile.transferDirectory.deletingLastPathComponent()) }
    }

    func check(additionalBytes: Int64) async -> ProjectStorageVerdict {
        guard additionalBytes >= 0 else { return .insufficient(requiredBytes: 0, usableBytes: 0) }
        return ImportCopyAdmission.verdict(ImportCopyAdmission.check(sourceBytes: additionalBytes, usableCapacity: await capacity()))
    }
}
