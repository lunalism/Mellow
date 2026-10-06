import Foundation
import OSLog

// ADR-050 050-D D7a (bounded recovery), the 050-C execution boundaries C1 / C2 / C3 and D8.0 save-outcome
// classification, applied to ONE import attempt (internal, unwired). It consumes an already classified
// Accepted Set, its plans, a live workspace and an explicit target, and returns a typed outcome with the
// cleanup and retained-source facts a future retry controller needs. It does not orchestrate CR / Retry,
// open a picker, show copy, keep a durable journal or resume after process exit (ADR-047). No production
// flow calls it yet.

/// What the attempt commits into. Every target is re-read under the shared lifecycle gate with the
/// accepted fresh-read policy (OD-10) before C1 and again before materialization and before the save.
enum ImportAttemptTarget: Equatable, Sendable {
    /// Select Clips: a brand-new Project B (`create`).
    case newProject
    /// Select Clips: replace the current saved Project A with B in one save (`replaceProject`, ADR-033
    /// Revision 1). A must still exist and still be the current saved Project; B is never created alone.
    case replacingSaved(previousID: UUID)
    /// Editor Add onto the Editor's base state (`update`). The fresh prior must equal `base` exactly (D8.5c).
    case add(base: VlogProject)
    /// Editor Replace of the active Clip `clipID` of `base` (`update`); exactly one accepted item.
    case replaceClip(base: VlogProject, clipID: UUID)
}

/// Which accepted 050-C boundary the admission section checks. Both use the same requirement (remaining
/// normalization outputs + current metadata + Import reserve) at the same serialized point, after the
/// source and target checks; only the boundary — and so its refusal route — differs.
enum ImportAttemptAdmission: Equatable, Sendable {
    /// The operation's first attempt: C1 (initial storage refusal).
    case initial
    /// A same-set Retry attempt: CR (retry-capacity refusal) in place of C1, never in addition to it.
    case retry
}

struct ImportAttemptRequest: Sendable {
    /// The Accepted Set in its accepted order (Step 3 preflight output; ready and normalization items).
    let accepted: [ImportAcceptedItem]
    /// Exactly the plans `WorkingMediaPlanBuilder` derives for the normalization items.
    let plans: [ImportCandidateID: WorkingMediaNormalizationPlan]
    /// The operation's live workspace; every accepted source is a direct child of it.
    let workspace: ProjectMediaWorkspace
    let target: ImportAttemptTarget
    let admission: ImportAttemptAdmission

    init(accepted: [ImportAcceptedItem], plans: [ImportCandidateID: WorkingMediaNormalizationPlan], workspace: ProjectMediaWorkspace,
         target: ImportAttemptTarget, admission: ImportAttemptAdmission = .initial) {
        self.accepted = accepted
        self.plans = plans
        self.workspace = workspace
        self.target = target
        self.admission = admission
    }

    /// The same operation inputs for a Retry attempt.
    var forRetry: ImportAttemptRequest {
        ImportAttemptRequest(accepted: accepted, plans: plans, workspace: workspace, target: target, admission: .retry)
    }
}

/// Internal stage markers (diagnostics / tests). Not a progress policy: no counts, no fractions, no copy.
enum ImportAttemptEvent: Equatable, Sendable {
    case boundaryChecked(ImportBoundaryCheckResult)
    case normalizationStarted(ImportCandidateID)
    /// Bounded progress `0...1` reported by the normalizer for this item (may arrive late or out of order; consumers
    /// clamp and ignore stale values — ADR-050 050-D D7b §5).
    case normalizationProgress(ImportCandidateID, Double)
    case normalizationFinished(ImportCandidateID)
    /// Inside the commit gate section, after C3, before the first materialization.
    case materializationStarted
    /// Inside the gate, immediately before the final cancellation check and the synchronous save.
    case saveImminent
}

/// A caller defect or an input that no longer matches its preflight facts. Found before any mutation.
enum ImportAttemptInputProblem: Error, Equatable, Sendable {
    case emptyAcceptedSet
    case replaceRequiresOneItem(count: Int)
    /// The Replace target is not an active Clip of the given base.
    case replaceTargetNotActive
    /// The source is not a direct child of the request's workspace directory.
    case sourceOutsideWorkspace(ImportCandidateID)
    /// The source is not a regular file (or the workspace is not live / real).
    case sourceUnavailable(ImportCandidateID)
    /// The source's size no longer equals the size its preflight facts recorded.
    case sourceChanged(ImportCandidateID)
    /// Two candidates name the same file.
    case duplicateSource(ImportCandidateID)
    case workSet(ImportStorageCompositionError)
}

