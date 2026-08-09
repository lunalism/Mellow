import AVKit
import SwiftUI

/// 못생겨도 된다. 전체화면 플레이어 하나면 충분하다.
/// Phase 1 이 끝날 때까지 UI 를 다듬지 않는다.
struct CompositionPlayerView: View {

    let player: AVPlayer
    let info: String
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                Text(info)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))

                Button("CLOSE") { onClose() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
