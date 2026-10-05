import Foundation
import SwiftData
import XCTest
@testable import Mellow

/// Select Clips save-outcome integration (ADR-050 050-D D8.0 / D8.5a P1 · P4 · P6 · P8, OD-10, ADR-033
/// Revision 1): one gate section reads the prior state, materializes and checks B, saves once (`create` or
/// `replaceProject`), then observes and classifies before releasing the gate.
///
/// Runs against an isolated temporary SwiftData store and media root. "Throws after commit", injected
/// observation faults (`debugObservationFault`) and observation rewrites are test seams that model a save
/// or read whose result the caller cannot see; they do not prove any specific SwiftData failure mode.
@MainActor
final class SelectClipsSaveOutcomeTests: XCTestCase {
    private var directory: URL!
    private var container: ModelContainer!
    private var swiftData: SwiftDataProjectRepository!
    private var repository: FailableProjectRepository!
    private var root: URL!
    private var store: ProjectMediaStore!
    private var gate: ProjectLifecycleOperationGate!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "MellowSelectClipsOutcome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = try MellowModelContainer.makePersistentContainer(storeURL: directory.appending(path: "metadata.store"))
        swiftData = SwiftDataProjectRepository(modelContext: container.mainContext)
        repository = FailableProjectRepository(inner: swiftData)
        root = TestSupport.temporaryRoot("select-clips-outcome")
        store = ProjectMediaStore(root: root)
        gate = ProjectLifecycleOperationGate()
    }

    override func tearDown() {
        repository = nil
        swiftData = nil
        container = nil
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: helpers

    private func compose(_ intent: ProjectCompositionCoordinator.Intent, inspector: any ProjectMediaInspecting = AVAssetProjectMediaInspector(), sources count: Int = 1, removeSourceAt missing: Int? = nil, queuedBehind: Bool = false, mediaStore: (any ProjectMediaStoring)? = nil) async throws -> ProjectCompositionCoordinator.Outcome {
        let workspace = try await store.beginWorkspace()
        var fixtures: [URL] = []
        for index in 0..<count { fixtures.append(try await TestMediaFixtures.shared.portrait(seconds: Double(2 + index))) }
        let sources = try await TestSupport.adoptedSources(fixtures, into: workspace, store: store)
        if let missing { try FileManager.default.removeItem(at: sources[missing].url) }
        let coordinator = ProjectCompositionCoordinator(repository: repository, mediaStore: mediaStore ?? store,
                                                        validator: Phase5ReadyMediaValidator(inspector: inspector),
                                                        storage: FakeProjectStorageGate(verdict: .sufficient), lifecycle: gate)
        let outcome = await coordinator.compose(intent, sources: sources, workspace: workspace)
        // With an operation queued behind compose, release hands the gate straight to it (FIFO hand-off).
        if !queuedBehind { XCTAssertFalse(gate.isHeld, "the gate is released on every outcome") }
        XCTAssertFalse(TestSupport.exists(workspace.directory), "the workspace is always discarded")
        return outcome
    }

    /// A saved Project with one real Project-owned media file, seeded directly into the store.
    private func seed(updatedAt seconds: TimeInterval) async throws -> (VlogProject, RelativeMediaPath) {
        let workspace = try await store.beginWorkspace()
        let adopted = try await store.adopt(try TestSupport.transferCopy(of: try await TestMediaFixtures.shared.portrait(seconds: 2)), into: workspace)
        let projectID = UUID(), clipID = UUID()
        let path = try await store.materialize(adopted, projectID: projectID, clipID: clipID)
        await store.discard(workspace)
        let date = Date(timeIntervalSince1970: seconds)
        let clip = try VlogClip(id: clipID, projectID: projectID, sourceKind: .imported, mediaRelativePath: path, createdAt: date,
                                sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: 0)
        let project = try VlogProject(id: projectID, createdAt: date, updatedAt: date, orientation: .portrait9x16, clips: [clip])
        try swiftData.create(project)
        return (project, path)
    }

    /// Saved Project A (current) plus an older unrelated Project U, both with media.
    private func seedAAndUnrelated() async throws -> (a: VlogProject, aMedia: RelativeMediaPath, unrelatedMedia: RelativeMediaPath) {
        let (_, unrelatedMedia) = try await seed(updatedAt: 100)
        let (a, aMedia) = try await seed(updatedAt: 500)
        XCTAssertEqual(try swiftData.recentProjects().first?.id, a.id)
        return (a, aMedia, unrelatedMedia)
    }

    private func projectDirectories() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects").path)) ?? [])
    }

    /// The single new Project directory this operation created (its ID), if any.
    private func newDirectory(besides existing: Set<String>) -> UUID? {
        projectDirectories().subtracting(existing).first.flatMap(UUID.init(uuidString:))
    }

    private func mediaFiles(_ projectID: UUID) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects/\(projectID.uuidString)/Media").path)) ?? []).sorted()
    }

    private func recovery() -> ProjectStartupRecoveryCoordinator {
        ProjectStartupRecoveryCoordinator(repository: swiftData, store: store, lifecycle: gate, isEditorSessionLive: { _ in false })
    }

    /// Every observation fetch fails once the save has been attempted (prior reads stay real).
    private func failObservationsAfterSave() {
        let swiftData = swiftData!
        repository.onSave = { swiftData.debugObservationFault = { _ in true } }
    }

    // MARK: Fresh creation

    func testFreshCompletedSavesBOnceAndNavigates() async throws {
        let outcome = try await compose(.fresh, sources: 2)
        guard case .committed(let bID) = outcome else { return XCTFail("\(outcome)") }
        let b = try XCTUnwrap(try swiftData.project(id: bID))
        XCTAssertEqual(b.clips.count, 2)
        for clip in b.clips { await assertFileExists(store, clip.mediaRelativePath, true) }
        XCTAssertEqual(repository.createCount, 1)
        XCTAssertEqual(repository.replaceCount, 0)
        XCTAssertEqual(repository.priorObservations.count, 1, "B's absence was read before materialization")
        XCTAssertEqual(repository.stateObservations.count, 1)
    }

    func testFreshSaveThatLandsThenThrowsIsCompleted() async throws {
        repository.createThrowsAfterCommit = true
        let outcome = try await compose(.fresh)
        guard case .committed(let bID) = outcome else { return XCTFail("P4: completed despite the thrown save, got \(outcome)") }
        let b = try XCTUnwrap(try swiftData.project(id: bID))
        await assertFileExists(store, b.clips[0].mediaRelativePath, true)
    }

    func testFreshSuccessfulSaveWithUnavailableVerificationIsCommittedUnverified() async throws {
        failObservationsAfterSave()
        let before = projectDirectories()
        let outcome = try await compose(.fresh)
        XCTAssertEqual(outcome, .committedUnverified(.unreadable), "D8.0: success + unavailable verification is not indeterminate")
        let bID = try XCTUnwrap(newDirectory(besides: before))
        swiftData.debugObservationFault = nil
        let b = try XCTUnwrap(try swiftData.project(id: bID), "never rolled back")
        await assertFileExists(store, b.clips[0].mediaRelativePath, true, "referenced media preserved")
        XCTAssertTrue(repository.deletedIDs.isEmpty)
    }

    func testFreshSuccessfulSaveWithContradictoryVerificationIsCommittedUnverified() async throws {
        repository.stateObservationOverride = { expectation, observed in
            // B's row reads as absent although the save returned.
            PersistedStateObservation(projects: observed.projects.mapValues { _ in .absent }, createdIdentityHolders: observed.createdIdentityHolders)
        }
        let before = projectDirectories()
        let outcome = try await compose(.fresh)
        guard case .committedUnverified = outcome else { return XCTFail("\(outcome)") }
        let bID = try XCTUnwrap(newDirectory(besides: before))
        XCTAssertNotNil(try swiftData.project(id: bID))
        XCTAssertFalse(mediaFiles(bID).isEmpty, "media preserved")
    }

    func testFreshThrownSaveWithNothingLandedIsPriorConfirmedAndLeavesBToStartupRecovery() async throws {
        let (u, uMedia) = try await seed(updatedAt: 100)
        repository.createFails = true
        let before = projectDirectories()
        let outcome = try await compose(.fresh)
        XCTAssertEqual(outcome, .priorConfirmed)
        let bID = try XCTUnwrap(newDirectory(besides: before), "candidate files preserved (no rollback-to-workspace)")
        XCTAssertNil(try swiftData.project(id: bID))
        await assertFileExists(store, uMedia, true, "unrelated media untouched")

        let report = await recovery().recoverOrphans()
        XCTAssertEqual(report.orphanProjectDirsRemoved, 1, "the existing startup recovery removes the unreferenced B only")
        XCTAssertEqual(projectDirectories(), [u.id.uuidString])
    }

    func testFreshSaveThatLandsThenThrowsWithUnreadableEvidenceIsIndeterminate() async throws {
        repository.createThrowsAfterCommit = true
        failObservationsAfterSave()
        let before = projectDirectories()
        let outcome = try await compose(.fresh)
        XCTAssertEqual(outcome, .indeterminate(.unreadable))
        let bID = try XCTUnwrap(newDirectory(besides: before))
        swiftData.debugObservationFault = nil
        XCTAssertNotNil(try swiftData.project(id: bID), "the landed row is kept")
        XCTAssertFalse(mediaFiles(bID).isEmpty, "potentially referenced media preserved")
    }

    func testFreshThrownSaveWithMissingIdentityEvidenceIsIndeterminate() async throws {
        repository.createFails = true
        repository.stateObservationOverride = { _, observed in
            PersistedStateObservation(projects: observed.projects, createdIdentityHolders: nil)
        }
        let before = projectDirectories()
        let outcome = try await compose(.fresh)
        XCTAssertEqual(outcome, .indeterminate(.identityEvidenceMissing))
        XCTAssertNotNil(newDirectory(besides: before), "preserved: absence is not confirmed store-wide")
    }

    func testFreshUnreadablePriorStopsBeforeMaterialization() async throws {
        swiftData.debugObservationFault = { if case .project = $0 { return true } else { return false } }
        let outcome = try await compose(.fresh)
        XCTAssertEqual(outcome, .projectInspectionFailed, "unreadable is not verified absence")
        XCTAssertEqual(repository.createCount, 0)
        XCTAssertTrue(repository.stateObservations.isEmpty)
        XCTAssertTrue(TestSupport.noProjectMedia(under: root))
    }

    // MARK: Replacement

    func testReplacementCompletedUsesOneSaveAndRemovesAMediaOnly() async throws {
        let (a, aMedia, unrelatedMedia) = try await seedAAndUnrelated()
        let outcome = try await compose(.replacingSaved(a.id))
        guard case .committed(let bID) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(repository.replaceCount, 1)
        XCTAssertEqual(repository.createCount, 0, "no create(B)")
        XCTAssertEqual(repository.deletedIDs, [], "no separate deleteProject(A)")
        XCTAssertNil(try swiftData.project(id: a.id))
        XCTAssertEqual(try swiftData.recentProjects().first?.id, bID)
        await assertFileExists(store, aMedia, false, "A's media removed after completed + confirmed absence")
        await assertFileExists(store, unrelatedMedia, true, "unrelated media untouched")
        let b = try XCTUnwrap(try swiftData.project(id: bID))
        await assertFileExists(store, b.clips[0].mediaRelativePath, true)
    }

    func testReplacementThatLandsThenThrowsIsCompletedAndRemovesA() async throws {
        let (a, aMedia, unrelatedMedia) = try await seedAAndUnrelated()
        repository.replaceThrowsAfterCommit = true
        let outcome = try await compose(.replacingSaved(a.id))
        guard case .committed = outcome else { return XCTFail("\(outcome)") }
        await assertFileExists(store, aMedia, false)
        await assertFileExists(store, unrelatedMedia, true)
    }

    func testReplacementSuccessWithUnavailableVerificationPreservesBothMedia() async throws {
        let (a, aMedia, unrelatedMedia) = try await seedAAndUnrelated()
        failObservationsAfterSave()
        let before = projectDirectories()
        let outcome = try await compose(.replacingSaved(a.id))
        XCTAssertEqual(outcome, .committedUnverified(.unreadable))
        let bID = try XCTUnwrap(newDirectory(besides: before))
        await assertFileExists(store, aMedia, true, "A's media is kept without confirmation")
        await assertFileExists(store, unrelatedMedia, true)
        XCTAssertFalse(mediaFiles(bID).isEmpty)
    }

    func testReplacementSuccessWithContradictoryVerificationPreservesBothMedia() async throws {
        let (a, aMedia, _) = try await seedAAndUnrelated()
        repository.stateObservationOverride = { _, observed in
            // A still reported present next to B.
            var projects = observed.projects
            projects[a.id] = .present(a)
            return PersistedStateObservation(projects: projects, createdIdentityHolders: observed.createdIdentityHolders)
        }
        let outcome = try await compose(.replacingSaved(a.id))
        XCTAssertEqual(outcome, .committedUnverified(.partial))
        await assertFileExists(store, aMedia, true)
    }

    func testReplacementThrownWithNothingLandedIsPriorConfirmedAndKeepsA() async throws {
        let (a, aMedia, unrelatedMedia) = try await seedAAndUnrelated()
        repository.replaceFails = true
        let before = projectDirectories()
        let outcome = try await compose(.replacingSaved(a.id))
        XCTAssertEqual(outcome, .priorConfirmed)
        XCTAssertEqual(try swiftData.recentProjects().first?.id, a.id, "A is still the saved Project")
        await assertFileExists(store, aMedia, true)
        await assertFileExists(store, unrelatedMedia, true)
        XCTAssertNotNil(newDirectory(besides: before), "B's candidate files are left to startup recovery")
        XCTAssertEqual(repository.createCount, 0, "no B-only fallback")
    }

    func testReplacementThatLandsThenThrowsWithUnreadableEvidenceIsIndeterminate() async throws {
        let (a, aMedia, _) = try await seedAAndUnrelated()
        repository.replaceThrowsAfterCommit = true
        failObservationsAfterSave()
        let outcome = try await compose(.replacingSaved(a.id))
        XCTAssertEqual(outcome, .indeterminate(.unreadable))
        await assertFileExists(store, aMedia, true, "A's media preserved although its row may be gone")
    }

    func testRemovedTargetIsInvalidatedWithoutBOnlyFallback() async throws {
        let (a, _, unrelatedMedia) = try await seedAAndUnrelated()
        try swiftData.deleteProject(id: a.id)
        let before = projectDirectories()
        let outcome = try await compose(.replacingSaved(a.id))
        XCTAssertEqual(outcome, .replacementTargetInvalidated)
        XCTAssertEqual(repository.createCount, 0, "B is never created alone")
        XCTAssertEqual(repository.replaceCount, 0)
        XCTAssertEqual(projectDirectories(), before, "nothing materialized")
        await assertFileExists(store, unrelatedMedia, true)
    }

    func testTargetThatIsNoLongerCurrentIsInvalidated() async throws {
        let (a, aMedia, _) = try await seedAAndUnrelated()
        let (newer, _) = try await seed(updatedAt: 900)
        let before = projectDirectories()
        let outcome = try await compose(.replacingSaved(a.id))
        XCTAssertEqual(outcome, .replacementTargetInvalidated)
        XCTAssertEqual(try swiftData.recentProjects().first?.id, newer.id)
        XCTAssertNotNil(try swiftData.project(id: a.id))
        await assertFileExists(store, aMedia, true)
        XCTAssertEqual(projectDirectories(), before)
        XCTAssertEqual(repository.createCount + repository.replaceCount, 0)
    }

    func testUnreadablePriorTargetStopsBeforeMaterialization() async throws {
        let (a, aMedia, _) = try await seedAAndUnrelated()
        swiftData.debugObservationFault = { $0 == .project(a.id) }
        let before = projectDirectories()
        let outcome = try await compose(.replacingSaved(a.id))
        XCTAssertEqual(outcome, .projectInspectionFailed, "unreadable A is neither absent nor invalidated")
        XCTAssertEqual(projectDirectories(), before)
        XCTAssertEqual(repository.createCount + repository.replaceCount, 0)
        await assertFileExists(store, aMedia, true)
    }

    func testUnreadableCurrentProjectLookupStopsBeforeMaterialization() async throws {
        let (a, _, _) = try await seedAAndUnrelated()
        // Real fresh-read path, injected fetch failure.
        swiftData.debugObservationFault = { $0 == .currentProject }
        let before = projectDirectories()
        let outcome = try await compose(.replacingSaved(a.id))
        XCTAssertEqual(outcome, .projectInspectionFailed, "an undeterminable current Project is fail-closed")
        XCTAssertEqual(projectDirectories(), before)
        XCTAssertEqual(repository.createCount + repository.replaceCount, 0)
    }

    func testCurrentProjectCheckUsesTheFreshReadNotTheSharedContext() async throws {
        let (a, _, _) = try await seedAAndUnrelated()
        // The shared-context lookup is broken; the fresh-read check must not depend on it.
        repository.recentProjectsFails = true
        let outcome = try await compose(.replacingSaved(a.id))
        guard case .committed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(repository.currentProjectObservations, 1)
    }

    func testUnsavedSharedContextChangesDoNotMakeAnotherProjectCurrent() async throws {
        let (a, _, _) = try await seedAAndUnrelated()
        // An unsaved, newer row in the shared context: invisible to the fresh read, so A is still current.
        let pending = PersistedVlogProject(project: try VlogProject(createdAt: Date(timeIntervalSince1970: 9_000), updatedAt: Date(timeIntervalSince1970: 9_000), orientation: .portrait9x16))
        // Keep the row unsaved (this test's isolated container is discarded in tearDown).
        container.mainContext.autosaveEnabled = false
        container.mainContext.insert(pending)
        XCTAssertEqual(swiftData.observeCurrentProjectID(), .project(a.id), "fresh read ignores unsaved shared state")
        container.mainContext.delete(pending)
        // And the converse through compose: a saved newer Project is seen by the fresh read.
        let (newer, _) = try await seed(updatedAt: 9_500)
        XCTAssertEqual(swiftData.observeCurrentProjectID(), .project(newer.id))
        let outcome = try await compose(.replacingSaved(a.id))
        XCTAssertEqual(outcome, .replacementTargetInvalidated)
    }

    func testUnconvertiblePersistedRowMakesTheCurrentProjectUnreadable() async throws {
        let (a, _, _) = try await seedAAndUnrelated()
        // A stored row that cannot be converted (invalid orientation): the existing ordering decodes every
        // row, so the current Project cannot be determined reliably.
        let broken = PersistedVlogProject(id: UUID(), createdAt: Date(timeIntervalSince1970: 50), updatedAt: Date(timeIntervalSince1970: 50), orientationRawValue: "not-an-orientation")
        container.mainContext.insert(broken)
        try container.mainContext.save()
        XCTAssertEqual(swiftData.observeCurrentProjectID(), .unreadable)
        let outcome = try await compose(.replacingSaved(a.id))
        XCTAssertEqual(outcome, .projectInspectionFailed)
    }

    func testNoPersistedProjectIsNoneNotUnreadable() {
        XCTAssertEqual(swiftData.observeCurrentProjectID(), ObservedCurrentProject.none)
    }

    func testProjectNotFoundFromTheReplacementCallIsClassifiedNotInvalidated() async throws {
        let (a, aMedia, _) = try await seedAAndUnrelated()
        // A disappears after the in-gate recheck, so the repository call itself throws `projectNotFound`.
        let swiftData = swiftData!
        repository.onSave = { try? swiftData.deleteProject(id: a.id) }
        let before = projectDirectories()
        let outcome = try await compose(.replacingSaved(a.id))
        guard case .indeterminate = outcome else { return XCTFail("D8.0 classification after an attempted call, got \(outcome)") }
        XCTAssertEqual(repository.createCount, 0, "no B-only fallback")
        XCTAssertNotNil(newDirectory(besides: before), "B's media preserved after the attempt")
        await assertFileExists(store, aMedia, true, "A's files are not removed without completion")
    }

    // MARK: Pre-save failures

    func testPreSaveMaterializationFailureRemovesOnlyBsOwnDirectory() async throws {
        let (a, aMedia, unrelatedMedia) = try await seedAAndUnrelated()
        let before = projectDirectories()
        // The fake inspector passes both; the second workspace file is gone at materialization.
        let outcome = try await compose(.replacingSaved(a.id), inspector: FakeProjectMediaInspector(.ready()), sources: 2, removeSourceAt: 1)
        XCTAssertEqual(outcome, .preparationFailed)
        XCTAssertEqual(projectDirectories(), before, "B's partial directory removed (pre-save, owned)")
        XCTAssertEqual(repository.createCount + repository.replaceCount, 0)
        await assertFileExists(store, aMedia, true)
        await assertFileExists(store, unrelatedMedia, true)
    }

    func testEmptySelectionIsAPreparationFailure() async throws {
        let workspace = try await store.beginWorkspace()
        let coordinator = ProjectCompositionCoordinator(repository: repository, mediaStore: store,
                                                        validator: Phase5ReadyMediaValidator(inspector: FakeProjectMediaInspector(.ready())),
                                                        storage: FakeProjectStorageGate(verdict: .sufficient), lifecycle: gate)
        let outcome = await coordinator.compose(.fresh, sources: [], workspace: workspace)
        XCTAssertEqual(outcome, .preparationFailed)
        XCTAssertTrue(repository.priorObservations.isEmpty, "rejected before the gated section")
    }

    func testPreSaveMediaCheckFailureRemovesOnlyBsOwnDirectory() async throws {
        let (a, aMedia, unrelatedMedia) = try await seedAAndUnrelated()
        let before = projectDirectories()
        // Materialization succeeds, but the pre-save existence check cannot see B's files.
        let outcome = try await compose(.replacingSaved(a.id), mediaStore: BlindMediaStore(store))
        XCTAssertEqual(outcome, .preparationFailed)
        XCTAssertEqual(projectDirectories(), before, "B's own directory removed before any save")
        XCTAssertEqual(repository.createCount + repository.replaceCount, 0, "never saved")
        XCTAssertTrue(repository.stateObservations.isEmpty)
        await assertFileExists(store, aMedia, true)
        await assertFileExists(store, unrelatedMedia, true)
    }

    // MARK: Gate

    func testSaveObservationAndClassificationRunInsideOneGateSection() async throws {
        let (a, aMedia, _) = try await seedAAndUnrelated()
        final class Probe { var heldAtSave = false, heldAtObservation = false, queuedRan = false, queuedSawObservation = false, queuedSawAMedia = true }
        let probe = Probe()
        let gate = self.gate!, repository = self.repository!, store = self.store!
        repository.onSave = {
            probe.heldAtSave = gate.isHeld
            // A lifecycle operation queued during the save must wait for the whole section: observation,
            // classification and A's media removal.
            Task { @MainActor in
                await gate.withExclusiveAccess {
                    probe.queuedRan = true
                    probe.queuedSawObservation = repository.stateObservations.count == 1
                    probe.queuedSawAMedia = await store.fileExists(aMedia)
                }
            }
        }
        repository.stateObservationOverride = { _, observed in
            probe.heldAtObservation = gate.isHeld
            return observed
        }
        let outcome = try await compose(.replacingSaved(a.id), queuedBehind: true)
        guard case .committed = outcome else { return XCTFail("\(outcome)") }
        await gate.withExclusiveAccess {}   // FIFO: the queued operation has finished before this one runs
        XCTAssertTrue(probe.heldAtSave)
        XCTAssertTrue(probe.heldAtObservation)
        XCTAssertTrue(probe.queuedRan)
        XCTAssertTrue(probe.queuedSawObservation)
        XCTAssertFalse(probe.queuedSawAMedia, "the queued operation ran only after A's media removal")
        XCTAssertFalse(gate.isHeld)
    }

    func testEveryOutcomeReleasesTheGateWithoutNestedAcquisition() async throws {
        let (a, _, _) = try await seedAAndUnrelated()
        let gate = self.gate!
        /// Runs one compose against a bounded wait: re-acquiring the non-reentrant gate would hang it.
        func boundedCompose(_ intent: ProjectCompositionCoordinator.Intent, _ label: String, sources: Int = 1, removeSourceAt: Int? = nil, inspector: any ProjectMediaInspecting = AVAssetProjectMediaInspector()) async throws {
            final class Done { var value = false }
            let done = Done()
            let task = Task { @MainActor in
                _ = try await self.compose(intent, inspector: inspector, sources: sources, removeSourceAt: removeSourceAt)
                done.value = true
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while !done.value, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertTrue(done.value, "\(label): compose finished (no nested acquisition)")
            if done.value { try await task.value } else { task.cancel() }
            XCTAssertFalse(gate.isHeld, "\(label): gate released")
            XCTAssertEqual(gate.waitingCount, 0, label)
        }
        repository.replaceFails = true
        try await boundedCompose(.replacingSaved(a.id), "priorConfirmed")
        repository.replaceFails = false
        swiftData.debugObservationFault = { $0 == .currentProject }
        try await boundedCompose(.replacingSaved(a.id), "inspection failure")
        swiftData.debugObservationFault = nil
        try await boundedCompose(.replacingSaved(UUID()), "target invalidated")
        try await boundedCompose(.replacingSaved(a.id), "preparation failure", sources: 2, removeSourceAt: 1, inspector: FakeProjectMediaInspector(.ready()))
        repository.replaceThrowsAfterCommit = true
        failObservationsAfterSave()
        try await boundedCompose(.replacingSaved(a.id), "indeterminate")
    }
}

