import Foundation

struct VlogProject: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let orientation: ProjectOrientation
    private(set) var clips: [VlogClip]

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        orientation: ProjectOrientation,
        clips: [VlogClip] = []
    ) throws {
        guard clips.allSatisfy({ $0.projectID == id }) else {
            throw DomainValidationError.clipProjectMismatch
        }

        let sortOrders = clips.map(\.sortOrder)
        guard Set(sortOrders).count == sortOrders.count else {
            throw DomainValidationError.duplicateClipSortOrder
        }

        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.orientation = orientation
        self.clips = clips.sorted { $0.sortOrder < $1.sortOrder }
    }

    var totalDuration: MediaTime {
        clips.reduce(.zero) { $0 + $1.effectiveDuration }
    }

    func displayName(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        ProjectDisplayNameFormatter.displayName(
            for: createdAt,
            locale: locale,
            timeZone: timeZone
        )
    }

    mutating func reorderClip(id clipID: UUID, toIndex destinationIndex: Int, updatedAt: Date = .now) throws {
        guard let sourceIndex = clips.firstIndex(where: { $0.id == clipID }) else {
            throw DomainValidationError.clipNotFound
        }

        guard clips.indices.contains(destinationIndex) else {
            throw DomainValidationError.invalidReorderIndex
        }

        var reordered = clips
        let movedClip = reordered.remove(at: sourceIndex)
        reordered.insert(movedClip, at: destinationIndex)
        clips = try reordered.enumerated().map { index, clip in
            try clip.assigningSortOrder(index)
        }
        self.updatedAt = updatedAt
    }
}
