import AVFoundation
import UIKit

enum PhotoCaptureError: Error {
    case noData
    case processingFailed
}

/// AVCapturePhotoOutput 델리게이트 (Phase 1 Spec §6).
///
/// 풀해상도 **무필터** 원본을 받아 표시 방향으로 정규화하고, 화면 비율로 센터 크롭한 뒤
/// JPEG로 인코딩한다. 필터는 절대 베이크하지 않는다(비파괴/WYSIWYG는 표시 시 렌더).
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let aspectRatio: AspectRatio
    private let onReadyForNextShot: () -> Void
    private let completion: (Result<Data, Error>) -> Void

    /// 캡처 후처리 전용 큐. 풀해상도(≈12MP) 디코드·정규화·크롭·JPEG 인코딩은 무거워서
    /// CPU/코덱/메모리 대역을 크게 점유한다. 이를 **낮은 우선순위(.utility)** 백그라운드로
    /// 내려, 프리뷰(메인 스레드 GPU 렌더 + .userInitiated videoQueue)를 굶기지 않는다.
    /// serial — 연사 탭이 들어와도 저장은 순서대로 흘려보내 메모리/발열 스파이크를 막는다
    /// (캡처 자체는 셔터 재활성화와 분리돼 막히지 않음).
    private static let processingQueue = DispatchQueue(
        label: "com.chrisholic.mellow.camera.capture.processing", qos: .utility)

    /// - onReadyForNextShot: 센서 노출 완료(저장 완료가 **아님**) 시점 → 다음 셔터 허용. 메인에서 호출.
    /// - completion: 저장용 JPEG Data(느린 경로). 메인에서 호출.
    init(aspectRatio: AspectRatio,
         onReadyForNextShot: @escaping () -> Void,
         completion: @escaping (Result<Data, Error>) -> Void) {
        self.aspectRatio = aspectRatio
        self.onReadyForNextShot = onReadyForNextShot
        self.completion = completion
    }

    /// 센서가 노출을 끝낸 직후(처리·저장 전) 호출 → 즉시 다음 셔터를 허용한다.
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        DispatchQueue.main.async { [onReadyForNextShot] in onReadyForNextShot() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error { return finish(.failure(error)) }
        // 무거운 작업은 전부 백그라운드(.utility)로 넘기고 콜백은 즉시 반환 → 프리뷰 흐름을
        // 막지 않는다(프리뷰 = 메인 스레드 렌더). AVCapturePhoto는 다른 큐에서 읽어도 안전.
        let ratio = aspectRatio
        Self.processingQueue.async { [weak self] in
            guard let self else { return }
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                return self.finish(.failure(PhotoCaptureError.noData))
            }
            // 화면 비율로 센터 크롭(= 뷰파인더 프레이밍, WYSIWYG). 필터는 적용하지 않음.
            guard let cropped = Self.centerCropped(image, widthOverHeight: ratio.portraitWidthOverHeight),
                  let jpeg = cropped.jpegData(compressionQuality: 0.95) else {
                return self.finish(.failure(PhotoCaptureError.processingFailed))
            }
            self.finish(.success(jpeg))
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        DispatchQueue.main.async { [completion] in completion(result) }
    }

    /// 표시 방향(.up)으로 정규화 후 widthOverHeight 비율로 센터 크롭.
    private static func centerCropped(_ image: UIImage, widthOverHeight ratio: CGFloat) -> UIImage? {
        let upright = image.normalizedUp()
        guard let cg = upright.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let imageRatio = w / h
        let crop: CGRect
        if imageRatio > ratio {
            let cw = h * ratio                                  // 더 넓음 → 좌우 크롭
            crop = CGRect(x: (w - cw) / 2, y: 0, width: cw, height: h)
        } else {
            let ch = w / ratio                                  // 더 좁음 → 상하 크롭
            crop = CGRect(x: 0, y: (h - ch) / 2, width: w, height: ch)
        }
        guard let cropped = cg.cropping(to: crop.integral) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

private extension UIImage {
    /// EXIF 방향을 픽셀에 베이크해 .up으로 정규화(이후 cgImage 크롭이 정확해짐).
    /// scale=1 고정 — 기본값은 화면 스케일(아이폰 3×)이라 원본을 9배로 업스케일해
    /// 보간된 거대 파일이 된다. 네이티브 해상도 원본을 보존하려면 반드시 1.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
