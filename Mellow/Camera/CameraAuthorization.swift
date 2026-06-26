import AVFoundation
import Combine

/// 카메라 권한 상태 머신 (Phase 1 Spec §5.1).
///
/// notDetermined → (요청) → authorized → 정상 진입
///                        ↘ denied/restricted → 안내(설정 유도)
///
/// 앱은 어떤 경우에도 죽지 않는다. 거부 시 따뜻한 안내 화면으로 폴백.
@MainActor
final class CameraAuthorization: ObservableObject {
    enum State {
        case notDetermined   // 아직 안 물어봄 → 권한 프라이밍
        case authorized      // 정상 진입
        case denied          // denied/restricted → 안내(설정 유도)
    }

    @Published private(set) var state: State

    init() {
        state = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// 권한 요청. notDetermined일 때만 시스템 프롬프트가 뜬다.
    func request() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        state = granted ? .authorized : .denied
    }

    /// 외부(설정 앱)에서 권한이 바뀐 뒤 포그라운드 복귀 시 갱신.
    func refresh() {
        state = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    private static func map(_ status: AVAuthorizationStatus) -> State {
        switch status {
        case .authorized:           return .authorized
        case .denied, .restricted:  return .denied
        case .notDetermined:        return .notDetermined
        @unknown default:           return .denied
        }
    }
}
