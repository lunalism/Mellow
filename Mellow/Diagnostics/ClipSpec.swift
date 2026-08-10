import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

// 촬영된 파일의 실제 스펙을 읽고 비교하는 진단 유틸리티.
//
// Phase 1 의 1-8(여러 클립이 동일 스펙인지), 1-10(가로 클립 해상도),
// 1-11(preferredTransform 일치)에서 쓴다. passthrough 병합은 클립들의
// 스펙이 완전히 같아야 가능하므로, "어디가 다른지"를 짚어주는 것이 목적이다.
//
// UIKit·SwiftUI 에 의존하지 않는다. Foundation + AVFoundation 계열만 쓰므로
// 필요하면 Mac 에서 swiftc 로 단독 실행할 수 있다.

// MARK: - 스펙 모델

/// 비디오 트랙에서 읽어낸 값. 가공하지 않은 원본 그대로 담는다.
struct VideoTrackSpec {
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    /// 코덱 FourCC. 포맷 기술자가 없으면 nil.
    let codec: FourCharCode?
    /// 사람이 읽는 용도로만 쓴다. 비교에는 쓰지 않는다 — Float 정밀도 탓에
    /// 같은 30000/1001 도 파일마다 마지막 자리가 갈린다 (29.97003 vs 29.970032).
    let nominalFrameRate: Float
    /// 프레임 간격. 유리수라 정밀도 노이즈가 없어 프레임레이트 비교의 기준이 된다.
    /// 가변 프레임레이트 파일에서는 invalid 가 나올 수 있다.
    let minFrameDuration: CMTime
    /// 트랙 자체의 길이(timeRange.duration).
    let duration: CMTime
}

/// 오디오 트랙에서 읽어낸 값.
struct AudioTrackSpec {
    /// 포맷 ID FourCC (aac 등). 포맷 기술자가 없으면 nil.
    let formatID: FourCharCode?
    let sampleRate: Float64
    let channelCount: UInt32
    /// 트랙 자체의 길이(timeRange.duration).
    let duration: CMTime
}

/// 파일 하나의 스펙. 트랙이 없는 경우를 nil 로 구분한다.
///
/// 애셋 duration 과 트랙별 duration 을 모두 들고 있다. 녹화 종료 시점에
/// 오디오 샘플 경계와 비디오 프레임 경계가 정확히 맞지 않아 두 트랙 길이가
/// 미세하게 어긋날 수 있는데, 애셋 duration 은 긴 쪽으로 뭉뚱그려져
/// 그 어긋남이 보이지 않는다. 이 차이가 클립마다 쌓이면 병합 후 뒤쪽
/// 클립에서 오디오가 밀린다.
struct ClipSpec {
    let url: URL
    let duration: CMTime
    let video: VideoTrackSpec?
    let audio: AudioTrackSpec?

    /// 같은 클립 안에서 비디오와 오디오 길이가 어긋난 정도(비디오 - 오디오).
    /// 어긋남이 없거나 한쪽 트랙이 없으면 nil.
    var trackDurationSkew: CMTime? {
        guard let video, let audio,
              video.duration.isNumeric, audio.duration.isNumeric else { return nil }
        let skew = CMTimeSubtract(video.duration, audio.duration)
        return CMTimeCompare(skew, .zero) == 0 ? nil : skew
    }
}

// MARK: - 읽기

extension ClipSpec {

    /// 동영상 파일에서 스펙을 읽는다.
    ///
    /// iOS 16 에서 AVAsset 의 동기 프로퍼티가 전부 deprecated 되었으므로
    /// `load(_:)` / `loadTracks(withMediaType:)` async API 만 쓴다.
    static func load(from url: URL) async throws -> ClipSpec {
        let asset = AVURLAsset(url: url)

        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        var video: VideoTrackSpec?
        if let track = videoTracks.first {
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let frameRate = try await track.load(.nominalFrameRate)
            let minFrameDuration = try await track.load(.minFrameDuration)
            let timeRange = try await track.load(.timeRange)
            let formats = try await track.load(.formatDescriptions)

            video = VideoTrackSpec(
                naturalSize: naturalSize,
                preferredTransform: transform,
                codec: formats.first.map { CMFormatDescriptionGetMediaSubType($0) },
                nominalFrameRate: frameRate,
                minFrameDuration: minFrameDuration,
                duration: timeRange.duration
            )
        }

        var audio: AudioTrackSpec?
        if let track = audioTracks.first {
            let timeRange = try await track.load(.timeRange)
            let formats = try await track.load(.formatDescriptions)
            let asbd = formats.first.flatMap {
                CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
            }

            audio = AudioTrackSpec(
                formatID: asbd.map { FourCharCode($0.mFormatID) },
                sampleRate: asbd?.mSampleRate ?? 0,
                channelCount: asbd?.mChannelsPerFrame ?? 0,
                duration: timeRange.duration
            )
        }

        return ClipSpec(url: url, duration: duration, video: video, audio: audio)
    }

