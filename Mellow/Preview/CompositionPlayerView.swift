import AVFoundation
import SwiftUI
import UIKit

// AVPlayerLayer 를 SwiftUI 에 얹는 래퍼 (1-13).
//
// 프리뷰 레이어와 같은 방식으로 backing layer 를 쓴다. 서브레이어로 붙이면
// 레이아웃이 바뀔 때마다 frame 을 손으로 맞춰야 한다.

/// backing layer 가 AVPlayerLayer 인 UIView.
final class PlayerContainerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // layerClass 를 지정했으므로 항상 성립한다.
        layer as! AVPlayerLayer
    }
}

struct CompositionPlayerView: UIViewRepresentable {
    let player: AVPlayer
    /// 레이어가 준비되면 컨트롤러에 넘긴다. 첫 프레임 시각을 재는 데 필요하다.
    let onLayerReady: (AVPlayerLayer) -> Void

    func makeUIView(context: Context) -> PlayerContainerUIView {
        let view = PlayerContainerUIView()
        view.backgroundColor = .black
        view.playerLayer.player = player

        // .resizeAspect 로 둔다. 컴포지션 트랙 transform 에 따라 영상이 어떤
        // 모양으로 표시되는지 봐야 하므로, 채워서 잘라내면 안 된다.
        view.playerLayer.videoGravity = .resizeAspect

        let layer = view.playerLayer
        Task { @MainActor in
            onLayerReady(layer)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerContainerUIView, context: Context) {}
}
