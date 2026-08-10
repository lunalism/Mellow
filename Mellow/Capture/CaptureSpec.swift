@preconcurrency import AVFoundation

// 촬영 스펙 고정 (1-3).
//
// 한 세션의 모든 클립이 완전히 동일한 스펙이어야 재인코딩 없는 병합이 가능하다.
// 세 가지를 각각 잠근다 — 하나라도 빠지면 클립마다 스펙이 갈린다.
//
//   (1) 해상도  sessionPreset 이 잡는다
//   (2) fps     preset 이 보장하지 않는다. 어두운 곳에서 시스템이 자동으로
//               낮추므로 device 에서 따로 잠근다
//   (3) 코덱    최신 기기 기본값은 HEVC 다. H.264 를 명시해야 한다
//
// 여기의 함수는 전부 sessionQueue 에서 호출한다.
enum CaptureSpec {

    static let preset: AVCaptureSession.Preset = .hd1920x1080
    static let frameRate: Double = 30
    static let videoCodec: AVVideoCodecType = .h264

    /// 30fps 를 CMTime 으로. min/max 프레임 지속시간에 같은 값을 넣어 잠근다.
    static var frameDuration: CMTime {
        CMTime(value: 1, timescale: CMTimeScale(frameRate))
    }

    /// 클립 최대 길이 (1-5). 타이머가 아니라 프레임워크가 직접 끊는다.
    static let maxClipDuration = CMTime(seconds: 10, preferredTimescale: 600)

    /// 이 길이 미만이면 폐기한다 (1-7).
    ///
    /// 버튼을 누른 시간이 아니라 저장된 파일의 duration 으로 판정한다.
    /// 녹화 시작에는 지연이 있어 두 값이 일치하지 않는다.
    static let minClipDuration = CMTime(seconds: 1, preferredTimescale: 600)

    // MARK: - 녹화 길이 제한

    /// 10초 자동 정지를 건다.
    ///
    /// 이 한도로 종료되면 델리게이트에 `AVError.maximumDurationReached` 가
    /// 에러로 전달되지만 파일은 정상이다. 실패로 처리하면 안 된다.
    static func applyRecordingLimit(to output: AVCaptureMovieFileOutput) {
        output.maxRecordedDuration = maxClipDuration
        print("[spec] ✓ maxRecordedDuration = \(ClipSpec.describe(time: maxClipDuration))")
    }

    // MARK: - (1) 해상도

    /// preset 을 지정한다.
    ///
    /// 반환값을 무시하면 다른 해상도로 촬영하면서 구성은 성공한 것처럼 보인다.
    /// 호출부가 반드시 처리하도록 `@discardableResult` 를 붙이지 않는다.
    /// - Returns: 지정에 성공하면 true.
    static func applyPreset(to session: AVCaptureSession) -> Bool {
        guard session.canSetSessionPreset(preset) else {
            print("[spec] ✕ preset \(preset.rawValue) 지원 안 함 — 현재 preset 유지: "
                  + session.sessionPreset.rawValue)
            return false
        }
        session.sessionPreset = preset
        print("[spec] ✓ preset = \(session.sessionPreset.rawValue)")
        return true
    }

    // MARK: - (2) 프레임레이트

    /// fps 를 고정하고 HDR 자동 조정을 끈다.
    ///
    /// preset 을 바꾸면 activeFormat 과 프레임 지속시간이 초기화되므로
    /// 반드시 `commitConfiguration()` 이후에 호출한다.
    /// - Returns: 실패 사유. 성공하면 nil.
    static func lockFrameRate(on device: AVCaptureDevice) -> String? {
        let format = device.activeFormat
        let ranges = format.videoSupportedFrameRateRanges

        print("[spec] activeFormat 지원 fps 범위: "
              + ranges.map { "\($0.minFrameRate)–\($0.maxFrameRate)" }.joined(separator: ", "))

        let supported = ranges.contains { $0.minFrameRate <= frameRate && frameRate <= $0.maxFrameRate }
        guard supported else {
            return "activeFormat 이 \(Int(frameRate))fps 를 지원하지 않습니다."
        }

        do {
            try device.lockForConfiguration()
        } catch {
            return "device 잠금 실패: \(error.localizedDescription)"
        }
        defer { device.unlockForConfiguration() }

        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration

        // HDR 이 켜지면 포맷 설명이 달라질 수 있다. 자동 조정을 끈다.
        if device.activeFormat.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            print("[spec] ✓ automaticallyAdjustsVideoHDREnabled = false "
                  + "(isVideoHDREnabled = \(device.isVideoHDREnabled))")
        } else {
            print("[spec] · activeFormat 이 HDR 을 지원하지 않음 — 조정 불필요")
        }

        print("[spec] ✓ fps 고정 min=\(ClipSpec.describe(time: device.activeVideoMinFrameDuration)) "
              + "max=\(ClipSpec.describe(time: device.activeVideoMaxFrameDuration))")
        return nil
    }

    // MARK: - (3) 코덱

    /// 비디오 코덱을 H.264 로 지정한다. 지정 전후의 outputSettings 를 모두 찍는다.
    ///
    /// 오디오는 건드리지 않는다. 기본값이 AAC 일 것으로 보고, 실제 파일에서
    /// 확인한 뒤 필요하면 그때 지정한다.
    /// - Returns: 실패 사유. 성공하면 nil.
    static func applyVideoCodec(to output: AVCaptureMovieFileOutput) -> String? {
        guard let connection = output.connection(with: .video) else {
            return "movieFileOutput 에 비디오 연결이 없습니다."
        }

        print("[spec] availableVideoCodecTypes = "
              + output.availableVideoCodecTypes.map(\.rawValue).joined(separator: ", "))
        print("[spec] outputSettings(지정 전) = \(output.outputSettings(for: connection))")

        guard output.availableVideoCodecTypes.contains(videoCodec) else {
            return "이 기기가 \(videoCodec.rawValue) 를 지원하지 않습니다."
        }

        output.setOutputSettings([AVVideoCodecKey: videoCodec], for: connection)
        print("[spec] outputSettings(지정 후) = \(output.outputSettings(for: connection))")
        return nil
    }
}