    /// 여러 파일을 순서대로 읽는다.
    static func load(from urls: [URL]) async throws -> [ClipSpec] {
        var specs: [ClipSpec] = []
        specs.reserveCapacity(urls.count)
        for url in urls {
            specs.append(try await load(from: url))
        }
        return specs
    }
}

// MARK: - 비교

/// 한 필드에서 발견된 차이. 양쪽 값을 문자열로 들고 있다.
struct SpecDifference {

    /// 이 차이가 문제인지 아닌지.
    enum Kind {
        /// passthrough 병합 가능 여부를 가르는 항목. 다르면 문제다.
        case compatibility
        /// 클립마다 다른 것이 정상인 항목(길이). 판정에 넣지 않는다.
        ///
        /// 따로 찍은 클립은 길이가 항상 조금씩 다르다. 10초 자동 정지를 걸어도
        /// 프레임 경계에서 끝나는 지점이 클립마다 다르고, 짧은 클립을 남기면
        /// 대놓고 다르다. 이걸 판정에 넣으면 정상 클립이 매번 "병합 불가"로 뜬다.
        case informational
    }

    let kind: Kind
    let field: String
    let base: String
    let other: String
}

extension Array where Element == SpecDifference {
    /// passthrough 병합을 막는 차이만.
    var compatibilityIssues: [SpecDifference] { filter { $0.kind == .compatibility } }
    /// 정상 범위의 차이(길이)만.
    var informational: [SpecDifference] { filter { $0.kind == .informational } }
}

extension ClipSpec {

    /// 두 스펙을 비교해 다른 필드만 돌려준다. 전부 같으면 빈 배열.
    ///
    /// 지속시간은 CMTime 을 문자열이 아니라 실제 값으로 비교한다.
    /// 1/30 과 2/60 은 timescale 이 달라도 같은 시각이다.
    static func differences(base: ClipSpec, other: ClipSpec) -> [SpecDifference] {
        var result: [SpecDifference] = []

        func compare<T>(_ kind: SpecDifference.Kind,
                        _ field: String,
                        _ lhs: T,
                        _ rhs: T,
                        equal: (T, T) -> Bool,
                        describe: (T) -> String) {
            guard !equal(lhs, rhs) else { return }
            result.append(SpecDifference(kind: kind,
                                         field: field,
                                         base: describe(lhs),
                                         other: describe(rhs)))
        }

        /// CMTime 비교. 실제 값으로 비교하므로 1/30 과 2/60 은 같다고 본다.
        ///
        /// 한쪽이라도 수치가 아니면(invalid·indefinite) 무조건 차이로 올린다.
        /// invalid 끼리 "동일"로 통과시키면 가변 프레임레이트 파일이 조용히
        /// 섞여 들어온다. 값을 모르는 것과 값이 같은 것은 다르다.
        func compareTime(_ kind: SpecDifference.Kind,
                         _ field: String,
                         _ lhs: CMTime,
                         _ rhs: CMTime) {
            guard lhs.isNumeric, rhs.isNumeric else {
                result.append(SpecDifference(kind: kind,
                                             field: field + " (값 불명)",
                                             base: Self.describe(time: lhs),
                                             other: Self.describe(time: rhs)))
                return
            }
            compare(kind, field, lhs, rhs,
                    equal: { CMTimeCompare($0, $1) == 0 },
                    describe: Self.describe(time:))
        }

        compareTime(.informational, "duration", base.duration, other.duration)

        // 비디오
        switch (base.video, other.video) {
        case (nil, nil):
            break
        case let (lhs?, rhs?):
            compare(.compatibility, "video.naturalSize", lhs.naturalSize, rhs.naturalSize,
                    equal: { $0.width == $1.width && $0.height == $1.height },
                    describe: { "\($0.width) x \($0.height)" })

            compare(.compatibility, "video.preferredTransform",
                    lhs.preferredTransform, rhs.preferredTransform,
                    equal: Self.transformsEqual,
                    describe: Self.describe(transform:))

            compare(.compatibility, "video.codec", lhs.codec, rhs.codec,
                    equal: { $0 == $1 },
                    describe: { $0.map(Self.describe(fourCC:)) ?? "없음" })

            // 프레임레이트 비교는 nominalFrameRate(Float) 가 아니라
            // minFrameDuration(CMTime) 으로 한다. 정밀도 노이즈가 없다.
            compareTime(.compatibility, "video.minFrameDuration",
                        lhs.minFrameDuration, rhs.minFrameDuration)

            compareTime(.informational, "video.duration", lhs.duration, rhs.duration)
        case (nil, _?):
            result.append(SpecDifference(kind: .compatibility, field: "video 트랙",
                                         base: "없음", other: "있음"))
        case (_?, nil):
            result.append(SpecDifference(kind: .compatibility, field: "video 트랙",
                                         base: "있음", other: "없음"))
        }

        // 오디오
        switch (base.audio, other.audio) {
        case (nil, nil):
            break
        case let (lhs?, rhs?):
            compare(.compatibility, "audio.formatID", lhs.formatID, rhs.formatID,
                    equal: { $0 == $1 },
                    describe: { $0.map(Self.describe(fourCC:)) ?? "없음" })

            compare(.compatibility, "audio.sampleRate", lhs.sampleRate, rhs.sampleRate,
                    equal: { $0 == $1 },
                    describe: { "\($0)" })

            compare(.compatibility, "audio.channelCount", lhs.channelCount, rhs.channelCount,
                    equal: { $0 == $1 },
                    describe: { "\($0)" })

            compareTime(.informational, "audio.duration", lhs.duration, rhs.duration)
        case (nil, _?):
            result.append(SpecDifference(kind: .compatibility, field: "audio 트랙",
                                         base: "없음", other: "있음"))
        case (_?, nil):
            result.append(SpecDifference(kind: .compatibility, field: "audio 트랙",
                                         base: "있음", other: "없음"))
        }

        return result
    }

