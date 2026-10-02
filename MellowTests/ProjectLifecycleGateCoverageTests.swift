import Foundation
import SwiftData
import XCTest
@testable import Mellow

/// ADR-039 / ADR-050 serialization prerequisite: Home Project deletion and the Editor's Add / Replace
/// target check → materialise → commit share the ONE lifecycle gate with composition, cleanup and
/// startup recovery. Real on-disk SwiftData store and real `ProjectMediaStore` under a temporary root,
/// the real Phase-5 validator with fixture media and the deterministic fake selector. Interleavings
/// are forced through the gate's FIFO order (a test-held section, then queued operations), never by
/// timing; `waitUntil` only polls for a queued state to be reached.
@MainActor
final class ProjectLifecycleGateCoverageTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!
    private var container: ModelContainer!
    private var repository: SwiftDataProjectRepository!
    private var gate: ProjectLifecycleOperationGate!

    override func setUpWithError() throws {
        root = TestSupport.temporaryRoot("lifecycle-gate")
        store = ProjectMediaStore(root: root)
        let storeDirectory = root.appendingPathComponent("Store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        container = try MellowModelContainer.makePersistentContainer(storeURL: storeDirectory.appendingPathComponent("metadata.store"))
        repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        gate = ProjectLifecycleOperationGate()
    }

    override func tearDown() {
        repository = nil
        container = nil
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: helpers

    /// Holds the gate from the test until `release()`, so operations can be queued in a chosen order.
    private final class GateHolder {
        private var continuation: CheckedContinuation<Void, Never>?
        private var task: Task<Void, Never>?
        var isHolding: Bool { continuation != nil }

        @MainActor func hold(_ gate: ProjectLifecycleOperationGate) {
            task = Task { @MainActor in
                await gate.withExclusiveAccess { await withCheckedContinuation { self.continuation = $0 } }
            }
        }

        @MainActor func release() async {
            continuation?.resume()
            continuation = nil
            await task?.value
        }
    }

    private func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition() {
            guard ContinuousClock.now < deadline else { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func holdGate() async throws -> GateHolder {
        let holder = GateHolder()
        holder.hold(gate)
        try await waitUntil("test holds the gate") { holder.isHolding }
        return holder
    }

    private func committedClip(projectID: UUID, order: Int, withFile: Bool) async throws -> VlogClip {
        let clipID = UUID()
        let path = try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID)
        if withFile {
            let url = await store.url(for: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: 128).write(to: url)
        }
        return try VlogClip(id: clipID, projectID: projectID, sourceKind: .recorded, mediaRelativePath: path,
                            sourceDuration: .seconds(3), trimDuration: .seconds(3), sortOrder: order)
    }

    /// An empty Project (no directory on disk) or `A B` where B's file is missing (unavailable).
    private func makeProject(withClips: Bool) async throws -> VlogProject {
        let id = UUID()
        let clips = withClips
            ? [try await committedClip(projectID: id, order: 0, withFile: true), try await committedClip(projectID: id, order: 1, withFile: false)]
            : []
        let project = try VlogProject(id: id, orientation: .portrait9x16, clips: clips)
        try repository.create(project)
        return project
    }

    private func makeEditor(_ project: VlogProject, fixtures: Int = 1, repository: (any ProjectRepository)? = nil,
                            afterMaterialize: (@MainActor () -> Void)? = nil) async throws -> ProjectEditorModel {
        var urls: [URL] = []
        for _ in 0..<fixtures { urls.append(try await TestMediaFixtures.shared.portrait(seconds: 2)) }
        let selector = FakeProjectMediaSelector(script: .fixtures(urls))
        let appender = ProjectClipAppendCoordinator(mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()), storage: FakeProjectStorageGate(verdict: .sufficient))
        var acquisition = EditorClipAcquisition(mediaStore: store, mediaSelector: selector, storageGate: FakeProjectStorageGate(verdict: .sufficient), appender: appender, lifecycle: gate)
        acquisition.debugAfterMaterialize = afterMaterialize
        let model = ProjectEditorModel(project: project, repository: repository ?? self.repository, thumbnails: FakeClipThumbnailProvider(),
                                       acquisition: acquisition, availability: CommittedMediaAvailabilityChecker(resolver: store))
        await model.refreshAvailability()
        return model
    }

    private func makeHome(deleting project: VlogProject) -> HomeModel {
        let home = HomeModel(repository: repository, router: AppRouter(), lifecycle: gate)
        home.pendingDeletion = project
        return home
    }

    private func projectDirectory(_ id: UUID) -> URL { root.appendingPathComponent("Projects/\(id.uuidString)") }
    private func mediaFiles(_ id: UUID) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: projectDirectory(id).appendingPathComponent("Media").path)) ?? []).sorted()
    }
    private func workspaceEntries() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("ProjectWorkspace").path)) ?? []
    }

    // MARK: Deletion wins

    func testDeletionBeforeAddStopsBeforeMaterialisationAndNeverRecreatesTheDirectory() async throws {
        let project = try await makeProject(withClips: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectDirectory(project.id).path))
        let editor = try await makeEditor(project)
        let home = makeHome(deleting: project)

        let holder = try await holdGate()
        let deletion = Task { await home.confirmDeletion() }
        try await waitUntil("deletion queued") { gate.waitingCount == 1 }
        let add = Task { await editor.addClips() }
        try await waitUntil("add validated and queued") { gate.waitingCount == 2 }
        await holder.release()
        await deletion.value
        let added = await add.value

        XCTAssertEqual(added, 0)
        XCTAssertNil(home.failure)
        XCTAssertNil(try repository.project(id: project.id), "no Project is silently created")
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectDirectory(project.id).path), "deleted Project directory not recreated")
        XCTAssertEqual(editor.editorMessage, .addFailed)
        XCTAssertTrue(editor.undoStack.isEmpty)
        XCTAssertEqual(editor.project, project)
        let liveWorkspaces = await store.liveWorkspaceCount
        XCTAssertEqual(liveWorkspaces, 0)
        XCTAssertTrue(workspaceEntries().isEmpty)
        XCTAssertFalse(gate.isHeld)
    }

    func testDeletionBeforeReplaceStopsBeforeMaterialisation() async throws {
        let project = try await makeProject(withClips: true)
        let editor = try await makeEditor(project)
        editor.select(project.clips[1].id)
        XCTAssertTrue(editor.canReplaceSelectedClip)
        let filesBefore = mediaFiles(project.id)
        let home = makeHome(deleting: project)

        let holder = try await holdGate()
        let deletion = Task { await home.confirmDeletion() }
        try await waitUntil("deletion queued") { gate.waitingCount == 1 }
        let replace = Task { await editor.replaceSelectedClip() }
        try await waitUntil("replace validated and queued") { gate.waitingCount == 2 }
        await holder.release()
        await deletion.value
        let replaced = await replace.value

        XCTAssertNil(replaced)
        XCTAssertNil(try repository.project(id: project.id))
        XCTAssertEqual(mediaFiles(project.id), filesBefore, "no replacement file materialised")
        XCTAssertEqual(editor.editorMessage, .replaceFailed)
        XCTAssertEqual(editor.project, project)
        XCTAssertTrue(editor.undoStack.isEmpty)
        XCTAssertFalse(gate.isHeld)
    }

    // MARK: Navigation while a deletion waits

    /// The Recent alert's flow: the deleted Project was opened earlier (so `openedProject` matches) and
    /// the user is back on Recent when confirming. `navigate` runs while the deletion waits in the gate.
    private func deleteWhileNavigating(_ navigate: (HomeModel, VlogProject, VlogProject) -> Void) async throws -> (home: HomeModel, deleted: VlogProject, other: VlogProject) {
        let deleted = try await makeProject(withClips: false)
        let other = try await makeProject(withClips: false)
        let home = HomeModel(repository: repository, router: AppRouter(), lifecycle: gate)
        home.loadRecent()
        home.openProject(id: deleted.id)
        home.router.path = [.recent]
        XCTAssertEqual(home.openedProject?.id, deleted.id)

        let holder = try await holdGate()
        let deletion = Task { await home.delete(deleted) }
        try await waitUntil("deletion queued") { gate.waitingCount == 1 }
        navigate(home, deleted, other)
        await holder.release()
        await deletion.value

        XCTAssertNil(try repository.project(id: deleted.id), "the captured Project was deleted")
        XCTAssertNotNil(try repository.project(id: other.id))
        XCTAssertNil(home.failure)
        return (home, deleted, other)
    }

    func testUnchangedNavigationStillLeavesTheDeletedProjectAsBefore() async throws {
        let r = try await deleteWhileNavigating { _, _, _ in }
        XCTAssertEqual(r.home.router.path, [.recent])
        XCTAssertNil(r.home.openedProject)
    }

    func testUnrelatedNavigationDuringTheWaitIsNotReset() async throws {
        let r = try await deleteWhileNavigating { home, _, _ in home.showProjects() }
        XCTAssertEqual(r.home.router.path, [.projectsEntry], "a later, unrelated navigation is kept")
        XCTAssertNil(r.home.openedProject)
    }

    func testOpeningAnotherProjectDuringTheWaitIsKept() async throws {
        let r = try await deleteWhileNavigating { home, _, other in home.openProject(id: other.id) }
        XCTAssertEqual(r.home.router.path, [.recent, .camera(r.other.id)])
        XCTAssertEqual(r.home.openedProject?.id, r.other.id)
    }

    func testNavigationIntoTheDeletedProjectDuringTheWaitIsLeft() async throws {
        let r = try await deleteWhileNavigating { home, deleted, _ in home.openProject(id: deleted.id) }
        XCTAssertEqual(r.home.router.path, [.recent], "still navigates away from the deleted Project")
        XCTAssertNil(r.home.openedProject)
    }

    // MARK: Add / Replace wins

    func testAddWinningMakesDeletionWaitForTheWholeProtectedSection() async throws {
        let project = try await makeProject(withClips: false)
        var observed: (projectPresent: Bool, held: Bool, waiting: Int)?
        let repository = self.repository!
        let gate = self.gate!
        let editor = try await makeEditor(project) {
            observed = ((try? repository.project(id: project.id)) != nil, gate.isHeld, gate.waitingCount)
        }
        let home = makeHome(deleting: project)

        let holder = try await holdGate()
        let add = Task { await editor.addClips() }
        try await waitUntil("add validated and queued") { gate.waitingCount == 1 }
        let deletion = Task { await home.confirmDeletion() }
        try await waitUntil("deletion queued") { gate.waitingCount == 2 }
        await holder.release()
        let added = await add.value
        await deletion.value

        let seen = try XCTUnwrap(observed, "materialised inside the protected section")
        XCTAssertTrue(seen.projectPresent, "deletion had not run when the batch was materialised")
        XCTAssertTrue(seen.held)
        XCTAssertEqual(seen.waiting, 1, "deletion queued behind the protected section")
        XCTAssertEqual(added, 1, "the commit landed before the deletion ran")
        XCTAssertEqual(editor.undoStack.count, 1)
        XCTAssertNil(home.failure)
        XCTAssertNil(try repository.project(id: project.id), "deletion ran afterwards")
        XCTAssertFalse(gate.isHeld)
    }

    func testReplaceWinningMakesDeletionWait() async throws {
        let project = try await makeProject(withClips: true)
        var projectPresentAtMaterialize: Bool?
        let repository = self.repository!
        let editor = try await makeEditor(project) { projectPresentAtMaterialize = (try? repository.project(id: project.id)) != nil }
        editor.select(project.clips[1].id)
        let home = makeHome(deleting: project)

        let holder = try await holdGate()
        let replace = Task { await editor.replaceSelectedClip() }
        try await waitUntil("replace queued") { gate.waitingCount == 1 }
        let deletion = Task { await home.confirmDeletion() }
        try await waitUntil("deletion queued") { gate.waitingCount == 2 }
        await holder.release()
        let replaced = await replace.value
        await deletion.value

        XCTAssertNotNil(replaced)
        XCTAssertEqual(projectPresentAtMaterialize, true)
        XCTAssertEqual(editor.undoStack.map(\.kind), [.replace])
        XCTAssertNil(try repository.project(id: project.id))
    }

    // MARK: Replace target invalidation

    func testReplaceTargetNoLongerActiveInTheStoreStopsBeforeMaterialisation() async throws {
        let project = try await makeProject(withClips: true)
        let editor = try await makeEditor(project)
        let target = project.clips[1].id
        editor.select(target)
        let filesBefore = mediaFiles(project.id)

        let holder = try await holdGate()
        let replace = Task { await editor.replaceSelectedClip() }
        try await waitUntil("replace queued") { gate.waitingCount == 1 }
        // A serialized writer (the test holds the gate) makes the target pending-deleted in the store.
        var changed = project
        try changed.deleteClip(id: target, deletedAt: .now)
        try repository.update(changed)
        await holder.release()
        let replaced = await replace.value

        XCTAssertNil(replaced)
        XCTAssertEqual(editor.editorMessage, .replaceFailed)
        XCTAssertEqual(mediaFiles(project.id), filesBefore, "nothing materialised")
        XCTAssertEqual(try repository.project(id: project.id), changed, "store left exactly as the other writer saved it")
        XCTAssertEqual(editor.project, project)
        XCTAssertTrue(editor.undoStack.isEmpty)
        XCTAssertFalse(gate.isHeld)
    }

    // MARK: Startup cleanup shares the gate

    func testAddWaitsBehindStartupRecoveryOnTheSameGate() async throws {
        let project = try await makeProject(withClips: false)
        let editor = try await makeEditor(project)
        let recovery = ProjectStartupRecoveryCoordinator(repository: repository, store: store, lifecycle: gate, isEditorSessionLive: { _ in true })
        var resume: CheckedContinuation<Void, Never>?
        recovery.debugHold = { await withCheckedContinuation { resume = $0 } }

        let recovering = Task { await recovery.recoverOrphans() }
        try await waitUntil("recovery inside the gate") { resume != nil }
        let add = Task { await editor.addClips() }
        try await waitUntil("add queued behind recovery") { gate.waitingCount == 1 }
        XCTAssertTrue(mediaFiles(project.id).isEmpty, "nothing materialised while recovery holds the gate")
        resume?.resume()
        _ = await recovering.value
        let added = await add.value

        XCTAssertEqual(added, 1)
        XCTAssertEqual(mediaFiles(project.id).count, 1)
        XCTAssertFalse(gate.isHeld)
    }

    func testStartupWorkspaceSweepOnTheSameGateSparesAQueuedAddsLiveWorkspace() async throws {
        let project = try await makeProject(withClips: false)
        let editor = try await makeEditor(project)
        let recovery = ProjectStartupRecoveryCoordinator(repository: repository, store: store, lifecycle: gate, isEditorSessionLive: { _ in true })
        // A genuinely abandoned canonical workspace, so the sweep demonstrably runs.
        let abandoned = root.appendingPathComponent("ProjectWorkspace/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)

        let holder = try await holdGate()
        let sweep = Task { await recovery.sweepAbandonedWorkspaces() }
        try await waitUntil("sweep queued") { gate.waitingCount == 1 }
        let add = Task { await editor.addClips() }
        try await waitUntil("add validated and queued behind the sweep") { gate.waitingCount == 2 }
        await holder.release()
        let report = await sweep.value
        let added = await add.value

        XCTAssertEqual(report.workspacesRemoved, 1, "only the abandoned workspace")
        XCTAssertEqual(report.noncanonicalPreserved, 1, "the queued Add's live workspace is reported live and kept")
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertEqual(added, 1, "the Add's sources survived the sweep and were committed")
        XCTAssertEqual(mediaFiles(project.id).count, 1)
        XCTAssertTrue(workspaceEntries().isEmpty)
    }

    // MARK: Failure / cancellation release the gate

    func testDeletionFailureReleasesTheGate() async throws {
        let project = try VlogProject(orientation: .portrait9x16)   // never saved: deletion throws
        let home = makeHome(deleting: project)
        await home.confirmDeletion()
        XCTAssertEqual(home.failure, .deletion)
        XCTAssertFalse(gate.isHeld)
        XCTAssertEqual(gate.waitingCount, 0)
    }

    func testMaterialisationFailureInsideTheGateReleasesIt() async throws {
        let project = try await makeProject(withClips: false)
        // A regular file where the Project directory would go: materialisation fails inside the gate.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        try Data([1]).write(to: projectDirectory(project.id))
        let editor = try await makeEditor(project)

        let added = await editor.addClips()

        XCTAssertEqual(added, 0)
        XCTAssertEqual(editor.editorMessage, .addFailed)
        XCTAssertFalse(gate.isHeld)
        let home = makeHome(deleting: project)
        await home.confirmDeletion()
        XCTAssertNil(home.failure, "the gate is usable again")
    }

    func testCommitFailurePreservesTheBatchAndReleasesTheGate() async throws {
        let project = try await makeProject(withClips: false)
        let failing = FailableProjectRepository()
        try failing.create(project)
        failing.updateFails = true
        let editor = try await makeEditor(project, repository: failing)

        let added = await editor.addClips()

        XCTAssertEqual(added, 0)
        XCTAssertEqual(mediaFiles(project.id).count, 1, "after a save attempt the batch is preserved (ADR-050 050-D D8.0)")
        XCTAssertFalse(gate.isHeld)
        XCTAssertEqual(gate.waitingCount, 0)
    }

    func testCancelledQueuedOperationsStillReleaseTheGate() async throws {
        let project = try await makeProject(withClips: false)
        let editor = try await makeEditor(project)
        let other = try await makeProject(withClips: false)
        let home = makeHome(deleting: other)

        let holder = try await holdGate()
        let add = Task { await editor.addClips() }
        try await waitUntil("add queued") { gate.waitingCount == 1 }
        let deletion = Task { await home.confirmDeletion() }
        try await waitUntil("deletion queued") { gate.waitingCount == 2 }
        add.cancel()
        deletion.cancel()
        await holder.release()
        let added = await add.value
        await deletion.value

        // No cancellation policy is added: a queued section that is reached runs to completion and releases.
        XCTAssertEqual(added, 1)
        XCTAssertNil(try repository.project(id: other.id))
        XCTAssertFalse(gate.isHeld)
        XCTAssertEqual(gate.waitingCount, 0)
    }

    // MARK: No nested acquisition

    func testProtectedSectionsNeverReacquireTheGate() async throws {
        let project = try await makeProject(withClips: true)
        var waitingInside: [Int] = []
        let gate = self.gate!
        let editor = try await makeEditor(project) { waitingInside.append(gate.waitingCount) }
        let home = HomeModel(repository: repository, router: AppRouter(), lifecycle: gate)

        // A nested acquisition would self-deadlock (the lock is not reentrant), so completion within a
        // bounded wait IS the assertion; the work is not awaited directly so a hang fails instead of stalling.
        var results: (added: Int, replaced: UUID?)?
        let work = Task { @MainActor in
            let added = await editor.addClips()
            editor.select(project.clips[1].id)
            let replaced = await editor.replaceSelectedClip()
            await home.delete(editor.project)
            results = (added, replaced)
        }
        try await waitUntil("every protected section completed without self-deadlock") { results != nil }
        guard let results else { return work.cancel() }

        XCTAssertEqual(results.added, 1)
        XCTAssertNotNil(results.replaced)
        XCTAssertEqual(waitingInside, [0, 0], "nothing queued behind the sections")
        XCTAssertNil(home.failure)
        XCTAssertFalse(gate.isHeld)
        XCTAssertEqual(gate.waitingCount, 0)
    }
}
