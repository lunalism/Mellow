import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

// 클립 여러 개를 AVMutableComposition 으로 이어붙인다 (1-12).
//
// ClipSpec 과 같은 제약을 지킨다 — UIKit·SwiftUI 에 의존하지 않고
// Foundation + AVFoundation 계열만 쓴다. Mac 에서 swiftc 로 단독 실행할 수 있어야
// 실기기 왕복 없이 파라미터를 바꿔가며 반복 실험할 수 있다.
//
// 이 단계에서는 인코딩이 일어나지 않는다. 컴포지션은 "어느 원본의 어느 구간을
// 어디에 놓을지"를 적어둔 편집 목록일 뿐이다. 실제 재인코딩 여부는 익스포트
// 단계(1-17)에서 결정된다.

// MARK: - 결과 모델

/// 클립 하나를 컴포지션에 넣은 결과.
struct MergedClip {
    let index: Int
    let url: URL
    /// 컴포지션 상에서 이 클립이 시작하는 시각.
    let start: CMTime
    /// 커서를 얼마나 전진시켰는지. 정책에 따라 달라진다.
    let advance: CMTime

    let videoDuration: CMTime?
    let audioDuration: CMTime?
    let sourceNaturalSize: CGSize?
    let sourceTransform: CGAffineTransform?

    /// 넣지 못했거나 온전하지 않은 부분. 비어 있으면 정상.
    let issues: [String]

    var name: String { url.lastPathComponent }
}

/// 병합 전체 결과.
struct MergeReport {
    let composition: AVMutableComposition
    let clips: [MergedClip]
    /// 병합을 중단시킨 실패. 어느 클립의 어느 단계인지 담는다.
    let fatal: String?

    let compositionDuration: CMTime
    let videoTrackDuration: CMTime?
    let audioTrackDuration: CMTime?
    /// 컴포지션 비디오 트랙이 실제로 갖게 된 값.
    let videoTrackTransform: CGAffineTransform?
    let videoTrackNaturalSize: CGSize?
    let compositionNaturalSize: CGSize
    /// 트랙에 들어간 세그먼트 수. 클립 수와 일치해야 정상이다.
    let videoSegmentCount: Int
    let audioSegmentCount: Int

    var succeeded: Bool { fatal == nil }

    /// 비디오 트랙과 오디오 트랙의 총 길이 차이 (비디오 − 오디오).
    var trackDurationSkew: CMTime? {
        guard let videoTrackDuration, let audioTrackDuration else { return nil }
        return CMTimeSubtract(videoTrackDuration, audioTrackDuration)
    }
}

// MARK: - 병합

enum ClipMerger {

    // 커서 전진은 **비디오 트랙 길이** 기준으로 고정한다.
    //
    // 한 클립 안에서도 비디오와 오디오 길이가 다르다. 실측(iPhone 12)에서
    // 세로 10개 중 5개가 비디오 쪽이 1/600(1.67ms) 길었다. 무엇을 기준으로
    // 커서를 전진시키느냐에 따라 결과가 질적으로 갈린다.
    //
    //   비디오 기준 — 오디오가 짧은 경계에 1.67ms 빈 구간이 삽입된다.
    //                 각 클립의 오디오가 자기 비디오 시작점에 정확히 정렬되고
    //                 총 길이 차이 0. 어긋남이 다음 클립으로 넘어가지 않는다.
    //                 클립 20개로 늘려도 각 경계 값은 1.67ms 그대로다.
    //
    //   오디오 기준 — 커서가 비디오 트랙의 현재 끝보다 앞에 놓여
    //                 insertTimeRange 가 삽입-밀어내기로 동작한다. 앞 클립의
    //                 마지막 1.67ms 가 잘려 뒤로 밀린다. 실측에서 클립 10개가
    //                 비디오 세그먼트 15개로 파편화됐고 총 차이 8.33ms 가 남았다.
    //                 트랙 구성 자체가 온전하지 않다.
    //
    // 그래서 선택지를 두지 않는다.

    /// 클립들을 순서대로 이어붙인다.
    static func merge(_ urls: [URL]) async -> MergeReport {

        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return report(composition: composition, clips: [],
                          fatal: "컴포지션에 트랙을 만들 수 없습니다.",
                          videoTrack: nil, audioTrack: nil)
        }

        var clips: [MergedClip] = []
        var cursor = CMTime.zero
        var firstTransform: CGAffineTransform?

        for (index, url) in urls.enumerated() {
            let asset = AVURLAsset(url: url)
            var issues: [String] = []

            // 원본 트랙 읽기
            let sourceVideo: AVAssetTrack?
            let sourceAudio: AVAssetTrack?
            do {
                sourceVideo = try await asset.loadTracks(withMediaType: .video).first
                sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
            } catch {
                return report(composition: composition, clips: clips,
                              fatal: "[\(index)] \(url.lastPathComponent) — 트랙 읽기 실패: \(error.localizedDescription)",
                              videoTrack: videoTrack, audioTrack: audioTrack)
            }

            if sourceVideo == nil { issues.append("비디오 트랙 없음") }
            if sourceAudio == nil { issues.append("오디오 트랙 없음") }

            // 원본 속성
            var videoRange: CMTimeRange?
            var audioRange: CMTimeRange?
            var naturalSize: CGSize?
            var transform: CGAffineTransform?

            do {
                if let sourceVideo {
                    videoRange = try await sourceVideo.load(.timeRange)
                    naturalSize = try await sourceVideo.load(.naturalSize)
                    transform = try await sourceVideo.load(.preferredTransform)
                }
                if let sourceAudio {
                    audioRange = try await sourceAudio.load(.timeRange)
                }
            } catch {
                return report(composition: composition, clips: clips,
                              fatal: "[\(index)] \(url.lastPathComponent) — 속성 읽기 실패: \(error.localizedDescription)",
                              videoTrack: videoTrack, audioTrack: audioTrack)
            }

            if firstTransform == nil { firstTransform = transform }

            // 삽입
            let start = cursor
            do {
                if let sourceVideo, let videoRange {
                    try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: cursor)
                }
            } catch {
                return report(composition: composition, clips: clips,
                              fatal: "[\(index)] \(url.lastPathComponent) — 비디오 삽입 실패: \(error.localizedDescription)",
                              videoTrack: videoTrack, audioTrack: audioTrack)
            }

