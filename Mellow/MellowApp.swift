import SwiftUI
import SwiftData

@main
struct MellowApp: App {

    /// 컨테이너 생성은 실패할 수 있으므로 결과를 들고 있는다.
    ///
    /// **크래시시키지 않는다.** v0.1 은 마이그레이션이 없어 실패는 사실상
    /// 복구 불가 상황이지만, 그렇다고 `fatalError` 로 죽이면 사용자는 앱이
    /// 그냥 고장난 것으로만 본다. 무엇보다 **이미 찍어둔 영상은 무사하다** —
    /// 영상은 `Documents` 에 있고 스토어는 `Application Support` 에 따로 있다.
    /// 죽는 대신 그 사실을 알려서, 사용자가 앱을 지워 영상까지 날리는 선택을
    /// 하지 않게 한다.
    ///
    /// 실패해도 **스토어를 새로 만들거나 지우지 않는다.** 메타데이터를 버리면
    /// 영상 파일이 전부 고아가 된다.
    private let container: Result<ModelContainer, Error>

    init() {
        container = Result { try MellowModelContainer.make() }
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                ContentView()
                    .modelContainer(container)
            case .failure(let error):
                StoreUnavailableView(error: error)
            }
        }
    }
}

/// 스토어를 열지 못했을 때. 화면은 3-15 에서 제대로 만든다.
private struct StoreUnavailableView: View {
    let error: Error

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("저장된 기록을 열 수 없습니다")
                    .font(.headline)
                Text("촬영한 영상은 지워지지 않았습니다.\n앱을 지우지 마시고 다시 실행해 주세요.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                Text(verbatim: "\(error)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(32)
        }
    }
}
