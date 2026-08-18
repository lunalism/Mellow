import Foundation
import SwiftData

/// 최상위 단위. 여행·나들이 같은 이벤트 하나에 10초 컷을 쌓는다.
@Model
final class Session {
    var id: UUID
    var title: String
    var createdAt: Date
    var isClosed: Bool

    /// 세션 방향의 유일한 저장 위치.
    ///
    /// `Orientation` 을 그대로 두지 않는 이유는 `#Predicate` 가 enum 을 지원하지
    /// 않기 때문이다. `Codable` enum 은 `Schema.CompositeAttribute` 로 등록되고
    /// CoreData 가 그 이름으로 키패스를 찾지 못한다 (CLAUDE.md "API 주의사항").
    ///
    /// 바깥에서는 `orientation` / `orientationState` 로만 접근하고, 조회는
    /// 이 타입의 predicate 팩토리를 쓴다. `private` 이므로 바깥에서
    /// `$0.orientation == nil` 같은 코드를 쓸 방법 자체가 없다.
    private var orientationRaw: String?

    /// 세션을 지우면 클립 메타데이터도 함께 사라진다 (2-12).
    /// 파일 삭제는 메타데이터와 별개이며 파일 관리자가 맡는다 (2-3).
    @Relationship(deleteRule: .cascade, inverse: \Clip.session)
    var clips: [Clip]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        orientation: Orientation? = nil,
        isClosed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.orientationRaw = orientation?.rawValue
        self.isClosed = isClosed
        self.clips = []
    }
}

// MARK: - 방향

extension Session {
    /// `orientationRaw` 와 `clips` 에서 읽어내는 네 가지 상태.
    ///
    /// `Orientation?` 만으로는 **정상적인 미정과 값 손상이 구분되지 않는다.**
    /// 전부 `nil` 로 보이지만 성질이 다르다. 정합성 복구(2-16)가 이들을
    /// 갈라 봐야 하므로 상태를 타입으로 남긴다.
    ///
    /// **`orientationRaw` 가 `nil` 이 되는 경로는 둘이다.** 아직 첫 클립이
    /// 없어서(정상) 와, 값이 있었는데 사라져서(손상). 클립 유무가 이 둘을
    /// 가른다 — 클립이 있는데 방향이 없는 세션은 존재할 수 없는 상태다.
    /// 이를 `.unset` 으로 뭉뚱그리면 2-8이 "아직 미정" 으로 보고 다음 촬영에
    /// 방향을 다시 맡기며, 반대 계열이 나오면 **한 세션에 세로·가로가 섞여
    /// 정규화로도 복구되지 않는다.**
    ///
    /// 저장 프로퍼티를 늘리지 않는다 — 네 상태 전부 `orientationRaw` 와
    /// `clips` 관계에서 파생된다.
    enum OrientationState: Equatable {
        /// 아직 방향이 정해지지 않았다. 첫 클립이 정한다. **정상 상태다.**
        case unset
        /// 클립이 있는데 방향 값이 없다. 존재할 수 없는 상태이며 복구 대상이다.
        case missing
        /// 정상적으로 해석된 방향.
        case decided(Orientation)
        /// 값이 있는데 `Orientation` 으로 해석되지 않는다. 복구 대상이다.
        case corrupted(rawValue: String)
    }

    /// 표시 경로에서도 불리므로 크래시하거나 throw 하지 않는다.
    ///
    /// `clips` 를 읽으면 관계가 fault in 되지만, 세션 목록이 어차피 클립 수와
    /// 총 길이를 표시하므로(PRD 4.2) 실질적인 추가 비용은 없다.
    var orientationState: OrientationState {
        guard let raw = orientationRaw else {
            return clips.isEmpty ? .unset : .missing
        }
        guard let value = Orientation(rawValue: raw) else { return .corrupted(rawValue: raw) }
        return .decided(value)
    }

    /// 해석된 방향만 돌려준다. `.decided` 가 아닌 세 상태는 전부 `nil` 이며,
    /// 그들을 구분해야 하면 `orientationState` 를 본다.
    ///
    /// 계산 프로퍼티이므로 `@Transient` 는 필요 없다. 애초에 저장 대상이 아니다.
    ///
    /// **읽기 전용이다 (2-8).** 예전에는 setter 가 있었는데, getter 가
    /// `.decided` 일 때만 값을 주므로 `if session.orientation == nil { 세팅 }`
    /// 이 **`.missing` 과 `.corrupted` 까지 덮어썼다.** 손상된 세션의 방향을
    /// 다음 촬영이 새로 정하게 되고, 계열이 다르면 한 세션에 세로·가로가
    /// 섞여 정규화로도 복구되지 않는다. 쓰기는 아래 `decideOrientation(_:)`
    /// 하나로 모으고 가드를 그 안에 둔다 — **함정을 API 표면에서 없앤다.**
    var orientation: Orientation? {
        guard case .decided(let value) = orientationState else { return nil }
        return value
    }

