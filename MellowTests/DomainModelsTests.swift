import XCTest
@testable import Mellow

final class DomainModelsTests: XCTestCase {
    func testFiveSecondClipIsAccepted() throws {
        let clip = try makeClip(duration: .seconds(5))

        XCTAssertEqual(clip.effectiveDuration, ClipPolicy.maximumDuration)
    }

    func testClipLongerThanFiveSecondsIsRejected() throws {
        let duration = try MediaTime(value: 3_001, timescale: 600)

        XCTAssertThrowsError(try makeClip(duration: duration)) { error in
            XCTAssertEqual(error as? DomainValidationError, .clipDurationExceedsMaximum)
        }
    }

    func testZeroDurationClipIsRejected() {
        XCTAssertThrowsError(try makeClip(duration: .zero)) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidClipDuration)
        }
    }

    func testNegativeDurationClipIsRejected() throws {
        let negativeDuration = try MediaTime(value: -1, timescale: 1)

        XCTAssertThrowsError(try makeClip(duration: negativeDuration)) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidClipDuration)
        }
    }

    func testPortraitOrientationIsRepresented() throws {
        let project = try VlogProject(orientation: .portrait9x16)

        XCTAssertEqual(project.orientation, .portrait9x16)
    }

    func testLandscapeOrientationIsRepresented() throws {
        let project = try VlogProject(orientation: .landscape16x9)

        XCTAssertEqual(project.orientation, .landscape16x9)
    }

    func testProjectDurationSumsEffectiveClipDurations() throws {
        let projectID = UUID()
        let project = try VlogProject(
            id: projectID,
            orientation: .portrait9x16,
            clips: [
                try makeClip(projectID: projectID, duration: .seconds(3), sortOrder: 0),
                try makeClip(projectID: projectID, duration: .seconds(5), sortOrder: 1)
            ]
        )

        XCTAssertEqual(project.totalDuration, .seconds(8))
    }

    func testReorderChangesLogicalClipOrderAndReindexesSortOrder() throws {
        let projectID = UUID()
        let first = try makeClip(id: UUID(), projectID: projectID, sortOrder: 0)
        let second = try makeClip(id: UUID(), projectID: projectID, sortOrder: 1)
        let third = try makeClip(id: UUID(), projectID: projectID, sortOrder: 2)
        var project = try VlogProject(
            id: projectID,
            orientation: .portrait9x16,
            clips: [first, second, third]
        )

        try project.reorderClip(id: third.id, toIndex: 0)

        XCTAssertEqual(project.clips.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1, 2])
    }

    func testReorderFirstClipToEndAndSameIndexKeepsIdentitiesAndTotal() throws {
        let projectID = UUID()
        let first = try makeClip(id: UUID(), projectID: projectID, duration: .seconds(2), sortOrder: 0)
        let second = try makeClip(id: UUID(), projectID: projectID, duration: .seconds(3), sortOrder: 1)
        let third = try makeClip(id: UUID(), projectID: projectID, duration: .seconds(1), sortOrder: 2)
        var project = try VlogProject(id: projectID, orientation: .portrait9x16, clips: [first, second, third])
        let total = project.totalDuration

        try project.reorderClip(id: first.id, toIndex: 2)
        XCTAssertEqual(project.clips.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(project.totalDuration, total)
        XCTAssertEqual(project.orientation, .portrait9x16)

        // Same index: order and sortOrder unchanged, no gaps or duplicates.
        try project.reorderClip(id: third.id, toIndex: 1)
        XCTAssertEqual(project.clips.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1, 2])

        XCTAssertThrowsError(try project.reorderClip(id: first.id, toIndex: 3))
        XCTAssertThrowsError(try project.reorderClip(id: UUID(), toIndex: 0))
        XCTAssertEqual(project.clips.map(\.id), [second.id, third.id, first.id], "a rejected reorder mutates nothing")
    }

    // MARK: - Logical delete / Undo anchors (Phase 5 STEP 10, ADR-021)

    private func makeFourClipProject() throws -> (VlogProject, [UUID]) {
        let projectID = UUID()
        let clips = try (0..<4).map { try makeClip(id: UUID(), projectID: projectID, duration: .seconds(Int64($0 + 1)), sortOrder: $0) }
        return (try VlogProject(id: projectID, orientation: .portrait9x16, clips: clips), clips.map(\.id))
    }

    func testDeleteClipMovesItToDurableDeletedSetWithAnchorsAndRenormalisesActiveOrder() throws {
        var (project, ids) = try makeFourClipProject()
        let (a, b, c, d) = (ids[0], ids[1], ids[2], ids[3])
        let originalB = project.clips[1]
        let deletedAt = Date(timeIntervalSince1970: 1_000)

        try project.deleteClip(id: b, deletedAt: deletedAt)

        XCTAssertEqual(project.clips.map(\.id), [a, c, d])
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(project.deletedClips.map(\.id), [b])
        let record = try XCTUnwrap(project.deletedClips[0].deletion)
        XCTAssertEqual(record.deletedAt, deletedAt)
        XCTAssertEqual(record.originalIndex, 1)
        XCTAssertEqual(record.previousClipID, a)
        XCTAssertEqual(record.nextClipID, c)
        XCTAssertEqual(project.totalDuration, .seconds(1 + 3 + 4))
        XCTAssertEqual(project.durableClips.count, 4, "metadata is retained")
        XCTAssertEqual(project.updatedAt, deletedAt)
        // Same identity / media / metadata on the deleted record.
        let deleted = project.deletedClips[0]
        XCTAssertEqual(deleted.id, originalB.id)
        XCTAssertEqual(deleted.mediaRelativePath, originalB.mediaRelativePath)
        XCTAssertEqual(deleted.trimStart, originalB.trimStart)
        XCTAssertEqual(deleted.trimDuration, originalB.trimDuration)
        XCTAssertEqual(deleted.sourceDuration, originalB.sourceDuration)
        XCTAssertEqual(deleted.framing, originalB.framing)
        XCTAssertEqual(deleted.sourceKind, originalB.sourceKind)
        XCTAssertEqual(deleted.createdAt, originalB.createdAt)

        XCTAssertThrowsError(try project.deleteClip(id: b)) { XCTAssertEqual($0 as? DomainValidationError, .clipNotFound) }
        XCTAssertThrowsError(try project.reorderClip(id: b, toIndex: 0), "a pending-deleted clip cannot be reordered")
    }

    func testDeleteFirstAndLastClipsRecordBoundaryAnchors() throws {
        var (project, ids) = try makeFourClipProject()
        try project.deleteClip(id: ids[0])
        XCTAssertNil(project.deletedClips[0].deletion?.previousClipID)
        XCTAssertEqual(project.deletedClips[0].deletion?.nextClipID, ids[1])
        try project.deleteClip(id: ids[3])
        XCTAssertEqual(project.deletedClips[1].deletion?.previousClipID, ids[2])
        XCTAssertNil(project.deletedClips[1].deletion?.nextClipID)
        XCTAssertEqual(project.clips.map(\.id), [ids[1], ids[2]])
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1])
    }

    func testUndoRestoresSameClipAtOriginalPlaceWhenNothingElseChanged() throws {
        var (project, ids) = try makeFourClipProject()
        let before = project.clips
        try project.deleteClip(id: ids[1])
        try project.restoreDeletedClip(id: ids[1])
        XCTAssertEqual(project.clips.map(\.id), ids)
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertTrue(project.deletedClips.isEmpty)
        XCTAssertEqual(project.clips[1], before[1], "same clip, same metadata, no deletion state")
        XCTAssertEqual(project.totalDuration, .seconds(10))
    }

    func testUndoAfterUnrelatedReorderRestoresAfterPreviousAnchor() throws {
        var (project, ids) = try makeFourClipProject()
        let (a, b, c, d) = (ids[0], ids[1], ids[2], ids[3])
        try project.deleteClip(id: b)                 // A C D
        try project.reorderClip(id: d, toIndex: 0)    // D A C
        try project.restoreDeletedClip(id: b)
        XCTAssertEqual(project.clips.map(\.id), [d, a, b, c], "restored after A, D's reorder preserved")
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1, 2, 3])
    }

    func testUndoUsesNextAnchorWhenPreviousIsGone() throws {
        var (project, ids) = try makeFourClipProject()
        let (a, b, c, d) = (ids[0], ids[1], ids[2], ids[3])
        try project.deleteClip(id: b)                 // A C D  (prev A, next C)
        try project.deleteClip(id: a)                 // C D
        try project.reorderClip(id: d, toIndex: 0)    // D C
        try project.restoreDeletedClip(id: b)
        XCTAssertEqual(project.clips.map(\.id), [d, b, c], "before C")
    }

    func testUndoClampsOriginalIndexWhenBothAnchorsAreGone() throws {
        var (project, ids) = try makeFourClipProject()
        let (a, b, c, d) = (ids[0], ids[1], ids[2], ids[3])
        try project.deleteClip(id: b)   // A C D (orig 1)
        try project.deleteClip(id: a)   // C D
        try project.deleteClip(id: c)   // D
        try project.restoreDeletedClip(id: b)
        XCTAssertEqual(project.clips.map(\.id), [d, b], "original index 1 within 0...1")

        // Both anchors gone and the timeline shorter than the original index → appended.
        var (other, otherIDs) = try makeFourClipProject()
        try other.deleteClip(id: otherIDs[3])   // orig 3, prev C
        try other.deleteClip(id: otherIDs[2])
        try other.deleteClip(id: otherIDs[1])
        try other.deleteClip(id: otherIDs[0])   // empty
        try other.restoreDeletedClip(id: otherIDs[3])
        XCTAssertEqual(other.clips.map(\.id), [otherIDs[3]])
        XCTAssertEqual(other.deletedClips.count, 3, "the others stay pending-deleted")
    }

    func testRestorationIndexRulePrefersPreviousAnchor() throws {
        let (project, ids) = try makeFourClipProject()
        let record = try ClipDeletionRecord(deletedAt: .now, originalIndex: 0, previousClipID: ids[2], nextClipID: ids[0])
        XCTAssertEqual(VlogProject.restorationIndex(for: record, in: project.clips), 3, "previous wins even when next is also present")
        let onlyNext = try ClipDeletionRecord(deletedAt: .now, originalIndex: 9, previousClipID: UUID(), nextClipID: ids[1])
        XCTAssertEqual(VlogProject.restorationIndex(for: onlyNext, in: project.clips), 1)
        let none = try ClipDeletionRecord(deletedAt: .now, originalIndex: 9, previousClipID: nil, nextClipID: nil)
        XCTAssertEqual(VlogProject.restorationIndex(for: none, in: project.clips), 4)
    }

    func testDeletingEveryClipLeavesValidEmptyProject() throws {
        var (project, ids) = try makeFourClipProject()
        for id in ids { try project.deleteClip(id: id) }
        XCTAssertTrue(project.clips.isEmpty)
        XCTAssertEqual(project.totalDuration, .zero)
        XCTAssertEqual(project.deletedClips.map(\.id), ids, "oldest deletion first")
        XCTAssertEqual(project.durableClips.count, 4)
        XCTAssertEqual(project.orientation, .portrait9x16)
    }

    func testFinalizeRemovesOnlyPendingDeletedClipRecord() throws {
        var (project, ids) = try makeFourClipProject()
        XCTAssertThrowsError(try project.finalizeDeletedClip(id: ids[0])) { XCTAssertEqual($0 as? DomainValidationError, .clipNotPendingDeletion) }
        try project.deleteClip(id: ids[0])
        try project.finalizeDeletedClip(id: ids[0])
        XCTAssertTrue(project.deletedClips.isEmpty)
        XCTAssertEqual(project.clips.map(\.id), Array(ids[1...]))
        XCTAssertThrowsError(try project.restoreDeletedClip(id: ids[0]), "a finalized clip can no longer be restored")
    }

    func testProjectRejectsMixedDeletionStateAndDuplicateIdentity() throws {
        let projectID = UUID()
        let active = try makeClip(id: UUID(), projectID: projectID, sortOrder: 0)
        let record = try ClipDeletionRecord(deletedAt: .now, originalIndex: 0, previousClipID: nil, nextClipID: nil)
        let deleted = try active.assigning(sortOrder: 0, deletion: record)
        XCTAssertThrowsError(try VlogProject(id: projectID, orientation: .portrait9x16, clips: [deleted])) {
            XCTAssertEqual($0 as? DomainValidationError, .clipDeletionStateMismatch)
        }
        XCTAssertThrowsError(try VlogProject(id: projectID, orientation: .portrait9x16, deletedClips: [active])) {
            XCTAssertEqual($0 as? DomainValidationError, .clipDeletionStateMismatch)
        }
        XCTAssertThrowsError(try VlogProject(id: projectID, orientation: .portrait9x16, clips: [active], deletedClips: [deleted])) {
            XCTAssertEqual($0 as? DomainValidationError, .clipDeletionStateMismatch)
        }
        XCTAssertThrowsError(try ClipDeletionRecord(deletedAt: .now, originalIndex: -1, previousClipID: nil, nextClipID: nil))
    }

    // MARK: - Append (Phase 5 STEP 11, ADR-037)

    func testAppendClipsAddsAfterLastActiveInOrderAndLeavesPendingUntouched() throws {
        var (project, ids) = try makeFourClipProject()
        try project.deleteClip(id: ids[3])                                          // A B C, D pending
        let x = try makeClip(id: UUID(), projectID: project.id, duration: .seconds(1), sortOrder: 99)
        let y = try makeClip(id: UUID(), projectID: project.id, duration: .seconds(2), sortOrder: 0)
        let stamp = Date(timeIntervalSince1970: 9_000)

        try project.appendClips([x, y], appendedAt: stamp)

        XCTAssertEqual(project.clips.map(\.id), [ids[0], ids[1], ids[2], x.id, y.id])
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1, 2, 3, 4], "renormalised regardless of incoming sortOrder")
        XCTAssertEqual(project.deletedClips.map(\.id), [ids[3]], "pending-deleted clips untouched")
        XCTAssertEqual(project.totalDuration, .seconds(1 + 2 + 3 + 1 + 2))
        XCTAssertEqual(project.updatedAt, stamp)
        XCTAssertEqual(project.clips[3].mediaRelativePath, x.mediaRelativePath)

        // All-or-nothing validation.
        let foreign = try makeClip(id: UUID(), projectID: UUID(), sortOrder: 0)
        XCTAssertThrowsError(try project.appendClips([foreign])) { XCTAssertEqual($0 as? DomainValidationError, .clipProjectMismatch) }
        XCTAssertThrowsError(try project.appendClips([x]), "duplicate identity") { XCTAssertEqual($0 as? DomainValidationError, .clipDeletionStateMismatch) }
        XCTAssertThrowsError(try project.appendClips([ids[3]].compactMap { id in project.deletedClips.first { $0.id == id } }), "already durable") { XCTAssertEqual($0 as? DomainValidationError, .clipDeletionStateMismatch) }
        XCTAssertEqual(project.clips.count, 5, "rejected batches mutate nothing")
        try project.appendClips([])
        XCTAssertEqual(project.updatedAt, stamp, "empty batch is a no-op")
    }

    // MARK: - Replace (Phase 5 STEP 13, ADR-040)

    /// A replacement Clip as the append coordinator would produce it: new identity, `.imported`,
    /// trim reset to the whole source, no framing, canonical committed path for THIS Project.
    private func makeReplacement(projectID: UUID, seconds: Int64) throws -> VlogClip {
        let id = UUID()
        return try VlogClip(
            id: id, projectID: projectID, sourceKind: .imported,
            mediaRelativePath: try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: id),
            sourceDuration: .seconds(seconds), trimStart: .zero, trimDuration: .seconds(seconds), framing: nil, sortOrder: 42
        )
    }

    func testReplaceClipPutsNewIdentityInExactSlotAndMakesOldClipPending() throws {
        var (project, ids) = try makeFourClipProject()                                // A B C D (1 2 3 4 s)
        try project.deleteClip(id: ids[3])                                            // A B C, D pending
        let before = project
        let d = try makeReplacement(projectID: project.id, seconds: 5)
        let stamp = Date(timeIntervalSince1970: 9_500)

        try project.replaceClip(id: ids[1], with: d, replacedAt: stamp)               // A D C

        XCTAssertEqual(project.clips.map(\.id), [ids[0], d.id, ids[2]], "D occupies B's exact logical index")
        XCTAssertNotEqual(d.id, ids[1], "Model B: a NEW identity")
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1, 2], "sortOrder renormalised")
        XCTAssertEqual(project.clips[0], before.clips[0], "other active clips untouched")
        XCTAssertEqual(project.clips[2].id, before.clips[2].id)
        let replaced = project.clips[1]
        XCTAssertEqual(replaced.projectID, project.id)
        XCTAssertEqual(replaced.sourceKind, .imported)
        XCTAssertEqual(replaced.trimStart, .zero)
        XCTAssertEqual(replaced.trimDuration, replaced.sourceDuration)
        XCTAssertNil(replaced.framing)
        XCTAssertNil(replaced.deletion)
        XCTAssertEqual(project.deletedClips.map(\.id), [ids[3], ids[1]], "pre-existing pending preserved; B pending after it")
        let b = try XCTUnwrap(project.deletedClips.last)
        XCTAssertTrue(b.isPendingDeletion)
        XCTAssertEqual(b.mediaRelativePath, before.clips[1].mediaRelativePath, "B's metadata and media reference intact")
        XCTAssertEqual(b.trimDuration, .seconds(2))
        XCTAssertEqual(b.deletion?.originalIndex, 1)
        XCTAssertEqual(b.deletion?.previousClipID, ids[0]); XCTAssertEqual(b.deletion?.nextClipID, ids[2])
        XCTAssertEqual(b.deletion?.deletedAt, stamp)
        XCTAssertEqual(project.totalDuration, .seconds(1 + 5 + 3), "Total uses D's duration")
        XCTAssertEqual(project.updatedAt, stamp)
        XCTAssertEqual(project.durableClips.count, 5)
        // The durable set is a valid Project value again (round-trips the initialiser).
        XCTAssertNoThrow(try VlogProject(id: project.id, orientation: .portrait9x16, clips: project.clips, deletedClips: project.deletedClips))
    }

    func testReplaceFirstAndLastClipsKeepBoundaries() throws {
        var (project, ids) = try makeFourClipProject()
        let first = try makeReplacement(projectID: project.id, seconds: 1)
        try project.replaceClip(id: ids[0], with: first)
        XCTAssertEqual(project.clips.map(\.id), [first.id, ids[1], ids[2], ids[3]])
        let last = try makeReplacement(projectID: project.id, seconds: 2)
        try project.replaceClip(id: ids[3], with: last)
        XCTAssertEqual(project.clips.map(\.id), [first.id, ids[1], ids[2], last.id])
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertEqual(project.deletedClips.map(\.id), [ids[0], ids[3]])
        // A single-clip Project stays valid through Replace.
        var single = try VlogProject(id: UUID(), orientation: .portrait9x16, clips: [])
        let only = try makeClip(id: UUID(), projectID: single.id, sortOrder: 0)
        try single.appendClips([only])
        let onlyReplacement = try makeReplacement(projectID: single.id, seconds: 3)
        try single.replaceClip(id: only.id, with: onlyReplacement)
        XCTAssertEqual(single.clips.map(\.id), [onlyReplacement.id]); XCTAssertEqual(single.deletedClips.map(\.id), [only.id])
    }

    func testReplaceClipRejectsInvalidTargetsWithoutMutating() throws {
        var (project, ids) = try makeFourClipProject()
        try project.deleteClip(id: ids[3])
        let before = project
        let ok = try makeReplacement(projectID: project.id, seconds: 2)

        XCTAssertThrowsError(try project.replaceClip(id: UUID(), with: ok), "unknown old id") { XCTAssertEqual($0 as? DomainValidationError, .clipNotFound) }
        XCTAssertThrowsError(try project.replaceClip(id: ids[3], with: ok), "pending old id is not active") { XCTAssertEqual($0 as? DomainValidationError, .clipNotFound) }
        let foreign = try makeReplacement(projectID: UUID(), seconds: 2)
        XCTAssertThrowsError(try project.replaceClip(id: ids[1], with: foreign), "wrong Project") { XCTAssertEqual($0 as? DomainValidationError, .clipProjectMismatch) }
        let collidingActive = try makeClip(id: ids[2], projectID: project.id, sortOrder: 0)
        XCTAssertThrowsError(try project.replaceClip(id: ids[1], with: collidingActive), "identity collision with an active clip") { XCTAssertEqual($0 as? DomainValidationError, .clipDeletionStateMismatch) }
        let collidingPending = try makeClip(id: ids[3], projectID: project.id, sortOrder: 0)
        XCTAssertThrowsError(try project.replaceClip(id: ids[1], with: collidingPending), "identity collision with a pending clip") { XCTAssertEqual($0 as? DomainValidationError, .clipDeletionStateMismatch) }
        let sameAsOld = try makeClip(id: ids[1], projectID: project.id, sortOrder: 0)
        XCTAssertThrowsError(try project.replaceClip(id: ids[1], with: sameAsOld), "the old identity is never reused") { XCTAssertEqual($0 as? DomainValidationError, .clipDeletionStateMismatch) }
        let alreadyPending = try ok.assigning(sortOrder: 0, deletion: ClipDeletionRecord(deletedAt: .now, originalIndex: 0, previousClipID: nil, nextClipID: nil))
        XCTAssertThrowsError(try project.replaceClip(id: ids[1], with: alreadyPending), "replacement must be active") { XCTAssertEqual($0 as? DomainValidationError, .clipDeletionStateMismatch) }

        XCTAssertEqual(project, before, "every rejection leaves the Project untouched")
    }

    func testDisplayNameUsesCreatedAtWithLocaleAwareFormatting() throws {
        let createdAt = Date(timeIntervalSince1970: 1_704_164_240)
        let laterDate = createdAt.addingTimeInterval(60 * 60)
        let locale = Locale(identifier: "en_US")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let project = try VlogProject(
            createdAt: createdAt,
            orientation: .portrait9x16
        )

        let displayName = project.displayName(locale: locale, timeZone: timeZone)

        XCTAssertEqual(
            displayName,
            ProjectDisplayNameFormatter.displayName(
                for: createdAt,
                locale: locale,
                timeZone: timeZone
            )
        )
        XCTAssertNotEqual(
            displayName,
            ProjectDisplayNameFormatter.displayName(
                for: laterDate,
                locale: locale,
                timeZone: timeZone
            )
        )
    }

    func testAbsoluteMediaPathIsRejected() {
        XCTAssertThrowsError(try RelativeMediaPath("/private/clip.mov")) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidMediaRelativePath)
        }
    }

    private func makeClip(
        id: UUID = UUID(),
        projectID: UUID = UUID(),
        duration: MediaTime = .seconds(5),
        sortOrder: Int = 0
    ) throws -> VlogClip {
        try VlogClip(
            id: id,
            projectID: projectID,
            sourceKind: .recorded,
            mediaRelativePath: try RelativeMediaPath("projects/clip-\(id.uuidString).mov"),
            sourceDuration: duration,
            trimDuration: duration,
            sortOrder: sortOrder
        )
    }
}
