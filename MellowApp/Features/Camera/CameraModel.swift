import Observation
import Foundation
import CoreGraphics
#if DEBUG
import OSLog
#endif

enum CameraDuration: Int, CaseIterable { case one = 1, two, three, four, five }

extension CameraDuration {
    /// Discrete stepping shared by the picker's drag snap, side taps and VoiceOver adjustment.
    /// Always clamps to 1s–5s; never produces a fractional or out-of-range duration.
    func advanced(by steps: Int) -> CameraDuration {
        let all = CameraDuration.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[min(max(index + steps, 0), all.count - 1)]
    }
    /// The three-slot window the picker shows: previous, selected, next (nil at the edges).
    var visibleWindow: [CameraDuration?] {
        let all = CameraDuration.allCases
        let index = all.firstIndex(of: self) ?? 0
        return [index > 0 ? all[index - 1] : nil, self, index < all.count - 1 ? all[index + 1] : nil]
    }
    var accessibilityValueText: String { "\(rawValue) second\(rawValue == 1 ? "" : "s")" }
}
enum CameraReadiness: Equatable {
    case permissionPending, denied, restricted, preparing, ready, mismatch, unavailable, interrupted, inactive
    /// A capture is in flight (preparing → savingToPhotos). Posture is not re-evaluated until it ends.
    case recording
    case failed(CameraFailure)
}

@MainActor
@Observable
final class CameraModel {
    let projectOrientation: ProjectOrientation
    private(set) var authorization: CameraAuthorization = .notDetermined
    private(set) var sessionState = CameraSessionState()
    /// Raw physical posture as reported, including face up/down, unknown and settling states.
    private(set) var deviceOrientation: CameraDeviceOrientation = .unknown
    /// Last definite posture, preserved while the device is face up/down or a reading settles.
    private(set) var stablePosture: CameraDeviceOrientation?
    private(set) var interfaceOrientation: CameraInterfaceOrientation = .unknown
    private(set) var presentation = CameraPreviewPresentation()
    var selectedDuration: CameraDuration = .three
    private(set) var visible = false
    private(set) var active = false
    private(set) var microphoneAuthorization: MicrophoneAuthorization = .notDetermined
    @ObservationIgnored let service: any CameraCaptureService
    @ObservationIgnored let recording: RecordingCoordinator
    @ObservationIgnored private let microphone: any MicrophoneAuthorizationProviding
    @ObservationIgnored private let orientation: any CameraOrientationSource
    @ObservationIgnored private var lifecycle: Task<Void, Never>?

#if DEBUG
    @ObservationIgnored private let startupLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.example.Mellow",
        category: "CameraStartup"
    )
    @ObservationIgnored private var startupSignpostID: OSSignpostID?
    @ObservationIgnored private var startupStart: DispatchTime?
    @ObservationIgnored private var startupInProgress = false
