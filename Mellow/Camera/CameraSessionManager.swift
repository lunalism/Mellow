import AVFoundation
import CoreImage  // CGImagePropertyOrientation

/// AVCaptureSession 수명주기 관리 (Phase 1 Spec §7).
///
/// 라이브 프리뷰는 **AVCaptureVideoDataOutput → CMSampleBuffer → (콜백)** 경로,
/// 정지 캡처는 **AVCapturePhotoOutput**(풀해상도 무필터 원본)로 분리된다.
/// `.photo` 프리셋으로 풀해상도 스틸을 얻고, 프리뷰는 FrameProcessor에서 다운스케일.
///
/// 세션 구성/제어는 전용 sessionQueue, 프레임 전달은 별도 videoQueue.
final class CameraSessionManager: NSObject {
    let session = AVCaptureSession()
    let videoDataOutput = AVCaptureVideoDataOutput()
    let photoOutput = AVCapturePhotoOutput()

    private let sessionQueue = DispatchQueue(label: "com.chrisholic.mellow.camera.session")
    private let videoQueue = DispatchQueue(label: "com.chrisholic.mellow.camera.video", qos: .userInitiated)
    private var videoInput: AVCaptureDeviceInput?
    private var didAddVideoOutput = false
    private var didAddPhotoOutput = false

    /// in-flight 캡처 델리게이트 보관(콜백까지 살려둠). 메인에서만 접근.
    private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]

    /// 현재 전/후면.
    private(set) var position: AVCaptureDevice.Position = .back

    /// 카메라 입력 구성 가능 여부. 시뮬레이터는 false → 더미 모드.
    private(set) var hasCamera = false

    /// 프리뷰 표시 방향(전면은 미러 포함). videoQueue에서 읽는다 — 스위치 중 한 프레임 stale 무해.
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

    // MARK: - 캡처 (Spec §6)

    /// 풀해상도 무필터 원본을 촬영.
    /// - onReadyForNextShot: 센서 노출 완료 → 다음 셔터 허용(저장 완료를 기다리지 않음). 메인.
    /// - completion: 저장용 JPEG Data 또는 에러. 메인.
    func capturePhoto(aspectRatio: AspectRatio,
                      onReadyForNextShot: @escaping () -> Void,
                      completion: @escaping (Result<Data, Error>) -> Void) {
        let settings = makePhotoSettings()
        let delegate = PhotoCaptureDelegate(aspectRatio: aspectRatio,
                                            onReadyForNextShot: onReadyForNextShot) { [weak self] result in
            self?.captureDelegates[settings.uniqueID] = nil
            completion(result)
        }
        captureDelegates[settings.uniqueID] = delegate   // 콜백까지 retain (캡처마다 개별 보관 → 동시 저장 충돌 없음)
        sessionQueue.async {
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func makePhotoSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions  // 풀해상도
        return settings
    }

    // MARK: - Private

    /// sessionQueue에서만 호출. 입력 교체 + 출력 구성 + 방향/미러 갱신.
    private func applyConfiguration(position: AVCaptureDevice.Position) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 풀해상도 스틸을 위해 .photo 프리셋(4:3 풀센서). 프리뷰는 FrameProcessor에서 다운스케일.
        session.sessionPreset = .photo

        // 세션이 commit 시 색공간을 wide-gamut(HDR)로 되돌리지 않게 — 우리는 SDR sRGB로 고정한다.
        // (아래 configureStandardDynamicRange의 activeColorSpace 설정이 유지되도록.)
        session.automaticallyConfiguresCaptureDeviceForWideColor = false

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

        // HDR 끄기 + sRGB 고정. iOS 26.5에서 HDR 스틸이 깨진 XDR 톤매핑 Metal 커널
        // (xdr::convert_image_to_image_loop)을 건드려 캡처 서버(mediaserverd)가 크래시한다.
        // SDR을 강제해 그 경로 자체를 타지 않게 한다. (전/후면 전환마다 새 입력에 재적용.)
        configureStandardDynamicRange(on: device)

        // 비디오 데이터 출력(프리뷰) — 1회만 추가.
        if !didAddVideoOutput {
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
                didAddVideoOutput = true
            }
        }

        // 포토 출력(캡처) — 1회만 추가.
        if !didAddPhotoOutput {
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                didAddPhotoOutput = true
            }
        }
        // 지연(deferred) 처리 경로는 HDR/Deep Fusion 후처리를 비동기로 돌리며,
        // 우리 델리게이트는 didFinishProcessingPhoto만 구현하므로 프록시가 아닌 완성본을
        // 받기 위해서도 꺼야 한다(= 동기 SDR 캡처).
        if photoOutput.isAutoDeferredPhotoDeliverySupported {
            photoOutput.isAutoDeferredPhotoDeliveryEnabled = false
        }
        // 풀해상도 캡처 차원 설정.
        if let maxDim = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }) {
            photoOutput.maxPhotoDimensions = maxDim
        }

        // 프리뷰 방향/미러는 CI에서 명시(.oriented). 후면 = .right, 전면 = .leftMirrored(셀피).
        currentOrientation = (position == .front) ? .leftMirrored : .right
        // 캡처(포토) 연결은 세로 회전 + 전면 미러를 직접 적용 → 저장 원본이 프리뷰와 일치.
        configurePhotoConnection(position: position)

        self.position = position
        hasCamera = true
        return true
    }

    /// 캡처를 표준 다이내믹 레인지(SDR sRGB)로 고정. HDR 스틸이 iOS 26.5의 깨진 XDR
    /// 톤매핑 Metal 커널을 타며 캡처 서버가 크래시하는 것을 막는다. lockForConfiguration이
    /// 필수 — 실패해도 캡처는 계속(완화만 건너뜀)하고 절대 크래시하지 않는다.
    private func configureStandardDynamicRange(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = false   // 먼저 자동 조정 해제
                device.isVideoHDREnabled = false                     // 그 다음 명시적으로 off
            }
            device.activeColorSpace = .sRGB                          // wide/XDR 대신 SDR
        } catch {
            // 완화 실패 — 그래도 진행. 크래시 금지(IMPORTANT: 캡처 경로는 절대 죽지 않음).
        }
    }

    private func configurePhotoConnection(position: AVCaptureDevice.Position) {
        guard let connection = photoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90   // 세로
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }
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
