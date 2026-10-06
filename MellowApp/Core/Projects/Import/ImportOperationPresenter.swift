import Foundation
import Observation
import OSLog

/// What a finished (terminal) import operation produced, for its owner to present with its own accepted copy.
enum ImportOperationSettlement: Equatable {
    /// `completed` (including a thrown save confirmed by evidence).
    case succeeded(ImportAttemptCommit)
    /// `committedUnverified` / `indeterminate`: media preserved, never retried.
    case uncertain(ImportAttemptOutcome)
    /// Restoration / cleanup unresolved: the workspace and evidence stay (D7a); U3.
    case retainedUnresolved(ImportAttemptOutcome)
    /// Ended with verified cleanup or nothing mutated (cancelled, refused, ineligible).
    case ended(ImportRetryIneligibility, result: ImportRetryResult, isRetryAttempt: Bool)
}

/// The shared presentation state of ONE Phase 6 import operation at a time (Select Clips, Editor Add / Replace):
/// attempts through `ImportRetryController`, the Blocking Preparation Sheet's progress (D7b §5), the Retry prompts
/// (R4 §3, CR, D7b §1), controller-owned cancellation, and route removal (D7b §4 and its clarification). Owners map
/// terminal settlements to their own accepted copy; this type introduces none.
@Observable
@MainActor
final class ImportOperationPresenter {
    /// Non-nil while the sheet is shown (only when the Accepted Set has normalization items).
    private(set) var preparation: ImportPreparationProgress?
    /// True after `취소` on the sheet until the attempt's own outcome processing finished.
    private(set) var isCancellingPreparation = false
    /// The operation waits for an explicit `다시 시도` / `취소`.
    var retryPrompt: ImportRetryPrompt?
    /// An operation is running or waiting (owners block Back / mutations meanwhile).
    var isActive: Bool { operation != nil }

    private final class Operation {
        let controller: ImportRetryController
        let needsSheet: Bool
        let normalizationIDs: [ImportCandidateID]
        let isRouteLive: () -> Bool
        let onSettle: (ImportOperationSettlement, Bool) -> Void
        let onIdle: () -> Void
        var attempt = 0
        /// Set by `다시 시도` until the Retry attempt has started (guards a double tap).
        var isRetryQueued = false
        /// Set once an unanswerable Retry wait is being ended (route removed); repeated notifications are no-ops.
        var isEndingUnreachableWait = false
        init(controller: ImportRetryController, normalizationIDs: [ImportCandidateID], isRouteLive: @escaping () -> Bool,
             onSettle: @escaping (ImportOperationSettlement, Bool) -> Void, onIdle: @escaping () -> Void) {
            self.controller = controller
            self.needsSheet = !normalizationIDs.isEmpty
            self.normalizationIDs = normalizationIDs
            self.isRouteLive = isRouteLive
            self.onSettle = onSettle
            self.onIdle = onIdle
        }
    }
    /// Tracked: owners derive Back / button availability from `isActive`.
    private var operation: Operation?

    init() {}

    /// Starts an operation and runs its first attempt. `onSettle(settlement, isRouteLive)` runs once at the terminal
    /// state (the owner suppresses UI when the route is gone); `onIdle` runs right before it, when the operation stops
    /// blocking. Never holds the lifecycle gate (the coordinator takes its own sections).
    func run(controller: ImportRetryController, normalizationIDs: [ImportCandidateID], isRouteLive: @escaping () -> Bool,
             onSettle: @escaping (ImportOperationSettlement, Bool) -> Void, onIdle: @escaping () -> Void = {}) async {
        guard operation == nil else {
            // Owners never start a second operation while one is active; a refused start must not leave them locked.
            assertionFailure("ImportOperationPresenter: an operation is already active")
            onIdle()
            return
        }
        let current = Operation(controller: controller, normalizationIDs: normalizationIDs, isRouteLive: isRouteLive, onSettle: onSettle, onIdle: onIdle)
        operation = current
        await runAttempt(current, retry: false)
    }

    /// `다시 시도` on a Retry prompt.
    func retry() {
        retryPrompt = nil
        guard let current = operation, case .awaitingRetry = current.controller.state, !current.isRetryQueued,
              !current.isEndingUnreachableWait else { return }
        current.isRetryQueued = true   // a second tap before the attempt starts is a no-op
        Task { await runAttempt(current, retry: true) }
    }

    /// `취소` on the sheet or on a Retry prompt: through the controller, which waits for the running attempt's own
    /// rollback / save processing (a confirmed save stays a success) before anything is released.
    func cancel() {
        retryPrompt = nil
        guard let current = operation, !current.controller.state.isTerminal else { return }
        if current.controller.state == .running {
            isCancellingPreparation = true
            current.controller.requestCancellation()   // the running attempt settles the outcome
        } else {
            Task {
                await current.controller.cancel()
                self.settle(current, .ineligible(.cancelled))
            }
        }
    }

