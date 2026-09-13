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
    let router: AppRouter

    init(repository: any ProjectRepository, router: AppRouter) {
        self.repository = repository
        self.router = router
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

    func confirmDeletion() {
        guard let project = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            try repository.deleteProject(id: project.id)
            projects.removeAll { $0.id == project.id }
            if openedProject?.id == project.id {
                openedProject = nil
                router.path = [.recent]
            }
            loadRecent()
        } catch {
            logPersistenceFailure(error)
            failure = .deletion
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
