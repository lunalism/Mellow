import Foundation
import SwiftData

@Model
final class PersistedVlogProject {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var orientationRawValue: String

    @Relationship(deleteRule: .cascade, inverse: \PersistedVlogClip.project)
    var clips: [PersistedVlogClip] = []

    init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        orientationRawValue: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.orientationRawValue = orientationRawValue
    }
}

@Model
final class PersistedVlogClip {
    @Attribute(.unique) var id: UUID
    var sourceKindRawValue: String
    var mediaRelativePath: String
    var createdAt: Date
    var sourceDurationValue: Int64
    var sourceDurationTimescale: Int32
    var trimStartValue: Int64
    var trimStartTimescale: Int32
    var trimDurationValue: Int64
    var trimDurationTimescale: Int32
    var framingCenterX: Double?
    var framingCenterY: Double?
    var framingScale: Double?
    var sortOrder: Int
    var project: PersistedVlogProject?

    init(
        id: UUID,
        sourceKindRawValue: String,
        mediaRelativePath: String,
        createdAt: Date,
        sourceDurationValue: Int64,
        sourceDurationTimescale: Int32,
        trimStartValue: Int64,
        trimStartTimescale: Int32,
        trimDurationValue: Int64,
        trimDurationTimescale: Int32,
        framingCenterX: Double?,
        framingCenterY: Double?,
        framingScale: Double?,
        sortOrder: Int
    ) {
        self.id = id
        self.sourceKindRawValue = sourceKindRawValue
        self.mediaRelativePath = mediaRelativePath
        self.createdAt = createdAt
        self.sourceDurationValue = sourceDurationValue
        self.sourceDurationTimescale = sourceDurationTimescale
        self.trimStartValue = trimStartValue
        self.trimStartTimescale = trimStartTimescale
        self.trimDurationValue = trimDurationValue
        self.trimDurationTimescale = trimDurationTimescale
        self.framingCenterX = framingCenterX
        self.framingCenterY = framingCenterY
        self.framingScale = framingScale
        self.sortOrder = sortOrder
    }
}

extension PersistedVlogProject {
    convenience init(project: VlogProject) {
        self.init(
            id: project.id,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            orientationRawValue: project.orientation.rawValue
        )

        clips = project.clips.map(PersistedVlogClip.init(clip:))
        clips.forEach { $0.project = self }
    }

    func apply(_ project: VlogProject) {
        createdAt = project.createdAt
        updatedAt = project.updatedAt
    }

    func domainValue() throws -> VlogProject {
        guard let orientation = ProjectOrientation(rawValue: orientationRawValue) else {
            throw ProjectRepositoryError.invalidPersistedMetadata
        }

        return try VlogProject(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            orientation: orientation,
            clips: try clips.map { try $0.domainValue(projectID: id) }
        )
    }
}

extension PersistedVlogClip {
    convenience init(clip: VlogClip) {
        self.init(
            id: clip.id,
            sourceKindRawValue: clip.sourceKind.rawValue,
            mediaRelativePath: clip.mediaRelativePath.value,
            createdAt: clip.createdAt,
            sourceDurationValue: clip.sourceDuration.value,
            sourceDurationTimescale: clip.sourceDuration.timescale,
            trimStartValue: clip.trimStart.value,
            trimStartTimescale: clip.trimStart.timescale,
            trimDurationValue: clip.trimDuration.value,
            trimDurationTimescale: clip.trimDuration.timescale,
            framingCenterX: clip.framing?.normalizedCenterX,
            framingCenterY: clip.framing?.normalizedCenterY,
            framingScale: clip.framing?.scale,
            sortOrder: clip.sortOrder
        )
    }

    func apply(_ clip: VlogClip) {
        sourceKindRawValue = clip.sourceKind.rawValue
        mediaRelativePath = clip.mediaRelativePath.value
        createdAt = clip.createdAt
        sourceDurationValue = clip.sourceDuration.value
        sourceDurationTimescale = clip.sourceDuration.timescale
        trimStartValue = clip.trimStart.value
        trimStartTimescale = clip.trimStart.timescale
        trimDurationValue = clip.trimDuration.value
        trimDurationTimescale = clip.trimDuration.timescale
        framingCenterX = clip.framing?.normalizedCenterX
        framingCenterY = clip.framing?.normalizedCenterY
        framingScale = clip.framing?.scale
        sortOrder = clip.sortOrder
    }

    func domainValue(projectID: UUID) throws -> VlogClip {
        guard let sourceKind = ClipSourceKind(rawValue: sourceKindRawValue) else {
            throw ProjectRepositoryError.invalidPersistedMetadata
        }

        let framing: ClipFraming?
        switch (framingCenterX, framingCenterY, framingScale) {
        case (nil, nil, nil):
            framing = nil
        case let (centerX?, centerY?, scale?):
            framing = ClipFraming(
                normalizedCenterX: centerX,
                normalizedCenterY: centerY,
                scale: scale
            )
        default:
            throw ProjectRepositoryError.invalidPersistedMetadata
        }

        return try VlogClip(
            id: id,
            projectID: projectID,
            sourceKind: sourceKind,
            mediaRelativePath: try RelativeMediaPath(mediaRelativePath),
            createdAt: createdAt,
            sourceDuration: try MediaTime(value: sourceDurationValue, timescale: sourceDurationTimescale),
            trimStart: try MediaTime(value: trimStartValue, timescale: trimStartTimescale),
            trimDuration: try MediaTime(value: trimDurationValue, timescale: trimDurationTimescale),
            framing: framing,
            sortOrder: sortOrder
        )
    }
}
