import SwiftUI
import AVFoundation

/// 라이브 프리뷰 (Stage 2~). SwiftUI ↔ `MetalPreviewView`(MTKView) 브리지.
///
/// 세션의 VideoDataOutput 프레임을 `FrameProcessor`로 CIImage로 바꿔 Metal 뷰에
/// 넘긴다. raw 패스스루(필터 없음) — 화면은 기존 프리뷰 레이어와 동일하게 보인다.
struct CameraPreviewView: UIViewRepresentable {
    let sessionManager: CameraSessionManager

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionManager: sessionManager)
    }

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {}

    /// 프레임 콜백(videoQueue)을 받아 CIImage 변환 후 메인에서 뷰에 전달.
    final class Coordinator {
        private let sessionManager: CameraSessionManager
        private let processor = FrameProcessor()
        private weak var view: MetalPreviewView?

        init(sessionManager: CameraSessionManager) {
            self.sessionManager = sessionManager
        }

        func attach(to view: MetalPreviewView) {
            self.view = view
            sessionManager.onFrame = { [weak self] sampleBuffer in
                self?.render(sampleBuffer)
            }
        }

        /// videoQueue에서 호출. CIImage 변환(가벼움) 후 메인에서 렌더 트리거.
        private func render(_ sampleBuffer: CMSampleBuffer) {
            guard let image = processor.process(sampleBuffer,
                                                orientation: sessionManager.currentOrientation)
            else { return }
            DispatchQueue.main.async { [weak self] in
                self?.view?.image = image
            }
        }
    }
}
