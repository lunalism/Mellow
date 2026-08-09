@preconcurrency import AVFoundation
import Foundation

/// 재인코딩 없는 익스포트. (Tasks 1-17)
///
/// "passthrough 프리셋을 썼다"와 "실제로 재인코딩이 없었다"는 별개의 주장이라
/// 결과를 세 가지로 검증한다 — 스펙 보존(ClipSpec 대조), 크기 비율, 처리 속도.
/// 이 타입은 소요 시간과 결과 파일까지만 책임지고, 대조는 호출부가 한다.
enum ClipExporter {

    struct Result {
        let url: URL
        let milliseconds: Double
        let fileSize: Int64?
    }

    enum Failure: LocalizedError {
        case sessionCreationFailed
        case passthroughIncompatible
        case exportFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .sessionCreationFailed: return "익스포트 세션을 만들지 못했다"
            case .passthroughIncompatible: return "passthrough 로 내보낼 수 없는 구성이다"
            case .exportFailed(let reason): return "익스포트 실패: \(reason)"
            case .cancelled: return "익스포트가 취소됐다"
            }
        }
    }

    /// `exportAsynchronously` / `status` / `error` 는 iOS 18 에서 deprecated 됐고
    /// 대체 API(`export(to:as:)`, `states(updateInterval:)`)는 iOS 18+ 전용이다.
    /// 배포 타깃이 17.0 인 동안은 구 API 를 써야 한다.
    ///
    /// 이 함수 자체를 deprecated 로 표시해 두 가지를 동시에 얻는다 —
    /// 내부의 deprecation 경고가 억제되고, **iOS 18 로 올릴 때 갈아엎을 지점**이
    /// 주석이 아니라 타입 시스템에 남는다.
    @available(iOS, deprecated: 18.0,
               message: "iOS 18+ 로 올리면 export(to:as:) async / states(updateInterval:) 로 교체한다")
    static func exportPassthrough(_ asset: AVAsset, to url: URL) async throws -> Result {
        // 먼저 물어본다. passthrough 가 애초에 불가능한 구성이면 시도조차 하지 않는다.
        // 그래야 "왜 실패했는지"가 명확해진다. 이 API 는 deprecated 가 아니다.
        let compatible = await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetPassthrough,
            with: asset,
            outputFileType: .mov
        )
        guard compatible else { throw Failure.passthroughIncompatible }

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else { throw Failure.sessionCreationFailed }

        session.outputURL = url
        session.outputFileType = .mov

        let startedAt = Date()
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        let elapsed = Date().timeIntervalSince(startedAt) * 1000

        switch session.status {
        case .completed:
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))
                .flatMap(\.fileSize)
                .map(Int64.init)
            return Result(url: url, milliseconds: elapsed, fileSize: size)
        case .cancelled:
            throw Failure.cancelled
        default:
            throw Failure.exportFailed(session.error?.localizedDescription ?? "알 수 없음")
        }
    }

    /// 익스포트 결과는 원본 클립과 분리한다.
    /// 같은 디렉터리에 두면 ClipLibrary.scan() 이 결과물을 원본 클립으로 집어삼킨다.
    static func exportDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 촬영 파일과 같은 방식으로 디스크의 최대 번호에서 이어붙인다.
    static func nextExportURL(degrees: Int, clipCount: Int) -> URL {
        let directory = exportDirectory()
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let highest = existing.compactMap { name -> Int? in
            guard name.hasPrefix("export_"), name.hasSuffix(".mov") else { return nil }
            return Int(name.dropLast(".mov".count).suffix(3))
        }.max() ?? 0

        var index = highest + 1
        while true {
            let name = String(format: "export_%03ddeg_%02dclips_%03d.mov", degrees, clipCount, index)
            let url = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }
}