            do {
                if let sourceAudio, let audioRange {
                    try audioTrack.insertTimeRange(audioRange, of: sourceAudio, at: cursor)
                }
            } catch {
                return report(composition: composition, clips: clips,
                              fatal: "[\(index)] \(url.lastPathComponent) — 오디오 삽입 실패: \(error.localizedDescription)",
                              videoTrack: videoTrack, audioTrack: audioTrack)
            }

            // 비디오 트랙 길이만큼 전진. 비디오가 없는 클립은 오디오 길이로 대신한다.
            let advance = videoRange?.duration ?? audioRange?.duration ?? .zero
            cursor = CMTimeAdd(cursor, advance)

            clips.append(MergedClip(index: index,
                                    url: url,
                                    start: start,
                                    advance: advance,
                                    videoDuration: videoRange?.duration,
                                    audioDuration: audioRange?.duration,
                                    sourceNaturalSize: naturalSize,
                                    sourceTransform: transform,
                                    issues: issues))
        }

        // 트랙 transform 은 첫 클립 값을 쓴다.
        //
        // 지정하지 않으면 identity 로 남는다 — 첫 클립 값을 물려받지 않는다(실측).
        // 세로 세션이라면 identity 는 모든 클립을 90도 돌아간 상태로 만든다.
        //
        // 방향이 섞인 세션에서 무엇을 기준으로 정할지(첫 클립 / 다수결 / 그 외)는
        // 아직 정하지 않았다. 재인코딩 비용을 모르는 상태에서 정하면 되돌리게 되므로
        // 1-17 익스포트 측정 후에 판단한다.
        if let firstTransform {
            videoTrack.preferredTransform = firstTransform
        }

        return report(composition: composition, clips: clips, fatal: nil,
                      videoTrack: videoTrack, audioTrack: audioTrack)
    }

    private static func report(composition: AVMutableComposition,
                               clips: [MergedClip],
                               fatal: String?,
                               videoTrack: AVMutableCompositionTrack?,
                               audioTrack: AVMutableCompositionTrack?) -> MergeReport {
        MergeReport(composition: composition,
                    clips: clips,
                    fatal: fatal,
                    compositionDuration: composition.duration,
                    videoTrackDuration: videoTrack?.timeRange.duration,
                    audioTrackDuration: audioTrack?.timeRange.duration,
                    videoTrackTransform: videoTrack?.preferredTransform,
                    videoTrackNaturalSize: videoTrack?.naturalSize,
                    compositionNaturalSize: composition.naturalSize,
                    videoSegmentCount: videoTrack?.segments.count ?? 0,
                    audioSegmentCount: audioTrack?.segments.count ?? 0)
    }
}

// MARK: - 출력

extension MergeReport {

    /// transform 을 적용했을 때의 표시 규격.
    static func renderedSize(_ naturalSize: CGSize, _ transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    func report(title: String) {
        print("══ 병합: \(title)")

        if let fatal {
            print("   ✕ 실패 — \(fatal)")
        }

        print("   클립 \(clips.count)개  비디오 세그먼트 \(videoSegmentCount)  오디오 세그먼트 \(audioSegmentCount)")
        print("   composition.duration   \(ClipSpec.describe(time: compositionDuration))")
        if let videoTrackDuration {
            print("   video 트랙 총 길이     \(ClipSpec.describe(time: videoTrackDuration))")
        }
        if let audioTrackDuration {
            print("   audio 트랙 총 길이     \(ClipSpec.describe(time: audioTrackDuration))")
        }
        if let skew = trackDurationSkew {
            print("   트랙 길이 차이         \(ClipSpec.describe(time: skew))  (video − audio)")
        }

        if let videoTrackNaturalSize {
            print("   video 트랙 naturalSize \(videoTrackNaturalSize.width) x \(videoTrackNaturalSize.height)")
        }
        if let videoTrackTransform {
            print("   video 트랙 transform   \(ClipSpec.describe(transform: videoTrackTransform))")
            if let size = videoTrackNaturalSize {
                let rendered = Self.renderedSize(size, videoTrackTransform)
                print("   → 표시 규격            \(rendered.width) x \(rendered.height)")
            }
        }
        print("   composition.naturalSize \(compositionNaturalSize.width) x \(compositionNaturalSize.height)")

        for clip in clips {
            var line = "   [\(clip.index)] \(clip.name)"
            line += "  start=\(ClipSpec.describe(time: clip.start))"
            line += "  advance=\(ClipSpec.describe(time: clip.advance))"
            print(line)
            if let size = clip.sourceNaturalSize, let transform = clip.sourceTransform {
                let rendered = Self.renderedSize(size, transform)
                print("        원본 \(size.width)x\(size.height)"
                      + "  transform \(ClipSpec.describe(transform: transform))"
                      + "  → 표시 \(rendered.width)x\(rendered.height)")
            }
            if !clip.issues.isEmpty {
                print("        ⚠ \(clip.issues.joined(separator: ", "))")
            }
        }
    }
}
