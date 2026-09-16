import Foundation

/// A Project's durable state: the ACTIVE logical timeline (`clips`, ordered, what the user sees and
/// edits) plus the DURABLE set of logically deleted Clips (`deletedClips`, ADR-021 pending
/// deletion). Both sets are persisted; only an explicit physical-cleanup operation ever removes a
/// deleted Clip's metadata. Every consumer of "the Project's clips" (total duration, thumbnails,
/// reorder, counts) means the active timeline; deletion / Undo / cleanup logic is the only reader of
/// `deletedClips`.
struct VlogProject: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let orientation: ProjectOrientation
    /// Active logical timeline, sorted by `sortOrder`; never contains a pending-deleted Clip.
    private(set) var clips: [VlogClip]
    /// Logically deleted Clips awaiting Undo or explicit physical cleanup, oldest deletion first.
    /// Their `sortOrder` is historical and not canonical; the deletion record's anchors are.
    private(set) var deletedClips: [VlogClip]

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        orientation: ProjectOrientation,
        clips: [VlogClip] = [],
        deletedClips: [VlogClip] = []
    ) throws {
        guard clips.allSatisfy({ $0.projectID == id }), deletedClips.allSatisfy({ $0.projectID == id }) else {
            throw DomainValidationError.clipProjectMismatch
        }

        guard clips.allSatisfy({ !$0.isPendingDeletion }), deletedClips.allSatisfy(\.isPendingDeletion) else {
            throw DomainValidationError.clipDeletionStateMismatch
        }

        let sortOrders = clips.map(\.sortOrder)
        guard Set(sortOrders).count == sortOrders.count else {
            throw DomainValidationError.duplicateClipSortOrder
        }

        let ids = clips.map(\.id) + deletedClips.map(\.id)
        guard Set(ids).count == ids.count else {
            throw DomainValidationError.clipDeletionStateMismatch
        }

        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.orientation = orientation
        self.clips = clips.sorted { $0.sortOrder < $1.sortOrder }
        self.deletedClips = deletedClips.sorted { ($0.deletion?.deletedAt ?? .distantPast) < ($1.deletion?.deletedAt ?? .distantPast) }
    }

    /// Every durable Clip (active + pending-deleted): the set the repository must keep.
    var durableClips: [VlogClip] { clips + deletedClips }

    /// Active timeline duration only; pending-deleted Clips never count.
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

    // MARK: - Append (ADR-037)

    /// Appends already-materialised Clips after the last active Clip, in the given order, with
    /// `sortOrder` renormalised 0…n-1. Pending-deleted Clips are untouched. All-or-nothing: any
    /// invalid Clip (foreign Project, duplicate identity, deletion state) rejects the whole batch.
    mutating func appendClips(_ newClips: [VlogClip], appendedAt: Date = .now) throws {
        guard !newClips.isEmpty else { return }
        guard newClips.allSatisfy({ $0.projectID == id }) else {
            throw DomainValidationError.clipProjectMismatch
        }
        guard newClips.allSatisfy({ !$0.isPendingDeletion }) else {
            throw DomainValidationError.clipDeletionStateMismatch
        }
        let known = Set(durableClips.map(\.id))
        let incoming = newClips.map(\.id)
        guard Set(incoming).count == incoming.count, incoming.allSatisfy({ !known.contains($0) }) else {
            throw DomainValidationError.clipDeletionStateMismatch
        }
        clips = try (clips + newClips).enumerated().map { try $1.assigningSortOrder($0) }
        updatedAt = appendedAt
    }

    // MARK: - Logical deletion (ADR-021)

    /// Logically deletes an active Clip: it leaves the timeline at once (remaining `sortOrder`
    /// renormalised 0…n-1) and joins `deletedClips` with its anchors recorded. Metadata and media
    /// are untouched.
    mutating func deleteClip(id clipID: UUID, deletedAt: Date = .now) throws {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else {
            throw DomainValidationError.clipNotFound
        }
        let record = try ClipDeletionRecord(
            deletedAt: deletedAt,
            originalIndex: index,
            previousClipID: index > 0 ? clips[index - 1].id : nil,
            nextClipID: index + 1 < clips.count ? clips[index + 1].id : nil
        )
        var remaining = clips
        let removed = remaining.remove(at: index)
        clips = try remaining.enumerated().map { try $1.assigningSortOrder($0) }
        deletedClips.append(try removed.assigning(sortOrder: removed.sortOrder, deletion: record))
        updatedAt = deletedAt
    }

    /// Undo: the SAME Clip (identity, media, metadata) returns to the active timeline at the
    /// anchor-resolved position — after its previous neighbour if that Clip is still active,
    /// else before its next neighbour if still active, else at the original index clamped to the
    /// current insertion range. Other Clips keep their current relative order.
    mutating func restoreDeletedClip(id clipID: UUID, restoredAt: Date = .now) throws {
        guard let deletedIndex = deletedClips.firstIndex(where: { $0.id == clipID }),
              let record = deletedClips[deletedIndex].deletion else {
            throw DomainValidationError.clipNotPendingDeletion
        }
        let insertionIndex = Self.restorationIndex(for: record, in: clips)
        let restored = deletedClips.remove(at: deletedIndex)
        var reinstated = clips
        reinstated.insert(try restored.assigning(sortOrder: 0, deletion: nil), at: insertionIndex)
        clips = try reinstated.enumerated().map { try $1.assigningSortOrder($0) }
        updatedAt = restoredAt
    }

    /// Pure anchor rule (tested directly): previous anchor first, then next anchor, then clamp.
    static func restorationIndex(for record: ClipDeletionRecord, in active: [VlogClip]) -> Int {
        if let previous = record.previousClipID, let index = active.firstIndex(where: { $0.id == previous }) {
            return index + 1
        }
        if let next = record.nextClipID, let index = active.firstIndex(where: { $0.id == next }) {
            return index
        }
        return min(max(record.originalIndex, 0), active.count)
    }

    /// Explicit physical-cleanup boundary (metadata side): forgets a pending-deleted Clip's record.
    /// Only `ProjectMediaCleanupCoordinator` calls this (ADR-039), after the media file is confirmed
    /// absent. Cleanup is maintenance, not a user edit: `updatedAt` is deliberately NOT touched, so
    /// Recent / saved-Project recency ordering never moves because of it.
    mutating func finalizeDeletedClip(id clipID: UUID) throws {
        guard let index = deletedClips.firstIndex(where: { $0.id == clipID }) else {
            throw DomainValidationError.clipNotPendingDeletion
        }
        deletedClips.remove(at: index)
    }
}
