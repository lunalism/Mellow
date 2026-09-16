import Foundation
import OSLog

/// A reader of Project-owned committed media that physical cleanup must not pull the file from under
/// (ADR-021 active consumer). `ClipThumbnailService` is the only production reader today; playback /
/// export consumers added later must conform and be composed into the coordinator's gate the same
/// way — cleanup never assumes "no consumer" for a reader it was not told about.
protocol ProjectMediaConsumerGating: Sendable {
    /// `true` once nothing is reading any of `paths`; `false` if still busy after `timeout`.
    func awaitIdle(for paths: Set<RelativeMediaPath>, timeout: Duration) async -> Bool
}

/// Tunables of one reconciliation pass. Bounded consumer waiting is policy, not a magic number.
struct ProjectMediaCleanupPolicy: Sendable {
    /// How long one pending Clip may wait for its media readers to go idle before the pass defers
    /// it (file kept, row kept pending, retried at the next boundary).
    var consumerWaitTimeout: Duration = .seconds(3)

    static let `default` = ProjectMediaCleanupPolicy()
}

/// Why a pending Clip was left exactly as it was by a pass. Every reason is retryable: nothing here
/// is user-facing, and the next Editor exit / app launch simply tries again.
enum ProjectCleanupDeferral: Equatable, Sendable {
    /// The persisted path is not the canonical `Projects/<projectID>/Media/<clipID>.mov` — ownership
    /// of the file cannot be proven, so neither file nor metadata is touched.
    case nonCanonicalPath
    /// A media reader was still using the file past the bounded wait.
    case consumerBusy
    /// The store could not remove the file (or it still exists afterwards).
    case removalFailed
    /// File is gone but the metadata finalize did not land; the pending row survives for retry.
    case finalizeFailed
}

/// Outcome of one Project's pass, for logs, diagnostics and tests. Never shown to the user.
struct ProjectCleanupReport: Equatable, Sendable {
    let projectID: UUID
    /// The pass was skipped entirely: a live Editor session owns this Project (ADR-039 §1).
    var skippedForLiveEditor = false
    /// Pending Clips found at the start of the pass.
    var pendingCount = 0
    /// Clips whose file was actually removed by this pass.
    var removedFiles: [UUID] = []
    /// Clips whose file was already absent at the boundary (crash recovery: file step complete).
    var alreadyAbsent: [UUID] = []
    /// Clips whose pending metadata was finalized (removed) by this pass.
    var finalized: [UUID] = []
    /// Clips left pending, with the reason.
    var deferred: [UUID: ProjectCleanupDeferral] = [:]

    init(projectID: UUID) { self.projectID = projectID }
}

/// Deferred physical cleanup of known pending Clips (ADR-039, Phase 5 STEP 12A).
///
/// Ownership: cross-resource lifecycle orchestration only. The repository owns metadata, the media
/// store owns the filesystem, the Editor owns its session history, the router owns navigation. This
/// coordinator evaluates `Project.deletedClips` at exactly two boundaries — an Editor route for the
/// Project was removed, or the app started — and for each pending Clip runs the file-first pipeline:
///
///   still pending → canonical owned path → readers idle → remove file → verify absent → finalize row
///
/// Never the other order: a pending row that outlives a crash is discoverable; a deleted row over a
/// surviving file is an orphan. Every step is per Clip (one failure never rolls back another Clip's
/// success), idempotent (rerunning after any partial outcome converges) and silent (log only).
///
/// Absolute rules: nothing of a Project with a live Editor session is touched (in-session eligibility
/// changes wait for the boundary); an ACTIVE Clip is never finalized, whatever its file's state (that
/// is unavailable-media handling, a later slice); and this slice does not scan directories — a file
/// without a row, a Project directory without a Project, an abandoned workspace are STEP 12B.
@MainActor
final class ProjectMediaCleanupCoordinator {
    private let repository: any ProjectRepository
    private let mediaStore: any ProjectMediaCleanupStoring
    private let consumers: any ProjectMediaConsumerGating
    private let lifecycle: ProjectLifecycleOperationGate
    private let isEditorSessionLive: @MainActor (UUID) -> Bool
    private let policy: ProjectMediaCleanupPolicy
    /// Passes scheduled by a trigger and not yet finished (each removes itself on completion).
    private var scheduled: [UUID: Task<Void, Never>] = [:]

