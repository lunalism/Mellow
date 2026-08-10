@preconcurrency import AVFoundation

// AVCaptureMovieFileOutput 의 녹화 델리게이트.
//
// 콜백이 임의의 큐로 오므로 컨트롤러가 직접 받지 않고 이 객체가 받아
// 클로저로 넘긴다. 컨트롤러 쪽에서 메인으로 hop 한다.
// 불변인 @Sendable 클로저 두 개만 들고 있어 스레드 간 전달이 안전하다.
final class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {

    private let onStart: @Sendable (URL) -> Void
    private let onFinish: @Sendable (URL, Error?) -> Void

    init(onStart: @escaping @Sendable (URL) -> Void,
         onFinish: @escaping @Sendable (URL, Error?) -> Void) {
        self.onStart = onStart
        self.onFinish = onFinish
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        onStart(fileURL)
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // 에러가 있어도 파일이 쓸 만한 경우가 있다(AVErrorRecordingSuccessfullyFinishedKey).
        // 판단은 컨트롤러에 맡기고 여기서는 그대로 넘긴다.
        onFinish(outputFileURL, error)
    }
}
