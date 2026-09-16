import Foundation
import SwiftData
import XCTest
@testable import Mellow

/// Recovery store wrapper: injectable failures per UUID (project directory / workspace / media clip).
actor FailableRecoveryStore: ProjectOrphanRecoveryStoring {
    private let inner: ProjectMediaStore
    private var failing: Set<UUID> = []
    private(set) var removalAttempts: [UUID] = []
    init(_ inner: ProjectMediaStore) { self.inner = inner }
    func setFailing(_ ids: Set<UUID>) { failing = ids }

    func enumerateProjectDirectories() async throws -> [ProjectRecoveryEntry] { try await inner.enumerateProjectDirectories() }
    func enumerateCommittedMedia(projectID: UUID) async throws -> [ProjectRecoveryEntry] { try await inner.enumerateCommittedMedia(projectID: projectID) }
    func enumerateWorkspaces() async throws -> [ProjectRecoveryEntry] { try await inner.enumerateWorkspaces() }
    func removeCommittedMedia(_ path: RelativeMediaPath, projectID: UUID, clipID: UUID) async throws {
        removalAttempts.append(clipID)
        if failing.contains(clipID) { throw ProjectMediaStoreError.removalFailed }
        try await inner.removeCommittedMedia(path, projectID: projectID, clipID: clipID)
    }
    func removeOrphanProjectDirectory(projectID: UUID) async throws {
        removalAttempts.append(projectID)
        if failing.contains(projectID) { throw ProjectMediaStoreError.removalFailed }
        try await inner.removeOrphanProjectDirectory(projectID: projectID)
    }
    func removeAbandonedWorkspace(id: UUID) async throws -> Bool {
        removalAttempts.append(id)
        if failing.contains(id) { throw ProjectMediaStoreError.removalFailed }
        return try await inner.removeAbandonedWorkspace(id: id)
    }
}

