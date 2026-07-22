import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia

/// CMSampleBuffer → CIImage 변환(방향 보정 + 프리뷰 다운스케일) (Phase 1 Spec §7).
///
/// 필터 적용은 이 타입 밖에서 일어난다 — 라이브 프리뷰는 `LUTStore`에서 얻은 LUT `CIFilter`에
/// 프레임당 inputImage만 교체해 렌더한다(`CameraPreviewView.Coordinator.render` 참조).
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
}
