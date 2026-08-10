// AVCaptureSession 은 Sendable 이 아니라서 serial queue 로 넘길 때 경고가 난다.
// 스레드 경계는 sessionQueue 로 우리가 직접 지키고 있고, Swift 6 언어 모드 전환은
// Phase 2 에서 따로 판단하기로 했다(project.yml 참고). 그때까지 @preconcurrency 로 덮는다.
@preconcurrency import AVFoundation
import UIKit

// AVCaptureSession 의 구성·구동과 회전각 관찰을 담당한다.
//
// 세션 구성과 start/stop 은 전용 serial queue 에서, 상태 공개는 메인에서 한다.
// AVCaptureSession 은 스레드 안전하지 않으므로 이 경계를 지키는 것이 중요하다.
//
// 1-2 범위이므로 출력(AVCaptureMovieFileOutput)은 붙이지 않는다. 프리뷰 레이어는
// 세션에 직접 물리면 출력 없이도 연결이 생겨 화면이 나온다.
@MainActor
final class CaptureSessionController: ObservableObject {

    /// 세션 구성이 어디까지 갔는지.
    enum SetupState: Equatable {
        case idle
        /// 권한이 모자라 시작하지 못함.
        case permissionBlocked
        case configured
        case failed(String)
    }

    // MARK: - 공개 상태

    @Published private(set) var cameraPermission: PermissionState = .undetermined
    @Published private(set) var microphonePermission: PermissionState = .undetermined
    @Published private(set) var setupState: SetupState = .idle
    /// 세션이 실제로 돌고 있는지. 의도가 아니라 `session.isRunning` 을 읽어 반영한다.
    @Published private(set) var isRunning = false

    // MARK: - 디버그 표시용 (0-6 Portrait 잠금 결정의 검증 수단)

    /// 수평 기준 프리뷰 회전각. 프리뷰 레이어 연결에 그대로 반영한다.
    @Published private(set) var previewRotationAngle: CGFloat?
    /// 수평 기준 캡처 회전각. Portrait 잠금 상태에서도 이 값이 변해야
    /// 가로 촬영 감지가 가능하다는 전제가 성립한다.
    @Published private(set) var captureRotationAngle: CGFloat?
    @Published private(set) var deviceOrientation: UIDeviceOrientation = .unknown

    // MARK: - 녹화 (1-4)

    @Published private(set) var isRecording = false
    /// 이번 실행에서 찍은 클립들. 한 번에 비교하려고 모아둔다.
    /// Phase 2 에서 세션 개념이 들어오면 이 배열은 사라진다.
    @Published private(set) var recordedURLs: [URL] = []
    /// 직전 녹화가 어떻게 끝났는지. 폐기됐다는 사실이 화면에 드러나야 한다.
    @Published private(set) var lastOutcome: ClipOutcome?

    /// 녹화 한 건의 결말.
    enum ClipOutcome {
        case saved(seconds: Double, hitLimit: Bool)
        /// 1초 미만이라 폐기 (1-7).
        case discarded(seconds: Double)
        case failed(String)
    }

    /// 두 권한이 모두 허용되어야 프리뷰를 띄운다.
    var hasAllPermissions: Bool {
        cameraPermission.isAuthorized && microphonePermission.isAuthorized
    }

    let session = AVCaptureSession()

    // MARK: - 내부

    private let sessionQueue = DispatchQueue(label: "com.lunalism.mellow.capture.session")
    /// 씬이 화면에 떠 있는지. 세션 시작의 전제 조건이다.
    ///
    /// 권한 요청이나 세션 구성이 진행되는 동안 앱을 내리면, 구성이 끝나는 시점에는
    /// 이미 백그라운드다. 그 상태로 startRunning 을 부르면 실제로는 시작되지 않는데
    /// 앱은 돌고 있다고 착각해, 복귀해도 다시 시작하지 않는다. 그걸 막는 가드다.
    private var isSceneActive = false
    private var videoDevice: AVCaptureDevice?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var recordingDelegate: MovieRecordingDelegate?
    /// 녹화 버튼을 누른 시각. 파일 duration 과의 차이를 보려는 계측용.
    private var pressedAt: UInt64?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []
    private var orientationObserver: NSObjectProtocol?
    /// 계측용. 세션이 실제로 언제 시작·중단·인터럽션되는지 보려고 건다.
    private var sessionObservers: [NSObjectProtocol] = []

