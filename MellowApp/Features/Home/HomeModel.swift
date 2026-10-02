import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class HomeModel {
    private(set) var projects: [VlogProject] = []
    private(set) var openedProject: VlogProject?
    private(set) var loadFailed = false
    var pendingDeletion: VlogProject?
    var failure: HomeFailure?

    private let repository: any ProjectRepository
    /// The shared Project lifecycle gate (ADR-039): deletion never interleaves with an Editor Add /
    /// Replace commit, composition, cleanup or startup recovery.
    private let lifecycle: ProjectLifecycleOperationGate
    let router: AppRouter

    init(repository: any ProjectRepository, router: AppRouter, lifecycle: ProjectLifecycleOperationGate) {
        self.repository = repository
        self.router = router
        self.lifecycle = lifecycle
    }

    func loadRecent() {
        do {
            projects = try repository.recentProjects()
            loadFailed = false
        } catch {
            logPersistenceFailure(error)
            loadFailed = true
        }
    }

    /// Canonical Camera `Projects` action (ADR-035/036): the dedicated `프로젝트` screen.
    func showProjects() {
        router.path = [.projectsEntry]
    }

    /// Transitional multi-project Recent browser. No longer reachable from the canonical Camera path;
    /// retained for historical Phase 2/3 regressions (DEBUG `-uiTestLegacyRecentProjects`) until the
    /// Post-V1 multi-project decision (ADR-033).
    func showRecent() {
        router.path = [.recent]
    }

    func createProject(orientation: ProjectOrientation) {
        guard router.path.isEmpty else { return }
        do {
            let project = try VlogProject(orientation: orientation)
            try repository.create(project)
            openedProject = project
            // A persisted selection leaves the chooser and prevents duplicate taps.
            router.path = [.camera(project.id)]
            loadRecent()
        } catch {
            logPersistenceFailure(error)
            failure = .creation
        }
    }

    func openProject(id: UUID) {
        do {
            guard let project = try repository.project(id: id) else {
                failure = .unavailable
                loadRecent()
                return
            }
            openedProject = project
            router.path = [.recent, .camera(project.id)]
        } catch {
            logPersistenceFailure(error)
            failure = .opening
        }
    }

    /// Deletes the pending Project (programmatic entry; the alert passes its captured value to
    /// `delete(_:)` because dismissal clears `pendingDeletion` before any Task body runs).
    func confirmDeletion() async {
        guard let project = pendingDeletion else { return }
        pendingDeletion = nil
        await delete(project)
    }

    /// Deletes `project`'s metadata inside the shared lifecycle gate (the media directory is left for
    /// startup orphan recovery, as before). Waits its turn behind an in-flight protected section.
    func delete(_ project: VlogProject) async {
        // The deletion may wait behind another gate holder; navigation can change meanwhile.
        let pathAtConfirmation = router.path
        do {
            try await lifecycle.withExclusiveAccess { try repository.deleteProject(id: project.id) }
            projects.removeAll { $0.id == project.id }
            if openedProject?.id == project.id {
                openedProject = nil
                // Leave the deleted Project as before, but never undo a later, unrelated navigation.
                if router.path == pathAtConfirmation || router.path.contains(where: { Self.route($0, refersTo: project.id) }) {
                    router.path = [.recent]
                }
            }
            loadRecent()
        } catch {
            logPersistenceFailure(error)
            failure = .deletion
        }
    }

    private static func route(_ route: AppRouter.Route, refersTo projectID: UUID) -> Bool {
        switch route {
        case .camera(let id), .projectEditor(let id): id == projectID
        case .recent, .projectsEntry: false
        }
    }

    private func logPersistenceFailure(_ error: Error) {
        let details = error as NSError
        MellowLog.app.error("Project persistence failed: domain=\(details.domain, privacy: .public), code=\(details.code)")
    }
}

enum HomeFailure: String, Identifiable {
    case creation, opening, unavailable, deletion
    var id: String { rawValue }

    var message: String {
        switch self {
        case .creation: "Your vlog couldn’t be saved. Please try again."
        case .opening: "This vlog couldn’t be opened. Please try again."
        case .unavailable: "This vlog is no longer available."
        case .deletion: "Your vlog couldn’t be deleted. Please try again."
        }
    }
}
