import Foundation
import XCTest
@testable import Mellow

/// ADR-050 050-D D8.0 media preservation: from a save attempt on, media the save may reference is never
/// removed. Covers Select Clips composition (create, verification, two-save `.replacingSaved` retire-A)
/// and Editor Add / Replace, against a real `ProjectMediaStore` under a temporary root and the fake
/// repository. "Throws after commit" / hidden / unreadable reads are injected repository behaviours that
/// model a save whose outcome the caller cannot see; they do not prove any specific SwiftData failure mode.
@MainActor
final class ProjectMediaPreservationTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!
    private let gate = ProjectLifecycleOperationGate()

    override func setUp() {
        root = TestSupport.temporaryRoot("media-preservation")
        store = ProjectMediaStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    // MARK: helpers

    private func coordinator(_ repository: any ProjectRepository) -> ProjectCompositionCoordinator {
        ProjectCompositionCoordinator(repository: repository, mediaStore: store,
                                      validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()),
                                      storage: FakeProjectStorageGate(verdict: .sufficient), lifecycle: gate)
    }

    private func compose(_ intent: ProjectCompositionCoordinator.Intent, _ repository: any ProjectRepository) async throws -> ProjectCompositionCoordinator.Outcome {
        let workspace = try await store.beginWorkspace()
        let sources = try await TestSupport.adoptedSources([try await TestMediaFixtures.shared.portrait(seconds: 2)], into: workspace, store: store)
        return await coordinator(repository).compose(intent, sources: sources, workspace: workspace)
    }

    /// Saved Project A with one real Project-owned media file.
    private func seedA(_ repository: any ProjectRepository) async throws -> (VlogProject, RelativeMediaPath) {
        let workspace = try await store.beginWorkspace()
        let adopted = try await store.adopt(try TestSupport.transferCopy(of: try await TestMediaFixtures.shared.portrait(seconds: 2)), into: workspace)
        let projectID = UUID(), clipID = UUID()
        let path = try await store.materialize(adopted, projectID: projectID, clipID: clipID)
        await store.discard(workspace)
        let clip = try VlogClip(id: clipID, projectID: projectID, sourceKind: .imported, mediaRelativePath: path,
                                sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: 0)
        let project = try VlogProject(id: projectID, createdAt: Date(timeIntervalSince1970: 100), orientation: .portrait9x16, clips: [clip])
        try repository.create(project)
        return (project, path)
    }

    private func projectDirectories() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects").path)) ?? [])
    }
    private func mediaFiles(_ projectID: UUID) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects/\(projectID.uuidString)/Media").path)) ?? []).sorted()
    }
    private func recovery(_ repository: any ProjectRepository) -> ProjectStartupRecoveryCoordinator {
        ProjectStartupRecoveryCoordinator(repository: repository, store: store, lifecycle: gate, isEditorSessionLive: { _ in false })
    }

    // MARK: Select Clips — create and verification

    func testCreateThatCommittedThenThrewKeepsTheSavedRowsMedia() async throws {
        let repository = FailableProjectRepository()
        repository.createThrowsAfterCommit = true
        let outcome = try await compose(.fresh, repository)
        XCTAssertEqual(outcome, .failed(.persistence), "presentation unchanged (pending D8.5)")
        let saved = try XCTUnwrap(try repository.recentProjects().first, "the save landed")
        for clip in saved.clips { await assertFileExists(store, clip.mediaRelativePath, true, "referenced media preserved") }
        XCTAssertTrue(repository.deletedIDs.isEmpty, "no rollback of a saved row")
    }

    func testCreateErrorWithoutVisibleCommitPreservesMediaAndLeavesItToStartupRecovery() async throws {
        let repository = FailableProjectRepository()
        let (a, aMedia) = try await seedA(repository)
        repository.createFails = true
        let outcome = try await compose(.fresh, repository)
        XCTAssertEqual(outcome, .failed(.persistence))
        XCTAssertEqual(projectDirectories().count, 2, "B's directory is preserved: a thrown save is not proof that nothing committed")
        await assertFileExists(store, aMedia, true, "unrelated existing media untouched")

        // Existing ownership mechanism: B's row is absent, so the next launch's recovery removes B only.
        let report = await recovery(repository).recoverOrphans()
        XCTAssertEqual(report.orphanProjectDirsRemoved, 1)
        XCTAssertEqual(projectDirectories(), [a.id.uuidString])
        await assertFileExists(store, aMedia, true)
    }

    func testSuccessfulCreateWithFailedVerificationKeepsRowAndMedia() async throws {
        let repository = FailableProjectRepository()
        let (a, aMedia) = try await seedA(repository)
        repository.hideCreatedProjects = true
        let outcome = try await compose(.replacingSaved(a.id), repository)
        XCTAssertEqual(outcome, .failed(.verification))
        let bID = try XCTUnwrap(repository.hiddenIDs.first)
        let b = try XCTUnwrap(try repository.inner.project(id: bID), "B's saved row is not rolled back")
        for clip in b.clips { await assertFileExists(store, clip.mediaRelativePath, true, "B media preserved") }
        XCTAssertTrue(repository.deletedIDs.isEmpty, "neither B nor A deleted")
        XCTAssertNotNil(try repository.project(id: a.id))
        await assertFileExists(store, aMedia, true, "A untouched without a verified B")
    }

    // MARK: Select Clips — two-save `.replacingSaved` retire-A

    func testFailedOldProjectDeletionPreservesAMedia() async throws {
        let repository = FailableProjectRepository()
        let (a, aMedia) = try await seedA(repository)
        repository.deleteFails = true
        guard case .committed(let bID) = try await compose(.replacingSaved(a.id), repository) else { return XCTFail() }
        XCTAssertNotNil(try repository.project(id: a.id))
        await assertFileExists(store, aMedia, true, "A's row survives, so its media must too")
        let b = try XCTUnwrap(try repository.project(id: bID))
        await assertFileExists(store, b.clips[0].mediaRelativePath, true)
    }

    func testOldProjectDeletionThatThrewAfterCommittingPreservesAMediaForRecovery() async throws {
        let repository = FailableProjectRepository()
        let (a, aMedia) = try await seedA(repository)
        repository.deleteThrowsAfterCommit = true
        guard case .committed(let bID) = try await compose(.replacingSaved(a.id), repository) else { return XCTFail() }
        XCTAssertNil(try repository.project(id: a.id), "the delete landed")
        await assertFileExists(store, aMedia, true, "a thrown delete is not confirmation: media preserved")
        let report = await recovery(repository).recoverOrphans()
        XCTAssertEqual(report.orphanProjectDirsRemoved, 1, "the absent row's directory is startup recovery's")
        await assertFileExists(store, aMedia, false)
        XCTAssertEqual(projectDirectories(), [bID.uuidString])
    }

    func testUnconfirmableAbsencePreservesAMedia() async throws {
        let repository = FailableProjectRepository()
        let (a, aMedia) = try await seedA(repository)
        repository.unreadableIDs = [a.id]
        guard case .committed = try await compose(.replacingSaved(a.id), repository) else { return XCTFail() }
        XCTAssertEqual(repository.deletedIDs, [a.id])
        await assertFileExists(store, aMedia, true, "an unreadable re-read does not confirm absence")
    }

    func testVerifiedReplacementWithConfirmedAbsenceStillRemovesAMedia() async throws {
        let repository = FailableProjectRepository()
        let (a, aMedia) = try await seedA(repository)
        guard case .committed(let bID) = try await compose(.replacingSaved(a.id), repository) else { return XCTFail() }
        await assertFileExists(store, aMedia, false)
        XCTAssertEqual(projectDirectories(), [bID.uuidString])
    }

    func testPreSaveMaterialisationFailureStillCleansItsOwnDirectory() async throws {
        let repository = FailableProjectRepository()
        let (_, aMedia) = try await seedA(repository)
        let workspace = try await store.beginWorkspace()
        let sources = try await TestSupport.adoptedSources([try await TestMediaFixtures.shared.portrait(seconds: 2), try await TestMediaFixtures.shared.portrait(seconds: 3)], into: workspace, store: store)
        // The second source is gone (the fake inspector still passes it): #1 materialises, #2 fails pre-save.
        let coordinator = ProjectCompositionCoordinator(repository: repository, mediaStore: store,
                                                        validator: Phase5ReadyMediaValidator(inspector: FakeProjectMediaInspector(.ready())),
                                                        storage: FakeProjectStorageGate(verdict: .sufficient), lifecycle: gate)
        try FileManager.default.removeItem(at: sources[1].url)
        let outcome = await coordinator.compose(.fresh, sources: sources, workspace: workspace)
        XCTAssertEqual(outcome, .failed(.materialization))
        XCTAssertEqual(projectDirectories().count, 1, "B's partial directory removed (pre-save, owned)")
        XCTAssertEqual(repository.createCount, 1, "only A was ever saved")
        await assertFileExists(store, aMedia, true, "unrelated existing media untouched")
    }

    // MARK: Editor Add / Replace

    private struct Editor {
        let model: ProjectEditorModel
        let repository: FailableProjectRepository
        let project: VlogProject
        let existing: [String]
    }

    /// `A` (file present) and, with `withUnavailable`, `B` (file missing).
    private func makeEditor(withUnavailable: Bool = false) async throws -> Editor {
        let repository = FailableProjectRepository()
        let id = UUID()
        var clips: [VlogClip] = []
        for index in 0..<(withUnavailable ? 2 : 1) {
            let clipID = UUID()
            let path = try ProjectMediaStore.committedMediaPath(projectID: id, clipID: clipID)
            if index == 0 {
                let url = await store.url(for: path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(repeating: 0xAB, count: 128).write(to: url)
            }
            clips.append(try VlogClip(id: clipID, projectID: id, sourceKind: .recorded, mediaRelativePath: path,
                                      sourceDuration: .seconds(3), trimDuration: .seconds(3), sortOrder: index))
        }
        let project = try VlogProject(id: id, orientation: .portrait9x16, clips: clips)
        try repository.create(project)
        let selector = FakeProjectMediaSelector(script: .fixtures([try await TestMediaFixtures.shared.portrait(seconds: 2)]))
        let appender = ProjectClipAppendCoordinator(mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()), storage: FakeProjectStorageGate(verdict: .sufficient))
        let acquisition = EditorClipAcquisition(mediaStore: store, mediaSelector: selector, storageGate: FakeProjectStorageGate(verdict: .sufficient), appender: appender, lifecycle: gate)
        let model = ProjectEditorModel(project: project, repository: repository, thumbnails: FakeClipThumbnailProvider(),
                                       acquisition: acquisition, availability: CommittedMediaAvailabilityChecker(resolver: store))
        await model.refreshAvailability()
        return Editor(model: model, repository: repository, project: project, existing: mediaFiles(id))
    }

    func testAddWhoseUpdateCommittedThenThrewKeepsTheNewMedia() async throws {
        let e = try await makeEditor()
        e.repository.updateThrowsAfterCommit = true
        let added = await e.model.addClips()
        XCTAssertEqual(added, 0)
        XCTAssertEqual(e.model.editorMessage, .addFailed, "presentation unchanged (pending D8.5)")
        let stored = try XCTUnwrap(try e.repository.project(id: e.project.id))
        XCTAssertEqual(stored.clips.count, 2, "the update landed")
        guard stored.clips.count == 2 else { return }
        await assertFileExists(store, stored.clips[1].mediaRelativePath, true, "the saved row's media is preserved")
        XCTAssertTrue(Set(mediaFiles(e.project.id)).isSuperset(of: e.existing), "existing media untouched")
        XCTAssertEqual(e.model.project, e.project, "known gap: the model keeps its previous in-memory state (reload pending)")
    }

    func testAddWithFailedReadBackVerificationKeepsTheNewMedia() async throws {
        let e = try await makeEditor()
        // The gated target check still sees the Project; from the update on, the read-back cannot.
        let repository = e.repository, projectID = e.project.id
        repository.onUpdate = { repository.hiddenIDs = [projectID] }
        let added = await e.model.addClips()
        XCTAssertEqual(added, 0)
        let stored = try XCTUnwrap(try e.repository.inner.project(id: e.project.id))
        XCTAssertEqual(stored.clips.count, 2, "the update landed")
        guard stored.clips.count == 2 else { return }
        await assertFileExists(store, stored.clips[1].mediaRelativePath, true)
        XCTAssertEqual(mediaFiles(e.project.id).count, e.existing.count + 1)
    }

    func testAddUpdateErrorWithoutVisibleCommitPreservesTheNewFile() async throws {
        let e = try await makeEditor()
        e.repository.updateFails = true
        let added = await e.model.addClips()
        XCTAssertEqual(added, 0)
        XCTAssertEqual(try e.repository.project(id: e.project.id), e.project)
        XCTAssertEqual(mediaFiles(e.project.id).count, e.existing.count + 1, "a thrown update is not proof: the file is preserved")
        XCTAssertTrue(Set(mediaFiles(e.project.id)).isSuperset(of: e.existing))
    }

    func testReplaceWhoseUpdateCommittedThenThrewKeepsTheReplacementMedia() async throws {
        let e = try await makeEditor(withUnavailable: true)
        e.model.select(e.project.clips[1].id)
        XCTAssertTrue(e.model.canReplaceSelectedClip)
        e.repository.updateThrowsAfterCommit = true
        let replaced = await e.model.replaceSelectedClip()
        XCTAssertNil(replaced)
        XCTAssertEqual(e.model.editorMessage, .replaceFailed)
        let stored = try XCTUnwrap(try e.repository.project(id: e.project.id))
        let d = try XCTUnwrap(stored.clips.first { !e.project.durableClips.map(\.id).contains($0.id) }, "D was saved")
        await assertFileExists(store, d.mediaRelativePath, true, "the saved replacement's media is preserved")
        XCTAssertTrue(Set(mediaFiles(e.project.id)).isSuperset(of: e.existing))
    }

    func testPreSaveTargetRefusalStillCreatesNothing() async throws {
        let e = try await makeEditor(withUnavailable: true)
        e.model.select(e.project.clips[1].id)
        // The target leaves the store before the gated section: refused before materialisation.
        var changed = e.project
        try changed.deleteClip(id: e.project.clips[1].id)
        try e.repository.update(changed)
        let replaced = await e.model.replaceSelectedClip()
        XCTAssertNil(replaced)
        XCTAssertEqual(mediaFiles(e.project.id), e.existing, "nothing materialised, nothing removed")
    }
}