    deinit {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
        for observer in sessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 준비

    /// 권한을 확인·요청하고, 통과하면 세션을 구성한다.
    func prepare() async {
        startObservingDeviceOrientation()
        startObservingSessionNotifications()
        CaptureTrace.shared.mark("prepare() 진입")

        cameraPermission = await CameraPermissions.request(for: .video)
        microphonePermission = await CameraPermissions.request(for: .audio)

        guard hasAllPermissions else {
            setupState = .permissionBlocked
            return
        }

        guard setupState != .configured else { return }
        await configureSession()
    }

    private func configureSession() async {
        // 이 마크가 복귀 때마다 찍히면 재구성이 도는 것이다. 원인 판별용.
        CaptureTrace.shared.mark("configureSession() 진입")

        let result = await withCheckedContinuation { continuation in
            sessionQueue.async { [session] in
                let output = AVCaptureMovieFileOutput()

                // 입력·출력 구성. 이 안에서는 세션이 열려 있다.
                func build() -> Result {
                    // (1) 해상도. 실패해도 조용히 넘어가지 않고 로그로 드러낸다.
                    CaptureSpec.applyPreset(to: session)

                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                               for: .video,
                                                               position: .back) else {
                        return .failure("후면 광각 카메라를 찾을 수 없습니다.")
                    }

                    do {
                        let videoInput = try AVCaptureDeviceInput(device: device)
                        guard session.canAddInput(videoInput) else {
                            return .failure("카메라 입력을 세션에 추가할 수 없습니다.")
                        }
                        session.addInput(videoInput)

                        guard let mic = AVCaptureDevice.default(for: .audio) else {
                            return .failure("마이크를 찾을 수 없습니다.")
                        }
                        let audioInput = try AVCaptureDeviceInput(device: mic)
                        guard session.canAddInput(audioInput) else {
                            return .failure("마이크 입력을 세션에 추가할 수 없습니다.")
                        }
                        session.addInput(audioInput)

                        guard session.canAddOutput(output) else {
                            return .failure("무비 출력을 세션에 추가할 수 없습니다.")
                        }
                        session.addOutput(output)

                        return .success(device, output)
                    } catch {
                        return .failure("입력 생성 실패: \(error.localizedDescription)")
                    }
                }

                session.beginConfiguration()
                let built = build()
                session.commitConfiguration()

                guard case .success(let device, let output) = built else {
                    continuation.resume(returning: built)
                    return
                }

                // (2) fps. preset 을 바꾸면 activeFormat 과 프레임 지속시간이
                // 초기화되므로 커밋 이후에 잠근다.
                if let failure = CaptureSpec.lockFrameRate(on: device) {
                    continuation.resume(returning: .failure(failure))
                    return
                }

                // (3) 코덱. 연결은 출력을 세션에 붙인 뒤에야 생긴다.
                if let failure = CaptureSpec.applyVideoCodec(to: output) {
                    continuation.resume(returning: .failure(failure))
                    return
                }

                // 10초 자동 정지 (1-5)
                CaptureSpec.applyRecordingLimit(to: output)

                continuation.resume(returning: .success(device, output))
            }
        }

        switch result {
        case .success(let device, let output):
            CaptureTrace.shared.mark("configureSession() 완료")
            videoDevice = device
            movieOutput = output
            setupState = .configured
            makeRotationCoordinatorIfPossible()
            start()
        case .failure(let message):
            print("[spec] ✕ 세션 구성 실패: \(message)")
            setupState = .failed(message)
        }
    }

    /// 세션 구성 결과. 실패 사유를 문자열로 들고 다닌다.
    private enum Result {
        case success(AVCaptureDevice, AVCaptureMovieFileOutput)
        case failure(String)
    }

    // MARK: - 구동

