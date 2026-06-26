import SwiftUI

@main
struct MellowApp: App {
    var body: some Scene {
        WindowGroup {
            // colorScheme은 CameraScreen이 화면별로 결정한다(어두운 chrome=라이트 상태바).
            CameraScreen()
        }
    }
}
