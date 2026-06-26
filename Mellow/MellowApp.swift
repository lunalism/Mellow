import SwiftUI

@main
struct MellowApp: App {
    var body: some Scene {
        WindowGroup {
            CameraScreen()
                // v1은 라이트 모드 고정 (다크모드는 v1.1).
                .preferredColorScheme(.light)
        }
    }
}
