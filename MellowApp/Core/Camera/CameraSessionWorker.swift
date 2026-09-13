import AVFoundation

/// The sole unchecked boundary: all mutable state and AVFoundation operations are confined
/// to queue. Only Sendable commands/snapshots cross it; the session is shared solely with
/// the main-thread preview layer, which owns presentation rather than capture configuration.
final class CameraSessionWorker: @unchecked Sendable {
    enum Command: Sendable { case prepare, start, stop, switchCamera, zoom(Double) }
    private let queue = DispatchQueue(label: "com.mellow.camera.session", qos: .userInitiated)
    private let session: AVCaptureSession
    private var input: AVCaptureDeviceInput?
    private var state = CameraSessionState()
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []
    private var publish: (@Sendable (CameraSessionState) -> Void)?

    init(session: AVCaptureSession) { self.session = session }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func shutdown() {
        queue.async {
            self.wantsRunning = false
            self.publish = nil
            self.observers.forEach(NotificationCenter.default.removeObserver)
            self.observers = []
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func observe(_ callback: @escaping @Sendable (CameraSessionState) -> Void) {
        queue.async {
            self.publish = callback
            let center = NotificationCenter.default
            self.observers = [
                center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: self.session, queue: nil) { [weak self] _ in
                    self?.enqueueInterruption(began: true)
                },
                center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: self.session, queue: nil) { [weak self] _ in
                    self?.enqueueInterruption(began: false)
                },
                center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: self.session, queue: nil) { [weak self] note in
                    let reset = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code == .mediaServicesWereReset
                    self?.enqueueRuntimeFailure(reset: reset)
                }
            ]
        }
    }

    func perform(_ command: Command) async -> CameraSessionState {
        await withCheckedContinuation { continuation in
            queue.async {
                switch command {
                case .prepare:
                    if self.input == nil || self.isFailed { self.configure(position: self.state.position) }
                case .start:
                    self.wantsRunning = true
                    self.startIfPossible()
                case .stop:
                    self.wantsRunning = false
                    if self.session.isRunning { self.session.stopRunning() }
                    if self.state.phase == .running { self.state.phase = .prepared }
                case .switchCamera:
                    guard self.state.canSwitch, self.state.phase == .running else {
                        continuation.resume(returning: self.snapshot()); return
                    }
                    self.configure(position: self.state.position == .rear ? .front : .rear)
                    self.startIfPossible()
                case .zoom(let factor): self.applyZoom(factor)
                }
                continuation.resume(returning: self.snapshot())
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = state.phase { return true }
        return state.phase == .unavailable
    }

    private func configure(position: CameraPosition) {
        dispatchPrecondition(condition: .onQueue(queue))
        state.phase = .preparing
        state.canSwitch = false
        _ = snapshot()
        if session.isRunning { session.stopRunning() }
        // No virtual or secondary-lens fallback. Missing wide camera is a typed failure.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                  position: position == .rear ? .back : .front) else {
            fail(.cameraUnavailable); return
        }
        do {
            let candidate = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.inputs.forEach(session.removeInput)
            input = nil
            guard session.canSetSessionPreset(.hd1920x1080), session.canAddInput(candidate) else {
                fail(.unsupportedConfiguration); return
            }
            session.sessionPreset = .hd1920x1080
            session.addInput(candidate)
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            guard device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }),
                  position != .rear || (device.minAvailableVideoZoomFactor <= 1 && device.maxAvailableVideoZoomFactor >= 2) else {
                fail(.unsupportedConfiguration); return
            }
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.videoZoomFactor = 1
            input = candidate
            state.position = position
            state.deviceKind = .wideAngle
            state.zoom = 1
            state.canSwitch = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                      position: position == .rear ? .front : .back) != nil
            state.phase = .prepared
        } catch { fail(.configurationFailed) }
    }

    private func startIfPossible() {
        guard wantsRunning, input != nil, !isFailed else { return }
        guard !session.isInterrupted else { state.phase = .interrupted; return }
        guard state.phase == .prepared || state.phase == .running || state.phase == .interrupted else { return }
        if !session.isRunning { session.startRunning() }
        state.phase = session.isRunning ? .running : .failed(.startFailed)
    }

    private func applyZoom(_ requested: Double) {
        guard state.phase == .running, state.position == .rear, let device = input?.device else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.videoZoomFactor = CGFloat(CameraZoomPolicy.clamp(requested))
            state.zoom = Double(device.videoZoomFactor)
        } catch {
            if session.isRunning { session.stopRunning() }
            fail(.zoomFailed)
        }
    }

    private func enqueueInterruption(began: Bool) {
        queue.async {
            // A delayed interruption notification must not erase a runtime/configuration error.
            guard !self.isFailed else { return }
            if began { self.state.phase = .interrupted }
            else {
                self.state.phase = self.input == nil ? .idle : .prepared
                self.startIfPossible()
            }
            _ = self.snapshot()
        }
    }

    private func enqueueRuntimeFailure(reset: Bool) {
        queue.async {
            if reset {
                self.configure(position: self.state.position)
                self.startIfPossible()
            } else {
                if self.session.isRunning { self.session.stopRunning() }
                self.fail(.runtimeFailure)
            }
            _ = self.snapshot()
        }
    }

    private func fail(_ error: CameraFailure) {
        wantsRunning = false
        state.phase = error == .cameraUnavailable ? .unavailable : .failed(error)
        state.canSwitch = false
    }

    @discardableResult private func snapshot() -> CameraSessionState {
        state.revision += 1
        publish?(state)
        return state
    }
}
