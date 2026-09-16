import Foundation
import SwiftData
import XCTest
@testable import Mellow

// MARK: - Doubles

/// Which Projects currently have a live Editor session (the router's role in production).
@MainActor
final class LiveEditorSessions {
    var live: Set<UUID> = []
    func isLive(_ id: UUID) -> Bool { live.contains(id) }
}

/// Main-Actor mutable cell for values written from a detached Task in a test.
@MainActor
final class Cell<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Never busy: the fake thumbnail provider reads no media.
struct IdleConsumers: ProjectMediaConsumerGating {
    func awaitIdle(for paths: Set<RelativeMediaPath>, timeout: Duration) async -> Bool { true }
}

/// Cleanup store wrapper: injectable removal failure per path and an optional hold that suspends the
/// first removal until released (drives the Editor-open race deterministically).
actor FailableCleanupStore: ProjectMediaCleanupStoring {
    private let inner: ProjectMediaStore
    var failingPaths: Set<RelativeMediaPath> = []
    private var holdRemoval = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var enteredRemoval: [CheckedContinuation<Void, Never>] = []
    private(set) var removalAttempts: [RelativeMediaPath] = []

    init(_ inner: ProjectMediaStore) { self.inner = inner }

    func setFailing(_ paths: Set<RelativeMediaPath>) { failingPaths = paths }
    func setHold(_ hold: Bool) { holdRemoval = hold }
    func release() { for waiter in held { waiter.resume() }; held.removeAll(); holdRemoval = false }
    /// Suspends until a removal has entered this store (and is held there).
    func waitUntilRemovalEntered() async {
        guard removalAttempts.isEmpty else { return }
        await withCheckedContinuation { enteredRemoval.append($0) }
    }

    func removeCommittedMedia(_ path: RelativeMediaPath, projectID: UUID, clipID: UUID) async throws {
        removalAttempts.append(path)
        for waiter in enteredRemoval { waiter.resume() }
        enteredRemoval.removeAll()
        if holdRemoval { await withCheckedContinuation { held.append($0) } }
        if failingPaths.contains(path) { throw ProjectMediaStoreError.removalFailed }
        try await inner.removeCommittedMedia(path, projectID: projectID, clipID: clipID)
    }

    func fileExists(_ path: RelativeMediaPath) async -> Bool { await inner.fileExists(path) }
}

/// Repository wrapper that can fail `finalizeDeletedClip` and lets a test probe the filesystem at the
/// exact moment metadata is finalized (file-first ordering proof).
@MainActor
final class ProbingRepository: ProjectRepository {
    let inner: any ProjectRepository
    var finalizeFails = false
    var onFinalize: ((UUID) -> Void)?
    private(set) var finalizeCalls: [UUID] = []
    private(set) var updateCount = 0
    struct Failure: Error {}

    init(_ inner: any ProjectRepository) { self.inner = inner }

    func create(_ project: VlogProject) throws { try inner.create(project) }
    func project(id: UUID) throws -> VlogProject? { try inner.project(id: id) }
    func recentProjects() throws -> [VlogProject] { try inner.recentProjects() }
    func update(_ project: VlogProject) throws { updateCount += 1; try inner.update(project) }
    func finalizeDeletedClip(projectID: UUID, clipID: UUID) throws {
        finalizeCalls.append(clipID)
        onFinalize?(clipID)
        if finalizeFails { throw Failure() }
        try inner.finalizeDeletedClip(projectID: projectID, clipID: clipID)
    }
    func deleteProject(id: UUID) throws { try inner.deleteProject(id: id) }
}

// MARK: - Tests

