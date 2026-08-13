import Foundation

// 프리뷰가 뜨기까지 어느 구간에서 시간이 걸리는지 재는 계측기.
//
// 백그라운드 복귀 후 프리뷰가 늦게 나타나는 문제(PRD 6장 "프리뷰 표시까지 1초 이내")를
// 추측이 아니라 숫자로 확인하기 위한 것이다. 원인이 확정되고 수정이 끝나면 걷어낸다.
//
// 메인과 sessionQueue 양쪽에서 찍히므로 잠금으로 보호한다. 단조 시계를 쓴다 —
// 벽시계는 시스템 시각이 조정되면 음수 구간이 나올 수 있다.
final class CaptureTrace: @unchecked Sendable {

    static let shared = CaptureTrace()

    /// 계측 로그를 찍을지.
    ///
    /// 기본은 꺼둔다 — 켜두면 백그라운드를 오갈 때마다 콘솔이 채워져
    /// 정작 봐야 할 로그가 묻힌다. 릴리스 빌드에서는 아예 컴파일되지 않는다.
    ///
    /// 다시 재려면 실행 인자에 `-MellowTrace` 를 넣는다:
    ///   Xcode: Scheme > Run > Arguments Passed On Launch
    ///   CLI:   xcrun devicectl device process launch --console \
    ///            --device <UDID> com.lunalism.mellow -MellowTrace
    #if DEBUG
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-MellowTrace")
    #else
    static let isEnabled = false
    #endif

    private let lock = NSLock()
    /// 단발 이벤트의 시각 기준점. 프로세스 시작 이후 경과로 찍어 서로 대조하기 쉽게 한다.
    private let baseline = DispatchTime.now().uptimeNanoseconds
    /// 현재 구간의 시작 시각. nil 이면 계측 중이 아니다.
    private var startedAt: UInt64?
    /// 직전 mark 시각. 구간별 증분을 내는 데 쓴다.
    private var previousAt: UInt64?

    private init() {}

    /// 새 계측 구간을 시작한다. 이전 구간이 남아 있으면 덮어쓴다.
    func begin(_ label: String) {
        guard Self.isEnabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        startedAt = now
        previousAt = now
        lock.unlock()

        print("[trace] ▶ \(label)")
    }

    /// 구간 안의 한 지점을 찍는다. begin 이후가 아니면 무시한다.
    func mark(_ label: String) {
        guard Self.isEnabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds

        lock.lock()
        guard let startedAt else {
            lock.unlock()
            return
        }
        let sinceStart = now - startedAt
        let sincePrevious = now - (previousAt ?? startedAt)
        previousAt = now
        lock.unlock()

        print("[trace]   \(Self.pad(label))"
              + "  t=\(Self.milliseconds(sinceStart))ms"
              + "  +\(Self.milliseconds(sincePrevious))ms")
    }

    /// 구간과 무관한 단발 이벤트.
    ///
    /// `mark` 는 `begin` 이후에만 찍히고 t= 가 직전 구간 시작 기준이라, 녹화·회전처럼
    /// 구간 밖에서 흩어져 일어나는 일에는 맞지 않는다. 이쪽은 항상 찍히고 프로세스
    /// 시작 이후 경과 시각을 붙여, 여러 이벤트를 시간순으로 대조할 수 있게 한다.
    func event(_ label: String) {
        guard Self.isEnabled else { return }
        let elapsed = DispatchTime.now().uptimeNanoseconds - baseline
        print("[trace] · \(Self.milliseconds(elapsed))ms  \(label)")
    }

    /// 구간을 닫는다. 이후의 mark 는 무시된다.
    func end(_ label: String) {
        guard Self.isEnabled else { return }
        mark(label)
        lock.lock()
        startedAt = nil
        previousAt = nil
        lock.unlock()
    }

    // MARK: - 형식

    private static func milliseconds(_ nanoseconds: UInt64) -> String {
        String(format: "%.1f", Double(nanoseconds) / 1_000_000)
    }

    /// 로그 열을 맞춘다. 한글은 폭이 넓지만 Xcode 콘솔에서 읽는 데는 충분하다.
    private static func pad(_ label: String) -> String {
        let width = 32
        guard label.count < width else { return label }
        return label + String(repeating: " ", count: width - label.count)
    }
}
