import Foundation

// 방향 불일치 시 녹화 차단 (2-9).
//
// # UIKit 을 import 하지 않는다
//
// 판정 소스는 `UIDevice.current.orientation` 인데(2-9 결정 (A)) **그 타입을
// 여기까지 들이지 않는다.** UIKit 은 macOS 에서 못 쓰므로 `UIDeviceOrientation`
// 을 인자로 받으면 Mac 하네스에서 이 판정을 돌릴 수 없다(실측: `no such module
// 'UIKit'`).
//
// 그래서 **경계를 계열에서 자른다.**
//
//   UIDeviceOrientation  ──(UIKit 이 판정)──▶  Orientation?  ──▶  RecordingGate
//   앱에만 있다              .isPortrait          계열               여기부터 순수
//                            .isLandscape
//
// 왼쪽 화살표가 `UIDeviceOrientation.family` 이고 앱에만 있다. **그쪽에는
// 우리 로직이 없다** — UIKit 이 제공하는 `isPortrait` / `isLandscape` 를
// 그대로 부르는 세 줄이라 하네스에서 검증할 것이 없다. 판단이 들어 있는
// 것은 전부 이 파일이고, 이 파일은 값만 넣으면 돌아간다.
//
// **각도→방향 상수 테이블이 어디에도 없다.** 이 경로를 고른 이유가 그것이다
// (CLAUDE.md "각도 값을 방향 상수로 매핑하는 테이블은 만들지 않는다").
enum RecordingGate {

    /// 지금 녹화를 시작해도 되는가.
    enum Decision: Equatable {
        case allowed
        /// 세션 방향과 기기 계열이 다르다. 연관값은 **사용자가 맞춰야 할 방향**이다.
        case blocked(required: Orientation)

        var isBlocked: Bool {
            if case .blocked = self { return true }
            return false
        }

        /// 차단 중이면 맞춰야 할 방향. 아니면 `nil`.
        var required: Orientation? {
            if case .blocked(let orientation) = self { return orientation }
            return nil
        }
    }

    /// 세션 방향과 기기 계열을 대조한다.
    ///
    /// **차단은 한 경우뿐이다** — 세션 방향이 정해져 있고, 기기 계열이 나왔고,
    /// 그 둘이 다를 때. 나머지는 전부 통과다.
    ///
    /// # 계열이 안 나오면 통과시킨다 (2-9 결정 (B))
    ///
    /// `.faceUp` / `.faceDown` / `.unknown` 이 `device == nil` 로 들어온다.
    /// **브이로그를 폰 수평으로 눕혀 찍는 자세는 없으므로** 이 구간은 촬영
    /// 자세가 아니라 폰을 들거나 내릴 때 지나가는 상태다. 막을 이유가 없다.
    ///
    /// **마지막 계열을 기억하지 않는다.** 상태를 만들지 않는 것이 결정이다 —
    /// 실제로 찍는 순간엔 계열이 확실해 기능적 차이가 없고, 차이는 지나가는
    /// 구간에 버튼이 깜빡이느냐뿐이다. 깜빡임이 실기기에서 관찰되면 그때 넣는다.
    ///
    /// # `.unset` 은 차단하지 않는다
    ///
    /// 첫 클립이 세션 방향을 정한다(2-8). 아직 방향이 없는 세션에서 막으면
    /// 세로로도 가로로도 시작할 수 없다.
    ///
    /// # `.missing` / `.corrupted` 는 도달 불가다
    ///
    /// 특별 처리를 만들지 않고 `.unset` 과 같이 통과시킨다. 그 상태의 세션은
    /// `startOrResume` → `resumableSession()` 의 `isResumable` 필터에 걸려
    /// **촬영 화면의 활성 세션이 될 수 없기 때문이다.** 2-8 에서 이 전제를
    /// 확인했고, 같은 이유로 `Session.decideOrientation` 의 `.missing` 거절도
    /// 실기기로는 검증할 수 없어 하네스 4군으로 옮겼다.
    ///
    /// **여기에 분기를 만들면 도달하지 않는 코드가 생긴다.** 만약 이 경로가
    /// 실제로 열린다면 그것은 2-7 의 필터가 깨진 것이고, 그때 고칠 곳은
    /// 여기가 아니라 그쪽이다.
    ///
    /// # 계열 내 180도는 차단하지 않는다
    ///
    /// `Orientation` 이 2값이라 세로/거꾸로가 둘 다 `.portrait`, 가로L/가로R 이
    /// 둘 다 `.landscape` 로 들어온다. 이 함수는 그 차이를 볼 수단이 없고,
    /// **없는 것이 맞다** — 막으면 로우앵글 촬영(확정된 유스케이스)이 막힌다.
    /// 좌우 차이는 2-D 의 정규화가 흡수한다.
    ///
    /// - Parameters:
    ///   - session: 활성 세션의 방향 상태.
    ///   - device: 기기 계열. `UIDeviceOrientation.family` 가 만든다.
    ///     계열이 안 나오면 `nil`.
    static func decide(session: Session.OrientationState,
                       device: Orientation?) -> Decision {
        guard case .decided(let required) = session else { return .allowed }
        guard let device else { return .allowed }
        return device == required ? .allowed : .blocked(required: required)
    }
}
