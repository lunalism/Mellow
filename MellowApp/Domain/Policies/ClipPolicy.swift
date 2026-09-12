enum ClipPolicy {
    static let maximumDuration = MediaTime.seconds(10)

    static func validateEffectiveDuration(_ duration: MediaTime) throws {
        guard duration > .zero else {
            throw DomainValidationError.invalidClipDuration
        }

        guard duration <= maximumDuration else {
            throw DomainValidationError.clipDurationExceedsMaximum
        }
    }
}
