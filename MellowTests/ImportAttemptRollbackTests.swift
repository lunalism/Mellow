import Foundation
import XCTest
@testable import Mellow

/// ADR-050 050-D D7a §1 attempt rollback executor (internal, unwired) on isolated temporary media roots.
/// Failure paths use real filesystem conditions (occupied destinations, symlinks, read-only directories).
final class ImportAttemptRollbackTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!
    private var readOnlyDirectories: [URL] = []

    override func setUp() {
        root = TestSupport.temporaryRoot("attempt-rollback")
        store = ProjectMediaStore(root: root)
    }

    override func tearDown() {
        for directory in readOnlyDirectories { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    private func bytes(_ count: Int, _ fill: UInt8) -> Data { Data(repeating: fill, count: count) }

    /// A file adopted into `workspace` (its name is the restoration target) with `count` bytes.
    private func workspaceFile(_ workspace: ProjectMediaWorkspace, _ count: Int, fill: UInt8 = 0x11) async throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        try bytes(count, fill).write(to: temp)
        return try await store.adopt(temp, into: workspace)
    }

    private struct Prepared {
        let record: ImportRollbackRecord
        let workspaceURL: URL
        let materializedURL: URL
    }

    /// A ready item: adopted, then (optionally) materialized into the Project like the fast path does.
    private func ready(_ workspace: ProjectMediaWorkspace, projectID: UUID, bytes count: Int = 1_000, materialize: Bool = true) async throws -> Prepared {
        let file = try await workspaceFile(workspace, count)
        let clipID = UUID()
        let path = try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID)
        if materialize { _ = try await store.materialize(file, projectID: projectID, clipID: clipID) }
        return Prepared(record: ImportRollbackRecord(clipID: clipID, materializedPath: path, kind: .ready(workspaceFileName: file.lastPathComponent, recordedByteCount: Int64(count))),
                        workspaceURL: file, materializedURL: root.appendingPathComponent(path.value))
    }

    /// A normalization output written in the attempt directory, then (optionally) materialized.
    private func normalized(_ workspace: ProjectMediaWorkspace, projectID: UUID, attempt: String = "attempt-1", materialize: Bool = true) async throws -> Prepared {
        let directory = workspace.directory.appendingPathComponent(attempt, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("\(UUID().uuidString).mov")
        try bytes(2_000, 0x22).write(to: output)
        let clipID = UUID()
        let path = try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID)
        if materialize { _ = try await store.materialize(output, projectID: projectID, clipID: clipID) }
        return Prepared(record: ImportRollbackRecord(clipID: clipID, materializedPath: path, kind: .normalizedOutput),
                        workspaceURL: output, materializedURL: root.appendingPathComponent(path.value))
    }

    /// Unrelated media: another Project's committed file and another live workspace's file.
    private func unrelatedMedia() async throws -> [URL] {
        let otherProject = root.appendingPathComponent(try ProjectMediaStore.committedMediaPath(projectID: UUID(), clipID: UUID()).value)
        try FileManager.default.createDirectory(at: otherProject.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes(500, 0x33).write(to: otherProject)
        let otherWorkspace = try await store.beginWorkspace()
        return [otherProject, try await workspaceFile(otherWorkspace, 700, fill: 0x44)]
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private func size(_ url: URL) -> Int64? { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value }

    private func results(_ outcome: ImportRollbackOutcome) -> [UUID: ImportRollbackRecordResult] {
        switch outcome {
        case .verifiedClean(let records): return records
        case .unresolved(let records, _): return records
        }
    }

    // MARK: Verified rollback

    func testReadyItemsAreRestoredAndVerifiedWithoutTouchingUnrelatedMedia() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let a = try await ready(workspace, projectID: projectID, bytes: 1_000)
        let b = try await ready(workspace, projectID: projectID, bytes: 3_000)
        let unrelated = try await unrelatedMedia()

        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [a.record, b.record], attemptDirectoryName: nil))
        XCTAssertEqual(outcome, .verifiedClean(records: [a.record.clipID: .restored, b.record.clipID: .restored]))
        XCTAssertTrue(outcome.isVerifiedClean)
        XCTAssertEqual(size(a.workspaceURL), 1_000); XCTAssertEqual(size(b.workspaceURL), 3_000)
        XCTAssertFalse(exists(a.materializedURL)); XCTAssertFalse(exists(b.materializedURL))
        XCTAssertTrue(exists(root.appendingPathComponent("Projects/\(projectID.uuidString)/Media")), "empty Project directories are left alone (unresolved rule)")
        for url in unrelated { XCTAssertTrue(exists(url), "unrelated media untouched: \(url.lastPathComponent)") }
    }

    func testMixedAttemptRestoresReadyRemovesOwnOutputsAndTheAttemptDirectory() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let retainedSource = try await workspaceFile(workspace, 4_000)        // the normalization item's Retry source
        let r = try await ready(workspace, projectID: projectID)
        let n = try await normalized(workspace, projectID: projectID)
        let unmaterialized = try await normalized(workspace, projectID: projectID, materialize: false)   // still in attempt-1

        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [r.record, n.record], attemptDirectoryName: "attempt-1"))
        XCTAssertEqual(outcome, .verifiedClean(records: [r.record.clipID: .restored, n.record.clipID: .removed]))
        XCTAssertFalse(exists(n.materializedURL))
        XCTAssertFalse(exists(unmaterialized.workspaceURL.deletingLastPathComponent()), "the attempt's own output directory is gone")
        XCTAssertTrue(exists(r.workspaceURL))
        XCTAssertEqual(size(retainedSource), 4_000, "retained sources outside the attempt directory are untouched")
        XCTAssertTrue(exists(workspace.directory))
    }

    func testPartialMaterializationLocatesEachCandidateBeforeActing() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let first = try await ready(workspace, projectID: projectID)                        // moved
        let failing = try await ready(workspace, projectID: projectID, materialize: false)  // failed before its move
        let notReached = try await normalized(workspace, projectID: projectID, materialize: false)

        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID,
                                                                     records: [first.record, failing.record, notReached.record], attemptDirectoryName: "attempt-1"))
        XCTAssertEqual(outcome, .verifiedClean(records: [first.record.clipID: .restored, failing.record.clipID: .alreadyInWorkspace,
                                                         notReached.record.clipID: .alreadyAbsent]))
    }

    // MARK: Unresolved states (no overwrite, no false success)

    func testOccupiedDestinationIsNeverOverwrittenAndOtherRecordsStillRollBack() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let blocked = try await ready(workspace, projectID: projectID)
        let fine = try await ready(workspace, projectID: projectID)
        try bytes(42, 0x99).write(to: blocked.workspaceURL)   // something now occupies the original path

        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [blocked.record, fine.record], attemptDirectoryName: nil))
        XCTAssertFalse(outcome.isVerifiedClean)
        XCTAssertEqual(results(outcome), [blocked.record.clipID: .unresolved(.destinationOccupied), fine.record.clipID: .restored])
        XCTAssertEqual(size(blocked.workspaceURL), 42, "the occupying file is not overwritten")
        XCTAssertEqual(size(blocked.materializedURL), 1_000, "the candidate is preserved, not deleted")
    }

    func testMissingAndInconsistentFilesAreUnresolved() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let gone = try await ready(workspace, projectID: projectID)
        try FileManager.default.removeItem(at: gone.materializedURL)
        let wrongSize = try await ready(workspace, projectID: projectID, bytes: 1_000)
        let misrecorded = ImportRollbackRecord(clipID: wrongSize.record.clipID, materializedPath: wrongSize.record.materializedPath,
                                               kind: .ready(workspaceFileName: wrongSize.workspaceURL.lastPathComponent, recordedByteCount: 999))

        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [gone.record, misrecorded], attemptDirectoryName: nil))
        XCTAssertEqual(outcome, .unresolved(records: [gone.record.clipID: .unresolved(.fileMissing),
                                                      wrongSize.record.clipID: .unresolved(.sizeMismatch(expected: 999, actual: 1_000))], attemptDirectory: nil))
        XCTAssertFalse(outcome.isVerifiedClean, "verification failure blocks Retry")
        XCTAssertTrue(exists(wrongSize.materializedURL), "a file that does not match its record never leaves the Project")
        XCTAssertFalse(exists(wrongSize.workspaceURL))
    }

    func testFailedRestorationAndRemovalAreUnresolvedAndPreserveFiles() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let r = try await ready(workspace, projectID: projectID)
        let n = try await normalized(workspace, projectID: projectID)
        let media = r.materializedURL.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: media.path)   // nothing can leave or be removed
        readOnlyDirectories.append(media)

        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [r.record, n.record], attemptDirectoryName: nil))
        XCTAssertEqual(outcome, .unresolved(records: [r.record.clipID: .unresolved(.restoreFailed), n.record.clipID: .unresolved(.removalFailed)], attemptDirectory: nil))
        XCTAssertTrue(exists(r.materializedURL)); XCTAssertTrue(exists(n.materializedURL))
        XCTAssertFalse(exists(r.workspaceURL))
    }

    func testSymlinksAndForeignPathsAreRefused() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).mov")
        try bytes(10, 0x55).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        // Materialized candidate is a symlink to a file outside the root.
        let linked = try await normalized(workspace, projectID: projectID)
        try FileManager.default.removeItem(at: linked.materializedURL)
        try FileManager.default.createSymbolicLink(at: linked.materializedURL, withDestinationURL: outside)
        // Ready record whose workspace name tries to escape.
        let escaping = ImportRollbackRecord(clipID: UUID(), materializedPath: try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: UUID()),
                                            kind: .ready(workspaceFileName: "../escape.mov", recordedByteCount: 1))
        // A record pointing at another Project's canonical path.
        let foreign = ImportRollbackRecord(clipID: UUID(), materializedPath: try ProjectMediaStore.committedMediaPath(projectID: UUID(), clipID: UUID()), kind: .normalizedOutput)
        // Attempt directory that is a symlink.
        let linkedAttempt = workspace.directory.appendingPathComponent("attempt-9")
        try FileManager.default.createSymbolicLink(at: linkedAttempt, withDestinationURL: FileManager.default.temporaryDirectory)

        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [linked.record, escaping, foreign], attemptDirectoryName: "attempt-9"))
        XCTAssertEqual(outcome, .unresolved(records: [linked.record.clipID: .unresolved(.symbolicLink), escaping.clipID: .unresolved(.pathNotOwned),
                                                      foreign.clipID: .unresolved(.pathNotOwned)], attemptDirectory: .symbolicLink))
        XCTAssertEqual(size(outside), 10, "a symlink target is never touched")
        XCTAssertTrue(exists(FileManager.default.temporaryDirectory), "nor a symlinked directory's target")
    }

    func testASymlinkedMediaDirectoryIsRefused() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let r = try await ready(workspace, projectID: projectID)
        let media = r.materializedURL.deletingLastPathComponent()
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: media, to: elsewhere)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.createSymbolicLink(at: media, withDestinationURL: elsewhere)

        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [r.record], attemptDirectoryName: nil))
        XCTAssertEqual(results(outcome), [r.record.clipID: .unresolved(.symbolicLink)])
        XCTAssertTrue(exists(elsewhere.appendingPathComponent(r.materializedURL.lastPathComponent)), "nothing moved through the link")
    }

    // MARK: Repeated calls and ownership

    func testRepeatedCallVerifiesAgainAndADiscardedWorkspaceIsNeverClean() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let r = try await ready(workspace, projectID: projectID)
        let n = try await normalized(workspace, projectID: projectID)
        let plan = ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [r.record, n.record], attemptDirectoryName: "attempt-1")

        let first = await store.rollBackAttempt(plan)
        XCTAssertTrue(first.isVerifiedClean)
        let second = await store.rollBackAttempt(plan)
        XCTAssertEqual(second, .verifiedClean(records: [r.record.clipID: .alreadyInWorkspace, n.record.clipID: .alreadyAbsent]),
                       "a repeated call re-verifies the same state; nothing is done twice")

        await store.discard(workspace)
        let afterDiscard = await store.rollBackAttempt(plan)
        XCTAssertEqual(afterDiscard, .unresolved(records: [r.record.clipID: .unresolved(.workspaceNotLive), n.record.clipID: .unresolved(.workspaceNotLive)],
                                                 attemptDirectory: .workspaceNotLive), "no false cleanup success without a live workspace")
    }

    func testDuplicateRecordsAreUnresolved() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let r = try await ready(workspace, projectID: projectID)
        let other = try await ready(workspace, projectID: projectID)
        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [r.record, other.record, r.record], attemptDirectoryName: nil))
        XCTAssertEqual(results(outcome), [r.record.clipID: .unresolved(.duplicateRecord), other.record.clipID: .restored])
        XCTAssertFalse(outcome.isVerifiedClean)
        XCTAssertTrue(exists(r.materializedURL), "a duplicated identity is rejected before any mutation")
        XCTAssertFalse(exists(r.workspaceURL))
    }

    // MARK: Ownership and type edge cases

    func testAnUnusableWorkspaceMutatesNothing() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let r = try await ready(workspace, projectID: projectID)
        let n = try await normalized(workspace, projectID: projectID)
        // A workspace value whose directory is not the canonical one for its ID.
        let impostor = ProjectMediaWorkspace(id: workspace.id, directory: FileManager.default.temporaryDirectory)
        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: impostor, projectID: projectID, records: [r.record, n.record], attemptDirectoryName: "attempt-1"))
        XCTAssertEqual(outcome, .unresolved(records: [r.record.clipID: .unresolved(.workspaceNotADirectory), n.record.clipID: .unresolved(.workspaceNotADirectory)],
                                            attemptDirectory: .workspaceNotADirectory))
        XCTAssertTrue(exists(r.materializedURL)); XCTAssertTrue(exists(n.materializedURL))

        // A normalized-only plan against a discarded workspace is not clean and removes nothing.
        await store.discard(workspace)
        let late = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [n.record], attemptDirectoryName: nil))
        XCTAssertFalse(late.isVerifiedClean)
        XCTAssertTrue(exists(n.materializedURL))
        let empty = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [], attemptDirectoryName: nil))
        XCTAssertFalse(empty.isVerifiedClean, "even an empty plan is never clean without a live workspace")
    }

    func testASymlinkedWorkspaceDirectoryIsRefused() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        let r = try await ready(workspace, projectID: projectID)
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: workspace.directory, to: elsewhere)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.createSymbolicLink(at: workspace.directory, withDestinationURL: elsewhere)
        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [r.record], attemptDirectoryName: nil))
        XCTAssertEqual(results(outcome), [r.record.clipID: .unresolved(.workspaceNotADirectory)])
        XCTAssertTrue(exists(r.materializedURL))
    }

    func testProjectPathComponentsMustBeRealDirectories() async throws {
        let workspace = try await store.beginWorkspace()
        // Projects/<P> is a symlink.
        let linkedProject = UUID()
        let a = try await normalized(workspace, projectID: linkedProject)
        let projectDirectory = root.appendingPathComponent("Projects/\(linkedProject.uuidString)", isDirectory: true)
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("p-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: projectDirectory, to: elsewhere)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.createSymbolicLink(at: projectDirectory, withDestinationURL: elsewhere)
        var outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: linkedProject, records: [a.record], attemptDirectoryName: nil))
        XCTAssertEqual(results(outcome), [a.record.clipID: .unresolved(.symbolicLink)])
        XCTAssertTrue(exists(elsewhere.appendingPathComponent("Media/\(a.materializedURL.lastPathComponent)")))

        // Media is a regular file instead of a directory.
        let fileProject = UUID()
        let fixedClip = UUID()
        let fixed = ImportRollbackRecord(clipID: fixedClip, materializedPath: try ProjectMediaStore.committedMediaPath(projectID: fileProject, clipID: fixedClip), kind: .normalizedOutput)
        let media = root.appendingPathComponent("Projects/\(fileProject.uuidString)/Media")
        try FileManager.default.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes(1, 0x01).write(to: media)
        outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: fileProject, records: [fixed], attemptDirectoryName: nil))
        XCTAssertEqual(results(outcome), [fixed.clipID: .unresolved(.notADirectory)])
        XCTAssertTrue(exists(media))
    }

    func testWrongTypesAndBadAttemptDirectoryNamesAreUnresolved() async throws {
        let workspace = try await store.beginWorkspace()
        let projectID = UUID()
        // A normalized "output" that is a directory.
        let clipID = UUID()
        let path = try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(path.value), withIntermediateDirectories: true)
        let directoryOutput = ImportRollbackRecord(clipID: clipID, materializedPath: path, kind: .normalizedOutput)
        // A ready record whose candidate is gone and whose workspace path is a directory.
        let r = try await ready(workspace, projectID: projectID)
        try FileManager.default.removeItem(at: r.materializedURL)   // the workspace path is already empty (it was moved)
        try FileManager.default.createDirectory(at: r.workspaceURL, withIntermediateDirectories: true)
        let outcome = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [directoryOutput, r.record], attemptDirectoryName: nil))
        XCTAssertEqual(results(outcome), [clipID: .unresolved(.notARegularFile), r.record.clipID: .unresolved(.notARegularFile)])
        XCTAssertTrue(exists(root.appendingPathComponent(path.value)))

        for name in ["..", "", "a/b", "."] {
            let named = await store.rollBackAttempt(ImportRollbackPlan(workspace: workspace, projectID: projectID, records: [], attemptDirectoryName: name))
            XCTAssertEqual(named, .unresolved(records: [:], attemptDirectory: .pathNotOwned), "attempt directory name \(name.debugDescription)")
        }
        XCTAssertTrue(exists(workspace.directory))
    }

    // MARK: Attempt preparation surface

    func testAttemptDirectoryNeedsALiveWorkspaceAndIsNeverReused() async throws {
        let workspace = try await store.beginWorkspace()
        let directory = try await store.createAttemptDirectory(named: "attempt-1", in: workspace)
        XCTAssertEqual(directory.deletingLastPathComponent().standardizedFileURL.path, workspace.directory.standardizedFileURL.path)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        try bytes(10, 0x01).write(to: directory.appendingPathComponent("keep.mov"))

        do {
            _ = try await store.createAttemptDirectory(named: "attempt-1", in: workspace)
            XCTFail("an existing entry is never reused")
        } catch { XCTAssertEqual(error as? ProjectMediaStoreError, .destinationAlreadyExists) }
        XCTAssertTrue(exists(directory.appendingPathComponent("keep.mov")))

        for name in ["..", "", "a/b", "."] {
            do {
                _ = try await store.createAttemptDirectory(named: name, in: workspace)
                XCTFail("name \(name.debugDescription) is not a plain child")
            } catch { XCTAssertEqual(error as? ProjectMediaStoreError, .pathNotCanonical) }
        }

        await store.discard(workspace)
        do {
            _ = try await store.createAttemptDirectory(named: "attempt-2", in: workspace)
            XCTFail("a discarded workspace is not live")
        } catch { XCTAssertEqual(error as? ProjectMediaStoreError, .workspaceNotLive) }
        XCTAssertFalse(exists(workspace.directory), "nothing is recreated for a discarded workspace")
    }

    func testWorkspaceFileByteCountOnlyForRegularDirectChildrenOfALiveWorkspace() async throws {
        let workspace = try await store.beginWorkspace()
        let file = try await workspaceFile(workspace, 1_234)
        await XCTAssertEqualAsync(await store.workspaceFileByteCount(file, in: workspace), 1_234)

        let link = workspace.directory.appendingPathComponent("link.mov")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        await XCTAssertNilAsync(await store.workspaceFileByteCount(link, in: workspace), "a symlink is never followed")

        let nested = try await store.createAttemptDirectory(named: "attempt-1", in: workspace).appendingPathComponent("nested.mov")
        try bytes(5, 0x02).write(to: nested)
        await XCTAssertNilAsync(await store.workspaceFileByteCount(nested, in: workspace), "only direct children")
        await XCTAssertNilAsync(await store.workspaceFileByteCount(nested.deletingLastPathComponent(), in: workspace), "a directory is not a source")

        let other = try await store.beginWorkspace()
        await XCTAssertNilAsync(await store.workspaceFileByteCount(file, in: other), "another workspace's file")
        await XCTAssertNilAsync(await store.workspaceFileByteCount(workspace.directory.appendingPathComponent("missing.mov"), in: workspace))

    }
}
