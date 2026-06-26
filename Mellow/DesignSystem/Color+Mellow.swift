import SwiftUI

// MARK: - 디자인 토큰 (Mellow Design System v0.2 · §7)
//
// 색은 반드시 이 토큰만 사용한다. 순수 검정(#000) 금지 → 들린 블랙(mellowShadow).
// 다크모드는 v1.1. v1은 라이트 모드 고정.

extension Color {
    /// 16진수 코드(0xRRGGBB)로 sRGB 색 생성.
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8)  & 0xff) / 255,
                  blue:  Double( hex        & 0xff) / 255,
                  opacity: alpha)
    }
}

extension Color {
    // MARK: Core — 한낮 햇살
    static let mellowCream  = Color(hex: 0xF6E7C9)
    static let mellowHoney  = Color(hex: 0xEFC98A)
    static let mellowGolden = Color(hex: 0xE0A85C)
    static let mellowAmber  = Color(hex: 0xC97F3E)

    // MARK: Core — 카페 / 빛바랜 필름 / 베이스
    static let mellowLatte      = Color(hex: 0xDCC4A2)
    static let mellowSage       = Color(hex: 0xA8B49B)
    static let mellowDustyRose  = Color(hex: 0xD49C86)
    static let mellowIvory      = Color(hex: 0xFBF8F1)
    static let mellowPaper      = Color(hex: 0xF4EEE1)
    static let mellowLightTan   = Color(hex: 0xEBDFCB)

    // MARK: 분위기 빛 (액센트)
    static let mellowSky        = Color(hex: 0xB4C8CC) // 액센트 한정
    static let mellowSunset     = Color(hex: 0xF0B894)
    static let mellowDreamWash  = Color(hex: 0xF1E5E0)
    static let mellowBleedGlow  = Color(hex: 0xF6CCA0)

    // MARK: 시맨틱 역할
    static let mellowBg            = Color(hex: 0xF4EEE1) // 배경 (페이퍼)
    static let mellowBgRaised      = Color(hex: 0xFBF8F1) // 밝은 배경 (아이보리)
    static let mellowTextPrimary   = Color(hex: 0x4A443A) // 본문 (잉크)
    static let mellowTextSecondary = Color(hex: 0xB0855C) // 보조 (카라멜)
    static let mellowShadow        = Color(hex: 0x3B362E) // 들린 블랙
    static let mellowAccent        = Color(hex: 0xC97F3E) // 주 액센트 (앰버)
    static let mellowBorder        = Color(hex: 0xEBDFCB) // 보더 (라이트탄)
}