    private static func transformsEqual(_ lhs: CGAffineTransform, _ rhs: CGAffineTransform) -> Bool {
        lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c
            && lhs.d == rhs.d && lhs.tx == rhs.tx && lhs.ty == rhs.ty
    }
}

// MARK: - 출력용 문자열

extension ClipSpec {

    /// FourCC 를 'avc1' 처럼 보여준다. 인쇄 불가능한 바이트가 섞이면 16진수로.
    static func describe(fourCC code: FourCharCode) -> String {
        let bytes = [
            UInt8(truncatingIfNeeded: code >> 24),
            UInt8(truncatingIfNeeded: code >> 16),
            UInt8(truncatingIfNeeded: code >> 8),
            UInt8(truncatingIfNeeded: code)
        ]
        let printable = bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7F }
        guard printable else { return String(format: "0x%08X", code) }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }

    /// CMTime 을 value/timescale 과 초 단위 양쪽으로 보여준다.
    static func describe(time: CMTime) -> String {
        if !time.isValid {
            return "invalid — 값 없음 (가변 프레임레이트 등)"
        }
        if time.flags.contains(.indefinite) {
            return "indefinite — 길이 미정"
        }
        guard time.isNumeric else {
            return "비수치 (flags: \(time.flags.rawValue))"
        }
        return "\(time.value)/\(time.timescale) (\(CMTimeGetSeconds(time))s)"
    }

    static func describe(transform t: CGAffineTransform) -> String {
        "a:\(t.a) b:\(t.b) c:\(t.c) d:\(t.d) tx:\(t.tx) ty:\(t.ty)"
    }
}

// MARK: - 리포트

extension ClipSpec {

    /// 파일 하나의 전체 스펙을 콘솔에 찍는다. 값을 요약하거나 반올림하지 않는다.
    func report() {
        print("── ClipSpec: \(url.lastPathComponent)")
        print("   path                 \(url.path)")
        print("   duration(asset)      \(Self.describe(time: duration))")

        if let video {
            print("   video.naturalSize    \(video.naturalSize.width) x \(video.naturalSize.height)")
            print("   video.transform      \(Self.describe(transform: video.preferredTransform))")
            print("   video.codec          \(video.codec.map(Self.describe(fourCC:)) ?? "없음")")
            print("   video.minFrameDur    \(Self.describe(time: video.minFrameDuration))")
            print("   video.frameRate      \(video.nominalFrameRate)  ※ 참고용, 비교엔 minFrameDur 사용")
            print("   video.duration       \(Self.describe(time: video.duration))")
        } else {
            print("   video                트랙 없음")
        }

        if let audio {
            print("   audio.formatID       \(audio.formatID.map(Self.describe(fourCC:)) ?? "없음")")
            print("   audio.sampleRate     \(audio.sampleRate)")
            print("   audio.channels       \(audio.channelCount)")
            print("   audio.duration       \(Self.describe(time: audio.duration))")
        } else {
            print("   audio                트랙 없음")
        }

        reportTrackDurationSkew()
    }

