import Foundation
import XCTest
@testable import Mellow

/// ADR-050 050-D D8.0 media preservation: from a save attempt on, media the save may reference is never
/// removed. Covers Editor Add / Replace (Select Clips save outcomes: `SelectClipsSaveOutcomeTests`),
/// against a real `ProjectMediaStore` under a temporary root and the fake repository. "Throws after commit" / hidden / unreadable reads are injected repository behaviours that
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

    private func mediaFiles(_ projectID: UUID) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects/\(projectID.uuidString)/Media").path)) ?? []).sorted()
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
