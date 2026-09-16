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
