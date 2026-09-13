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
    var previewSession: AVCaptureSession? { nil }
    private var wantsRunning = false

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
        state = CameraSessionState(phase: .prepared, canSwitch: frontAvailable, deviceKind: .wideAngle)
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
    func interrupt() { state.phase = .interrupted }
    func endInterruption() { state.phase = wantsRunning ? .running : .prepared }
    func fail(_ failure: CameraFailure) { state.phase = .failed(failure) }
}
#endif
