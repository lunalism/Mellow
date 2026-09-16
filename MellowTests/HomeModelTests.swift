import Foundation
import SwiftData
import XCTest
@testable import Mellow

@MainActor
final class HomeModelTests: XCTestCase {
    func testLaunchAndRecentNavigationDoNotCreateProjects() throws {
        let repository = InMemoryProjectRepository()
        let model = HomeModel(repository: repository, router: AppRouter())
        model.loadRecent()
        model.loadRecent()
        XCTAssertTrue(model.router.path.isEmpty)
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        model.showRecent()
        model.createProject(orientation: .portrait9x16)
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        model.router.path = []
        model.createProject(orientation: .landscape16x9)
        XCTAssertEqual(try repository.recentProjects().count, 1)
        model.router.path = []
        model.showRecent()
        XCTAssertEqual(model.router.path, [.recent])
        XCTAssertEqual(try repository.recentProjects().count, 1)
    }

    func testBothOrientationsPersistAcrossRecreationAndDeletion() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "metadata.store")
        var ids: [UUID] = []
        do {
            let container = try MellowModelContainer.makePersistentContainer(storeURL: url)
            let model = HomeModel(repository: SwiftDataProjectRepository(modelContext: container.mainContext), router: AppRouter())
            model.loadRecent()
            XCTAssertTrue(model.projects.isEmpty)
            for orientation in ProjectOrientation.allCases {
                model.router.path = []
                model.createProject(orientation: orientation)
                let project = try XCTUnwrap(model.openedProject)
                ids.append(project.id)
                XCTAssertEqual(project.orientation, orientation)
                XCTAssertTrue(project.clips.isEmpty)
                XCTAssertEqual(model.router.path, [.camera(project.id)])
                XCTAssertEqual(project.displayName(), ProjectDisplayNameFormatter.displayName(for: project.createdAt))
                model.createProject(orientation: orientation)
            }
            XCTAssertEqual(model.projects.count, 2, "Repeated selection must not duplicate a saved project")
        }
        do {
            let container = try MellowModelContainer.makePersistentContainer(storeURL: url)
            let model = HomeModel(repository: SwiftDataProjectRepository(modelContext: container.mainContext), router: AppRouter())
            model.loadRecent()
            XCTAssertEqual(model.projects.count, 2)
            for (index, orientation) in ProjectOrientation.allCases.enumerated() {
                model.openProject(id: ids[index])
                XCTAssertEqual(model.openedProject?.orientation, orientation)
                XCTAssertEqual(model.router.path, [.recent, .camera(ids[index])])
            }
            model.pendingDeletion = model.projects.first { $0.id == ids[0] }
            model.confirmDeletion()
            XCTAssertEqual(model.projects.map(\.id), [ids[1]])
        }
        let container = try MellowModelContainer.makePersistentContainer(storeURL: url)
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        XCTAssertEqual(try repository.recentProjects().map(\.id), [ids[1]])
    }

    func testCreationFailureDoesNotNavigateAndRetryWorks() throws {
        let repository = FailingProjectRepository()
        let model = HomeModel(repository: repository, router: AppRouter())
        model.router.path = []
        repository.shouldFail = true
        model.createProject(orientation: .portrait9x16)
        XCTAssertEqual(model.failure, .creation)
        XCTAssertEqual(model.router.path, [])
        XCTAssertNil(model.openedProject)
        XCTAssertTrue(model.projects.isEmpty)
        repository.shouldFail = false
        model.createProject(orientation: .portrait9x16)
        XCTAssertEqual(model.projects.count, 1)
    }

    func testDeleteCancelAndFailurePreserveProject() throws {
        let repository = FailingProjectRepository()
        let project = try VlogProject(orientation: .landscape16x9)
        try repository.create(project)
        let model = HomeModel(repository: repository, router: AppRouter())
        model.loadRecent()
        model.pendingDeletion = project
        model.pendingDeletion = nil
        model.confirmDeletion()
        XCTAssertEqual(try repository.project(id: project.id), project)
        model.pendingDeletion = project
        repository.shouldFail = true
        model.confirmDeletion()
        XCTAssertEqual(model.failure, .deletion)
        XCTAssertEqual(model.projects, [project])
        repository.shouldFail = false
        XCTAssertEqual(try repository.project(id: project.id), project)
    }

    func testLoadFailureIsNotPresentedAsEmptyAndCanRecover() throws {
        let repository = FailingProjectRepository()
        let model = HomeModel(repository: repository, router: AppRouter())
        repository.shouldFail = true
        model.loadRecent()
        XCTAssertTrue(model.loadFailed)
        repository.shouldFail = false
        model.loadRecent()
        XCTAssertFalse(model.loadFailed)
    }

    func testOpenFailureAndMissingProjectDoNotNavigate() throws {
        let repository = FailingProjectRepository()
        let model = HomeModel(repository: repository, router: AppRouter())
        repository.shouldFail = true
        model.openProject(id: UUID())
        XCTAssertEqual(model.failure, .opening)
        XCTAssertTrue(model.router.path.isEmpty)
        repository.shouldFail = false
        model.openProject(id: UUID())
        XCTAssertEqual(model.failure, .unavailable)
        XCTAssertTrue(model.router.path.isEmpty)
    }

    func testSwiftDataFailedWritesRollbackInsteadOfRemainingPending() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "metadata.store")
        let original = try VlogProject(orientation: .portrait9x16)
        do {
            let writer = try MellowModelContainer.makePersistentContainer(storeURL: url)
            try SwiftDataProjectRepository(modelContext: writer.mainContext).create(original)
        }
        let schema = Schema([PersistedVlogProject.self, PersistedVlogClip.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url, allowsSave: false))
        let context = container.mainContext
        let repository = SwiftDataProjectRepository(modelContext: context)
        let newProject = try VlogProject(orientation: .landscape16x9)
        XCTAssertThrowsError(try repository.create(newProject))
        XCTAssertFalse(context.hasChanges)
        XCTAssertNil(try repository.project(id: newProject.id))
        XCTAssertThrowsError(try repository.deleteProject(id: original.id))
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try repository.project(id: original.id), original)
    }

    func testRecentOrderingIsDeterministicInBothRepositories() throws {
        let schema = Schema([PersistedVlogProject.self, PersistedVlogClip.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repositories: [any ProjectRepository] = [InMemoryProjectRepository(), SwiftDataProjectRepository(modelContext: container.mainContext)]
        let date = Date(timeIntervalSince1970: 100)
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let low = try VlogProject(id: lowID, createdAt: date, orientation: .portrait9x16)
        let high = try VlogProject(id: highID, createdAt: date, orientation: .landscape16x9)
        let newest = try VlogProject(createdAt: date, updatedAt: date.addingTimeInterval(2), orientation: .portrait9x16)
        let newerCreation = try VlogProject(createdAt: date.addingTimeInterval(1), updatedAt: date, orientation: .portrait9x16)
        for repository in repositories {
            for project in [high, low, newerCreation, newest] { try repository.create(project) }
            XCTAssertEqual(try repository.recentProjects().map(\.id), [newest.id, newerCreation.id, low.id, high.id])
        }
    }

    func testRepresentativeSourceUsesCurrentOrderAndUsability() throws {
        let id = UUID()
        let clips = try (0..<3).map { index in
            try VlogClip(projectID: id, sourceKind: .recorded,
                         mediaRelativePath: RelativeMediaPath("clip-\(index).mov"),
                         sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: index)
        }
        let empty = try VlogProject(orientation: .portrait9x16)
        XCTAssertNil(RepresentativeThumbnailSource.clipID(in: empty) { _ in true })
        let single = try VlogProject(id: id, orientation: .portrait9x16, clips: [clips[0]])
        XCTAssertEqual(RepresentativeThumbnailSource.clipID(in: single) { _ in true }, clips[0].id)
        var project = try VlogProject(id: id, orientation: .portrait9x16, clips: clips.reversed())
        XCTAssertEqual(RepresentativeThumbnailSource.clipID(in: project) { _ in true }, clips[0].id)
        XCTAssertEqual(RepresentativeThumbnailSource.clipID(in: project) { $0.id != clips[0].id }, clips[1].id)
        XCTAssertNil(RepresentativeThumbnailSource.clipID(in: project) { _ in false })
        try project.reorderClip(id: clips[2].id, toIndex: 0)
        XCTAssertEqual(RepresentativeThumbnailSource.clipID(in: project) { _ in true }, clips[2].id)
    }
}

@MainActor
private final class FailingProjectRepository: ProjectRepository {
    let underlying = InMemoryProjectRepository()
    var shouldFail = false
    private func check() throws { if shouldFail { throw ProjectRepositoryError.invalidPersistedMetadata } }
    func create(_ project: VlogProject) throws { try check(); try underlying.create(project) }
    func project(id: UUID) throws -> VlogProject? { try check(); return try underlying.project(id: id) }
    func recentProjects() throws -> [VlogProject] { try check(); return try underlying.recentProjects() }
    func update(_ project: VlogProject) throws { try check(); try underlying.update(project) }
    func finalizeDeletedClip(projectID: UUID, clipID: UUID) throws { try check(); try underlying.finalizeDeletedClip(projectID: projectID, clipID: clipID) }
    func deleteProject(id: UUID) throws { try check(); try underlying.deleteProject(id: id) }
}