/// Why the target no longer admits this attempt. Unreadable is never read as absence.
enum ImportAttemptTargetProblem: Error, Equatable, Sendable {
    case unreadable
    /// Add / Replace: the Project row is gone. Replacement: A is gone.
    case projectAbsent
    /// Add / Replace: the fresh prior is not exactly the Editor's base (stale). Also any change of the
    /// prior between the reads of one commit section.
    case projectChanged
    /// Replacement: A is no longer the current saved Project.
    case notCurrentSavedProject
    /// The brand-new Project identity is not verifiably absent.
    case newProjectIdentityUnavailable
}

/// Nothing was created, moved, renamed or saved.
enum ImportAttemptRefusal: Equatable, Sendable {
    case cancelled
    case invalidInput(ImportAttemptInputProblem)
    case target(ImportAttemptTargetProblem)
    /// The admission check did not pass: C1 for `.initial` (initial storage refusal route), CR for `.retry`
    /// (retry-capacity refusal route). Unknown capacity fails closed onto the same route.
    case storage(ImportBoundaryCheckResult)
}

/// Why an admitted attempt stopped before any save was attempted.
enum ImportAttemptFailure: Error, Equatable, Sendable {
    case cancelled
    /// C2 or C3 did not pass. An `.invalidBoundaryState` outcome inside is a caller defect, not a shortage.
    case storage(ImportBoundaryCheckResult)
    case attemptDirectoryUnavailable
    /// nil when the normalizer threw something outside its declared error type. A `cleanupFailed` error is
    /// reported here even when it was caused by cancellation, so its evidence is never dropped: such a cancel is
    /// recognised by `ImportAttemptRollback.cancellationRequested`, and its cleanup is always unresolved.
    case normalizationFailed(ImportCandidateID, WorkingMediaNormalizationError?)
    /// The normalizer reported success with a result that does not belong to this item, does not fit
    /// the ADR-045 §7 window, or does not cover the accepted trim (owner decision 2026-10-06).
    case normalizationResultRejected(ImportCandidateID)
    case inconsistentWorkSet(ImportStorageCompositionError)
    /// The attempt's own bookkeeping disagrees with the Accepted Set (a ready item with an output, or a
    /// normalization item without one). A defect; never a pass.
    case inconsistentPreparation(ImportCandidateID)
    case target(ImportAttemptTargetProblem)
    /// A ready source changed size between admission and its materialization.
    case sourceChanged(ImportCandidateID)
    /// The canonical destination of a new Clip was not verifiably free, so it is never claimed.
    case destinationOccupied(ImportCandidateID)
    case materializationFailed(ImportCandidateID)
    case metadataInvalid
    case mediaVerificationFailed
}

/// One accepted source as the attempt recorded it before any mutation (D7 §2 facts for a later Retry).
struct ImportRetainedSource: Equatable, Sendable {
    let candidateID: ImportCandidateID
    let workspaceFileName: String
    let recordedByteCount: Int64
}

/// The D7a §1 rollback this attempt ran, with the facts a future retry controller re-checks. A
/// `verifiedClean` result is necessary, never sufficient, for Retry: sources, target and CR must still be
/// established by that controller, and a requested cancellation ends the operation (D7a §3).
struct ImportAttemptRollback: Equatable, Sendable {
    let result: ImportRollbackOutcome
    let retainedSources: [ImportRetainedSource]
    /// The task was cancelled at any point up to the end of the rollback.
    let cancellationRequested: Bool
}

struct ImportAttemptCommit: Equatable, Sendable {
    /// The intended state the save outcome confirmed.
    let project: VlogProject
    /// The new Clips in Accepted Set order.
    let clipIDs: [UUID]
    /// `completed` after a thrown save (D8.5a P4): success; the error is only logged.
    let saveThrew: Bool
    /// Replacement only: A's row was observed absent and A's media removal was requested.
    let replacedProjectMediaRemoved: Bool
}

/// Media a non-completed save may reference: preserved, never rolled back (D8.0), no Retry.
struct ImportAttemptPreservedMedia: Equatable, Sendable {
    let projectID: UUID
    let mediaPaths: [RelativeMediaPath]
}

