import SwiftUI
import AVFoundation
import QuartzCore  // CACurrentMediaTime

/// 라이브 프리뷰 (Stage 2~). SwiftUI ↔ `MetalPreviewView`(MTKView) 브리지.
///
/// 세션의 VideoDataOutput 프레임을 `FrameProcessor`로 처리(방향 보정 + 필터 체인 +
/// 프리셋 크로스페이드)한 뒤 Metal 뷰에 넘긴다. 필터·크로스페이드는 videoQueue에서
/// 수행되고, Metal 뷰는 받은 CIImage를 GPU로 렌더하기만 한다.
struct CameraPreviewView: UIViewRepresentable {
    let sessionManager: CameraSessionManager
    let selectedFilter: FilterPreset

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionManager: sessionManager)
    }

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView()
        context.coordinator.attach(to: view)
        context.coordinator.setPreset(selectedFilter, animated: false) // 최초엔 크로스페이드 없이
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {
        // selectedFilter가 바뀌면 크로스페이드 시작(스와이프/스트립 공통 경로).
        context.coordinator.setPreset(selectedFilter, animated: true)
    }

    /// 프레임 콜백(videoQueue) → 필터/크로스페이드 적용 → 메인에서 뷰에 전달.
    final class Coordinator {
        private let sessionManager: CameraSessionManager
        private let processor = FrameProcessor()
        private weak var view: MetalPreviewView?

        // 크로스페이드 상태(잠금으로 보호: render는 videoQueue, setPreset은 메인).
        private let crossfadeDuration: CFTimeInterval = 0.18  // Spec §4.2 (~180ms)
        private let lock = NSLock()
        private var currentPreset: FilterPreset = .original
        private var previousPreset: FilterPreset?
        private var crossfadeStart: CFTimeInterval?

        init(sessionManager: CameraSessionManager) {
            self.sessionManager = sessionManager
        }

        func attach(to view: MetalPreviewView) {
            self.view = view
            sessionManager.onFrame = { [weak self] sampleBuffer in
                self?.render(sampleBuffer)
            }
        }

        /// 프리셋 변경. animated면 직전 프리셋에서 크로스페이드. 같은 프리셋이면 무시.
        /// 상태가 하나뿐이라 빠른 연속 전환 시 큐가 쌓이지 않고 **최신값이 이긴다**(Spec §4.4).
        func setPreset(_ preset: FilterPreset, animated: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard preset.id != currentPreset.id else { return }
            if animated {
                previousPreset = currentPreset
                crossfadeStart = CACurrentMediaTime()
            } else {
                previousPreset = nil
                crossfadeStart = nil
            }
            currentPreset = preset
        }

        /// videoQueue에서 호출. 방향 보정 → 필터(+크로스페이드) → 메인에서 렌더 트리거.
        private func render(_ sampleBuffer: CMSampleBuffer) {
            guard let oriented = processor.process(sampleBuffer,
                                                   orientation: sessionManager.currentOrientation)
            else { return }

            // 크로스페이드 상태 스냅샷 + 완료 처리.
            lock.lock()
            let current = currentPreset
            var previous = previousPreset
            var progress: Double = 1
            if let start = crossfadeStart, previous != nil {
                progress = min(1, (CACurrentMediaTime() - start) / crossfadeDuration)
                if progress >= 1 {            // 완료 → 상태 정리
                    previousPreset = nil
                    crossfadeStart = nil
                    previous = nil
                }
            }
            lock.unlock()

            let currentImage = processor.apply(current, to: oriented)
            let output: CIImage
            if let previous, progress < 1 {
                let previousImage = processor.apply(previous, to: oriented)
                output = processor.crossfade(from: previousImage, to: currentImage, progress: progress)
            } else {
                output = currentImage
            }

            DispatchQueue.main.async { [weak self] in
                self?.view?.image = output
            }
        }
    }
}
