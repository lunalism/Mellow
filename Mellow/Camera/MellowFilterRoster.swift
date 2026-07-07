import Foundation

/// 9종 필터 로스터의 단일 진실 공급원 (Stage L1).
///
/// `slug`이 영속 식별자다 — 표시 순서·표시 이름과 분리되어 저장 키로 쓰인다.
/// (비파괴 저장: 원본 + slug. 순서를 바꿔도, 이름을 바꿔도 저장된 사진의 룩은 유지.)
/// `fileName`은 번들 리소스의 정확한 basename(공백 포함, 확장자 제외).
enum MellowFilterRoster {

    struct Entry {
        let order: Int
        let displayName: String
        let slug: String
        let fileName: String
    }

    /// 표시 순서. 기본값은 `sunday`(1번 Hazy 아님).
    static let entries: [Entry] = [
        Entry(order: 1, displayName: "Hazy",     slug: "hazy",     fileName: "01 Hazy"),
        Entry(order: 2, displayName: "Ember",    slug: "ember",    fileName: "02 Ember"),
        Entry(order: 3, displayName: "Sunday",   slug: "sunday",   fileName: "03 Sunday"),
        Entry(order: 4, displayName: "Honey",    slug: "honey",    fileName: "04 Honey"),
        Entry(order: 5, displayName: "Hush",     slug: "hush",     fileName: "05 Hush"),
        Entry(order: 6, displayName: "Winter",   slug: "winter",   fileName: "06 Winter"),
        Entry(order: 7, displayName: "Travel",   slug: "travel",   fileName: "07 Travel"),
        Entry(order: 8, displayName: "Moonrise", slug: "moonrise", fileName: "08 Moonrise"),
        Entry(order: 9, displayName: "Color",    slug: "color",    fileName: "09 Color"),
    ]

    /// 기본 선택 (Spec: Sunday).
    static let defaultSlug = "sunday"

    /// **합성 Original** slug — 로스터에 실제 엔트리는 없다(룩업-미스 = 패스스루). 프리뷰·저장·UI가
    /// 공유하는 단일 리터럴 → "무필터"가 세 경로에서 동일하게 흐른다(GATE 3).
    static let originalSlug = "original"

    /// slug으로 엔트리 조회.
    static func entry(forSlug slug: String) -> Entry? {
        entries.first { $0.slug == slug }
    }
}
