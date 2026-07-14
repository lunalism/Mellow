import SwiftUI

@main
struct MellowApp: App {
    init() {
        #if DEBUG
        // 열/메모리 진단 계측 — 전용 시리얼 큐에서 항상 켜짐(메인스레드 무부하). 하루 테스트 관측용.
        ThermalDiagnostics.shared.start()
        #endif

        // L2 스토어 프리로드 — 런치·메인 블로킹 없이 백그라운드 1회. Debug/Release 공통
        // (릴리스에서도 큐브 캐시를 채워야 필터가 렌더된다).
        Task.detached(priority: .utility) {
            await LUTStore.shared.preload()
            #if DEBUG
            // L2 색/축순서 검증(순서 보장 — 색 검증은 프리로드된 큐브에 의존).
            await LUTColorVerification.run()
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            // colorScheme은 CameraScreen이 화면별로 결정한다(어두운 chrome=라이트 상태바).
            CameraScreen()
        }
    }
}
