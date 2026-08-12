import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

// 컴포지션을 파일로 내보낸다 (1-17).
//
// ClipSpec / ClipMerger 와 같은 제약을 지킨다 — UIKit·SwiftUI 에 의존하지 않고
// Foundation + AVFoundation 계열만 쓴다. Mac 에서 swiftc 로 단독 실행할 수 있어야
// 실기기 왕복 없이 프리셋·비디오컴포지션을 바꿔가며 반복 측정할 수 있다.
//
// 병합(ClipMerger)까지는 인코딩이 일어나지 않는다. 실제로 비트를 옮기거나
// 다시 만드는 것은 이 단계다. 두 경로가 있다.
//
//   passthrough  — 원본 샘플을 그대로 컨테이너에 옮긴다. 재인코딩 없음
//   재인코딩      — 프리셋이 정한 규격으로 다시 만든다. videoComposition 을
//                  붙이면(방향 교정·자막) 무조건 이쪽이다
//
// 어느 쪽을 언제 쓸지는 여기서 정하지 않는다. 프리셋을 인자로 받는다.

// MARK: - 사용한 API
//
// AVAssetExportSession 은 iOS 18 / macOS 15 에서 인터페이스가 갈렸다.
// 이 파일은 전부 **새 쪽**을 쓴다.
//
//   export(to:as:) async throws
//       - exportAsynchronously(completionHandler:) 의 대체.
//         구 API 는 iOS 18 / macOS 15 에서 deprecated.
//       - outputURL / outputFileType 프로퍼티와 status / error 폴링도 함께
//         deprecated 되었으므로 쓰지 않는다. 실패는 throw 로 온다.
//       - Swift 오버레이가 백디플로이되어 배포 타깃 iOS 17 에서도 쓸 수 있다
//         (iOS 15 타깃까지 타입체크 확인).
//
//   compatibility(ofExportPreset:with:outputFileType:) async -> Bool
//       - determineCompatibilityOfExportPreset:withAsset:outputFileType: 의
//         Swift 이름(NS_SWIFT_ASYNC_NAME). exportPresets(compatibleWith:) 는
//         iOS 16 에서 deprecated 되었고 이것이 대체 API 다.
//
//   states(updateInterval:) 는 iOS 18 이상이라 쓰지 않았다. 배포 타깃이 17 이고,
//   진행률이 필요한 단계가 아니다. progress 프로퍼티도 deprecated 이므로
//   진행률이 필요해지면(3-12 등) 그때 iOS 18 분기를 넣는다.
//
// AVMutableVideoComposition / AVMutableVideoCompositionInstruction /
// AVMutableVideoCompositionLayerInstruction 은 iOS 26 · macOS 26 에서
// deprecated 되었다(대체: AVVideoComposition.Configuration 등). 대체 API 가
// iOS 26 이상이라 배포 타깃 iOS 17 에서는 쓸 수 없다. 여기서는 구 API 를
// 계속 쓴다 — 제거된 것이 아니라 deprecated 이며 iOS 17 에서 동작한다.
// 배포 타깃을 올릴 때 함께 옮긴다.

// MARK: - 결과 모델

/// 익스포트 한 번의 결과.
struct ExportOutcome {
    let outputURL: URL
    let preset: String
    /// 세션 생성부터 export(to:as:) 반환까지의 wall time.
    let elapsed: TimeInterval
    /// 출력 파일 크기(byte). 읽지 못하면 nil.
    let fileSize: Int64?
}

enum ClipExportError: Error, CustomStringConvertible {
    /// 해당 프리셋으로 세션을 만들 수 없다. 프리셋이 애셋과 맞지 않을 때.
    case sessionUnavailable(preset: String)

    var description: String {
        switch self {
        case .sessionUnavailable(let preset):
            return "익스포트 세션을 만들 수 없습니다 — preset: \(preset)"
        }
    }
}

// MARK: - 익스포트

enum ClipExporter {

    /// 재인코딩 없이 원본 샘플을 그대로 옮기는 프리셋.
    static let passthroughPreset = AVAssetExportPresetPassthrough

    /// 이 애셋을 이 프리셋·파일타입 조합으로 내보낼 수 있는지.
    ///
    /// passthrough 성립 여부는 이 API 로만 확인할 수 있다.
    /// `exportPresets(compatibleWith:)` 는 헤더에 명시된 대로
    /// **passthrough 를 결과 배열에 넣지 않는다** — 빠져 있다고 해서
    /// 불가능하다는 뜻이 아니다.
    static func isCompatible(preset: String,
                             with asset: AVAsset,
                             outputFileType: AVFileType) async -> Bool {
        await AVAssetExportSession.compatibility(ofExportPreset: preset,
                                                 with: asset,
                                                 outputFileType: outputFileType)
    }

