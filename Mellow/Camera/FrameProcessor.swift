import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia

/// CMSampleBuffer → CIImage 변환 + 필터 체인/크로스페이드 (Phase 1 Spec §7).
///
/// Stage 3a부터 `FilterPreset.makeChain` 체인을 CIImage와 Metal 렌더 사이에 삽입한다.
/// 모든 처리는 GPU(Metal-backed CIContext)에서 렌더된다.
struct FrameProcessor {
    /// 프리뷰 프레임 다운스케일 상한(긴 변, px). .photo 프리셋이 큰 프레임을 줘도
    /// 필터 비용을 낮게 유지. 캡처는 별도 풀해상도 경로라 영향 없음.
    private let previewMaxDimension: CGFloat = 1600

    /// 샘플 버퍼를 화면 방향에 맞춘 raw CIImage로 변환(프리뷰용 다운스케일 포함).
    /// - orientation: 전/후면·기기 방향을 반영한 표시 방향(전면은 미러 포함).
    func process(_ sampleBuffer: CMSampleBuffer,
                 orientation: CGImagePropertyOrientation) -> CIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        return downscaledForPreview(oriented)
    }

    private func downscaledForPreview(_ image: CIImage) -> CIImage {
        let longSide = max(image.extent.width, image.extent.height)
        guard longSide > previewMaxDimension else { return image }
        let scale = previewMaxDimension / longSide
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// 프리셋 필터 체인 적용 (필터 없음 = Original이면 그대로 통과).
    ///
    /// **WYSIWYG:** 캡처를 나중에 표시·익스포트할 때도 **이 동일한 `makeChain`**을 써야 한다
    /// (필터 로직 중복 금지). Sunday/Honey는 색 전용이라 해상도 무관이지만,
    /// TODO(그레인/비네팅/헐레이션 단계): 픽셀 단위 효과는 프리뷰(~1600px)와 풀해상도 캡처의
    ///   **해상도 차이를 보정**해야 한다(시드 스케일·반경 등). 지금은 구조만 둔다.
    func apply(_ preset: FilterPreset, to image: CIImage, intensity: Double = 1.0) -> CIImage {
        preset.makeChain(for: image, intensity: intensity)
    }

    /// 두 프리셋 출력의 크로스페이드 (Spec §4.2). progress 0 → from, 1 → to.
    func crossfade(from: CIImage, to: CIImage, progress: Double) -> CIImage {
        let p = max(0, min(1, progress))
        let fade = CIFilter.colorMatrix()
        fade.inputImage = to
        fade.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(p)) // to의 알파 = progress
        guard let faded = fade.outputImage else { return p >= 0.5 ? to : from }
        let over = CIFilter.sourceOverCompositing()
        over.inputImage = faded
        over.backgroundImage = from
        return over.outputImage ?? to
    }
}
