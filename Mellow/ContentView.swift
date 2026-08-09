// Phase 1 스파이크용 임시 호스트. Phase 3에서 촬영 화면(3-1~3-7)으로 교체한다.

import SwiftUI

struct ContentView: View {

    @State private var controller = CameraController()

    var body: some View {
        ZStack(alignment: .topLeading) {
            CameraPreviewView(controller: controller)
                .ignoresSafeArea()

            RotationDebugOverlay(controller: controller)
                .padding()
        }
        .task { await controller.start() }
        .onDisappear { controller.stop() }
    }
}

#Preview {
    ContentView()
}
