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

    // MARK: - Logical deletion persistence (Phase 5 STEP 10)

    private func makeThreeClipProject() throws -> (VlogProject, [UUID]) {
        let id = UUID()
        let clips = try (0..<3).map { try makeClip(projectID: id, sortOrder: $0) }
        return (try VlogProject(id: id, orientation: .portrait9x16, clips: clips), clips.map(\.id))
    }

    func testUpdateRefusesProjectThatOmitsDurableClipInsteadOfDeletingIt() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let swiftData = try makeSwiftDataEnvironment(storeURL: store.url)
        for repository in [InMemoryProjectRepository() as any ProjectRepository, swiftData.repository] {
            let (project, ids) = try makeThreeClipProject()
            try repository.create(project)
            // The forbidden pattern: drop a clip from the active set and autosave.
            let truncated = try VlogProject(id: project.id, createdAt: project.createdAt, updatedAt: project.updatedAt, orientation: .portrait9x16, clips: Array(project.clips[0...1]))
            XCTAssertThrowsError(try repository.update(truncated)) { XCTAssertEqual($0 as? ProjectRepositoryError, .missingDurableClip) }
            XCTAssertEqual(try repository.project(id: project.id)?.clips.map(\.id), ids, "nothing was deleted")
        }
    }

    func testSwiftDataLogicalDeleteSurvivesReopenAndUndoRestoresSameClip() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        var (project, ids) = try makeThreeClipProject()
        let (a, b, c) = (ids[0], ids[1], ids[2])
        let originalB = project.clips[1]

        do {
            let environment = try makeSwiftDataEnvironment(storeURL: store.url)
            try environment.repository.create(project)
            try project.deleteClip(id: b, deletedAt: Date(timeIntervalSince1970: 500))
            try environment.repository.update(project)
            let rows = try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>())
            XCTAssertEqual(rows.count, 3, "the deleted clip's row is retained")
            XCTAssertEqual(rows.first { $0.id == b }?.deletedAt, Date(timeIntervalSince1970: 500))
        }

        let reopened = try makeSwiftDataEnvironment(storeURL: store.url)
        var reloaded = try XCTUnwrap(try reopened.repository.project(id: project.id))
        XCTAssertEqual(reloaded.clips.map(\.id), [a, c], "the deleted clip does not reappear")
        XCTAssertEqual(reloaded.clips.map(\.sortOrder), [0, 1])
        XCTAssertEqual(reloaded.deletedClips.map(\.id), [b], "…but stays durable")
        let record = try XCTUnwrap(reloaded.deletedClips[0].deletion)
        XCTAssertEqual(record.originalIndex, 1)
        XCTAssertEqual(record.previousClipID, a)
        XCTAssertEqual(record.nextClipID, c)
        XCTAssertEqual(reloaded.deletedClips[0].mediaRelativePath, originalB.mediaRelativePath)

        // An unrelated autosave (reorder) keeps the pending-deleted clip durable.
        try reloaded.reorderClip(id: c, toIndex: 0)
        try reopened.repository.update(reloaded)
        XCTAssertEqual(try reopened.repository.project(id: project.id)?.deletedClips.map(\.id), [b])

        // Undo through the restoration anchors, then reopen once more.
        try reloaded.restoreDeletedClip(id: b)
        try reopened.repository.update(reloaded)
        let finalEnvironment = try makeSwiftDataEnvironment(storeURL: store.url)
        let final = try XCTUnwrap(try finalEnvironment.repository.project(id: project.id))
        XCTAssertEqual(final.clips.map(\.id), [c, a, b], "restored after its previous anchor A")
        XCTAssertEqual(final.clips.map(\.sortOrder), [0, 1, 2])
        XCTAssertTrue(final.deletedClips.isEmpty)
        let restored = try XCTUnwrap(final.clips.first { $0.id == b })
        XCTAssertEqual(restored.mediaRelativePath, originalB.mediaRelativePath)
        XCTAssertEqual(restored.trimDuration, originalB.trimDuration)
        XCTAssertEqual(restored.sourceDuration, originalB.sourceDuration)
        XCTAssertNil(restored.deletion)
        XCTAssertEqual(try finalEnvironment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>()).count, 3, "no row was ever deleted or duplicated")
    }

    func testSwiftDataFinalizeRemovesOnlyPendingDeletedClipRow() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        var (project, ids) = try makeThreeClipProject()
        try environment.repository.create(project)

        XCTAssertThrowsError(try environment.repository.finalizeDeletedClip(projectID: project.id, clipID: ids[0])) {
            XCTAssertEqual($0 as? ProjectRepositoryError, .clipNotPendingDeletion)
        }
        try project.deleteClip(id: ids[0])
        try environment.repository.update(project)
        try environment.repository.finalizeDeletedClip(projectID: project.id, clipID: ids[0])

        let reopened = try makeSwiftDataEnvironment(storeURL: store.url)
        let reloaded = try XCTUnwrap(try reopened.repository.project(id: project.id))
        XCTAssertEqual(reloaded.clips.map(\.id), [ids[1], ids[2]])
        XCTAssertTrue(reloaded.deletedClips.isEmpty)
        XCTAssertEqual(try reopened.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>()).count, 2)
        XCTAssertThrowsError(try reopened.repository.finalizeDeletedClip(projectID: project.id, clipID: ids[0]))
        XCTAssertThrowsError(try reopened.repository.finalizeDeletedClip(projectID: UUID(), clipID: ids[1])) {
            XCTAssertEqual($0 as? ProjectRepositoryError, .projectNotFound)
        }
    }

    /// Rows written before STEP 10 carry nil in every deletion attribute; they must load as active
    /// clips, and a half-written record must be rejected rather than resurrect or drop a clip.
    func testSwiftDataRowsWithoutDeletionAttributesLoadAsActiveClips() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        let (project, ids) = try makeThreeClipProject()
        try environment.repository.create(project)
        let rows = try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>())
        XCTAssertTrue(rows.allSatisfy { $0.deletedAt == nil && $0.deletionOriginalIndex == nil && $0.deletionPreviousClipID == nil && $0.deletionNextClipID == nil })
        XCTAssertEqual(try environment.repository.project(id: project.id)?.clips.map(\.id), ids)

        rows.first { $0.id == ids[1] }?.deletedAt = .now   // timestamp without an original index
        try environment.container.mainContext.save()
        let reopened = try makeSwiftDataEnvironment(storeURL: store.url)
        XCTAssertThrowsError(try reopened.repository.project(id: project.id)) {
            XCTAssertEqual($0 as? ProjectRepositoryError, .invalidPersistedMetadata)
        }
    }

    // MARK: - Add + undone-Add durability (Phase 5 STEP 11)

    /// Add appends rows in place; Undo Add keeps the new row as pending-deleted (never removed);
    /// the state survives reopen and unrelated autosave; Redo restores the same row identity.
    func testSwiftDataAppendThenUndoneAddKeepsRowsAcrossReopen() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        var (project, ids) = try makeThreeClipProject()
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        try environment.repository.create(project)
        let rowsBefore = Set(try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>()).map(\.persistentModelID))

        let added = try makeClip(projectID: project.id, sortOrder: 0)
        try project.appendClips([added])
        try environment.repository.update(project)
        let rowsAfterAdd = try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>())
        XCTAssertEqual(rowsAfterAdd.count, 4)
        XCTAssertTrue(rowsBefore.isSubset(of: Set(rowsAfterAdd.map(\.persistentModelID))), "existing rows retained in place")
        let addedRow = try XCTUnwrap(rowsAfterAdd.first { $0.id == added.id })

        // Undo Add = the added clip becomes pending-deleted (durable), never omitted.
        try project.deleteClip(id: added.id)
        try environment.repository.update(project)
        XCTAssertEqual(try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>()).count, 4, "no row deleted")
        XCTAssertNotNil(addedRow.deletedAt)

        let reopened = try makeSwiftDataEnvironment(storeURL: store.url)
        var reloaded = try XCTUnwrap(try reopened.repository.project(id: project.id))
        XCTAssertEqual(reloaded.clips.map(\.id), ids)
        XCTAssertEqual(reloaded.deletedClips.map(\.id), [added.id], "undone-Add clip survives reopen as pending")
        XCTAssertEqual(reloaded.deletedClips[0].mediaRelativePath, added.mediaRelativePath)

        // Unrelated autosave keeps it; the omission guard still holds.
        try reloaded.reorderClip(id: ids[2], toIndex: 0)
        try reopened.repository.update(reloaded)
        XCTAssertEqual(try reopened.repository.project(id: project.id)?.deletedClips.map(\.id), [added.id])
        let truncated = try VlogProject(id: project.id, createdAt: project.createdAt, orientation: .portrait9x16, clips: reloaded.clips)
        XCTAssertThrowsError(try reopened.repository.update(truncated)) { XCTAssertEqual($0 as? ProjectRepositoryError, .missingDurableClip) }

        // Redo Add = restore the same row to active.
        try reloaded.restoreDeletedClip(id: added.id)
        try reopened.repository.update(reloaded)
        let again = try makeSwiftDataEnvironment(storeURL: store.url)
        let final = try XCTUnwrap(try again.repository.project(id: project.id))
        XCTAssertEqual(final.clips.map(\.id), [ids[2], added.id, ids[0], ids[1]], "domain anchor restore: after its previous anchor C, wherever C now is")
        XCTAssertTrue(final.deletedClips.isEmpty)
        XCTAssertEqual(try again.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>()).count, 4, "never a fifth row")
    }

    // MARK: - Replace durability (Phase 5 STEP 13, ADR-040) — no schema change

    /// Replace = B row kept as pending + D row inserted (one commit); unrelated rows keep their
    /// identity; Undo (B active / D pending) and Redo (B pending / D active) only flip the same
    /// rows; the omission guard still protects both; 12A's `finalizeDeletedClip` removes exactly the
    /// pending row. State survives container reopen at every step.
    func testSwiftDataReplaceKeepsBothRowsAndSurvivesReopenThroughUndoRedoAndFinalize() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        var (project, ids) = try makeThreeClipProject()
        let (a, b, c) = (ids[0], ids[1], ids[2])
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        try environment.repository.create(project)
        let rowsBefore = Dictionary(uniqueKeysWithValues: try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>()).map { ($0.id, $0.persistentModelID) })

        let dID = UUID()
        let d = try VlogClip(id: dID, projectID: project.id, sourceKind: .imported,
                             mediaRelativePath: try ProjectMediaStore.committedMediaPath(projectID: project.id, clipID: dID),
                             sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: 0)
        try project.replaceClip(id: b, with: d)
        try environment.repository.update(project)                                              // one commit
        let rowsAfter = try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>())
        XCTAssertEqual(rowsAfter.count, 4, "B kept, D inserted")
        for id in [a, b, c] { XCTAssertEqual(rowsAfter.first { $0.id == id }?.persistentModelID, rowsBefore[id], "existing rows retain identity") }
        XCTAssertNotNil(rowsAfter.first { $0.id == b }?.deletedAt); XCTAssertNil(rowsAfter.first { $0.id == dID }?.deletedAt)

        let reopen1 = try makeSwiftDataEnvironment(storeURL: store.url)
        var reopened = try XCTUnwrap(try reopen1.repository.project(id: project.id))
        XCTAssertEqual(reopened.clips.map(\.id), [a, dID, c], "final Replace state after reopen")
        XCTAssertEqual(reopened.clips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(reopened.deletedClips.map(\.id), [b])
        XCTAssertEqual(reopened.clips[1].sourceKind, .imported); XCTAssertEqual(reopened.clips[1].trimStart, .zero); XCTAssertNil(reopened.clips[1].framing)
        let truncated = try VlogProject(id: project.id, createdAt: project.createdAt, orientation: .portrait9x16, clips: reopened.clips)
        XCTAssertThrowsError(try environment.repository.update(truncated), "omitting pending B is refused") { XCTAssertEqual($0 as? ProjectRepositoryError, .missingDurableClip) }

        // Undo Replace (history restore): B active, D pending — rows retained.
        let undone = try VlogProject(id: project.id, createdAt: project.createdAt, orientation: .portrait9x16,
                                     clips: [reopened.clips[0], try reopened.deletedClips[0].assigning(sortOrder: 1, deletion: nil), reopened.clips[2]].enumerated().map { try $1.assigningSortOrder($0) },
                                     deletedClips: [try reopened.clips[1].assigning(sortOrder: 1, deletion: ClipDeletionRecord(deletedAt: .now, originalIndex: 1, previousClipID: a, nextClipID: c))])
        try environment.repository.update(undone)
        let reopen2 = try makeSwiftDataEnvironment(storeURL: store.url)
        reopened = try XCTUnwrap(try reopen2.repository.project(id: project.id))
        XCTAssertEqual(reopened.clips.map(\.id), [a, b, c]); XCTAssertEqual(reopened.deletedClips.map(\.id), [dID])
        XCTAssertEqual(try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>()).count, 4)

        // Redo Replace: B pending, D active — same rows, same identities.
        try environment.repository.update(project)
        let reopen3 = try makeSwiftDataEnvironment(storeURL: store.url)
        reopened = try XCTUnwrap(try reopen3.repository.project(id: project.id))
        XCTAssertEqual(reopened.clips.map(\.id), [a, dID, c]); XCTAssertEqual(reopened.deletedClips.map(\.id), [b])
        let rowsRedo = try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>())
        XCTAssertEqual(rowsRedo.count, 4, "never a fifth row")
        for id in [a, b, c] { XCTAssertEqual(rowsRedo.first { $0.id == id }?.persistentModelID, rowsBefore[id]) }

        // Exit cleanup (12A) finalizes exactly the pending row; the active rows are untouched.
        try environment.repository.finalizeDeletedClip(projectID: project.id, clipID: b)
        XCTAssertThrowsError(try environment.repository.finalizeDeletedClip(projectID: project.id, clipID: dID)) { XCTAssertEqual($0 as? ProjectRepositoryError, .clipNotPendingDeletion) }
        let reopen4 = try makeSwiftDataEnvironment(storeURL: store.url)
        let final = try XCTUnwrap(try reopen4.repository.project(id: project.id))
        XCTAssertEqual(final.clips.map(\.id), [a, dID, c]); XCTAssertTrue(final.deletedClips.isEmpty)
        XCTAssertEqual(try environment.container.mainContext.fetch(FetchDescriptor<PersistedVlogClip>()).count, 3)
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

