import XCTest
@testable import Mellow

/// ADR-050 050-D accepted classification rules: completed / committed-unverified / prior-confirmed /
/// indeterminate. Pure inputs only — no store, no files.
final class ProjectSaveOutcomeTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func clip(_ projectID: UUID, _ index: Int, trimSeconds: Int64 = 3) throws -> VlogClip {
        let id = UUID()
        return try VlogClip(id: id, projectID: projectID, sourceKind: .imported,
                            mediaRelativePath: RelativeMediaPath("Projects/\(projectID.uuidString)/Media/\(id.uuidString).mov"),
                            createdAt: base, sourceDuration: .seconds(5), trimDuration: .seconds(trimSeconds), sortOrder: index)
    }

    /// `active` active Clips, then `pending` of them logically deleted.
    private func project(active: Int, pending: Int = 0, updatedAt: Date? = nil) throws -> VlogProject {
        let id = UUID()
        var p = try VlogProject(id: id, createdAt: base, updatedAt: updatedAt ?? base, orientation: .portrait9x16,
                                clips: (0..<(active + pending)).map { try clip(id, $0) })
        for i in 0..<pending { try p.deleteClip(id: p.clips[p.clips.count - 1].id, deletedAt: base.addingTimeInterval(Double(i + 1))) }
        return p
    }

    private func classify(_ attempt: ProjectSaveAttempt, _ expectation: ProjectSaveExpectation,
                          _ projects: [UUID: ObservedProjectRecord], holders: [UUID: Set<UUID>]?) -> ProjectSaveOutcome {
        ProjectSaveOutcomeClassifier.classify(attempt, expectation: expectation,
                                              observation: PersistedStateObservation(projects: projects, createdIdentityHolders: holders))
    }

    private func absentHolders(_ expectation: ProjectSaveExpectation) -> [UUID: Set<UUID>] {
        Dictionary(uniqueKeysWithValues: expectation.createdProjectIDs.union(expectation.createdClipOwners.keys).map { ($0, Set<UUID>()) })
    }

    private func intendedHolders(_ expectation: ProjectSaveExpectation) -> [UUID: Set<UUID>] {
        var holders: [UUID: Set<UUID>] = [:]
        for id in expectation.createdProjectIDs { holders[id] = [id] }
        for (clipID, owner) in expectation.createdClipOwners { holders[clipID] = [owner] }
        return holders
    }

    // MARK: Decision table — create

    func testCreateDecisionTable() throws {
        let b = try project(active: 3)
        let e = ProjectSaveExpectation.create(b)
        // Save succeeded + intended confirmed.
        XCTAssertEqual(classify(.succeeded, e, [b.id: .present(b)], holders: intendedHolders(e)), .completed)
        XCTAssertEqual(classify(.succeeded, e, [b.id: .present(b)], holders: nil), .completed)
        // Save succeeded + unavailable / contradictory verification.
        XCTAssertEqual(classify(.succeeded, e, [b.id: .unreadable], holders: nil), .committedUnverified(.unreadable))
        XCTAssertEqual(classify(.succeeded, e, [:], holders: nil), .committedUnverified(.notObserved))
        // Save threw + intended confirmed.
        XCTAssertEqual(classify(.threw, e, [b.id: .present(b)], holders: intendedHolders(e)), .completed)
        // Save threw + prior confirmed with store-wide absence of every created identity.
        XCTAssertEqual(classify(.threw, e, [b.id: .absent], holders: absentHolders(e)), .priorConfirmed)
        // Save threw + anything else.
        XCTAssertEqual(classify(.threw, e, [b.id: .unreadable], holders: absentHolders(e)), .indeterminate(.unreadable))
        XCTAssertEqual(classify(.threw, e, [:], holders: absentHolders(e)), .indeterminate(.notObserved))
    }

    func testSaveSuccessFollowedByApparentPriorStateNeverAuthorizesRollback() throws {
        let b = try project(active: 2)
        let e = ProjectSaveExpectation.create(b)
        XCTAssertEqual(classify(.succeeded, e, [b.id: .absent], holders: absentHolders(e)), .committedUnverified(.contradictory))
        let a = try project(active: 2)
        let r = try ProjectSaveExpectation.replace(a, with: b)
        XCTAssertEqual(classify(.succeeded, r, [a.id: .present(a), b.id: .absent], holders: absentHolders(r)), .committedUnverified(.contradictory))
    }

    func testVerifiedAbsentIsNotAFailedRead() throws {
        let b = try project(active: 1)
        let e = ProjectSaveExpectation.create(b)
        XCTAssertEqual(classify(.threw, e, [b.id: .absent], holders: absentHolders(e)), .priorConfirmed)
        XCTAssertEqual(classify(.threw, e, [b.id: .unreadable], holders: absentHolders(e)), .indeterminate(.unreadable))
    }

    // MARK: Identity evidence

    func testPriorWithoutCompleteIdentityEvidenceIsIndeterminate() throws {
        let b = try project(active: 3)
        let e = ProjectSaveExpectation.create(b)
        XCTAssertEqual(classify(.threw, e, [b.id: .absent], holders: nil), .indeterminate(.identityEvidenceMissing))
        var partial = absentHolders(e)
        partial.removeValue(forKey: b.clips[2].id)
        XCTAssertEqual(classify(.threw, e, [b.id: .absent], holders: partial), .indeterminate(.identityEvidenceMissing))
    }

    func testCreatedIdentityHeldByAnotherProjectBlocksRollbackAndCompletion() throws {
        let b = try project(active: 2)
        let other = UUID()
        let e = ProjectSaveExpectation.create(b)
        var holders = absentHolders(e)
        holders[b.clips[1].id] = [other]
        // Target Project absent, but one created Clip ID exists in another Project.
        XCTAssertEqual(classify(.threw, e, [b.id: .absent], holders: holders), .indeterminate(.createdIdentityPresent))
        // Intended values match, but store-wide evidence also places a created Clip with another Project.
        var intended = intendedHolders(e)
        intended[b.clips[0].id] = [b.id, other]
        XCTAssertEqual(classify(.threw, e, [b.id: .present(b)], holders: intended), .indeterminate(.contradictory))
        XCTAssertEqual(classify(.succeeded, e, [b.id: .present(b)], holders: intended), .committedUnverified(.contradictory))
    }

    // MARK: Single-save replacement

    func testReplacementDecisionTable() throws {
        let a = try project(active: 3, pending: 1)
        let b = try project(active: 2, updatedAt: base.addingTimeInterval(60))
        let e = try ProjectSaveExpectation.replace(a, with: b)
        XCTAssertEqual(classify(.succeeded, e, [a.id: .absent, b.id: .present(b)], holders: intendedHolders(e)), .completed)
        // After a throw, completion needs complete created-identity evidence.
        XCTAssertEqual(classify(.threw, e, [a.id: .absent, b.id: .present(b)], holders: intendedHolders(e)), .completed)
        XCTAssertEqual(classify(.threw, e, [a.id: .absent, b.id: .present(b)], holders: nil), .indeterminate(.identityEvidenceMissing))
        XCTAssertEqual(classify(.threw, e, [a.id: .present(a), b.id: .absent], holders: absentHolders(e)), .priorConfirmed)
        // Both present, or neither present: partial.
        XCTAssertEqual(classify(.threw, e, [a.id: .present(a), b.id: .present(b)], holders: intendedHolders(e)), .indeterminate(.partial))
        XCTAssertEqual(classify(.threw, e, [a.id: .absent, b.id: .absent], holders: absentHolders(e)), .indeterminate(.partial))
        XCTAssertEqual(classify(.succeeded, e, [a.id: .absent, b.id: .absent], holders: absentHolders(e)), .committedUnverified(.partial))
        // One side unreadable.
        XCTAssertEqual(classify(.threw, e, [a.id: .present(a), b.id: .unreadable], holders: absentHolders(e)), .indeterminate(.unreadable))
    }

    // MARK: Add / Replace (update)

    func testUpdateFieldAndOrderChangesAreContradictory() throws {
        let before = try project(active: 2)
        var after = before
        let added = try clip(before.id, 2)
        try after.appendClips([added], appendedAt: base.addingTimeInterval(1))
        let e = try ProjectSaveExpectation.update(from: before, to: after)
        XCTAssertEqual(e.createdClipOwners, [added.id: before.id])
        XCTAssertEqual(classify(.threw, e, [before.id: .present(after)], holders: intendedHolders(e)), .completed)
        XCTAssertEqual(classify(.threw, e, [before.id: .present(before)], holders: absentHolders(e)), .priorConfirmed)

        // One field differs (trim) on the added Clip.
        let altered = try VlogClip(id: added.id, projectID: before.id, sourceKind: .imported, mediaRelativePath: added.mediaRelativePath,
                                   createdAt: added.createdAt, sourceDuration: added.sourceDuration, trimDuration: .seconds(2), sortOrder: added.sortOrder)
        let fieldChanged = try VlogProject(id: before.id, createdAt: after.createdAt, updatedAt: after.updatedAt, orientation: after.orientation,
                                           clips: Array(after.clips.dropLast()) + [altered])
        XCTAssertEqual(classify(.threw, e, [before.id: .present(fieldChanged)], holders: intendedHolders(e)), .indeterminate(.contradictory))
        XCTAssertEqual(classify(.succeeded, e, [before.id: .present(fieldChanged)], holders: intendedHolders(e)), .committedUnverified(.contradictory))

        // Same Clips, different active order.
        var reordered = after
        try reordered.reorderClip(id: after.clips[2].id, toIndex: 0, updatedAt: after.updatedAt)
        XCTAssertEqual(classify(.threw, e, [before.id: .present(reordered)], holders: intendedHolders(e)), .indeterminate(.contradictory))

        // Partial metadata: the added Clip is missing although the timestamp moved.
        let partialMetadata = try VlogProject(id: before.id, createdAt: after.createdAt, updatedAt: after.updatedAt, orientation: after.orientation, clips: before.clips)
        XCTAssertEqual(classify(.threw, e, [before.id: .present(partialMetadata)], holders: absentHolders(e)), .indeterminate(.contradictory))
    }

    func testPendingDeletedRecordsCompareBySemanticsNotOrder() throws {
        // Two pending-deleted Clips with the same deletedAt: fetch order may differ between reads.
        let id = UUID()
        var source = try VlogProject(id: id, createdAt: base, updatedAt: base, orientation: .portrait9x16, clips: (0..<4).map { try clip(id, $0) })
        try source.deleteClip(id: source.clips[3].id, deletedAt: base.addingTimeInterval(5))
        try source.deleteClip(id: source.clips[2].id, deletedAt: base.addingTimeInterval(5))
        let reversed = try VlogProject(id: id, createdAt: base, updatedAt: source.updatedAt, orientation: .portrait9x16,
                                       clips: source.clips, deletedClips: source.deletedClips.reversed())
        XCTAssertNotEqual(source.deletedClips.map(\.id), reversed.deletedClips.map(\.id), "arbitrary order differs")
        XCTAssertEqual(ProjectStateSnapshot(source), ProjectStateSnapshot(reversed))

        let e = ProjectSaveExpectation.create(source)
        XCTAssertEqual(classify(.threw, e, [id: .present(reversed)], holders: intendedHolders(e)), .completed)

        // A changed deletion record is a real difference.
        let pending = source.deletedClips[0]
        let changedRecord = try pending.assigning(sortOrder: pending.sortOrder, deletion: ClipDeletionRecord(
            deletedAt: base.addingTimeInterval(99), originalIndex: pending.deletion!.originalIndex,
            previousClipID: pending.deletion!.previousClipID, nextClipID: pending.deletion!.nextClipID))
        let changed = try VlogProject(id: id, createdAt: base, updatedAt: source.updatedAt, orientation: .portrait9x16,
                                      clips: source.clips, deletedClips: [changedRecord, source.deletedClips[1]])
        XCTAssertEqual(classify(.threw, e, [id: .present(changed)], holders: intendedHolders(e)), .indeterminate(.contradictory))
    }

    func testIndistinguishableSnapshotsAreInconclusiveAfterAThrow() throws {
        let p = try project(active: 2)
        let e = try ProjectSaveExpectation.update(from: p, to: p)
        XCTAssertTrue(e.isIndistinguishable)
        XCTAssertEqual(classify(.threw, e, [p.id: .present(p)], holders: absentHolders(e)), .indeterminate(.indistinguishable))
        // A reported success with the (identical) intended state is still completed.
        XCTAssertEqual(classify(.succeeded, e, [p.id: .present(p)], holders: nil), .completed)
    }

    // MARK: Review follow-ups (F1–F4)

    func testEditorReplaceExpressedAsUpdate() throws {
        let before = try project(active: 3)
        var after = before
        let replacement = try clip(before.id, 0)
        try after.replaceClip(id: before.clips[1].id, with: replacement, replacedAt: base.addingTimeInterval(1))
        let e = try ProjectSaveExpectation.update(from: before, to: after)
        XCTAssertEqual(e.createdClipOwners, [replacement.id: before.id])
        XCTAssertEqual(classify(.threw, e, [before.id: .present(after)], holders: intendedHolders(e)), .completed)
        XCTAssertEqual(classify(.threw, e, [before.id: .present(before)], holders: absentHolders(e)), .priorConfirmed)
        XCTAssertEqual(classify(.threw, e, [before.id: .present(before)], holders: nil), .indeterminate(.identityEvidenceMissing))
        XCTAssertEqual(classify(.succeeded, e, [before.id: .present(before)], holders: absentHolders(e)), .committedUnverified(.contradictory))
    }

    func testPartiallyObservedReplacementIsInconclusive() throws {
        let a = try project(active: 2)
        let b = try project(active: 2, updatedAt: base.addingTimeInterval(60))
        let e = try ProjectSaveExpectation.replace(a, with: b)
        XCTAssertEqual(classify(.threw, e, [a.id: .present(a)], holders: absentHolders(e)), .indeterminate(.notObserved))
        XCTAssertEqual(classify(.threw, e, [b.id: .present(b)], holders: intendedHolders(e)), .indeterminate(.notObserved))
        XCTAssertEqual(classify(.succeeded, e, [b.id: .present(b)], holders: intendedHolders(e)), .committedUnverified(.notObserved))
    }

    func testSaveSuccessWithIncompleteOrContradictoryEvidence() throws {
        let b = try project(active: 3)
        let e = ProjectSaveExpectation.create(b)
        var incomplete = intendedHolders(e)
        incomplete.removeValue(forKey: b.clips[0].id)
        XCTAssertEqual(classify(.succeeded, e, [b.id: .present(b)], holders: incomplete), .completed)
        XCTAssertEqual(classify(.succeeded, e, [b.id: .present(b)], holders: nil), .completed)
        var contradictory = intendedHolders(e)
        contradictory[b.id] = []
        XCTAssertEqual(classify(.succeeded, e, [b.id: .present(b)], holders: contradictory), .committedUnverified(.contradictory))
    }

    func testThrownSaveNeedsCompleteConsistentCreatedIdentityEvidenceToComplete() throws {
        let b = try project(active: 3)
        let e = ProjectSaveExpectation.create(b)
        XCTAssertEqual(classify(.threw, e, [b.id: .present(b)], holders: nil), .indeterminate(.identityEvidenceMissing))
        var partial = intendedHolders(e)
        partial.removeValue(forKey: b.clips[2].id)
        XCTAssertEqual(classify(.threw, e, [b.id: .present(b)], holders: partial), .indeterminate(.identityEvidenceMissing))
        var foreignClip = intendedHolders(e)
        foreignClip[b.clips[1].id] = [UUID()]
        XCTAssertEqual(classify(.threw, e, [b.id: .present(b)], holders: foreignClip), .indeterminate(.contradictory))
        var projectNotHeld = intendedHolders(e)
        projectNotHeld[b.id] = []
        XCTAssertEqual(classify(.threw, e, [b.id: .present(b)], holders: projectNotHeld), .indeterminate(.contradictory))
        XCTAssertEqual(classify(.threw, e, [b.id: .present(b)], holders: intendedHolders(e)), .completed)
    }

    /// A missing key must never hide a contradicting or present one, whatever the dictionary order.
    func testContradictionOrPresenceWinsOverMissingEvidenceRegardlessOfOrder() throws {
        let b = try project(active: 6)
        let e = ProjectSaveExpectation.create(b)
        for missingIndex in 0..<b.clips.count {
            for otherIndex in 0..<b.clips.count where otherIndex != missingIndex {
                var mixed = intendedHolders(e)
                mixed.removeValue(forKey: b.clips[missingIndex].id)
                mixed[b.clips[otherIndex].id] = [UUID()]
                XCTAssertEqual(classify(.succeeded, e, [b.id: .present(b)], holders: mixed), .committedUnverified(.contradictory))
                XCTAssertEqual(classify(.threw, e, [b.id: .present(b)], holders: mixed), .indeterminate(.contradictory))

                var priorMixed = absentHolders(e)
                priorMixed.removeValue(forKey: b.clips[missingIndex].id)
                priorMixed[b.clips[otherIndex].id] = [UUID()]
                XCTAssertEqual(classify(.threw, e, [b.id: .absent], holders: priorMixed), .indeterminate(.createdIdentityPresent))
            }
        }
    }

    func testUpdateCreatingNoIdentitiesIsVacuouslySatisfied() throws {
        let before = try project(active: 3)
        var after = before
        try after.reorderClip(id: before.clips[2].id, toIndex: 0, updatedAt: base.addingTimeInterval(1))
        let e = try ProjectSaveExpectation.update(from: before, to: after)
        XCTAssertTrue(e.createdProjectIDs.isEmpty && e.createdClipOwners.isEmpty)
        XCTAssertEqual(classify(.threw, e, [before.id: .present(after)], holders: nil), .completed)
        XCTAssertEqual(classify(.threw, e, [before.id: .present(before)], holders: nil), .priorConfirmed)
        // The full intended-state comparison is still required.
        XCTAssertEqual(classify(.threw, e, [before.id: .unreadable], holders: nil), .indeterminate(.unreadable))
    }

    func testFactoriesRejectInvalidIdentityContractsWithoutTrapping() throws {
        let a = try project(active: 2)
        let other = try project(active: 2)
        XCTAssertThrowsError(try ProjectSaveExpectation.update(from: a, to: other)) { XCTAssertEqual($0 as? ProjectSaveExpectationError, .mismatchedProjectIDs) }
        XCTAssertThrowsError(try ProjectSaveExpectation.replace(a, with: a)) { XCTAssertEqual($0 as? ProjectSaveExpectationError, .sameProjectID) }
        let borrowing = try VlogProject(id: UUID(), createdAt: base, updatedAt: base, orientation: .portrait9x16, clips: [])
        let reused = try VlogClip(id: a.clips[0].id, projectID: borrowing.id, sourceKind: .imported, mediaRelativePath: a.clips[0].mediaRelativePath,
                                  createdAt: base, sourceDuration: .seconds(5), trimDuration: .seconds(3), sortOrder: 0)
        let b = try VlogProject(id: borrowing.id, createdAt: base, updatedAt: base, orientation: .portrait9x16, clips: [reused])
        XCTAssertThrowsError(try ProjectSaveExpectation.replace(a, with: b)) { XCTAssertEqual($0 as? ProjectSaveExpectationError, .overlappingClipIdentities) }
    }

    func testEmptyOrStructurallyInvalidExpectationsNeverCompleteOrConfirmPrior() throws {
        let b = try project(active: 1)
        let s = ProjectStateSnapshot(b)
        let invalid: [ProjectSaveExpectation] = [
            .debugUnvalidated(prior: [:], intended: [:]),
            .debugUnvalidated(prior: [:], intended: [b.id: .present(s)]),
            .debugUnvalidated(prior: [b.id: .absent], intended: [:]),
            .debugUnvalidated(prior: [b.id: .absent], intended: [UUID(): .present(s)]),
            .debugUnvalidated(prior: [b.id: .absent], intended: [b.id: .absent], createdProjectIDs: [b.id]),
            .debugUnvalidated(prior: [b.id: .absent], intended: [b.id: .present(s)], createdClipOwners: [UUID(): UUID()]),
        ]
        for e in invalid {
            XCTAssertFalse(e.isStructurallyValid)
            XCTAssertEqual(classify(.threw, e, [b.id: .absent], holders: [:]), .indeterminate(.invalidExpectation))
            XCTAssertEqual(classify(.succeeded, e, [b.id: .present(b)], holders: [:]), .committedUnverified(.invalidExpectation))
        }
    }

    func testSnapshotCapturesEveryComparedField() throws {
        let p = try project(active: 2, pending: 1)
        let s = ProjectStateSnapshot(p)
        XCTAssertTrue(s.ownershipIsConsistent)
        XCTAssertEqual(s.activeClips, p.clips)
        XCTAssertEqual(Set(s.pendingDeletedClips.keys), Set(p.deletedClips.map(\.id)))
        XCTAssertEqual(s.clipIDs, Set(p.durableClips.map(\.id)))
        let moved = try VlogProject(id: p.id, createdAt: p.createdAt, updatedAt: p.updatedAt.addingTimeInterval(1), orientation: p.orientation,
                                    clips: p.clips, deletedClips: p.deletedClips)
        XCTAssertNotEqual(ProjectStateSnapshot(moved), s)
    }
}