enum ImportAttemptOutcome: Equatable, Sendable {
    case refused(ImportAttemptRefusal)
    /// Stopped before any save attempt; the attempt's own candidates went through D7a rollback.
    case failedBeforeSave(ImportAttemptFailure, ImportAttemptRollback)
    /// The save threw and the prior state is confirmed (D8.0 `priorConfirmed`); rolled back under D7a.
    case notSaved(ImportAttemptRollback)
    case completed(ImportAttemptCommit)
    /// The save returned but its result is not confirmed (D8.0). Media preserved.
    case committedUnverified(ImportAttemptPreservedMedia, ProjectSaveOutcomeReason)
    /// The save threw and nothing is confirmed (D8.0). Media preserved; Retry prohibited.
    case indeterminate(ImportAttemptPreservedMedia, ProjectSaveOutcomeReason)
}

/// Runs one import attempt. Gate ownership is explicit: two `withExclusiveAccess` sections — admission
/// (fresh target read, work set from current metadata, C1) and commit (fresh target read, work set
/// rebuilt from current metadata, C3, ownership records, materialization, verification, target re-check,
/// the final cancellation check, ONE save, observation, classification, and any rollback or A-media
/// removal). Preparation (attempt directory, normalization, C2) runs outside the gate; the workspace is
/// protected by the store's live-workspace registry. Private helpers that run inside a section assume the
/// gate is held and never acquire it. The workspace itself is never discarded here: its owner does that.
@MainActor
final class ImportAttemptCoordinator {
    typealias CapacityReader = @Sendable () async throws -> Int64?

    private let repository: any ProjectRepository
    private let mediaStore: any ImportAttemptMediaStoring
    private let normalizer: any WorkingMediaNormalizing
    private let lifecycle: ProjectLifecycleOperationGate
    /// Usable capacity of the Mellow-root volume (050-C C1 / C2 / C3). nil / negative / errors fail closed.
    private let capacity: CapacityReader

    init(repository: any ProjectRepository, mediaStore: any ImportAttemptMediaStoring, normalizer: any WorkingMediaNormalizing,
         lifecycle: ProjectLifecycleOperationGate, capacity: @escaping CapacityReader) {
        self.repository = repository
        self.mediaStore = mediaStore
        self.normalizer = normalizer
        self.lifecycle = lifecycle
        self.capacity = capacity
    }

    /// Cancellation is the calling task's: accepted until immediately before the synchronous save call.
    /// Precondition: the caller does not hold the lifecycle gate (it is not reentrant).
    func run(_ request: ImportAttemptRequest, events: ((ImportAttemptEvent) -> Void)? = nil) async -> ImportAttemptOutcome {
        assert(!lifecycle.isHeld, "run acquires the shared lifecycle gate itself; a holder must never call it")
        let attempt = Attempt(request: request, newProjectID: UUID(), emit: events ?? { _ in })
        if Task.isCancelled { return .refused(.cancelled) }

        // 1. Inputs: read-only on the live workspace, outside the gate. Sizes are recorded before any mutation.
        switch await validateInputs(attempt) {
        case .failure(let problem): return .refused(.invalidInput(problem))
        case .success(let retained): attempt.retained = retained
        }

        // 2. Admission section: fresh target read, work set from the current metadata, C1.
        if let refusal = await lifecycle.withExclusiveAccess({ await self.admitInsideGate(attempt) }) {
            return .refused(refusal)
        }

        // 3. Preparation outside the gate: attempt directory, normalization in accepted order, C2.
        if let failure = await prepare(attempt) {
            // Nothing is materialized yet: only the attempt directory can be owned output.
            return .failedBeforeSave(failure, await rollBack(attempt))
        }

        // 4. Commit section.
        return await lifecycle.withExclusiveAccess { await self.commitInsideGate(attempt) }
    }

    /// Per-run state. Main-actor bound like the coordinator.
    @MainActor
    private final class Attempt {
        let request: ImportAttemptRequest
        /// B for `.newProject` / `.replacingSaved`.
        let newProjectID: UUID
        let emit: (ImportAttemptEvent) -> Void
        var retained: [ImportRetainedSource] = []
        var workSet: ImportStorageWorkSet?
        var attemptDirectoryName: String?
        /// The normalizer reported unresolved cleanup inside the attempt directory: keep it as evidence.
        var normalizerCleanupUnresolved = false
        var outputs: [ImportCandidateID: WorkingMediaNormalizationResult] = [:]
        /// Ownership records, appended BEFORE the filesystem mutation they describe.
        var records: [ImportRollbackRecord] = []

        init(request: ImportAttemptRequest, newProjectID: UUID, emit: @escaping (ImportAttemptEvent) -> Void) {
            self.request = request
            self.newProjectID = newProjectID
            self.emit = emit
        }

