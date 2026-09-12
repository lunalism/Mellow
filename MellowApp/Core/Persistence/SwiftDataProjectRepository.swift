import Foundation
import SwiftData

@MainActor
final class SwiftDataProjectRepository: ProjectRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func create(_ project: VlogProject) throws {
        guard try persistedProject(id: project.id) == nil else {
            throw ProjectRepositoryError.duplicateProject
        }

        modelContext.insert(PersistedVlogProject(project: project))
        try modelContext.save()
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

        let incomingClipIDs = Set(project.clips.map(\.id))
        persistedProject.clips
            .filter { !incomingClipIDs.contains($0.id) }
            .forEach(modelContext.delete)

        let existingClipsByID = Dictionary(
            uniqueKeysWithValues: persistedProject.clips.map { ($0.id, $0) }
        )
        let persistedClips = project.clips.map { clip in
            if let persistedClip = existingClipsByID[clip.id] {
                persistedClip.apply(clip)
                return persistedClip
            }
            return PersistedVlogClip(clip: clip)
        }

        persistedProject.apply(project)
        persistedProject.clips = persistedClips
        persistedProject.clips.forEach { $0.project = persistedProject }
        try modelContext.save()
    }

    func deleteProject(id: UUID) throws {
        guard let persistedProject = try persistedProject(id: id) else {
            throw ProjectRepositoryError.projectNotFound
        }

        modelContext.delete(persistedProject)
        try modelContext.save()
    }

    private func persistedProject(id: UUID) throws -> PersistedVlogProject? {
        let predicate = #Predicate<PersistedVlogProject> { $0.id == id }
        var descriptor = FetchDescriptor<PersistedVlogProject>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