    /// **첫 클립이 세션 방향을 정한다 (2-8).**
    ///
    /// `orientationState` 가 `.unset` 일 때만 값을 쓴다. 나머지 셋은 전부
    /// 거절한다 — 이유가 상태마다 다르다.
    ///
    /// - `.decided` — 이미 정해졌다. 두 번째 이후 클립이 전부 여기 해당하며
    ///   **정상 경로다.** 거절이 실패를 뜻하지 않는다
    /// - `.missing` / `.corrupted` — 클립이 있는데 방향이 없거나 깨진 상태다.
    ///   여기에 새 방향을 붙이면 **먼저 찍힌 클립과 계열이 다를 수 있고,
    ///   계열 간 혼재는 정규화로 복구되지 않는다.** 복구는 2-16 의 몫이다
    ///
    /// **가드를 `#Predicate` 로 옮길 수 없다.** `orientationState` 가 `clips`
    /// 관계를 세기 때문이다. 조회는 저장 상태 기준(`orientationRawIsNil()`),
    /// 판정은 코드에서 — 이 모델의 구조가 그렇다.
    ///
    /// 호출은 **클립 기록과 같은 저장 단위 안에서** 일어나야 한다. 그 자리가
    /// `ClipStore.save` 의 `alsoApply` 다.
    ///
    /// - Returns: 이번 호출이 실제로 방향을 정했으면 `true`.
    ///   **`@discardableResult` 를 붙이지 않는다** — 이 값을 봐야 저장 실패
    ///   시 되돌릴 대상인지 알 수 있다. 남의 결정을 지우면 안 된다
    func decideOrientation(_ orientation: Orientation) -> Bool {
        guard orientationState == .unset else { return false }
        orientationRaw = orientation.rawValue
        return true
    }

    /// **저장 실패 복구 전용 (2-8).** `ClipStore.save` 의 `revertOnFailure` 가
    /// 부른다. 다른 곳에서 부를 일이 없다.
    ///
    /// `decideOrientation` 이 `true` 를 돌려준 **바로 그 호출**만 되돌린다.
    /// 판단은 호출부가 한다 — 이 함수는 상태를 보지 않으므로, 이미 정해져
    /// 있던 방향에 대고 부르면 남의 결정을 지운다.
    ///
    /// **2-10 의 `resetOrientation()` 과 다른 것이다.** 이름을 겹치지 않게
    /// 둔 이유가 그것이다.
    ///
    /// - 이쪽은 **저장이 실패해 없던 일이 된 것**을 인메모리에서 지운다.
    ///   스토어에는 애초에 들어가지 않았다
    /// - 저쪽은 **클립이 0개가 되어 방향을 다시 물어야 하는 것**을 저장까지
    ///   해서 초기화한다
    func undoOrientationDecision() {
        orientationRaw = nil
    }
}

// MARK: - 표시 이름 (2-6)

extension Session {
    /// 목록·상세에 보여줄 이름. **저장하지 않고 매번 만든다.**
    ///
    /// `title` 이 비어 있으면 `createdAt` 에서 `8월 9일 세션` 형태를 만든다
    /// (PRD F-01). 자동 생성분을 `title` 에 넣어 저장하지 않는 이유는 둘이다.
    ///
    /// - `createdAt` 에서 언제든 다시 만들 수 있는 값이다. "파생 가능한 값을
    ///   저장하지 않는다" 는 원칙이 여기에도 걸린다
    /// - **사용자가 입력한 제목과 자동 생성분이 구분되어야 한다.** 저장해
    ///   버리면 둘이 같은 문자열이 되어, 나중에 제목 편집이 붙을 때 "사용자가
    ///   지은 이름" 과 "우리가 지어준 이름" 을 가릴 수 없다. 빈 문자열이
    ///   "아직 이름을 짓지 않았다" 를 뜻한다
    ///
    /// 공백만 입력한 경우도 비어 있는 것으로 본다. 저장 시점에 다듬지만
    /// (`SessionStore`), 밖에서 만든 `Session` 이 들어올 수 있으므로 여기서도 본다.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.autoTitle(for: createdAt) : trimmed
    }

    /// `8월 9일 세션`.
    ///
    /// **`DateFormatter` 를 쓰지 않는다.** 처음에는 로케일을 `ko_KR` 로 고정한
    /// `static let` 포매터를 뒀는데, `DateFormatter` 가 non-Sendable 이라
    /// **언어 모드 6에서 깨지는 곳을 3건에서 4건으로 늘린다.** 그 3건이라는
    /// 숫자가 2-18 재검토의 근거이므로(CLAUDE.md "Swift 언어 모드") 조용히
    /// 바꿀 수 없다. `Calendar` 로 월·일만 뽑아 조립하면 정적 상태도, 로케일
    /// 의존도 함께 사라지고 문자열은 같다.
    ///
    /// **타임존은 기기 로컬이다.** 사용자에게는 그것이 맞다 — 밤 11시에 찍은
    /// 세션이 다음 날짜로 보이면 안 된다. 대신 파생값이라 **여행하면 이름이
    /// 하루 밀려 보일 수 있다**(서울에서 만든 세션이 LA 에서 하루 앞으로).
    /// 감수한 트레이드오프이며 근거는 Tasks.md 2-6 참고.
    static func autoTitle(for date: Date) -> String {
        let calendar = Calendar.current
        return "\(calendar.component(.month, from: date))월 "
            + "\(calendar.component(.day, from: date))일 세션"
    }
}