// MARK: - Saved-Project replacement in one save (ADR-033 Revision 1 / ADR-050 OD-14)

extension ProjectRepositoryTests {
    /// A Project with `active` active Clips followed by `pending` pending-deleted Clips.
    private func makeReplacementProject(active: Int, pending: Int, updatedAt: Date) throws -> VlogProject {
        let id = UUID()
        var project = try VlogProject(
            id: id, createdAt: updatedAt.addingTimeInterval(-60), updatedAt: updatedAt, orientation: .portrait9x16,
            clips: (0..<(active + pending)).map { try makeClip(projectID: id, sortOrder: $0) }
        )
        for index in 0..<pending {
            try project.deleteClip(id: project.clips[project.clips.count - 1].id, deletedAt: updatedAt.addingTimeInterval(Double(index + 1)))
        }
        return project
    }

    private func storedClipRowCount(_ container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<PersistedVlogClip>())
    }

    private func assertDurableState(storeURL: URL, present: [VlogProject], absent: [UUID], clipRows: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let reopened = try makeSwiftDataEnvironment(storeURL: storeURL)
        for project in present { XCTAssertEqual(try reopened.repository.project(id: project.id), project, file: file, line: line) }
        for id in absent { XCTAssertNil(try reopened.repository.project(id: id), file: file, line: line) }
        XCTAssertEqual(try storedClipRowCount(reopened.container), clipRows, file: file, line: line)
    }

    func testSwiftDataReplaceProjectSwapsAForBInOneSaveAndCascadesPendingClips() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try makeReplacementProject(active: 3, pending: 2, updatedAt: base)
        let other = try makeReplacementProject(active: 2, pending: 0, updatedAt: base.addingTimeInterval(-3600))
        let b = try makeReplacementProject(active: 4, pending: 0, updatedAt: base.addingTimeInterval(60))
        do {
            let environment = try makeSwiftDataEnvironment(storeURL: store.url)
            try environment.repository.create(other)
            try environment.repository.create(a)
            XCTAssertEqual(try storedClipRowCount(environment.container), 7)

            try environment.repository.replaceProject(previousID: a.id, with: b)

            // The same repository (shared context) sees the replacement at once.
            XCTAssertNil(try environment.repository.project(id: a.id))
            let stored = try XCTUnwrap(try environment.repository.project(id: b.id))
            XCTAssertEqual(stored, b)
            XCTAssertEqual(stored.clips.map(\.id), b.clips.map(\.id))
            XCTAssertEqual(stored.clips.map(\.sortOrder), [0, 1, 2, 3])
            XCTAssertTrue(stored.clips.allSatisfy { $0.projectID == b.id })
            XCTAssertEqual(try environment.repository.project(id: other.id), other)
            XCTAssertEqual(try environment.repository.recentProjects().first?.id, b.id)
        }
        // A fresh repository: B complete, A and all five of A's rows (two pending) gone, the other Project intact.
        try assertDurableState(storeURL: store.url, present: [b, other], absent: [a.id], clipRows: 6)
    }

    func testSwiftDataReplaceProjectRefusesMissingADuplicateBAndConflictingClipsWithoutChanges() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try makeReplacementProject(active: 2, pending: 1, updatedAt: base)
        let other = try makeReplacementProject(active: 2, pending: 0, updatedAt: base.addingTimeInterval(-60))
        let b = try makeReplacementProject(active: 2, pending: 0, updatedAt: base.addingTimeInterval(60))
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        try environment.repository.create(a)
        try environment.repository.create(other)

        XCTAssertThrowsError(try environment.repository.replaceProject(previousID: UUID(), with: b)) {
            XCTAssertEqual($0 as? ProjectRepositoryError, .projectNotFound)
        }
        XCTAssertThrowsError(try environment.repository.replaceProject(previousID: a.id, with: other)) {
            XCTAssertEqual($0 as? ProjectRepositoryError, .duplicateProject)
        }
        XCTAssertThrowsError(try environment.repository.replaceProject(previousID: a.id, with: a)) {
            XCTAssertEqual($0 as? ProjectRepositoryError, .duplicateProject)
        }
        // B reusing one of A's Clip identities, and B reusing another Project's Clip identity.
        for borrowed in [a.durableClips[0].id, other.clips[1].id] {
            let conflicting = try VlogProject(
                id: b.id, createdAt: b.createdAt, updatedAt: b.updatedAt, orientation: b.orientation,
                clips: [try VlogClip(id: borrowed, projectID: b.id, sourceKind: .imported, mediaRelativePath: b.clips[0].mediaRelativePath,
                                     sourceDuration: .seconds(5), trimDuration: .seconds(5), sortOrder: 0)]
            )
            XCTAssertThrowsError(try environment.repository.replaceProject(previousID: a.id, with: conflicting)) {
                XCTAssertEqual($0 as? ProjectRepositoryError, .clipIdentityConflict)
            }
        }
        try assertDurableState(storeURL: store.url, present: [a, other], absent: [b.id], clipRows: 5)
    }

    func testSwiftDataReplaceProjectMappingFailureLeavesAIntact() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try makeReplacementProject(active: 2, pending: 1, updatedAt: base)
        let b = try makeReplacementProject(active: 3, pending: 0, updatedAt: base.addingTimeInterval(60))
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        try environment.repository.create(a)
        environment.repository.debugStagedMappingOverride = { _, _ in false }

        XCTAssertThrowsError(try environment.repository.replaceProject(previousID: a.id, with: b)) {
            XCTAssertEqual($0 as? ProjectRepositoryError, .replacementMappingMismatch)
        }
        XCTAssertEqual(try environment.repository.project(id: a.id), a)
        try assertDurableState(storeURL: store.url, present: [a], absent: [b.id], clipRows: 3)
    }

    /// A store opened with `allowsSave: false` refuses the save. This exercises the repository's error
    /// and rollback path only; it is NOT evidence of how a failure in the middle of a save behaves.
    func testSwiftDataReplaceProjectSaveRefusalLeavesAIntact() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try makeReplacementProject(active: 2, pending: 1, updatedAt: base)
        let b = try makeReplacementProject(active: 3, pending: 0, updatedAt: base.addingTimeInterval(60))
        do {
            let writer = try makeSwiftDataEnvironment(storeURL: store.url)
            try writer.repository.create(a)
        }
        do {
            let schema = Schema([PersistedVlogProject.self, PersistedVlogClip.self])
            let readOnly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: store.url, allowsSave: false)])
            let repository = SwiftDataProjectRepository(modelContext: readOnly.mainContext)
            XCTAssertThrowsError(try repository.replaceProject(previousID: a.id, with: b)) {
                // Not a validation refusal: every pre-save check passes, so the error comes from the save.
                XCTAssertFalse($0 is ProjectRepositoryError, "\($0)")
            }
            XCTAssertEqual(try repository.project(id: a.id), a)
            XCTAssertNil(try repository.project(id: b.id))
        }
        try assertDurableState(storeURL: store.url, present: [a], absent: [b.id], clipRows: 3)
    }

    func testSwiftDataReplaceProjectDoesNotPersistUnrelatedPendingEditsInTheSharedContext() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try makeReplacementProject(active: 2, pending: 0, updatedAt: base)
        let b = try makeReplacementProject(active: 2, pending: 0, updatedAt: base.addingTimeInterval(60))
        let stray = try makeReplacementProject(active: 1, pending: 0, updatedAt: base.addingTimeInterval(-60))
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        try environment.repository.create(a)
        // An unsaved edit in the shared context (its own autosave held off so only replaceProject could save it).
        environment.container.mainContext.autosaveEnabled = false
        environment.container.mainContext.insert(PersistedVlogProject(project: stray))
        XCTAssertTrue(environment.container.mainContext.hasChanges)

        try environment.repository.replaceProject(previousID: a.id, with: b)

        XCTAssertTrue(environment.container.mainContext.hasChanges, "the shared context's pending edit was not saved")
        try assertDurableState(storeURL: store.url, present: [b], absent: [a.id, stray.id], clipRows: 2)
        environment.container.mainContext.rollback()
    }

    func testSwiftDataReplaceProjectKeepsBsPendingDeletedClipsAcrossReopen() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try makeReplacementProject(active: 2, pending: 1, updatedAt: base)
        let b = try makeReplacementProject(active: 3, pending: 2, updatedAt: base.addingTimeInterval(60))
        XCTAssertEqual(b.deletedClips.count, 2)
        do {
            let environment = try makeSwiftDataEnvironment(storeURL: store.url)
            try environment.repository.create(a)
            try environment.repository.replaceProject(previousID: a.id, with: b)
        }
        let reopened = try makeSwiftDataEnvironment(storeURL: store.url)
        let stored = try XCTUnwrap(try reopened.repository.project(id: b.id))
        XCTAssertEqual(stored, b)
        XCTAssertEqual(stored.deletedClips.map(\.id), b.deletedClips.map(\.id))
        XCTAssertEqual(stored.deletedClips.map(\.deletion), b.deletedClips.map(\.deletion))
        XCTAssertTrue(stored.durableClips.allSatisfy { $0.projectID == b.id })
        XCTAssertNil(try reopened.repository.project(id: a.id))
        XCTAssertEqual(try storedClipRowCount(reopened.container), 5)
    }

    /// No Clip-count cap: a B larger than several conflict-query batches replaces A, and a conflict that
    /// sits beyond the first batch is still refused before anything is staged.
    func testSwiftDataReplaceProjectHandlesLargeBAndFindsConflictBeyondFirstBatch() throws {
        let store = try makeStore()
        defer { store.cleanup() }
        let batch = SwiftDataProjectRepository.clipIdentityQueryBatchSize
        let count = batch * 2 + 200
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try makeReplacementProject(active: 2, pending: 0, updatedAt: base)
        let other = try makeReplacementProject(active: 1, pending: 0, updatedAt: base.addingTimeInterval(-60))
        let environment = try makeSwiftDataEnvironment(storeURL: store.url)
        try environment.repository.create(a)
        try environment.repository.create(other)

        func largeB(borrowing borrowed: UUID?) throws -> VlogProject {
            let id = UUID()
            let clips = try (0..<count).map { index -> VlogClip in
                let clipID = (index == count - 1) ? (borrowed ?? UUID()) : UUID()
                return try VlogClip(id: clipID, projectID: id, sourceKind: .imported,
                                    mediaRelativePath: try RelativeMediaPath("Projects/\(id.uuidString)/Media/\(clipID.uuidString).mov"),
                                    sourceDuration: .seconds(5), trimDuration: .seconds(5), sortOrder: index)
            }
            return try VlogProject(id: id, createdAt: base, updatedAt: base.addingTimeInterval(60), orientation: .portrait9x16, clips: clips)
        }
        // Conflict in the last batch: the last Clip reuses the other Project's Clip identity.
        let conflicting = try largeB(borrowing: other.clips[0].id)
        XCTAssertThrowsError(try environment.repository.replaceProject(previousID: a.id, with: conflicting)) {
            XCTAssertEqual($0 as? ProjectRepositoryError, .clipIdentityConflict)
        }
        try assertDurableState(storeURL: store.url, present: [a, other], absent: [conflicting.id], clipRows: 3)

        let valid = try largeB(borrowing: nil)
        try environment.repository.replaceProject(previousID: a.id, with: valid)
        try assertDurableState(storeURL: store.url, present: [valid, other], absent: [a.id], clipRows: count + 1)
    }

    func testInMemoryReplaceProjectMatchesSwiftDataSemantics() throws {
        let repository = InMemoryProjectRepository()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try makeReplacementProject(active: 2, pending: 1, updatedAt: base)
        let other = try makeReplacementProject(active: 1, pending: 0, updatedAt: base.addingTimeInterval(-60))
        let b = try makeReplacementProject(active: 3, pending: 0, updatedAt: base.addingTimeInterval(60))
        try repository.create(a)
        try repository.create(other)

        XCTAssertThrowsError(try repository.replaceProject(previousID: UUID(), with: b)) { XCTAssertEqual($0 as? ProjectRepositoryError, .projectNotFound) }
        XCTAssertThrowsError(try repository.replaceProject(previousID: a.id, with: other)) { XCTAssertEqual($0 as? ProjectRepositoryError, .duplicateProject) }
        let conflicting = try VlogProject(
            id: b.id, createdAt: b.createdAt, updatedAt: b.updatedAt, orientation: b.orientation,
            clips: [try VlogClip(id: other.clips[0].id, projectID: b.id, sourceKind: .imported, mediaRelativePath: b.clips[0].mediaRelativePath,
                                 sourceDuration: .seconds(5), trimDuration: .seconds(5), sortOrder: 0)]
        )
        XCTAssertThrowsError(try repository.replaceProject(previousID: a.id, with: conflicting)) { XCTAssertEqual($0 as? ProjectRepositoryError, .clipIdentityConflict) }
        XCTAssertEqual(try repository.project(id: a.id), a)

        try repository.replaceProject(previousID: a.id, with: b)
        XCTAssertNil(try repository.project(id: a.id))
        XCTAssertEqual(try repository.project(id: b.id), b)
        XCTAssertEqual(try repository.project(id: other.id), other)
    }
}
