import Foundation

@MainActor
final class InMemoryProjectRepository: ProjectRepository {
    private var projects: [UUID: VlogProject] = [:]

    func create(_ project: VlogProject) throws {
        guard projects[project.id] == nil else {
            throw ProjectRepositoryError.duplicateProject
        }

        projects[project.id] = project
    }

    func project(id: UUID) throws -> VlogProject? {
        projects[id]
    }

    func recentProjects() throws -> [VlogProject] {
        projects.values.sorted(by: RecentProjectOrdering.precedes)
    }

    func update(_ project: VlogProject) throws {
        guard let existingProject = projects[project.id] else {
            throw ProjectRepositoryError.projectNotFound
        }

        guard existingProject.orientation == project.orientation else {
            throw ProjectRepositoryError.projectOrientationImmutable
        }

        let incoming = Set(project.durableClips.map(\.id))
        guard existingProject.durableClips.allSatisfy({ incoming.contains($0.id) }) else {
            throw ProjectRepositoryError.missingDurableClip
        }

        projects[project.id] = project
    }

    /// Maintenance, not an edit: the Project's `updatedAt` is unchanged (same as SwiftData).
    func finalizeDeletedClip(projectID: UUID, clipID: UUID) throws {
        guard var project = projects[projectID] else {
            throw ProjectRepositoryError.projectNotFound
        }
        do { try project.finalizeDeletedClip(id: clipID) } catch { throw ProjectRepositoryError.clipNotPendingDeletion }
        projects[projectID] = project
    }

    /// Same validation and outcome as SwiftData's single-save replacement (no partial state in memory).
    func replaceProject(previousID: UUID, with project: VlogProject) throws {
        guard previousID != project.id else { throw ProjectRepositoryError.duplicateProject }
        guard projects[previousID] != nil else { throw ProjectRepositoryError.projectNotFound }
        guard projects[project.id] == nil else { throw ProjectRepositoryError.duplicateProject }
        let existingClipIDs = Set(projects.values.flatMap { $0.durableClips.map(\.id) })
        guard project.durableClips.allSatisfy({ !existingClipIDs.contains($0.id) }) else {
            throw ProjectRepositoryError.clipIdentityConflict
        }
        projects.removeValue(forKey: previousID)
        projects[project.id] = project
    }

    func deleteProject(id: UUID) throws {
        guard projects.removeValue(forKey: id) != nil else {
            throw ProjectRepositoryError.projectNotFound
        }
    }
}
