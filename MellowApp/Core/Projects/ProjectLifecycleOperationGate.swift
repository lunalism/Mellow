import Foundation

/// The one async critical section for cross-resource Project lifecycle mutations (ADR-039):
/// pending-Clip physical cleanup, Project composition / Safe Atomic Replacement and the Editor's
/// Project load all enter through `withExclusiveAccess`, so cleanup can never interleave with a
/// composition that touches the same Project files / metadata, and a new Editor never reads a
/// half-reconciled Project (file gone, row still pending) that a later autosave could resurrect.
///
/// Main-Actor bound on purpose: every participant (repository, coordinators, destination load) is
/// Main-Actor isolated, so acquire / release are plain synchronous state changes with no hop and no
/// check-then-act window. The lock is HELD ACROSS the operation's suspension points; waiters queue in
/// FIFO order and receive the lock by direct hand-off. It is not a Boolean flag and there is no
/// polling. Camera capture never takes this gate (it has no Project).
@MainActor
final class ProjectLifecycleOperationGate {
    private(set) var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Number of operations queued behind the current holder (diagnostics / tests only).
    var waitingCount: Int { waiters.count }

    init() {}

    func withExclusiveAccess<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        // A cancelled waiter still receives the lock in its turn and releases it normally; the
        // operation itself decides what cancellation means.
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            // Hand-off: the lock stays held and passes straight to the next waiter (FIFO).
            waiters.removeFirst().resume()
        }
    }
}
