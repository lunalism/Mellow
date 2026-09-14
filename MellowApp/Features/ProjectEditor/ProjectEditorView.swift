import SwiftUI

/// Loads the requested Project once and presents the editor, or a minimal recoverable unavailable
/// state if it no longer exists. Mirrors `CameraDestination`'s load-once pattern so the model is
/// never rebuilt during SwiftUI body evaluation.
struct ProjectEditorDestination: View {
    let projectID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var model: ProjectEditorModel?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let model {
                ProjectEditorView(model: model)
            } else if unavailable {
                ProjectEditorUnavailableView()
            } else {
                ProgressView().accessibilityLabel("Loading project")
            }
        }
        .task(id: projectID) {
            guard model == nil, !unavailable else { return }
            do {
                if let project = try environment.projectRepository.project(id: projectID) {
                    model = ProjectEditorModel(project: project)
                } else {
                    unavailable = true
                }
            } catch {
                unavailable = true
            }
        }
    }
}

/// Phase 5 Project Editor shell (ADR-034): a large Preview surface, an ordered clip strip and a
/// quiet project summary. Placeholders only — no playback, no reorder/delete, no edit tools. The
/// shell deliberately shows no dead controls for deferred features.
struct ProjectEditorView: View {
    @Bindable var model: ProjectEditorModel

    var body: some View {
        VStack(spacing: 16) {
            ProjectPreviewShell(
                orientation: model.project.orientation,
                selectedClip: model.selectedClip,
                selectedPosition: selectedPosition
            )
            ClipThumbnailStrip(
                clips: model.orderedClips,
                selectedClipID: model.selectedClipID,
                select: model.select
            )
            ProjectSummary(totalDuration: model.totalDuration)
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
        // `.contain` keeps the preview / strip / summary individually queryable under the container
        // identifier (a bare identifier would swallow them).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectEditor")
    }

    private var selectedPosition: Int? {
        guard let id = model.selectedClipID else { return nil }
        return model.orderedClips.firstIndex { $0.id == id }.map { $0 + 1 }
    }
}

/// Structural preview surface only. Shows the selected clip's identity as a placeholder; it never
/// renders raw media and hosts no AVPlayer or playback control (real effective-result playback is
/// Phase 8).
struct ProjectPreviewShell: View {
    let orientation: ProjectOrientation
    let selectedClip: VlogClip?
    let selectedPosition: Int?

    private var aspect: CGFloat {
        switch orientation {
        case .portrait9x16: return 9.0 / 16.0
        case .landscape16x9: return 16.0 / 9.0
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxHeight: 340)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "film").font(.largeTitle).foregroundStyle(.primary)
                    Text(placeholderText).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("projectEditorPreview")
            .accessibilityLabel(accessibilityText)
    }

    private var placeholderText: String {
        guard let selectedPosition else { return "No clip selected" }
        return "Clip \(selectedPosition) preview"
    }
    private var accessibilityText: String {
        guard let selectedPosition else { return "Preview, no clip selected" }
        return "Preview of clip \(selectedPosition)"
    }
}

/// Quiet supporting information; must not compete with the preview (ADR-034).
struct ProjectSummary: View {
    let totalDuration: MediaTime

    var body: some View {
        Text("Total \(ClipDurationText.string(totalDuration))")
            .font(.footnote).monospacedDigit().foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("projectTotalDuration")
            .accessibilityLabel("Total duration \(ClipDurationText.string(totalDuration))")
    }
}

/// Minimal recoverable state when the requested Project no longer exists. Never invents a
/// replacement Project.
struct ProjectEditorUnavailableView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Project unavailable").font(.headline)
            Text("This project is no longer available.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityIdentifier("projectEditorUnavailable")
    }
}
