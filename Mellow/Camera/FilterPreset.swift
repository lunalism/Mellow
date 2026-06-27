import CoreImage
import CoreImage.CIFilterBuiltins

/// 필터 프리셋 (Phase 1 Spec §7). 데이터 주도 — id·이름·체인만 정의하면 8종으로 확장 가능.
///
/// Stage 3a는 첫 인상(방향성)만. 최종 룩·강도는 3b에서 튜닝. LUT는 Phase 2.
/// 모든 룩은 CIFilter 프리미티브로만 구성(브랜드 LUT 미사용).
struct FilterPreset: Identifiable {
    let id: String              // 비파괴 저장 키(원본 + filterID). 캡처 단계에서 사용.
    let displayName: String
    private let build: (CIImage, Double) -> CIImage

    init(id: String, displayName: String, build: @escaping (CIImage, Double) -> CIImage) {
        self.id = id
        self.displayName = displayName
        self.build = build
    }

    /// 입력 CIImage에 필터 체인 적용. intensity는 향후 강도 슬라이더용(현재 1.0 고정).
    func makeChain(for input: CIImage, intensity: Double = 1.0) -> CIImage {
        build(input, intensity)
    }
}

// MARK: - 큐레이션 카탈로그 (Stage 3a: Original / Sunday / Honey)

extension FilterPreset {
    /// 비교용 원본(패스스루).
    static let original = FilterPreset(id: "original", displayName: "Original") { image, _ in
        image
    }

    /// 기본값. 따뜻한 앰버, 낮춘 채도, 들린 그림자 → 나른한 일요일 오후.
    static let sunday = FilterPreset(id: "sunday", displayName: "Sunday") { image, _ in
        var img = colorControls(image, saturation: 0.80, contrast: 0.94)
        img = liftShadows(img, black: 0.20, white: 0.97)   // 강한 페이드 + 들린 블랙
        img = channelGains(img, r: 1.06, g: 1.00, b: 0.90) // 따뜻하게(들린 블랙도 웜톤화)
        return img
    }

    /// 더 따뜻하고 생생하게. 골든 하이라이트, 약한 페이드 → 밝은 데일리 스냅샷.
    static let honey = FilterPreset(id: "honey", displayName: "Honey") { image, _ in
        var img = colorControls(image, saturation: 1.15, contrast: 1.10) // 비비드 + 대비↑
        img = liftShadows(img, black: 0.09, white: 1.00)   // 약한 페이드
        img = channelGains(img, r: 1.10, g: 1.01, b: 0.86) // Sunday보다 더 웜/골드
        return img
    }

    /// 전체 카탈로그(스트립/스와이프 순서). Phase 2에서 8종으로 확장.
    static let all: [FilterPreset] = [.original, .sunday, .honey]

    /// 비파괴 저장의 filterID → 프리셋 조회. 미상이면 Original(패스스루)로 안전 폴백.
    /// 썸네일·익스포트가 저장된 룩을 재현할 때 쓰는 단일 진입점.
    static func preset(for id: String) -> FilterPreset {
        all.first { $0.id == id } ?? .original
    }

    /// 기본 선택 (Spec §2.3 = Sunday).
    static let `default`: FilterPreset = .sunday
}

// MARK: - CIFilter 빌딩 블록

private func colorControls(_ image: CIImage, saturation: Float, contrast: Float, brightness: Float = 0) -> CIImage {
    let f = CIFilter.colorControls()
    f.inputImage = image
    f.saturation = saturation
    f.contrast = contrast
    f.brightness = brightness
    return f.outputImage ?? image
}

/// 채널별 게인(따뜻함). r>1·b<1 = 웜.
private func channelGains(_ image: CIImage, r: CGFloat, g: CGFloat, b: CGFloat) -> CIImage {
    let f = CIFilter.colorMatrix()
    f.inputImage = image
    f.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
    f.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
    f.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
    f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    return f.outputImage ?? image
}

/// 그림자를 들어올려 페이드(블랙 포인트 상승). [0,1] → [black, white] 선형 리매핑.
private func liftShadows(_ image: CIImage, black: CGFloat, white: CGFloat = 1.0) -> CIImage {
    let f = CIFilter.toneCurve()
    f.inputImage = image
    f.point0 = CGPoint(x: 0.00, y: black)
    f.point1 = CGPoint(x: 0.25, y: black + 0.25 * (white - black))
    f.point2 = CGPoint(x: 0.50, y: black + 0.50 * (white - black))
    f.point3 = CGPoint(x: 0.75, y: black + 0.75 * (white - black))
    f.point4 = CGPoint(x: 1.00, y: white)
    return f.outputImage ?? image
}
