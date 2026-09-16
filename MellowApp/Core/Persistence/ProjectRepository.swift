import Foundation

@MainActor
protocol ProjectRepository {
    func create(_ project: VlogProject) throws
    func project(id: UUID) throws -> VlogProject?
    func recentProjects() throws -> [VlogProject]
    /// Whole-Project autosave. Reconciles every durable Clip (active + pending-deleted) by identity
    /// and NEVER removes Clip metadata: a persisted Clip missing from the incoming Project is a
    /// caller bug and is rejected (`missingDurableClip`), not silently deleted (ADR-021).
    func update(_ project: VlogProject) throws
    /// Explicit physical-cleanup boundary for one pending-deleted Clip's metadata. Refused for an
    /// active Clip (`clipNotPendingDeletion`, also thrown for an already-finalized row). Media files
    /// are not touched here; `ProjectMediaCleanupCoordinator` sequences file removal → verified
    /// absence → this call (ADR-039). Maintenance semantics: must NOT bump the Project's `updatedAt`.
    func finalizeDeletedClip(projectID: UUID, clipID: UUID) throws
    func deleteProject(id: UUID) throws
}

enum ProjectRepositoryError: Error, Equatable {
    case duplicateProject
    case projectNotFound
    case projectOrientationImmutable
    case invalidPersistedMetadata
    /// `update` was handed a Project that omits a Clip the store still holds.
    case missingDurableClip
    case clipNotPendingDeletion
}