#endif

    init(
        projectOrientation: ProjectOrientation,
        service: any CameraCaptureService,
        orientation: any CameraOrientationSource,
        recording: RecordingCoordinator,
        microphone: any MicrophoneAuthorizationProviding
    ) {
        self.projectOrientation = projectOrientation
        self.service = service
        self.orientation = orientation
        self.recording = recording
        self.microphone = microphone
        authorization = service.authorization
        sessionState = service.state
        microphoneAuthorization = microphone.authorization
        service.stateDidChange = { [weak self] state in
#if DEBUG
            if let self, self.sessionState.phase != state.phase {
                MellowLog.app.info("Camera phase \(String(describing: self.sessionState.phase), privacy: .public) → \(String(describing: state.phase), privacy: .public)")
            }
#endif
            self?.sessionState = state
            self?.presentation.mirrored = state.position == .front
            self?.reactToSessionChangeWhileRecording(state)
#if DEBUG
            self?.handleStartupCompletion(state)
#endif
        }
    }

    // MARK: - Recording (Phase 4)

    var isRecordingActive: Bool { recording.isActive }
    /// Representative frame of the last successfully saved clip, for the preview tile (session-only,
    /// Phase 4 feedback). Nil until a save succeeds this session.
    var lastRecordingThumbnail: CGImage? { recording.lastThumbnail }
    /// Controls that could destabilise capture are locked for the whole capture lifecycle.
    var controlsLocked: Bool { recording.isActive }
    var isMicrophoneMuted: Bool { microphoneAuthorization != .authorized }
    var shutterEnabled: Bool {
        switch recording.phase {
        case .idle: return readiness == .ready
        case .recording: return true
        case .preparing, .finishing, .savingToPhotos: return false
        }
    }

    /// Shutter tap: start when idle, request an early stop while recording. No hold-to-record.
    func shutterTapped() async {
        switch recording.phase {
        case .idle:
            guard readiness == .ready else { return }
            // Definite physical posture only; capturePosture's provisional Portrait is for preview.
            await recording.record(maximum: selectedDuration, posture: deviceOrientation)
        case .recording:
            await recording.requestStop(.userRequested)
        case .preparing, .finishing, .savingToPhotos:
            break
        }
    }

    /// Applies the current microphone authorization to the session while idle only.
    func syncAudio() async {
        microphoneAuthorization = microphone.authorization
        guard !recording.isActive else { return }
        await service.setAudioEnabled(microphoneAuthorization == .authorized)
    }

    /// `mic.slash` control: request when undetermined; denied/restricted are surfaced to the UI.
    enum MicrophoneAction: Equatable { case none, openSettings, showRestricted }
    func microphoneTapped() async -> MicrophoneAction {
        guard !recording.isActive else { return .none }
        switch microphone.authorization {
        case .notDetermined:
            microphoneAuthorization = await microphone.requestAccess()
            await syncAudio()
            return .none
        case .denied: return .openSettings
        case .restricted: return .showRestricted
        case .authorized: return .none
        }
    }

    private func reactToSessionChangeWhileRecording(_ state: CameraSessionState) {
        guard recording.phase == .preparing || recording.phase == .recording else { return }
        switch state.phase {
        case .interrupted, .failed, .unavailable:
            Task { await recording.requestStop(.captureInterrupted) }
        default: break
        }
    }

    var readiness: CameraReadiness {
        guard visible, active else { return .inactive }
        switch authorization {
        case .notDetermined: return .permissionPending
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: break
        }
        // During a capture the clip's Portrait is already fixed; posture changes neither stop it
        // nor surface "Rotate your iPhone" until the capture ends (ADR-033).
        if recording.isActive { return .recording }
        switch sessionState.phase {
        case .idle, .preparing, .prepared: return .preparing
        case .failed(let failure): return .failed(failure)
        case .unavailable: return .unavailable
        case .interrupted: return .interrupted
        case .running: return capturePosture.matches(projectOrientation) ? .ready : .mismatch
        }
    }
    /// Posture used for readiness: a definite reading wins, otherwise the last definite posture,
    /// otherwise the interface orientation stands in until the device reports one.
    var capturePosture: CameraDeviceOrientation {
        if deviceOrientation.isDefinite { return deviceOrientation }
        if let stablePosture { return stablePosture }
        return interfaceOrientation.provisionalPosture
    }
    var canFlip: Bool { visible && active && sessionState.isRunning && sessionState.canSwitch && !recording.isActive }
    var canZoom: Bool { visible && active && sessionState.isRunning && sessionState.position == .rear }
    var isPortraitProject: Bool { projectOrientation == .portrait9x16 }

    func enter(active: Bool) {
        visible = true
        setActive(active)
    }
    func leave() {
        visible = false
        #if DEBUG
        stopStartupMeasurementIfNeeded()
        #endif
        orientation.stop()
        if recording.isActive { Task { await recording.requestStop(.appInactive) } }
        reconcile()
    }
    func setActive(_ value: Bool) {
        active = value
        if visible && active {
#if DEBUG
            beginStartupMeasurement()
#endif
            orientation.start { [weak self] in self?.receivePosture($0) }
        } else {
            #if DEBUG
            stopStartupMeasurementIfNeeded()
            #endif
            orientation.stop()
            // Never record in the background: finalize now, save if ≥ 1.0s, else discard.
            if recording.isActive { Task { await recording.requestStop(.appInactive) } }
        }
        reconcile()
    }
    func retry() { reconcile() }
    private func receivePosture(_ posture: CameraDeviceOrientation) {
        deviceOrientation = posture
        if posture.isDefinite { stablePosture = posture }
    }
    func updateInterface(_ value: CameraInterfaceOrientation) {
        interfaceOrientation = value
        if let angle = value.previewAngle { presentation.angle = angle }
    }
    func flip() async {
        guard canFlip else { return }
        await service.switchCamera()
    }
    func zoom(to factor: Double) async {
        guard canZoom else { return }
        await service.setZoom(CameraZoomPolicy.clamp(factor))
    }
    func waitForLifecycle() async { await lifecycle?.value }

    private func reconcile() {
        let previous = lifecycle
        // Popping the destination destroys this model, so the stop path must not depend on it still
        // being alive: otherwise the shared session keeps running after leaving Camera, and the next
        // entry attaches a new preview layer to a live session and stalls before it is usable.
        let service = self.service
        lifecycle = Task { [weak self] in
            await previous?.value
            guard let self, self.visible, self.active else { await service.stop(); return }
            authorization = await service.resolveAuthorization()
            guard visible && active else { await service.stop(); return }
            guard authorization == .authorized else { await service.stop(); return }
            await service.prepare()
            guard visible && active else { await service.stop(); return }
            // Optional audio follows the current microphone authorization; idle-only by construction.
            await syncAudio()
            // Preparation failure remains authoritative; orientation cannot overwrite it.
            guard service.state.phase == .prepared || service.state.phase == .running else { return }
            await service.start()
        }
    }

#if DEBUG
    private func beginStartupMeasurement() {
        guard !startupInProgress else { return }
        startupInProgress = true
        startupSignpostID = OSSignpostID(log: startupLog)
        startupStart = DispatchTime.now()
        if let signpostID = startupSignpostID {
            os_signpost(.begin, log: startupLog, name: "camera-startup", signpostID: signpostID, "project=%{public}s", projectOrientation.rawValue)
        }
    }

    private func handleStartupCompletion(_ state: CameraSessionState) {
        guard startupInProgress else { return }
        guard let signpostID = startupSignpostID, let start = startupStart else { return }
        guard state.phase == .running else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        os_signpost(
            .end,
            log: startupLog,
            name: "camera-startup",
            signpostID: signpostID,
            "duration_ms=%{public}.1f",
            elapsed
        )
        // This endpoint is AVCaptureSession.isRunning, NOT a rendered frame. There is no public
        // first-frame callback on AVCaptureVideoPreviewLayer, so it is named for what it measures.
        MellowLog.app.info("Camera session-running latency \(elapsed, privacy: .public) ms (not visible-frame)")
        startupSignpostID = nil
        startupStart = nil
        startupInProgress = false
    }

    private func stopStartupMeasurementIfNeeded() {
        guard startupInProgress else { return }
        if let signpostID = startupSignpostID {
            os_signpost(
                .event,
                log: startupLog,
                name: "camera-startup",
                signpostID: signpostID,
                "status=%{public}s",
                "canceled"
            )
        }
        startupSignpostID = nil
        startupStart = nil
        startupInProgress = false
    }
#endif
}
