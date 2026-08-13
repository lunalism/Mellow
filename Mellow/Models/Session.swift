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
    var orientation: Orientation? {
        get {
            guard case .decided(let value) = orientationState else { return nil }
            return value
        }
        set { orientationRaw = newValue?.rawValue }
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

    /// 방향이 아직 정해지지 않은 세션.
    ///
    /// `$0.orientation == nil` 은 컴파일이 통과하고 런타임에 ObjC 예외로 죽는다.
    /// 그 형태를 쓸 일이 없도록 여기서 대신 만든다.
    static func orientationUnset() -> Predicate<Session> {
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