        var projectID: UUID {
            switch request.target {
            case .newProject, .replacingSaved: return newProjectID
            case .add(let base), .replaceClip(let base, _): return base.id
            }
        }

        var short: String { String(projectID.uuidString.prefix(8)) }
    }

    // MARK: - Inputs

    private func validateInputs(_ attempt: Attempt) async -> Result<[ImportRetainedSource], ImportAttemptInputProblem> {
        let request = attempt.request
        guard !request.accepted.isEmpty else { return .failure(.emptyAcceptedSet) }
        if case .replaceClip(let base, let clipID) = request.target {
            guard request.accepted.count == 1 else { return .failure(.replaceRequiresOneItem(count: request.accepted.count)) }
            guard base.clips.contains(where: { $0.id == clipID }) else { return .failure(.replaceTargetNotActive) }
        }
        let workspacePath = request.workspace.directory.standardizedFileURL.path
        var retained: [ImportRetainedSource] = []
        var seenPaths = Set<String>()
        for item in request.accepted {
            let id = item.candidate.id, url = item.candidate.url
            guard seenPaths.insert(url.standardizedFileURL.path).inserted else { return .failure(.duplicateSource(id)) }
            guard url.isFileURL, url.deletingLastPathComponent().standardizedFileURL.path == workspacePath else { return .failure(.sourceOutsideWorkspace(id)) }
            guard let size = await mediaStore.workspaceFileByteCount(url, in: request.workspace) else { return .failure(.sourceUnavailable(id)) }
            guard size == item.facts.byteCount else { return .failure(.sourceChanged(id)) }
            retained.append(ImportRetainedSource(candidateID: id, workspaceFileName: url.lastPathComponent, recordedByteCount: size))
        }
        return .success(retained)
    }

    // MARK: - Target (inside the gate)

    private struct ResolvedTarget {
        /// The fresh prior Project: A for a replacement, the base for Add / Replace, nil for a new Project.
        let prior: VlogProject?
        let operation: ImportStorageOperation
    }

    /// INSIDE the gate (never acquires it). OD-10 fresh reads only; nothing is mutated.
    private func resolveTargetInsideGate(_ attempt: Attempt) -> Result<ResolvedTarget, ImportAttemptTargetProblem> {
        assert(lifecycle.isHeld, "target resolution runs inside the shared lifecycle gate")
        func newProjectAbsent() -> ImportAttemptTargetProblem? {
            switch repository.observePersistedProject(id: attempt.newProjectID) {
            case .absent: return nil
            case .unreadable: return .unreadable
            case .present: return .newProjectIdentityUnavailable
            }
        }
        func verifiedBase(_ base: VlogProject) -> Result<VlogProject, ImportAttemptTargetProblem> {
            switch repository.observePersistedProject(id: base.id) {
            case .present(let stored) where ProjectStateSnapshot(stored) == ProjectStateSnapshot(base): return .success(stored)
            case .present: return .failure(.projectChanged)
            case .unreadable: return .failure(.unreadable)
            case .absent: return .failure(.projectAbsent)
            }
        }
        switch attempt.request.target {
        case .newProject:
            if let problem = newProjectAbsent() { return .failure(problem) }
            return .success(ResolvedTarget(prior: nil, operation: .createProject))
        case .replacingSaved(let previousID):
            if let problem = newProjectAbsent() { return .failure(problem) }
            switch repository.observePersistedProject(id: previousID) {
            case .unreadable: return .failure(.unreadable)
            case .absent: return .failure(.projectAbsent)
            case .present(let previous):
                switch repository.observeCurrentProjectID() {
                case .unreadable: return .failure(.unreadable)
                case .project(let current) where current == previousID:
                    return .success(ResolvedTarget(prior: previous, operation: .replacingSaved(previous: previous)))
                case .none, .project: return .failure(.notCurrentSavedProject)
                }
            }
        case .add(let base):
            return verifiedBase(base).map { ResolvedTarget(prior: $0, operation: .add(to: $0)) }
        case .replaceClip(let base, _):
            return verifiedBase(base).map { ResolvedTarget(prior: $0, operation: .replaceClip(in: $0)) }
        }
    }

    // MARK: - Admission section