// MARK: - 이어가기 (2-7)

extension Session {
    /// **이어서 촬영할 수 있는 세션인가.**
    ///
    /// `isClosed == false` 이고 방향이 `.unset` 또는 `.decided` 일 때만 참이다.
    ///
    /// **`.missing` / `.corrupted` 를 제외하는 것이 이 판정의 핵심이다.**
    /// 클립이 있는데 방향이 없거나 깨진 세션을 이어가면 2-8 이 그 세션의
    /// 방향을 **다시** 정하게 되고, 먼저 찍힌 클립과 계열이 다르면 한 세션에
    /// 세로·가로가 섞인다. 정규화는 계열 내 180도만 흡수하므로 그 상태는
    /// 복구되지 않는다.
    ///
    /// 제외된 세션은 사라지지 않는다. 목록에는 그대로 보이고 미리보기·삭제도
    /// 된다. 복구는 2-16 의 몫이며, 복구되면 다시 이어갈 수 있게 된다.
    ///
    /// **계산 프로퍼티이므로 `#Predicate` 에 넣을 수 없다.** `orientationState`
    /// 가 `clips` 관계를 세기 때문이며, enum 미지원과는 별개의 제약이다.
    /// 조회는 `inProgress()` 로 하고 이 판정은 Swift 에서 한다 (`SessionStore`).
    var isResumable: Bool {
        guard !isClosed else { return false }
        switch orientationState {
        case .unset, .decided:
            return true
        case .missing, .corrupted:
            return false
        }
    }
}

// MARK: - 조회

/// predicate 는 전부 여기 모아 둔다. `orientationRaw` 가 `private` 이라
/// 타입 밖에서는 만들 수 없고, 안에서 만들 때도 **enum 이 아니라 `String` 을
/// 캡처해야 한다.**
extension Session {
    /// 방향이 일치하는 세션.
    static func matching(_ orientation: Orientation) -> Predicate<Session> {
        let raw: String? = orientation.rawValue
        return #Predicate<Session> { $0.orientationRaw == raw }
    }

    /// 방향 값이 저장돼 있지 않은 세션. **저장 상태 기준이지 의미 기준이 아니다.**
    ///
    /// **`.unset` 과 `.missing` 을 함께 반환한다.** 둘 다 `orientationRaw` 가
    /// `nil` 이라 조회로는 갈리지 않는다. 전자는 첫 클립이 아직 없는 정상
    /// 상태이고 후자는 클립이 있는데 값이 사라진 손상 상태다.
    /// **구분해야 하면 결과를 `orientationState` 로 다시 걸러라** — 특히
    /// "방향 미정이니 첫 클립이 정하면 된다" 로 이어지는 경로(2-8)에서는
    /// 반드시 걸러야 한다. `.missing` 세션에 그 판단을 적용하면 방향이 다른
    /// 계열로 다시 정해져 한 세션에 세로·가로가 섞인다.
    ///
    /// `$0.orientation == nil` 은 컴파일이 통과하고 런타임에 ObjC 예외로 죽는다.
    /// 그 형태를 쓸 일이 없도록 여기서 대신 만든다.
    static func orientationRawIsNil() -> Predicate<Session> {
        #Predicate<Session> { $0.orientationRaw == nil }
    }

    /// 진행 중인 세션 (2-7). 있으면 새로 만들지 않고 이어간다.
    static func inProgress() -> Predicate<Session> {
        #Predicate<Session> { !$0.isClosed }
    }
}

// MARK: - 클립 순서

extension Session {
    /// `order` 기준으로 정렬된 클립.
    ///
    /// SwiftData 의 to-many 관계는 순서를 보장하지 않는다. `clips` 를 그대로
    /// 쓰면 병합·필름스트립·그리드가 제각기 다른 순서를 볼 수 있으므로
    /// 순서가 필요한 곳은 전부 이쪽을 쓴다.
    var orderedClips: [Clip] {
        clips.sorted { $0.order < $1.order }
    }
}
