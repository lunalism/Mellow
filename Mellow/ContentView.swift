// Phase 1 스파이크용 임시 호스트. Phase 3에서 촬영 화면(3-1~3-7)으로 교체한다.

import SwiftUI

struct ContentView: View {

    @State private var controller = CameraController()
    @State private var composition = CompositionController()

    var body: some View {
        ZStack(alignment: .topLeading) {
            CameraPreviewView(controller: controller)
                .ignoresSafeArea()

            RotationDebugOverlay(controller: controller)
                .padding()

            VStack {
                Spacer()

                Text(composition.libraryState + "  |  " + composition.buildState
                     + (composition.readyMilliseconds.map { String(format: "  |  ready %.0f ms", $0) } ?? ""))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 10) {
                    ForEach(composition.groups) { group in
                        Button(group.label) { composition.play(group: group) }
                    }
                    if composition.groups.count >= 2 {
                        Button("섞기") { composition.playMixed() }
                    }
                    Button("RESCAN") { Task { await composition.scan() } }
                }
                .buttonStyle(.bordered)
                .tint(.white)

                HStack(spacing: 12) {
                    Button(controller.isRecording ? "STOP" : "REC") {
                        controller.toggleRecording()
                    }
                    .tint(controller.isRecording ? .red : .accentColor)

                    Button("COMPARE") { controller.compareRecorded() }

                    Button("SAVE") { controller.saveLastClipToPhotos() }
                        .tint(.green)
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            await controller.start()
            await composition.scan()
        }
        .onDisappear { controller.stop() }
        .fullScreenCover(isPresented: $composition.isPlayerPresented) {
            if let player = composition.player {
                CompositionPlayerView(
                    player: player,
                    info: composition.buildState,
                    onClose: { composition.dismissPlayer() }
                )
            }
        }
    }
}

#Preview {
    ContentView()
}
