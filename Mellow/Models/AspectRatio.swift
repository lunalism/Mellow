import CoreGraphics

/// 촬영/프리뷰 화면 비율 (Spec §3 · §8).
///
/// **WYSIWYG 핵심:** 프리뷰와 캡처가 반드시 같은 `AspectRatio`를 사용한다.
/// 프리뷰만 9:16으로 두고 캡처를 4:3으로 저장하는 식의 분기를 만들지 말 것.
enum AspectRatio: String, CaseIterable, Codable, Identifiable {
    case ratio9x16   // 9:16 세로 (현재 기본값)
    case ratio4x3    // 4:3
    case ratio1x1    // 1:1
    case ratio2x1    // 2:1

    var id: String { rawValue }

    /// 프리뷰·캡처 공통 기본값. 제품 결정으로 9:16(세로).
    /// (Spec §3 문서상 기본은 4:3 — 문서는 추후 갱신.)
    static let `default`: AspectRatio = .ratio9x16

    /// 세로 방향 폭÷높이. < 1 이면 세로로 길다.
    /// 프리뷰 카드 크기 산정과 캡처 크롭에 **공통**으로 쓰는 단일 출처.
    var portraitWidthOverHeight: CGFloat {
        switch self {
        case .ratio9x16: return 9.0 / 16.0
        case .ratio4x3:  return 3.0 / 4.0   // 4:3 사진을 세로로 → 3:4
        case .ratio1x1:  return 1.0
        case .ratio2x1:  return 1.0 / 2.0
        }
    }
}
