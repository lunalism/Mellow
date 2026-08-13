import Foundation
import SwiftData

/// 앱 전체가 쓰는 단 하나의 `ModelContainer`.
///
/// # 메인 컨텍스트 전용 (확정)
///
/// **별도 `ModelContext` 나 `ModelActor` 를 만들지 않는다.** 모든 읽기·쓰기는
/// `@Environment(\.modelContext)` 로 받는 메인 컨텍스트에서 한다.
///
/// - 2-3 ~ 2-12 가 전부 메인 컨텍스트로 충분하다
/// - 백그라운드에서 SwiftData 를 쓰는 곳은 **2-18의 `Clip.duration` 갱신
///   한 곳뿐**이다. 정규화가 끝난 뒤의 쓰기 한 번이라 급하지 않고,
///   메인으로 hop 하면 된다
/// - `ModelActor` 를 지금 깔면 컨텍스트 간 동기화 · `PersistentIdentifier`
///   전달 · 두 컨텍스트가 같은 객체를 다르게 보는 문제가 **지금 없는 문제로
///   새로 들어온다**
/// - 나중에 필요해지면 추가하는 것은 국소적이지만, 지금 깔았다가 걷어내는
///   것은 그 위에 쌓인 2-3 ~ 2-12 를 전부 건드려야 한다
///
/// `ModelContext` 는 SDK 에서 `@available(*, unavailable, message: "contexts
/// cannot be shared across concurrency contexts")` 로 `Sendable` 이 막혀 있다.
/// 컨텍스트를 격리 경계 너머로 넘기는 것은 애초에 지원되지 않는 사용법이다.
enum MellowModelContainer {

    /// 메타데이터 저장 파일.
    ///
    /// **영상 파일과 다른 디렉터리에 둔다.**
    /// - 메타데이터: `Library/Application Support/Mellow.store`
    /// - 영상: `Documents/sessions/{uuid}/clips/` (2-3)
    ///
    /// `Application Support` 를 쓰는 이유는 이 파일이 앱이 관리하는 내부
    /// 데이터이기 때문이다. `Documents` 는 사용자에게 보이는 자리이며
    /// 파일 공유를 켜면 그대로 노출된다.
    ///
    /// **둘이 갈라져 있다는 사실이 2-16에서 중요해진다.** 한쪽만 살아남는
    /// 복원 시나리오가 성립하므로 고아 파일과 고아 메타데이터가 양방향으로
    /// 생길 수 있다.
    static let storeURL = URL.applicationSupportDirectory.appending(path: "Mellow.store")

    /// 스키마는 `Session` / `Clip` 둘이다. `Orientation` 은 `String` 으로
    /// 저장되므로 스키마에 등록되지 않는다 (2-1).
    static func make() throws -> ModelContainer {
        // iOS 는 Application Support 디렉터리를 만들어 두지 않는다.
        // 없으면 스토어 생성이 실패하므로 여기서 보장한다.
        try FileManager.default.createDirectory(
            at: URL.applicationSupportDirectory,
            withIntermediateDirectories: true
        )

        let configuration = ModelConfiguration(url: storeURL)
        return try ModelContainer(for: Session.self, Clip.self, configurations: configuration)
    }
}
