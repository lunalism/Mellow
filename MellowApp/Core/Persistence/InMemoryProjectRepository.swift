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

        projects[project.id] = project
    }

    func deleteProject(id: UUID) throws {
        guard projects.removeValue(forKey: id) != nil else {
            throw ProjectRepositoryError.projectNotFound
        }
    }
}
