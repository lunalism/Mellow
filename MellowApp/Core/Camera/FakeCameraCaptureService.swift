#if DEBUG
import AVFoundation

/// Shared by feature unit tests and explicitly opted-in simulator UI tests only.
@MainActor
final class FakeCameraCaptureService: CameraCaptureService {
    var authorization: CameraAuthorization
    var grantOnRequest = true
    var preparationFailure: CameraFailure?
    var rearWideAvailable = true
    var frontAvailable = true
    var authorizationSuspended = false
    private var authorizationWaiter: CheckedContinuation<CameraAuthorization, Never>?
    private(set) var calls: [String] = []
    private(set) var state = CameraSessionState() { didSet { stateDidChange?(state) } }
    var stateDidChange: (@MainActor (CameraSessionState) -> Void)?
    var recordingDidChange: (@MainActor (CameraRecordingEvent) -> Void)?
    var previewSession: AVCaptureSession? { nil }
    private var wantsRunning = false

    // MARK: Scripted recording
    /// When set, the fake advances `recordedDuration` in real time from a monotonic clock so UI
    /// tests can stop "early"; unit tests instead assign `recordedDuration` directly.
    var advancesRecordedDurationInRealTime = false
    /// Caps reported duration below 1s so a UI stop always discards, independent of tap timing.
    var capsBelowMinimum = false
    /// Result the fake reports for the next finished recording.
    var nextFileUsable = true
    var startRecordingFails = false
    private(set) var recordedDuration: TimeInterval = 0
    private(set) var activeRecordingURL: URL?
    private var recordingStartedAt: ContinuousClock.Instant?
    private var maximumDuration: TimeInterval = 0
    private var autoStopTask: Task<Void, Never>?
    var recordedDurationOverride: TimeInterval? {
        didSet { if let recordedDurationOverride { recordedDuration = recordedDurationOverride } }
    }

    init(authorization: CameraAuthorization = .authorized) { self.authorization = authorization }
    func resolveAuthorization() async -> CameraAuthorization {
        calls.append("authorize")
        if authorization == .notDetermined {
            if authorizationSuspended {
                authorization = await withCheckedContinuation { authorizationWaiter = $0 }
            } else { authorization = grantOnRequest ? .authorized : .denied }
        }
        return authorization
    }
    func completeAuthorization(_ value: CameraAuthorization) {
        authorizationWaiter?.resume(returning: value); authorizationWaiter = nil
    }
    func prepare() async {
        calls.append("prepare")
        guard authorization == .authorized else { return }
        guard rearWideAvailable else { state.phase = .unavailable; return }
        if let preparationFailure { state.phase = .failed(preparationFailure); return }
        if state.phase == .running || state.phase == .interrupted || state.phase == .prepared { return }
        state = CameraSessionState(phase: .prepared, canSwitch: frontAvailable, deviceKind: .wideAngle,
                                   captureFormat: CaptureFormatVerification.verifiedForTests)
    }
    func start() async {
        calls.append("start")
        wantsRunning = true
        if state.phase == .prepared { state.phase = .running }
    }
    func stop() async {
        calls.append("stop")
        wantsRunning = false
        if state.phase == .running { state.phase = .prepared }
    }
    func switchCamera() async {
        calls.append("switch")
        guard state.isRunning, state.canSwitch else { return }
        state.position = state.position == .rear ? .front : .rear
        state.zoom = 1
    }
    func setZoom(_ factor: Double) async {
        guard state.isRunning, state.position == .rear else { return }
        state.zoom = CameraZoomPolicy.clamp(factor)
    }
    func setAudioEnabled(_ enabled: Bool) async {
        calls.append(enabled ? "audioOn" : "audioOff")
        guard !state.recordingRequested else { return }
        state.audioEnabled = enabled
    }

    func startRecording(to url: URL, maximumDuration: TimeInterval) async -> Bool {
        calls.append("startRecording")
        guard state.isRunning, !state.recordingRequested, !startRecordingFails else { return false }
        state.recordingRequested = true
        activeRecordingURL = url
        // Mirror AVFoundation: the staging file exists on disk while recording.
        FileManager.default.createFile(atPath: url.path, contents: Data([0]))
        self.maximumDuration = maximumDuration
        recordedDuration = recordedDurationOverride ?? 0
        recordingStartedAt = advancesRecordedDurationInRealTime ? ContinuousClock.now : nil
        // Deliver didStart on a later hop, like AVFoundation does.
        Task { @MainActor [weak self] in
            guard let self, self.state.recordingRequested else { return }
            self.state.isRecording = true
            self.recordingDidChange?(.started)
            if self.advancesRecordedDurationInRealTime {
                self.autoStopTask = Task { @MainActor [weak self] in
                    while let self, self.state.isRecording {
                        if let start = self.recordingStartedAt {
                            let elapsed = (ContinuousClock.now - start).components
                            let raw = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                            self.recordedDuration = self.capsBelowMinimum ? min(0.6, raw) : min(self.maximumDuration, raw)
                        }
                        if self.recordedDuration >= self.maximumDuration { self.finishRecording(reachedMaximum: true); return }
                        try? await Task.sleep(for: .milliseconds(33))
                    }
                }
            }
        }
        return true
    }

    func requestStopRecording() async {
        calls.append("stopRecording")
        guard state.recordingRequested else { return }
        finishRecording(reachedMaximum: false)
    }

    /// Simulates the pipeline reaching `maxRecordedDuration`.
    func simulateMaximumReached() { finishRecording(reachedMaximum: true) }

    private func finishRecording(reachedMaximum: Bool) {
        guard state.recordingRequested, let url = activeRecordingURL else { return }
        autoStopTask?.cancel(); autoStopTask = nil
        if reachedMaximum { recordedDuration = maximumDuration }
        state.recordingRequested = false
        state.isRecording = false
        activeRecordingURL = nil
        recordingStartedAt = nil
        let usable = nextFileUsable
        nextFileUsable = true
        recordingDidChange?(.finished(url: url, fileUsable: usable, reachedMaximum: reachedMaximum, errorDescription: usable ? nil : "fake write failure"))
    }

    func interrupt() { state.phase = .interrupted }
    func endInterruption() { state.phase = wantsRunning ? .running : .prepared }
    func fail(_ failure: CameraFailure) { state.phase = .failed(failure) }
}
#endif
