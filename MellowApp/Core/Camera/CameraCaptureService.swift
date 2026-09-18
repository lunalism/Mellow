import AVFoundation

enum CameraAuthorization: String, Sendable, CaseIterable {
    case notDetermined, authorized, denied, restricted
}

enum CameraPosition: String, Sendable { case rear, front }
enum CameraDeviceKind: Sendable { case wideAngle }

enum CameraFailure: Error, Equatable, Sendable {
    case cameraUnavailable, unsupportedConfiguration, configurationFailed, startFailed, runtimeFailure, zoomFailed

    var message: String {
        switch self {
        case .cameraUnavailable: return "A camera is not available on this device."
        case .unsupportedConfiguration, .configurationFailed: return "The camera couldn’t be prepared. Try again."
        case .startFailed, .runtimeFailure: return "The camera stopped unexpectedly. Try again."
        case .zoomFailed: return "Camera zoom couldn’t be changed. Try again."
        }
    }
}

enum CameraSessionPhase: Equatable, Sendable {
    case idle, preparing, prepared, running, interrupted, unavailable
    case failed(CameraFailure)
}

struct CameraSessionState: Equatable, Sendable {
    var phase: CameraSessionPhase = .idle
    var position: CameraPosition = .rear
    var canSwitch = false
    var zoom = 1.0
    var deviceKind: CameraDeviceKind?
    /// Whether the session currently carries a microphone input (Phase 4, optional audio).
    var audioEnabled = false
    /// True once the output accepted a start request, until its didFinish callback.
    var recordingRequested = false
    /// True from the file output's didStart callback until its didFinish callback.
    var isRecording = false
    /// ADR-046: the verified QuickTime / H.264 / SDR / 1080p / 30 fps capture contract for the
    /// prepared session; nil until verified. Recording never starts without it.
    var captureFormat: CaptureFormatVerification?
    var revision = 0
    var isRunning: Bool { phase == .running }
}

/// Raw outcome of one file-output recording as the capture pipeline reports it. Policy
/// (duration limits, Photos, project separation) lives above this in RecordingCoordinator.
enum CameraRecordingEvent: Equatable, Sendable {
    case started
    /// `fileUsable` is AVFoundation's own verdict that the file was finalized playably, which is
    /// true for manual stops, maximum-duration stops and most interruptions.
    case finished(url: URL, fileUsable: Bool, reachedMaximum: Bool, errorDescription: String?)
}

enum CameraZoomPolicy {
    static let range = 1.0...2.0
    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
    }
}

/// Camera session + file-output recording boundary. No Photos, persistence or project API:
/// the service writes staging files and reports what happened; nothing more.
@MainActor
protocol CameraCaptureService: AnyObject {
    var authorization: CameraAuthorization { get }
    var state: CameraSessionState { get }
    /// Presentation-only access; callers must never mutate the session.
    var previewSession: AVCaptureSession? { get }
    var stateDidChange: (@MainActor (CameraSessionState) -> Void)? { get set }
    func resolveAuthorization() async -> CameraAuthorization
    func prepare() async
    func start() async
    func stop() async
    func switchCamera() async
    func setZoom(_ factor: Double) async

    // MARK: Recording (Phase 4)

    var recordingDidChange: (@MainActor (CameraRecordingEvent) -> Void)? { get set }
    /// Media time actually written so far; the canonical source for progress and early-stop checks.
    var recordedDuration: TimeInterval { get }
    /// Adds or removes the microphone input. No-op while recording; applied on the session's
    /// serial context.
    func setAudioEnabled(_ enabled: Bool) async
    /// Starts a Portrait-locked recording into `url` with a pipeline-enforced maximum.
    /// Returns false if the session cannot record right now.
    func startRecording(to url: URL, maximumDuration: TimeInterval) async -> Bool
    /// Idempotent stop request; completion arrives through `recordingDidChange`.
    func requestStopRecording() async
}