    /// The owner's originating route left the path. Only the operation's own route identity decides: a running attempt
    /// is never cancelled (it settles and suppresses its late UI); a waiting one ends through the controller. Idempotent.
    func originatingRouteRemoved() {
        guard let current = operation, !current.isRouteLive() else { return }
        retryPrompt = nil
        if case .awaitingRetry = current.controller.state { endUnreachableWait(current) }
    }

    // MARK: - Private

    private func runAttempt(_ current: Operation, retry: Bool) async {
        current.isRetryQueued = false
        // A Retry queued just before its route was removed never starts: route removal never cancels a running attempt.
        if retry, current.isEndingUnreachableWait { return }
        current.attempt += 1
        let attempt = current.attempt
        preparation = current.needsSheet ? ImportPreparationProgress(normalizationIDs: current.normalizationIDs) : nil
        let events: (ImportAttemptEvent) -> Void = { [weak self, weak current] event in
            guard let self, let current, self.operation === current, current.attempt == attempt else { return }
            self.preparation?.apply(event)
        }
        let result = retry ? await current.controller.retry(events: events) : await current.controller.start(events: events)
        preparation = nil
        isCancellingPreparation = false
        settle(current, result)
    }

    private func endUnreachableWait(_ current: Operation) {
        guard !current.isEndingUnreachableWait else { return }
        current.isEndingUnreachableWait = true
        retryPrompt = nil
        Task {
            await current.controller.cancel()
            self.settle(current, .ineligible(.cancelled))
        }
    }

    private func settle(_ current: Operation, _ result: ImportRetryResult) {
        guard operation === current else { return }
        let live = current.isRouteLive()
        let settlement: ImportOperationSettlement
        switch current.controller.state {
        case .idle, .running:
            return
        case .awaitingRetry(let evidence):
            // No inaccessible Retry wait (D7b §4 clarification): a removed route ends it through the controller.
            guard live, !current.isEndingUnreachableWait else { endUnreachableWait(current); return }
            switch result {
            case .capacityRefused: retryPrompt = .storageShortage
            case .targetUnavailable: retryPrompt = .targetUnavailable
            default: retryPrompt = .forEvidence(evidence)
            }
            return
        case .succeeded(let commit): settlement = .succeeded(commit)
        case .uncertain(let outcome): settlement = .uncertain(outcome)
        case .retainedUnresolved(let outcome): settlement = .retainedUnresolved(outcome)
        case .ended(let reason): settlement = .ended(reason, result: result, isRetryAttempt: current.attempt > 1)
        }
        operation = nil
        retryPrompt = nil
        current.onIdle()
        current.onSettle(settlement, live)
    }
}

/// Which Project's Editor currently runs a Phase 6 import, so an Editor-route removal first lets that operation finish
/// its outcome processing and attempt cleanup, and only then schedules the gated Editor-exit pending-clip cleanup
/// (Editor decision 3, 2026-10-06). Waiting never holds the lifecycle gate.
@MainActor
final class ImportOperationActivity {
    /// One registration per import operation (an Editor reopened for the same Project registers separately).
    struct Token: Hashable { let projectID: UUID; let id = UUID() }

    private struct Registration {
        let presenter: ImportOperationPresenter
        let onRouteRemoved: () -> Void
    }
    private var operations: [UUID: [Token: Registration]] = [:]
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    init() {}

    /// `onRouteRemoved` covers the stage before the presenter owns the operation (picker / transfer / preflight).
    func begin(projectID: UUID, presenter: ImportOperationPresenter, onRouteRemoved: @escaping () -> Void = {}) -> Token {
        let token = Token(projectID: projectID)
        operations[projectID, default: [:]][token] = Registration(presenter: presenter, onRouteRemoved: onRouteRemoved)
        return token
    }

    /// Ends ONE operation; waiters resume only once no operation for that Project remains.
    func end(_ token: Token) {
        operations[token.projectID]?[token] = nil
        guard operations[token.projectID]?.isEmpty ?? true else { return }
        operations[token.projectID] = nil
        for waiter in waiters.removeValue(forKey: token.projectID) ?? [] { waiter.resume() }
    }

    func isActive(projectID: UUID) -> Bool { !(operations[projectID]?.isEmpty ?? true) }

    /// An Editor route for `projectID` left the path: each operation checks its own route identity; an unanswerable
    /// Retry wait ends, a running attempt continues.
    func routeRemoved(projectID: UUID) {
        for registration in operations[projectID]?.values.map({ $0 }) ?? [] {
            registration.onRouteRemoved()
            registration.presenter.originatingRouteRemoved()
        }
    }

    /// Returns once no import operation for `projectID` is active (immediately when none is).
    func waitUntilIdle(projectID: UUID) async {
        guard isActive(projectID: projectID) else { return }
        await withCheckedContinuation { waiters[projectID, default: []].append($0) }
    }
}
