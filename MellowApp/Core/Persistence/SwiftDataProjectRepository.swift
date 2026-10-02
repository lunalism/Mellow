import Foundation
import SwiftData

@MainActor
final class SwiftDataProjectRepository: ProjectRepository {
    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func create(_ project: VlogProject) throws {
        guard try persistedProject(id: project.id) == nil else {
            throw ProjectRepositoryError.duplicateProject
        }

        modelContext.insert(PersistedVlogProject(project: project))
        try saveOrRollback()
    }

    func project(id: UUID) throws -> VlogProject? {
        try persistedProject(id: id).map { try $0.domainValue() }
    }

    func recentProjects() throws -> [VlogProject] {
        var descriptor = FetchDescriptor<PersistedVlogProject>(
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )
        descriptor.includePendingChanges = false
        return try modelContext.fetch(descriptor).map { try $0.domainValue() }
            .sorted(by: RecentProjectOrdering.precedes)
    }

    func update(_ project: VlogProject) throws {
        guard let persistedProject = try persistedProject(id: project.id) else {
            throw ProjectRepositoryError.projectNotFound
        }

        guard let existingOrientation = ProjectOrientation(rawValue: persistedProject.orientationRawValue) else {
            throw ProjectRepositoryError.invalidPersistedMetadata
        }

        guard existingOrientation == project.orientation else {
            throw ProjectRepositoryError.projectOrientationImmutable
        }

        // Never an implicit metadata deletion: every persisted Clip must still be present in the
        // incoming durable set (active or pending-deleted). Physical removal is `finalizeDeletedClip`.
        let incomingClipIDs = Set(project.durableClips.map(\.id))
        guard persistedProject.clips.allSatisfy({ incomingClipIDs.contains($0.id) }) else {
            throw ProjectRepositoryError.missingDurableClip
        }

        let existingClipsByID = Dictionary(
            uniqueKeysWithValues: persistedProject.clips.map { ($0.id, $0) }
        )
        let persistedClips = project.durableClips.map { clip in
            if let persistedClip = existingClipsByID[clip.id] {
                persistedClip.apply(clip)
                return persistedClip
            }
            return PersistedVlogClip(clip: clip)
        }

        persistedProject.apply(project)
        persistedProject.clips = persistedClips
        persistedProject.clips.forEach { $0.project = persistedProject }
        try saveOrRollback()
    }

    /// Maintenance, not an edit: only the Clip row goes; the Project row (incl. `updatedAt`) is untouched.
    func finalizeDeletedClip(projectID: UUID, clipID: UUID) throws {
        guard let persistedProject = try persistedProject(id: projectID) else {
            throw ProjectRepositoryError.projectNotFound
        }
        guard let persistedClip = persistedProject.clips.first(where: { $0.id == clipID }), persistedClip.deletedAt != nil else {
            throw ProjectRepositoryError.clipNotPendingDeletion
        }
        persistedProject.clips.removeAll { $0.id == clipID }
        modelContext.delete(persistedClip)
        try saveOrRollback()
    }

    func deleteProject(id: UUID) throws {
        guard let persistedProject = try persistedProject(id: id) else {
            throw ProjectRepositoryError.projectNotFound
        }

        modelContext.delete(persistedProject)
        try saveOrRollback()
    }

    /// ADR-033 Revision 1 / ADR-050 OD-14. A dedicated context with autosave disabled keeps this one
    /// explicit save the only persistence point: nothing is written while rows are staged, and pending
    /// edits in the shared context are never swept into this save. Every fetch and check runs before the
    /// first mutation; staging and `save()` then run with no suspension point. On a save error the
    /// dedicated context is rolled back and discarded (the shared context is untouched).
    /// A stays registered, unchanged, in the shared context afterwards. That is harmless only because
    /// every repository mutation saves or rolls back at once, so the shared context never holds a
    /// dirty A that a later autosave could write against the deleted row.
    func replaceProject(previousID: UUID, with project: VlogProject) throws {
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false

        guard previousID != project.id else { throw ProjectRepositoryError.duplicateProject }
        guard let previous = try Self.persistedProject(id: previousID, in: context) else {
            throw ProjectRepositoryError.projectNotFound
        }
        guard try Self.persistedProject(id: project.id, in: context) == nil else {
            throw ProjectRepositoryError.duplicateProject
        }
        // Never rely on unique-attribute upsert: any existing row with one of B's Clip IDs (A's included)
        // is a conflict, refused before staging. There is no Clip-count cap, so the IN query is split into
        // bounded batches that stay far below SQLite's bind-variable limit; every batch runs before any
        // mutation is staged.
        let clipIDs = project.durableClips.map(\.id)
        for start in stride(from: 0, to: clipIDs.count, by: Self.clipIdentityQueryBatchSize) {
            let batch = Array(clipIDs[start..<min(start + Self.clipIdentityQueryBatchSize, clipIDs.count)])
            let descriptor = FetchDescriptor<PersistedVlogClip>(predicate: #Predicate { batch.contains($0.id) })
            guard try context.fetchCount(descriptor) == 0 else {
                throw ProjectRepositoryError.clipIdentityConflict
            }
        }
        let staged = PersistedVlogProject(project: project)
        guard stagedMappingMatches(staged, project) else {
            throw ProjectRepositoryError.replacementMappingMismatch
        }

        context.insert(staged)
        context.delete(previous)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Clip identities checked per conflict query (bind variables per statement).
    static let clipIdentityQueryBatchSize = 500

    #if DEBUG
    /// Test seam: replaces the staged-mapping check. Nil in every production path; absent from Release.
    var debugStagedMappingOverride: ((PersistedVlogProject, VlogProject) -> Bool)? = nil
    #endif

    /// The staged B must convert back to exactly the incoming Project (identity, Clip values and order,
    /// pending-deleted Clips).
    private func stagedMappingMatches(_ staged: PersistedVlogProject, _ project: VlogProject) -> Bool {
        #if DEBUG
        if let override = debugStagedMappingOverride { return override(staged, project) }
        #endif
        return (try? staged.domainValue()) == project
    }

    private static func persistedProject(id: UUID, in context: ModelContext) throws -> PersistedVlogProject? {
        let predicate = #Predicate<PersistedVlogProject> { $0.id == id }
        var descriptor = FetchDescriptor<PersistedVlogProject>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func saveOrRollback() throws {
        do {
            try modelContext.save()
        } catch {
            let container = modelContext.container
            modelContext.rollback()
            // A failed save can leave stale registered models after rollback.
            // Re-read committed state through a fresh context before allowing retry.
            modelContext = ModelContext(container)
            modelContext.autosaveEnabled = false
            throw error
        }
    }

    private func persistedProject(id: UUID) throws -> PersistedVlogProject? {
        let predicate = #Predicate<PersistedVlogProject> { $0.id == id }
        var descriptor = FetchDescriptor<PersistedVlogProject>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
