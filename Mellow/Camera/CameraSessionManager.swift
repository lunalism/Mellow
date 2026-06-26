import AVFoundation
import CoreImage  // CGImagePropertyOrientation

/// AVCaptureSession 수명주기 관리 (Phase 1 Spec §7).
///
/// Stage 2부터 라이브 프리뷰는 **AVCaptureVideoDataOutput → CMSampleBuffer → (콜백)**
/// 경로로 흐른다. 프레임은 `FrameProcessor`가 CIImage로 바꾸고 `MetalPreviewView`가
/// Metal로 렌더한다(프리뷰 레이어 제거). 향후 캡처는 별도 AVCapturePhotoOutput.
///
/// 세션 구성/제어는 전용 백그라운드 큐, 프레임 전달은 별도 videoQueue.
final class CameraSessionManager: NSObject {
    let session = AVCaptureSession()
    let videoDataOutput = AVCaptureVideoDataOutput()

    private let sessionQueue = DispatchQueue(label: "com.chrisholic.mellow.camera.session")
    private let videoQueue = DispatchQueue(label: "com.chrisholic.mellow.camera.video", qos: .userInitiated)
    private var videoInput: AVCaptureDeviceInput?
    private var didAddOutput = false

    /// 현재 전/후면.
    private(set) var position: AVCaptureDevice.Position = .back

    /// 카메라 입력 구성 가능 여부. 시뮬레이터는 false → 더미 모드.
    private(set) var hasCamera = false

    /// 표시 방향(전면은 미러 포함). videoQueue에서 읽는다 — 스위치 중 한 프레임 stale은 무해.
    private(set) var currentOrientation: CGImagePropertyOrientation = .right

    /// VideoDataOutput 델리게이트 → 프레임 콜백 (videoQueue에서 호출).
    var onFrame: ((CMSampleBuffer) -> Void)?

    // MARK: - 구성

    func configure(position: AVCaptureDevice.Position = .back,
                   completion: @escaping (_ success: Bool) -> Void) {
        sessionQueue.async {
            let ok = self.applyConfiguration(position: position)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func switchCamera(completion: @escaping (_ success: Bool) -> Void) {
        let target: AVCaptureDevice.Position = (position == .back) ? .front : .back
        sessionQueue.async {
            let ok = self.applyConfiguration(position: target)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    // MARK: - 시작 / 정지

    func start() {
        sessionQueue.async {
            guard self.hasCamera, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - Private

    /// sessionQueue에서만 호출. 입력 교체 + 데이터 출력 + 방향/미러 갱신.
    private func applyConfiguration(position: AVCaptureDevice.Position) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 입력 교체
        if let existing = videoInput {
            session.removeInput(existing)
            videoInput = nil
        }

        guard let device = Self.device(for: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            hasCamera = false
            return false
        }
        session.addInput(input)
        videoInput = input

        // 프리뷰용 4:3 30fps 포맷. 4:3 센서 화각을 유지해 9:16 크롭이 .photo 프리뷰와 동일.
        configurePreviewFormat(device)

        // 데이터 출력은 1회만 추가(입력 교체 시 유지).
        if !didAddOutput {
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
                didAddOutput = true
            }
        }

        // 방향/미러는 데이터 출력 경로에선 자동 처리되지 않으므로 CI에서 명시 적용.
        // 세로 고정: 후면 = .right, 전면 = .leftMirrored(셀피 미러).
        currentOrientation = (position == .front) ? .leftMirrored : .right

        self.position = position
        hasCamera = true
        return true
    }

    /// 4:3 비율 · ≤~1440p · 30fps 지원 포맷을 골라 activeFormat으로 설정.
    /// 적당한 포맷이 없으면 .photo 프리셋으로 폴백.
    private func configurePreviewFormat(_ device: AVCaptureDevice) {
        let fourThree = device.formats.filter { format in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let ratioOK = abs(Double(d.width) / Double(d.height) - 4.0 / 3.0) < 0.01
            let sizeOK = d.width <= 2048
            let fpsOK = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
            return ratioOK && sizeOK && fpsOK
        }
        let best = fourThree.max { a, b in
            CMVideoFormatDescriptionGetDimensions(a.formatDescription).width <
            CMVideoFormatDescriptionGetDimensions(b.formatDescription).width
        }

        guard let format = best, (try? device.lockForConfiguration()) != nil else {
            session.sessionPreset = .photo
            return
        }
        session.sessionPreset = .inputPriority   // activeFormat을 우리가 제어
        device.activeFormat = format
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30) // 최대 30fps 캡(발열 방지)
        device.unlockForConfiguration()
    }

    private static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
    }
}

// MARK: - 프레임 델리게이트

extension CameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
    }
}