/// Media store whose existence check never sees a file (everything else forwards): models B's media
/// disappearing between materialization and the pre-save check.
private struct BlindMediaStore: ProjectMediaStoring {
    let inner: ProjectMediaStore
    init(_ inner: ProjectMediaStore) { self.inner = inner }
    func beginWorkspace() async throws -> ProjectMediaWorkspace { try await inner.beginWorkspace() }
    func adopt(_ url: URL, into workspace: ProjectMediaWorkspace) async throws -> URL { try await inner.adopt(url, into: workspace) }
    func materialize(_ url: URL, projectID: UUID, clipID: UUID) async throws -> RelativeMediaPath { try await inner.materialize(url, projectID: projectID, clipID: clipID) }
    func url(for path: RelativeMediaPath) async -> URL { await inner.url(for: path) }
    func fileExists(_ path: RelativeMediaPath) async -> Bool { false }
    func discard(_ workspace: ProjectMediaWorkspace) async { await inner.discard(workspace) }
    func removeProjectMedia(projectID: UUID) async { await inner.removeProjectMedia(projectID: projectID) }
    func removeMedia(_ path: RelativeMediaPath) async { await inner.removeMedia(path) }
    func usableCapacityBytes() async -> Int64 { await inner.usableCapacityBytes() }
}