    /// INSIDE the gate (never acquires it): the work set's metadata inputs come from this fresh read. Order:
    /// sources (already checked before the gate), target, then the single admission capacity check.
    private func admitInsideGate(_ attempt: Attempt) async -> ImportAttemptRefusal? {
        let resolved: ResolvedTarget
        switch resolveTargetInsideGate(attempt) {
        case .failure(let problem):
            MellowLog.app.info("Import attempt refused project=\(attempt.short, privacy: .public) target=\(String(describing: problem), privacy: .public)")
            return .target(problem)
        case .success(let value): resolved = value
        }
        let workSet: ImportStorageWorkSet
        do {
            workSet = try ImportStorageWorkSet(accepted: attempt.request.accepted, plans: attempt.request.plans, operation: resolved.operation)
        } catch {
            return .invalidInput(.workSet(error))
        }
        // One admission capacity check: C1 for the first attempt, CR (same requirement) for a Retry.
        let boundary: ImportAttemptBoundary = attempt.request.admission == .retry ? .crBeforeRetry : .c1BeforePreparation
        switch await check(boundary, workSet, attempt) {
        case .cancelled: return .cancelled
        case .refused(let result):
            MellowLog.app.info("Import attempt admission refused project=\(attempt.short, privacy: .public) boundary=\(String(describing: boundary), privacy: .public)")
            return .storage(result)
        case .passed:
            attempt.workSet = workSet
            return nil
        }
    }

    private enum BoundaryResult { case passed, refused(ImportBoundaryCheckResult), cancelled }

    /// Reuses `ImportAttemptBoundaryChecker` unchanged (no arithmetic here).
    private func check(_ boundary: ImportAttemptBoundary, _ workSet: ImportStorageWorkSet, _ attempt: Attempt) async -> BoundaryResult {
        let result: ImportBoundaryCheckResult
        do { result = try await ImportAttemptBoundaryChecker.check(boundary, workSet: workSet, capacity: capacity) } catch { return .cancelled }
        attempt.emit(.boundaryChecked(result))
        return result.passes ? .passed : .refused(result)
    }

    // MARK: - Preparation (outside the gate)

    /// Normalizes every normalization item in accepted order into the attempt's own directory; ready items
    /// need nothing. C2 runs before the second and each later normalization, in a short gate section of its
    /// own that re-reads the target and charges the CURRENT metadata (never the admission snapshot). An
    /// output counts as written only after the normalizer returned a result that belongs to the item.
    private func prepare(_ attempt: Attempt) async -> ImportAttemptFailure? {
        let request = attempt.request
        let normalizationItems = request.accepted.filter { $0.preparationPath.normalization != nil }
        guard !normalizationItems.isEmpty else { return Task.isCancelled ? .cancelled : nil }
        if Task.isCancelled { return .cancelled }

        // A single non-intermediate mkdir: a failed creation made nothing, and an entry that already existed
        // is not this attempt's, so the name is owned (and later removed) only after creation succeeded.
        let name = "attempt-\(UUID().uuidString)"
        let directory: URL
        do {
            directory = try await mediaStore.createAttemptDirectory(named: name, in: request.workspace)
        } catch {
            log(attempt, "attempt directory", error)
            return .attemptDirectoryUnavailable
        }
        attempt.attemptDirectoryName = name

        for item in normalizationItems {
            let id = item.candidate.id
            if Task.isCancelled { return .cancelled }
            if !attempt.outputs.isEmpty {
                // Not nested: preparation never holds the gate.
                if let failure = await lifecycle.withExclusiveAccess({ await self.c2InsideGate(attempt) }) { return failure }
            }
            guard let plan = request.plans[id] else { return .inconsistentPreparation(id) }
            let destination = directory.appendingPathComponent(id.rawValue.uuidString).appendingPathExtension(ProjectMediaLayout.mediaExtension)
            attempt.emit(.normalizationStarted(id))
            let result: WorkingMediaNormalizationResult
            do {
                result = try await normalizer.normalize(sourceURL: item.candidate.url, destinationURL: destination, plan: plan,
                                                        progress: { fraction in Task { @MainActor in attempt.emit(.normalizationProgress(id, fraction)) } })
            } catch is CancellationError {
                return .cancelled
            } catch let error as WorkingMediaNormalizationError {
                // The normalizer could not remove (or had to quarantine) something it reports: that evidence
                // stays in the attempt directory and the cleanup is never reported clean (D7a §1).
                if case .cleanupFailed = error { attempt.normalizerCleanupUnresolved = true }
                log(attempt, "normalization", error)
                return .normalizationFailed(id, error)
            } catch {
                log(attempt, "normalization", error)
                return .normalizationFailed(id, nil)
            }
            guard Self.belongs(result, to: item, plan: plan, destination: destination) else {
                MellowLog.app.error("Import attempt normalization result rejected project=\(attempt.short, privacy: .public)")
                return .normalizationResultRejected(id)
            }
            guard var workSet = attempt.workSet else { return .inconsistentPreparation(id) }
            do { try workSet.markOutputWritten(id) } catch { return .inconsistentWorkSet(error) }
            attempt.workSet = workSet
            attempt.outputs[id] = result
            attempt.emit(.normalizationFinished(id))
        }
        return nil
    }

