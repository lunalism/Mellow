import Foundation
import OSLog

// ADR-050 050-D D7a §2 / §3 same-set Retry over `ImportAttemptCoordinator` (internal, unwired). One operation
// keeps its original Accepted Set, plans, workspace and target across attempts. Retry eligibility is the owner-
// approved 2026-10-06 classification (D7a "Retry 자격 분류"), applied to the last attempt's typed outcome and
// same-process rollback evidence; source, target and CR are revalidated by the coordinator's own admission on
// every Retry. No UI copy, alerts, picker access, durable journal or process resume.

/// Why the last outcome does not allow a Retry. Category only; never user copy.
enum ImportRetryIneligibility: Equatable, Sendable {
    case notStarted
    case completed
    case uncertainPersistence
    case initialAdmissionRefusal
    case sourceInvalidated
    case targetInvalidated
    case cancelled
    case cleanupUnresolved
    /// A caller or bookkeeping defect, a non-shortage boundary result, or `destinationOccupied`.
    case nonRetryableFailure
    /// Retry admission's CR could not be evaluated (`invalidEstimate` / `invalidBoundaryState`): repeating the
    /// same check cannot succeed, so it never becomes a capacity-refusal loop (owner clarification 2026-10-06).
    case retryAdmissionDefect
    /// The operation already ended (terminal state).
    case operationEnded
}

enum ImportRetryEligibility: Equatable, Sendable {
    case eligible
    case ineligible(ImportRetryIneligibility)

    /// Pure classification of one attempt outcome (owner-approved 2026-10-06). Eligible only after a
    /// `verifiedClean` rollback with no accepted cancellation, and only for: `notSaved` (`priorConfirmed`), a C2
    /// or C3 shortage (insufficient or unknown capacity), `normalizationFailed` other than `cleanupFailed`,
    /// `normalizationResultRejected`, `materializationFailed`, `mediaVerificationFailed`,
    /// `attemptDirectoryUnavailable`. Valid sources and target are established afterwards by the Retry
    /// attempt's own admission, never assumed here.
    static func evaluate(_ outcome: ImportAttemptOutcome) -> ImportRetryEligibility {
        switch outcome {
        case .completed: return .ineligible(.completed)
        case .committedUnverified, .indeterminate: return .ineligible(.uncertainPersistence)
        case .refused(let refusal):
            switch refusal {
            case .cancelled: return .ineligible(.cancelled)
            case .target: return .ineligible(.targetInvalidated)
            case .invalidInput(.sourceUnavailable), .invalidInput(.sourceChanged): return .ineligible(.sourceInvalidated)
            case .storage(let result) where result.boundary == .c1BeforePreparation: return .ineligible(.initialAdmissionRefusal)
            case .invalidInput, .storage: return .ineligible(.nonRetryableFailure)
            }
        case .notSaved(let rollback):
            return gate(rollback) ?? .eligible
        case .failedBeforeSave(let failure, let rollback):
            if let blocked = gate(rollback) { return blocked }
            switch failure {
            case .storage(let result):
                guard result.boundary == .c2BeforeNormalizationItem || result.boundary == .c3BeforeMaterialization else { return .ineligible(.nonRetryableFailure) }
                switch result.outcome {
                case .insufficient, .capacityUnknown: return .eligible
                case .sufficient, .invalidEstimate, .invalidBoundaryState: return .ineligible(.nonRetryableFailure)
                }
            case .normalizationFailed(_, .cleanupFailed?): return .ineligible(.cleanupUnresolved)
            case .normalizationFailed, .normalizationResultRejected, .materializationFailed, .mediaVerificationFailed, .attemptDirectoryUnavailable:
                return .eligible
            case .cancelled: return .ineligible(.cancelled)
            case .target: return .ineligible(.targetInvalidated)
            case .sourceChanged: return .ineligible(.sourceInvalidated)
            case .inconsistentPreparation, .inconsistentWorkSet, .metadataInvalid, .destinationOccupied: return .ineligible(.nonRetryableFailure)
            }
        }
    }

