import AVFoundation

@MainActor
final class AVFoundationCameraService: CameraCaptureService {
    private(set) var authorization: CameraAuthorization = .notDetermined
    private(set) var state = CameraSessionState() {
        didSet { stateDidChange?(state) }
    }
    var stateDidChange: (@MainActor (CameraSessionState) -> Void)?
    var recordingDidChange: (@MainActor (CameraRecordingEvent) -> Void)?
    var previewSession: AVCaptureSession? { state.deviceKind == nil ? nil : session }
    var recordedDuration: TimeInterval { worker.recordedDurationSeconds }
    private let session: AVCaptureSession
    private let worker: CameraSessionWorker
    private var authorizationTask: Task<CameraAuthorization, Never>?

    init() {
        let session = AVCaptureSession()
        self.session = session
        worker = CameraSessionWorker(session: session)
        worker.observe { [weak self] state in
            Task { @MainActor [weak self] in self?.accept(state) }
        }
        worker.observeRecording { [weak self] event in
            Task { @MainActor [weak self] in self?.recordingDidChange?(event) }
        }
    }

    deinit { worker.shutdown() }

    func resolveAuthorization() async -> CameraAuthorization {
        if let authorizationTask { return await authorizationTask.value }
        let task = Task { @MainActor in
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return CameraAuthorization.authorized
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined:
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                return granted ? .authorized : .denied
            @unknown default: return .restricted
            }
        }
        authorizationTask = task
        authorization = await task.value
        authorizationTask = nil
        return authorization
    }

    func prepare() async {
        guard authorization == .authorized else { return }
        accept(await worker.perform(.prepare))
    }
    func start() async {
        guard authorization == .authorized else { return }
        accept(await worker.perform(.start))
    }
    func stop() async { accept(await worker.perform(.stop)) }
    func switchCamera() async {
        guard authorization == .authorized, state.canSwitch, state.isRunning else { return }
        accept(await worker.perform(.switchCamera))
    }
    func setZoom(_ factor: Double) async {
        guard state.position == .rear, state.isRunning else { return }
        accept(await worker.perform(.zoom(CameraZoomPolicy.clamp(factor))))
    }
    func setAudioEnabled(_ enabled: Bool) async {
        guard authorization == .authorized else { return }
        accept(await worker.perform(.setAudio(enabled)))
    }
    func startRecording(to url: URL, maximumDuration: TimeInterval) async -> Bool {
        guard authorization == .authorized, state.isRunning, !state.recordingRequested else { return false }
        let after = await worker.perform(.startRecording(url: url, maximumDuration: maximumDuration))
        accept(after)
        return after.recordingRequested
    }
    func requestStopRecording() async {
        accept(await worker.perform(.stopRecording))
    }
    private func accept(_ update: CameraSessionState) {
        guard update.revision >= state.revision else { return }
        state = update
    }
}
