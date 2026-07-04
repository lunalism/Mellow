import AVFoundation
import Combine
import CoreLocation
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

    /// 촬영 위치 캐시 (slice B-1). 세션과 함께 시작/중단하고, 셔터에서 동기로 좌표를 읽는다.
    private let location = LocationProvider()

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

    /// 셔터 게이트 상태. **저장과 분리** — capturing은 탭 직후 센서 노출이 끝날 때까지의
    /// 짧은 구간만이다. 저장은 백그라운드에서 독립적으로 돌며 다음 셔터를 막지 않는다.
    @Published private(set) var captureState: CaptureState = .idle
    /// 실패 토스트 메시지(저장공간 부족·촬영 실패). nil이면 미표시.
    @Published var captureError: String?

    enum CaptureState { case idle, capturing }

    /// 최근 캡처의 **필터 적용** 썸네일 (Stage 4b-1). nil이면 빈 상태(플레이스홀더).
    /// 비파괴 — 무필터 원본 + filterID를 프리뷰와 같은 체인으로 재렌더한 결과.
    @Published private(set) var latestThumbnail: UIImage?
    /// 캐시 키. 같은 캡처면 재렌더하지 않는다(SwiftUI 본문 재평가마다 렌더 금지).
    private var latestThumbnailID: UUID?

    private var didConfigure = false
    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let shutterHaptic = UIImpactFeedbackGenerator(style: .soft)

    /// 최초 진입 시 1회 세션 구성. 권한 authorized 이후에 호출한다.
    /// 구성·시작은 모두 백그라운드 큐에서 수행되어 UI를 막지 않는다(런치 윈도우 단축).
    func startSession() {
        #if DEBUG
        ThermalDiagnostics.shared.setActivity("previewing")
        #endif
        location.start()   // 카메라 활성 동안만 위치 갱신(권한 있을 때만 실제 시작)
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

    /// 백그라운드 진입 등으로 화면을 떠날 때. 위치 갱신도 함께 멈춘다(발열/배터리).
    func stopSession() {
        sessionManager.stop()
        location.stop()
        #if DEBUG
        ThermalDiagnostics.shared.setActivity("idle")
        #endif
    }

    /// 카메라 화면 진입 시 위치 권한 프라이밍(카메라 권한이 이미 허용된 상태에서 호출).
    /// 위치가 미결정일 때만 시스템 프롬프트가 뜬다 — 기존 사용자는 다음 카메라 진입 때 자연히 받는다.
    func requestLocationIfNeeded() {
        location.requestIfNeeded()
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

    // MARK: - 캡처 (Spec §6) — 비파괴 저장

    /// 셔터. 풀해상도 무필터 원본 + filterID를 비파괴 저장. 촬영 중 중복 탭 무시(Spec §3).
    func capturePhoto() {
        guard isCameraAvailable, captureState == .idle else { return }
        // 커밋된 값 스냅샷 — 크로스페이드 중이어도 transient가 아닌 selectedFilter를 쓴다.
        let filterID = selectedFilter.id
        let ratio = aspectRatio
        let createdAt = Date()
        // 셔터를 느리게 하지 않도록 캐시된 좌표를 **동기로** 읽는다(fresh fix 대기 없음).
        // fix가 아직 없으면(실내·방금 실행·거부) nil → 좌표 없이 저장.
        let coordinate = location.lastCoordinate

        captureState = .capturing
        shutterHaptic.impactOccurred()
        shutterHaptic.prepare()

        sessionManager.capturePhoto(
            aspectRatio: ratio,
            onReadyForNextShot: { [weak self] in
                // 센서 노출 완료 → 즉시 다음 셔터 허용(저장 완료를 기다리지 않음).
                self?.captureState = .idle
            },
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let data):
                    // 저장은 백그라운드에서 독립적으로 — 셔터 재활성화를 막지 않는다.
                    self.persist(data: data, filterID: filterID, ratio: ratio, at: createdAt,
                                 coordinate: coordinate)
                case .failure:
                    self.captureError = "촬영에 실패했어요"
                    self.captureState = .idle   // 센서 콜백 전 실패 시 안전하게 게이트 해제.
                }
            })
    }

    func clearCaptureError() { captureError = nil }

    /// 원본 저장(파일 쓰기는 백그라운드). 셔터 게이트(captureState)와 무관 — 저장이 다음
    /// 촬영을 막지 않는다. 저장 직후 같은 백그라운드 작업에서 썸네일을 렌더해 최신 샷을 반영.
    /// 저장공간 부족 시 실패 토스트만 띄운다.
    private func persist(data: Data, filterID: String, ratio: AspectRatio, at createdAt: Date,
                         coordinate: CLLocationCoordinate2D?) {
        Task.detached(priority: .utility) {
            do {
                let capture = try CaptureStore.shared.save(imageData: data, filterID: filterID,
                                                           ratio: ratio, createdAt: createdAt,
                                                           latitude: coordinate?.latitude,
                                                           longitude: coordinate?.longitude)
                let thumb = await CaptureThumbnailRenderer.shared.render(
                    originalURL: CaptureStore.shared.url(for: capture), filterID: capture.filterID)
                await MainActor.run {
                    guard let thumb else { return }
                    self.latestThumbnail = thumb
                    self.latestThumbnailID = capture.id
                }
            } catch {
                await MainActor.run { self.captureError = "저장 공간이 부족해요" }
            }
        }
    }

    // MARK: - 보관함 썸네일 (Stage 4b-1)

    /// 좌하단 썸네일을 **단일 소스(captures 최신순)**에 맞춘다 — 앱 진입/카메라 표시 시, 그리고
    /// 보관함에서 돌아올 때. 자체 상태를 들고 있지 않고 매번 `CaptureStore.latest`에서 파생한다:
    /// - 최신 캡처가 **있으면** 그 썸네일(같은 최신이면 내부 가드로 no-op, 바뀌었으면 재렌더).
    /// - **없으면**(전부 삭제) 비워서 첫 촬영 전과 같은 빈/비활성 상태로 되돌린다.
    /// 덕분에 상세 뷰 삭제(최신 삭제·비최신 삭제·전부 삭제) 후에도 썸네일이 갤러리와 일관된다.
    func syncLatestThumbnail() {
        guard let capture = CaptureStore.shared.latest else {
            latestThumbnail = nil          // → libraryThumbnail이 빈 상태 + .disabled로 복귀
            latestThumbnailID = nil
            return
        }
        renderThumbnail(for: capture)
    }

    /// 캡처 1건의 필터 적용 썸네일을 백그라운드에서 렌더 → 메인에서 반영. 같은 캡처면 스킵(캐시).
    private func renderThumbnail(for capture: Capture) {
        guard latestThumbnailID != capture.id else { return }
        let url = CaptureStore.shared.url(for: capture)
        let filterID = capture.filterID
        let id = capture.id
        Task.detached(priority: .utility) {
            let image = await CaptureThumbnailRenderer.shared.render(originalURL: url, filterID: filterID)
            await MainActor.run {
                guard let image else { return }
                self.latestThumbnail = image
                self.latestThumbnailID = id
            }
        }
    }
}
