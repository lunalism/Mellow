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
                        acquisition: environment.editorClipAcquisition,
                        availability: environment.clipAvailability
                    )
                    #if DEBUG
                    MellowLog.app.info("Project editor loaded \(project.id.uuidString, privacy: .public) clips=\(project.clips.count, privacy: .public) total=\(ClipDurationText.string(project.totalDuration), privacy: .public)")
                    // Physical-review aid (ADR-040 fixture flow): the active Clip identities in logical
                    // order, so a tester can name the disposable Clip for `-uiTestRemoveActiveClipMedia=`.
                    MellowLog.app.info("Project editor active clips \(project.clips.map(\.id.uuidString).joined(separator: ","), privacy: .public)")
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
                selectedPosition: selectedPosition,
                isSelectedClipUnavailable: model.isSelectedClipUnavailable,
                canReplace: model.canReplaceSelectedClip,
                isReplacing: model.isReplacingClip,
                replace: replaceSelectedClip
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
        // Re-run whenever the active clip SET changes (Add / Delete / Undo / Redo / Replace): the
        // model re-derives availability, then requests only the thumbnails that are not ready. The key
        // is order-independent, so a reorder or a pure selection change never re-runs it (ADR-040 §6).
        .task(id: ThumbnailLoadKey(scale: displayScale, clipIDs: Set(model.committedClips.map(\.id)))) {
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

    private func replaceSelectedClip() {
        guard model.canReplaceSelectedClip else { return }
        Task {
            if await model.replaceSelectedClip() != nil {
                AccessibilityNotification.Announcement("클립을 교체했어요. 실행 취소할 수 있어요.").post()
            }
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

/// Identity of one thumbnail load: the display scale and the active clip set (order-independent).
private struct ThumbnailLoadKey: Hashable {
    let scale: CGFloat
    let clipIDs: Set<UUID>
}

/// Hosts the system Photos picker for the Editor's production selector (ADR-037 Add, ADR-040
/// Replace): videos only, no library read permission (the picker runs out of process). ONE host
/// serves both flows — the selector's current session sets the selection bound (Add: unlimited,
/// Replace: exactly 1), so two pickers can never compete and a cancel resolves only its own session.
/// Absent under test fakes. Its own selector instance, so the Projects screen's picker host below in
/// the stack never competes.
private struct EditorPhotosPickerHost: ViewModifier {
    let selector: PhotosVideoSelector?

    func body(content: Content) -> some View {
        if let selector {
            @Bindable var selector = selector
            content
                .photosPicker(
                    isPresented: $selector.isPresented,
                    selection: $selector.items,
                    maxSelectionCount: selector.maxSelectionCount,
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
///
/// STEP 13 (ADR-040): when the SELECTED Clip's media is structurally unavailable, the same canvas
/// hosts a centred neutral shell (`video.slash`, title, message, `클립 교체`) as an overlay layer —
/// no red card, no alert, no second Delete (the dock trash stays the one destructive control).
struct ProjectPreviewCanvas: View {
    let orientation: ProjectOrientation
    let selectedClip: VlogClip?
    let selectedPosition: Int?
    var isSelectedClipUnavailable = false
    var canReplace = false
    var isReplacing = false
    var replace: () -> Void = {}

    private var mediaAspect: CGFloat {
        switch orientation {
        case .portrait9x16: return 9.0 / 16.0
        case .landscape16x9: return 16.0 / 9.0
        }
    }

    var body: some View {
        ZStack {
            // The canvas itself stays ONE accessibility element with a stable identity whatever is
            // selected; the unavailable shell is a sibling layer with its own readable elements.
            ZStack {
                EditorWorkspace.canvas
                // Media area: where the Project's 9:16 content will aspect-fit later. Invisible now.
                Color.clear
                    .aspectRatio(mediaAspect, contentMode: .fit)
                    .overlay {
                        Image(systemName: "film")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(Color(white: 0.28))
                            .opacity(isSelectedClipUnavailable ? 0 : 1)
                    }
                // Overlay layer (top-leading / trailing tool placement) is reserved here; nothing is
                // rendered until the owning Phase ships real controls — no dead buttons.
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("projectEditorPreview")
            .accessibilityLabel(accessibilityText)
            if isSelectedClipUnavailable {
                UnavailableClipShell(canReplace: canReplace, isReplacing: isReplacing, replace: replace)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
    }

    private var accessibilityText: String {
        guard let selectedPosition else { return "Preview, no clip selected" }
        return "Preview, selected clip \(selectedPosition)" + (isSelectedClipUnavailable ? ", unavailable" : "")
    }
}

/// Centred neutral unavailable shell (DESIGN §19 STEP 13): glyph, exact V1 copy and the one Replace
/// action. Workspace-consistent (dark control surface, light foreground), no destructive colour, no
/// second Delete. The button keeps a 44 pt target and shows progress while the Replace transaction
/// runs; it is disabled (never hidden) while any other mutation is in flight.
private struct UnavailableClipShell: View {
    let canReplace: Bool
    let isReplacing: Bool
    let replace: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(EditorWorkspace.secondaryText)
                .accessibilityHidden(true)
            Text("클립을 사용할 수 없어요")
                .font(.headline)
                .foregroundStyle(EditorWorkspace.primaryText)
                .accessibilityIdentifier("unavailableClipTitle")
            Text("파일을 찾을 수 없어요.")
                .font(.subheadline)
                .foregroundStyle(EditorWorkspace.secondaryText)
                .accessibilityIdentifier("unavailableClipMessage")
            Button(action: replace) {
                ZStack {
                    Text("클립 교체")
                        .font(.body.weight(.medium))
                        .foregroundStyle(canReplace ? EditorWorkspace.primaryText : EditorWorkspace.secondaryText)
                        .opacity(isReplacing ? 0 : 1)
                    if isReplacing {
                        ProgressView().controlSize(.small).tint(EditorWorkspace.secondaryText)
                    }
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .background(EditorWorkspace.control, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canReplace)
            .padding(.top, 6)
            .accessibilityIdentifier("replaceSelectedClip")
            .accessibilityLabel("클립 교체")
            .accessibilityHint("사진 보관함에서 이 클립을 교체합니다.")
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unavailableClipShell")
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
