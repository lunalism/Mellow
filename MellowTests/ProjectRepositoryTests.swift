import Foundation
import SwiftData
import XCTest
@testable import Mellow

@MainActor
final class ProjectRepositoryTests: XCTestCase {
    func testInMemoryRepositoryCreatesAndReadsProject() throws {
        let repository = InMemoryProjectRepository()
        let project = try makeProject()

        try repository.create(project)

        XCTAssertEqual(try repository.project(id: project.id), project)
    }

    func testInMemoryRepositoryUpdatesSameOrientation() throws {
        let repository = InMemoryProjectRepository()
        var project = try makeProject()
        try repository.create(project)
        let updatedAt = project.updatedAt.addingTimeInterval(60)
        try project.reorderClip(id: project.clips[1].id, toIndex: 0, updatedAt: updatedAt)

        try repository.update(project)

        XCTAssertEqual(try repository.project(id: project.id), project)
        XCTAssertEqual(try repository.project(id: project.id)?.orientation, .portrait9x16)
    }

    func testInMemoryRepositoryRejectsOrientationMutationAndPreservesProject() throws {
        let repository = InMemoryProjectRepository()
        let originalProject = try makeProject(orientation: .portrait9x16)
        try repository.create(originalProject)
        let changedOrientationProject = try VlogProject(
            id: originalProject.id,
            createdAt: originalProject.createdAt,
            updatedAt: originalProject.updatedAt.addingTimeInterval(60),
            orientation: .landscape16x9,
            clips: originalProject.clips
        )

        XCTAssertThrowsError(try repository.update(changedOrientationProject)) { error in
            XCTAssertEqual(error as? ProjectRepositoryError, .projectOrientationImmutable)
        }

        XCTAssertEqual(try repository.project(id: originalProject.id), originalProject)
    }

    func testInMemoryRepositoryDeletesProject() throws {
        let repository = InMemoryProjectRepository()
        let project = try makeProject()
        try repository.create(project)

        try repository.deleteProject(id: project.id)

        XCTAssertNil(try repository.project(id: project.id))
    }

    func testInMemoryRepositoryReturnsMultipleRecentProjects() throws {
        let repository = InMemoryProjectRepository()
        let earlier = try makeProject(updatedAt: Date(timeIntervalSince1970: 100))
        let later = try makeProject(updatedAt: Date(timeIntervalSince1970: 200))
        try repository.create(earlier)
        try repository.create(later)

        XCTAssertEqual(try repository.recentProjects().map(\.id), [later.id, earlier.id])
    }

    func testSwiftDataRepositoryCreatesReadsAndDeletesProject() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        let repository = environment.repository
        let project = try makeProject()

        try repository.create(project)
        XCTAssertEqual(try repository.project(id: project.id), project)

