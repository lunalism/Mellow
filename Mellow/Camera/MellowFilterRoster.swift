import SwiftUI

/// 9종 필터 로스터의 단일 진실 공급원 (Stage L1).
///
/// `slug`이 영속 식별자다 — 표시 순서·표시 이름과 분리되어 저장 키로 쓰인다.
/// (비파괴 저장: 원본 + slug. 순서를 바꿔도, 이름을 바꿔도 저장된 사진의 룩은 유지.)
/// `fileName`은 번들 리소스의 정확한 basename(공백 포함, 확장자 제외).
/// `swatch`는 필터별 표시 스와치(장식용 — 인포 시트 등). 룩의 대표 톤을 딴 고정색.
enum MellowFilterRoster {

    struct Entry {
        let order: Int
        let displayName: String
        let slug: String
        let fileName: String
        let swatch: Color
    }

    /// 표시 순서. 기본값은 `sunday`(1번 Hazy 아님).
    static let entries: [Entry] = [
        Entry(order: 1, displayName: "Hazy",     slug: "hazy",     fileName: "01 Hazy",     swatch: Color(hex: 0xC9C2B8)),
        Entry(order: 2, displayName: "Ember",    slug: "ember",    fileName: "02 Ember",    swatch: Color(hex: 0xC97B5A)),
        Entry(order: 3, displayName: "Sunday",   slug: "sunday",   fileName: "03 Sunday",   swatch: .mellowAmber),  // = #C97F3E
        Entry(order: 4, displayName: "Honey",    slug: "honey",    fileName: "04 Honey",    swatch: Color(hex: 0xD9A441)),
        Entry(order: 5, displayName: "Hush",     slug: "hush",     fileName: "05 Hush",     swatch: Color(hex: 0xA8ADB5)),
        Entry(order: 6, displayName: "Winter",   slug: "winter",   fileName: "06 Winter",   swatch: Color(hex: 0x9FB4C7)),
        Entry(order: 7, displayName: "Travel",   slug: "travel",   fileName: "07 Travel",   swatch: Color(hex: 0x7FA08C)),
        Entry(order: 8, displayName: "Moonrise", slug: "moonrise", fileName: "08 Moonrise", swatch: Color(hex: 0x8B87A8)),
        Entry(order: 9, displayName: "Color",    slug: "color",    fileName: "09 Color",    swatch: Color(hex: 0xC46A79)),
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

    /// slug → 사람이 읽는 표시명. 로스터에 있으면 그 displayName, 없으면 "Original"로 폴백한다.
    /// **합성 Original**(로스터 엔트리 없음)과 미상/레거시 slug 둘 다 여기서 "Original"로 접힌다
    /// — 미상 slug이 와도 크래시·원시 문자열 노출 없이 표시명이 나오는 안전망(표시명 전용).
    static func displayName(forSlug slug: String) -> String {
        entry(forSlug: slug)?.displayName ?? "Original"
    }

    /// slug → 표시 스와치(장식용). 로스터에 없으면(합성 Original·미상/레거시 slug)
    /// `.mellowAccent`로 안전 폴백 — 크래시 없음, 브랜드 앰버.
    static func swatchColor(forSlug slug: String) -> Color {
        entry(forSlug: slug)?.swatch ?? .mellowAccent
    }
}
