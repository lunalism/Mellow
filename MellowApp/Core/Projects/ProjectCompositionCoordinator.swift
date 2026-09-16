import Foundation
import OSLog

/// V1 Single Saved Project policy (ADR-033 / ADR-034 / ADR-036).
///
/// The repository stays multi-project capable; "one editable saved Project" is a product policy
/// enforced here, not a destructive schema restriction. This coordinator owns Project-level policy:
/// saved-Project lookup, fresh composition commit, Safe Atomic Replacement, promotion and previous-
/// Project cleanup. It never performs file IO itself (that is `ProjectMediaStoring`) and never routes
/// user Clip Delete through the repository's clip-diffing `update()`.
@MainActor
final class ProjectCompositionCoordinator {
    private let repository: any ProjectRepository
    private let mediaStore: any ProjectMediaStoring
    private let validator: Phase5ReadyMediaValidator
    private let storage: any ProjectStorageGating
    /// Shared with pending-Clip cleanup and the Editor load (ADR-039): composition / replacement
    /// mutates Project files and metadata, so it may never overlap a cleanup pass.
    private let lifecycle: ProjectLifecycleOperationGate

    init(
        repository: any ProjectRepository,
        mediaStore: any ProjectMediaStoring,
        validator: Phase5ReadyMediaValidator,
        storage: any ProjectStorageGating,
        lifecycle: ProjectLifecycleOperationGate
    ) {
        self.repository = repository
        self.mediaStore = mediaStore
        self.validator = validator
        self.storage = storage
        self.lifecycle = lifecycle
    }

    /// The current V1 editable saved Project: the most-recent committed Project by the repository's
    /// canonical recency ordering, or nil when none exists. This never mutates or deletes anything.
    func lastSavedProject() throws -> VlogProject? {
        try repository.recentProjects().first
    }

    // MARK: - Composition

    enum Intent: Equatable, Sendable {
        case fresh
        case replacingSaved(UUID)
    }

    enum Outcome: Equatable, Sendable {
        case committed(projectID: UUID)
        /// At least one selected source needs Phase 6 preparation. Nothing was created or removed.
        case requiresImportPreparation(Phase5ReadyVerdict.PreparationReason)
        /// At least one selected source is unreadable / not a video. Nothing was created or removed.
        case invalidMedia(Phase5ReadyVerdict.InvalidReason)
        case insufficientStorage
        /// Materialization or persistence failed; workspace and any partial B were discarded.
        case failed(Failure)

        enum Failure: Equatable, Sendable { case noSources, materialization, persistence, verification }
    }

    /// Composes one Portrait Project from already-transferred, workspace-owned sources following
    /// ADR-020: validate all → materialize all → persist → verify → promote → (replacement only) remove
    /// the previous Project → discard workspace. All-or-nothing: a Project is never committed with a
    /// subset of the selected sources. On every non-committed outcome the previous saved Project (if
    /// any) is untouched and the workspace is discarded.
    ///
    /// The whole validate → materialize → persist → promote → retire-A section runs inside the shared
    /// lifecycle gate, so a pending-Clip cleanup pass (which may be retiring A's own pending Clips or
    /// finalizing rows) can never interleave with the replacement. Selection / transfer happened
    /// before this call and is not gated. Safe Atomic Replacement itself is unchanged.
    func compose(_ intent: Intent, sources: [SelectedVideoSource], workspace: ProjectMediaWorkspace) async -> Outcome {
        let outcome = await lifecycle.withExclusiveAccess {
            await composeInternal(intent, sources: sources, workspace: workspace)
        }
        await mediaStore.discard(workspace)
        return outcome
    }

    private func composeInternal(_ intent: Intent, sources: [SelectedVideoSource], workspace: ProjectMediaWorkspace) async -> Outcome {
        guard !sources.isEmpty else { return .failed(.noSources) }

        // 1. Final reserve guard (ADR-024). The primary media preflight ran per file before its first
        //    Mellow-owned copy (selection boundary); the sources are already adopted on this volume and
        //    promotion is a rename, so the remaining peak additional allocation is 0.
        let adoptedBytes = sources.reduce(0) { $0 + $1.byteCount }
        let additional = ProjectCompositionPolicy.estimatedPeakAdditionalBytes(adoptedSourceBytes: adoptedBytes)
        if case .insufficient(let required, let usable) = await storage.check(additionalBytes: additional) {
            MellowLog.app.info("Project composition storage preflight refused: required=\(required, privacy: .public) usable=\(usable, privacy: .public) adopted=\(adoptedBytes, privacy: .public)")
            return .insufficientStorage
        }

        // 2. Validate every source; the first non-ready verdict rejects the whole selection.
        var durations: [MediaTime] = []
        for source in sources {
            switch await validator.validate(source.url) {
            case .ready(let duration): durations.append(duration)
            case .requiresImportPreparation(let reason): return .requiresImportPreparation(reason)
            case .invalid(let reason): return .invalidMedia(reason)
            }
        }

        // 3. Materialize into Project B's own directory, then build metadata.
        let projectID = UUID()
        var clips: [VlogClip] = []
        for (index, source) in sources.enumerated() {
            let clipID = UUID()
            do {
                let path = try await mediaStore.materialize(source.url, projectID: projectID, clipID: clipID)
                guard await mediaStore.fileExists(path) else { throw ProjectMediaStoreError.sourceMissing }
                clips.append(try VlogClip(
                    id: clipID,
                    projectID: projectID,
                    sourceKind: .imported,
                    mediaRelativePath: path,
                    sourceDuration: durations[index],
                    trimStart: .zero,
                    trimDuration: durations[index],
                    framing: nil,
                    sortOrder: index
                ))
            } catch {
                log("materialization", error)
                await mediaStore.removeProjectMedia(projectID: projectID)
                return .failed(.materialization)
            }
        }

        // 4. Persist B, then verify the commit by reading it back.
        let project: VlogProject
        do {
            project = try VlogProject(id: projectID, orientation: .portrait9x16, clips: clips)
            try repository.create(project)
        } catch {
            log("persistence", error)
            await mediaStore.removeProjectMedia(projectID: projectID)
            return .failed(.persistence)
        }
        guard let committed = try? repository.project(id: projectID), committed.clips.count == clips.count else {
            log("verification", nil)
            try? repository.deleteProject(id: projectID)
            await mediaStore.removeProjectMedia(projectID: projectID)
            return .failed(.verification)
        }
        for clip in committed.clips where await !mediaStore.fileExists(clip.mediaRelativePath) {
            log("verification", nil)
            try? repository.deleteProject(id: projectID)
            await mediaStore.removeProjectMedia(projectID: projectID)
            return .failed(.verification)
        }

        // 5. B is committed and is now the current saved Project (canonical recency ordering).
        //    Only now may the replaced Project A go: metadata first, then its app-owned media.
        if case .replacingSaved(let previousID) = intent, previousID != projectID {
            do {
                try repository.deleteProject(id: previousID)
            } catch {
                // A already gone or delete failed: B is still the valid saved Project; report only.
                log("previous project removal", error)
            }
            await mediaStore.removeProjectMedia(projectID: previousID)
        }
        return .committed(projectID: projectID)
    }

    private func log(_ stage: String, _ error: Error?) {
        if let error {
            let details = error as NSError
            MellowLog.app.error("Project composition \(stage, privacy: .public) failed: domain=\(details.domain, privacy: .public), code=\(details.code)")
        } else {
            MellowLog.app.error("Project composition \(stage, privacy: .public) failed")
        }
    }
}
