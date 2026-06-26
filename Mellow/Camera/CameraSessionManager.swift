import AVFoundation

/// AVCaptureSession 수명주기 관리 (Phase 1 Spec §7).
///
/// Stage 1 범위: 전/후면 입력 구성 + 시작/정지 + 전환. **라이브 프리뷰는
/// AVCaptureVideoPreviewLayer로 raw 렌더**(필터 없음). 필터 단계에서
/// VideoDataOutput → FrameProcessor → Metal 경로로 교체한다.
///
/// 세션 구성/제어는 전용 백그라운드 큐에서 수행해 UI 스레드를 막지 않는다.
final class CameraSessionManager: NSObject {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.chrisholic.mellow.camera.session")
    private var videoInput: AVCaptureDeviceInput?

    /// 현재 전/후면. 구성 큐에서 쓰고 메인에서 읽으므로 콜백으로만 노출.
    private(set) var position: AVCaptureDevice.Position = .back

    /// 이 기기에 카메라 입력을 붙일 수 있었는지. 시뮬레이터는 false → 더미 모드.
    private(set) var hasCamera = false

    // MARK: - 구성

    /// 초기 세션 구성. completion은 메인 스레드에서 호출된다.
    func configure(position: AVCaptureDevice.Position = .back,
                   completion: @escaping (_ success: Bool) -> Void) {
        sessionQueue.async {
            let ok = self.applyConfiguration(position: position)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// 전/후면 전환 (세션 재구성). completion은 메인 스레드.
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

    /// sessionQueue에서만 호출. 입력 교체 후 성공 여부 반환.
    private func applyConfiguration(position: AVCaptureDevice.Position) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        if let existing = videoInput {
            session.removeInput(existing)
            videoInput = nil
        }

        guard let device = Self.device(for: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            // 시뮬레이터 등 카메라 없음 → 더미 모드로 폴백.
            hasCamera = false
            return false
        }

        session.addInput(input)
        videoInput = input
        self.position = position
        hasCamera = true

        // 전면 미러링 정상화 (프리뷰 레이어 단계에서 처리되지만 연결 단위로도 보정).
        if let connection = session.connections.first(where: { $0.isVideoMirroringSupported }) {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }

        return true
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
