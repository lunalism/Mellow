import AVFoundation
import SwiftUI
import UIKit

/// 뷰의 backing layer 자체를 AVCaptureVideoPreviewLayer 로 만든다.
///
/// addSublayer 방식은 쓰지 않는다. 서브레이어로 붙이면 frame 을 수동으로
/// 따라가야 하고 회전·크기 변화마다 어긋난다. layerClass 면 bounds 를 자동으로 따른다.
final class CameraPreviewUIView: UIView {

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    /// layerClass 가 보장하므로 캐스팅은 항상 성공한다.
    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    /// 윈도우에 붙거나 빠질 때 알린다. nil 이면 빠진 것이다.
    var onWindowChange: ((AVCaptureVideoPreviewLayer?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window == nil ? nil : previewLayer)
    }
}

struct CameraPreviewView: UIViewRepresentable {

    let controller: CameraController

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill

        // 여기서 코디네이터를 만들지 않는다. 이 시점의 뷰는 아직 윈도우에 없어서
        // preview 각도가 0 으로 고정된다.
        view.onWindowChange = { layer in
            if let layer {
                controller.attach(previewLayer: layer)
            } else {
                controller.detach()
            }
        }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}
