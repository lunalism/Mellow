enum ClipPolicy {
    /// ADR-029: every clip from any source satisfies `0 < effectiveClipDuration <= 5 seconds`.
    static let maximumDuration = MediaTime.seconds(5)

    static func validateEffectiveDuration(_ duration: MediaTime) throws {
        guard duration > .zero else {
            throw DomainValidationError.invalidClipDuration
        }

        guard duration <= maximumDuration else {
            throw DomainValidationError.clipDurationExceedsMaximum
        }
    }
}
