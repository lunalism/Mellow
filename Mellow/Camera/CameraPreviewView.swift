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
    let selectedFilter: FilterPreset

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionManager: sessionManager)
    }

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView()
        context.coordinator.attach(to: view)
        context.coordinator.setPreset(selectedFilter, animated: false)
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {
        // selectedFilter가 바뀌면 즉시 스왑(스와이프/스트립 공통 경로).
        context.coordinator.setPreset(selectedFilter, animated: true)
    }

    /// 프레임 콜백(videoQueue) → LUT 적용 → 메인에서 뷰에 전달.
    final class Coordinator {
        private let sessionManager: CameraSessionManager
        private let processor = FrameProcessor()
        private weak var view: MetalPreviewView?

        // 상태 보호(잠금): render는 videoQueue, setPreset/프리페치 완료는 다른 컨텍스트.
        private let lock = NSLock()
        private var currentSlug: String = FilterPreset.original.id
        /// slug → 영속 CIFilter 로컬 캐시. LUTStore(actor)에서 1회 가져와 보관 →
        /// render()는 프레임마다 **동기**로 읽는다(프레임당 await/필터 재생성 없음).
        private var liveFilters: [String: CIFilter] = [:]

        init(sessionManager: CameraSessionManager) {
            self.sessionManager = sessionManager
        }

        func attach(to view: MetalPreviewView) {
            self.view = view
            prefetch(MellowFilterRoster.defaultSlug)   // 기본값(sunday) 첫 프레임부터 준비
            sessionManager.onFrame = { [weak self] sampleBuffer in
                self?.render(sampleBuffer)
            }
        }

        /// 프리셋 변경 → 즉시 스왑(L3 Decision B, 크로스페이드 없음). 같은 값이면 무시.
        /// 필터가 아직 로컬 캐시에 없으면 프리페치를 킥하고, 준비 전까지 패스스루로 폴백.
        /// animated 파라미터는 시그니처 호환용(L3에선 무시 — 즉시 전환).
        func setPreset(_ preset: FilterPreset, animated: Bool) {
            let slug = preset.id
            lock.lock()
            let changed = slug != currentSlug
            currentSlug = slug
            let needFetch = changed && slug != FilterPreset.original.id && liveFilters[slug] == nil
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
            let filter = (slug == FilterPreset.original.id) ? nil : liveFilters[slug]
            lock.unlock()

            let output: CIImage
            if let filter {
                filter.setValue(oriented, forKey: kCIInputImageKey)   // 프레임당 inputImage만 교체
                output = filter.outputImage ?? oriented               // 실패해도 원본(블랙 프레임 금지)
            } else {
                output = oriented
            }

            // L3.5: 메인 홉 제거 — videoQueue에서 직접 오프메인 렌더(CA 커밋 사이클 이탈).
            view?.renderFrame(output)
        }
    }
}
