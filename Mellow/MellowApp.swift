import SwiftUI

@main
struct MellowApp: App {
    init() {
        #if DEBUG
        // LUT DEBUG 하네스 — 런치·메인 블로킹 없이 백그라운드 1회.
        // L1 구조 검증 → L2 스토어 프리로드 → L2 색/축순서 검증(순서 보장).
        Task.detached(priority: .utility) {
            LUTVerification.runParseCheck()
            await LUTStore.shared.preload()
            await LUTColorVerification.run()
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