    /// 같은 클립 안에서 비디오/오디오 길이가 어긋났으면 그 사실을 찍는다.
    /// 클립 간 비교와는 별개 정보다 — 모든 클립이 똑같이 어긋나 있으면
    /// 클립 간 diff 에는 잡히지 않지만, 병합하면 어긋남이 누적된다.
    func reportTrackDurationSkew() {
        guard let skew = trackDurationSkew else { return }
        let longer = CMTimeCompare(skew, .zero) > 0 ? "비디오" : "오디오"
        print("   ⚠ 트랙 길이 어긋남   video - audio = \(Self.describe(time: skew)) "
              + "(\(longer)가 김)")
    }

    /// 두 파일을 비교해 결과를 찍는다. 같은 값은 나열하지 않는다.
    ///
    /// 호환성 차이(✕)와 정상 범위의 길이 차이(·)를 시각적으로 갈라서 찍는다.
    /// 클립이 10~20 개로 늘어도 "이건 문제, 저건 정상"이 한눈에 보여야 한다.
    /// - Returns: passthrough 병합에 문제가 없으면 true. 길이 차이는 판정에 넣지 않는다.
    @discardableResult
    static func report(base: ClipSpec, other: ClipSpec) -> Bool {
        let diffs = differences(base: base, other: other)
        let blocking = diffs.compatibilityIssues
        let info = diffs.informational
        let name = other.url.lastPathComponent

        if blocking.isEmpty {
            print("── ✓ \(name) — 호환")
        } else {
            print("── ✕ \(name) — 호환성 차이 \(blocking.count)개 "
                  + "(기준: \(base.url.lastPathComponent))")
            for diff in blocking {
                print("     ✕ \(diff.field)")
                print("         기준  \(diff.base)")
                print("         대상  \(diff.other)")
            }
        }

        if !info.isEmpty {
            print("     · 길이 차이 \(info.count)개 — 클립마다 다른 것이 정상, 병합에 영향 없음")
            for diff in info {
                print("         \(diff.field)")
                print("           기준  \(diff.base)")
                print("           대상  \(diff.other)")
            }
        }

        return blocking.isEmpty
    }

    /// 여러 파일을 첫 파일 기준으로 전부 비교해 찍는다.
    /// 1-8 "여러 클립이 정말 동일한 값인지"를 확인할 때 쓴다.
    /// - Returns: 전부 동일하면 true.
    @discardableResult
    static func reportComparison(of urls: [URL]) async -> Bool {
        guard let first = urls.first else {
            print("── ClipSpec 비교: 파일 없음")
            return true
        }

        let specs: [ClipSpec]
        do {
            specs = try await load(from: urls)
        } catch {
            print("── ClipSpec 비교 실패: \(error)")
            return false
        }

        print("══ ClipSpec 비교: \(urls.count)개 파일, 기준 \(first.lastPathComponent)")
        specs[0].report()

        var incompatibleCount = 0
        for spec in specs.dropFirst() where !report(base: specs[0], other: spec) {
            incompatibleCount += 1
        }

        // 클립 간 비교와 별개로, 각 클립 내부의 트랙 길이 어긋남을 따로 모아 찍는다.
        // 모든 클립이 똑같이 어긋나 있으면 위 diff 에는 한 줄도 안 잡히지만,
        // 이어붙이면 클립 수만큼 누적되어 뒤쪽 오디오가 밀린다.
        let skewed = specs.filter { $0.trackDurationSkew != nil }
        if !skewed.isEmpty {
            print("── 트랙 길이 어긋남 (클립 내부, \(skewed.count)/\(specs.count)개)")
            for spec in skewed {
                guard let skew = spec.trackDurationSkew else { continue }
                print("     \(spec.url.lastPathComponent)  video - audio = "
                      + Self.describe(time: skew))
            }
        }

        if incompatibleCount == 0 {
            print("══ 결과: ✓ \(urls.count)개 전부 호환 — passthrough 병합 가능")
        } else {
            print("══ 결과: ✕ 호환되지 않는 클립 \(incompatibleCount)/\(specs.count - 1)개 "
                  + "— passthrough 병합 불가 가능성")
        }
        return incompatibleCount == 0
    }
}
