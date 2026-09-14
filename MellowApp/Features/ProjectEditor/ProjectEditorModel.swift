import Foundation
import Observation

/// Presentation state for the Phase 5 Project Editor shell (ADR-034).
///
/// STEP 4 is READ-ONLY: it holds one already-loaded Project, exposes its ordered clips, total
/// duration and the selected clip. There is no reorder, delete, undo, autosave, thumbnail
/// generation or playback — those belong to later slices and are intentionally absent so this model
/// can be extended without pre-implementing future phases.
@Observable
@MainActor
final class ProjectEditorModel {
    let project: VlogProject
    private(set) var selectedClipID: UUID?

    init(project: VlogProject) {
        self.project = project
        // Default selection: the first clip when the project has clips, otherwise none.
        self.selectedClipID = project.clips.first?.id
    }

    /// Clips in committed logical order (`VlogProject` already keeps `clips` sorted by `sortOrder`).
    var orderedClips: [VlogClip] { project.clips }

    var totalDuration: MediaTime { project.totalDuration }

    var selectedClip: VlogClip? {
        guard let selectedClipID else { return nil }
        return project.clips.first { $0.id == selectedClipID }
    }

    /// Selects a clip by identity. Ignores ids that are not part of this project; never mutates the
    /// persisted project.
    func select(_ clipID: UUID) {
        guard project.clips.contains(where: { $0.id == clipID }) else { return }
        selectedClipID = clipID
    }
}

/// Compact, locale-independent duration label for the editor shell (e.g. "2.0s").
enum ClipDurationText {
    static func string(_ time: MediaTime) -> String {
        let seconds = time.timescale > 0 ? Double(time.value) / Double(time.timescale) : 0
        return String(format: "%.1fs", seconds)
    }
}
