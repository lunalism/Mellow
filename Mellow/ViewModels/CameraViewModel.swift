import AVFoundation
import Combine
import UIKit  // 햅틱

/// 카메라 화면 상태 바인딩 (Phase 1 Spec §7).
///
/// 세션 수명주기 · 전/후면 전환 · 필터 선택(스와이프/스트립).
/// 비율·노출·캡처(capturePhoto)는 다음 단계에서 추가.
///
/// 시뮬레이터 더미는 **뷰의 컴파일 타임 분기**(`#if targetEnvironment(simulator)`)로만
/// 진입한다. 여기엔 더미 상태가 존재하지 않는다 — 실기기 빌드에서 더미는 도달 불가.
@MainActor
final class CameraViewModel: ObservableObject {
    let sessionManager = CameraSessionManager()

    /// 프리뷰·캡처 공통 화면 비율. 기본 9:16(세로). 단일 출처(= WYSIWYG).
    /// TODO(캡처 단계): 셔터 캡처 시 원본을 **반드시 이 `aspectRatio`로 크롭**해 저장한다.
    ///   프리뷰는 resizeAspectFill로 이 비율의 센터 크롭을 보여주므로, 저장 크롭도
    ///   동일해야 프리뷰=캡처(WYSIWYG)가 유지된다. 다른 비율 하드코딩 금지.
    @Published private(set) var aspectRatio: AspectRatio = .default

    /// 선택된 필터 (단일 출처 = WYSIWYG). 캡처 단계에서 원본 + 이 `selectedFilter.id`를
    /// 비파괴 저장한다(원본은 그대로, 표시·익스포트 시 필터 렌더).
    @Published private(set) var selectedFilter: FilterPreset = .default

    /// 스트립/스와이프 순서(현재 Original/Sunday/Honey). Phase 2에서 8종.
    let presets: [FilterPreset] = FilterPreset.all

    /// 카메라 입력 구성에 성공했는지(전/후면 전환 활성화 여부). 실기기에서만 true.
    @Published private(set) var isCameraAvailable = false
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
    @Published private(set) var isSwitchingCamera = false

    private var didConfigure = false
    private let selectionHaptic = UISelectionFeedbackGenerator()

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

    // MARK: - 필터 선택 (Spec §4 — 이중 입력, 동기화)

    /// 스트립 칩 탭 → 특정 필터 선택.
    func selectFilter(_ preset: FilterPreset) {
        setFilter(preset)
    }

    /// 뷰파인더 스와이프 → 다음/이전 필터 순환(+1/-1). 끝에서 래핑.
    func cycleFilter(by delta: Int) {
        guard let index = presets.firstIndex(where: { $0.id == selectedFilter.id }) else { return }
        let count = presets.count
        let next = ((index + delta) % count + count) % count
        setFilter(presets[next])
    }

    /// 단일 진입점: 변경 시에만 갱신 + 디텐트 햅틱(Spec §4.3). 스트립↔스와이프 자동 동기화.
    private func setFilter(_ preset: FilterPreset) {
        guard preset.id != selectedFilter.id else { return }
        selectedFilter = preset
        selectionHaptic.selectionChanged()
        selectionHaptic.prepare()
    }
}
