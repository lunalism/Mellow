import Foundation
import SwiftData
import XCTest
@testable import Mellow

/// ADR-050 050-D OD-10: `SwiftDataProjectRepository.observePersistedState(for:)` on isolated temporary
/// on-disk stores. Injected fetch failures (`debugObservationFault`) simulate a failing fetch only; these
/// tests do not prove behaviour under every cache state or every mid-save error.
@MainActor
final class ProjectStateObservationTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private var directory: URL!
    private var container: ModelContainer!
    private var repository: SwiftDataProjectRepository!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "MellowObservationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = try MellowModelContainer.makePersistentContainer(storeURL: directory.appending(path: "metadata.store"))
        repository = SwiftDataProjectRepository(modelContext: container.mainContext)
    }

    override func tearDown() {
        repository = nil
        container = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func clip(_ projectID: UUID, _ index: Int, id: UUID = UUID()) throws -> VlogClip {
        try VlogClip(id: id, projectID: projectID, sourceKind: .imported,
                     mediaRelativePath: RelativeMediaPath("Projects/\(projectID.uuidString)/Media/\(id.uuidString).mov"),
                     createdAt: base, sourceDuration: .seconds(5), trimDuration: .seconds(3), sortOrder: index)
    }

    private func project(active: Int, pending: Int = 0, updatedAt: Date? = nil, clipIDs: [UUID]? = nil) throws -> VlogProject {
        let id = UUID()
        let count = active + pending
        let ids = clipIDs ?? (0..<count).map { _ in UUID() }
        var p = try VlogProject(id: id, createdAt: base, updatedAt: updatedAt ?? base, orientation: .portrait9x16,
                                clips: (0..<count).map { try clip(id, $0, id: ids[$0]) })
        for i in 0..<pending { try p.deleteClip(id: p.clips[p.clips.count - 1].id, deletedAt: base.addingTimeInterval(Double(i + 1))) }
        return p
    }

    private func classify(_ attempt: ProjectSaveAttempt, _ e: ProjectSaveExpectation) -> ProjectSaveOutcome {
        ProjectSaveOutcomeClassifier.classify(attempt, expectation: e, observation: repository.observePersistedState(for: e))
    }

    // MARK: Absent / present / unreadable

    func testAbsentPresentAndDomainConversionFailureAreDistinct() throws {
        let a = try project(active: 2, pending: 1)
        try repository.create(a)
        let b = try project(active: 1)
        let present = repository.observePersistedState(for: try .update(from: a, to: a))
        XCTAssertEqual(present.projects[a.id], .present(a))
        XCTAssertEqual(repository.observePersistedState(for: .create(b)).projects[b.id], .absent)

        // A genuine conversion failure: a stored row whose orientation value is not a valid orientation.
        let broken = PersistedVlogProject(id: UUID(), createdAt: base, updatedAt: base, orientationRawValue: "not-an-orientation")
        let writer = ModelContext(container)
        writer.insert(broken)
        try writer.save()
        let brokenExpectation = ProjectSaveExpectation.create(try VlogProject(id: broken.id, createdAt: base, updatedAt: base, orientation: .portrait9x16))
        XCTAssertEqual(repository.observePersistedState(for: brokenExpectation).projects[broken.id], .unreadable)
    }

    func testInjectedFetchFailureIsUnreadableAndClassifiesInconclusively() throws {
        let b = try project(active: 2)
        let e = ProjectSaveExpectation.create(b)
        repository.debugObservationFault = { $0 == .project(b.id) }   // simulated fetch failure
        let observation = repository.observePersistedState(for: e)
        XCTAssertEqual(observation.projects[b.id], .unreadable)
        XCTAssertEqual(ProjectSaveOutcomeClassifier.classify(.threw, expectation: e, observation: observation), .indeterminate(.unreadable))
        XCTAssertEqual(ProjectSaveOutcomeClassifier.classify(.succeeded, expectation: e, observation: observation), .committedUnverified(.unreadable))
    }

    // MARK: Create / update / replacement

    func testCreateObservedBeforeAndAfterTheSave() throws {
        let b = try project(active: 3, pending: 1)
        let e = ProjectSaveExpectation.create(b)
        let before = repository.observePersistedState(for: e)
        XCTAssertEqual(before.projects[b.id], .absent)
        XCTAssertEqual(before.createdIdentityHolders?.count, 1 + 4)
        XCTAssertTrue(before.createdIdentityHolders?.values.allSatisfy(\.isEmpty) ?? false)
        XCTAssertEqual(ProjectSaveOutcomeClassifier.classify(.threw, expectation: e, observation: before), .priorConfirmed)

        try repository.create(b)
        let after = repository.observePersistedState(for: e)
        XCTAssertEqual(after.projects[b.id], .present(b))
        XCTAssertEqual(after.createdIdentityHolders?[b.id], [b.id])
        XCTAssertTrue(b.durableClips.allSatisfy { after.createdIdentityHolders?[$0.id] == [b.id] })
        XCTAssertEqual(ProjectSaveOutcomeClassifier.classify(.threw, expectation: e, observation: after), .completed)
        XCTAssertEqual(ProjectSaveOutcomeClassifier.classify(.succeeded, expectation: e, observation: after), .completed)
    }

    func testUpdateAndANewObservationAfterALaterSave() throws {
        let before = try project(active: 2)
        try repository.create(before)
        var after = before
        let added = try clip(before.id, 2)
        try after.appendClips([added], appendedAt: base.addingTimeInterval(1))
        let e = try ProjectSaveExpectation.update(from: before, to: after)

        let first = repository.observePersistedState(for: e)
        XCTAssertEqual(first.projects[before.id], .present(before))
        XCTAssertEqual(first.createdIdentityHolders, [added.id: []])

        try repository.update(after)
        let second = repository.observePersistedState(for: e)
        XCTAssertEqual(second.projects[before.id], .present(after))
        XCTAssertEqual(second.createdIdentityHolders, [added.id: [before.id]])
        XCTAssertEqual(ProjectSaveOutcomeClassifier.classify(.threw, expectation: e, observation: second), .completed)
    }

    func testSingleSaveReplacementObservation() throws {
        let a = try project(active: 3, pending: 2)
        try repository.create(a)
        let b = try project(active: 2, pending: 1, updatedAt: base.addingTimeInterval(60))
        let e = try ProjectSaveExpectation.replace(a, with: b)
        let before = repository.observePersistedState(for: e)
        XCTAssertEqual(before.projects, [a.id: .present(a), b.id: .absent])

        try repository.replaceProject(previousID: a.id, with: b)
        let after = repository.observePersistedState(for: e)
        XCTAssertEqual(after.projects, [a.id: .absent, b.id: .present(b)])
        guard case .present(let stored)? = after.projects[b.id] else { return XCTFail("B missing") }
        XCTAssertEqual(stored.deletedClips.count, 1)
        XCTAssertTrue(stored.durableClips.allSatisfy { $0.projectID == b.id })
        XCTAssertEqual(ProjectSaveOutcomeClassifier.classify(.threw, expectation: e, observation: after), .completed)
    }

    // MARK: Store-wide created identities

    func testCreatedClipHeldByAnotherProjectIsReported() throws {
        let sharedID = UUID()
        let c = try project(active: 2, clipIDs: [sharedID, UUID()])
        try repository.create(c)
        let b = try project(active: 2, clipIDs: [UUID(), sharedID])
        let e = ProjectSaveExpectation.create(b)
        let observation = repository.observePersistedState(for: e)
        XCTAssertEqual(observation.createdIdentityHolders?[sharedID], [c.id])
        XCTAssertEqual(observation.createdIdentityHolders?[b.clips[0].id], [])
        XCTAssertEqual(ProjectSaveOutcomeClassifier.classify(.threw, expectation: e, observation: observation), .indeterminate(.createdIdentityPresent))
    }

    func testCreatedClipRowWithoutOwnerIsReportedAsHeld() throws {
        let orphanID = UUID()
        let writer = ModelContext(container)
        writer.insert(PersistedVlogClip(clip: try clip(UUID(), 0, id: orphanID)))   // genuine row with no Project
        try writer.save()
        let b = try project(active: 1, clipIDs: [orphanID])
        let e = ProjectSaveExpectation.create(b)
        let observation = repository.observePersistedState(for: e)
        XCTAssertEqual(observation.createdIdentityHolders?[orphanID], [SwiftDataProjectRepository.unownedClipHolder])
        XCTAssertEqual(ProjectSaveOutcomeClassifier.classify(.threw, expectation: e, observation: observation), .indeterminate(.createdIdentityPresent))
    }

    func testLargeCreatedIdentitySetIncludingBatchBoundaries() throws {
        let batch = SwiftDataProjectRepository.clipIdentityQueryBatchSize
        let count = batch * 2 + 200
        // The helper batches created identities in sorted order; real batch edges are in that order.
        let ids = (0..<count).map { _ in UUID() }.sorted { $0.uuidString < $1.uuidString }
        let boundaries = [batch - 1, batch, batch * 2 - 1, batch * 2]
        let c = try project(active: boundaries.count, clipIDs: boundaries.map { ids[$0] })
        try repository.create(c)
        let b = try project(active: count, clipIDs: ids)
        let observation = repository.observePersistedState(for: .create(b))
        let holders = try XCTUnwrap(observation.createdIdentityHolders)
        XCTAssertEqual(holders.count, count + 1)
        for index in 0..<count {
            XCTAssertEqual(holders[ids[index]], boundaries.contains(index) ? [c.id] : [], "index \(index)")
        }
    }

    func testFailedBatchIsMissingButOtherBatchesStillReportConflicts() throws {
        let batch = SwiftDataProjectRepository.clipIdentityQueryBatchSize
        let created = (0..<(batch * 2 + 200)).map { _ in UUID() }
        // The helper batches created identities in sorted order; index into that order.
        let ids = created.sorted { $0.uuidString < $1.uuidString }
        let c = try project(active: 1, clipIDs: [ids[batch * 2 + 10]])
        try repository.create(c)
        let b = try project(active: created.count, clipIDs: created)
        let e = ProjectSaveExpectation.create(b)
        repository.debugObservationFault = { $0 == .createdClips(batch: 1) }   // simulated failure of one batch
        let observation = repository.observePersistedState(for: e)
        let holders = try XCTUnwrap(observation.createdIdentityHolders)
        XCTAssertTrue((batch..<(batch * 2)).allSatisfy { holders[ids[$0]] == nil }, "a failed batch is left missing, not reported absent")
        XCTAssertEqual(holders.count, 1 + created.count - batch)
        XCTAssertEqual(holders[ids[batch * 2 + 10]], [c.id])
        XCTAssertEqual(holders[ids[0]], [])
        // The conflict found elsewhere is not hidden by the missing batch.
        XCTAssertEqual(ProjectSaveOutcomeClassifier.classify(.threw, expectation: e, observation: observation), .indeterminate(.createdIdentityPresent))
    }

    func testNoCreatedIdentitiesMeansNoCreatedIdentityQueries() throws {
        let before = try project(active: 3)
        try repository.create(before)
        var after = before
        try after.reorderClip(id: before.clips[2].id, toIndex: 0, updatedAt: base.addingTimeInterval(1))
        let e = try ProjectSaveExpectation.update(from: before, to: after)
        var fetches: [SwiftDataProjectRepository.ObservationFetch] = []
        repository.debugObservationFault = { fetches.append($0); return false }   // records, never fails
        let observation = repository.observePersistedState(for: e)
        XCTAssertEqual(fetches, [.project(before.id)])
        XCTAssertEqual(observation.createdIdentityHolders, [:])
    }

    // MARK: Shared-context unsaved edits

    func testSharedContextUnsavedEditsAreExcludedAndPreserved() throws {
        let a = try project(active: 2)
        try repository.create(a)
        let shared = container.mainContext
        shared.autosaveEnabled = false
        // An unsaved new Project and an unsaved edit to A in the shared context.
        let stray = try project(active: 1)
        shared.insert(PersistedVlogProject(project: stray))
        let aID = a.id
        let row = try XCTUnwrap(try shared.fetch(FetchDescriptor<PersistedVlogProject>(predicate: #Predicate { $0.id == aID })).first)
        row.updatedAt = base.addingTimeInterval(999)
        XCTAssertTrue(shared.hasChanges)

        XCTAssertEqual(repository.observePersistedState(for: .create(stray)).projects[stray.id], .absent)
        XCTAssertEqual(repository.observePersistedState(for: try .update(from: a, to: a)).projects[a.id], .present(a))

        XCTAssertTrue(shared.hasChanges, "the shared context's edits were neither saved nor discarded")
        XCTAssertTrue(shared.insertedModelsArray.contains { ($0 as? PersistedVlogProject)?.id == stray.id }, "the stray insert is still pending")
        XCTAssertEqual(row.updatedAt, base.addingTimeInterval(999))
        // The store itself is unchanged: a third, fresh context sees neither edit.
        let verifier = ModelContext(container)
        let strayID = stray.id
        XCTAssertEqual(try verifier.fetchCount(FetchDescriptor<PersistedVlogProject>(predicate: #Predicate { $0.id == strayID })), 0)
        XCTAssertEqual(try verifier.fetch(FetchDescriptor<PersistedVlogProject>(predicate: #Predicate { $0.id == aID })).first?.updatedAt, a.updatedAt)
        shared.rollback()
    }
}
