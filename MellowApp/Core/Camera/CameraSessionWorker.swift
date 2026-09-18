import AVFoundation

/// The sole unchecked boundary: all mutable state and AVFoundation operations are confined
/// to queue. Only Sendable commands/snapshots cross it; the session is shared solely with
/// the main-thread preview layer, which owns presentation rather than capture configuration.
final class CameraSessionWorker: @unchecked Sendable {
    enum Command: Sendable {
        case prepare, start, stop, switchCamera, zoom(Double)
        case setAudio(Bool)
        case startRecording(url: URL, maximumDuration: TimeInterval)
        case stopRecording
    }
    private let queue = DispatchQueue(label: "com.mellow.camera.session", qos: .userInitiated)
    private let session: AVCaptureSession
    private var input: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var wantsAudio = false
    private let movieOutput = AVCaptureMovieFileOutput()
    private lazy var recordingDelegate = RecordingDelegate(worker: self)
    private var recordingRequested = false
    private var stopSessionAfterRecording = false
    private var state = CameraSessionState()
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []
    private var publish: (@Sendable (CameraSessionState) -> Void)?
    private var publishRecording: (@Sendable (CameraRecordingEvent) -> Void)?

    init(session: AVCaptureSession) {
        self.session = session
        // ~1s fragments keep crash-left 1–5s staging files playable up to the last written
        // second (best-effort recovery); the default 10s would leave them without a moov atom.
        movieOutput.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        // ADR-046: the session must not re-pick a wide-color / HDR format or color space behind our
        // back; the worker sets and verifies the SDR color space itself in configure(position:).
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
    }

    /// Media time written so far. AVFoundation documents this property as safe to read from any
    /// thread, so progress can sample it without a queue hop.
    var recordedDurationSeconds: TimeInterval {
        let duration = movieOutput.recordedDuration
        return duration.isNumeric ? duration.seconds : 0
    }

