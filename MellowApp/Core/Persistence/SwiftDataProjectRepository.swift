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
    /// Test seam: returns true for an observation fetch that should fail with `InjectedObservationFault`.
    /// Nil in every production path; absent from Release.
    var debugObservationFault: ((ObservationFetch) -> Bool)? = nil

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

// MARK: - Persisted-state observation (ADR-050 050-D OD-10)

extension SwiftDataProjectRepository {
    /// Holder recorded for a created Clip ID whose row exists but has no owning Project. It never equals a
    /// real Project ID (`UUID()` never yields the all-zero UUID) and so never equals an intended owner: the
    /// classifier treats it as present (prior) and as a contradiction (intended).
    static let unownedClipHolder = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// The fetches one observation makes (names the DEBUG-only fault-injection points).
    enum ObservationFetch: Equatable {
        case project(UUID)
        case createdProjects(batch: Int)
        case createdClips(batch: Int)
        case currentProject
    }

    #if DEBUG
    /// Error thrown by an injected (simulated) observation fetch failure — not a real store failure.
    struct InjectedObservationFault: Error {}
    #endif

    /// Reads the persisted state a `ProjectSaveExpectation` needs, for `ProjectSaveOutcomeClassifier`.
    ///
    /// OD-10 policy: every call uses a NEW `ModelContext` from this repository's container, with autosave
    /// disabled and `includePendingChanges = false`; it never reuses the save context or the shared
    /// context's objects, so the shared context's unsaved edits are neither read, saved nor discarded.
    /// Nothing is mutated. This is an implementation policy, not a guarantee of bypassing every shared
    /// cache or of independent durable truth under every failure. The observation is several separate
    /// fetches, not one atomic store snapshot: callers must serialize it with Project lifecycle mutations
    /// (the lifecycle gate) for the results to describe one moment. Without that serialization a row
    /// deleted mid-observation can also fail while its relationships are read, which surfaces as a framework
    /// exception rather than an `.unreadable` result, as on the repository's other read paths.
    ///
    /// Evidence is explicit and never hidden: a missing row is `.absent`; a fetch or domain-conversion
    /// failure is `.unreadable`; created identities are queried store-wide in bounded batches, and an
    /// identity whose batch failed is simply left out (so the classifier sees it as missing) while every
    /// identity that was queried successfully, including conflicting holders, is still reported.
    func observePersistedState(for expectation: ProjectSaveExpectation) -> PersistedStateObservation {
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false

        var projects: [UUID: ObservedProjectRecord] = [:]
        for id in Set(expectation.prior.keys).union(expectation.intended.keys) {
            projects[id] = observeProject(id, in: context)
        }

        var holders: [UUID: Set<UUID>] = [:]
        // Deterministic batches (sorted identities), independent of dictionary / set iteration order.
        let createdProjectIDs = expectation.createdProjectIDs.sorted { $0.uuidString < $1.uuidString }
        let createdClipIDs = expectation.createdClipOwners.keys.sorted { $0.uuidString < $1.uuidString }
        let batchSize = Self.clipIdentityQueryBatchSize
        for (batchIndex, start) in stride(from: 0, to: createdProjectIDs.count, by: batchSize).enumerated() {
            let batch = Array(createdProjectIDs[start..<min(start + batchSize, createdProjectIDs.count)])
            do {
                try injectObservationFault(.createdProjects(batch: batchIndex))
                var descriptor = FetchDescriptor<PersistedVlogProject>(predicate: #Predicate { batch.contains($0.id) })
                descriptor.includePendingChanges = false
                let found = Set(try context.fetch(descriptor).map(\.id))
                for id in batch { holders[id] = found.contains(id) ? [id] : [] }
            } catch {
                continue   // these identities stay missing
            }
        }
        for (batchIndex, start) in stride(from: 0, to: createdClipIDs.count, by: batchSize).enumerated() {
            let batch = Array(createdClipIDs[start..<min(start + batchSize, createdClipIDs.count)])
            do {
                try injectObservationFault(.createdClips(batch: batchIndex))
                var descriptor = FetchDescriptor<PersistedVlogClip>(predicate: #Predicate { batch.contains($0.id) })
                descriptor.includePendingChanges = false
                var batchHolders = Dictionary(uniqueKeysWithValues: batch.map { ($0, Set<UUID>()) })
                for row in try context.fetch(descriptor) {
                    batchHolders[row.id, default: []].insert(row.project?.id ?? Self.unownedClipHolder)
                }
                holders.merge(batchHolders) { $0.union($1) }
            } catch {
                continue   // these identities stay missing
            }
        }
        return PersistedStateObservation(projects: projects, createdIdentityHolders: holders)
    }

    /// One Project under the same OD-10 policy as `observePersistedState(for:)`: a NEW dedicated context
    /// (autosave off, `includePendingChanges = false`); the save context and shared objects are never reused.
    func observePersistedProject(id: UUID) -> ObservedProjectRecord {
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        return observeProject(id, in: context)
    }

    /// Same ordering as `recentProjects()` (fetch sorted by `updatedAt` / `createdAt`, every row converted,
    /// then `RecentProjectOrdering`), read through a NEW dedicated context (autosave off,
    /// `includePendingChanges = false`): unsaved shared-context edits are invisible, and any failure is
    /// `.unreadable`.
    func observeCurrentProjectID() -> ObservedCurrentProject {
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        do {
            try injectObservationFault(.currentProject)
            var descriptor = FetchDescriptor<PersistedVlogProject>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.includePendingChanges = false
            let projects = try context.fetch(descriptor).map { try $0.domainValue() }
            return projects.sorted(by: RecentProjectOrdering.precedes).first.map { .project($0.id) } ?? .none
        } catch {
            return .unreadable
        }
    }

    private func observeProject(_ id: UUID, in context: ModelContext) -> ObservedProjectRecord {
        do {
            try injectObservationFault(.project(id))
            var descriptor = FetchDescriptor<PersistedVlogProject>(predicate: #Predicate { $0.id == id })
            descriptor.includePendingChanges = false
            let rows = try context.fetch(descriptor)
            guard let row = rows.first else { return .absent }
            guard rows.count == 1 else { return .unreadable }
            return .present(try row.domainValue())
        } catch {
            return .unreadable
        }
    }

    private func injectObservationFault(_ fetch: ObservationFetch) throws {
        #if DEBUG
        if let fault = debugObservationFault, fault(fetch) { throw InjectedObservationFault() }
        #endif
    }
}
