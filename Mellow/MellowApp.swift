import SwiftUI

@main
struct MellowApp: App {
    init() {
        #if DEBUG
        // Stage L1: 번들 .cube 9종 구조 검증(콘솔). 런치·메인 블로킹 없이 백그라운드 1회.
        DispatchQueue.global(qos: .utility).async {
            LUTVerification.runParseCheck()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // colorScheme은 CameraScreen이 화면별로 결정한다(어두운 chrome=라이트 상태바).
            CameraScreen()
        }
    }
}
