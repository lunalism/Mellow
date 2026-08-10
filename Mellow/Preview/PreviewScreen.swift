import AVFoundation
import SwiftUI

// 1-13 / 1-14 확인용 미리보기 화면. UI 는 3-12 에서 제대로 만든다.
//
// 화면에 띄우는 값은 전부 이음새 검증에 쓰인다 — 어느 시각에 클립이 바뀌는지
// 알아야 그 지점에서 검은 프레임이나 끊김을 눈으로 대조할 수 있다.
struct PreviewScreen: View {
    let urls: [URL]
    let onClose: () -> Void

    @StateObject private var controller = PreviewPlayerController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CompositionPlayerView(player: controller.player) { layer in
                controller.attach(playerLayer: layer)
            }
            .ignoresSafeArea()

            info
            closeButton
        }
        .task {
            await controller.prepare(urls: urls)
        }
        .onDisappear {
            controller.stop()
        }
    }

    // MARK: - 정보 표시

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("재생 시각", String(format: "%.3fs / %.3fs",
                                CMTimeGetSeconds(controller.currentTime),
                                CMTimeGetSeconds(controller.duration)))
            row("클립", "\(controller.currentClipIndex + 1) / \(controller.clipCount)")
            row("첫 프레임", controller.firstFrameMilliseconds
                .map { String(format: "%.1fms", $0) } ?? "측정 중")
            if let size = controller.renderedSize {
                row("표시 규격", "\(Int(size.width)) x \(Int(size.height))")
            }
            if case .failed(let message) = controller.state {
                row("실패", message)
            }

            // 멈칫이 한 번이라도 잡히면 눈에 띄어야 한다.
            if controller.stallEvents.isEmpty {
                row("멈칫", "없음")
            } else {
                row("멈칫", "\(controller.stallEvents.count)건")
                Text(controller.stallEvents.suffix(3).joined(separator: "\n"))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // * 표시가 붙은 경계 앞에 1.67ms 무음이 들어간다. 청취 대조용.
            Text("경계 " + controller.boundaries.enumerated()
                .map { index, time in
                    String(format: "%.2f", CMTimeGetSeconds(time))
                        + (controller.silenceGapBoundaries.contains(index) ? "*" : "")
                }
                .joined(separator: " · "))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Text("* = 앞 경계에 1.67ms 무음 삽입")
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 72, alignment: .leading)
            Text(value)
        }
    }

    private var closeButton: some View {
        Button("닫기") { onClose() }
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