    /// The rollback preconditions every eligible category shares.
    private static func gate(_ rollback: ImportAttemptRollback) -> ImportRetryEligibility? {
        guard rollback.result.isVerifiedClean else { return .ineligible(.cleanupUnresolved) }
        guard !rollback.cancellationRequested else { return .ineligible(.cancelled) }
        return nil
    }
}

/// The one attempt operation the controller drives (`ImportAttemptCoordinator`; tests may script outcomes).
@MainActor
protocol ImportAttemptRunning: AnyObject {
    /// Must not be called while holding the lifecycle gate (the coordinator takes its own sections).
    func runAttempt(_ request: ImportAttemptRequest) async -> ImportAttemptOutcome
}

extension ImportAttemptCoordinator: ImportAttemptRunning {
    func runAttempt(_ request: ImportAttemptRequest) async -> ImportAttemptOutcome { await run(request, events: nil) }
}

/// Ends the operation's ownership of its workspace (`ProjectMediaStore.discard`). Called only when the evidence
/// proves nothing in it must be kept.
protocol ImportOperationWorkspaceReleasing: Sendable {
    func discard(_ workspace: ProjectMediaWorkspace) async
}

extension ProjectMediaStore: ImportOperationWorkspaceReleasing {}

/// What one `start()` / `retry()` / `cancel()` call produced. Categories only; no copy.
enum ImportRetryResult: Equatable, Sendable {
    /// An attempt ran (or was refused by its own checks). Read `state` for what follows: usually the outcome sets
    /// it, but an unrequested `.refused(.cancelled)` on Retry leaves the operation waiting on its prior evidence.
    case attempted(ImportAttemptOutcome)
    /// Retry admission: a retained source is gone or changed. The operation ended.
    case sourceInvalid(ImportAttemptInputProblem)
    /// Retry admission: the target is confirmed absent, changed (stale), not current, or its new identity is
    /// unavailable. Retry eligibility ended.
    case targetInvalid(ImportAttemptTargetProblem)
    /// Retry admission: the target could not be READ — unknown, not proven invalid (owner clarification
    /// 2026-10-06). The operation keeps waiting on its previous eligible evidence and retained sources; a later
    /// explicit Retry revalidates sources and target before CR. No automatic loop.
    case targetUnavailable
    /// Retry admission: CR found insufficient or unknown capacity. The operation keeps waiting with its previous
    /// eligible evidence; each explicit Retry revalidates and reruns CR. No automatic loop.
    case capacityRefused(ImportBoundaryCheckResult)
    /// Retry admission: CR returned `invalidEstimate` / `invalidBoundaryState` (a defect, not a shortage). Retry
    /// eligibility ended (`.ended(.retryAdmissionDefect)`).
    case retryAdmissionDefect(ImportBoundaryCheckResult)
    case ineligible(ImportRetryIneligibility)
    /// An attempt is already running for this operation; nothing was started.
    case busy
}

/// The operation's explicit state. The workspace stays owned (live) in every state except those that say it
/// was released.
enum ImportRetryOperationState: Equatable, Sendable {
    case idle
    case running
    /// Waiting for an explicit Retry; `evidence` is the last eligible attempt outcome (never a CR refusal).
    case awaitingRetry(evidence: ImportAttemptOutcome)
    /// `completed`; workspace released.
    case succeeded(ImportAttemptCommit)
    /// `committedUnverified` / `indeterminate`: Project media preserved; never retried. The workspace (whose files
    /// no durable row can reference) was released.
    case uncertain(ImportAttemptOutcome)
    /// Ended with verified cleanup (or nothing mutated); workspace released.
    case ended(ImportRetryIneligibility)
    /// Ended with unresolved restoration / cleanup or preserved evidence: the workspace is deliberately kept and
    /// still owned. Only a later accepted recovery policy may release it.
    case retainedUnresolved(ImportAttemptOutcome)

    var isTerminal: Bool {
        switch self {
        case .succeeded, .uncertain, .ended, .retainedUnresolved: return true
        case .idle, .running, .awaitingRetry: return false
        }
    }
}

