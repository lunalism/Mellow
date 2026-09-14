import Foundation

/// Phase 4 direct-capture rules and tunables in one place (ADR-029 / ADR-033).
enum RecordingPolicy {
    /// Strict product minimum: sub-second captures are discarded, never rounded up.
    static let minimumDuration: TimeInterval = 1.0
    /// Highest user-visible maximum preset.
    static let absoluteMaximumDuration: TimeInterval = 5.0
    /// One nominal frame at the 30 fps capture profile. Exists only to absorb AVFoundation
    /// timestamp/encoder quantization at the maximum-duration stop; never exposed to UI.
    static let upperDurationTolerance: TimeInterval = 1.0 / 30.0
    /// Conservative V1 storage gate before any staging media is created.
    static let minimumUsableStorageBytes: Int64 = 200 * 1_024 * 1_024

    enum DurationVerdict: Equatable { case valid, tooShort, tooLong }

    /// Judges a finalized clip's actual media duration against the selected maximum.
    static func judge(duration: TimeInterval, selectedMaximum: TimeInterval) -> DurationVerdict {
        guard duration.isFinite, duration >= minimumDuration else { return .tooShort }
        let ceiling = min(selectedMaximum, absoluteMaximumDuration) + upperDurationTolerance
        return duration <= ceiling ? .valid : .tooLong
    }

    static func hasSufficientStorage(usableBytes: Int64) -> Bool {
        usableBytes >= minimumUsableStorageBytes
    }
}
