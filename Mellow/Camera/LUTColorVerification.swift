#if DEBUG
import Foundation
import CoreImage
import CoreGraphics

/// DEBUG 전용 색 정확도 + 축순서 검증 하네스 (Stage L2).
///
/// 라이브 60fps 프리뷰를 건드리기 전에, 각 LUT이 알려진 sRGB 스와치를 어떻게 매핑하는지
/// 헤드리스로 렌더해 콘솔에 찍고, 카타스트로픽한 R/B 축·채널 스왑을 자동 단언한다.
/// WYSIWYG: sRGB 입력 → sRGB 저작 LUT → sRGB 워킹 → sRGB 리드백(세 색공간 모두 sRGB).
enum LUTColorVerification {

    private struct Swatch {
        let name: String
        let r: CGFloat, g: CGFloat, b: CGFloat
    }

    private static let swatches: [Swatch] = [
        Swatch(name: "red",    r: 1.00, g: 0.00, b: 0.00),
        Swatch(name: "green",  r: 0.00, g: 1.00, b: 0.00),
        Swatch(name: "blue",   r: 0.00, g: 0.00, b: 1.00),
        Swatch(name: "black",  r: 0.00, g: 0.00, b: 0.00),
        Swatch(name: "gray18", r: 0.18, g: 0.18, b: 0.18),
        Swatch(name: "gray50", r: 0.50, g: 0.50, b: 0.50),
        Swatch(name: "white",  r: 1.00, g: 1.00, b: 1.00),
        Swatch(name: "skin",   r: 0.85, g: 0.65, b: 0.50),
        Swatch(name: "warmHi", r: 0.95, g: 0.90, b: 0.78),
        Swatch(name: "shadow", r: 0.15, g: 0.13, b: 0.10),
    ]

    static func run() async {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else {
            print("[LUT-COLOR] sRGB unavailable — skipping")
            return
        }
        // 라이브 컨텍스트와 무관한 전용 one-off 컨텍스트.
        let ctx = CIContext(options: [
            .workingColorSpace: srgb,
            .cacheIntermediates: false,
        ])

        for entry in MellowFilterRoster.entries {
            let slug = entry.slug
            guard let cube = await LUTStore.shared.cube(for: slug),
                  let filter = await LUTStore.shared.makeFilter(for: slug) else {
                print("[LUT-COLOR] \(slug) — unavailable (not loaded)")
                continue
            }

            print("[LUT-COLOR] \(slug) (N=\(cube.dimension))")
            for sw in swatches {
                guard let input = swatchImage(sw, srgb: srgb) else {
                    print("   \(pad(sw.name)) — could not build input")
                    continue
                }
                filter.setValue(input, forKey: kCIInputImageKey)
                guard let out = filter.outputImage,
                      let px = render(out, ctx: ctx, srgb: srgb) else {
                    print("   \(pad(sw.name)) — no output")
                    continue
                }
                report(slug: slug, sw: sw, px: px)
            }
        }
    }

    // MARK: - Rendering

    private static func swatchImage(_ sw: Swatch, srgb: CGColorSpace) -> CIImage? {
        guard let color = CIColor(red: sw.r, green: sw.g, blue: sw.b, alpha: 1, colorSpace: srgb) else {
            return nil
        }
        return CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
    }

    /// float 정밀도(.RGBAf) 리드백 — 8-bit는 작은 오차를 숨긴다. 중앙 1px.
    private static func render(_ image: CIImage, ctx: CIContext, srgb: CGColorSpace) -> (r: Float, g: Float, b: Float)? {
        var buf = [Float](repeating: 0, count: 4)
        buf.withUnsafeMutableBytes { raw in
            ctx.render(image,
                       toBitmap: raw.baseAddress!,
                       rowBytes: 16,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf,
                       colorSpace: srgb)
        }
        return (buf[0], buf[1], buf[2])
    }

    // MARK: - Reporting + assertions

    private static func report(slug: String, sw: Swatch, px: (r: Float, g: Float, b: Float)) {
        print("   \(pad(sw.name)) in(\(f(sw.r)),\(f(sw.g)),\(f(sw.b))) -> out(\(f(px.r)),\(f(px.g)),\(f(px.b)))")

        if !inRange(px.r) || !inRange(px.g) || !inRange(px.b) {
            print("   ⚠️ OUT OF RANGE")
        }
        // R/B 스왑은 빨강을 파랑 우세로 뒤집는다 — 정상 웜 그레이드와 카테고리컬하게 구분됨.
        if sw.name == "red", px.r < px.b - 0.02 {
            print("   ⚠️ AXIS/CHANNEL SWAP SUSPECT on \(slug) (red)")
        }
        if sw.name == "blue", px.b < px.r - 0.02 {
            print("   ⚠️ AXIS/CHANNEL SWAP SUSPECT on \(slug) (blue)")
        }
    }

    private static func inRange(_ x: Float) -> Bool { x >= -0.0001 && x <= 1.0001 }
    private static func f(_ x: CGFloat) -> String { String(format: "%.4f", x) }
    private static func f(_ x: Float) -> String { String(format: "%.4f", x) }
    private static func pad(_ s: String) -> String { s.padding(toLength: 6, withPad: " ", startingAt: 0) }
}
#endif
