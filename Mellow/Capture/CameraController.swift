// AVCaptureSession 은 Sendable 이 아니지만, 전용 시리얼 큐에서만 만지는 것이
// AVFoundation 의 표준 사용법이다. Swift 6 승격(Phase 2) 때 다시 본다.
@preconcurrency import AVFoundation
import Observation
import UIKit

/// AVCaptureSession 소유자. (Tasks 1-1, 1-2)
///
/// 큐 경계는 **소유물 기준**으로 긋는다.
/// - 세션 그래프(구성·시작·정지)는 `sessionQueue`. 전부 블로킹 호출이다.
/// - CALayer, RotationCoordinator, 게시 상태는 메인.
///   코디네이터의 KVO 는 헤더가 메인 큐 전달을 보장한다.
///
/// 이번 단계에는 녹화가 없다. AVCaptureMovieFileOutput 은 다음 작업이다.
@MainActor
@Observable
final class CameraController {

    // MARK: 게시 상태 (오버레이가 읽는다)

    private(set) var previewAngle: CGFloat = 0
    private(set) var captureAngle: CGFloat = 0
    /// 프리뷰 connection 에 실제로 설정된 값. 우리가 넣은 값이 아니라 읽어온 값이다.
    private(set) var appliedAngle: CGFloat = 0
    private(set) var appliedSupported = true

    /// KVO 가 조용히 안 걸리는 경우를 구분하기 위한 콜백 횟수.
    /// 기기를 돌렸는데 안 늘면 KVO 미동작, 느는데 각도가 그대로면 각도가 안 변하는 것이다.
    private(set) var previewObservationCount = 0
    private(set) var captureObservationCount = 0

    /// 진단용. capture KVO 가 울릴 때마다 preview 각도를 **직접 읽은** 값이다.
    /// KVO 로 받은 previewAngle 과 다르면 통지가 안 온 것이고,
    /// 같은 채로 자세가 바뀌어도 그대로면 값 자체가 안 변하는 것이다.
    private(set) var polledPreviewAngle: CGFloat = 0
    private(set) var previewKVOMismatch = false

    private(set) var deviceOrientation: UIDeviceOrientation = .unknown
    private(set) var videoAuthorization: AVAuthorizationStatus = .notDetermined
    private(set) var audioAuthorization: AVAuthorizationStatus = .notDetermined
    private(set) var sessionState = "미시작"
    private(set) var coordinatorState = "미생성"
    private(set) var hasAudioInput = false
    private(set) var audioModeState = "-"

    // MARK: 녹화 상태 (1-4)

    private(set) var isRecording = false
    /// 녹화 시작 시점에 동결한 각도. 녹화 중에는 절대 바뀌지 않는다.
    private(set) var frozenAngle: CGFloat?
    private(set) var recorderState = "대기"
    private(set) var clipCount = 0
    private(set) var lastClipName = "-"
    /// 마지막 클립이 녹화 도중 자세가 바뀐 오염 클립인지.
    private(set) var lastContaminated = false
    private(set) var recordedSpecs: [ClipSpec] = []
    /// 녹화가 파일을 남기지 못한 횟수. 0 이 아니면 촬영 데이터를 믿으면 안 된다.
    private(set) var saveFailureCount = 0
    private(set) var lastFailure = "-"
    /// 사진 앱 저장 대상. 마지막으로 성공한 클립.
    private(set) var lastClipURL: URL?
    private(set) var saveState = "-"
    private(set) var photoAuthorization = "미확인"
    /// COMPARE 결과는 콘솔로 나간다. 버튼이 먹었는지 화면에서 구분하기 위한 표시.
    private(set) var compareState = "-"
    private var compareCount = 0

    // MARK: 보관

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.chrisholic.mellow.session")

    /// 코디네이터가 device 와 previewLayer 를 **weak** 로 잡는다.
    /// device 는 우리가 강하게 쥔다.
    private var device: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewObservation: NSKeyValueObservation?
    private var captureObservation: NSKeyValueObservation?

