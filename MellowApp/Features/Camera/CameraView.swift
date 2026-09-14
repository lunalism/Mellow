import SwiftUI

/// V1 capture context. The root Camera is a new Portrait capture surface that owns no persisted
/// project yet; project creation for the first recorded clip belongs to the recording phase.
enum CameraCaptureContext {
    case newCapture
    case project(VlogProject)

    var orientation: ProjectOrientation {
        switch self {
        case .newCapture: return .portrait9x16
        case .project(let project): return project.orientation
        }
    }
    var clipCount: Int {
        switch self {
        case .newCapture: return 0
        case .project(let project): return project.clips.count
        }
    }
    /// The root capture surface is the application root after onboarding and shows no Back.
    var isRoot: Bool {
        if case .newCapture = self { return true }
        return false
    }
    /// V1 exposes Portrait capture only; historical Landscape projects are never converted.
    var isSupportedInV1: Bool { orientation == .portrait9x16 }
}

/// Creates one feature model per navigation destination, never during body reevaluation.
struct CameraDestination: View {
    let context: CameraCaptureContext
    var showProjects: (() -> Void)?
    @Environment(AppEnvironment.self) private var environment
    @State private var model: CameraModel?
    var body: some View {
        Group {
            if !context.isSupportedInV1 {
                UnsupportedCaptureView()
            } else if let model {
                CameraView(context: context, model: model, showProjects: showProjects)
            } else {
                Color.black.ignoresSafeArea()
            }
        }.onAppear {
            guard context.isSupportedInV1, model == nil else { return }
            model = environment.makeCameraModel(orientation: context.orientation)
        }
    }
}

/// Historical Landscape projects stay untouched: capture is refused rather than silently
/// reinterpreted as Portrait. Landscape capture restoration is a post-V1 product decision.
struct UnsupportedCaptureView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Landscape isn’t available yet").font(.headline).multilineTextAlignment(.center)
            Text("This vlog was made in landscape. Mellow currently records in portrait only.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MellowDesignSystem.brandBackground.ignoresSafeArea())
        // A bare stack is not a queryable element; make the refusal an addressable container.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unsupportedCapture")
    }
}

struct CameraView: View {
    let context: CameraCaptureContext
    let showProjects: (() -> Void)?
    @State private var model: CameraModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @State private var pinchBase: Double?
    @GestureState private var pinching = false

    init(context: CameraCaptureContext, model: CameraModel, showProjects: (() -> Void)? = nil) {
        self.context = context
        self.showProjects = showProjects
        _model = State(initialValue: model)
    }

    var body: some View {
        surface
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .modifier(CameraChrome(isRoot: context.isRoot))
            .overlay(alignment: .topTrailing) { projectsAccess }
            .overlay(alignment: .topLeading) { microphoneAccess }
            .overlay(alignment: .bottom) { transientCaption }
            .overlay { recordingFailureOverlay }
            .tint(.white).foregroundStyle(.white)
            .onAppear { model.enter(active: scenePhase == .active) }
            .onDisappear { model.leave() }
            .onChange(of: scenePhase) { _, value in model.setActive(value == .active) }
            .onChange(of: pinching) { _, value in if !value { pinchBase = nil } }
    }

