import CoreImage

/// **LUT 적용 단일 소스 오브 트루스** (프리뷰 = 저장 = 익스포트 공용).
///
/// `CIColorCubeWithColorSpace` 빌드/적용 로직은 오직 여기 하나만 존재한다 — 프리뷰의 영속
/// 필터 빌드(LUTStore.makeFilter)도, 저장/썸네일/익스포트의 임의 CIImage 적용도 모두 이걸 쓴다.
/// `cube.colorSpace`는 파싱 시 이미 **명시적 sRGB**로 고정돼 있어 큐브 룩업이 sRGB에 핀된다.
enum LUTFilter {

    /// cube → **inputImage 미설정** CIColorCubeWithColorSpace. 프리뷰 영속 인스턴스(프레임마다
    /// inputImage만 교체)·검증 하네스가 쓴다. 생성 실패 시 nil(호출자가 패스스루 폴백).
    static func makeFilter(cube: LUTCube) -> CIFilter? {
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(cube.dimension, forKey: "inputCubeDimension")
        filter.setValue(cube.data, forKey: "inputCubeData")
        filter.setValue(cube.colorSpace, forKey: "inputColorSpace")
        return filter
    }

    /// 저장/썸네일/익스포트용 — **매번 새 인스턴스**로 임의 CIImage에 LUT을 적용한다.
    /// (프리뷰의 공유 영속 인스턴스는 stateful이라 프레임 루프와 레이스 → 절대 재사용 금지: GATE 2.)
    /// 빌드/출력 실패 시 입력을 그대로 반환(블랙/빈 프레임 금지).
    static func apply(cube: LUTCube, to input: CIImage) -> CIImage {
        guard let filter = makeFilter(cube: cube) else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        return filter.outputImage ?? input
    }
}
