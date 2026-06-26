import SwiftUI
import AVFoundation

/// raw 라이브 프리뷰 (Stage 1). `AVCaptureVideoPreviewLayer`로 세션 영상을
/// 그대로 표시한다. 필터는 다음 단계에서 Metal 경로로 입힌다.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        // 첫 프레임 도착 전에는 레이어가 비어 있으므로 배경을 페이퍼로 둔다(검정 플래시 방지).
        view.backgroundColor = UIColor(Color.mellowPaper)
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }

    /// 백킹 레이어가 AVCaptureVideoPreviewLayer인 UIView.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
