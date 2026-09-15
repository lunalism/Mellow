import XCTest
@testable import Mellow

@MainActor
final class ProjectsEntryModelTests: XCTestCase {
    private final class Recorder {
        var continued: [UUID] = []
        var newProject: [ProjectsEntryModel.NewProjectIntent] = []
    }

    private func makeModel(repository: any ProjectRepository, recorder: Recorder) -> ProjectsEntryModel {
        ProjectsEntryModel(
            composition: ProjectCompositionCoordinator(repository: repository),
            onContinueEditing: { recorder.continued.append($0) },
            onNewProject: { recorder.newProject.append($0) }
        )
    }

    // MARK: - No saved Project

    func testNoSavedProjectReportsNoneAndOnlyNewProjectIntent() throws {
        let repository = InMemoryProjectRepository()
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()

        XCTAssertNil(model.savedProjectID)
        XCTAssertFalse(model.hasSavedProject)

        // Continue is unavailable: it delivers nothing without a saved Project.
        model.continueEditing()
        XCTAssertTrue(recorder.continued.isEmpty)

        // New project goes straight through without a confirmation and creates nothing.
        model.requestNewProject()
        XCTAssertFalse(model.isReplacementConfirmationPresented)
        XCTAssertEqual(recorder.newProject, [.fresh])
        XCTAssertTrue(try repository.recentProjects().isEmpty, "no Project may be created by the entry")
    }

    // MARK: - Saved Project

    func testSavedProjectIsIdentifiedAndContinuePreservesExactID() throws {
        let repository = InMemoryProjectRepository()
        let older = try VlogProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100), orientation: .portrait9x16)
        let newer = try VlogProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 500), orientation: .portrait9x16)
        try repository.create(older)
        try repository.create(newer)
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()

        XCTAssertEqual(model.savedProjectID, newer.id, "coordinator's canonical saved Project")
        XCTAssertTrue(model.hasSavedProject)

        model.continueEditing()
        XCTAssertEqual(recorder.continued, [newer.id], "navigation identity is the exact saved ID")
        XCTAssertTrue(recorder.newProject.isEmpty)
        XCTAssertEqual(Set(try repository.recentProjects().map(\.id)), [older.id, newer.id], "continue deletes nothing")
    }

    func testNewProjectWithSavedProjectEntersReplacementConfirmation() throws {
        let repository = InMemoryProjectRepository()
        let saved = try VlogProject(orientation: .portrait9x16)
        try repository.create(saved)
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()

        model.requestNewProject()
        XCTAssertTrue(model.isReplacementConfirmationPresented)
        XCTAssertTrue(recorder.newProject.isEmpty, "no intent before the user confirms")
        XCTAssertEqual(try repository.recentProjects().map(\.id), [saved.id])
    }

    func testCancelLeavesSavedProjectUntouched() throws {
        let repository = InMemoryProjectRepository()
        let saved = try VlogProject(orientation: .portrait9x16)
        try repository.create(saved)
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()

        model.requestNewProject()
        model.cancelReplacement()
        XCTAssertFalse(model.isReplacementConfirmationPresented)
        XCTAssertTrue(recorder.newProject.isEmpty)
        XCTAssertTrue(recorder.continued.isEmpty)
        XCTAssertEqual(model.savedProjectID, saved.id)
        XCTAssertEqual(try repository.recentProjects().map(\.id), [saved.id])
    }

    func testConfirmEmitsConfirmedIntentWithoutMutatingPersistence() throws {
        let repository = InMemoryProjectRepository()
        let saved = try VlogProject(orientation: .portrait9x16)
        try repository.create(saved)
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()

        model.requestNewProject()
        model.confirmReplacement()
        XCTAssertFalse(model.isReplacementConfirmationPresented)
        XCTAssertEqual(recorder.newProject, [.replacingSaved(saved.id)])

        // STEP 5: the confirmed intent is delivered only; nothing is deleted, created or mutated.
        let all = try repository.recentProjects()
        XCTAssertEqual(all.map(\.id), [saved.id])
        XCTAssertEqual(all.first?.updatedAt, saved.updatedAt)
        XCTAssertEqual(model.savedProjectID, saved.id, "the entry still reports the same saved Project")
    }

    func testLoadFailureFallsBackToNoSavedProjectWithoutCreating() throws {
        let repository = FailingLookupRepository()
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()
        XCTAssertNil(model.savedProjectID)
        XCTAssertFalse(model.hasSavedProject)
        XCTAssertTrue(recorder.newProject.isEmpty)
        XCTAssertEqual(repository.created, 0, "a failed lookup never creates a Project")
    }

    /// Repository whose recency lookup fails; everything else is a no-op that counts creations.
    private final class FailingLookupRepository: ProjectRepository {
        private(set) var created = 0
        private enum LookupError: Error { case failed }
        func create(_ project: VlogProject) throws { created += 1 }
        func project(id: UUID) throws -> VlogProject? { nil }
        func recentProjects() throws -> [VlogProject] { throw LookupError.failed }
        func update(_ project: VlogProject) throws {}
        func deleteProject(id: UUID) throws {}
    }
}
