import CoreImage
import CoreMedia

/// CMSampleBuffer → (필터된) CIImage 변환 (Phase 1 Spec §7).
///
/// **Stage 2는 PASSTHROUGH:** 필터 체인 없음. 카메라 프레임을 방향/미러만 바로잡아
/// 그대로 통과시킨다. 필터 단계에서 이 지점에 `FilterPreset` 체인을 삽입한다.
struct FrameProcessor {
    /// 샘플 버퍼를 화면 방향에 맞춘 CIImage로 변환.
    /// - orientation: 전/후면·기기 방향을 반영한 표시 방향(전면은 미러 포함).
    func process(_ sampleBuffer: CMSampleBuffer,
                 orientation: CGImagePropertyOrientation) -> CIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        // TODO(필터 단계): 여기서 FilterPreset.makeChain(...)으로 GPU 필터 체인 적용.
        return CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
    }
}
