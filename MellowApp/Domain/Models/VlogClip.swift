import Foundation

struct VlogClip: Identifiable, Equatable, Sendable {
    let id: UUID
    let projectID: UUID
    let sourceKind: ClipSourceKind
    let mediaRelativePath: RelativeMediaPath
    let createdAt: Date
    let sourceDuration: MediaTime
    let trimStart: MediaTime
    let trimDuration: MediaTime
    let framing: ClipFraming?
    let sortOrder: Int

    init(
        id: UUID = UUID(),
        projectID: UUID,
        sourceKind: ClipSourceKind,
        mediaRelativePath: RelativeMediaPath,
        createdAt: Date = .now,
        sourceDuration: MediaTime,
        trimStart: MediaTime = .zero,
        trimDuration: MediaTime,
        framing: ClipFraming? = nil,
        sortOrder: Int
    ) throws {
        guard sourceDuration > .zero else {
            throw DomainValidationError.invalidClipDuration
        }

        guard trimStart >= .zero else {
            throw DomainValidationError.invalidTrimStart
        }

        try ClipPolicy.validateEffectiveDuration(trimDuration)

        guard trimStart + trimDuration <= sourceDuration else {
            throw DomainValidationError.trimRangeExceedsSourceDuration
        }

        self.id = id
        self.projectID = projectID
        self.sourceKind = sourceKind
        self.mediaRelativePath = mediaRelativePath
        self.createdAt = createdAt
        self.sourceDuration = sourceDuration
        self.trimStart = trimStart
        self.trimDuration = trimDuration
        self.framing = framing
        self.sortOrder = sortOrder
    }

    var effectiveDuration: MediaTime {
        trimDuration
    }

    func assigningSortOrder(_ sortOrder: Int) throws -> VlogClip {
        try VlogClip(
            id: id,
            projectID: projectID,
            sourceKind: sourceKind,
            mediaRelativePath: mediaRelativePath,
            createdAt: createdAt,
            sourceDuration: sourceDuration,
            trimStart: trimStart,
            trimDuration: trimDuration,
            framing: framing,
            sortOrder: sortOrder
        )
    }
}