@MainActor
final class ImportRetryController {
    private let coordinator: any ImportAttemptRunning
    private let workspaces: any ImportOperationWorkspaceReleasing
    private let request: ImportAttemptRequest
    private(set) var state: ImportRetryOperationState = .idle
    /// `cancel()` callers waiting for the running attempt to be fully processed (outcome absorbed and any
    /// workspace release finished). Woken only by `settle()`.
    private var settledWaiters: [CheckedContinuation<Void, Never>] = []
    private var running: Task<ImportAttemptOutcome, Never>?
    /// Set by `requestCancellation()` (and so `cancel()`) while an attempt runs; the operation ends once that
    /// attempt's outcome is processed.
    private var cancelRequested = false
    /// A terminal workspace release is in progress (`end`); `cancel()` callers wait for it to finish.
    private var releasing = false

    /// The controller owns `request.workspace` from here on. `request` becomes the first attempt (`.initial`);
    /// every Retry reuses the same Accepted Set, plans, workspace and target with `.retry` admission.
    init(coordinator: any ImportAttemptRunning, workspaces: any ImportOperationWorkspaceReleasing, request: ImportAttemptRequest) {
        self.coordinator = coordinator
        self.workspaces = workspaces
        self.request = ImportAttemptRequest(accepted: request.accepted, plans: request.plans, workspace: request.workspace,
                                            target: request.target, admission: .initial)
    }

    /// Runs the first attempt. Never holds the lifecycle gate: the coordinator takes its own sections.
    ///
    /// Cancellation is only `cancel()` / `requestCancellation()`: the attempt runs in a task this controller owns,
    /// so cancelling the CALLER's task does not cancel it — this guarantees the outcome (rollback included) is
    /// always absorbed before ownership changes.
    func start() async -> ImportRetryResult {
        switch state {
        case .idle: break
        case .running: return .busy
        default: return .ineligible(.operationEnded)
        }
        state = .running   // reserved before any await
        defer { settle() }
        let outcome = await execute(request)
        await absorb(outcome)
        return .attempted(outcome)
    }

    /// One explicit same-set Retry. The in-flight state is reserved synchronously; a second call while running is
    /// `busy`. Source, target and CR are revalidated by the attempt's own admission — this controller reads no
    /// capacity and holds no gate.
    func retry() async -> ImportRetryResult {
        let evidence: ImportAttemptOutcome
        switch state {
        case .running: return .busy
        case .idle: return .ineligible(.notStarted)
        case .succeeded, .uncertain, .ended, .retainedUnresolved: return .ineligible(.operationEnded)
        case .awaitingRetry(let previous): evidence = previous
        }
        // Defensive: the stored evidence must still classify as eligible.
        if case .ineligible(let reason) = ImportRetryEligibility.evaluate(evidence) { return .ineligible(reason) }
        state = .running   // reserved before any await
        defer { settle() }
        let outcome = await execute(request.forRetry)

        if case .refused(let refusal) = outcome, !cancelRequested {
            switch refusal {
            case .storage(let result) where result.boundary == .crBeforeRetry:
                switch result.outcome {
                case .insufficient, .capacityUnknown:
                    // Nothing was mutated; the prior eligible evidence stays the Retry basis. No automatic loop.
                    state = .awaitingRetry(evidence: evidence)
                    return .capacityRefused(result)
                case .invalidEstimate, .invalidBoundaryState, .sufficient:
                    // Not a shortage: the same check would fail again. This refused attempt mutated nothing and the
                    // evidence that put the operation in `awaitingRetry` was verified clean, so the workspace may go.
                    await end(.ended(.retryAdmissionDefect))
                    return .retryAdmissionDefect(result)
                }
            case .cancelled:
                // A cancellation nobody requested (e.g. thrown by the capacity reader): nothing was mutated, so the
                // operation keeps waiting on its prior eligible evidence instead of ending and dropping the sources.
                state = .awaitingRetry(evidence: evidence)
                return .attempted(outcome)
            case .invalidInput(let problem) where Self.isSourceInvalidation(problem):
                await absorb(outcome)
                return .sourceInvalid(problem)
            case .target(.unreadable):
                // Unknown, not proven invalid: keep the evidence, retained sources and waiting state.
                state = .awaitingRetry(evidence: evidence)
                return .targetUnavailable
            case .target(let problem):
                // Confirmed absence / change (stale state is never read as unreadable): eligibility ends.
                await absorb(outcome)
                return .targetInvalid(problem)
            default:
                break
            }
        }
        await absorb(outcome)
        return .attempted(outcome)
    }