    /// INSIDE the gate (never acquires it): C2 against the current target and metadata.
    private func c2InsideGate(_ attempt: Attempt) async -> ImportAttemptFailure? {
        switch currentWorkSetInsideGate(attempt) {
        case .failure(let failure): return failure
        case .success(let current):
            switch await check(.c2BeforeNormalizationItem, current.workSet, attempt) {
            case .cancelled: return .cancelled
            case .refused(let result): return .storage(result)
            case .passed: return nil
            }
        }
    }

    /// INSIDE the gate (never acquires it): a fresh target read and a work set rebuilt from THAT read's
    /// metadata (row counts are never assumed to stay current), with the written outputs replayed.
    private func currentWorkSetInsideGate(_ attempt: Attempt) -> Result<(resolved: ResolvedTarget, workSet: ImportStorageWorkSet), ImportAttemptFailure> {
        let resolved: ResolvedTarget
        switch resolveTargetInsideGate(attempt) {
        case .failure(let problem):
            MellowLog.app.info("Import attempt target invalidated project=\(attempt.short, privacy: .public) target=\(String(describing: problem), privacy: .public)")
            return .failure(.target(problem))
        case .success(let value): resolved = value
        }
        let request = attempt.request
        var current: ImportStorageWorkSet
        do {
            current = try ImportStorageWorkSet(accepted: request.accepted, plans: request.plans, operation: resolved.operation)
            for item in request.accepted where attempt.outputs[item.candidate.id] != nil { try current.markOutputWritten(item.candidate.id) }
        } catch {
            return .failure(.inconsistentWorkSet(error))
        }
        return .success((resolved, current))
    }

    /// The result is this item's: its destination, its accepted source duration, an output duration
    /// inside the ADR-045 §7 window, and an output that covers the whole accepted trim (owner decision
    /// 2026-10-06 — never clamped, never a shorter output).
    private static func belongs(_ result: WorkingMediaNormalizationResult, to item: ImportAcceptedItem, plan: WorkingMediaNormalizationPlan, destination: URL) -> Bool {
        result.destinationURL.standardizedFileURL.path == destination.standardizedFileURL.path
            && sameInstant(result.sourceDuration, item.sourceDuration)
            && sameInstant(plan.sourceDuration, item.sourceDuration)
            && plan.acceptedOutputDuration.contains(result.outputDuration)
            && !(result.outputDuration < item.sourceDuration)
    }

    private static func sameInstant(_ a: MediaTime, _ b: MediaTime) -> Bool { !(a < b) && !(b < a) }

    // MARK: - Commit section

