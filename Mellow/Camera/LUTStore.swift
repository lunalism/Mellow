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
    /// 블롭엔 색공간을 저장하지 않는다(항상 sRGB) → 런타임에 이 하나로 재구성.
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// `.lutbin` v1 헤더: magic(4) + version(4) + dimension(4).
    private static let headerSize = 12
    private static let formatVersion: UInt32 = 1

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

    /// **로드 보장** cube 접근 — 저장/썸네일/익스포트용. preload 완료 전이라도(예: 런치 직후
    /// 보관함이 옛 캡처를 렌더) 로스터에 있으면 즉석 로드해 캐시한다 → 미필터 저장(구 버그) 방지.
    /// 로스터에 없는 slug("original"/미상)은 nil → 호출자가 패스스루(GATE 1).
    func loadedCube(for slug: String) -> LUTCube? {
        if let cached = cubes[slug] { return cached }
        guard let cube = loadCube(forSlug: slug) else { return nil }
        cubes[slug] = cube
        return cube
    }

    /// STATIC 렌더/검증/익스포트용 일회성 필터. inputImage는 호출자가 세팅.
    /// 미상 slug → nil(호출자가 아이덴티티 폴백 결정). 크래시 금지.
    func makeFilter(for slug: String) -> CIFilter? {
        guard let cube = cubes[slug] else { return nil }
        return LUTFilter.makeFilter(cube: cube)   // 단일 빌더(프리뷰·검증·저장 공용)
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

    /// 번들의 **precompiled `.lutbin` 블롭**을 읽어 LUTCube로. 런타임 텍스트 파싱 없음.
    ///
    /// `.cube` 텍스트 파싱은 64³(7MB) 한 장에 ~1–3s가 들어 콜드런치에서 프리뷰가 몇 초간
    /// 패스스루로 남는 원인이었다. 이제 파싱은 **빌드 전 오프라인**(LUTSource/*.cube → Mellow/LUTs/*.lutbin,
    /// 동일한 CubeParser로 생성 — 바이트 동일 검증 완료)에서 끝내고, 런타임은 블롭을 그대로 읽는다.
    /// `CubeParser`는 오프라인 컨버터 전용으로 남는다(런타임 호출 없음).
    ///
    /// 포맷 v1: [0..3] magic "MLUT" · [4..7] version UInt32 LE(=1) · [8..11] dimension UInt32 LE
    ///          [12..] payload = n³×16B Float32 RGBA(= LUTCube.data 그대로). colorSpace는 미저장 —
    ///          항상 sRGB라 런타임에 재구성한다.
    private func loadCube(forSlug slug: String) -> LUTCube? {
        guard let entry = MellowFilterRoster.entry(forSlug: slug) else { return nil }
        guard let url = Bundle.main.url(forResource: entry.fileName, withExtension: "lutbin") else {
            print("[LUTStore] MISSING \(entry.fileName)")
            return nil
        }

        // mmap — 페이로드는 읽기 전용이고 변형하지 않는다(풀 리드 없이 페이지 폴트로 들어옴).
        let blob: Data
        do {
            blob = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            print("[LUTStore] BADBLOB \(slug): read failed — \(error)")
            return nil
        }

        guard blob.count >= Self.headerSize else {
            print("[LUTStore] BADBLOB \(slug): truncated (\(blob.count)B < \(Self.headerSize)B header)")
            return nil
        }

        let (magicOK, version, dimension) = blob.withUnsafeBytes { raw -> (Bool, UInt32, UInt32) in
            let magicOK = raw[0] == 0x4D && raw[1] == 0x4C && raw[2] == 0x55 && raw[3] == 0x54   // "MLUT"
            let v = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            let d = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
            return (magicOK, v, d)
        }

        guard magicOK else {
            print("[LUTStore] BADBLOB \(slug): bad magic")
            return nil
        }
        guard version == Self.formatVersion else {
            print("[LUTStore] BADBLOB \(slug): unsupported version \(version)")
            return nil
        }
        let n = Int(dimension)
        guard (2...64).contains(n) else {
            print("[LUTStore] BADBLOB \(slug): dimension out of range (\(n))")
            return nil
        }

        let expected = n * n * n * 4 * MemoryLayout<Float>.size          // n³ × 16B
        let payloadCount = blob.count - Self.headerSize
        guard payloadCount == expected else {
            print("[LUTStore] BADBLOB \(slug): payload \(payloadCount)B != expected \(expected)B for N=\(n)")
            return nil
        }

        // ⚠️ 페이로드는 **base-0 연속 Data**로 넘긴다. mmap 슬라이스를 그대로 주면 startIndex가
        //    12인 Data가 되어 CIColorCubeWithColorSpace가 오프셋을 오해할 여지가 있다(색 밀림/크래시).
        //    `subdata`는 페이로드만 복사해 startIndex=0을 보장한다 — 4MB memcpy(<1ms)로 정확성을 산다.
        let payload = blob.subdata(in: Self.headerSize ..< blob.count)
        return LUTCube(dimension: n, data: payload, colorSpace: Self.sRGB)
    }
}
