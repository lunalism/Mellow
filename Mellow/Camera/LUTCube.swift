import Foundation
import CoreGraphics

/// 파싱된 3D LUT의 불변 값 타입 (Stage L1).
///
/// `.cube` 파일을 파싱한 결과. CIColorCube / Metal 경로에 그대로 전달할 수 있는 형태로 보관한다.
/// - `dimension`: 파일별 N (32·33·64 확인됨). 하드코딩 금지 — 파일에서 읽는다.
/// - `data`: N*N*N*4 Float32, RGBA 인터리브, **RED가 가장 빠른 축**, A=1.0.
/// - `colorSpace`: 큐브가 정의된 색 공간(현재 sRGB).
struct LUTCube {
    let dimension: Int
    let data: Data
    let colorSpace: CGColorSpace
}
