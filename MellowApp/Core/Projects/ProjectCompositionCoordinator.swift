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
        /// The save outcome is `completed` (ADR-050 050-D D8.0), including a save that threw but whose
        /// complete evidence confirms the intended state (D8.5a P4).
        case committed(projectID: UUID)
        /// At least one selected source needs Phase 6 preparation. Nothing was created or removed.
        case requiresImportPreparation(Phase5ReadyVerdict.PreparationReason)
        /// At least one selected source is unreadable / not a video. Nothing was created or removed.
        case invalidMedia(Phase5ReadyVerdict.InvalidReason)
        case insufficientStorage
        /// Before any save: the prior persisted state could not be read (never treated as absence).
        /// Nothing was materialized or saved.
        case projectInspectionFailed
        /// Replacement only: A is gone or no longer the current saved Project. Nothing was materialized
        /// or saved, and B is never created alone instead (ADR-033 Revision 1).
        case replacementTargetInvalidated
        /// Another failure before the save attempt (no sources, materialization, metadata); B's own
        /// directory was removed.
        case preparationFailed
        /// The save returned but its result was not confirmed (D8.0). Media preserved; never rolled back.
        case committedUnverified(ProjectSaveOutcomeReason)
        /// The save threw and nothing could be confirmed (D8.0). Media preserved; no Retry.
        case indeterminate(ProjectSaveOutcomeReason)
        /// The save threw and the prior state is confirmed (D8.0). Candidate files are left to startup
        /// recovery; no rollback-to-workspace and no same-set Retry in this slice (D8.5a P6).
        case priorConfirmed
    }

    /// Composes one Portrait Project from already-transferred, workspace-owned sources (ADR-020 /
    /// ADR-033 Revision 1 / ADR-050 050-D D8.5a P1 · P8). All-or-nothing: a Project is never committed
    /// with a subset of the selected sources.
    ///
    /// Storage guard and validation touch only the live workspace and run before the lifecycle gate.
    /// One gate section then reads the prior state (OD-10 fresh read) before materialization, rechecks a
    /// replacement target, materializes and checks B, saves once (`create` or `replaceProject`), and
    /// observes and classifies the result (D8.0) before the gate is released. B's media is removed only
    /// on failures before the save attempt; A's media only after `completed` with A's row observed
    /// absent. The workspace is always discarded afterwards.
    func compose(_ intent: Intent, sources: [SelectedVideoSource], workspace: ProjectMediaWorkspace) async -> Outcome {
        let outcome: Outcome
        switch await validate(sources) {
        case .rejected(let rejection): outcome = rejection
        case .ready(let durations):
            outcome = await lifecycle.withExclusiveAccess {
                await commit(intent, sources: sources, durations: durations)
            }
        }
        await mediaStore.discard(workspace)
        return outcome
    }

    private enum Validation { case ready([MediaTime]), rejected(Outcome) }

    private func validate(_ sources: [SelectedVideoSource]) async -> Validation {
        guard !sources.isEmpty else { return .rejected(.preparationFailed) }

        // 1. Final reserve guard (ADR-024). The primary media preflight ran per file before its first
        //    Mellow-owned copy (selection boundary); the sources are already adopted on this volume and
        //    promotion is a rename, so the remaining peak additional allocation is 0.
        let adoptedBytes = sources.reduce(0) { $0 + $1.byteCount }
        let additional = ProjectCompositionPolicy.estimatedPeakAdditionalBytes(adoptedSourceBytes: adoptedBytes)
        if case .insufficient(let required, let usable) = await storage.check(additionalBytes: additional) {
            MellowLog.app.info("Project composition storage preflight refused: required=\(required, privacy: .public) usable=\(usable, privacy: .public) adopted=\(adoptedBytes, privacy: .public)")
            return .rejected(.insufficientStorage)
        }

        // 2. Validate every source; the first non-ready verdict rejects the whole selection.
        var durations: [MediaTime] = []
        for source in sources {
            switch await validator.validate(source.url) {
            case .ready(let duration): durations.append(duration)
            case .requiresImportPreparation(let reason): return .rejected(.requiresImportPreparation(reason))
            case .invalid(let reason): return .rejected(.invalidMedia(reason))
            }
        }
        return .ready(durations)
    }

    /// Runs inside the lifecycle gate. Never acquires the gate itself (it is not reentrant).
    private func commit(_ intent: Intent, sources: [SelectedVideoSource], durations: [MediaTime]) async -> Outcome {
        let projectID = UUID()

        // 3. Prior snapshot (D8.5a P1) before anything is materialized: B's ID must be verified absent, and
        //    a replacement target must still exist and still be the current saved Project. Unreadable is
        //    never read as absence; a row already holding the brand-new ID would contradict the expected
        //    prior state, so it stops here too (fail safe).
        guard case .absent = repository.observePersistedProject(id: projectID) else {
            log("prior inspection", nil)
            return .projectInspectionFailed
        }
        var previous: VlogProject?
        if case .replacingSaved(let previousID) = intent {
            switch repository.observePersistedProject(id: previousID) {
            case .unreadable:
                log("prior inspection", nil)
                return .projectInspectionFailed
            case .absent:
                MellowLog.app.info("Project composition replacement target invalidated: absent")
                return .replacementTargetInvalidated
            case .present(let project):
                // "A is still current" through the same fresh-read policy and the existing current-Project
                // ordering; an undeterminable current Project is fail-closed.
                switch repository.observeCurrentProjectID() {
                case .unreadable:
                    log("prior inspection", nil)
                    return .projectInspectionFailed
                case .project(let current) where current == previousID:
                    previous = project
                case .none, .project:
                    MellowLog.app.info("Project composition replacement target invalidated: not current")
                    return .replacementTargetInvalidated
                }
            }
        }

        // 4. Materialize into B's own directory and build B. Everything up to the save attempt is pre-save:
        //    B's directory is this operation's own and nothing was persisted, so it may still be removed.
        var clips: [VlogClip] = []
        for (index, source) in sources.enumerated() {
            let clipID = UUID()
            do {
                let path = try await mediaStore.materialize(source.url, projectID: projectID, clipID: clipID)
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
                return .preparationFailed
            }
        }
        let project: VlogProject
        let expectation: ProjectSaveExpectation
        do {
            project = try VlogProject(id: projectID, orientation: .portrait9x16, clips: clips)
            expectation = try previous.map { try ProjectSaveExpectation.replace($0, with: project) } ?? .create(project)
        } catch {
            log("metadata", error)
            await mediaStore.removeProjectMedia(projectID: projectID)
            return .preparationFailed
        }
        // B's media and metadata are checked before the save (ADR-033 Revision 1 step 5); the repository
        // additionally checks the staged replacement mapping before staging.
        var mediaPresent = true
        for clip in project.clips where await !mediaStore.fileExists(clip.mediaRelativePath) { mediaPresent = false }
        guard mediaPresent, expectation.isStructurallyValid else {
            log("pre-save check", nil)
            await mediaStore.removeProjectMedia(projectID: projectID)
            return .preparationFailed
        }

        // 5. One save: `create` for a fresh Project, the single-save `replaceProject` for a replacement.
        //    Any error from the call — `projectNotFound` included — is classified from the observation like
        //    every other thrown save (D8.0); an error name alone is not proof that nothing was saved.
        //    From here on B's media (and A's) may be referenced and is never removed on a non-completed
        //    outcome; an unreferenced copy is startup recovery's.
        let attempt: ProjectSaveAttempt
        var saveError: Error?
        do {
            if let previous {
                try repository.replaceProject(previousID: previous.id, with: project)
            } else {
                try repository.create(project)
            }
            attempt = .succeeded
        } catch {
            saveError = error
            attempt = .threw
        }

        // 6. Observe (OD-10) and classify (D8.0) before the gate is released.
        let observation = repository.observePersistedState(for: expectation)
        let outcome = ProjectSaveOutcomeClassifier.classify(attempt, expectation: expectation, observation: observation)
        let short = String(projectID.uuidString.prefix(8))
        switch outcome {
        case .completed:
            if let saveError {
                // D8.5a P4: completion is confirmed, so the thrown error is logged only.
                log("save (completed despite error)", saveError)
            }
            // 7. A's media goes only after `completed` with A's row observed absent. Removal is
            //    best-effort and never changes the already-confirmed save outcome.
            if let previous, observation.projects[previous.id] == .absent {
                await mediaStore.removeProjectMedia(projectID: previous.id)
            }
            return .committed(projectID: projectID)
        case .committedUnverified(let reason):
            MellowLog.app.error("Project composition save unverified project=\(short, privacy: .public) reason=\(String(describing: reason), privacy: .public); media preserved")
            return .committedUnverified(reason)
        case .indeterminate(let reason):
            if let saveError { log("save", saveError) }
            MellowLog.app.error("Project composition save indeterminate project=\(short, privacy: .public) reason=\(String(describing: reason), privacy: .public); media preserved")
            return .indeterminate(reason)
        case .priorConfirmed:
            if let saveError { log("save", saveError) }
            MellowLog.app.info("Project composition save not applied project=\(short, privacy: .public); candidate files left to startup recovery")
            return .priorConfirmed
        }
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