    #if DEBUG
    /// Test / UI-test seam: awaited inside the critical section right before the first Clip's
    /// consumer wait, so a paused pass can be observed (Editor open must wait for it). Never Release.
    var debugHold: (@MainActor () async -> Void)?
    /// Observer of every finished pass (diagnostics overlay in UI tests).
    var onReport: (@MainActor (ProjectCleanupReport) -> Void)?
    #endif

    init(
        repository: any ProjectRepository,
        mediaStore: any ProjectMediaCleanupStoring,
        consumers: any ProjectMediaConsumerGating,
        lifecycle: ProjectLifecycleOperationGate,
        isEditorSessionLive: @escaping @MainActor (UUID) -> Bool,
        policy: ProjectMediaCleanupPolicy = .default
    ) {
        self.repository = repository
        self.mediaStore = mediaStore
        self.consumers = consumers
        self.lifecycle = lifecycle
        self.isEditorSessionLive = isEditorSessionLive
        self.policy = policy
    }

    // MARK: - Triggers

    /// Editor-exit trigger: fire-and-forget so Back navigation never waits on disk IO.
    func scheduleReconcile(projectID: UUID) {
        schedule { await $0.reconcile(projectID: projectID) }
    }

    /// Startup trigger: every durable Project, after persistence is available. Not awaited by the
    /// Camera; Project loads / composition serialize behind it through the lifecycle gate.
    func scheduleReconcileAll() {
        schedule { await $0.reconcileAll() }
    }

    private func schedule<Result>(_ pass: @escaping @MainActor (ProjectMediaCleanupCoordinator) async -> Result) {
        let token = UUID()
        scheduled[token] = Task { [weak self] in
            if let self { _ = await pass(self) }
            self?.scheduled[token] = nil
        }
    }

    /// Awaits every pass scheduled so far (tests only; production never blocks on this).
    func drainScheduledForTesting() async {
        for task in Array(scheduled.values) { await task.value }
    }

    // MARK: - Reconciliation

    /// One serialized pass over one Project's pending Clips. Returns the report; never throws.
    func reconcile(projectID: UUID) async -> ProjectCleanupReport {
        let report = await lifecycle.withExclusiveAccess { await reconcileExclusively(projectID: projectID) }
        #if DEBUG
        onReport?(report)
        #endif
        return report
    }

    /// Every durable Project, one serialized pass each. `recentProjects()` is the repository's
    /// complete enumeration (no predicate, no limit; recency is only its order), so no separate query
    /// is needed. Editor history never survives a launch, so at startup a Project is history-free —
    /// but a route already restored to the Editor still counts as a live session and is skipped.
    func reconcileAll() async -> [ProjectCleanupReport] {
        let projectIDs: [UUID] = await lifecycle.withExclusiveAccess {
            do {
                return try repository.recentProjects().map(\.id)
            } catch {
                log(error: error, "Cleanup enumeration failed")
                return []
            }
        }
        MellowLog.app.info("Cleanup startup reconciliation projects=\(projectIDs.count, privacy: .public)")
        var reports: [ProjectCleanupReport] = []
        for projectID in projectIDs {
            reports.append(await reconcile(projectID: projectID))
        }
        return reports
    }

