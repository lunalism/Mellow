import AVFoundation
import Combine

/// 카메라 화면 상태 바인딩 (Phase 1 Spec §7).
///
/// Stage 1 범위만 구현: 세션 수명주기 · 전/후면 전환.
/// 필터(selectedFilter)·비율(ratio)·노출·캡처(capturePhoto)는 다음 단계에서 추가.
///
/// 시뮬레이터 더미는 **뷰의 컴파일 타임 분기**(`#if targetEnvironment(simulator)`)로만
/// 진입한다. 여기엔 더미 상태가 존재하지 않는다 — 실기기 빌드에서 더미는 도달 불가.
@MainActor
final class CameraViewModel: ObservableObject {
    let sessionManager = CameraSessionManager()

    /// 카메라 입력 구성에 성공했는지(전/후면 전환 활성화 여부). 실기기에서만 true.
    @Published private(set) var isCameraAvailable = false
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
    @Published private(set) var isSwitchingCamera = false

    private var didConfigure = false

    /// 최초 진입 시 1회 세션 구성. 권한 authorized 이후에 호출한다.
    /// 구성·시작은 모두 백그라운드 큐에서 수행되어 UI를 막지 않는다(런치 윈도우 단축).
    func startSession() {
        guard !didConfigure else {
            sessionManager.start()
            return
        }
        didConfigure = true
        sessionManager.configure(position: .back) { [weak self] success in
            guard let self else { return }
            self.isCameraAvailable = success
            self.cameraPosition = self.sessionManager.position
            if success { self.sessionManager.start() }
        }
    }

    /// 백그라운드 진입 등으로 화면을 떠날 때.
    func stopSession() {
        sessionManager.stop()
    }

    /// 전/후면 전환 (Spec §3). 카메라 없으면 무시. 중복 탭 방지.
    func toggleCamera() {
        guard isCameraAvailable, !isSwitchingCamera else { return }
        isSwitchingCamera = true
        sessionManager.switchCamera { [weak self] success in
            guard let self else { return }
            self.isSwitchingCamera = false
            if success { self.cameraPosition = self.sessionManager.position }
        }
    }
}
