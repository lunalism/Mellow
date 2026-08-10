import AVFoundation

// 촬영에 필요한 권한(카메라·마이크)의 상태 조회와 요청.
//
// v0.1 은 카메라와 마이크가 둘 다 있어야 촬영이 성립한다. 하나라도 없으면
// 프리뷰를 시작하지 않는다. 설정 앱으로 보내는 동선은 여기 없다 — 2-13 에서 붙인다.

/// 권한 상태. AVAuthorizationStatus 를 앱에서 쓰는 형태로 좁힌 것.
enum PermissionState {
    /// 아직 물어본 적 없음. 요청하면 시스템 팝업이 뜬다.
    case undetermined
    case authorized
    /// 사용자가 거부함. 앱에서 다시 물을 수 없다.
    case denied
    /// 스크린타임 등 정책으로 막힘. 사용자가 거부한 것과 구분해서 안내한다.
    case restricted

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .undetermined
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }

    var isAuthorized: Bool { self == .authorized }
}

enum CameraPermissions {

    static func current(for mediaType: AVMediaType) -> PermissionState {
        PermissionState(AVCaptureDevice.authorizationStatus(for: mediaType))
    }

    /// 미결정이면 시스템에 요청하고, 그 외에는 현재 상태를 그대로 돌려준다.
    /// 이미 거부된 권한은 다시 물어도 팝업이 뜨지 않는다.
    static func request(for mediaType: AVMediaType) async -> PermissionState {
        let state = current(for: mediaType)
        guard state == .undetermined else { return state }

        let granted = await AVCaptureDevice.requestAccess(for: mediaType)
        return granted ? .authorized : .denied
    }
}