    /// 씬 활성 여부를 알린다.
    ///
    /// `.inactive` 는 전달하지 않는다. 권한 팝업·제어 센터·알림 배너에서도 발생하는데
    /// 그때마다 세션을 껐다 켜면 프리뷰가 깜빡인다. `.background` 에서만 정지한다.
    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        if active {
            start()
        } else {
            // 녹화 중에 세션을 멈추면 파일이 온전하지 않을 수 있다. 먼저 닫는다.
            stopRecording()
            stop()
        }
    }

    func start() {
        CaptureTrace.shared.mark("start() 호출")
        guard setupState == .configured, isSceneActive else {
            CaptureTrace.shared.mark("start() 가드에서 반환")
            return
        }
        sessionQueue.async { [weak self, session] in
            CaptureTrace.shared.mark("sessionQueue 진입")
            if !session.isRunning {
                CaptureTrace.shared.mark("startRunning() 진입")
                session.startRunning()
                CaptureTrace.shared.mark("startRunning() 반환")
            } else {
                CaptureTrace.shared.mark("이미 running — 호출 생략")
            }
            let running = session.isRunning
            Task { @MainActor in
                self?.isRunning = running
                CaptureTrace.shared.mark("isRunning=\(running) 메인 반영")
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self, session] in
            CaptureTrace.shared.mark("stop: sessionQueue 진입")
            if session.isRunning {
                CaptureTrace.shared.mark("stopRunning() 진입")
                session.stopRunning()
                CaptureTrace.shared.mark("stopRunning() 반환")
            }
            let running = session.isRunning
            Task { @MainActor in
                self?.isRunning = running
                CaptureTrace.shared.mark("isRunning=\(running) 메인 반영")
            }
        }
    }

    // MARK: - 녹화 (1-4)

    /// 녹화를 시작한다. 길이 제한은 없다 — 10초 자동 정지는 1-5 에서 붙인다.
    func startRecording() {
        guard let movieOutput, setupState == .configured, !isRecording else { return }

        // 회전 각도는 시작 직전에 한 번 읽어 고정한다. 녹화 중에는 바꾸지 않는다.
        // 이미 시작된 클립은 시작 시점의 방향을 유지한다(PRD 8장).
        // 각도를 방향 상수로 매핑하지 않고 값을 그대로 넣는다.
        let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture

        let url = Self.makeTemporaryMovieURL()
        let delegate = MovieRecordingDelegate(
            onStart: { [weak self] url in
                Task { @MainActor in self?.handleRecordingStarted(url) }
            },
            onFinish: { [weak self] url, error in
                Task { @MainActor in await self?.handleRecordingFinished(url, error: error) }
            }
        )
        // 델리게이트는 출력이 약하게 잡으므로 여기서 붙들어 둔다.
        recordingDelegate = delegate
        lastOutcome = nil
        // 버튼을 누른 시점. 파일 duration 과 얼마나 벌어지는지 보려고 잰다.
        pressedAt = DispatchTime.now().uptimeNanoseconds

        sessionQueue.async {
            if let angle, let connection = movieOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                    print("[rec] 회전각 고정 \(angle)")
                } else {
                    print("[rec] ✕ 지원하지 않는 회전각 \(angle) — 기존 값 유지")
                }
            }
            movieOutput.startRecording(to: url, recordingDelegate: delegate)
        }
    }

    func stopRecording() {
        guard let movieOutput, isRecording else { return }
        sessionQueue.async {
            guard movieOutput.isRecording else { return }
            movieOutput.stopRecording()
        }
    }

    private func handleRecordingStarted(_ url: URL) {
        isRecording = true
        print("[rec] ▶ 시작 \(url.lastPathComponent)")
    }

    private func handleRecordingFinished(_ url: URL, error: Error?) async {
        isRecording = false

        let pressedSeconds = pressedAt.map {
            Double(DispatchTime.now().uptimeNanoseconds - $0) / 1_000_000_000
        }
        pressedAt = nil

        // 10초 한도로 끊긴 경우도 에러로 온다. 정상 종료이므로 구분한다 (1-5).
        var hitLimit = false
        if let error {
            hitLimit = (error as? AVError)?.code == .maximumDurationReached
            let usable = (error as NSError)
                .userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false

            if hitLimit {
                print("[rec] ⏱ 10초 한도 도달로 자동 종료 (파일 사용 가능=\(usable))")
            } else {
                print("[rec] ✕ 종료 오류: \(error.localizedDescription) (파일 사용 가능=\(usable))")
            }

            guard usable else {
                lastOutcome = .failed(error.localizedDescription)
                Self.deleteFile(at: url)
                return
            }
        }

        // 스펙을 먼저 읽는다. 폐기 판정을 파일 duration 으로 하기 때문이다.
        let spec: ClipSpec
        do {
            spec = try await ClipSpec.load(from: url)
        } catch {
            print("[rec] ✕ ClipSpec 읽기 실패: \(error) — 검증 불가라 저장하지 않는다")
            lastOutcome = .failed("스펙 읽기 실패: \(error.localizedDescription)")
            Self.deleteFile(at: url)
            return
        }

        let seconds = CMTimeGetSeconds(spec.duration)
        if let pressedSeconds {
            print(String(format: "[rec] 누른 시간 %.3fs / 파일 duration %.3fs (차이 %.3fs)",
                         pressedSeconds, seconds, pressedSeconds - seconds))
        }

        // 1초 미만은 클립으로 남기지 않는다 (1-7). 조용히 사라지면 안 되므로
        // 로그와 화면 양쪽에 드러낸다.
        guard CMTimeCompare(spec.duration, CaptureSpec.minClipDuration) >= 0 else {
            print(String(format: "[rec] ⌫ 폐기 %.3fs — %.1f초 미만",
                         seconds, CMTimeGetSeconds(CaptureSpec.minClipDuration)))
            lastOutcome = .discarded(seconds: seconds)
            Self.deleteFile(at: url)
            return
        }

        recordedURLs.append(url)
        lastOutcome = .saved(seconds: seconds, hitLimit: hitLimit)
        print("[rec] ■ 저장 \(url.lastPathComponent) — 누적 \(recordedURLs.count)개")

        // 찍자마자 실제 스펙을 확인한다. 1-3 의 고정이 먹혔는지 보는 지점이다.
        spec.report()
    }

    private static func deleteFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("[rec] ✕ 파일 삭제 실패: \(error.localizedDescription)")
        }
    }

    /// 지금까지 찍은 클립을 첫 클립 기준으로 한 번에 비교한다 (1-8 예행).
    func reportRecordedComparison() async {
        guard !recordedURLs.isEmpty else {
            print("[rec] 비교할 클립이 없습니다.")
            return
        }
        await ClipSpec.reportComparison(of: recordedURLs)
    }

    private static func makeTemporaryMovieURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mellow-\(UUID().uuidString).mov")
    }

    // MARK: - 프리뷰 레이어 연결

    /// 프리뷰 레이어가 만들어지면 붙인다. 세션 구성보다 먼저 올 수도, 나중에 올 수도
    /// 있으므로 양쪽 경로에서 회전 코디네이터 생성을 시도한다.
    func attach(previewLayer layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        makeRotationCoordinatorIfPossible()
    }

    // MARK: - 회전

    private func makeRotationCoordinatorIfPossible() {
        guard rotationCoordinator == nil,
              let videoDevice,
              let previewLayer else { return }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: videoDevice,
                                                              previewLayer: previewLayer)
        rotationCoordinator = coordinator

        // 각도 값을 방향 상수로 매핑하지 않는다. 기기·카메라에 따라 값이
        // 다르게 나온다는 보고가 있어, 지금은 값을 그대로 쓰고 관찰만 한다.
        //
        // KVO 콜백이 어느 스레드로 오는지 문서에 명시가 없어 메인으로 넘긴다.
        rotationObservations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview,
                                 options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                Task { @MainActor [weak self] in
                    self?.applyPreviewRotation(angle)
                }
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture,
                                 options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                Task { @MainActor [weak self] in
                    self?.captureRotationAngle = angle
                }
            }
        ]
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        previewRotationAngle = angle

        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    // MARK: - 세션 알림 (계측용)

    // 화면 잠금은 세션 인터럽션을 일으킨다. 정지/재시작 경로와 인터럽션 경로 중
    // 어느 쪽이 지연의 원인인지 가르려면 둘 다 봐야 한다.
    private func startObservingSessionNotifications() {
        guard sessionObservers.isEmpty else { return }

        func observe(_ name: Notification.Name, _ label: @escaping (Notification) -> String) {
            let observer = NotificationCenter.default.addObserver(
                forName: name, object: session, queue: nil
            ) { notification in
                CaptureTrace.shared.mark(label(notification))
            }
            sessionObservers.append(observer)
        }

        observe(AVCaptureSession.didStartRunningNotification) { _ in "알림: didStartRunning" }
        observe(AVCaptureSession.didStopRunningNotification) { _ in "알림: didStopRunning" }
        observe(AVCaptureSession.runtimeErrorNotification) { notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey]
            return "알림: runtimeError \(error.map { "\($0)" } ?? "")"
        }
        observe(AVCaptureSession.wasInterruptedNotification) { notification in
            let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey]
            return "알림: wasInterrupted reason=\(reason.map { "\($0)" } ?? "?")"
        }
        observe(AVCaptureSession.interruptionEndedNotification) { _ in "알림: interruptionEnded" }
    }

    // MARK: - 기기 방향 (디버그 표시용)

    private func startObservingDeviceOrientation() {
        guard orientationObserver == nil else { return }

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        deviceOrientation = UIDevice.current.orientation

        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let orientation = UIDevice.current.orientation
            Task { @MainActor [weak self] in
                self?.deviceOrientation = orientation
            }
        }
    }
}