    /// 레이어는 **약하게** 잡는다.
    /// 강한 참조를 하나 더 쥐면 뷰가 죽어도 레이어가 살아남아
    /// "살아 있지만 뷰 계층에 없는" 상태가 된다. 그 상태의 preview 각도는
    /// 여전히 0 이고, 원인만 안 보이게 된다.
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    private var orientationObserver: NSObjectProtocol?
    private let recorder = MovieRecorder()

    // MARK: 시작 / 정지

    func start() async {
        beginDeviceOrientationTracking()

        videoAuthorization = await CameraPermissions.resolve(.video)
        audioAuthorization = await CameraPermissions.resolve(.audio)

        guard videoAuthorization == .authorized else {
            sessionState = "카메라 권한 없음 (\(videoAuthorization.shortText))"
            log("permission")
            return
        }

        recorder.onStart = { [weak self] url in
            Task { @MainActor in
                self?.recorderState = "녹화 중"
                print("MREC started file=\(url.lastPathComponent)")
            }
        }
        recorder.onFinish = { [weak self] url, error in
            Task { @MainActor in self?.handleRecordingFinished(url: url, error: error) }
        }

        configureAndRun(audioAllowed: audioAuthorization == .authorized)
    }

    func stop() {
        previewObservation = nil
        captureObservation = nil
        rotationCoordinator = nil
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            self.orientationObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()

        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    /// 0단계(기본값 관찰)를 위해 **카메라 설정을 아무것도 건드리지 않는다.**
    /// sessionPreset 도 지정하지 않는다 — 지정하면 "설정이 바꾼 것"과
    /// "원래 그랬던 것"을 구분할 수 없다. 스펙 고정은 1-3 작업이다.
    private func configureAndRun(audioAllowed: Bool) {
        sessionState = "구성 중"
        let session = self.session
        let movieOutput = recorder.output

        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back) else {
                Task { @MainActor in self.sessionState = "후면 카메라를 찾지 못했다" }
                return
            }

            var failure: String?
            var addedAudio = false

            session.beginConfiguration()
            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    failure = "비디오 입력을 추가할 수 없다"
                }
            } catch {
                failure = "비디오 입력 생성 실패: \(error.localizedDescription)"
            }

            var audioModeText = "오디오 입력 없음"
            if failure == nil, audioAllowed, let microphone = AVCaptureDevice.default(for: .audio) {
                do {
                    let audioInput = try AVCaptureDeviceInput(device: microphone)
                    if session.canAddInput(audioInput) {
                        session.addInput(audioInput)
                        addedAudio = true
                        audioModeText = Self.applyStereoIfPossible(audioInput)
                    }
                } catch {
                    print("MREC audio-input-failed \(error.localizedDescription)")
                }
            }

            if failure == nil {
                if session.canAddOutput(movieOutput) {
                    session.addOutput(movieOutput)
                } else {
                    failure = "MovieFileOutput 을 추가할 수 없다"
                }
            }
            session.commitConfiguration()

            if failure == nil { session.startRunning() }
            let running = session.isRunning

            Task { @MainActor in
                self.device = camera
                self.hasAudioInput = addedAudio
                self.audioModeState = audioModeText
                self.sessionState = failure ?? (running ? "실행 중" : "시작 실패")
                // 레이어가 이미 윈도우에 붙어 있었다면 여기서 코디네이터가 만들어진다.
                self.makeCoordinatorIfPossible()
                self.log("configured")
            }
        }
    }

    /// 스테레오 녹음을 켠다. sessionQueue 에서 부른다.
    ///
    /// 기본값은 모노(`.none`)다. 기본 카메라 앱은 2ch 로 찍는데 우리는 1ch 였고,
    /// 같은 조건에서 저역 에너지가 5배 차이났다(1-4 실측). 그 차이를 좁히려는 변경이다.
    ///
    /// iOS 18+ 전용이라 17 에서는 모노로 남는다. 기기 간 채널 수가 갈리지만
    /// **한 기기 안에서는 일정**하므로 세션 내 스펙 일치는 깨지지 않는다.
    /// 우리가 막아야 하는 것은 한 세션 안에서 갈리는 것이지 기기 간 차이가 아니다.
    ///
    /// 헤더 주의사항: 내장 마이크로 라우팅될 때만 적용되고 외장 마이크에서는 무시된다.
    nonisolated private static func applyStereoIfPossible(_ input: AVCaptureDeviceInput) -> String {
        guard #available(iOS 18.0, *) else {
            print("MAUD stereo 미적용 — iOS 18 미만")
            return "모노 (iOS 18 미만)"
        }
        guard input.isMultichannelAudioModeSupported(.stereo) else {
            print("MAUD stereo 미적용 — 기기가 지원하지 않음")
            return "모노 (기기 미지원)"
        }
        input.multichannelAudioMode = .stereo
        print("MAUD stereo 적용 (multichannelAudioMode=.stereo)")
        return "스테레오"
    }

    // MARK: 프리뷰 레이어 부착
    //
    // 조건은 소유가 아니라 **윈도우에 붙어 있느냐**다.
    // 레이어를 지정하지 않았거나 / 뷰 계층에 없거나 / 해제됐으면
    // videoRotationAngleForHorizonLevelPreview 가 조용히 0 을 반환한다.
    // 그래서 makeUIView 가 아니라 didMoveToWindow 에서 부른다.

    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        previewLayer.session = session
        makeCoordinatorIfPossible()
    }

    func detach() {
        previewObservation = nil
        captureObservation = nil
        rotationCoordinator = nil
        previewLayer = nil
        coordinatorState = "미생성 (뷰 계층에서 빠짐)"
        log("detach")
    }

    private func makeCoordinatorIfPossible() {
        guard let device else {
            coordinatorState = "대기 (device 없음)"
            return
        }
        guard let previewLayer else {
            coordinatorState = "대기 (previewLayer 없음)"
            return
        }

        // 재부착 때마다 새로 만든다. 낡은 관찰은 먼저 끊는다.
        previewObservation = nil
        captureObservation = nil

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device,
                                                              previewLayer: previewLayer)
        rotationCoordinator = coordinator
        coordinatorState = "생성됨"

        // 진단: 코디네이터가 우리 레이어를 실제로 붙잡았는지 남긴다.
        // previewLayer 를 nil 로 준 대조군은 0 이 나와야 한다. 우리 것이 0 이 아니면
        // 레이어가 뷰 계층에 살아 있다는 뜻이다(헤더가 명시한 0 반환 조건의 대우).
        let control = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        print("MROT attach inHierarchy=\(previewLayer.superlayer != nil) "
              + "layerMatch=\(coordinator.previewLayer === previewLayer) "
              + "withLayer=\(Int(coordinator.videoRotationAngleForHorizonLevelPreview)) "
              + "withoutLayer=\(Int(control.videoRotationAngleForHorizonLevelPreview))")

        previewObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            // 헤더가 메인 큐 전달을 보장한다.
            MainActor.assumeIsolated {
                self?.handlePreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
            }
        }

        captureObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            MainActor.assumeIsolated {
                self?.handleCaptureAngle(coordinator.videoRotationAngleForHorizonLevelCapture)
            }
        }

        log("coordinator")
    }

    // MARK: 각도 반영

    /// 인터페이스가 Portrait 으로 고정된 동안 이 각도는 **상수 90°** 다.
    /// 그래서 previewObservationCount 가 1 에서 멈춰 있는 것은 고장이 아니라
    /// 값이 한 번도 안 변했다는 신호다.
    ///
    /// 근거(1-2 실측, iPhone 12 / 후면 광각):
    /// - portrait · landscapeLeft · landscapeRight · upsideDown · faceUp 전부 90°.
    ///   capture KVO 가 울릴 때마다 이 값을 직접 읽어 대조했고 불일치 0 건이었다.
    /// - 같은 device 로 previewLayer: nil 코디네이터를 만들면 0 을 반환한다.
    ///   우리 쪽이 90 이라는 것 자체가 레이어가 뷰 계층에 살아 있다는 증거다.
    ///
    /// 이유: 프리뷰 레이어와 카메라 센서가 둘 다 기기에 고정돼 있다.
    /// 인터페이스가 안 돌면 둘의 상대 관계가 불변이라 보정할 각도도 안 변한다.
    /// 인터페이스 회전을 허용하게 되면 이 전제가 깨진다.
    private func handlePreviewAngle(_ angle: CGFloat) {
        previewObservationCount += 1
        previewAngle = angle
        applyToPreview(angle)
        log("previewKVO")
    }

    private func handleCaptureAngle(_ angle: CGFloat) {
        captureObservationCount += 1
        captureAngle = angle
        // 적용할 출력이 아직 없다. MovieFileOutput 은 다음 작업이라 표시만 한다.

        // capture KVO 를 공짜 샘플링 시계로 쓴다. 회전할 때마다 반드시 울리므로
        // 여기서 preview 각도를 직접 읽어 KVO 로 받은 값과 대조하면
        // "값이 안 변한다"와 "통지가 안 온다"를 구분할 수 있다.
        if let polled = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview {
            polledPreviewAngle = polled
            if polled != previewAngle {
                previewKVOMismatch = true
                print("MROT PREVIEW_KVO_MISMATCH polled=\(Int(polled)) stored=\(Int(previewAngle))")
            }
        }
        log("captureKVO")
    }

    /// 지원하지 않는 각도를 넣으면 옵셔널 반환이 아니라 NSInvalidArgumentException 이다.
    /// 반드시 isVideoRotationAngleSupported(_:) 를 먼저 확인한다.
    private func applyToPreview(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection else {
            appliedSupported = false
            return
        }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
            appliedSupported = true
        } else {
            appliedSupported = false
        }
        // 넣은 값이 아니라 실제로 들어간 값을 읽는다.
        appliedAngle = connection.videoRotationAngle
    }

    // MARK: 녹화 (1-4)

    func toggleRecording() {
        isRecording ? requestStop() : requestStart()
    }

    /// 시작 시점의 capture 각도를 **동결**한다.
    /// 녹화 중에는 이 각도를 바꾸지 않는다. 바꾸면 한 파일 안에서 방향이 섞이고
    /// 파일에는 흔적이 남지 않아 나중에 원인을 찾을 수 없다.
    private func requestStart() {
        guard !isRecording else { return }
        guard sessionState == "실행 중" else {
            recorderState = "세션이 실행 중이 아니다"
            return
        }

        let angle = captureAngle
        let (name, url) = nextClipDestination(angle: angle)

        // 0단계의 핵심. 결과 파일(ClipSpec)과 대조하려면 소스가 뭘 쓰고 있었는지
        // 같은 시점에 찍어둬야 한다. 둘이 갈리면 인코더 태깅 문제다.
        logSourceSettings(frozen: angle, fileName: name)

        let recorder = self.recorder
        sessionQueue.async { [weak self] in
            let failure = recorder.start(to: url, rotationAngle: angle)
            Task { @MainActor in
                guard let self else { return }
                if let failure {
                    self.recorderState = "시작 실패: \(failure)"
                    print("MREC start-failed \(failure)")
                    return
                }
                self.isRecording = true
                self.frozenAngle = angle
            }
        }
    }

    /// 다음 클립의 파일명과 경로.
    ///
    /// clipCount 는 앱을 다시 켜면 0 으로 돌아가는데 파일명은 그 값으로 짓고 있었다.
    /// 이전 실행에서 만든 파일과 이름이 겹치면 AVCaptureMovieFileOutput 이
    /// `Cannot Save` 로 녹화를 실패시킨다(실제로 7번 중 3번이 이렇게 날아갔다).
    /// 그래서 메모리 카운터가 아니라 **디스크에 있는 번호**에서 이어붙인다.
    ///
    /// 세션 디렉터리 구조는 Phase 2 라 여기서는 최소로만 막는다.
    private func nextClipDestination(angle: CGFloat) -> (name: String, url: URL) {
        let directory = ClipLibrary.directory()
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let highest = existing.compactMap { name -> Int? in
            guard name.hasPrefix("spike_"), name.hasSuffix(".mov") else { return nil }
            return Int(name.dropFirst("spike_".count).prefix(3))
        }.max() ?? 0

        var index = highest + 1
        while true {
            let name = String(format: "spike_%03d_%@_%03d.mov",
                              index, deviceOrientation.shortText, Int(angle))
            let url = directory.appendingPathComponent(name)
            // 번호를 이어붙였어도 마지막으로 한 번 더 확인한다. 덮어쓰는 것보다 낫다.
            if !FileManager.default.fileExists(atPath: url.path) {
                return (name, url)
            }
            index += 1
        }
    }

    private func requestStop() {
        recorderState = "정지 요청"
        let recorder = self.recorder
        sessionQueue.async { recorder.stop() }
    }

    private func handleRecordingFinished(url: URL, error: Error?) {
        isRecording = false

        let frozen = frozenAngle ?? 0
        let current = captureAngle
        // 녹화 도중 자세가 바뀌면 파일은 시작 각도로 동결됐는데 내용은 기울어진다.
        // 파일명에 시작 자세만 박히므로, 표시가 없으면 compare() 결과를 흐린다.
        let contaminated = frozen != current
        frozenAngle = nil

        var finalURL = url
        if contaminated {
            let base = url.deletingPathExtension().lastPathComponent
            let renamed = "\(base)_moved.\(url.pathExtension)"
            let target = url.deletingLastPathComponent().appendingPathComponent(renamed)
            do {
                try FileManager.default.moveItem(at: url, to: target)
                finalURL = target
            } catch {
                print("MREC rename-failed \(error.localizedDescription)")
            }
        }

        lastClipName = finalURL.lastPathComponent
        lastContaminated = contaminated
        recorderState = error == nil ? "종료" : "종료(에러)"
        if let error {
            // 저장 실패가 조용히 넘어가면 clipCount 가 안 늘어난 것으로만 드러나
            // 촬영 중에는 알아채기 어렵다. 화면에 남긴다.
            saveFailureCount += 1
            lastFailure = "\(finalURL.lastPathComponent): \(error.localizedDescription)"
        }

        print("MREC finished file=\(finalURL.lastPathComponent) "
              + "frozen=\(Int(frozen)) nowCapture=\(Int(current)) "
              + "contaminated=\(contaminated) "
              + "error=\(error?.localizedDescription ?? "none")")

        // 에러가 있어도 파일이 남을 수 있다. 존재 여부를 따로 본다.
        guard FileManager.default.fileExists(atPath: finalURL.path) else {
            print("MREC no-file \(finalURL.lastPathComponent)")
            return
        }
        clipCount += 1
        lastClipURL = finalURL
        Task { await loadSpec(from: finalURL, contaminated: contaminated) }
    }

    /// 마지막으로 성공한 클립을 사진 앱에 저장한다. (1-18)
    func saveLastClipToPhotos() {
        guard let url = lastClipURL else {
            saveState = "저장할 클립이 없다"
            return
        }
        saveState = "저장 중 \(url.lastPathComponent)"
        Task {
            do {
                let status = try await PhotoLibrarySaver.save(url)
                photoAuthorization = status.shortText
                saveState = "저장 완료 \(url.lastPathComponent)"
                print("MSAVE ok file=\(url.lastPathComponent) auth=\(status.shortText)")
            } catch {
                photoAuthorization = PhotoLibrarySaver.currentStatus().shortText
                saveState = "저장 실패: \(error.localizedDescription)"
                print("MSAVE failed file=\(url.lastPathComponent) \(error.localizedDescription)")
            }
        }
    }

    private func loadSpec(from url: URL, contaminated: Bool) async {
        do {
            let spec = try await ClipSpec.load(from: url)
            recordedSpecs.append(spec)
            print("########## \(spec.name)\(contaminated ? "   [오염: 녹화 중 자세 변경]" : "") ##########")
            print(spec.description)
        } catch {
            print("MREC spec-load-failed \(url.lastPathComponent): \(error)")
        }
    }

    func compareRecorded() {
        compareCount += 1
        guard !recordedSpecs.isEmpty else {
            compareState = "녹화된 클립이 없다 (#\(compareCount))"
            print("MREC compare: 녹화된 클립이 없다")
            return
        }
        // 결과 자체는 콘솔로 간다. 화면에는 버튼이 먹었다는 것만 남긴다.
        compareState = "compared \(recordedSpecs.count) clips (#\(compareCount))"
        print("########## 누적 \(recordedSpecs.count)개 대조 ##########")
        print(ClipSpec.compare(recordedSpecs))
    }

    /// 소스 설정 스냅샷. ClipSpec 은 결과 파일을 보고, 이건 기기가 뭘 쓰는지를 본다.
    private func logSourceSettings(frozen: CGFloat, fileName: String) {
        guard let device else {
            print("MREC source: device 없음")
            return
        }
        let format = device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let subType = ClipSpec.fourCCText(format.formatDescription.mediaSubType.rawValue)
        let codecs = recorder.output.availableVideoCodecTypes.map(\.rawValue).joined(separator: ",")
        let minFD = device.activeVideoMinFrameDuration
        let maxFD = device.activeVideoMaxFrameDuration

        logAudioSession(fileName: fileName)

        print("MREC source file=\(fileName) preset=\(session.sessionPreset.rawValue) "
              + "activeFormat=\(dimensions.width)x\(dimensions.height) sub=\(subType) "
              + "minFD=\(minFD.value)/\(minFD.timescale) maxFD=\(maxFD.value)/\(maxFD.timescale) "
              + "colorSpace=\(colorSpaceText(device.activeColorSpace)) "
              + "codecs=[\(codecs)] audioInput=\(hasAudioInput) frozen=\(Int(frozen))")
    }

    /// 오디오 런타임 값 관찰. **아무것도 설정하지 않는다.**
    ///
    /// AVCaptureSession 의 `automaticallyConfiguresApplicationAudioSession` 기본값이 YES 라
    /// 카테고리와 마이크·폴라 패턴은 AVFoundation 이 이미 고르고 있다. 헤더는 무엇을
    /// 고르는지 말해주지 않으므로 런타임에 읽어야 한다. mode 는 헤더에 언급이 없어서
    /// 실제 값이 무엇인지가 이번 관찰의 핵심이다.
    private func logAudioSession(fileName: String) {
        let session = AVAudioSession.sharedInstance()

        let inputs = session.currentRoute.inputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")

        var dataSourceText = "없음"
        var polarText = "없음"
        var supportedText = "없음"
        if let input = session.currentRoute.inputs.first {
            if let selected = input.selectedDataSource {
                dataSourceText = "\(selected.dataSourceName)"
                    + (selected.location.map { "@\($0.rawValue)" } ?? "")
                    + (selected.orientation.map { "/\($0.rawValue)" } ?? "")
                polarText = selected.selectedPolarPattern?.rawValue ?? "미선택"
                supportedText = (selected.supportedPolarPatterns ?? [])
                    .map(\.rawValue).joined(separator: "|")
                if supportedText.isEmpty { supportedText = "없음" }
            }
            if let sources = input.dataSources, !sources.isEmpty {
                dataSourceText += "  (전체 \(sources.count): "
                    + sources.map(\.dataSourceName).joined(separator: ",") + ")"
            }
        }

        print("MAUD file=\(fileName) category=\(session.category.rawValue) "
              + "mode=\(session.mode.rawValue) options=\(session.categoryOptions.rawValue) "
              + "sampleRate=\(session.sampleRate) inputChannels=\(session.inputNumberOfChannels) "
              + "route=[\(inputs)]")
        // 스테레오일 때 좌/우가 어느 쪽으로 잡히는지. 가로 촬영에서 의미가 생긴다.
        print("MAUD   inputOrientation=\(session.inputOrientation.rawValue) "
              + "preferred=\(session.preferredInputOrientation.rawValue) "
              + "appliedMode=\(audioModeState)")
        print("MAUD   dataSource=\(dataSourceText)")
        print("MAUD   polarPattern=\(polarText)  supported=[\(supportedText)]")
        print("MAUD   captureInput=\(audioInputCapabilityText())")
    }

    /// AVCaptureDeviceInput 쪽에서 읽을 수 있는 값. 상당수가 iOS 18+ 라 분기한다.
    private func audioInputCapabilityText() -> String {
        guard let audioInput = session.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.audio) }) else {
            return "오디오 입력 없음"
        }
        guard #available(iOS 18.0, *) else {
            return "multichannelAudioMode/windNoiseRemoval 사용 불가 (iOS 18+)"
        }
        let stereoSupported = audioInput.isMultichannelAudioModeSupported(.stereo)
        let foaSupported = audioInput.isMultichannelAudioModeSupported(.firstOrderAmbisonics)
        return "multichannelAudioMode=\(audioInput.multichannelAudioMode.rawValue) "
            + "stereoSupported=\(stereoSupported) foaSupported=\(foaSupported) "
            + "windNoiseRemovalSupported=\(audioInput.isWindNoiseRemovalSupported) "
            + "windNoiseRemovalEnabled=\(audioInput.isWindNoiseRemovalEnabled)"
    }

    private func colorSpaceText(_ space: AVCaptureColorSpace) -> String {
        // appleLog2 는 iOS 26.0+ 라 배포 타깃(17.0)에서는 가용성 분기가 필요하다.
        if #available(iOS 26.0, *), space == .appleLog2 { return "appleLog2" }
        switch space {
        case .sRGB: return "sRGB"
        case .P3_D65: return "P3_D65"
        case .HLG_BT2020: return "HLG_BT2020"
        case .appleLog: return "appleLog"
        default: return "unknown(\(space.rawValue))"
        }
    }

    // MARK: 기기 방향
    //
    // 인터페이스를 세로로 잠갔기 때문에 시스템이 알아서 갱신해주지 않는다.
    // beginGeneratingDeviceOrientationNotifications() 를 부르지 않으면 .unknown 이다.

    private func beginDeviceOrientationTracking() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDeviceOrientation()
            }
        }
        updateDeviceOrientation()
    }

    private func updateDeviceOrientation() {
        deviceOrientation = UIDevice.current.orientation
        log("deviceOrientation")
    }

    // MARK: 로그
    //
    // 오버레이만으로는 회전 순서를 되짚기 어렵다. 콘솔에 한 줄씩 남긴다.

    private func log(_ reason: String) {
        print("MROT \(reason) preview=\(Int(previewAngle)) capture=\(Int(captureAngle)) "
              + "pollP=\(Int(polledPreviewAngle)) mism=\(previewKVOMismatch) "
              + "applied=\(Int(appliedAngle)) sup=\(appliedSupported) "
              + "dev=\(deviceOrientation.shortText) "
              + "obsP=\(previewObservationCount) obsC=\(captureObservationCount) "
              + "coord=\(coordinatorState) session=\(sessionState)")
    }
}

extension UIDeviceOrientation {
    var shortText: String {
        switch self {
        case .unknown: return "unknown"
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "upsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}
