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
    /// Saved-Project replacement (ADR-033 Revision 1 / ADR-050 OD-14): inserts `project` (B) and deletes
    /// the Project `previousID` (A) with all of A's durable Clip rows, active and pending-deleted, in ONE
    /// explicit save. Everything that can fail is validated before anything is staged: A must exist
    /// (`projectNotFound`), B's ID must be absent (`duplicateProject`), and no B Clip identity may already
    /// exist in the store (`clipIdentityConflict`). Media files are never touched here; callers keep A's
    /// media until B's complete saved state and A's absence are confirmed. A thrown error does not prove
    /// the prior durable state, and one save call is not a crash / power-loss atomicity guarantee.
    func replaceProject(previousID: UUID, with project: VlogProject) throws
    /// One Project's persisted state under the accepted OD-10 observation policy (ADR-050 050-D): a read
    /// failure is `.unreadable`, never absence. Used for the in-gate prior snapshot (D8.5a P1).
    func observePersistedProject(id: UUID) -> ObservedProjectRecord
    /// The persisted state a save expectation needs, under the same OD-10 policy, for
    /// `ProjectSaveOutcomeClassifier`. Several fetches, not one atomic snapshot: callers serialize it with
    /// lifecycle mutations (the lifecycle gate).
    func observePersistedState(for expectation: ProjectSaveExpectation) -> PersistedStateObservation
    /// The current saved Project's ID under the same OD-10 policy, with the existing current-Project ordering
    /// (`recentProjects()` order: every row decoded, `RecentProjectOrdering`). Any fetch or conversion failure
    /// is `.unreadable` — never "no Project". Not a cache-independence or atomic-snapshot guarantee; callers
    /// serialize it with lifecycle mutations.
    func observeCurrentProjectID() -> ObservedCurrentProject
}

/// Result of a fresh-read lookup of the current saved Project.
enum ObservedCurrentProject: Equatable, Sendable {
    /// The read succeeded and found no Project.
    case none
    case project(UUID)
    case unreadable
}

enum ProjectRepositoryError: Error, Equatable {
    case duplicateProject
    case projectNotFound
    case projectOrientationImmutable
    case invalidPersistedMetadata
    /// `update` was handed a Project that omits a Clip the store still holds.
    case missingDurableClip
    case clipNotPendingDeletion
    /// `replaceProject` was handed a Clip identity that already exists in the store (any Project).
    case clipIdentityConflict
    /// `replaceProject`'s staged rows did not map back to the exact incoming Project.
    case replacementMappingMismatch
}
