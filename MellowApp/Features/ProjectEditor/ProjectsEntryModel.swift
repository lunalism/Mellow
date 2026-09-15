import Foundation
import Observation
import OSLog

/// Presentation state for the Phase 5 Projects screen (ADR-034 semantics, ADR-035 destination,
/// ADR-036 two-action content).
///
/// A short decision surface: `새 프로젝트 시작` (always) and `기존 프로젝트 불러오기` (enabled only
/// while a saved Project exists). Saved-Project lookup policy stays in `ProjectCompositionCoordinator`;
/// this model only turns that answer into presentation state and delivers user intents to its owner.
///
/// STEP 5 is intent-only: the model never creates, deletes or replaces a Project and never touches
/// media. The confirmed new-project intent is handed to the owner, who (in a later slice) runs the
/// actual composition / Safe Atomic Replacement flow.
@Observable
@MainActor
final class ProjectsEntryModel {
    /// What the owner should do with a confirmed `새 프로젝트 시작`.
    enum NewProjectIntent: Equatable {
        /// No saved Project exists; nothing needs replacing.
        case fresh
        /// The user confirmed replacing the given saved Project.
        case replacingSaved(UUID)
    }

    /// The current V1 saved Project's ID, or nil. Refreshed by `load()`; never mutated by intents.
    /// The screen shows no Project metadata (ADR-036), so the ID alone is the whole state.
    private(set) var savedProjectID: UUID?
    /// True while the ADR-034 replacement confirmation is on screen.
    var isReplacementConfirmationPresented = false

    private let composition: ProjectCompositionCoordinator
    private let onContinueEditing: (UUID) -> Void
    private let onNewProject: (NewProjectIntent) -> Void

    init(
        composition: ProjectCompositionCoordinator,
        onContinueEditing: @escaping (UUID) -> Void,
        onNewProject: @escaping (NewProjectIntent) -> Void
    ) {
        self.composition = composition
        self.onContinueEditing = onContinueEditing
        self.onNewProject = onNewProject
    }

    var hasSavedProject: Bool { savedProjectID != nil }

    /// Resolves the saved Project through the coordinator's read-only lookup. A lookup failure is
    /// treated as "no saved Project" for presentation and logged; it never creates one.
    func load() {
        do {
            savedProjectID = try composition.lastSavedProject()?.id
        } catch {
            let details = error as NSError
            MellowLog.app.error("Projects entry lookup failed: domain=\(details.domain, privacy: .public), code=\(details.code)")
            savedProjectID = nil
        }
    }

    /// `기존 프로젝트 불러오기`: delivers the exact saved Project ID as the navigation identity.
    /// No-op without a saved Project (the control is disabled then).
    func continueEditing() {
        guard let savedProjectID else { return }
        onContinueEditing(savedProjectID)
    }

    /// `새 프로젝트 시작`: with a saved Project this first asks for replacement confirmation;
    /// without one the intent is delivered immediately.
    func requestNewProject() {
        if hasSavedProject {
            isReplacementConfirmationPresented = true
        } else {
            onNewProject(.fresh)
        }
    }

    /// `취소`: closes the confirmation and leaves the saved Project untouched.
    func cancelReplacement() {
        isReplacementConfirmationPresented = false
    }

    /// `새 프로젝트 만들기`: closes the confirmation and delivers the confirmed intent. Persistence
    /// is not modified here — replacement itself is the owner's later responsibility.
    func confirmReplacement() {
        isReplacementConfirmationPresented = false
        guard let savedProjectID else {
            onNewProject(.fresh)
            return
        }
        onNewProject(.replacingSaved(savedProjectID))
    }
}
