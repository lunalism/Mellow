import Foundation
import CoreImage
import CoreGraphics

/// 인메모리 LUT 스토어 (Stage L2).
///
/// 번들의 `.cube`를 L1 파서로 파싱해 메모리에 보관하고, STATIC 렌더/검증/익스포트 경로용
/// CIColorCubeWithColorSpace 필터를 일회성으로 만들어 준다.
/// - 디스크 캐시 없음(의도적) — 스테일 블롭이 축순서 버그를 가리지 못하도록 매번 신선 파싱.
/// - 라이브 프리뷰용 **영속 인스턴스는 Stage L3로 이연**. 여기선 one-off만.
actor LUTStore {
    static let shared = LUTStore()

    private var cubes: [String: LUTCube] = [:]
    /// 라이브 프리뷰용 영속 필터 — slug당 1개, 최초 1회 생성 후 영구 재사용.
    /// 프레임마다 inputImage만 교체 → 3D 텍스처 재업로드(발열) 방지(L3 #1 열 레버).
    private var liveFilters: [String: CIFilter] = [:]
    /// 큐브는 sRGB로 저작됨 — 파싱·필터 색공간 모두 sRGB로 통일(WYSIWYG).
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private init() {}

    /// 백그라운드 프리로드. 기본값(sunday) 먼저, 나머지 순서대로.
    func preload() async {
        for slug in orderedSlugsDefaultFirst() where cubes[slug] == nil {
            if let cube = loadCube(forSlug: slug) {
                cubes[slug] = cube
            }
        }
    }

    /// 미상/미로딩이면 nil.
    func cube(for slug: String) -> LUTCube? {
        cubes[slug]
    }

    /// STATIC 렌더/검증/익스포트용 일회성 필터. inputImage는 호출자가 세팅.
    /// 미상 slug → nil(호출자가 아이덴티티 폴백 결정). 크래시 금지.
    func makeFilter(for slug: String) -> CIFilter? {
        guard let cube = cubes[slug],
              let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(cube.dimension, forKey: "inputCubeDimension")
        filter.setValue(cube.data, forKey: "inputCubeData")
        filter.setValue(cube.colorSpace, forKey: "inputColorSpace")
        return filter
    }

    /// 라이브 프리뷰용 **영속** 필터. slug당 한 번 생성해 캐시하고 영구 재사용한다.
    /// 호출자는 프레임마다 inputImage만 교체할 것 — 절대 프레임마다 재생성 금지.
    /// 미상/미로딩 slug → nil(호출자가 아이덴티티 패스스루로 폴백).
    func livePreviewFilter(for slug: String) -> CIFilter? {
        if let cached = liveFilters[slug] { return cached }
        guard let filter = makeFilter(for: slug) else { return nil }
        liveFilters[slug] = filter
        return filter
    }

    // MARK: - Helpers

    /// 로스터 순서에서 기본값 slug을 맨 앞으로.
    private func orderedSlugsDefaultFirst() -> [String] {
        var slugs = MellowFilterRoster.entries.map(\.slug)
        let def = MellowFilterRoster.defaultSlug
        if let idx = slugs.firstIndex(of: def) {
            slugs.remove(at: idx)
            slugs.insert(def, at: 0)
        }
        return slugs
    }

    private func loadCube(forSlug slug: String) -> LUTCube? {
        guard let entry = MellowFilterRoster.entry(forSlug: slug) else { return nil }
        guard let url = Bundle.main.url(forResource: entry.fileName, withExtension: "cube") else {
            print("[LUTStore] MISSING \(entry.fileName)")
            return nil
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            return try CubeParser.parse(text, colorSpace: colorSpace)
        } catch {
            print("[LUTStore] PARSE FAIL \(slug): \(error)")
            return nil
        }
    }
}
