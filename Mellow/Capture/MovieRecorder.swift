@preconcurrency import AVFoundation
import Foundation

/// AVCaptureMovieFileOutput 소유와 녹화 시작/정지. (Tasks 1-4)
///
/// 10초 자동 정지(1-5)와 1초 미만 폐기(1-7)는 다음 작업이다.
/// 파일 배치도 여기서 정하지 않는다 — 세션 디렉터리는 Phase 2 다.
///
/// `@unchecked Sendable` — 출력을 만지는 start/stop 은 sessionQueue 에서만 부르고,
/// 콜백 클로저는 세션이 돌기 전에 메인에서 한 번만 설정한다.
/// 컴파일러가 확인해주지 못하는 규약이라 Swift 6 승격(Phase 2) 때 다시 본다.
final class MovieRecorder: @unchecked Sendable {

    let output = AVCaptureMovieFileOutput()

    /// 출력이 델리게이트를 강하게 잡지 않는다. 우리가 쥐고 있어야 한다.
    private let bridge = RecordingBridge()

    var onStart: ((URL) -> Void)? {
        get { bridge.onStart }
        set { bridge.onStart = newValue }
    }

    var onFinish: ((URL, Error?) -> Void)? {
        get { bridge.onFinish }
        set { bridge.onFinish = newValue }
    }

    var isRecording: Bool { output.isRecording }

    /// sessionQueue 에서 부른다. 성공하면 nil, 실패하면 사유를 돌려준다.
    ///
    /// 각도를 적용하지 못하면 **녹화를 시작하지 않는다.**
    /// 방향이 틀린 파일을 만드는 것보다 안 만드는 편이 낫다.
    func start(to url: URL, rotationAngle: CGFloat) -> String? {
        // 마지막 방어선. 녹화 중에 각도를 바꾸면 한 파일 안에서 방향이 섞이는데,
        // 파일에는 아무 흔적도 남지 않아 나중에 원인을 찾을 수 없다.
        guard !output.isRecording else {
            return "이미 녹화 중이다"
        }
        guard let connection = output.connection(with: .video) else {
            return "비디오 connection 이 없다"
        }
        guard connection.isVideoRotationAngleSupported(rotationAngle) else {
            return "지원하지 않는 각도 \(Int(rotationAngle))°"
        }
        connection.videoRotationAngle = rotationAngle
        output.startRecording(to: url, recordingDelegate: bridge)
        return nil
    }

    /// sessionQueue 에서 부른다.
    func stop() {
        guard output.isRecording else { return }
        output.stopRecording()
    }
}

/// AVCaptureFileOutputRecordingDelegate 가 NSObject 를 요구한다.
/// CameraController 는 @Observable 이라 NSObject 가 아니어서 브리지를 둔다.
/// 콜백은 임의 큐로 도착한다.
private final class RecordingBridge: NSObject, AVCaptureFileOutputRecordingDelegate {

    var onStart: ((URL) -> Void)?
    var onFinish: ((URL, Error?) -> Void)?

    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        onStart?(fileURL)
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        onFinish?(outputFileURL, error)
    }
}