@MainActor
final class ProjectMediaCleanupCoordinatorTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!

    override func setUp() {
        root = TestSupport.temporaryRoot("cleanup")
        store = ProjectMediaStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// A canonical committed Clip with a small placeholder file behind it (cleanup never decodes).
    private func committedClip(projectID: UUID, order: Int, seconds: Int64 = 2, withFile: Bool = true, path: RelativeMediaPath? = nil) async throws -> VlogClip {
        let clipID = UUID()
        let canonical = try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID)
        if withFile {
            let url = await store.url(for: canonical)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: 256).write(to: url)
        }
        return try VlogClip(
            id: clipID, projectID: projectID, sourceKind: .imported, mediaRelativePath: path ?? canonical,
            sourceDuration: .seconds(seconds), trimDuration: .seconds(seconds), sortOrder: order
        )
    }

    private func makeProject(clipCount: Int, withFiles: Bool = true) async throws -> VlogProject {
        let id = UUID()
        var clips: [VlogClip] = []
        for order in 0..<clipCount { clips.append(try await committedClip(projectID: id, order: order, withFile: withFiles)) }
        return try VlogProject(id: id, orientation: .portrait9x16, clips: clips)
    }

    private struct Harness {
        let repository: ProbingRepository
        let cleanupStore: FailableCleanupStore
        let sessions: LiveEditorSessions
        let gate: ProjectLifecycleOperationGate
        let coordinator: ProjectMediaCleanupCoordinator
    }

    private func makeHarness(
        repository: (any ProjectRepository)? = nil,
        consumers: (any ProjectMediaConsumerGating)? = nil,
        timeout: Duration = .seconds(2)
    ) -> Harness {
        let probing = ProbingRepository(repository ?? InMemoryProjectRepository())
        let cleanupStore = FailableCleanupStore(store)
        let sessions = LiveEditorSessions()
        let gate = ProjectLifecycleOperationGate()
        let coordinator = ProjectMediaCleanupCoordinator(
            repository: probing,
            mediaStore: cleanupStore,
            consumers: consumers ?? IdleConsumers(),
            lifecycle: gate,
            isEditorSessionLive: { sessions.isLive($0) },
            policy: ProjectMediaCleanupPolicy(consumerWaitTimeout: timeout)
        )
        return Harness(repository: probing, cleanupStore: cleanupStore, sessions: sessions, gate: gate, coordinator: coordinator)
    }

    private func exists(_ path: RelativeMediaPath) async -> Bool { await store.fileExists(path) }

    /// Polls a Main-Actor condition without blocking the actor (each iteration yields).
    private func eventually(_ timeout: Duration = .seconds(3), _ condition: @MainActor () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() { return true }
            try? await clock.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    // MARK: 20. Delete lifecycle through the real Editor model

    func testDeleteLifecycleCleansOnlyAtSessionEndFileFirst() async throws {
        let project = try await makeProject(clipCount: 3)
        let h = makeHarness()
        try h.repository.create(project)
        let (a, b, c) = (project.clips[0], project.clips[1], project.clips[2])
        h.sessions.live = [project.id]
        let editor = ProjectEditorModel(project: project, repository: h.repository, thumbnails: FakeClipThumbnailProvider())

        editor.select(b.id)
        XCTAssertTrue(editor.deleteSelectedClip())
        XCTAssertEqual(editor.orderedClips.map(\.id), [a.id, c.id])
        XCTAssertEqual(try h.repository.project(id: project.id)?.deletedClips.map(\.id), [b.id], "B pending, durable")

        // Live Editor: a pass evaluates nothing and touches nothing.
        var report = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertTrue(report.skippedForLiveEditor)
        XCTAssertEqual(report.pendingCount, 0)
        XCTAssertTrue(h.repository.finalizeCalls.isEmpty)
        let existsPending = await exists(b.mediaRelativePath)
        XCTAssertTrue(existsPending, "B file stays while the Editor is live")

        XCTAssertTrue(editor.undo())
        XCTAssertEqual(editor.orderedClips.map(\.id), [a.id, b.id, c.id])
        XCTAssertTrue(try h.repository.project(id: project.id)?.deletedClips.isEmpty ?? false)
        _ = await h.coordinator.reconcile(projectID: project.id)
        let existsRestored = await exists(b.mediaRelativePath)
        XCTAssertTrue(existsRestored, "no cleanup after Undo")

        XCTAssertTrue(editor.redo())
        XCTAssertEqual(try h.repository.project(id: project.id)?.deletedClips.map(\.id), [b.id])
        report = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertTrue(report.skippedForLiveEditor)
        let existsRedone = await exists(b.mediaRelativePath)
        XCTAssertTrue(existsRedone, "Redo → pending again, file still protected by the live session")

        // Session boundary: the Editor route is gone; the pass runs file-first.
        h.sessions.live = []
        var fileExistedAtFinalize: Bool?
        let bPath = b.mediaRelativePath, rootURL = root!
        h.repository.onFinalize = { _ in fileExistedAtFinalize = FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(bPath.value).path) }
        report = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertFalse(report.skippedForLiveEditor)
        XCTAssertEqual(report.pendingCount, 1)
        XCTAssertEqual(report.removedFiles, [b.id])
        XCTAssertEqual(report.finalized, [b.id])
        XCTAssertTrue(report.deferred.isEmpty)
        XCTAssertEqual(fileExistedAtFinalize, false, "metadata is finalized only after the file is gone")
        let existsAfter = await exists(b.mediaRelativePath)
        XCTAssertFalse(existsAfter)
        let existsA = await exists(a.mediaRelativePath), existsC = await exists(c.mediaRelativePath)
        XCTAssertTrue(existsA && existsC, "active media untouched")

        // Reopen: A C, B absent, history empty.
        let reopened = try XCTUnwrap(try h.repository.project(id: project.id))
        XCTAssertEqual(reopened.clips.map(\.id), [a.id, c.id])
        XCTAssertTrue(reopened.deletedClips.isEmpty)
        let editor2 = ProjectEditorModel(project: reopened, repository: h.repository, thumbnails: FakeClipThumbnailProvider())
        XCTAssertFalse(editor2.canUndo); XCTAssertFalse(editor2.canRedo)
    }

    // MARK: 21 / 22. Undone Add lifecycle and Redo invalidation

    private func makeAddEditor(_ h: Harness, project: VlogProject) async throws -> ProjectEditorModel {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let selector = FakeProjectMediaSelector(script: .fixtures([fixture]))
        let appender = ProjectClipAppendCoordinator(mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()), storage: FakeProjectStorageGate(verdict: .sufficient))
        let acquisition = EditorClipAcquisition(mediaStore: store, mediaSelector: selector, storageGate: FakeProjectStorageGate(verdict: .sufficient), appender: appender)
        return ProjectEditorModel(project: project, repository: h.repository, thumbnails: FakeClipThumbnailProvider(), acquisition: acquisition)
    }

    func testUndoneAddIsCleanedOnlyAfterSessionEnd() async throws {
        let project = try await makeProject(clipCount: 2)
        let h = makeHarness()
        try h.repository.create(project)
        h.sessions.live = [project.id]
        let editor = try await makeAddEditor(h, project: project)
        let (a, b) = (project.clips[0].id, project.clips[1].id)

        let added = await editor.addClips()
        XCTAssertEqual(added, 1)
        let c = try XCTUnwrap(editor.orderedClips.last)
        XCTAssertEqual(editor.orderedClips.map(\.id), [a, b, c.id])
        let cExists = await exists(c.mediaRelativePath)
        XCTAssertTrue(cExists)

        XCTAssertTrue(editor.undo())
        XCTAssertEqual(editor.orderedClips.map(\.id), [a, b])
        XCTAssertEqual(try h.repository.project(id: project.id)?.deletedClips.map(\.id), [c.id], "C pending, Redo available")
        XCTAssertTrue(editor.canRedo)
        _ = await h.coordinator.reconcile(projectID: project.id)
        let cStill = await exists(c.mediaRelativePath)
        XCTAssertTrue(cStill, "file protected while the Editor is live")

        XCTAssertTrue(editor.redo())
        XCTAssertEqual(editor.orderedClips.map(\.id), [a, b, c.id], "C returns exactly")
        XCTAssertEqual(editor.orderedClips.last?.mediaRelativePath, c.mediaRelativePath)
        XCTAssertTrue(editor.undo())
        XCTAssertEqual(try h.repository.project(id: project.id)?.deletedClips.map(\.id), [c.id])

        h.sessions.live = []
        let report = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertEqual(report.removedFiles, [c.id]); XCTAssertEqual(report.finalized, [c.id])
        let cGone = await exists(c.mediaRelativePath)
        XCTAssertFalse(cGone)
        let reopened = try XCTUnwrap(try h.repository.project(id: project.id))
        XCTAssertEqual(reopened.clips.map(\.id), [a, b]); XCTAssertTrue(reopened.deletedClips.isEmpty)
        let existsA = await exists(project.clips[0].mediaRelativePath)
        XCTAssertTrue(existsA)
    }

    func testRedoInvalidationDoesNotCleanInsideSession() async throws {
        let project = try await makeProject(clipCount: 2)
        let h = makeHarness()
        try h.repository.create(project)
        h.sessions.live = [project.id]
        let editor = try await makeAddEditor(h, project: project)
        let (a, b) = (project.clips[0].id, project.clips[1].id)
        let added = await editor.addClips()
        XCTAssertEqual(added, 1)
        let c = try XCTUnwrap(editor.orderedClips.last)
        XCTAssertTrue(editor.undo())
        XCTAssertTrue(editor.canRedo)

        // New edit clears Redo: C is logically unreachable, but still not cleaned in-session.
        XCTAssertNotNil(editor.moveClipLater(id: a))
        XCTAssertFalse(editor.canRedo)
        XCTAssertEqual(editor.orderedClips.map(\.id), [b, a])
        XCTAssertEqual(try h.repository.project(id: project.id)?.deletedClips.map(\.id), [c.id], "still durable pending")
        let report1 = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertTrue(report1.skippedForLiveEditor)
        let cStill = await exists(c.mediaRelativePath)
        XCTAssertTrue(cStill, "eligibility changed in-session; IO waits for the boundary")

        h.sessions.live = []
        let report2 = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertEqual(report2.finalized, [c.id])
        let cGone = await exists(c.mediaRelativePath)
        XCTAssertFalse(cGone)
        XCTAssertEqual(try h.repository.project(id: project.id)?.clips.map(\.id), [b, a], "the reorder survives cleanup")
    }

    // MARK: 23. Process / crash reconciliation (InMemory)

    func testPendingWithFileIsRemovedThenFinalized() async throws {
        var project = try await makeProject(clipCount: 2)
        let h = makeHarness()
        try h.repository.create(project)
        let victim = project.clips[1]
        try project.deleteClip(id: victim.id)
        try h.repository.update(project)

        let reports = await h.coordinator.reconcileAll()
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].removedFiles, [victim.id]); XCTAssertEqual(reports[0].finalized, [victim.id])
        let gone = await exists(victim.mediaRelativePath)
        XCTAssertFalse(gone)
        XCTAssertTrue(try h.repository.project(id: project.id)?.deletedClips.isEmpty ?? false)
    }

    func testPendingWithMissingFileFinalizesMetadataOnly() async throws {
        let id = UUID()
        let active = try await committedClip(projectID: id, order: 0)
        let pending = try await committedClip(projectID: id, order: 1, withFile: false)
        var project = try VlogProject(id: id, orientation: .portrait9x16, clips: [active, pending])
        let h = makeHarness()
        try h.repository.create(project)
        try project.deleteClip(id: pending.id)
        try h.repository.update(project)

        let report = await h.coordinator.reconcile(projectID: id)
        XCTAssertEqual(report.alreadyAbsent, [pending.id])
        XCTAssertTrue(report.removedFiles.isEmpty)
        XCTAssertEqual(report.finalized, [pending.id])
        XCTAssertTrue(report.deferred.isEmpty)
        let reopened = try XCTUnwrap(try h.repository.project(id: id))
        XCTAssertEqual(reopened.clips.map(\.id), [active.id]); XCTAssertTrue(reopened.deletedClips.isEmpty)
        XCTAssertEqual(h.repository.finalizeCalls, [pending.id])
    }

    func testFinalizeFailureLeavesRowPendingAndNextPassFinalizes() async throws {
        var project = try await makeProject(clipCount: 2)
        let h = makeHarness()
        try h.repository.create(project)
        let victim = project.clips[1]
        try project.deleteClip(id: victim.id)
        try h.repository.update(project)
        h.repository.finalizeFails = true

        let first = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertEqual(first.removedFiles, [victim.id])
        XCTAssertEqual(first.deferred, [victim.id: .finalizeFailed])
        XCTAssertTrue(first.finalized.isEmpty)
        let gone = await exists(victim.mediaRelativePath)
        XCTAssertFalse(gone, "file step completed")
        XCTAssertEqual(try h.repository.project(id: project.id)?.deletedClips.map(\.id), [victim.id], "row still pending → discoverable")

        h.repository.finalizeFails = false
        let second = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertEqual(second.alreadyAbsent, [victim.id]); XCTAssertEqual(second.finalized, [victim.id])
        XCTAssertTrue(try h.repository.project(id: project.id)?.deletedClips.isEmpty ?? false)
    }

    func testRemovalFailureKeepsMetadataPending() async throws {
        var project = try await makeProject(clipCount: 2)
        let h = makeHarness()
        try h.repository.create(project)
        let victim = project.clips[1]
        try project.deleteClip(id: victim.id)
        try h.repository.update(project)
        await h.cleanupStore.setFailing([victim.mediaRelativePath])

        let report = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertEqual(report.deferred, [victim.id: .removalFailed])
        XCTAssertTrue(report.finalized.isEmpty)
        XCTAssertTrue(h.repository.finalizeCalls.isEmpty, "never finalize over a surviving file")
        let stays = await exists(victim.mediaRelativePath)
        XCTAssertTrue(stays)
        XCTAssertEqual(try h.repository.project(id: project.id)?.deletedClips.map(\.id), [victim.id])
    }

    func testRerunAfterCompleteCleanupIsIdempotent() async throws {
        var project = try await makeProject(clipCount: 2)
        let h = makeHarness()
        try h.repository.create(project)
        let victim = project.clips[1]
        try project.deleteClip(id: victim.id)
        try h.repository.update(project)
        _ = await h.coordinator.reconcile(projectID: project.id)
        let calls = h.repository.finalizeCalls.count

        let again = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertEqual(again.pendingCount, 0)
        XCTAssertTrue(again.finalized.isEmpty && again.deferred.isEmpty && again.removedFiles.isEmpty)
        XCTAssertEqual(h.repository.finalizeCalls.count, calls, "nothing to do, nothing done")
        let all = await h.coordinator.reconcileAll()
        XCTAssertEqual(all.map(\.pendingCount), [0])
        _ = await h.coordinator.reconcile(projectID: UUID())   // unknown Project: no failure
    }

    // MARK: 24. Active + missing media is never touched

    func testActiveClipWithMissingFileIsNeverFinalized() async throws {
        let id = UUID()
        let present = try await committedClip(projectID: id, order: 0)
        let missing = try await committedClip(projectID: id, order: 1, withFile: false)
        let project = try VlogProject(id: id, orientation: .portrait9x16, clips: [present, missing])
        let h = makeHarness()
        try h.repository.create(project)
        let before = try h.repository.project(id: id)

        let report = await h.coordinator.reconcile(projectID: id)
        XCTAssertEqual(report.pendingCount, 0)
        XCTAssertTrue(report.finalized.isEmpty && report.deferred.isEmpty)
        XCTAssertTrue(h.repository.finalizeCalls.isEmpty, "no finalize call")
        XCTAssertEqual(h.repository.updateCount, 0, "no mutation")
        XCTAssertEqual(try h.repository.project(id: id), before, "row remains active, untouched")
        let attempts = await h.cleanupStore.removalAttempts
        XCTAssertTrue(attempts.isEmpty)
    }

    // MARK: 25. Thumbnail consumer gate with the real service

    private func realCommittedClip(projectID: UUID, order: Int) async throws -> VlogClip {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let workspace = try await store.beginWorkspace()
        let adopted = try await store.adopt(try TestSupport.transferCopy(of: fixture), into: workspace)
        let clipID = UUID()
        let path = try await store.materialize(adopted, projectID: projectID, clipID: clipID)
        await store.discard(workspace)
        return try VlogClip(id: clipID, projectID: projectID, sourceKind: .imported, mediaRelativePath: path, sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: order)
    }

    func testCleanupWaitsForInFlightThumbnailThenRemovesAndFinalizes() async throws {
        let id = UUID()
        let keep = try await realCommittedClip(projectID: id, order: 0)
        let victim = try await realCommittedClip(projectID: id, order: 1)
        var project = try VlogProject(id: id, orientation: .portrait9x16, clips: [keep, victim])
        let generator = CountingThumbnailGenerator(gated: true)
        let service = ClipThumbnailService(resolver: store, generator: generator)
        let h = makeHarness(consumers: service, timeout: .seconds(5))
        try h.repository.create(project)
        try project.deleteClip(id: victim.id)
        try h.repository.update(project)

        // A generation for the victim's media is in flight (the file is being read).
        let request = ClipThumbnailRequest(clip: victim, maximumPixelSize: ClipThumbnailPixelSize(width: 54, height: 96))
        let generation = Task { try await service.thumbnail(for: request) }
        await generator.waitUntilStarted()
        let inFlight = await service.inFlightCount
        XCTAssertEqual(inFlight, 1)

        let pass = Task { await h.coordinator.reconcile(projectID: id) }
        // Give the pass every chance to (wrongly) proceed: it must still be waiting on the reader.
        try await Task.sleep(for: .milliseconds(300))
        let stillThere = await exists(victim.mediaRelativePath)
        XCTAssertTrue(stillThere, "cleanup waits while the media is actively read")
        XCTAssertTrue(h.repository.finalizeCalls.isEmpty)

        await generator.release()
        _ = try await generation.value
        let report = await pass.value
        XCTAssertEqual(report.removedFiles, [victim.id]); XCTAssertEqual(report.finalized, [victim.id])
        let gone = await exists(victim.mediaRelativePath)
        XCTAssertFalse(gone)
        let keepExists = await exists(keep.mediaRelativePath)
        XCTAssertTrue(keepExists)
    }

    func testBusyConsumerPastBoundedWaitDefersWithoutHangingAndRetriesLater() async throws {
        let id = UUID()
        let keep = try await realCommittedClip(projectID: id, order: 0)
        let victim = try await realCommittedClip(projectID: id, order: 1)
        var project = try VlogProject(id: id, orientation: .portrait9x16, clips: [keep, victim])
        let generator = CountingThumbnailGenerator(gated: true)
        let service = ClipThumbnailService(resolver: store, generator: generator)
        let h = makeHarness(consumers: service, timeout: .milliseconds(200))
        try h.repository.create(project)
        try project.deleteClip(id: victim.id)
        try h.repository.update(project)
        let request = ClipThumbnailRequest(clip: victim, maximumPixelSize: ClipThumbnailPixelSize(width: 54, height: 96))
        let generation = Task { try await service.thumbnail(for: request) }
        await generator.waitUntilStarted()

        let clock = ContinuousClock()
        let started = clock.now
        let report = await h.coordinator.reconcile(projectID: id)
        XCTAssertLessThan(clock.now - started, .seconds(3), "bounded: the pass returns")
        XCTAssertEqual(report.deferred, [victim.id: .consumerBusy])
        XCTAssertTrue(report.finalized.isEmpty)
        XCTAssertTrue(h.repository.finalizeCalls.isEmpty)
        let retained = await exists(victim.mediaRelativePath)
        XCTAssertTrue(retained, "file retained")
        XCTAssertEqual(try h.repository.project(id: id)?.deletedClips.map(\.id), [victim.id], "row pending")

        await generator.release()
        _ = try await generation.value
        let retry = await h.coordinator.reconcile(projectID: id)
        XCTAssertEqual(retry.finalized, [victim.id])
        let gone = await exists(victim.mediaRelativePath)
        XCTAssertFalse(gone)
    }

    func testAwaitIdleObservesOnlyRequestedPathsAndNeverReordersRequests() async throws {
        let id = UUID()
        let clip = try await realCommittedClip(projectID: id, order: 0)
        let generator = CountingThumbnailGenerator(gated: true)
        let service = ClipThumbnailService(resolver: store, generator: generator)
        let request = ClipThumbnailRequest(clip: clip, maximumPixelSize: ClipThumbnailPixelSize(width: 54, height: 96))
        let generation = Task { try await service.thumbnail(for: request) }
        await generator.waitUntilStarted()
        let other = try ProjectMediaStore.committedMediaPath(projectID: id, clipID: UUID())
        let idleOther = await service.awaitIdle(for: [other], timeout: .milliseconds(50))
        XCTAssertTrue(idleOther, "an unrelated path is idle")
        let busy = await service.awaitIdle(for: [clip.mediaRelativePath], timeout: .milliseconds(100))
        XCTAssertFalse(busy)
        let generations = await generator.generations
        XCTAssertEqual(generations, 1, "observing never starts or repeats generation")
        await generator.release()
        _ = try await generation.value
        let idleNow = await service.awaitIdle(for: [clip.mediaRelativePath], timeout: .milliseconds(50))
        XCTAssertTrue(idleNow)
        let cached = await service.cachedCount
        XCTAssertEqual(cached, 1, "a ready cached thumbnail is not an active consumer")
    }

    // MARK: 26. Multiple pending, failure isolation

    func testOneRemovalFailureDoesNotStopOrRevertTheOthers() async throws {
        var project = try await makeProject(clipCount: 4)
        let h = makeHarness()
        try h.repository.create(project)
        let (c, d, e) = (project.clips[1], project.clips[2], project.clips[3])
        for clip in [c, d, e] { try project.deleteClip(id: clip.id) }
        try h.repository.update(project)
        await h.cleanupStore.setFailing([c.mediaRelativePath])

        let first = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertEqual(first.pendingCount, 3)
        XCTAssertEqual(first.deferred, [c.id: .removalFailed])
        XCTAssertEqual(Set(first.finalized), [d.id, e.id])
        XCTAssertEqual(Set(first.removedFiles), [d.id, e.id])
        let cStays = await exists(c.mediaRelativePath), dGone = await exists(d.mediaRelativePath), eGone = await exists(e.mediaRelativePath)
        XCTAssertTrue(cStays); XCTAssertFalse(dGone); XCTAssertFalse(eGone)
        XCTAssertEqual(try h.repository.project(id: project.id)?.deletedClips.map(\.id), [c.id])

        await h.cleanupStore.setFailing([])
        let second = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertEqual(second.finalized, [c.id])
        let cGone = await exists(c.mediaRelativePath)
        XCTAssertFalse(cGone)
        XCTAssertEqual(try h.repository.project(id: project.id)?.clips.map(\.id), [project.clips[0].id])
        XCTAssertTrue(try h.repository.project(id: project.id)?.deletedClips.isEmpty ?? false)
    }

    // MARK: 27. Path safety

    func testNonCanonicalPendingPathsArePreservedNeverFinalized() async throws {
        let id = UUID()
        let active = try await committedClip(projectID: id, order: 0)
        let foreignProject = UUID(), foreignClip = UUID()
        let wrongProject = try await committedClip(projectID: id, order: 1, withFile: false, path: try ProjectMediaStore.committedMediaPath(projectID: foreignProject, clipID: foreignClip))
        let wrongClip = try await committedClip(projectID: id, order: 2, withFile: false, path: try ProjectMediaStore.committedMediaPath(projectID: id, clipID: foreignClip))
        let workspace = try await committedClip(projectID: id, order: 3, withFile: false, path: try RelativeMediaPath("ProjectWorkspace/\(UUID().uuidString)/x.mov"))
        // Traversal is unrepresentable by construction: the domain path type refuses it before any
        // Clip could ever persist it, so cleanup can never be handed one.
        XCTAssertThrowsError(try RelativeMediaPath("Projects/\(id.uuidString)/Media/../../../Recordings/x.mov"))
        XCTAssertThrowsError(try RelativeMediaPath("/Projects/\(id.uuidString)/Media/x.mov"))
        let arbitrary = try await committedClip(projectID: id, order: 4, withFile: false, path: try RelativeMediaPath("Recordings/staging.mov"))
        // Put real bytes at every one of those locations so a wrong deletion would be observable.
        for clip in [wrongProject, wrongClip, workspace, arbitrary] {
            let url = await store.url(for: clip.mediaRelativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 16).write(to: url)
        }
        let victims = [wrongProject, wrongClip, workspace, arbitrary]
        var project = try VlogProject(id: id, orientation: .portrait9x16, clips: [active] + victims)
        let h = makeHarness()
        try h.repository.create(project)
        for clip in victims { try project.deleteClip(id: clip.id) }
        try h.repository.update(project)

        let report = await h.coordinator.reconcile(projectID: id)
        XCTAssertEqual(report.pendingCount, 4)
        XCTAssertEqual(report.deferred, Dictionary(uniqueKeysWithValues: victims.map { ($0.id, ProjectCleanupDeferral.nonCanonicalPath) }))
        XCTAssertTrue(report.finalized.isEmpty)
        XCTAssertTrue(h.repository.finalizeCalls.isEmpty, "ownership unproven → metadata untouched")
        let attempts = await h.cleanupStore.removalAttempts
        XCTAssertTrue(attempts.isEmpty, "the store is never even asked")
        for clip in [wrongProject, wrongClip, workspace, arbitrary] {
            let stays = await exists(clip.mediaRelativePath)
            XCTAssertTrue(stays, "\(clip.mediaRelativePath.value) preserved")
        }
        XCTAssertEqual(try h.repository.project(id: id)?.deletedClips.count, 4)
    }

    func testStorePrimitiveRefusesNonCanonicalAndIsIdempotent() async throws {
        let projectID = UUID(), clipID = UUID()
        let canonical = try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID)
        let url = await store.url(for: canonical)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 2, count: 8).write(to: url)

        for bad in [
            try ProjectMediaStore.committedMediaPath(projectID: UUID(), clipID: clipID),
            try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: UUID()),
            try RelativeMediaPath("ProjectWorkspace/\(projectID.uuidString)/Media/\(clipID.uuidString).mov"),
            try RelativeMediaPath("Projects/\(projectID.uuidString)/Media/\(clipID.uuidString).mp4")
        ] {
            do {
                try await store.removeCommittedMedia(bad, projectID: projectID, clipID: clipID)
                XCTFail("\(bad.value) must be refused")
            } catch let error as ProjectMediaStoreError {
                XCTAssertEqual(error, .pathNotCanonical)
            }
        }
        let untouched = await store.fileExists(canonical)
        XCTAssertTrue(untouched)

        try await store.removeCommittedMedia(canonical, projectID: projectID, clipID: clipID)
        let gone = await store.fileExists(canonical)
        XCTAssertFalse(gone)
        try await store.removeCommittedMedia(canonical, projectID: projectID, clipID: clipID)   // missing = success
    }

    // MARK: 28. updatedAt is maintenance-neutral (InMemory + SwiftData)

    func testCleanupDoesNotBumpUpdatedAtInMemory() async throws {
        var project = try await makeProject(clipCount: 2)
        let h = makeHarness()
        try h.repository.create(project)
        let victim = project.clips[1]
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        try project.deleteClip(id: victim.id, deletedAt: fixed)
        try h.repository.update(project)
        XCTAssertEqual(try h.repository.project(id: project.id)?.updatedAt, fixed)

        let report = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertEqual(report.finalized, [victim.id])
        XCTAssertEqual(try h.repository.project(id: project.id)?.updatedAt, fixed, "cleanup is not an edit")
    }

    func testCleanupDoesNotBumpUpdatedAtSwiftData() async throws {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let container = try MellowModelContainer.makePersistentContainer(storeURL: storeURL)
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        var project = try await makeProject(clipCount: 2)
        try repository.create(project)
        let victim = project.clips[1]
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        try project.deleteClip(id: victim.id, deletedAt: fixed)
        try repository.update(project)
        let h = makeHarness(repository: repository)

        let report = await h.coordinator.reconcile(projectID: project.id)
        XCTAssertEqual(report.finalized, [victim.id])
        let reloaded = try XCTUnwrap(try repository.project(id: project.id))
        XCTAssertEqual(reloaded.updatedAt.timeIntervalSince1970, fixed.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(reloaded.deletedClips.isEmpty)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>()).count, 1)
        let gone = await exists(victim.mediaRelativePath)
        XCTAssertFalse(gone)
    }

    /// Crash-recovery through the real store: pending row persisted, process "dies" after the file
    /// removal, the next launch's startup pass finalizes it — and an active row with a missing file
    /// in the same Project stays exactly as it is.
    func testSwiftDataStartupReconcileRecoversInterruptedCleanupAndProtectsActiveRows() async throws {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let id = UUID()
        let active = try await committedClip(projectID: id, order: 0)
        let activeMissing = try await committedClip(projectID: id, order: 1, withFile: false)
        let pendingRemoved = try await committedClip(projectID: id, order: 2, withFile: false)
        let pendingPresent = try await committedClip(projectID: id, order: 3)
        var project = try VlogProject(id: id, orientation: .portrait9x16, clips: [active, activeMissing, pendingRemoved, pendingPresent])
        do {
            let container = try MellowModelContainer.makePersistentContainer(storeURL: storeURL)
            let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
            try repository.create(project)
            try project.deleteClip(id: pendingRemoved.id)
            try project.deleteClip(id: pendingPresent.id)
            try repository.update(project)
        }
        // "Relaunch": fresh container, startup reconcileAll.
        let container = try MellowModelContainer.makePersistentContainer(storeURL: storeURL)
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        let h = makeHarness(repository: repository)
        let reports = await h.coordinator.reconcileAll()
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].alreadyAbsent, [pendingRemoved.id])
        XCTAssertEqual(reports[0].removedFiles, [pendingPresent.id])
        XCTAssertEqual(Set(reports[0].finalized), [pendingRemoved.id, pendingPresent.id])
        let reloaded = try XCTUnwrap(try repository.project(id: id))
        XCTAssertEqual(reloaded.clips.map(\.id), [active.id, activeMissing.id], "active rows untouched, missing file or not")
        XCTAssertTrue(reloaded.deletedClips.isEmpty)
        let activeExists = await exists(active.mediaRelativePath)
        XCTAssertTrue(activeExists)
        // Second launch: nothing left, nothing fails.
        let again = await h.coordinator.reconcileAll()
        XCTAssertEqual(again.map(\.pendingCount), [0])
    }

    // MARK: 16. Editor-open serialization (deterministic race)

    func testEditorLoadWaitsForRunningCleanupAndCannotResurrectFinalizedClip() async throws {
        var project = try await makeProject(clipCount: 3)
        let h = makeHarness()
        try h.repository.create(project)
        let (a, b, victim) = (project.clips[0], project.clips[1], project.clips[2])
        try project.deleteClip(id: victim.id)
        try h.repository.update(project)
        await h.cleanupStore.setHold(true)

        // Cleanup starts and is held inside its critical section, mid-file-removal.
        let pass = Task { await h.coordinator.reconcile(projectID: project.id) }
        await h.cleanupStore.waitUntilRemovalEntered()
        XCTAssertTrue(h.gate.isHeld)

        // An Editor load attempts to read the Project the way ProjectEditorDestination does.
        let loaded = Cell<VlogProject?>(nil)
        let load = Task { @MainActor in
            loaded.value = try? await h.gate.withExclusiveAccess { try h.repository.project(id: project.id) }
        }
        let waited = await eventually(.milliseconds(300)) { h.gate.waitingCount == 1 }
        XCTAssertTrue(waited, "the load queues behind the cleanup")
        XCTAssertNil(loaded.value, "the load has not read an intermediate snapshot")

        await h.cleanupStore.release()
        let report = await pass.value
        await load.value
        XCTAssertEqual(report.finalized, [victim.id])
        let snapshot = try XCTUnwrap(loaded.value)
        XCTAssertTrue(snapshot.deletedClips.isEmpty, "the Editor reads the final state")
        XCTAssertEqual(snapshot.clips.map(\.id), [a.id, b.id])

        // A later autosave from that Editor cannot bring the finalized Clip back.
        let editor = ProjectEditorModel(project: snapshot, repository: h.repository, thumbnails: FakeClipThumbnailProvider())
        XCTAssertEqual(editor.moveClipLater(id: a.id), 2)
        XCTAssertEqual(h.repository.updateCount, 2, "seed + the Editor's autosave")
        let persisted = try XCTUnwrap(try h.repository.project(id: project.id))
        XCTAssertEqual(persisted.clips.map(\.id), [b.id, a.id])
        XCTAssertTrue(persisted.deletedClips.isEmpty, "no resurrection")
        let gone = await exists(victim.mediaRelativePath)
        XCTAssertFalse(gone)
    }

    /// Counter-proof of the race the gate closes: reading around the gate while cleanup is paused
    /// yields the intermediate snapshot (row still pending, file already gone).
    func testUngatedReadDuringCleanupSeesIntermediateState() async throws {
        var project = try await makeProject(clipCount: 2)
        let h = makeHarness()
        try h.repository.create(project)
        let victim = project.clips[1]
        try project.deleteClip(id: victim.id)
        try h.repository.update(project)
        await h.cleanupStore.setHold(true)
        let pass = Task { await h.coordinator.reconcile(projectID: project.id) }
        await h.cleanupStore.waitUntilRemovalEntered()
        let stale = try XCTUnwrap(try h.repository.project(id: project.id))
        XCTAssertEqual(stale.deletedClips.map(\.id), [victim.id], "this is exactly the snapshot a gated load never sees")
        await h.cleanupStore.release()
        _ = await pass.value
    }

    // MARK: 17. Composition / replacement serialization

    func testCompositionWaitsForRunningCleanup() async throws {
        var project = try await makeProject(clipCount: 2)
        let h = makeHarness()
        try h.repository.create(project)
        let victim = project.clips[1]
        try project.deleteClip(id: victim.id)
        try h.repository.update(project)
        await h.cleanupStore.setHold(true)
        let pass = Task { await h.coordinator.reconcile(projectID: project.id) }
        await h.cleanupStore.waitUntilRemovalEntered()

        let composition = ProjectCompositionCoordinator(
            repository: h.repository, mediaStore: store,
            validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()),
            storage: FakeProjectStorageGate(verdict: .sufficient), lifecycle: h.gate
        )
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let workspace = try await store.beginWorkspace()
        let sources = try await TestSupport.adoptedSources([fixture], into: workspace, store: store)
        let outcome = Cell<ProjectCompositionCoordinator.Outcome?>(nil)
        let compose = Task { @MainActor in outcome.value = await composition.compose(.replacingSaved(project.id), sources: sources, workspace: workspace) }
        let queued = await eventually(.milliseconds(300)) { h.gate.waitingCount == 1 }
        XCTAssertTrue(queued, "replacement queues behind cleanup")
        XCTAssertNil(outcome.value)
        XCTAssertEqual(try h.repository.recentProjects().map(\.id), [project.id], "A is still the saved Project")

        await h.cleanupStore.release()
        let report = await pass.value
        await compose.value
        XCTAssertEqual(report.finalized, [victim.id])
        guard case .committed(let bID)? = outcome.value else { return XCTFail("\(String(describing: outcome.value))") }
        XCTAssertEqual(try h.repository.recentProjects().map(\.id), [bID])
        XCTAssertTrue(TestSupport.exists(root.appendingPathComponent("Projects/\(bID.uuidString)/Media")))
        XCTAssertFalse(TestSupport.exists(root.appendingPathComponent("Projects/\(project.id.uuidString)")), "A retired after B, not during cleanup")
    }

    // MARK: Gate semantics

    func testLifecycleGateIsFIFOAndHeldAcrossSuspension() async throws {
        let gate = ProjectLifecycleOperationGate()
        let order = Cell<[Int]>([])
        let releaseFirst = Cell<CheckedContinuation<Void, Never>?>(nil)
        let first = Task { @MainActor in
            await gate.withExclusiveAccess {
                order.value.append(1)
                await withCheckedContinuation { releaseFirst.value = $0 }
                order.value.append(11)
            }
        }
        _ = await eventually { gate.isHeld && releaseFirst.value != nil }
        let second = Task { @MainActor in await gate.withExclusiveAccess { order.value.append(2) } }
        let third = Task { @MainActor in await gate.withExclusiveAccess { order.value.append(3) } }
        _ = await eventually { gate.waitingCount == 2 }
        XCTAssertEqual(order.value, [1], "nobody enters while the first holder is suspended")
        releaseFirst.value?.resume()
        await first.value; await second.value; await third.value
        XCTAssertEqual(order.value, [1, 11, 2, 3])
        XCTAssertFalse(gate.isHeld)
    }

    func testScheduledTriggersRunAsynchronouslyAndDrain() async throws {
        var project = try await makeProject(clipCount: 2)
        let h = makeHarness()
        try h.repository.create(project)
        let victim = project.clips[1]
        try project.deleteClip(id: victim.id)
        try h.repository.update(project)

        h.coordinator.scheduleReconcile(projectID: project.id)
        XCTAssertEqual(try h.repository.project(id: project.id)?.deletedClips.count, 1, "the trigger returns before any IO")
        await h.coordinator.drainScheduledForTesting()
        XCTAssertTrue(try h.repository.project(id: project.id)?.deletedClips.isEmpty ?? false)
        let gone = await exists(victim.mediaRelativePath)
        XCTAssertFalse(gone)
    }
}