    @ViewBuilder private var surface: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 24) {
                            preview
                                .frame(height: geometry.size.width * (model.isPortraitProject ? 16.0 / 9.0 : 9.0 / 16.0))
                                .clipped()
                            statusOverlay
                            durationSelector
                            controls
                        }
                        .padding(16)
                    }
                    .background(Color.black)
                }
            } else {
                ZStack {
                    // Edge-to-edge live preview; controls overlay it directly. Portrait 9:16 stays
                    // the project/output policy but is not drawn as a frame on the surface.
                    preview
                    statusOverlay
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    VStack(spacing: 8) {
                        Spacer()
                        durationSelector
                        overlayControlsPortrait
                            .padding(.bottom, 18)
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    /// Quiet secondary access; the removed format chooser previously owned this entry point.
    @ViewBuilder private var projectsAccess: some View {
        if context.isRoot, let showProjects {
            CameraProjectsButton(open: showProjects)
                .disabled(model.controlsLocked)
                .opacity(model.controlsLocked ? 0.35 : 1)
                .padding(.top, 9)
                .padding(.trailing, 14)
        }
    }

    /// `mic.slash` appears only while audio is unavailable; it never gates video recording.
    @ViewBuilder private var microphoneAccess: some View {
        if model.isMicrophoneMuted {
            CameraMicrophoneControl(authorization: model.microphoneAuthorization, enabled: !model.controlsLocked) {
                Task {
                    switch await model.microphoneTapped() {
                    case .openSettings:
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    case .showRestricted:
                        model.recording.show(.microphoneRestricted)
                    case .none:
                        break
                    }
                }
            }
            .padding(.top, 9)
            .padding(.leading, 14)
        }
    }

    /// Brief non-modal captions (too short, storage, microphone restricted) above the controls.
    @ViewBuilder private var transientCaption: some View {
        if let notice = model.recording.notice {
            Text(notice.text)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.6)).clipShape(Capsule())
                .foregroundStyle(.white)
                .padding(.bottom, 186)
                .transition(.opacity)
                .accessibilityIdentifier("recordingNotice")
        }
    }

    private var durationSelector: some View {
        CameraDurationSelector(selected: $model.selectedDuration)
            .disabled(model.controlsLocked)
            .opacity(model.controlsLocked ? 0.35 : 1)
    }
    private var flip: some View {
        CameraFlipButton(enabled: model.canFlip, position: model.sessionState.position) {
            Task { await model.flip() }
        }
    }
    private var shutter: some View {
        CameraShutter(
            enabled: model.shutterEnabled,
            isRecording: model.recording.isActive,
            progress: model.recording.progress
        ) {
            Task { await model.shutterTapped() }
        }
    }

    @ViewBuilder private var controls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 20) {
                CameraContentSlot(clipCount: context.clipCount)
                HStack(spacing: 44) {
                    shutter
                    flip
                }
            }
        } else {
            overlayControlsPortrait
        }
    }

    /// The shutter sits on the true horizontal centreline: it is centred by the ZStack rather
    /// than by an HStack whose side controls have unequal widths.
    private var overlayControlsPortrait: some View {
        ZStack {
            HStack {
                CameraContentSlot(clipCount: context.clipCount)
                Spacer()
                flip
            }
            shutter
        }
        .frame(maxWidth: .infinity)
    }

    private var preview: some View {
        // No AnyView and no branching: the preview must keep one stable identity so its capture
        // session is never handed to a second preview layer.
        let fillsScreen = !dynamicTypeSize.isAccessibilitySize
        return basePreview
            .ignoresSafeArea(edges: fillsScreen ? .all : [])
            .frame(maxWidth: fillsScreen ? .infinity : nil, maxHeight: fillsScreen ? .infinity : nil)
    }

    private var basePreview: some View {
        GeometryReader { geometry in
            ZStack {
                CameraPreviewView(session: model.service.previewSession, presentation: model.presentation,
                                  interfaceChanged: model.updateInterface)
                    .accessibilityHidden(true)
                if pinching && model.canZoom {
                    VStack { Spacer(); Text(model.sessionState.zoom.formatted(.number.precision(.fractionLength(1))) + "×")
                        .font(.caption.monospacedDigit()).padding(8).background(.black.opacity(0.8)).clipShape(Capsule())
                    }.padding(8)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(zoomGesture, including: model.canZoom ? .all : .none)
            .modifier(CameraZoomAccessibility(enabled: model.canZoom, zoom: model.sessionState.zoom) { factor in
                Task { await model.zoom(to: factor) }
            })
            .accessibilityIdentifier("cameraShell")
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($pinching) { _, active, _ in active = true }
            .onChanged { value in
                guard model.canZoom else { return }
                if pinchBase == nil { pinchBase = model.sessionState.zoom }
                let factor = (pinchBase ?? 1) * Double(value.magnification)
                Task { await model.zoom(to: factor) }
            }
            .onEnded { _ in pinchBase = nil }
    }

    @ViewBuilder private var statusOverlay: some View {
        switch model.readiness {
        case .denied, .restricted:
            message(title: "Camera access is off", detail: "Allow camera access in Settings to use Mellow.") {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.accessibilityIdentifier("openSettings")
            }
        case .unavailable:
            message(title: "Camera unavailable", detail: CameraFailure.cameraUnavailable.message) { EmptyView() }
        case .failed(let error):
            message(title: "Camera unavailable", detail: error.message) { Button("Try Again", action: model.retry) }
        case .interrupted:
            Text("Camera temporarily unavailable").font(.headline).multilineTextAlignment(.center).padding()
                .background(.black.opacity(0.84)).accessibilityIdentifier("cameraInterrupted")
        case .mismatch:
            Text("Rotate your iPhone").font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.6)).clipShape(Capsule())
                .accessibilityIdentifier("cameraMismatch")
        case .permissionPending, .preparing:
            ProgressView().tint(.white).accessibilityLabel("Preparing camera")
        case .recording, .ready, .inactive: EmptyView()
        }
    }

    /// Recording failures are independent of preview readiness, so they live in their own overlay.
    @ViewBuilder private var recordingFailureOverlay: some View {
        if let failure = model.recording.failure {
            message(title: failure.title, detail: failure.detail) {
                if failure.offersSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }.accessibilityIdentifier("openSettings")
                }
                Button("OK") { model.recording.dismissFailure() }.accessibilityIdentifier("dismissRecordingFailure")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func message<Action: View>(title: String, detail: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline).accessibilityIdentifier("cameraMessageTitle")
            Text(detail).multilineTextAlignment(.center)
            action().buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).frame(minHeight: 44)
        }.foregroundStyle(.white).padding(18).background(.black.opacity(0.84))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// VoiceOver exposes the same bounded zoom without introducing a visible control.
private struct CameraZoomAccessibility: ViewModifier {
    let enabled: Bool
    let zoom: Double
    let adjust: (Double) -> Void
    func body(content: Content) -> some View {
        // One unconditional structure. Branching here changes structural identity the moment zoom
        // becomes available (session start), which tears down and rebuilds the preview UIView; the
        // rebuilt layer then takes the one preview connection the shared session can provide and the
        // visible layer goes black.
        content
            .accessibilityElement(children: .contain)
            .accessibilityLabel(enabled ? "Rear camera preview" : "Camera preview")
            .accessibilityValue(enabled ? zoom.formatted(.number.precision(.fractionLength(1))) + "×" : "")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                switch direction {
                case .increment: adjust(zoom + 0.1)
                case .decrement: adjust(zoom - 0.1)
                @unknown default: break
                }
            }
    }
}

/// The root capture surface is the application root: no Back, no title, preview dominant.
private struct CameraChrome: ViewModifier {
    let isRoot: Bool
    func body(content: Content) -> some View {
        content
            .toolbar(isRoot ? .hidden : .visible, for: .navigationBar)
            .navigationTitle(isRoot ? "" : "Camera").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
