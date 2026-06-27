import UIKit
import CoreImage
import ImageIO

/// 보관함 썸네일 렌더러 (Phase 1 Spec §6.4 · Stage 4b-1).
///
/// **비파괴/WYSIWYG:** 저장된 무필터 원본을 **다운스케일**한 뒤, 저장된 `filterID`의
/// `FilterPreset.makeChain`(라이브 프리뷰와 **동일한 단일 체인**)으로 렌더한다 — 필터를
/// 파일에 베이크하지 않고, 두 번째 필터 구현도 만들지 않는다. 그래서 썸네일 색이 촬영
/// 당시 프리뷰와 일치한다.
///
/// 성능: 풀해상도(2268×4032)를 절대 필터링하지 않는다. ImageIO 썸네일 디코드로 작게
/// 줄인 뒤에만 필터를 건다. 프리뷰와 **별도** CIContext를 써서 서로 GPU 작업을 막지 않음.
final class CaptureThumbnailRenderer {
    static let shared = CaptureThumbnailRenderer()

    private let ciContext: CIContext
    private let renderColorSpace = CGColorSpaceCreateDeviceRGB()
    /// 썸네일 한 변 최대 px. UI는 52pt(≈156px @3x)라 여유 있게 작게 잡는다.
    private let maxPixelSize = 400

    /// 렌더된 썸네일 인메모리 캐시 (Stage 4b-2). capture.id + 변형(정사각 side)으로 키잉 →
    /// 그리드 스크롤 시 셀이 재생성돼도 재렌더하지 않는다. NSCache라 스레드 안전 + 메모리 압박 시 자동 축출.
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [.name: "MellowThumbnail"])
        } else {
            ciContext = CIContext(options: [.name: "MellowThumbnail"])  // 폴백(시뮬 등)
        }
        cache.countLimit = 240   // 대량 캡처에서도 메모리 상한(초과분은 자동 축출)
    }

    /// 원본 파일 + filterID → 필터 적용된 작은 UIImage. **백그라운드에서 호출**, UI는 호출측이 메인에서.
    func render(originalURL: URL, filterID: String) -> UIImage? {
        guard let small = Self.downsampled(originalURL, maxPixelSize: maxPixelSize) else { return nil }
        let input = CIImage(cgImage: small)
        // 라이브 프리뷰와 같은 체인. 미상 id는 Original(패스스루)로 안전 폴백.
        let filtered = FilterPreset.preset(for: filterID).makeChain(for: input)
        // 색 전용 체인이라 extent는 입력과 동일 → 입력 extent로 안전하게 래스터.
        guard let cg = ciContext.createCGImage(filtered,
                                               from: input.extent,
                                               format: .RGBA8,
                                               colorSpace: renderColorSpace) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - 정사각 그리드 셀 (Stage 4b-2)

    /// 메인에서 안전한 캐시 조회(렌더하지 않음). 있으면 즉시 표시 → 재스크롤 시 깜빡임 없음.
    func cachedSquare(id: UUID, side: Int) -> UIImage? {
        cache.object(forKey: Self.squareKey(id, side))
    }

    /// 캐시 우선 **정사각** 썸네일. **백그라운드에서 호출**(미스 시 다운스케일→필터→크롭→래스터).
    /// 그리드 셀용 1:1 중앙 크롭은 표시 전용 — 저장 원본(9:16)은 그대로다.
    func squareThumbnail(id: UUID, url: URL, filterID: String, side: Int) -> UIImage? {
        let key = Self.squareKey(id, side)
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = renderSquare(originalURL: url, filterID: filterID, side: side) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func squareKey(_ id: UUID, _ side: Int) -> NSString {
        "\(id.uuidString)#sq\(side)" as NSString
    }

    /// 다운스케일 → 공유 필터 체인 → 중앙 정사각 크롭. **풀해상도를 필터링하지 않는다.**
    /// side*2로 디코드하면 우리 비율(9:16·4:3·1:1·2:1) 모두에서 짧은 변 ≥ side가 보장된다.
    private func renderSquare(originalURL: URL, filterID: String, side: Int) -> UIImage? {
        guard let small = Self.downsampled(originalURL, maxPixelSize: side * 2) else { return nil }
        let input = CIImage(cgImage: small)
        let filtered = FilterPreset.preset(for: filterID).makeChain(for: input)   // 4b-1·프리뷰와 동일 체인
        let ext = filtered.extent
        let s = min(ext.width, ext.height)
        let crop = CGRect(x: ext.midX - s / 2, y: ext.midY - s / 2, width: s, height: s).integral
        guard let cg = ciContext.createCGImage(filtered, from: crop,
                                               format: .RGBA8, colorSpace: renderColorSpace) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// ImageIO 썸네일 디코드 — 풀해상도를 메모리에 올리지 않고 작게 디코드(+EXIF 방향 보정).
    private static func downsampled(_ url: URL, maxPixelSize: Int) -> CGImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // 저장본은 이미 .up이라 사실상 no-op
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
