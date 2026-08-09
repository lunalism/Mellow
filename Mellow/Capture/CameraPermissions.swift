import AVFoundation

/// 카메라·마이크 권한 조회와 요청. (Tasks 1-1)
///
/// 설정 앱으로 보내는 동선은 2-13이라 여기서는 상태 확인까지만 한다.
enum CameraPermissions {

    static func status(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: mediaType)
    }

    /// 미결정이면 요청하고, 이미 결정된 상태면 그대로 돌려준다.
    /// 시스템 다이얼로그는 미결정일 때 한 번만 뜬다.
    @discardableResult
    static func resolve(_ mediaType: AVMediaType) async -> AVAuthorizationStatus {
        let current = status(for: mediaType)
        guard current == .notDetermined else { return current }
        _ = await AVCaptureDevice.requestAccess(for: mediaType)
        return status(for: mediaType)
    }
}

extension AVAuthorizationStatus {
    var shortText: String {
        switch self {
        case .notDetermined: return "미결정"
        case .restricted: return "제한됨"
        case .denied: return "거부됨"
        case .authorized: return "허용됨"
        @unknown default: return "알 수 없음(\(rawValue))"
        }
    }
}
