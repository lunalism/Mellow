import Foundation
import OSLog

/// Outcome counters of startup orphan recovery (STEP 12B). Tests / DEBUG diagnostics only.
struct ProjectStartupRecoveryReport: Equatable, Sendable {
    var workspacesRemoved = 0
    var workspaceFailures = 0
    var orphanProjectDirsRemoved = 0
    var orphanProjectDirFailures = 0
    var orphanMediaRemoved = 0
    var orphanMediaFailures = 0
    /// Canonical media files kept because a durable Clip (active or pending) still references them.
    var preservedReferenced = 0
    /// Entries kept because their shape / type / link status is not one Mellow owns.
    var noncanonicalPreserved = 0
    /// Projects whose scan was skipped because an Editor session was live for them.
    var skippedLiveProjects = 0

    static func + (lhs: Self, rhs: Self) -> Self {
        var sum = lhs
        sum.workspacesRemoved += rhs.workspacesRemoved
        sum.workspaceFailures += rhs.workspaceFailures
        sum.orphanProjectDirsRemoved += rhs.orphanProjectDirsRemoved
        sum.orphanProjectDirFailures += rhs.orphanProjectDirFailures
        sum.orphanMediaRemoved += rhs.orphanMediaRemoved
        sum.orphanMediaFailures += rhs.orphanMediaFailures
        sum.preservedReferenced += rhs.preservedReferenced
        sum.noncanonicalPreserved += rhs.noncanonicalPreserved
        sum.skippedLiveProjects += rhs.skippedLiveProjects
        return sum
    }
}

/// Startup-only filesystem recovery of what a dead process left behind (ADR-039 STEP 12B):
///
///   1. abandoned canonical `ProjectWorkspace/<op>/` directories (not live in this process),
///   2. canonical `Projects/<P>/` directories whose Project row no longer exists,
///   3. canonical `Projects/<P>/Media/<C>.mov` files no durable Clip of P references.
///
/// It runs only from app-startup maintenance, after STEP 12A has reconciled known pending Clips,
/// and only inside the shared lifecycle gate. It writes no metadata, never touches a Project with a
/// live Editor session, never follows symlinks, and preserves every object it cannot prove Mellow
/// owns — an unknown file, a future subdirectory, a differently spelled name. `CaptureStaging`,
/// `tmp`, Photos and the rest of the container are outside its enumeration by construction.
@MainActor
final class ProjectStartupRecoveryCoordinator {
    private let repository: any ProjectRepository
    private let store: any ProjectOrphanRecoveryStoring
    private let lifecycle: ProjectLifecycleOperationGate
    private let isEditorSessionLive: @MainActor (UUID) -> Bool
    #if DEBUG
    /// UI-test seam (`-uiTestRecoveryDelay=<ms>`): awaited inside the first orphan-recovery gate
    /// section, so tests can prove an Editor load waits while the Camera does not. Never Release.
    var debugHold: (@MainActor () async -> Void)?
    #endif

    init(
        repository: any ProjectRepository,
        store: any ProjectOrphanRecoveryStoring,
        lifecycle: ProjectLifecycleOperationGate,
        isEditorSessionLive: @escaping @MainActor (UUID) -> Bool
    ) {
        self.repository = repository
        self.store = store
        self.lifecycle = lifecycle
        self.isEditorSessionLive = isEditorSessionLive
    }

    // MARK: - Workspaces

    /// Removes every canonical workspace directory not owned by a live operation of this process.
    /// No age threshold: a workspace can only be live through the store's own registry.
    func sweepAbandonedWorkspaces() async -> ProjectStartupRecoveryReport {
        await lifecycle.withExclusiveAccess { await sweepWorkspacesExclusively() }
    }

    private func sweepWorkspacesExclusively() async -> ProjectStartupRecoveryReport {
        var report = ProjectStartupRecoveryReport()
        let entries: [ProjectRecoveryEntry]
        do {
            entries = try await store.enumerateWorkspaces()
        } catch {
            log(error: error, "Recovery workspace enumeration failed")
            return report
        }
        let candidates = entries.compactMap { entry -> UUID? in
            if case .canonical(let id) = entry { return id }
            return nil
        }
        MellowLog.app.info("Recovery workspace candidates=\(candidates.count, privacy: .public) noncanonical=\(entries.count - candidates.count, privacy: .public)")
        for entry in entries {
            switch entry {
            case .canonical(let id):
                do {
                    if try await store.removeAbandonedWorkspace(id: id) {
                        report.workspacesRemoved += 1
                        MellowLog.app.info("Recovery workspace removed op=\(Self.short(id), privacy: .public)")
                    } else {
                        report.noncanonicalPreserved += 1
                        MellowLog.app.info("Recovery workspace live op=\(Self.short(id), privacy: .public)")
                    }
                } catch {
                    report.workspaceFailures += 1
                    log(error: error, "Recovery workspace removal failed op=\(Self.short(id))")
                }
            case .noncanonical(_, let reason):
                report.noncanonicalPreserved += 1
                MellowLog.app.info("Recovery noncanonical preserved kind=workspace reason=\(reason, privacy: .public)")
            }
        }
        return report
    }

    // MARK: - Orphan Project directories and media

