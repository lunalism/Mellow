enum DomainValidationError: Error, Equatable {
    case invalidTimeScale
    case invalidClipDuration
    case clipDurationExceedsMaximum
    case invalidTrimStart
    case trimRangeExceedsSourceDuration
    case invalidMediaRelativePath
    case clipProjectMismatch
    case duplicateClipSortOrder
    case clipNotFound
    case invalidReorderIndex
}
