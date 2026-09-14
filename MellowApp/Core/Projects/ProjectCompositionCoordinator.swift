import Foundation

/// V1 Single Saved Project policy (ADR-033 / ADR-034).
///
/// The repository stays multi-project capable; "one editable saved Project" is a product policy
/// enforced here, not a destructive schema restriction. STEP 4 is deliberately READ-ONLY: it only
/// resolves the current saved Project. Creation, Safe Atomic Replacement, promotion and previous-
/// project cleanup arrive in a later slice and are intentionally absent here.
@MainActor
final class ProjectCompositionCoordinator {
    private let repository: any ProjectRepository

    init(repository: any ProjectRepository) {
        self.repository = repository
    }

    /// The current V1 editable saved Project: the most-recent committed Project by the repository's
    /// canonical recency ordering, or nil when none exists. This never mutates or deletes anything.
    func lastSavedProject() throws -> VlogProject? {
        try repository.recentProjects().first
    }
}