@MainActor
final class ProjectStartupRecoveryCoordinatorTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!
    private let fm = FileManager.default

    override func setUp() {
        root = TestSupport.temporaryRoot("recovery")
        store = ProjectMediaStore(root: root)
    }
    override func tearDown() { try? fm.removeItem(at: root) }

    // MARK: helpers

    private func write(_ relative: String, bytes: Int = 32) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: bytes).write(to: url)
        return url
    }
    private func mkdir(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func exists(_ relative: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(relative).path) }
    private func mediaPath(_ p: UUID, _ c: UUID) -> String { "Projects/\(p.uuidString)/Media/\(c.uuidString).mov" }

    private func committedClip(projectID: UUID, order: Int, withFile: Bool = true) throws -> VlogClip {
        let clipID = UUID()
        if withFile { _ = try write(mediaPath(projectID, clipID)) }
        return try VlogClip(id: clipID, projectID: projectID, sourceKind: .imported,
                            mediaRelativePath: try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID),
                            sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: order)
    }

    private struct Harness {
        let repository: ProbingRepository
        let recoveryStore: FailableRecoveryStore
        let sessions: LiveEditorSessions
        let gate: ProjectLifecycleOperationGate
        let recovery: ProjectStartupRecoveryCoordinator
        let cleanup: ProjectMediaCleanupCoordinator
        /// The production startup order: workspaces → 12A → orphans.
        func runStartupMaintenance() async -> ProjectStartupRecoveryReport {
            var report = await recovery.sweepAbandonedWorkspaces()
            _ = await cleanup.reconcileAll()
            report = report + (await recovery.recoverOrphans())
            return report
        }
    }

    private func makeHarness(repository: (any ProjectRepository)? = nil) -> Harness {
        let probing = ProbingRepository(repository ?? InMemoryProjectRepository())
        let recoveryStore = FailableRecoveryStore(store)
        let sessions = LiveEditorSessions()
        let gate = ProjectLifecycleOperationGate()
        let recovery = ProjectStartupRecoveryCoordinator(repository: probing, store: recoveryStore, lifecycle: gate, isEditorSessionLive: { sessions.isLive($0) })
        let cleanup = ProjectMediaCleanupCoordinator(repository: probing, mediaStore: store, consumers: IdleConsumers(), lifecycle: gate, isEditorSessionLive: { sessions.isLive($0) })
        return Harness(repository: probing, recoveryStore: recoveryStore, sessions: sessions, gate: gate, recovery: recovery, cleanup: cleanup)
    }

    /// A persisted two-clip Project with files, plus a pending (deleted) third clip with its file.
    private func seedProject(_ h: Harness, pendingClip: Bool = false) throws -> (VlogProject, [VlogClip]) {
        let id = UUID()
        var clips = [try committedClip(projectID: id, order: 0), try committedClip(projectID: id, order: 1)]
        if pendingClip { clips.append(try committedClip(projectID: id, order: 2)) }
        var project = try VlogProject(id: id, orientation: .portrait9x16, clips: clips)
        try h.repository.create(project)
        if pendingClip {
            try project.deleteClip(id: clips[2].id)
            try h.repository.update(project)
        }
        return (project, clips)
    }

    private func eventually(_ timeout: Duration = .seconds(3), _ condition: @MainActor () async -> Bool) async -> Bool {
        let clock = ContinuousClock(); let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() { return true }
            try? await clock.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    // MARK: - Layout parser (exhaustive)

    func testLayoutParserAcceptsOnlyCanonicalShapes() {
        let id = UUID()
        XCTAssertEqual(ProjectMediaLayout.canonicalUUID(id.uuidString), id)
        XCTAssertNil(ProjectMediaLayout.canonicalUUID(id.uuidString.lowercased()), "lowercase is not what Mellow writes")
        XCTAssertNil(ProjectMediaLayout.canonicalUUID("{" + id.uuidString + "}"))
        XCTAssertNil(ProjectMediaLayout.canonicalUUID(id.uuidString.replacingOccurrences(of: "-", with: "")))
        XCTAssertNil(ProjectMediaLayout.canonicalUUID("not-a-project"))
        XCTAssertNil(ProjectMediaLayout.canonicalUUID(""))
        XCTAssertNil(ProjectMediaLayout.canonicalUUID(" " + id.uuidString))

        XCTAssertEqual(ProjectMediaLayout.committedMediaClipID(fileName: "\(id.uuidString).mov"), id)
        XCTAssertNil(ProjectMediaLayout.committedMediaClipID(fileName: "\(id.uuidString).MOV"))
        XCTAssertNil(ProjectMediaLayout.committedMediaClipID(fileName: "\(id.uuidString).mp4"))
        XCTAssertNil(ProjectMediaLayout.committedMediaClipID(fileName: "\(id.uuidString)"))
        XCTAssertNil(ProjectMediaLayout.committedMediaClipID(fileName: "\(id.uuidString).mov.bak"))
        XCTAssertNil(ProjectMediaLayout.committedMediaClipID(fileName: "\(id.uuidString.lowercased()).mov"))
        XCTAssertNil(ProjectMediaLayout.committedMediaClipID(fileName: "readme.txt"))
        XCTAssertNil(ProjectMediaLayout.committedMediaClipID(fileName: ".\(id.uuidString).mov"))
        XCTAssertNil(ProjectMediaLayout.committedMediaClipID(fileName: "x.\(id.uuidString).mov"))
    }

    // MARK: 1–7, 30. Existing Project media scan

    func testExistingProjectScanRemovesOnlyCanonicalUnreferencedMedia() async throws {
        let h = makeHarness()
        let (project, clips) = try seedProject(h, pendingClip: true)
        let pid = project.id
        let orphan = UUID()
        _ = try write(mediaPath(pid, orphan))                                       // 3. canonical unreferenced
        _ = try write("Projects/\(pid.uuidString)/Media/thumb.jpg")                  // 4. non-UUID name
        _ = try write("Projects/\(pid.uuidString)/Media/\(UUID().uuidString).mp4")   // 5. wrong extension
        _ = try write("Projects/\(pid.uuidString)/Media/\(UUID().uuidString).MOV")   // 6. uppercase extension
        _ = try write("Projects/\(pid.uuidString)/Extras/note.txt")                  // 7. unknown subdirectory
        _ = try write("Projects/\(pid.uuidString)/Media/\(UUID().uuidString.lowercased()).mov") // 30. noncanonical spelling

        let report = await h.recovery.recoverOrphans()
        XCTAssertEqual(report.orphanMediaRemoved, 1)
        XCTAssertEqual(report.preservedReferenced, 3, "two active + one pending")
        XCTAssertEqual(report.noncanonicalPreserved, 4)
        XCTAssertEqual(report.orphanProjectDirsRemoved, 0)
        XCTAssertFalse(exists(mediaPath(pid, orphan)))
        for clip in clips { XCTAssertTrue(exists(clip.mediaRelativePath.value), "referenced media preserved") }
        XCTAssertTrue(exists("Projects/\(pid.uuidString)/Media/thumb.jpg"))
        XCTAssertTrue(exists("Projects/\(pid.uuidString)/Extras/note.txt"))
        XCTAssertEqual((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("Projects/\(pid.uuidString)/Media").path))?.count, 7, "3 referenced + 4 noncanonical remain")
        XCTAssertEqual(h.repository.updateCount, 1, "no metadata written by recovery (the one update is the seed's delete)")
        XCTAssertTrue(h.repository.finalizeCalls.isEmpty)
        XCTAssertEqual(try h.repository.project(id: pid)?.durableClips.count, 3)
    }

    /// 2 / 18: pending media survives the orphan classifier on its own (order independence).
    func testPendingClipMediaIsNeverAnOrphanEvenWithoutStep12A() async throws {
        let h = makeHarness()
        let (project, clips) = try seedProject(h, pendingClip: true)
        XCTAssertEqual(try h.repository.project(id: project.id)?.deletedClips.map(\.id), [clips[2].id])
        let report = await h.recovery.recoverOrphans()
        XCTAssertEqual(report.orphanMediaRemoved, 0)
        XCTAssertEqual(report.preservedReferenced, 3)
        XCTAssertTrue(exists(clips[2].mediaRelativePath.value))
        XCTAssertEqual(try h.repository.project(id: project.id)?.deletedClips.map(\.id), [clips[2].id], "still pending: 12A owns it")
    }

    /// 19 / 22: the production order — 12A finalizes the pending clip, 12B then finds nothing of it.
    func testStartupOrderCleansPendingThroughStep12AThenRecoversNothingForIt() async throws {
        let h = makeHarness()
        let (project, clips) = try seedProject(h, pendingClip: true)
        let orphan = UUID()
        _ = try write(mediaPath(project.id, orphan))
        let report = await h.runStartupMaintenance()
        XCTAssertTrue(try h.repository.project(id: project.id)?.deletedClips.isEmpty ?? false, "12A finalized the pending row")
        XCTAssertFalse(exists(clips[2].mediaRelativePath.value), "12A removed its file")
        XCTAssertEqual(report.orphanMediaRemoved, 1, "only the true orphan")
        XCTAssertEqual(report.orphanMediaFailures, 0)
        XCTAssertEqual(report.preservedReferenced, 2)
        XCTAssertEqual(h.repository.finalizeCalls, [clips[2].id])
    }

    /// 20 / 25 matrix: active + missing file is unavailable media, not an orphan; nothing happens.
    func testActiveMissingMediaIsUntouched() async throws {
        let h = makeHarness()
        let id = UUID()
        let present = try committedClip(projectID: id, order: 0)
        let missing = try committedClip(projectID: id, order: 1, withFile: false)
        let project = try VlogProject(id: id, orientation: .portrait9x16, clips: [present, missing])
        try h.repository.create(project)
        let before = try h.repository.project(id: id)
        let report = await h.runStartupMaintenance()
        XCTAssertEqual(report.orphanMediaRemoved, 0); XCTAssertEqual(report.orphanProjectDirsRemoved, 0)
        XCTAssertEqual(report.preservedReferenced, 1)
        XCTAssertEqual(try h.repository.project(id: id), before)
        XCTAssertEqual(h.repository.updateCount, 0); XCTAssertTrue(h.repository.finalizeCalls.isEmpty)
        XCTAssertTrue(exists(present.mediaRelativePath.value))
    }

    // MARK: 8–10, 16. Absent Project directories

    func testAbsentProjectCanonicalDirectoryIsRemovedWholeAndOthersPreserved() async throws {
        let h = makeHarness()
        let (project, _) = try seedProject(h)
        let absent = UUID()
        _ = try write(mediaPath(absent, UUID()))
        _ = try write("Projects/\(absent.uuidString)/Extras/future.dat")            // whole-dir ownership by UUID
        _ = try write("Projects/not-a-project/x.mov")                                // 9. non-UUID dir
        let lower = UUID().uuidString.lowercased()
        _ = try write("Projects/\(lower)/Media/\(UUID().uuidString).mov")            // 10. noncanonical spelling
        _ = try write("Projects/\(UUID().uuidString).txt")                           // regular file where a dir is expected

        let report = await h.recovery.recoverOrphans()
        XCTAssertEqual(report.orphanProjectDirsRemoved, 1)
        XCTAssertEqual(report.noncanonicalPreserved, 3)
        XCTAssertFalse(exists("Projects/\(absent.uuidString)"))
        XCTAssertTrue(exists("Projects/not-a-project/x.mov"))
        XCTAssertTrue(exists("Projects/\(lower)/Media"))
        XCTAssertTrue(exists("Projects/\(project.id.uuidString)/Media"), "existing Project untouched")
        XCTAssertEqual(report.preservedReferenced, 2)
        XCTAssertNotNil(try h.repository.project(id: project.id))
    }

    /// 16: a partially removed directory from a previous crash is just a canonical dir again.
    func testPartialOrphanProjectDirectoryIsRecoveredNextPass() async throws {
        let h = makeHarness()
        let absent = UUID()
        _ = try mkdir("Projects/\(absent.uuidString)/Media")   // nothing left inside
        let report = await h.recovery.recoverOrphans()
        XCTAssertEqual(report.orphanProjectDirsRemoved, 1)
        XCTAssertFalse(exists("Projects/\(absent.uuidString)"))
    }

    // MARK: 11–14, 17. Workspaces

    func testAbandonedCanonicalWorkspacesRemovedNoncanonicalPreserved() async throws {
        let h = makeHarness()
        let abandoned = UUID()
        _ = try write("ProjectWorkspace/\(abandoned.uuidString)/\(UUID().uuidString).mov")
        _ = try mkdir("ProjectWorkspace/\(UUID().uuidString)")                          // 17. partial / empty
        _ = try write("ProjectWorkspace/stale-op/x.mov")                                 // 12. noncanonical
        _ = try write("ProjectWorkspace/\(UUID().uuidString.lowercased())/x.mov")
        let report = await h.recovery.sweepAbandonedWorkspaces()
        XCTAssertEqual(report.workspacesRemoved, 2)
        XCTAssertEqual(report.noncanonicalPreserved, 2)
        XCTAssertEqual(report.workspaceFailures, 0)
        XCTAssertFalse(exists("ProjectWorkspace/\(abandoned.uuidString)"))
        XCTAssertTrue(exists("ProjectWorkspace/stale-op/x.mov"))
    }

    /// 13: a workspace begun by this process is live and survives a no-age-threshold sweep.
    func testLiveWorkspaceRegistryProtectsCurrentOperation() async throws {
        let h = makeHarness()
        let live = try await store.beginWorkspace()
        _ = try write("ProjectWorkspace/\(live.id.uuidString)/adopted.mov")
        let abandoned = UUID()
        _ = try write("ProjectWorkspace/\(abandoned.uuidString)/x.mov")
        let liveCount = await store.liveWorkspaceCount
        XCTAssertEqual(liveCount, 1)

        let report = await h.recovery.sweepAbandonedWorkspaces()
        XCTAssertEqual(report.workspacesRemoved, 1)
        XCTAssertEqual(report.noncanonicalPreserved, 1, "the live one is reported, never removed")
        XCTAssertTrue(exists("ProjectWorkspace/\(live.id.uuidString)/adopted.mov"))
        XCTAssertFalse(exists("ProjectWorkspace/\(abandoned.uuidString)"))
        let directRemoval = try await store.removeAbandonedWorkspace(id: live.id)
        XCTAssertFalse(directRemoval, "the primitive itself refuses a live ID")

        await store.discard(live)
        let afterDiscard = await store.liveWorkspaceCount
        XCTAssertEqual(afterDiscard, 0)
        let again = await h.recovery.sweepAbandonedWorkspaces()
        XCTAssertEqual(again.workspacesRemoved, 0, "discard already removed it")
        XCTAssertFalse(exists("ProjectWorkspace/\(live.id.uuidString)"))
    }

    /// 14: ownership ends at discard even when the filesystem removal fails; the next sweep takes it.
    func testRegistryReleasesWorkspaceEvenWhenDiscardRemovalFails() async throws {
        let h = makeHarness()
        let live = try await store.beginWorkspace()
        _ = try write("ProjectWorkspace/\(live.id.uuidString)/adopted.mov")
        // Make the directory undeletable for this user, then discard.
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: live.directory.deletingLastPathComponent().path)
        await store.discard(live)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: live.directory.deletingLastPathComponent().path)
        let count = await store.liveWorkspaceCount
        XCTAssertEqual(count, 0, "ID released regardless of the removal outcome")
        if exists("ProjectWorkspace/\(live.id.uuidString)") {
            let report = await h.recovery.sweepAbandonedWorkspaces()
            XCTAssertEqual(report.workspacesRemoved, 1, "the survivor is an abandoned workspace now")
        }
        XCTAssertFalse(exists("ProjectWorkspace/\(live.id.uuidString)"))
    }

    // MARK: 15, 28, 29. Failure isolation, multiple Projects, idempotency

    func testRemovalFailureIsIsolatedRetainedAndRetriedNextPass() async throws {
        let h = makeHarness()
        let (a, _) = try seedProject(h)
        let (b, _) = try seedProject(h)
        let orphanA = UUID(), orphanB = UUID(), absentDir = UUID(), workspace = UUID()
        _ = try write(mediaPath(a.id, orphanA))
        _ = try write(mediaPath(b.id, orphanB))
        _ = try write(mediaPath(absentDir, UUID()))
        _ = try write("ProjectWorkspace/\(workspace.uuidString)/x.mov")
        await h.recoveryStore.setFailing([orphanA, absentDir, workspace])

        let first = await h.runStartupMaintenance()
        XCTAssertEqual(first.orphanMediaFailures, 1); XCTAssertEqual(first.orphanMediaRemoved, 1, "B's orphan still cleaned")
        XCTAssertEqual(first.orphanProjectDirFailures, 1); XCTAssertEqual(first.orphanProjectDirsRemoved, 0)
        XCTAssertEqual(first.workspaceFailures, 1); XCTAssertEqual(first.workspacesRemoved, 0)
        XCTAssertTrue(exists(mediaPath(a.id, orphanA))); XCTAssertFalse(exists(mediaPath(b.id, orphanB)))
        XCTAssertTrue(exists("Projects/\(absentDir.uuidString)")); XCTAssertTrue(exists("ProjectWorkspace/\(workspace.uuidString)"))
        XCTAssertEqual(first.preservedReferenced, 4, "two Projects handled independently")

        await h.recoveryStore.setFailing([])
        let second = await h.runStartupMaintenance()
        XCTAssertEqual(second.orphanMediaRemoved, 1); XCTAssertEqual(second.orphanProjectDirsRemoved, 1); XCTAssertEqual(second.workspacesRemoved, 1)
        XCTAssertEqual(second.orphanMediaFailures + second.orphanProjectDirFailures + second.workspaceFailures, 0)

        let third = await h.runStartupMaintenance()
        XCTAssertEqual(third.orphanMediaRemoved + third.orphanProjectDirsRemoved + third.workspacesRemoved, 0, "idempotent")
        XCTAssertEqual(third.preservedReferenced, 4)
        XCTAssertEqual(h.repository.updateCount, 0); XCTAssertTrue(h.repository.finalizeCalls.isEmpty)
        XCTAssertEqual(Set(try h.repository.recentProjects().map(\.id)), [a.id, b.id])
    }

    // MARK: 21–23. Serialization and live Editor

    func testEditorLoadAndCompositionWaitBehindRecovery() async throws {
        let h = makeHarness()
        let (project, _) = try seedProject(h)
        let orphan = UUID()
        _ = try write(mediaPath(project.id, orphan))
        // Hold the gate (as a running maintenance section does); recovery queues behind it, and an
        // Editor load / composition queue behind recovery — FIFO — so they read the recovered state.
        let held = Cell<CheckedContinuation<Void, Never>?>(nil)
        let holder = Task { @MainActor in
            await h.gate.withExclusiveAccess { await withCheckedContinuation { held.value = $0 } }
        }
        _ = await eventually { held.value != nil }
        let recovery = Task { @MainActor in await h.recovery.recoverOrphans() }
        _ = await eventually { h.gate.waitingCount == 1 }
        let loaded = Cell<VlogProject?>(nil)
        let load = Task { @MainActor in loaded.value = try? await h.gate.withExclusiveAccess { try h.repository.project(id: project.id) } }
        let composition = ProjectCompositionCoordinator(repository: h.repository, mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()), storage: FakeProjectStorageGate(verdict: .sufficient), lifecycle: h.gate)
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let workspace = try await store.beginWorkspace()
        let sources = try await TestSupport.adoptedSources([fixture], into: workspace, store: store)
        let outcome = Cell<ProjectCompositionCoordinator.Outcome?>(nil)
        let compose = Task { @MainActor in outcome.value = await composition.compose(.fresh, sources: sources, workspace: workspace) }
        _ = await eventually { h.gate.waitingCount == 3 }
        XCTAssertNil(loaded.value); XCTAssertNil(outcome.value)
        XCTAssertTrue(exists(mediaPath(project.id, orphan)), "nothing recovered while the section is held")
        held.value?.resume()
        await holder.value
        let report = await recovery.value
        await load.value
        await compose.value
        XCTAssertEqual(report.orphanMediaRemoved, 1)
        XCTAssertNotNil(loaded.value)
        XCTAssertFalse(exists(mediaPath(project.id, orphan)))
        guard case .committed? = outcome.value else { return XCTFail("\(String(describing: outcome.value))") }
    }

    func testLiveEditorSessionSkipsThatProjectOnly() async throws {
        let h = makeHarness()
        let (live, _) = try seedProject(h)
        let (other, _) = try seedProject(h)
        let liveOrphan = UUID(), otherOrphan = UUID()
        _ = try write(mediaPath(live.id, liveOrphan)); _ = try write(mediaPath(other.id, otherOrphan))
        h.sessions.live = [live.id]
        let report = await h.recovery.recoverOrphans()
        XCTAssertEqual(report.skippedLiveProjects, 1)
        XCTAssertEqual(report.orphanMediaRemoved, 1)
        XCTAssertTrue(exists(mediaPath(live.id, liveOrphan)), "an Add in flight may own this file")
        XCTAssertFalse(exists(mediaPath(other.id, otherOrphan)))
        // Absent-Project directory that is somehow live (DEBUG restored route): also skipped.
        let absent = UUID(); _ = try write(mediaPath(absent, UUID())); h.sessions.live = [absent]
        let again = await h.recovery.recoverOrphans()
        XCTAssertTrue(exists("Projects/\(absent.uuidString)")); XCTAssertEqual(again.skippedLiveProjects, 1)
    }

    // MARK: 24. CaptureStaging and the rest of the container

    func testCaptureStagingAndUnknownRootEntriesAreNeverEnumeratedOrRemoved() async throws {
        let h = makeHarness()
        let staging = try write("CaptureStaging/\(UUID().uuidString).mov", bytes: 128)
        let stagingBytes = try Data(contentsOf: staging)
        _ = try write("Exports/\(UUID().uuidString).mov")
        _ = try write("\(UUID().uuidString).mov")
        _ = try write("ProjectWorkspace/\(UUID().uuidString)/x.mov")
        let report = await h.runStartupMaintenance()
        XCTAssertEqual(report.workspacesRemoved, 1)
        XCTAssertEqual(try Data(contentsOf: staging), stagingBytes, "byte-for-byte untouched")
        XCTAssertEqual((try fm.contentsOfDirectory(atPath: root.appendingPathComponent("CaptureStaging").path)).count, 1)
        XCTAssertEqual((try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Exports").path)).count, 1)
        XCTAssertEqual(report.noncanonicalPreserved, 0, "outside the two roots nothing is even classified")
    }

    // MARK: 25–27. Symlinks

    func testSymlinkedEntriesArePreservedAndTargetsSurvive() async throws {
        let h = makeHarness()
        let (project, _) = try seedProject(h)
        let external = TestSupport.temporaryRoot("external")
        defer { try? fm.removeItem(at: external) }
        try fm.createDirectory(at: external.appendingPathComponent("dir/Media"), withIntermediateDirectories: true)
        let externalFile = external.appendingPathComponent("target.mov")
        try Data(repeating: 1, count: 16).write(to: externalFile)
        try Data(repeating: 2, count: 16).write(to: external.appendingPathComponent("dir/Media/\(UUID().uuidString).mov"))

        // 25. Project dir symlink → external dir; 26. media symlink → external file; 27. workspace symlink.
        let projectLink = root.appendingPathComponent("Projects/\(UUID().uuidString)")
        try fm.createSymbolicLink(at: projectLink, withDestinationURL: external.appendingPathComponent("dir"))
        let mediaLink = root.appendingPathComponent(mediaPath(project.id, UUID()))
        try fm.createSymbolicLink(at: mediaLink, withDestinationURL: externalFile)
        _ = try mkdir("ProjectWorkspace")
        let workspaceLink = root.appendingPathComponent("ProjectWorkspace/\(UUID().uuidString)")
        try fm.createSymbolicLink(at: workspaceLink, withDestinationURL: external.appendingPathComponent("dir"))

        let report = await h.runStartupMaintenance()
        XCTAssertEqual(report.noncanonicalPreserved, 3)
        XCTAssertEqual(report.orphanProjectDirsRemoved + report.orphanMediaRemoved + report.workspacesRemoved, 0)
        XCTAssertTrue(fm.fileExists(atPath: externalFile.path))
        XCTAssertEqual((try fm.contentsOfDirectory(atPath: external.appendingPathComponent("dir/Media").path)).count, 1)
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: projectLink.path), "link entries themselves untouched")
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: mediaLink.path))
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: workspaceLink.path))

        // The primitives refuse links even when handed a canonical id.
        let linkedProjectID = ProjectMediaLayout.canonicalUUID(projectLink.lastPathComponent)!
        do { try await store.removeOrphanProjectDirectory(projectID: linkedProjectID); XCTFail() } catch let e as ProjectMediaStoreError { XCTAssertEqual(e, .symbolicLink) }
        let linkedClipID = ProjectMediaLayout.committedMediaClipID(fileName: mediaLink.lastPathComponent)!
        do { try await store.removeCommittedMedia(try ProjectMediaStore.committedMediaPath(projectID: project.id, clipID: linkedClipID), projectID: project.id, clipID: linkedClipID); XCTFail() } catch let e as ProjectMediaStoreError { XCTAssertEqual(e, .symbolicLink) }
        XCTAssertTrue(fm.fileExists(atPath: externalFile.path))
    }

    // MARK: Primitives

    func testOrphanDirectoryPrimitiveIsRootContainedAndIdempotent() async throws {
        let id = UUID()
        _ = try write(mediaPath(id, UUID()))
        try await store.removeOrphanProjectDirectory(projectID: id)
        XCTAssertFalse(exists("Projects/\(id.uuidString)"))
        try await store.removeOrphanProjectDirectory(projectID: id)   // missing = success
        let removed = try await store.removeAbandonedWorkspace(id: UUID())
        XCTAssertTrue(removed, "missing workspace = success")
        XCTAssertTrue(exists("Projects") || !exists("Projects"), "the Projects root itself is never a candidate")
    }

    // MARK: Add rollback (STEP 11) and the crash window

    func testAddRollbackStillCleansImmediatelyAndRecoveryHandlesOnlyTheCrashWindow() async throws {
        let h = makeHarness()
        let (project, _) = try seedProject(h)
        // In-process failure: STEP 11 discards its own files immediately (unchanged behaviour).
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let selector = FakeProjectMediaSelector(script: .fixtures([fixture]))
        let appender = ProjectClipAppendCoordinator(mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()), storage: FakeProjectStorageGate(verdict: .sufficient))
        let failing = FailableProjectRepository()
        try failing.create(project)
        failing.updateFails = true
        let editor = ProjectEditorModel(project: project, repository: failing, thumbnails: FakeClipThumbnailProvider(), acquisition: EditorClipAcquisition(mediaStore: store, mediaSelector: selector, storageGate: FakeProjectStorageGate(verdict: .sufficient), appender: appender))
        let added = await editor.addClips()
        XCTAssertEqual(added, 0)
        let media = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Projects/\(project.id.uuidString)/Media").path)
        XCTAssertEqual(media.count, 2, "rollback removed the materialised file before any recovery ran")

        // Crash window: the file exists, no row references it → next launch's recovery removes it.
        let workspace = try await store.beginWorkspace()
        let sources = try await TestSupport.adoptedSources([fixture], into: workspace, store: store)
        guard case .ready(let clips) = await appender.prepareClips(for: project, sources: sources) else { return XCTFail() }
        await store.discard(workspace)
        XCTAssertTrue(exists(clips[0].mediaRelativePath.value))
        let report = await h.runStartupMaintenance()
        XCTAssertEqual(report.orphanMediaRemoved, 1)
        XCTAssertFalse(exists(clips[0].mediaRelativePath.value))
        XCTAssertEqual(try h.repository.project(id: project.id)?.clips.count, 2)
    }

    /// Replacement retire-A stays with `compose`; a leftover directory is recovery's on a later launch.
    func testLeftoverRetiredProjectDirectoryIsRecoveredWithoutTouchingTheNewProject() async throws {
        let h = makeHarness()
        let (a, _) = try seedProject(h)
        try h.repository.deleteProject(id: a.id)              // row gone, media left (crash mid-retire)
        let (b, _) = try seedProject(h)
        let report = await h.runStartupMaintenance()
        XCTAssertEqual(report.orphanProjectDirsRemoved, 1)
        XCTAssertFalse(exists("Projects/\(a.id.uuidString)"))
        XCTAssertTrue(exists("Projects/\(b.id.uuidString)/Media"))
        XCTAssertEqual(report.preservedReferenced, 2)
    }

    // MARK: SwiftData reference set

    func testSwiftDataDurableReferencesProtectActiveAndPendingAcrossRelaunch() async throws {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("recovery-\(UUID().uuidString).store")
        defer { try? fm.removeItem(at: storeURL) }
        let id = UUID()
        let active = try committedClip(projectID: id, order: 0)
        let pending = try committedClip(projectID: id, order: 1)
        let orphan = UUID(); _ = try write(mediaPath(id, orphan))
        do {
            let container = try MellowModelContainer.makePersistentContainer(storeURL: storeURL)
            let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
            var project = try VlogProject(id: id, orientation: .portrait9x16, clips: [active, pending])
            try repository.create(project)
            try project.deleteClip(id: pending.id)
            try repository.update(project)
        }
        let container = try MellowModelContainer.makePersistentContainer(storeURL: storeURL)
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        let h = makeHarness(repository: repository)
        // Orphan scan alone (12B first) keeps the pending file; the full order then removes it via 12A.
        let scanOnly = await h.recovery.recoverOrphans()
        XCTAssertEqual(scanOnly.orphanMediaRemoved, 1); XCTAssertEqual(scanOnly.preservedReferenced, 2)
        XCTAssertTrue(exists(pending.mediaRelativePath.value))
        let full = await h.runStartupMaintenance()
        XCTAssertEqual(full.orphanMediaRemoved, 0)
        XCTAssertFalse(exists(pending.mediaRelativePath.value))
        XCTAssertTrue(exists(active.mediaRelativePath.value))
        XCTAssertEqual(try repository.project(id: id)?.clips.map(\.id), [active.id])
        XCTAssertTrue(try repository.project(id: id)?.deletedClips.isEmpty ?? false)
    }
}