        try repository.deleteProject(id: project.id)
        XCTAssertNil(try repository.project(id: project.id))
    }

    func testSwiftDataRepositoryUpdatesMutableMetadataWhilePreservingOrientation() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        let repository = environment.repository
        var project = try makeProject(orientation: .portrait9x16)
        try repository.create(project)
        let updatedAt = project.updatedAt.addingTimeInterval(60)
        try project.reorderClip(id: project.clips[1].id, toIndex: 0, updatedAt: updatedAt)

        try repository.update(project)

        let persistedProject = try XCTUnwrap(try repository.project(id: project.id))
        XCTAssertEqual(persistedProject, project)
        XCTAssertEqual(persistedProject.orientation, .portrait9x16)
    }

    func testSwiftDataRepositoryRejectsOrientationMutationAndPreservesProjectAfterReopen() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        let repository = environment.repository
        let originalProject = try makeProject(orientation: .portrait9x16)
        try repository.create(originalProject)
        let changedOrientationProject = try VlogProject(
            id: originalProject.id,
            createdAt: originalProject.createdAt,
            updatedAt: originalProject.updatedAt.addingTimeInterval(60),
            orientation: .landscape16x9,
            clips: originalProject.clips
        )

        XCTAssertThrowsError(try repository.update(changedOrientationProject)) { error in
            XCTAssertEqual(error as? ProjectRepositoryError, .projectOrientationImmutable)
        }

        let reopenedEnvironment = try makeSwiftDataEnvironment(storeURL: store.url)
        XCTAssertEqual(
            try reopenedEnvironment.repository.project(id: originalProject.id),
            originalProject
        )
    }

    func testSwiftDataRepositoryReturnsAllStoredProjects() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        let repository = environment.repository
        let firstProject = try makeProject(updatedAt: Date(timeIntervalSince1970: 100))
        let secondProject = try makeProject(updatedAt: Date(timeIntervalSince1970: 200))
        try repository.create(firstProject)
        try repository.create(secondProject)

        let retrievedProjectIDs = Set(try repository.recentProjects().map(\.id))

        XCTAssertEqual(retrievedProjectIDs, Set([firstProject.id, secondProject.id]))
    }

    func testSwiftDataMetadataPersistsAcrossReleasedWriterEnvironment() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let project = try makeProject()

        do {
            let writerEnvironment = try makeSwiftDataEnvironment(storeURL: store.url)
            try writerEnvironment.repository.create(project)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))

        let reopenedEnvironment = try makeSwiftDataEnvironment(storeURL: store.url)

        XCTAssertEqual(try reopenedEnvironment.repository.project(id: project.id), project)
    }

    // MARK: - Reorder persistence (Phase 5 STEP 9)

    /// A B C → C A B through `update`, then the container is released and a fresh one reopened:
    /// the order, normalised `sortOrder`, clip identities and media metadata all survive; a second
    /// reorder after reopen persists the same way.
    func testSwiftDataReorderSurvivesContainerReopen() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let projectID = UUID()
        let clips = try (0..<3).map { try makeClip(projectID: projectID, sortOrder: $0) }
        let (a, b, c) = (clips[0].id, clips[1].id, clips[2].id)
        var project = try VlogProject(id: projectID, orientation: .portrait9x16, clips: clips)
        let originalByID = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })

        do {
            let environment = try makeSwiftDataEnvironment(storeURL: store.url)
            try environment.repository.create(project)
            try project.reorderClip(id: c, toIndex: 0)
            try environment.repository.update(project)
            XCTAssertEqual(try environment.repository.project(id: projectID)?.clips.map(\.id), [c, a, b])
        }

        let reopened = try makeSwiftDataEnvironment(storeURL: store.url)
        var reloaded = try XCTUnwrap(try reopened.repository.project(id: projectID))
        XCTAssertEqual(reloaded.clips.map(\.id), [c, a, b])
        XCTAssertEqual(reloaded.clips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(reloaded.totalDuration, project.totalDuration)
        for clip in reloaded.clips {
            let original = try XCTUnwrap(originalByID[clip.id])
            XCTAssertEqual(clip.mediaRelativePath, original.mediaRelativePath)
            XCTAssertEqual(clip.sourceDuration, original.sourceDuration)
            XCTAssertEqual(clip.trimStart, original.trimStart)
            XCTAssertEqual(clip.trimDuration, original.trimDuration)
            XCTAssertEqual(clip.sourceKind, original.sourceKind)
        }

        // Second reorder after reopen: A after B → C B A.
        try reloaded.reorderClip(id: a, toIndex: 2)
        try reopened.repository.update(reloaded)
        let again = try makeSwiftDataEnvironment(storeURL: store.url)
        let final = try XCTUnwrap(try again.repository.project(id: projectID))
        XCTAssertEqual(final.clips.map(\.id), [c, b, a])
        XCTAssertEqual(final.clips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(Set(final.clips.map(\.id)), Set([a, b, c]))
    }

    /// `update` reconciles clips by identity and deletes persisted clips missing from the incoming
    /// Project. A reorder carries the identical clip set, so nothing is deleted or re-created: the
    /// persisted clip rows are the same three rows before and after.
    func testSwiftDataSameClipSetUpdateRemovesNoPersistedClip() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        let projectID = UUID()
        let clips = try (0..<3).map { try makeClip(projectID: projectID, sortOrder: $0) }
        var project = try VlogProject(id: projectID, orientation: .portrait9x16, clips: clips)
        try environment.repository.create(project)
        let rowsBefore = try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>())
        XCTAssertEqual(rowsBefore.count, 3)
        let identifiersBefore = Set(rowsBefore.map { ObjectIdentifier($0) })

        try project.reorderClip(id: clips[2].id, toIndex: 0)
        try environment.repository.update(project)

        let rowsAfter = try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>())
        XCTAssertEqual(rowsAfter.count, 3, "no clip row was deleted")
        XCTAssertEqual(Set(rowsAfter.map { ObjectIdentifier($0) }), identifiersBefore, "the same rows were updated in place")
        XCTAssertEqual(Set(rowsAfter.map(\.id)), Set(clips.map(\.id)))
        XCTAssertEqual(rowsAfter.sorted { $0.sortOrder < $1.sortOrder }.map(\.id), [clips[2].id, clips[0].id, clips[1].id])
    }

    private func makeSwiftDataEnvironment(storeURL: URL) throws -> SwiftDataRepositoryEnvironment {
        let container = try MellowModelContainer.makePersistentContainer(storeURL: storeURL)
        return SwiftDataRepositoryEnvironment(container: container)
    }

    private func makeProject(
        id: UUID = UUID(),
        orientation: ProjectOrientation = .portrait9x16,
        updatedAt: Date = .now
    ) throws -> VlogProject {
        let clips = [
            try makeClip(projectID: id, sortOrder: 0),
            try makeClip(projectID: id, sortOrder: 1)
        ]
        return try VlogProject(
            id: id,
            createdAt: updatedAt.addingTimeInterval(-60),
            updatedAt: updatedAt,
            orientation: orientation,
            clips: clips
        )
    }

    private func makeClip(projectID: UUID, sortOrder: Int) throws -> VlogClip {
        let clipID = UUID()
        return try VlogClip(
            id: clipID,
            projectID: projectID,
            sourceKind: .recorded,
            mediaRelativePath: try RelativeMediaPath("projects/\(projectID)/\(clipID).mov"),
            sourceDuration: .seconds(5),
            trimDuration: .seconds(5),
            sortOrder: sortOrder
        )
    }

    private func makeStore() throws -> TemporaryStore {
        let directory = URL.temporaryDirectory.appending(path: "MellowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return TemporaryStore(
            directory: directory,
            url: directory.appending(path: "metadata.store")
        )
    }
}

private struct TemporaryStore {
    let directory: URL
    let url: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class SwiftDataRepositoryEnvironment {
    let container: ModelContainer
    let repository: SwiftDataProjectRepository

    init(container: ModelContainer) {
        self.container = container
        self.repository = SwiftDataProjectRepository(modelContext: container.mainContext)
    }
}