    /// INSIDE the gate (never acquires it). Every failure before the save rolls back this attempt's own
    /// candidates; from the save attempt on, only `priorConfirmed` may roll back (D7a §1).
    private func commitInsideGate(_ attempt: Attempt) async -> ImportAttemptOutcome {
        let request = attempt.request
        func fail(_ failure: ImportAttemptFailure) async -> ImportAttemptOutcome {
            .failedBeforeSave(failure, await rollBack(attempt))
        }
        if Task.isCancelled { return await fail(.cancelled) }

        // Fresh target read before materialization (P1) and C3 on the current metadata.
        let resolved: ResolvedTarget, current: ImportStorageWorkSet
        switch currentWorkSetInsideGate(attempt) {
        case .failure(let failure): return await fail(failure)
        case .success(let value): (resolved, current) = value
        }
        switch await check(.c3BeforeMaterialization, current, attempt) {
        case .cancelled: return await fail(.cancelled)
        case .refused(let result): return await fail(.storage(result))
        case .passed: break
        }

        // Materialize in accepted order, each ownership record written before its move.
        attempt.emit(.materializationStarted)
        let projectID = attempt.projectID
        let retained = Dictionary(uniqueKeysWithValues: attempt.retained.map { ($0.candidateID, $0) })
        let firstSortOrder: Int
        if case .add = request.target, let prior = resolved.prior { firstSortOrder = prior.clips.count } else { firstSortOrder = 0 }
        var clips: [VlogClip] = []
        var expectedBytes: [UUID: Int64] = [:]
        for (index, item) in request.accepted.enumerated() {
            if Task.isCancelled { return await fail(.cancelled) }
            let id = item.candidate.id
            let output = attempt.outputs[id]
            guard (output != nil) == (item.preparationPath.normalization != nil) else { return await fail(.inconsistentPreparation(id)) }
            let clipID = UUID()
            guard let canonical = try? ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID) else { return await fail(.materializationFailed(id)) }
            // A record may claim only a destination verified free (lstat): rollback must never remove a file
            // the attempt did not put there.
            guard await mediaStore.mediaNode(canonical) == .missing else { return await fail(.destinationOccupied(id)) }
            let source: URL
            if let output {
                source = output.destinationURL
                expectedBytes[clipID] = output.outputByteCount
                attempt.records.append(ImportRollbackRecord(clipID: clipID, materializedPath: canonical, kind: .normalizedOutput))
            } else {
                guard let recorded = retained[id],
                      await mediaStore.workspaceFileByteCount(item.candidate.url, in: request.workspace) == recorded.recordedByteCount
                else { return await fail(.sourceChanged(id)) }
                source = item.candidate.url
                expectedBytes[clipID] = recorded.recordedByteCount
                attempt.records.append(ImportRollbackRecord(clipID: clipID, materializedPath: canonical,
                                                            kind: .ready(workspaceFileName: recorded.workspaceFileName, recordedByteCount: recorded.recordedByteCount)))
            }
            do {
                guard try await mediaStore.materialize(source, projectID: projectID, clipID: clipID) == canonical else { return await fail(.materializationFailed(id)) }
            } catch {
                log(attempt, "materialization", error)
                return await fail(.materializationFailed(id))
            }
            do {
                clips.append(try Self.clip(for: item, output: output, id: clipID, projectID: projectID, path: canonical, sortOrder: firstSortOrder + index))
            } catch {
                log(attempt, "clip metadata", error)
                return await fail(.metadataInvalid)
            }
        }

        // The intended state and its expectation, then media and metadata verification before the save.
        let intended: VlogProject
        let expectation: ProjectSaveExpectation
        do {
            switch (request.target, resolved.prior) {
            case (.newProject, nil):
                intended = try VlogProject(id: projectID, orientation: .portrait9x16, clips: clips)
                expectation = .create(intended)
            case (.replacingSaved, let previous?):
                intended = try VlogProject(id: projectID, orientation: .portrait9x16, clips: clips)
                expectation = try .replace(previous, with: intended)
            case (.add, let prior?):
                var updated = prior
                try updated.appendClips(clips)
                intended = updated
                expectation = try .update(from: prior, to: updated)
            case (.replaceClip(_, let targetID), let prior?):
                guard clips.count == 1 else { return await fail(.metadataInvalid) }
                var updated = prior
                try updated.replaceClip(id: targetID, with: clips[0])
                intended = updated
                expectation = try .update(from: prior, to: updated)
            default:
                return await fail(.metadataInvalid)
            }
        } catch {
            log(attempt, "metadata", error)
            return await fail(.metadataInvalid)
        }
        guard expectation.isStructurallyValid, !expectation.isIndistinguishable else { return await fail(.metadataInvalid) }
        // Every new Clip's media is a regular file (never a symlink) of the size it had before the move.
        for clip in clips where await mediaStore.mediaNode(clip.mediaRelativePath) != .regularFile(byteCount: expectedBytes[clip.id] ?? -1) {
            return await fail(.mediaVerificationFailed)
        }

        // Target re-check after the materialization suspensions; then no suspension point from the final
        // cancellation check through classification.
        switch resolveTargetInsideGate(attempt) {
        case .failure(let problem): return await fail(.target(problem))
        case .success(let again) where again.prior.map(ProjectStateSnapshot.init) == resolved.prior.map(ProjectStateSnapshot.init): break
        case .success: return await fail(.target(.projectChanged))
        }
        attempt.emit(.saveImminent)
        guard !Task.isCancelled else { return await fail(.cancelled) }
        var saveError: Error?
        do {
            switch request.target {
            case .newProject: try repository.create(intended)
            case .replacingSaved(let previousID): try repository.replaceProject(previousID: previousID, with: intended)
            case .add, .replaceClip: try repository.update(intended)
            }
        } catch {
            saveError = error
        }
        let observation = repository.observePersistedState(for: expectation)
        let outcome = ProjectSaveOutcomeClassifier.classify(saveError == nil ? .succeeded : .threw, expectation: expectation, observation: observation)

