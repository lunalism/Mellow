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
    var revision = 0
    var isRunning: Bool { phase == .running }
}

enum CameraZoomPolicy {
    static let range = 1.0...2.0
    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
    }
}

/// Phase 3 preview foundation only. No recording, audio, file output or persistence API.
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
}
