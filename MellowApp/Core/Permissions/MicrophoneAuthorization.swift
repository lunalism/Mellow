import AVFoundation

enum MicrophoneAuthorization: String, Sendable, CaseIterable {
    case notDetermined, authorized, denied, restricted
}

/// Microphone is optional in Mellow: this only reports/requests; nothing here gates recording.
@MainActor
protocol MicrophoneAuthorizationProviding: AnyObject {
    var authorization: MicrophoneAuthorization { get }
    func requestAccess() async -> MicrophoneAuthorization
}

@MainActor
final class AVMicrophoneAuthorization: MicrophoneAuthorizationProviding {
    var authorization: MicrophoneAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .restricted
        }
    }
    func requestAccess() async -> MicrophoneAuthorization {
        guard authorization == .notDetermined else { return authorization }
        return await AVCaptureDevice.requestAccess(for: .audio) ? .authorized : .denied
    }
}
