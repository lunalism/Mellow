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

    /// 상세 뷰 풀프레임 캐시 (Stage 4b-3). 화면 크기라 객체가 크므로 **소수만** 별도 보관 →
    /// 작은 정사각 캐시를 밀어내지 않고, 메모리 압박 시 자동 축출.
    private let fullCache = NSCache<NSString, UIImage>()

    private init() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [.name: "MellowThumbnail"])
        } else {
            ciContext = CIContext(options: [.name: "MellowThumbnail"])  // 폴백(시뮬 등)
        }
        cache.countLimit = 240   // 대량 캡처에서도 메모리 상한(초과분은 자동 축출)
        fullCache.countLimit = 6 // 큰 풀프레임은 최근 몇 장만(재진입 즉시, 나머지는 재렌더)
    }

    /// 원본 파일 + filterID → 필터 적용된 작은 UIImage(4b-1 좌하단 썸네일용). **백그라운드 호출**.
    func render(originalURL: URL, filterID: String) -> UIImage? {
        renderFullFrame(originalURL: originalURL, filterID: filterID, maxPixelSize: maxPixelSize)
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

    // MARK: - 상세 뷰 풀프레임 (Stage 4b-3) — 9:16 전체 프레이밍, 화면 크기 다운스케일

    /// 메인에서 안전한 캐시 조회(렌더 안 함). 있으면 즉시 표시(재진입 시 깜빡임 없음).
    func cachedFullFrame(id: UUID, maxPixelSize: Int) -> UIImage? {
        fullCache.object(forKey: Self.fullKey(id, maxPixelSize))
    }

    /// 캐시 우선 **풀프레임(9:16 전체, 크롭 없음)** 이미지. **백그라운드 호출**. 상세 뷰 전용.
    /// 화면 크기로 다운스케일한 뒤 필터를 건다 — 풀해상도(2268×4032)를 굳이 처리하지 않는다
    /// (화면에선 동일하게 보이고 훨씬 가볍다).
    func fullFrameThumbnail(id: UUID, url: URL, filterID: String, maxPixelSize: Int) -> UIImage? {
        let key = Self.fullKey(id, maxPixelSize)
        if let hit = fullCache.object(forKey: key) { return hit }
        guard let image = renderFullFrame(originalURL: url, filterID: filterID, maxPixelSize: maxPixelSize) else { return nil }
        fullCache.setObject(image, forKey: key)
        return image
    }

    private static func fullKey(_ id: UUID, _ max: Int) -> NSString { "\(id.uuidString)#full\(max)" as NSString }

    /// 다운스케일 → 공유 필터 체인 → 풀프레임(크롭 없음) 래스터. 4b-1·프리뷰·셀과 **동일한 체인**.
    /// 처음으로 (거의) 전체 해상도에 필터를 적용하는 지점.
    ///
    /// TODO(그레인/비네팅/헐레이션 단계 — Stage 4a 메모): **픽셀 단위** 효과가 들어오면 이 상세
    ///   렌더(≈화면 크기)와 작은 프리뷰/셀 렌더의 **해상도 차이를 보정**해야 한다(그레인 시드 스케일,
    ///   비네팅 반경, 헐레이션 블러 반경 등). 지금은 색 전용 체인이라 해상도 무관 → 모든 렌더가 동일하게 보인다.
    private func renderFullFrame(originalURL: URL, filterID: String, maxPixelSize: Int) -> UIImage? {
        guard let small = Self.downsampled(originalURL, maxPixelSize: maxPixelSize) else { return nil }
        let input = CIImage(cgImage: small)
        let filtered = FilterPreset.preset(for: filterID).makeChain(for: input)   // 미상 id는 Original 폴백
        // 색 전용 체인이라 extent는 입력과 동일 → 입력 extent로 안전하게 래스터.
        guard let cg = ciContext.createCGImage(filtered, from: input.extent,
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
