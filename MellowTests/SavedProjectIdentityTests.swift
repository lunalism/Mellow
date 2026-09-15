import SwiftData
import XCTest
@testable import Mellow

/// V1 invariant: `기존 프로젝트 불러오기` deterministically opens the exact current saved Project, and
/// nothing short of a successful composition changes which Project is current.
@MainActor
final class SavedProjectIdentityTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!
    override func setUp() {
        root = TestSupport.temporaryRoot("identity")
        store = ProjectMediaStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func clip(projectID: UUID, seconds: Int64) throws -> VlogClip {
        try VlogClip(projectID: projectID, sourceKind: .imported, mediaRelativePath: try RelativeMediaPath("Projects/\(projectID.uuidString)/Media/\(UUID().uuidString).mov"), sourceDuration: .seconds(seconds), trimDuration: .seconds(seconds), sortOrder: 0)
    }

    private func project(seconds: Int64, createdAt: Date, updatedAt: Date? = nil) throws -> VlogProject {
        let id = UUID()
        return try VlogProject(id: id, createdAt: createdAt, updatedAt: updatedAt, orientation: .portrait9x16, clips: [try clip(projectID: id, seconds: seconds)])
    }

    private func coordinator(_ repository: any ProjectRepository) -> ProjectCompositionCoordinator {
        ProjectCompositionCoordinator(repository: repository, mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()), storage: FakeProjectStorageGate(verdict: .sufficient))
    }

    private func model(_ repository: any ProjectRepository, selector: FakeProjectMediaSelector, opened: @escaping (UUID) -> Void) -> ProjectsEntryModel {
        ProjectsEntryModel(composition: coordinator(repository), mediaStore: store, mediaSelector: selector, storageGate: FakeProjectStorageGate(verdict: .sufficient), onContinueEditing: opened, onProjectCommitted: { _ in })
    }

    func testSingleSavedProjectOpensItselfRepeatedly() throws {
        let repository = InMemoryProjectRepository()
        let a = try project(seconds: 4, createdAt: Date(timeIntervalSince1970: 1_000))
        try repository.create(a)
        var opened: [UUID] = []
        let model = model(repository, selector: FakeProjectMediaSelector(script: .cancel)) { opened.append($0) }
        for _ in 0..<5 {
            model.load()            // Projects screen appears / re-appears after Back
            model.continueEditing() // 기존 프로젝트 불러오기
        }
        XCTAssertEqual(opened, Array(repeating: a.id, count: 5))
        XCTAssertEqual(try XCTUnwrap(repository.project(id: a.id)).totalDuration, .seconds(4))
    }

    func testHistoricalSecondProjectDoesNotFlipCurrentSelection() throws {
        let repository = InMemoryProjectRepository()
        let older3s = try project(seconds: 3, createdAt: Date(timeIntervalSince1970: 1_000))
        let newer4s = try project(seconds: 4, createdAt: Date(timeIntervalSince1970: 2_000))
        try repository.create(older3s)
        try repository.create(newer4s)
        let coordinator = coordinator(repository)
        let ids = try (0..<20).map { _ in try XCTUnwrap(coordinator.lastSavedProject()).id }
        XCTAssertEqual(Set(ids), [newer4s.id], "current selection never alternates")

        var opened: [UUID] = []
        let model = model(repository, selector: FakeProjectMediaSelector(script: .cancel)) { opened.append($0) }
        model.load(); model.continueEditing()
        model.load(); model.continueEditing() // entering / leaving the Editor re-runs load()
        XCTAssertEqual(opened, [newer4s.id, newer4s.id])
        XCTAssertEqual(Set(try repository.recentProjects().map(\.id)), [older3s.id, newer4s.id], "lookup never deletes the historical Project")
    }

    func testTimestampTieIsBrokenDeterministicallyAndStably() throws {
        let repository = InMemoryProjectRepository()
        let stamp = Date(timeIntervalSince1970: 5_000)
        let x = try project(seconds: 3, createdAt: stamp, updatedAt: stamp)
        let y = try project(seconds: 4, createdAt: stamp, updatedAt: stamp)
        try repository.create(x)
        try repository.create(y)
        let expected = [x, y].sorted(by: RecentProjectOrdering.precedes)[0].id
        XCTAssertEqual(expected, min(x.id.uuidString, y.id.uuidString) == x.id.uuidString ? x.id : y.id, "tie → lower UUID string")
        let coordinator = coordinator(repository)
        for _ in 0..<20 { XCTAssertEqual(try coordinator.lastSavedProject()?.id, expected) }
    }

    func testCancelAndPreparationRefusalDoNotChangeCurrentProject() async throws {
        let repository = InMemoryProjectRepository()
        let a = try project(seconds: 4, createdAt: Date(timeIntervalSince1970: 1_000))
        try repository.create(a)
        var opened: [UUID] = []

        let cancel = model(repository, selector: FakeProjectMediaSelector(script: .cancel)) { opened.append($0) }
        cancel.load()
        await cancel.runSelectClips(.replacingSaved(a.id))
        cancel.load(); cancel.continueEditing()

        let long = try await TestMediaFixtures.shared.portrait(seconds: 7)
        let prep = model(repository, selector: FakeProjectMediaSelector(script: .fixtures([long]))) { opened.append($0) }
        prep.load()
        await prep.runSelectClips(.replacingSaved(a.id))
        XCTAssertEqual(prep.compositionMessage, .requiresImportPreparation(.tooLong))
        prep.load(); prep.continueEditing()

        XCTAssertEqual(opened, [a.id, a.id])
        XCTAssertEqual(try repository.recentProjects().map(\.id), [a.id])
        XCTAssertEqual(try XCTUnwrap(repository.project(id: a.id)).totalDuration, .seconds(4))
    }

    /// The physically observed sequence: a confirmed one-clip session, then a presentation that is
    /// cancelled. The second session must be `.cancelled`, emit nothing, and write nothing.
    func testConfirmedSessionThenCancelledSessionWritesNothing() async throws {
        let repository = FailableProjectRepository()
        let a = try project(seconds: 3, createdAt: Date(timeIntervalSince1970: 1_000))
        try repository.create(a)
        let createsAfterSeed = repository.createCount
        let ready = try await TestMediaFixtures.shared.portrait(seconds: 4)
        let selector = FakeProjectMediaSelector(script: .fixtures([ready]))
        var opened: [UUID] = []
        let model = model(repository, selector: selector) { opened.append($0) }
        model.load()

        // Session 1: replacement with one confirmed 4 s clip → B committed, A retired.
        await model.runSelectClips(.replacingSaved(a.id))
        let b = try XCTUnwrap(coordinator(repository).lastSavedProject())
        XCTAssertNotEqual(b.id, a.id)
        XCTAssertEqual(repository.createCount, createsAfterSeed + 1)
        XCTAssertEqual(repository.deletedIDs, [a.id])

        // Session 2: the picker is presented again and cancelled — nothing from session 1 is reused.
        selector.script = .cancel
        model.load()
        await model.runSelectClips(.replacingSaved(b.id))
        XCTAssertNil(model.compositionMessage)
        XCTAssertEqual(repository.createCount, createsAfterSeed + 1, "repository.create never called on cancel")
        XCTAssertEqual(repository.deletedIDs, [a.id], "repository.deleteProject never called on cancel")
        XCTAssertEqual(try repository.recentProjects().map(\.id), [b.id])
        let bMedia = try XCTUnwrap(repository.project(id: b.id)).clips[0].mediaRelativePath
        await assertFileExists(store, bMedia, true, "current Project media unchanged")
        model.load(); model.continueEditing()
        XCTAssertEqual(opened.last, b.id)

        // preparation refusal → reopen → cancel: still nothing.
        selector.script = .fixtures([try await TestMediaFixtures.shared.portrait(seconds: 7)])
        await model.runSelectClips(.replacingSaved(b.id))
        XCTAssertEqual(model.compositionMessage, .requiresImportPreparation(.tooLong))
        model.compositionMessage = nil
        selector.script = .cancel
        await model.runSelectClips(.replacingSaved(b.id))
        XCTAssertEqual(repository.createCount, createsAfterSeed + 1)
        XCTAssertEqual(repository.deletedIDs, [a.id])

        // cancel → reopen → a new confirmed selection composes normally (isolated session).
        selector.script = .fixtures([ready])
        await model.runSelectClips(.replacingSaved(b.id))
        let c = try XCTUnwrap(coordinator(repository).lastSavedProject())
        XCTAssertNotEqual(c.id, b.id)
        XCTAssertEqual(repository.createCount, createsAfterSeed + 2)
        XCTAssertEqual(repository.deletedIDs, [a.id, b.id])
    }

    func testCurrentProjectSurvivesRepositoryReopenUnchanged() throws {
        // Equivalent of an overwrite install / relaunch: a fresh container over the same store file.
        let storeURL = TestSupport.temporaryRoot("identity-swiftdata").appendingPathComponent("store.sqlite")
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        let older3s = try project(seconds: 3, createdAt: Date(timeIntervalSince1970: 1_000))
        let newer4s = try project(seconds: 4, createdAt: Date(timeIntervalSince1970: 2_000))
        do {
            let repository = SwiftDataProjectRepository(modelContext: ModelContext(try MellowModelContainer.makePersistentContainer(storeURL: storeURL)))
            try repository.create(older3s)
            try repository.create(newer4s)
            XCTAssertEqual(try coordinator(repository).lastSavedProject()?.id, newer4s.id)
        }
        for _ in 0..<3 {
            let reopened = SwiftDataProjectRepository(modelContext: ModelContext(try MellowModelContainer.makePersistentContainer(storeURL: storeURL)))
            let current = try XCTUnwrap(coordinator(reopened).lastSavedProject())
            XCTAssertEqual(current.id, newer4s.id, "reopen never flips the current Project")
            XCTAssertEqual(current.totalDuration, .seconds(4))
            XCTAssertEqual(try reopened.project(id: current.id)?.totalDuration, .seconds(4), "Editor load by that UUID sees the same clips")
        }
    }
}
