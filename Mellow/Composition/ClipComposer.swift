import AVFoundation
import CoreMedia
import Foundation

/// AVMutableComposition 조립과 이음새 진단. (Tasks 1-12 ~ 1-14)
///
/// UI 의존이 없다. ClipSpec 과 같은 이유로 macOS 에서 단독 검증할 수 있게 둔다.
enum ClipComposer {

    struct Result {
        let composition: AVMutableComposition
        let report: String
        /// 컴포지션 비디오 트랙에 실제로 적용된 회전각.
        let appliedDegrees: Int
        /// transform 이 달라 회전이 버려진 클립 수.
        let transformConflicts: Int
        let buildMilliseconds: Double
    }

    enum Failure: Error {
        case noClips
        case trackCreationFailed
        case noVideoTrack(String)
    }

    /// 클립을 순서대로 이어붙인다.
    ///
    /// 커서를 비디오·오디오 **각각** 따로 둔다. `insertTimeRange` 는 삽입이라
    /// 이미 미디어가 있는 지점에 넣으면 뒤를 밀어내므로, 항상 각 트랙의 끝에 붙여야 한다.
    /// 그리고 두 커서의 차이가 곧 A/V 어긋남이다 — 하나로 통일하면 숫자는 예뻐지지만
    /// 실제 어긋남은 그대로 남고 관측만 불가능해진다.
    ///
    /// 어긋남이 임계를 넘어도 **자르지 않는다.** 원인을 모른 채 증상을 덮는 것이고,
    /// 클립을 10개로 늘렸을 때(1-15) 누적이 얼마나 되는지를 못 보게 된다.
    static func compose(_ specs: [ClipSpec]) async throws -> Result {
        guard !specs.isEmpty else { throw Failure.noClips }

        let startedAt = Date()
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw Failure.trackCreationFailed }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var videoCursor = CMTime.zero
        var audioCursor = CMTime.zero
        var sourceDurationSum = 0.0

        var appliedTransform: CGAffineTransform?
        var appliedDegrees = 0
        var conflicts = 0

        var lines: [String] = []
        /// 클립을 하나 붙일 때마다의 누적 어긋남(초). 추세 판정에 쓴다.
        var cumulativeDrifts: [Double] = []

        for (index, spec) in specs.enumerated() {
            let asset = AVURLAsset(url: spec.url)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            guard let sourceVideo = videoTracks.first else {
                throw Failure.noVideoTrack(spec.name)
            }

            // 에셋 duration 이 아니라 트랙의 실제 timeRange 를 쓴다.
            // 트랙 시작이 0 이 아닐 수 있고, 비디오와 오디오 길이가 서로 다를 수 있다.
            let videoRange = try await sourceVideo.load(.timeRange)
            let transform = try await sourceVideo.load(.preferredTransform)

            let videoStart = videoCursor
            try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: videoCursor)
            videoCursor = videoCursor + videoRange.duration

            var audioStart: CMTime?
            var audioDuration = CMTime.zero
            if let sourceAudio = audioTracks.first, let audioTrack {
                let audioRange = try await sourceAudio.load(.timeRange)
                audioStart = audioCursor
                try audioTrack.insertTimeRange(audioRange, of: sourceAudio, at: audioCursor)
                audioDuration = audioRange.duration
                audioCursor = audioCursor + audioRange.duration
            }

            // 컴포지션 트랙은 transform 을 하나만 가질 수 있다.
            // 첫 클립 것을 적용하고, 나머지 클립의 회전은 병합 시점에 버려진다.
            let degrees = rotationAngleDegrees(of: transform)
            var conflictNote = ""
            if appliedTransform == nil {
                appliedTransform = transform
                appliedDegrees = degrees
                videoTrack.preferredTransform = transform
            } else if degrees != appliedDegrees {
                conflicts += 1
                conflictNote = "   ← transform 불일치, 이 클립의 회전은 버려짐"
            }

            sourceDurationSum += spec.duration
            let drift = audioCursor.seconds - videoCursor.seconds
            cumulativeDrifts.append(drift)

            lines.append("MCOMP clip=\(index + 1) \(spec.name)  angle=\(degrees)°\(conflictNote)")
            lines.append("      video [\(seconds(videoStart)) → \(seconds(videoCursor))]"
                         + "  audio [\(audioStart.map(seconds) ?? "없음") → "
                         + "\(audioStart == nil ? "없음" : seconds(audioCursor))]"
                         + "  Δaudio=\(seconds(audioDuration))"
                         + "  drift=\(signed(drift))")
        }

        let finalDrift = cumulativeDrifts.last ?? 0
        let frameSeconds = 1.0 / 30.0
        let overThreshold = abs(finalDrift) > frameSeconds

        lines.append("")
        lines.append("MCOMP 합산 검증\(overThreshold ? "   ← 임계 초과 (1프레임=0.033s)" : "")")
        lines.append("      composition.duration   \(seconds(composition.duration))")
        lines.append("      videoCursor            \(seconds(videoCursor))")
        lines.append("      audioCursor            \(seconds(audioCursor))")
        lines.append(String(format: "      소스 duration 합       %.3f", sourceDurationSum))
        lines.append("      A/V 최종 어긋남        \(signed(finalDrift)) s"
                     + String(format: "  (%.2f 프레임)", finalDrift / frameSeconds))
        lines.append("      클립당 평균            "
                     + signed(finalDrift / Double(max(specs.count, 1))) + " s")
        lines.append("      추세                   \(trendText(cumulativeDrifts))")
        lines.append("      transform 적용         \(appliedDegrees)°  (불일치 클립 \(conflicts)개)")

        let elapsed = Date().timeIntervalSince(startedAt) * 1000
        lines.append(String(format: "      조립 소요              %.1f ms", elapsed))

        return Result(
            composition: composition,
            report: lines.joined(separator: "\n"),
            appliedDegrees: appliedDegrees,
            transformConflicts: conflicts,
            buildMilliseconds: elapsed
        )
    }

    /// 누적 어긋남이 계속 커지면 구조적 문제(프레임 길이 불일치)이고,
    /// 왔다 갔다 하면 반올림 잡음이다. 대응 방식이 완전히 다르다.
    private static func trendText(_ drifts: [Double]) -> String {
        guard drifts.count >= 3 else {
            return "표본 부족 (클립 \(drifts.count)개 — 1-15에서 10개로 판단)"
        }
        var rising = true
        var falling = true
        for index in 1..<drifts.count {
            if drifts[index] < drifts[index - 1] { rising = false }
            if drifts[index] > drifts[index - 1] { falling = false }
        }
        if rising && drifts.last! > drifts.first! { return "단조 증가 (구조적 누적 의심)" }
        if falling && drifts.last! < drifts.first! { return "단조 감소 (구조적 누적 의심)" }
        return "진동 (반올림 잡음으로 보임)"
    }

    private static func seconds(_ time: CMTime) -> String {
        guard time.isValid, time.isNumeric else { return "(무효)" }
        return String(format: "%.3f", time.seconds)
    }

    private static func signed(_ value: Double) -> String {
        String(format: "%+.4f", value)
    }
}