    func observeRecording(_ callback: @escaping @Sendable (CameraRecordingEvent) -> Void) {
        queue.async { self.publishRecording = callback }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func shutdown() {
        queue.async {
            self.wantsRunning = false
            self.publish = nil
            self.publishRecording = nil
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
                    if self.isRecordingOrRequested {
                        // Stopping the session mid-write truncates the file; finish the recording
                        // first and stop the session from the didFinish callback.
                        self.stopSessionAfterRecording = true
                        self.movieOutput.stopRecording()
                    } else {
                        if self.session.isRunning { self.session.stopRunning() }
                        if self.state.phase == .running { self.state.phase = .prepared }
                    }
                case .switchCamera:
                    guard self.state.canSwitch, self.state.phase == .running, !self.isRecordingOrRequested else {
                        continuation.resume(returning: self.snapshot()); return
                    }
                    self.configure(position: self.state.position == .rear ? .front : .rear)
                    self.startIfPossible()
                case .zoom(let factor): self.applyZoom(factor)
                case .setAudio(let enabled): self.setAudio(enabled)
                case .startRecording(let url, let maximumDuration): self.startRecording(to: url, maximumDuration: maximumDuration)
                case .stopRecording:
                    if self.isRecordingOrRequested { self.movieOutput.stopRecording() }
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
        state.captureFormat = nil
        _ = snapshot()
        if session.isRunning { session.stopRunning() }
        // No virtual or secondary-lens fallback. Missing wide camera is a typed failure.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                  position: position == .rear ? .back : .front) else {
            fail(.cameraUnavailable); return
        }
        var colorVerification: (colorSpace: CaptureColorSpace, hdr: Bool, autoHDR: Bool, width: Int32, height: Int32)?
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
            audioInput = nil
            if wantsAudio { attachAudioInputLocked() }
            if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let format = device.activeFormat
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let supports30 = format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
            if let rejection = CaptureFormatPolicy.verifyFormat(width: dimensions.width, height: dimensions.height, supports30fps: supports30) {
                rejectCapture(rejection); return
            }
            guard position != .rear || (device.minAvailableVideoZoomFactor <= 1 && device.maxAvailableVideoZoomFactor >= 2) else {
                fail(.unsupportedConfiguration); return
            }
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.videoZoomFactor = 1
            // ADR-046 SDR: take HDR control away from the device, force HDR off where the format
            // could stream it, and pin the sRGB color space (session wide-color auto-config is off).
            device.automaticallyAdjustsVideoHDREnabled = false
            if format.isVideoHDRSupported { device.isVideoHDREnabled = false }
            let supportedSpaces = format.supportedColorSpaces.map { CaptureColorSpace(rawValue: $0.rawValue) ?? .unknown }
            switch CaptureFormatPolicy.sdrColorSpace(supported: supportedSpaces) {
            case .failure(let rejection): rejectCapture(rejection); return
            case .success(let space): device.activeColorSpace = AVCaptureColorSpace(rawValue: space.rawValue) ?? .sRGB
            }
            let active = CaptureColorSpace(rawValue: device.activeColorSpace.rawValue) ?? .unknown
            if let rejection = CaptureFormatPolicy.verifyAppliedColor(active: active, hdrEnabled: device.isVideoHDREnabled, automaticHDR: device.automaticallyAdjustsVideoHDREnabled) {
                rejectCapture(rejection); return
            }
            colorVerification = (active, device.isVideoHDREnabled, device.automaticallyAdjustsVideoHDREnabled, dimensions.width, dimensions.height)
            input = candidate
            state.position = position
            state.deviceKind = .wideAngle
            state.zoom = 1
            state.canSwitch = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                      position: position == .rear ? .front : .back) != nil
        } catch { fail(.configurationFailed); return }
        // ADR-046 codec: only after the configuration is committed does the movie output expose its
        // real video connection and codec list for this preset. Explicit H.264 or a typed failure —
        // never the list's first / default codec.
        guard let color = colorVerification, let verification = enforceVideoCodec(color: color) else { return }
        state.captureFormat = verification
        state.phase = .prepared
        MellowLog.recording.info("capture contract verified: codec=\(verification.videoCodec, privacy: .public) colorSpace=\(verification.colorSpace.rawValue, privacy: .public) hdr=\(verification.hdrEnabled, privacy: .public) autoHDR=\(verification.automaticHDR, privacy: .public) \(verification.width, privacy: .public)x\(verification.height, privacy: .public)@\(verification.frameRate, privacy: .public) audio=\(verification.audioAttached, privacy: .public)")
    }

    /// Applies and verifies H.264 on the movie output's video connection. Returns nil (after
    /// failing the session) when the contract cannot be established.
    private func enforceVideoCodec(color: (colorSpace: CaptureColorSpace, hdr: Bool, autoHDR: Bool, width: Int32, height: Int32)) -> CaptureFormatVerification? {
        guard let connection = movieOutput.connection(with: .video) else { rejectCapture(.missingVideoConnection); return nil }
        let available = movieOutput.availableVideoCodecTypes.map(\.rawValue)
        let keys = movieOutput.supportedOutputSettingsKeys(for: connection)
        switch CaptureFormatPolicy.videoOutputSettings(availableCodecs: available, supportedKeys: keys) {
        case .failure(let rejection): rejectCapture(rejection); return nil
        case .success(let settings): movieOutput.setOutputSettings(settings, for: connection)
        }
        let applied = movieOutput.outputSettings(for: connection)[AVVideoCodecKey]
        let appliedCodec = (applied as? AVVideoCodecType)?.rawValue ?? applied as? String
        if let rejection = CaptureFormatPolicy.verifyAppliedCodec(appliedCodec) { rejectCapture(rejection); return nil }
        return CaptureFormatVerification(videoCodec: appliedCodec ?? "", colorSpace: color.colorSpace, hdrEnabled: color.hdr, automaticHDR: color.autoHDR,
                                         width: color.width, height: color.height, frameRate: CaptureFormatPolicy.requiredFrameRate, audioAttached: audioInput != nil)
    }

    private func rejectCapture(_ rejection: CaptureFormatPolicy.Rejection) {
        MellowLog.recording.error("capture contract rejected: \(String(describing: rejection), privacy: .public)")
        state.captureFormat = nil
        fail(.unsupportedConfiguration)
    }

    private var isRecordingOrRequested: Bool { recordingRequested || movieOutput.isRecording }

    /// Must be called inside begin/commitConfiguration. Missing or unusable microphone leaves the
    /// session video-only; no silent track is fabricated.
    private func attachAudioInputLocked() {
        guard let microphone = AVCaptureDevice.default(for: .audio),
              let candidate = try? AVCaptureDeviceInput(device: microphone),
              session.canAddInput(candidate) else {
            state.audioEnabled = false; return
        }
        session.addInput(candidate)
        audioInput = candidate
        state.audioEnabled = true
    }

    private func setAudio(_ enabled: Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        wantsAudio = enabled
        // Never reconfigure inputs under an active recording; the coordinator only asks while idle.
        guard !isRecordingOrRequested, input != nil, !isFailed else { return }
        guard enabled != (audioInput != nil) else { state.audioEnabled = audioInput != nil; return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if enabled {
            attachAudioInputLocked()
        } else if let audioInput {
            session.removeInput(audioInput)
            self.audioInput = nil
            state.audioEnabled = false
        }
    }

    private func startRecording(to url: URL, maximumDuration: TimeInterval) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state.phase == .running, session.outputs.contains(movieOutput), !isRecordingOrRequested else { return }
        // ADR-046: never write a file under an unverified codec / SDR contract.
        guard let contract = state.captureFormat, contract.satisfiesContract else {
            MellowLog.recording.error("recording refused: capture contract not verified")
            return
        }
        if let connection = movieOutput.connection(with: .video) {
            // Portrait is fixed once here for the clip's whole lifetime; later posture changes
            // never touch the connection (ADR-033).
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = state.position == .front
            }
        }
        movieOutput.maxRecordedDuration = CMTime(seconds: maximumDuration, preferredTimescale: 600)
        recordingRequested = true
        state.recordingRequested = true
        movieOutput.startRecording(to: url, recordingDelegate: recordingDelegate)
    }

    fileprivate func recordingDidStart() {
        queue.async {
            self.state.isRecording = true
            _ = self.snapshot()
            self.publishRecording?(.started)
        }
    }

    fileprivate func recordingDidFinish(url: URL, error: Error?) {
        queue.async {
            self.recordingRequested = false
            self.state.recordingRequested = false
            self.state.isRecording = false
            var usable = error == nil
            var reachedMaximum = false
            var description: String?
            if let error = error as NSError? {
                reachedMaximum = error.domain == AVFoundationErrorDomain && error.code == AVError.maximumDurationReached.rawValue
                usable = (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
                description = usable ? nil : error.localizedDescription
            }
            if self.stopSessionAfterRecording {
                self.stopSessionAfterRecording = false
                if self.session.isRunning { self.session.stopRunning() }
                if self.state.phase == .running { self.state.phase = .prepared }
            }
            _ = self.snapshot()
            self.publishRecording?(.finished(url: url, fileUsable: usable, reachedMaximum: reachedMaximum, errorDescription: description))
        }
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
        state.captureFormat = nil
    }

    @discardableResult private func snapshot() -> CameraSessionState {
        state.revision += 1
        publish?(state)
        return state
    }
}

/// Thin AVFoundation delegate; every callback hops back onto the worker queue.
private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private weak var worker: CameraSessionWorker?
    init(worker: CameraSessionWorker) { self.worker = worker }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        worker?.recordingDidStart()
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        worker?.recordingDidFinish(url: outputFileURL, error: error)
    }
}