    /// Cancels the operation. A running attempt is cancelled and AWAITED: its own rollback / save processing and
    /// this controller's outcome handling finish before anything is released (a `completed` save stays a success,
    /// unresolved cleanup stays retained). Between attempts the last rollback was verified, so the operation ends
    /// with the workspace released.
    func cancel() async {
        switch state {
        case .running:
            requestCancellation()
            // start() / retry() absorb the outcome and finish any release, then settle() wakes this (no polling).
            await withCheckedContinuation { settledWaiters.append($0) }
        case .awaitingRetry, .idle:
            await end(.ended(.cancelled))
        case .succeeded, .uncertain, .ended, .retainedUnresolved:
            // Never return while the terminal release is still running.
            if releasing { await withCheckedContinuation { settledWaiters.append($0) } }
        }
    }

    /// The synchronous half of `cancel()` for a running attempt: records the request and cancels the attempt task.
    /// The attempt's own cancellation boundary decides the outcome (a save already attempted stays as classified).
    func requestCancellation() {
        guard state == .running else { return }
        cancelRequested = true
        running?.cancel()
    }

    // MARK: - Private

    /// Wakes `cancel()` callers after the attempt's outcome, state and any workspace release are complete.
    private func settle() {
        let waiters = settledWaiters
        settledWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func execute(_ request: ImportAttemptRequest) async -> ImportAttemptOutcome {
        cancelRequested = false
        let coordinator = self.coordinator
        let task = Task { await coordinator.runAttempt(request) }
        running = task
        let outcome = await task.value
        running = nil
        return outcome
    }

    /// Applies one attempt outcome. Workspace release follows the evidence, never ineligibility alone: released after
    /// `completed` or an uncertain save (no durable row can reference a workspace file; Project media is untouched),
    /// after verified cleanup, or when nothing was mutated; KEPT whenever restoration / cleanup is unresolved.
    private func absorb(_ outcome: ImportAttemptOutcome) async {
        switch outcome {
        case .completed(let commit):
            await end(.succeeded(commit))
        case .committedUnverified, .indeterminate:
            await end(.uncertain(outcome))
        case .failedBeforeSave(_, let rollback), .notSaved(let rollback):
            if !rollback.result.isVerifiedClean {
                state = .retainedUnresolved(outcome)
                MellowLog.app.error("Import retry operation retained an unresolved workspace")
            } else if !cancelRequested, ImportRetryEligibility.evaluate(outcome) == .eligible {
                state = .awaitingRetry(evidence: outcome)
            } else {
                await end(.ended(cancelRequested ? .cancelled : Self.reason(outcome)))
            }
        case .refused:
            // (For the FIRST attempt an unrequested `.cancelled` refusal also ends here: there is no retry state yet.
            // Only `retry()` keeps waiting on it, because there a verified eligible evidence already exists.)
            // This attempt mutated nothing, and an earlier attempt's cleanup was verified (that made it eligible).
            await end(.ended(cancelRequested ? .cancelled : Self.reason(outcome)))
        }
    }

    /// Records the terminal state FIRST, then releases the workspace (verified-safe states only).
    private func end(_ terminal: ImportRetryOperationState) async {
        state = terminal
        releasing = true
        await workspaces.discard(request.workspace)
        releasing = false
        settle()
    }

    private static func reason(_ outcome: ImportAttemptOutcome) -> ImportRetryIneligibility {
        if case .ineligible(let reason) = ImportRetryEligibility.evaluate(outcome) { return reason }
        return .nonRetryableFailure
    }

    private static func isSourceInvalidation(_ problem: ImportAttemptInputProblem) -> Bool {
        switch problem {
        case .sourceUnavailable, .sourceChanged: return true
        default: return false
        }
    }
}
