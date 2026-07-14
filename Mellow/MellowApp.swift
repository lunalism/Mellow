import SwiftUI

@main
struct MellowApp: App {
    init() {
        #if DEBUG
        // 열/메모리 진단 계측 — 전용 시리얼 큐에서 항상 켜짐(메인스레드 무부하). 하루 테스트 관측용.
        ThermalDiagnostics.shared.start()

        // LUT DEBUG 하네스 — 런치·메인 블로킹 없이 백그라운드 1회.
        // L2 스토어 프리로드 → L2 색/축순서 검증(순서 보장 — 색 검증은 프리로드된 큐브에 의존).
        Task.detached(priority: .utility) {
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
