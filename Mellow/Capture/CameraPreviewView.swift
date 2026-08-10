import AVFoundation
import SwiftUI
import UIKit

// AVCaptureVideoPreviewLayer 를 SwiftUI 에 얹는 래퍼.
//
// 레이어를 뷰의 backing layer 로 쓴다(layerClass). 서브레이어로 붙이면
// 레이아웃이 바뀔 때마다 frame 을 손으로 맞춰줘야 한다.

/// backing layer 가 AVCaptureVideoPreviewLayer 인 UIView.
final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass 를 지정했으므로 항상 성립한다.
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// 레이어가 준비되면 컨트롤러에 넘긴다. 회전 코디네이터가 이 레이어를 필요로 한다.
    let onLayerReady: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        // 뷰 생성 도중에 컨트롤러 상태를 건드리면 "Modifying state during view update"
        // 경고가 난다. 한 틱 미뤄서 넘긴다.
        let layer = view.previewLayer
        Task { @MainActor in
            onLayerReady(layer)
        }

        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}