    /// 컴포지션을 파일로 내보낸다.
    ///
    /// - Parameters:
    ///   - videoComposition: 붙이면 재인코딩이 강제된다. 방향 교정·자막 경로.
    ///   - optimizeForNetworkUse: 무비 헤더를 파일 앞으로 보낸다(faststart).
    ///     기본은 false — 사진 앱 저장은 스트리밍이 아니다.
    /// - Note: 출력 경로에 파일이 남아 있으면 익스포트가 실패한다.
    ///   지우는 것은 호출자 책임이다. 조용히 덮어쓰지 않는다.
    static func export(_ asset: AVAsset,
                       preset: String,
                       to outputURL: URL,
                       as outputFileType: AVFileType = .mov,
                       videoComposition: AVVideoComposition? = nil,
                       optimizeForNetworkUse: Bool = false) async throws -> ExportOutcome {

        let started = CFAbsoluteTimeGetCurrent()

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ClipExportError.sessionUnavailable(preset: preset)
        }
        session.shouldOptimizeForNetworkUse = optimizeForNetworkUse
        session.videoComposition = videoComposition

        try await session.export(to: outputURL, as: outputFileType)

        let elapsed = CFAbsoluteTimeGetCurrent() - started

        let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size])
            .flatMap { $0 as? NSNumber }?.int64Value

        return ExportOutcome(outputURL: outputURL,
                             preset: preset,
                             elapsed: elapsed,
                             fileSize: size)
    }
}

// MARK: - 방향 교정

/// 클립마다 방향이 다른 컴포지션을 하나의 캔버스에 정방향으로 세우는
/// `AVVideoComposition` 을 만든다.
///
/// 컴포지션 비디오 트랙은 `preferredTransform` 을 하나만 갖는다(1-12 실측).
/// 그래서 트랙 단위 변환으로는 방향이 섞인 세션을 바로잡을 수 없다.
/// 클립 구간마다 별도의 instruction 을 두고, 각 instruction 의
/// layerInstruction 에 **그 클립의 원본 preferredTransform** 을 넣는다.
///
/// 이 방식은 캔버스(renderSize)를 고정한 채 개별 클립만 돌린다. 계열이
/// 같으면(세로 90 ↔ 거꾸로 270, 가로L 0 ↔ 가로R 180) 회전 후 규격이
/// renderSize 와 정확히 일치하므로 여백이 생기지 않는다. 계열이 다르면
/// (세로 ↔ 가로) 필러박스가 불가피하다 — 그 경우는 여기서 다루지 않는다.
enum OrientationFix {

    /// 클립 구간 하나. `ClipMerger` 의 `MergedClip` 에서 필요한 값만 뽑아 쓴다.
    struct Segment {
        let timeRange: CMTimeRange
        /// 이 구간 원본 클립의 preferredTransform.
        let transform: CGAffineTransform
    }

    /// 컴포지션을 방향 교정 익스포트용으로 맞추고, 그에 맞는
    /// videoComposition 을 돌려준다.
    ///
    /// **컴포지션을 변형한다.** 이름을 `videoComposition(for:)` 같은 생성형으로
    /// 두지 않은 이유다 — 비디오 트랙의 `preferredTransform` 을 identity 로
    /// 되돌린다. 트랙 변환이 남아 있으면 layerInstruction 변환 위에 한 번 더
    /// 얹혀 두 번 회전하므로, 이 초기화는 선택이 아니라 정확성의 일부다.
    /// 호출자는 이 함수를 부른 **뒤에** 컴포지션 스냅샷을 떠야 한다.
    ///
    /// - Returns: 비디오 트랙이 없거나 segments 가 비면 nil. 구간의 정렬·중첩·
    ///   커버리지까지는 보지 않는다 — 그건 AVFoundation 의
    ///   `isValid(forTracks:assetDuration:timeRange:validationDelegate:)` 몫이다.
    @discardableResult
    static func prepareForOrientationFix(_ composition: AVMutableComposition,
                                         segments: [Segment],
                                         renderSize: CGSize,
                                         frameDuration: CMTime = CMTime(value: 1, timescale: 30))
    -> AVMutableVideoComposition? {

        guard !segments.isEmpty,
              let videoTrack = composition.tracks(withMediaType: .video).first else { return nil }

        videoTrack.preferredTransform = .identity

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration

        videoComposition.instructions = segments.map { segment in
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layer.setTransform(segment.transform, at: segment.timeRange.start)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = segment.timeRange
            instruction.layerInstructions = [layer]
            return instruction
        }

        return videoComposition
    }
}
