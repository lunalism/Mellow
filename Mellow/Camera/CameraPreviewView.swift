import SwiftUI
import AVFoundation
import CoreImage
#if DEBUG
import QuartzCore  // CACurrentMediaTime (MTRACE5 워치독 단조 시계)
#endif

/// 라이브 프리뷰 (Stage L3~). SwiftUI ↔ `MetalPreviewView`(MTKView) 브리지.
///
/// 세션의 VideoDataOutput 프레임을 `FrameProcessor`로 방향 보정 + 프리뷰 다운스케일한 뒤
/// **LUT(LUTStore)**를 적용해 Metal 뷰에 넘긴다. LUT은 slug당 영속 필터 1개를 재사용하고
/// 프레임마다 inputImage만 교체한다(3D 텍스처 재업로드 없음). 전환은 즉시 스왑(L3 Decision B).
struct CameraPreviewView: UIViewRepresentable {
    let sessionManager: CameraSessionManager
    /// 선택 필터 slug(프리뷰·저장 공통 키). "original"/미상 → 패스스루.
    let selectedSlug: String
    /// 세션이 돌아야 하는지(= reconcile 불변식). false로 바뀌면 마지막 프레임을 freeze 오버레이로 얹는다.
    let isPreviewRunning: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionManager: sessionManager)
    }

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView()
        context.coordinator.attach(to: view)
        context.coordinator.setPreset(slug: selectedSlug, animated: false)
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {
        // selectedSlug가 바뀌면 즉시 스왑(스와이프/스트립 공통 경로).
        context.coordinator.setPreset(slug: selectedSlug, animated: true)
        #if DEBUG
        // MTRACE5 스톨 워치독 — 내부에서 실제 엣지만 반응(updateUIView는 반복 호출되므로).
        context.coordinator.updateStallWatchdog(isPreviewRunning: isPreviewRunning)
        #endif
        // 세션 정지(보관함 열림/백그라운드) → 마지막 프레임 freeze. 시작 시엔 첫 프레임이 오버레이를 해제.
        if !isPreviewRunning { context.coordinator.freezeLastFrame() }
    }

    /// 프레임 콜백(videoQueue) → LUT 적용 → 메인에서 뷰에 전달.
    final class Coordinator {
        private let sessionManager: CameraSessionManager
        private let processor = FrameProcessor()
        private weak var view: MetalPreviewView?

        // 상태 보호(잠금): render는 videoQueue, setPreset/프리페치 완료는 다른 컨텍스트.
        private let lock = NSLock()
        private var currentSlug: String = MellowFilterRoster.originalSlug
        /// slug → 영속 CIFilter 로컬 캐시. LUTStore(actor)에서 1회 가져와 보관 →
        /// render()는 프레임마다 **동기**로 읽는다(프레임당 await/필터 재생성 없음).
        private var liveFilters: [String: CIFilter] = [:]
        /// 프리페치 복구 가드: slug당 재킥 시도 수(캡 5) + 진행 중 dedupe.
        /// 캡 없으면 진짜 죽은 블롭(디스크 손상)에서 프레임레이트로 디스크 재시도가 돌아 발열 리스크.
        /// 캡 도달 후 패스스루가 올바른 종착 상태. 진행 중 Set은 프레임당 중복 Task 스폰 방지.
        private var prefetchAttempts: [String: Int] = [:]
        private var prefetchInFlight: Set<String> = []
        private static let maxPrefetchRetries = 5
        /// 마지막으로 렌더한 프레임(freeze-last-frame용). 프레임당 참조만 보관(변환 없음) →
        /// 정지 시 freezeLastFrame()에서 1회 UIImage로 변환. lock으로 보호(render=videoQueue).
        private var lastImage: CIImage?

        init(sessionManager: CameraSessionManager) {
            self.sessionManager = sessionManager
        }

        func attach(to view: MetalPreviewView) {
            self.view = view
            prefetch(MellowFilterRoster.defaultSlug)   // 기본값(sunday) 첫 프레임부터 준비
            sessionManager.onFrame = { [weak self] sampleBuffer in
                #if DEBUG
                ThermalDiagnostics.shared.recordFrame()   // 렌더 전 하트비트(프리즈 진단: 프레임 도착 여부)
                #endif
                self?.render(sampleBuffer)
            }
        }

        /// 프리셋 변경 → 즉시 스왑(L3 Decision B, 크로스페이드 없음). 같은 값이면 무시.
        /// 필터가 아직 로컬 캐시에 없으면 프리페치를 킥하고, 준비 전까지 패스스루로 폴백.
        /// animated 파라미터는 시그니처 호환용(L3에선 무시 — 즉시 전환).
        func setPreset(slug: String, animated: Bool) {
            lock.lock()
            let changed = slug != currentSlug
            currentSlug = slug
            let needFetch = changed && slug != MellowFilterRoster.originalSlug && liveFilters[slug] == nil
            lock.unlock()
            if needFetch { prefetch(slug) }
        }

        /// LUTStore에서 영속 필터를 가져와 로컬 캐시에 보관(off videoQueue). slug당 동시 1건으로 dedupe.
        /// nil(로스터 밖 slug)이면 캐시하지 않음 → render는 계속 패스스루. 크래시 없음.
        /// 스토어 쪽이 로드 보장(loadedCube)이라 transient 실패는 없다 — nil은 영구 케이스뿐.
        private func prefetch(_ slug: String) {
            lock.lock()
            let alreadyInFlight = prefetchInFlight.contains(slug)
            if !alreadyInFlight { prefetchInFlight.insert(slug) }
            lock.unlock()
            guard !alreadyInFlight else { return }

            Task { [weak self] in
                let filter = await LUTStore.shared.livePreviewFilter(for: slug)
                guard let self else { return }
                self.lock.lock()
                if let filter { self.liveFilters[slug] = filter }
                self.prefetchInFlight.remove(slug)
                self.lock.unlock()
                // 다음 프레임(30fps+)에서 자연히 반영됨 — 강제 리드로우 불필요.
            }
        }

        /// videoQueue에서 호출. 방향 보정/다운스케일 → LUT(inputImage만 교체) → 메인 렌더.
        private func render(_ sampleBuffer: CMSampleBuffer) {
            guard let oriented = processor.process(sampleBuffer,
                                                   orientation: sessionManager.currentOrientation)
            else { return }

            lock.lock()
            let slug = currentSlug
            // "original" 또는 미준비 slug → nil = 아이덴티티 패스스루.
            let filter = (slug == MellowFilterRoster.originalSlug) ? nil : liveFilters[slug]
            // 복구 가드: 로스터 slug인데 필터가 없으면(최초 프리페치가 레이스/오류로 유실) 재킥.
            // dedupe(진행 중 1건) + 캡(5회) — 죽은 블롭에서 프레임레이트 재시도 금지(발열).
            var rekick = false
            if filter == nil, slug != MellowFilterRoster.originalSlug,
               !prefetchInFlight.contains(slug),
               prefetchAttempts[slug, default: 0] < Self.maxPrefetchRetries {
                prefetchAttempts[slug, default: 0] += 1
                rekick = true
            }
            lock.unlock()
            if rekick { prefetch(slug) }

            let output: CIImage
            if let filter {
                filter.setValue(oriented, forKey: kCIInputImageKey)   // 프레임당 inputImage만 교체
                output = filter.outputImage ?? oriented               // 실패해도 원본(블랙 프레임 금지)
            } else {
                output = oriented
            }

            // 정지 시 freeze용으로 마지막 프레임 참조만 보관(변환 없음 = 값싸다).
            lock.lock()
            lastImage = output
            lock.unlock()

            // L3.5: 메인 홉 제거 — videoQueue에서 직접 오프메인 렌더(CA 커밋 사이클 이탈).
            view?.renderFrame(output)

            // 렌더 직후 필터의 inputImage 해제 (프리즈 수정). 영속 필터가 마지막 카메라 버퍼
            // (CVPixelBuffer 참조 CIImage)를 물고 있으면, 빠른 필터 전환 시 전환된 필터 수만큼
            // 버퍼가 고정되어 캡처 풀(~6개)이 고갈되고 captureOutput이 **조용히** 멈춘다(프리뷰
            // 프리즈, 세션 재구성으로만 복구). renderFrame의 ciContext.render가 동기 인코드하고
            // 커밋된 커맨드버퍼가 GPU 완료까지 자원을 붙들므로, 여기서 지워도 프레임은 안전하다.
            filter?.setValue(nil, forKey: kCIInputImageKey)
        }

        /// 세션 정지 시 마지막 프레임을 뷰의 freeze 오버레이로 얹는다(메인에서 호출 — updateUIView).
        /// 보관된 프레임이 없으면(최초 시작 전) 아무것도 하지 않아 오버레이는 숨김 유지(빈 화면/크래시 없음).
        func freezeLastFrame() {
            lock.lock()
            let image = lastImage
            lock.unlock()
            guard let image else { return }   // 최초 카메라 시작: 보관 프레임 없음 → freeze 없음
            view?.freeze(with: image)
            // freeze()가 UIImage로 변환을 마쳤으니 CIImage는 더 필요 없다. 세션 정지 동안
            // 카메라 버퍼(CVPixelBuffer)를 물고 있지 않도록 즉시 해제(캡처 풀 고정 방지 —
            // 위 inputImage 해제와 같은 결함 클래스). 재시작 후 첫 프레임이 자연히 다시 채운다.
            lock.lock()
            lastImage = nil
            lock.unlock()
        }

        #if DEBUG
        // MARK: MTRACE5 스톨 워치독 (텔레메트리 전용 — 클리어/복구/상태 변경 없음)
        //
        // "카메라가 살아 있어야 하는데(isPreviewRunning=true) 렌더 커밋이 2s 넘게 없고
        // freeze 오버레이가 떠 있다" = 오버레이가 영구히 남는 스톨 후보. arm 사이클당 1회
        // MTRACE5 EVENT만 기록한다. 오탐 방지: 기준 시각 = max(arm, 마지막 커밋)이라
        // 세션 재시작 갭(~0.3s)·첫 설치 셰이더 컴파일(~230ms)은 2s 임계에 걸리지 않는다.

        /// 워치독 상태는 전부 이 시리얼 큐에 confined — 잠금 불필요.
        private let watchdogQueue = DispatchQueue(label: "com.lunalism.mellow.mtrace5", qos: .utility)
        private var watchdog: DispatchSourceTimer?        // watchdogQueue에서만 접근
        private var watchdogArmTime: CFTimeInterval = 0   // watchdogQueue에서만 접근
        private var stallLatched = false                  // watchdogQueue에서만 접근
        /// 엣지 검출용 직전 값. updateUIView(메인)에서만 접근.
        private var lastPreviewRunning = false

        /// updateUIView(메인)에서 매 업데이트 호출되지만 **실제 엣지에서만** arm/disarm한다 —
        /// 반복되는 true 업데이트가 armTime을 덮어쓰면 타임아웃이 영원히 리셋되므로 가드 필수.
        func updateStallWatchdog(isPreviewRunning: Bool) {
            guard isPreviewRunning != lastPreviewRunning else { return }
            lastPreviewRunning = isPreviewRunning
            if isPreviewRunning { armStallWatchdog() } else { disarmStallWatchdog() }
        }

        private func armStallWatchdog() {
            let armTime = CACurrentMediaTime()   // 엣지 시점(메인)에서 캡처 — 큐 지연과 무관
            watchdogQueue.async { [weak self] in
                guard let self else { return }
                self.watchdog?.cancel()
                self.watchdogArmTime = armTime
                self.stallLatched = false        // arm 사이클마다 1회 래치 리셋
                let timer = DispatchSource.makeTimerSource(queue: self.watchdogQueue)
                timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
                timer.setEventHandler { [weak self] in self?.stallWatchdogTick() }
                self.watchdog = timer
                timer.resume()
            }
        }

        private func disarmStallWatchdog() {
            watchdogQueue.async { [weak self] in
                guard let self else { return }
                self.watchdog?.cancel()
                self.watchdog = nil
            }
        }

        /// watchdogQueue에서 500ms마다. 판정만 하고 아무것도 고치지 않는다.
        private func stallWatchdogTick() {
            guard !stallLatched else { return }              // arm 사이클당 1회만
            let now = CACurrentMediaTime()
            let lastCommit = ThermalDiagnostics.shared.lastRenderCommitTime()
            let reference = max(watchdogArmTime, lastCommit) // 커밋 0(미시작)이면 arm 기준
            guard now - reference > 2.0 else { return }
            guard let view else { return }                   // 뷰 해제됨 → 이 틱은 스킵
            // isHidden 직접 판독 금지(메인 전용) — 잠금 보호 미러로 오프메인 판독.
            guard view.isOverlayVisibleForDiagnostics else { return }
            stallLatched = true
            ThermalDiagnostics.shared.noteStallDetected(
                sinceMs: Int((now - reference) * 1000),
                overlayVisible: true,
                armAgeMs: Int((now - watchdogArmTime) * 1000))
        }
        #endif
    }
}
