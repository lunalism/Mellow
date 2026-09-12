import Foundation

@MainActor
protocol ProjectRepository {
    func create(_ project: VlogProject) throws
    func project(id: UUID) throws -> VlogProject?
    func recentProjects() throws -> [VlogProject]
    func update(_ project: VlogProject) throws
    func deleteProject(id: UUID) throws
}

enum ProjectRepositoryError: Error, Equatable {
    case duplicateProject
    case projectNotFound
    case projectOrientationImmutable
    case invalidPersistedMetadata
}