    /// Runs INSIDE the lifecycle gate: no composition, replacement or Editor load can interleave.
    private func reconcileExclusively(projectID: UUID) async -> ProjectCleanupReport {
        var report = ProjectCleanupReport(projectID: projectID)
        let projectLabel = String(projectID.uuidString.prefix(8))

        // 1. A live Editor session owns the Project: nothing is evaluated, nothing is touched.
        guard !isEditorSessionLive(projectID) else {
            report.skippedForLiveEditor = true
            MellowLog.app.info("Cleanup skipped project=\(projectLabel, privacy: .public) reason=liveEditorSession")
            return report
        }

        // 2. Durable pending set only. A missing Project has nothing pending (replacement removed it).
        let project: VlogProject
        do {
            guard let loaded = try repository.project(id: projectID) else { return report }
            project = loaded
        } catch {
            log(error: error, "Cleanup load failed project=\(projectLabel)")
            return report
        }
        report.pendingCount = project.deletedClips.count
        guard !project.deletedClips.isEmpty else { return report }
        MellowLog.app.info("Cleanup started project=\(projectLabel, privacy: .public) pending=\(project.deletedClips.count, privacy: .public)")

        #if DEBUG
        if let debugHold { await debugHold() }
        #endif

        // 3. Per Clip, independently: one failure never stops or reverts the others.
        for clip in project.deletedClips {
            let clipLabel = String(clip.id.uuidString.prefix(8))

            // 3a. Ownership must be provable: exactly the canonical committed path for THIS Clip.
            guard let canonical = try? ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clip.id),
                  clip.mediaRelativePath == canonical else {
                report.deferred[clip.id] = .nonCanonicalPath
                MellowLog.app.error("Cleanup preserved clip=\(clipLabel, privacy: .public) reason=nonCanonicalPath")
                continue
            }

            // 3b. Bounded consumer wait; a busy reader defers this Clip to a later boundary.
            guard await consumers.awaitIdle(for: [canonical], timeout: policy.consumerWaitTimeout) else {
                report.deferred[clip.id] = .consumerBusy
                MellowLog.app.info("Cleanup deferred clip=\(clipLabel, privacy: .public) reason=consumerBusy")
                continue
            }

            // 3c. File first. Already absent counts as done (crash between file removal and finalize).
            let existed = await mediaStore.fileExists(canonical)
            do {
                try await mediaStore.removeCommittedMedia(canonical, projectID: projectID, clipID: clip.id)
            } catch {
                report.deferred[clip.id] = .removalFailed
                log(error: error, "Cleanup file removal failed clip=\(clipLabel)")
                continue
            }
            // 3d. Verified absence is the precondition for touching metadata, whatever the store said.
            guard await !mediaStore.fileExists(canonical) else {
                report.deferred[clip.id] = .removalFailed
                MellowLog.app.error("Cleanup file still present clip=\(clipLabel, privacy: .public)")
                continue
            }
            if existed {
                report.removedFiles.append(clip.id)
                MellowLog.app.info("Cleanup file removed clip=\(clipLabel, privacy: .public)")
            } else {
                report.alreadyAbsent.append(clip.id)
                MellowLog.app.info("Cleanup file already absent clip=\(clipLabel, privacy: .public)")
            }

            // 3e. Metadata last. Re-read so the finalize targets the current durable state.
            switch finalize(projectID: projectID, clipID: clip.id) {
            case .finalized:
                report.finalized.append(clip.id)
                MellowLog.app.info("Cleanup metadata finalized clip=\(clipLabel, privacy: .public)")
            case .alreadyFinalized:
                report.finalized.append(clip.id)
                MellowLog.app.info("Cleanup metadata already finalized clip=\(clipLabel, privacy: .public)")
            case .failed(let error):
                report.deferred[clip.id] = .finalizeFailed
                log(error: error, "Cleanup metadata finalize failed clip=\(clipLabel)")
            }
        }
        MellowLog.app.info("Cleanup complete project=\(projectLabel, privacy: .public) finalized=\(report.finalized.count, privacy: .public) removed=\(report.removedFiles.count, privacy: .public) deferred=\(report.deferred.count, privacy: .public)")
        return report
    }

    private enum FinalizeOutcome { case finalized, alreadyFinalized, failed(Error) }

    /// Finalizes only a Clip that is STILL pending in the repository right now. An active Clip is
    /// never finalized (that would be data loss, not cleanup); a row that is already gone is success.
    private func finalize(projectID: UUID, clipID: UUID) -> FinalizeOutcome {
        do {
            guard let current = try repository.project(id: projectID) else { return .alreadyFinalized }
            if current.clips.contains(where: { $0.id == clipID }) {
                return .failed(ProjectRepositoryError.clipNotPendingDeletion)
            }
            guard current.deletedClips.contains(where: { $0.id == clipID }) else { return .alreadyFinalized }
            try repository.finalizeDeletedClip(projectID: projectID, clipID: clipID)
            return .finalized
        } catch {
            return .failed(error)
        }
    }

    private func log(error: Error, _ message: String) {
        let details = error as NSError
        MellowLog.app.error("\(message, privacy: .public): domain=\(details.domain, privacy: .public), code=\(details.code)")
    }
}
