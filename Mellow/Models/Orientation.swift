import Foundation

/// 세션 방향. **2값이다.**
///
/// 계열 내 180도 차이(가로L/가로R, 세로/거꾸로)는 촬영 직후 정규화가 흡수하므로
/// 데이터에는 정방향 클립만 남는다. 근거는 Tasks.md "세션 방향 모델 — 확정".
///
/// **`@Model` 프로퍼티로 직접 두지 않는다.** `#Predicate` 가 enum 을 지원하지 않아
/// 저장은 `String` raw value 로 한다. 이 타입은 API 표면에만 존재한다.
/// 근거는 CLAUDE.md "API 주의사항".
enum Orientation: String, Codable {
    case portrait
    case landscape
}
