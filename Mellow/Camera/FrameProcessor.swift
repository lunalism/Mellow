import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia

/// CMSampleBuffer → CIImage 변환 + 필터 체인/크로스페이드 (Phase 1 Spec §7).
///
/// Stage 3a부터 `FilterPreset.makeChain` 체인을 CIImage와 Metal 렌더 사이에 삽입한다.
/// 모든 처리는 GPU(Metal-backed CIContext)에서 렌더된다.
struct FrameProcessor {
    /// 샘플 버퍼를 화면 방향에 맞춘 raw CIImage로 변환.
    /// - orientation: 전/후면·기기 방향을 반영한 표시 방향(전면은 미러 포함).
    func process(_ sampleBuffer: CMSampleBuffer,
                 orientation: CGImagePropertyOrientation) -> CIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        return CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
    }

    /// 프리셋 필터 체인 적용 (필터 없음 = Original이면 그대로 통과).
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