        // A save was attempted: cancellation no longer changes anything below.
        let preserved = ImportAttemptPreservedMedia(projectID: projectID, mediaPaths: clips.map(\.mediaRelativePath))
        switch outcome {
        case .completed:
            if let saveError { log(attempt, "save (completed despite error)", saveError) }
            var removedReplaced = false
            if case .replacingSaved(let previousID) = request.target, observation.projects[previousID] == .absent {
                // A's media only after `completed` with A's row observed absent (P8); best-effort, never
                // changes the confirmed outcome.
                await mediaStore.removeProjectMedia(projectID: previousID)
                removedReplaced = true
            }
            return .completed(ImportAttemptCommit(project: intended, clipIDs: clips.map(\.id), saveThrew: saveError != nil, replacedProjectMediaRemoved: removedReplaced))
        case .committedUnverified(let reason):
            MellowLog.app.error("Import attempt save unverified project=\(attempt.short, privacy: .public) reason=\(String(describing: reason), privacy: .public); media preserved")
            return .committedUnverified(preserved, reason)
        case .indeterminate(let reason):
            if let saveError { log(attempt, "save", saveError) }
            MellowLog.app.error("Import attempt save indeterminate project=\(attempt.short, privacy: .public) reason=\(String(describing: reason), privacy: .public); media preserved")
            return .indeterminate(preserved, reason)
        case .priorConfirmed:
            if let saveError { log(attempt, "save", saveError) }
            return .notSaved(await rollBack(attempt))
        }
    }

    /// Fast-path: `sourceDuration = trimDuration = source duration`. Normalized, for every target including Editor
    /// Replace (owner decision 2026-10-06, ADR-045 §7 and the ADR-040 §6 Revision, which changes only these
    /// duration assignments): `sourceDuration` = the validated output duration, `trimStart = 0`, `trimDuration` =
    /// the accepted source duration; the output must cover the trim (`VlogClip` rejects otherwise).
    private static func clip(for item: ImportAcceptedItem, output: WorkingMediaNormalizationResult?, id: UUID, projectID: UUID,
                             path: RelativeMediaPath, sortOrder: Int) throws -> VlogClip {
        try VlogClip(id: id, projectID: projectID, sourceKind: .imported, mediaRelativePath: path,
                     sourceDuration: output?.outputDuration ?? item.sourceDuration, trimStart: .zero,
                     trimDuration: item.sourceDuration, framing: nil, sortOrder: sortOrder)
    }

    // MARK: - Rollback

    /// D7a §1 through the store's executor: exactly this attempt's records and attempt directory. Runs to
    /// completion whatever the task's cancellation state (the executor has no cancellation point). The
    /// caller has already established eligibility (before any save attempt, or `priorConfirmed`).
    private func rollBack(_ attempt: Attempt) async -> ImportAttemptRollback {
        // After a normalizer cleanup failure the attempt directory is evidence: it is not removed, and the
        // result can never be clean.
        let preserveDirectory = attempt.normalizerCleanupUnresolved
        let plan = ImportRollbackPlan(workspace: attempt.request.workspace, projectID: attempt.projectID, records: attempt.records,
                                      attemptDirectoryName: preserveDirectory ? nil : attempt.attemptDirectoryName)
        var result = await mediaStore.rollBackAttempt(plan)
        if preserveDirectory {
            switch result {
            case .verifiedClean(let records):
                result = .unresolved(records: records, attemptDirectory: .normalizerCleanupUnresolved)
            case .unresolved(let records, let problem):
                // The executor's own directory problem (if any) is the more specific evidence.
                result = .unresolved(records: records, attemptDirectory: problem ?? .normalizerCleanupUnresolved)
            }
        }
        if !result.isVerifiedClean {
            MellowLog.app.error("Import attempt rollback unresolved project=\(attempt.short, privacy: .public); unresolved files preserved")
        }
        return ImportAttemptRollback(result: result, retainedSources: attempt.retained, cancellationRequested: Task.isCancelled)
    }

    private func log(_ attempt: Attempt, _ stage: StaticString, _ error: Error) {
        let details = error as NSError
        MellowLog.app.error("Import attempt \(stage, privacy: .public) failed project=\(attempt.short, privacy: .public): domain=\(details.domain, privacy: .public), code=\(details.code)")
    }
}