    /// Absent-Project directories first (whole directory), then the narrow media scan of each
    /// existing Project. Each Project is its own gate section so a queued Editor load / composition
    /// is never held behind unrelated work.
    func recoverOrphans() async -> ProjectStartupRecoveryReport {
        var report = ProjectStartupRecoveryReport()
        let entries: [ProjectRecoveryEntry]
        do {
            entries = try await lifecycle.withExclusiveAccess {
                #if DEBUG
                if let debugHold { await debugHold() }
                #endif
                return try await store.enumerateProjectDirectories()
            }
        } catch {
            log(error: error, "Recovery project enumeration failed")
            return report
        }
        MellowLog.app.info("Recovery started projectDirectories=\(entries.count, privacy: .public)")
        for entry in entries {
            switch entry {
            case .canonical(let projectID):
                report = report + (await lifecycle.withExclusiveAccess { await recoverProjectExclusively(projectID) })
            case .noncanonical(_, let reason):
                report.noncanonicalPreserved += 1
                MellowLog.app.info("Recovery noncanonical preserved kind=projectDir reason=\(reason, privacy: .public)")
            }
        }
        MellowLog.app.info("Recovery complete dirsRemoved=\(report.orphanProjectDirsRemoved, privacy: .public) mediaRemoved=\(report.orphanMediaRemoved, privacy: .public) referenced=\(report.preservedReferenced, privacy: .public) noncanonical=\(report.noncanonicalPreserved, privacy: .public) failures=\(report.orphanProjectDirFailures + report.orphanMediaFailures, privacy: .public) skippedLive=\(report.skippedLiveProjects, privacy: .public)")
        return report
    }

    /// Inside the gate. A live Editor session owns the Project: nothing is evaluated.
    private func recoverProjectExclusively(_ projectID: UUID) async -> ProjectStartupRecoveryReport {
        var report = ProjectStartupRecoveryReport()
        let label = Self.short(projectID)
        guard !isEditorSessionLive(projectID) else {
            report.skippedLiveProjects += 1
            MellowLog.app.info("Recovery live project skipped project=\(label, privacy: .public)")
            return report
        }

        // Absent row → the whole canonical directory is an orphan (re-read immediately before removal).
        let project: VlogProject?
        do { project = try repository.project(id: projectID) } catch {
            log(error: error, "Recovery project load failed project=\(label)")
            return report
        }
        guard project != nil else {
            MellowLog.app.info("Recovery orphan project candidate project=\(label, privacy: .public)")
            do {
                try await store.removeOrphanProjectDirectory(projectID: projectID)
                report.orphanProjectDirsRemoved += 1
                MellowLog.app.info("Recovery orphan project removed project=\(label, privacy: .public)")
            } catch {
                report.orphanProjectDirFailures += 1
                log(error: error, "Recovery orphan project removal failed project=\(label)")
            }
            return report
        }

        // Existing row → only canonical `<UUID>.mov` children of Media/ that no durable Clip
        // (active OR pending) references by ID or by path. Nothing else in the directory is touched.
        let entries: [ProjectRecoveryEntry]
        do { entries = try await store.enumerateCommittedMedia(projectID: projectID) } catch {
            log(error: error, "Recovery media enumeration failed project=\(label)")
            return report
        }
        for entry in entries {
            switch entry {
            case .noncanonical(_, let reason):
                report.noncanonicalPreserved += 1
                MellowLog.app.info("Recovery noncanonical preserved kind=media project=\(label, privacy: .public) reason=\(reason, privacy: .public)")
            case .canonical(let clipID):
                guard let path = try? ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID) else {
                    report.noncanonicalPreserved += 1
                    continue
                }
                // Revalidate against a fresh read right before the file goes.
                guard let current = try? repository.project(id: projectID), !isEditorSessionLive(projectID) else {
                    report.preservedReferenced += 1
                    continue
                }
                if Self.isReferenced(clipID: clipID, path: path, by: current) {
                    report.preservedReferenced += 1
                    continue
                }
                MellowLog.app.info("Recovery orphan media candidate project=\(label, privacy: .public) clip=\(Self.short(clipID), privacy: .public)")
                do {
                    try await store.removeCommittedMedia(path, projectID: projectID, clipID: clipID)
                    report.orphanMediaRemoved += 1
                    MellowLog.app.info("Recovery orphan media removed clip=\(Self.short(clipID), privacy: .public)")
                } catch {
                    report.orphanMediaFailures += 1
                    log(error: error, "Recovery orphan media removal failed clip=\(Self.short(clipID))")
                }
            }
        }
        if report.preservedReferenced > 0 {
            MellowLog.app.info("Recovery referenced media preserved project=\(label, privacy: .public) count=\(report.preservedReferenced, privacy: .public)")
        }
        return report
    }

    /// The durable reference set: every active AND pending Clip, by identity and by path. Both must
    /// miss for a file to be an orphan — a Clip whose persisted path differs from canonical still
    /// proves ownership by ID, and a path match protects even a Clip with a foreign ID.
    static func isReferenced(clipID: UUID, path: RelativeMediaPath, by project: VlogProject) -> Bool {
        project.durableClips.contains { $0.id == clipID || $0.mediaRelativePath == path }
    }

    private static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }

    private func log(error: Error, _ message: String) {
        let details = error as NSError
        MellowLog.app.error("\(message, privacy: .public): domain=\(details.domain, privacy: .public), code=\(details.code)")
    }
}
