import XCTest
@testable import Mellow

@MainActor
final class ProjectCompositionCoordinatorTests: XCTestCase {
    private func makeProject(
        orientation: ProjectOrientation = .portrait9x16,
        createdAt: Date,
        updatedAt: Date? = nil
    ) throws -> VlogProject {
        try VlogProject(createdAt: createdAt, updatedAt: updatedAt, orientation: orientation)
    }

    func testNoProjectsReturnsNil() throws {
        let repository = InMemoryProjectRepository()
        let coordinator = ProjectCompositionCoordinator(repository: repository)
        XCTAssertNil(try coordinator.lastSavedProject())
    }

    func testSingleProjectReturnsThatProject() throws {
        let repository = InMemoryProjectRepository()
        let project = try makeProject(createdAt: Date(timeIntervalSince1970: 100))
        try repository.create(project)
        let coordinator = ProjectCompositionCoordinator(repository: repository)
        XCTAssertEqual(try coordinator.lastSavedProject()?.id, project.id)
    }

    func testMultipleProjectsReturnsMostRecentByCanonicalOrdering() throws {
        let repository = InMemoryProjectRepository()
        let older = try makeProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
        let newer = try makeProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 500))
        try repository.create(older)
        try repository.create(newer)
        let coordinator = ProjectCompositionCoordinator(repository: repository)
        XCTAssertEqual(try coordinator.lastSavedProject()?.id, newer.id, "most recent updatedAt wins")
    }

    func testLookupDoesNotDeleteOrMutateProjects() throws {
        let repository = InMemoryProjectRepository()
        let a = try makeProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
        let b = try makeProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 500))
        try repository.create(a)
        try repository.create(b)
        let coordinator = ProjectCompositionCoordinator(repository: repository)

        _ = try coordinator.lastSavedProject()
        _ = try coordinator.lastSavedProject()

        // The read-only lookup must not delete the older project or mutate anything.
        let all = try repository.recentProjects()
        XCTAssertEqual(Set(all.map(\.id)), [a.id, b.id], "no project removed by lookup")
    }
}
