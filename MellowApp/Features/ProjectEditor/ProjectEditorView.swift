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
                    model = ProjectEditorModel(project: project, repository: environment.projectRepository, thumbnails: environment.clipThumbnails)
                    #if DEBUG
                    MellowLog.app.info("Project editor loaded \(project.id.uuidString, privacy: .public) clips=\(project.clips.count, privacy: .public) total=\(ClipDurationText.string(project.totalDuration), privacy: .public)")
                    #endif
                } else {
                    unavailable = true
                }
            } catch {
                unavailable = true
            }
        }
    }
}

/// Phase 5 Project Editor (ADR-034): an immersive dark media workspace — a dominant Portrait Preview
/// canvas above a persistent bottom editing dock with the ordered clip timeline. Clips can be
/// selected and reordered (long press + drag, or the accessibility Move actions) with autosave. No
/// playback, no delete, no edit tools; the shell deliberately shows no dead controls for deferred features.
struct ProjectEditorView: View {
    @Bindable var model: ProjectEditorModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 8) {
            ProjectPreviewCanvas(
                orientation: model.project.orientation,
                selectedClip: model.selectedClip,
                selectedPosition: selectedPosition
            )
            EditorTimelineDock(model: model, showsStagedAddSlot: showsStagedAddSlot)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .padding(.top, 8)
        .background(EditorWorkspace.canvas.ignoresSafeArea())
        // One subtle haptic per reorder-mode activation (long press succeeded); nothing on drop.
        .sensoryFeedback(.impact(weight: .light), trigger: model.reorderActivationCount)
        // Recoverable autosave failure (the order was already rolled back); same alert style as
        // the Projects screen. The user simply reorders again.
        .alert(
            model.reorderMessage?.title ?? "",
            isPresented: Binding(
                get: { model.reorderMessage != nil },
                set: { if !$0 { model.reorderMessage = nil } }
            ),
            presenting: model.reorderMessage
        ) { _ in
            Button("확인", role: .cancel) { model.reorderMessage = nil }
        } message: { message in
            Text(message.message)
        }
        // Editor-only workspace appearance: the subtree and its navigation bar render dark whatever
        // the app appearance is; nothing global changes (Projects / Camera are untouched).
        .environment(\.colorScheme, .dark)
        .toolbarBackground(EditorWorkspace.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Thumbnail work lives in the model / service, never in body evaluation. `.task` cancels the
        // load when the screen leaves, so no generation outlives it.
        .task(id: displayScale) { await model.loadThumbnails(displayScale: displayScale) }
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
        // `.contain` keeps the preview / dock / timeline individually queryable under the container
        // identifier (a bare identifier would swallow them).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectEditor")
    }

    /// DEBUG staging of the Add Clip reference visual; `-uiTestProductionTimeline` reproduces the
    /// exact Release presentation (no slot) for tests and screenshots. Release is always false.
    private var showsStagedAddSlot: Bool {
        #if DEBUG
        return !ProcessInfo.processInfo.arguments.contains("-uiTestProductionTimeline")
        #else
        return false
        #endif
    }

    private var selectedPosition: Int? {
        guard let id = model.selectedClipID else { return nil }
        return model.orderedClips.firstIndex { $0.id == id }.map { $0 + 1 }
    }
}

/// Full flexible Preview canvas: owns every point between the navigation bar and the timeline dock
/// and is the same black as the workspace — no card, no visible boundary. Future Project media
/// aspect-fits (9:16) inside `mediaArea`; future Text / Sticker tools overlay the canvas through the
/// `ZStack` without taking layout space. STEP 8 shows only a faint glyph: no playback, no AVPlayer,
/// no static thumbnail preview, no engineering copy. The selected clip is described for accessibility.
struct ProjectPreviewCanvas: View {
    let orientation: ProjectOrientation
    let selectedClip: VlogClip?
    let selectedPosition: Int?

    private var mediaAspect: CGFloat {
        switch orientation {
        case .portrait9x16: return 9.0 / 16.0
        case .landscape16x9: return 16.0 / 9.0
        }
    }

    var body: some View {
        ZStack {
            EditorWorkspace.canvas
            // Media area: where the Project's 9:16 content will aspect-fit later. Invisible now.
            Color.clear
                .aspectRatio(mediaAspect, contentMode: .fit)
                .overlay {
                    Image(systemName: "film")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(Color(white: 0.28))
                }
            // Overlay layer (top-leading / trailing tool placement) is reserved here; nothing is
            // rendered until the owning Phase ships real controls — no dead buttons.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("projectEditorPreview")
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let selectedPosition else { return "Preview, no clip selected" }
        return "Preview, selected clip \(selectedPosition)"
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
