import SwiftUI
import AVFoundation
import CoreImage

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

        /// LUTStore에서 영속 필터를 1회 가져와 로컬 캐시에 보관(off videoQueue).
        /// nil(미상/미로딩)이면 캐시하지 않음 → render는 계속 패스스루. 크래시 없음.
        private func prefetch(_ slug: String) {
            Task { [weak self] in
                guard let filter = await LUTStore.shared.livePreviewFilter(for: slug) else { return }
                self?.lock.lock()
                self?.liveFilters[slug] = filter
                self?.lock.unlock()
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
            lock.unlock()

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
        }

        /// 세션 정지 시 마지막 프레임을 뷰의 freeze 오버레이로 얹는다(메인에서 호출 — updateUIView).
        /// 보관된 프레임이 없으면(최초 시작 전) 아무것도 하지 않아 오버레이는 숨김 유지(빈 화면/크래시 없음).
        func freezeLastFrame() {
            lock.lock()
            let image = lastImage
            lock.unlock()
            guard let image else { return }   // 최초 카메라 시작: 보관 프레임 없음 → freeze 없음
            view?.freeze(with: image)
        }
    }
}
