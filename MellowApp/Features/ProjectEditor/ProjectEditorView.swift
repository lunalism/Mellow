import SwiftUI

/// Loads the requested Project once and presents the editor, or a minimal recoverable unavailable
/// state if it no longer exists. Mirrors `CameraDestination`'s load-once pattern so the model is
/// never rebuilt during SwiftUI body evaluation.
///
/// The load waits its turn in the shared lifecycle gate (ADR-039): a pending-Clip cleanup pass for
/// this Project that is still removing files or finalizing rows finishes first, so the Editor never
/// starts from an intermediate snapshot that a later autosave would write back. The route is already
/// on the stack while this waits, so no NEW pass can start for the Project meanwhile.
struct ProjectEditorDestination: View {
    let projectID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var model: ProjectEditorModel?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let model {
                ProjectEditorView(model: model, photosSelector: environment.editorPhotosSelector)
            } else if unavailable {
                ProjectEditorUnavailableView()
            } else {
                ProgressView().accessibilityLabel("Loading project").accessibilityIdentifier("projectEditorLoading")
            }
        }
        .task(id: projectID) {
            guard model == nil, !unavailable else { return }
            do {
                let loaded = try await environment.projectLifecycle.withExclusiveAccess {
                    try environment.projectRepository.project(id: projectID)
                }
                guard !Task.isCancelled else { return }
                if let project = loaded {
                    model = ProjectEditorModel(
                        project: project,
                        repository: environment.projectRepository,
                        thumbnails: environment.clipThumbnails,
                        acquisition: environment.editorClipAcquisition
                    )
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
    /// The production Add Clips boundary the view hosts (`.photosPicker`); nil under a test fake.
    var photosSelector: PhotosVideoSelector? = nil
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 8) {
            ProjectPreviewCanvas(
                orientation: model.project.orientation,
                selectedClip: model.selectedClip,
                selectedPosition: selectedPosition
            )
            EditorTimelineDock(model: model, deleteSelected: deleteSelectedClip, addClips: addClips)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        // Session Undo / Redo (ADR-038): always present top-trailing, enabled by history
        // availability. The history lives in the model for this Editor session only.
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditorHistoryButton(symbol: "arrow.uturn.backward", label: "실행 취소", identifier: "editorUndo",
                                    hint: model.undoTarget.map { "\($0.description) 실행 취소" }, isEnabled: model.canUndo, action: undo)
                EditorHistoryButton(symbol: "arrow.uturn.forward", label: "다시 실행", identifier: "editorRedo",
                                    hint: model.redoTarget.map { "\($0.description) 다시 실행" }, isEnabled: model.canRedo, action: redo)
            }
        }
        .padding(.top, 8)
        .background(EditorWorkspace.canvas.ignoresSafeArea())
        // One subtle haptic per reorder-mode activation (long press succeeded); nothing on drop.
        .sensoryFeedback(.impact(weight: .light), trigger: model.reorderActivationCount)
        // Recoverable autosave failure (the state was already rolled back); same alert style as
        // the Projects screen. The user simply tries again.
        .alert(
            model.editorMessage?.title ?? "",
            isPresented: Binding(
                get: { model.editorMessage != nil },
                set: { if !$0 { model.editorMessage = nil } }
            ),
            presenting: model.editorMessage
        ) { _ in
            Button("확인", role: .cancel) { model.editorMessage = nil }
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
        // Re-run whenever the active clip set changes (Add / Delete / Undo / Redo): only clips that
        // are not ready are requested, so this is a no-op for a reorder or a pure selection change.
        .task(id: ThumbnailLoadKey(scale: displayScale, clipIDs: model.committedClips.map(\.id))) {
            await model.loadThumbnails(displayScale: displayScale)
        }
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(EditorPhotosPickerHost(selector: photosSelector))
        // `.contain` keeps the preview / dock / timeline individually queryable under the container
        // identifier (a bare identifier would swallow them).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectEditor")
    }

    private var selectedPosition: Int? {
        guard let id = model.selectedClipID else { return nil }
        return model.orderedClips.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    private func addClips() {
        guard model.canAddClips else { return }
        Task {
            let added = await model.addClips()
            if added > 0 { AccessibilityNotification.Announcement("클립 \(added)개를 추가했어요.").post() }
        }
    }

    private func deleteSelectedClip() {
        guard model.deleteSelectedClip() else { return }
        AccessibilityNotification.Announcement("클립을 삭제했어요. 실행 취소할 수 있어요.").post()
    }

    private func undo() {
        let kind = model.undoTarget
        guard model.undo() else { return }
        AccessibilityNotification.Announcement("\(kind?.description ?? "편집") 실행 취소했어요.").post()
    }

    private func redo() {
        let kind = model.redoTarget
        guard model.redo() else { return }
        AccessibilityNotification.Announcement("\(kind?.description ?? "편집") 다시 실행했어요.").post()
    }
}

/// Identity of one thumbnail load: the display scale and the active clip set.
private struct ThumbnailLoadKey: Hashable {
    let scale: CGFloat
    let clipIDs: [UUID]
}

/// Hosts the system Photos picker for the Editor's production selector (ADR-037): videos only, no
/// library read permission (the picker runs out of process). Absent under test fakes. Its own
/// selector instance, so the Projects screen's picker host below in the stack never competes.
private struct EditorPhotosPickerHost: ViewModifier {
    let selector: PhotosVideoSelector?

    func body(content: Content) -> some View {
        if let selector {
            @Bindable var selector = selector
            content
                .photosPicker(
                    isPresented: $selector.isPresented,
                    selection: $selector.items,
                    matching: .videos,
                    preferredItemEncoding: .current
                )
                .onChange(of: selector.isPresented) { _, presented in
                    if !presented { selector.pickerDismissed() }
                }
        } else {
            content
        }
    }
}

/// Navigation-bar Undo / Redo control: a plain system bar button (symbol only), structurally
/// always present. iOS 26 lays SwiftUI toolbar items out as 36 pt glyph frames inside the 44 pt
/// glass group with the bar's standard touch extension (the accessibility hit-region audit is the
/// authority). Disabled state stays legible (system disabled tint on the dark bar) and is exposed
/// to accessibility together with a hint naming the edit it targets.
private struct EditorHistoryButton: View {
    let symbol: String
    let label: String
    let identifier: String
    let hint: String?
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .disabled(!isEnabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
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
