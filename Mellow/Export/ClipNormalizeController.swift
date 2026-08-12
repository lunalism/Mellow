import AVFoundation
import Foundation

// 클립 **하나**를 방향 교정 재인코딩하고 시간을 재는 동선 (B 라운드).
//
// 1-21 과 같은 구성(prepareForOrientationFix + ClipExporter)을 쓰되,
// **클립 1개 = 익스포트 1회**로 돌린다. 이 차이가 이 측정의 핵심이다.
//
// 정규화 로직이 아니다. 큐·상태 관리·재시도·SwiftData 연동은 전부 이 라운드
// 밖이다. 여기서 나오는 값으로 Phase 2 의 정규화 태스크 규모를 정한다.
//
// **원본 클립을 건드리지 않는다.** 회차마다 원본을 라운드 디렉터리로 복사해
// 그 사본을 교체 대상으로 삼는다. 원본을 직접 교체하면 2회차부터는 이미
// 정규화된(= transform 이 identity 인) 클립을 재는 셈이라 반복이 성립하지
// 않는다. 복사 비용은 측정 구간 밖이다 — 실제 흐름에는 복사가 없다.
//
// 3-13 에서 걷어낸다.
@MainActor
final class ClipNormalizeController: ObservableObject {

    enum State: Equatable {
        case idle
        case running(String)
        case done(String)
        case failed(String)

        var isBusy: Bool {
            if case .running = self { return true }
            return false
        }
    }

    @Published private(set) var state: State = .idle
    /// 직전 측정의 회차들.
    @Published private(set) var rounds: [NormalizeMeasurement] = []
    /// B-5 교체 실패 확인 결과.
    @Published private(set) var replaceReport: [String] = []

    /// **앱 실행 내내 쌓이는** 측정 기록. 지우지 않는다.
    ///
    /// B-1 → B-2 → B-3 을 연달아 도는 화면이라 직전 값을 덮어쓰면 콘솔을 놓쳤을 때
    /// 앞 조건의 값이 통째로 사라진다. 조건이 여러 개인 측정에서 이건 치명적이다.
    /// 세로·가로를 따로 재는 것도 마찬가지라 방향까지 머리줄에 남긴다.
    @Published private(set) var history: [String] = []

    /// 기록을 비운다. 조건을 바꿔 처음부터 다시 잴 때만 쓴다.
    func clearHistory() {
        history = []
    }

    // MARK: - B-1 / B-2. 단일 클립 3회 반복

    /// 마지막 클립을 3회 정규화한다. 카메라 상태는 호출자가 만들어 둔다 —
    /// 세션을 멈춘 채로 돌리면 B-1, 프리뷰가 살아 있는 채로 돌리면 B-2 다.
    func measureRepeat(_ urls: [URL], cameraRunning: Bool, repeats: Int = 3) async {
        guard !state.isBusy else { return }
        guard let source = urls.last else {
            state = .failed("정규화할 클립이 없습니다.")
            return
        }

        rounds = []
        var measured: [NormalizeMeasurement] = []

        for round in 1...repeats {
            state = .running("\(round)/\(repeats)회차 정규화 중")
            do {
                let measurement = try await normalizeOnce(source: source,
                                                          round: round,
                                                          cameraRunning: cameraRunning)
                measurement.log()
                measured.append(measurement)
                rounds = measured
            } catch {
                state = .failed("\(round)회차 실패 — \(error)")
                return
            }
        }

        let summary = NormalizeRunSummary(rounds: measured)
        let title = "단일 클립 ×\(repeats) (카메라 \(cameraRunning ? "running" : "stopped"))"
        summary.log(title: title)
        record(title: title, measured, summary)
        state = .done(String(format: "중앙값 %.0fms  1회차 %.0fms  1-21 대비 %.2f배",
                             summary.medianTotal * 1000, summary.firstTotal * 1000,
                             summary.medianTotal * 1000 / NormalizeMeasurement.baseline1_21))
    }

    // MARK: - B-3. 연속 4회 발열 추이

    /// 마지막 4개 클립을 연속으로 정규화한다. 회차별 소요 시간을 전부 남긴다.
    func measureSequence(_ urls: [URL], cameraRunning: Bool, count: Int = 4) async {
        guard !state.isBusy else { return }
        let sources = Array(urls.suffix(count))
        guard sources.count == count else {
            state = .failed("연속 측정은 클립 \(count)개가 필요합니다 (현재 \(urls.count)개).")
            return
        }

        rounds = []
        var measured: [NormalizeMeasurement] = []

        for (offset, source) in sources.enumerated() {
            state = .running("\(offset + 1)/\(count) 연속 정규화 중")
            do {
                let measurement = try await normalizeOnce(source: source,
                                                          round: offset + 1,
                                                          cameraRunning: cameraRunning)
                measurement.log()
                measured.append(measurement)
                rounds = measured
            } catch {
                state = .failed("\(offset + 1)번째 실패 — \(error)")
                return
            }
        }

        let summary = NormalizeRunSummary(rounds: measured)
        let title = "연속 \(count)개 (카메라 \(cameraRunning ? "running" : "stopped"))"
        summary.log(title: title)
        record(title: title, measured, summary)
        state = .done(String(format: "1회차 %.0fms → %d회차 %.0fms  (%.2f배)  thermal %@",
                             summary.firstTotal * 1000, count, summary.lastTotal * 1000,
                             summary.drift,
                             NormalizeMeasurement.describe(measured.last?.thermalAfter ?? .nominal)))
    }

    // MARK: - B-5. 파일 교체 방식

    /// 교체가 성립하는지, 실패했을 때 원본이 살아남는지 확인한다.
    ///
    /// 정상 경로로 한 번 교체한 뒤 결과를 사진 앱에 넣는다 — 정상 재생 여부는
    /// 눈으로만 판정된다. 그다음 일부러 두 가지 방식으로 실패시킨다.
    func checkReplace(_ urls: [URL]) async {
        guard !state.isBusy else { return }
        guard let source = urls.last else {
            state = .failed("확인할 클립이 없습니다.")
            return
        }

        state = .running("교체 확인 중")
        replaceReport = []

        let directory = Self.makeRoundDirectory()
        defer { Self.discardRoundDirectory(directory) }

        // 1) 정상 교체
        let scratch = directory.appendingPathComponent("scratch.mov")
        do {
            try FileManager.default.copyItem(at: source, to: scratch)
        } catch {
            state = .failed("사본을 만들지 못했습니다 — \(error)")
            return
        }

        let before = try? await ClipSpec.load(from: scratch)
        let normalized = directory.appendingPathComponent("normalized.mov")
        do {
            let prepared = try await prepareNormalization(of: scratch, output: normalized)
            _ = try await ClipExporter.export(prepared.asset,
                                              preset: AVAssetExportPreset1920x1080,
                                              to: normalized,
                                              as: .mov,
                                              videoComposition: prepared.videoComposition)
            _ = try FileManager.default.replaceItemAt(scratch, withItemAt: normalized)
        } catch {
            state = .failed("정상 교체 경로에서 실패 — \(error)")
            return
        }

        let after = try? await ClipSpec.load(from: scratch)
        let playable = after?.video != nil && after?.audio != nil
        report("정상 교체: \(playable ? "✓ 트랙 정상" : "✕ 트랙 결손")"
               + "  전 \(NormalizeMeasurement.precise(before?.duration ?? .zero))"
               + "  후 \(NormalizeMeasurement.precise(after?.duration ?? .zero))")

        // 2) 잘못된 대상 URL — 존재하지 않는 디렉터리 아래를 가리킨다.
        let decoy = directory.appendingPathComponent("nowhere/original.mov")
        let spare = directory.appendingPathComponent("spare.mov")
        try? FileManager.default.copyItem(at: source, to: spare)
        do {
            _ = try FileManager.default.replaceItemAt(decoy, withItemAt: spare)
            report("잘못된 대상 URL: ✕ 실패하지 않았다 — 예상 밖")
        } catch {
            let spareAlive = FileManager.default.fileExists(atPath: spare.path)
            report("잘못된 대상 URL: ✓ throw"
                   + "  새 파일 \(spareAlive ? "남음" : "사라짐")"
                   + "  — \((error as NSError).code)")
        }

        // 3) 새 파일이 없는 경우 — 대상(원본)이 살아남아야 한다.
        //    데이터가 걸린 쪽은 이쪽이다. 교체가 깨졌을 때 원본까지 날아가면
        //    정규화는 촬영분을 잃는 경로가 된다.
        let missing = directory.appendingPathComponent("does-not-exist.mov")
        let sizeBefore = Self.fileSize(of: scratch)
        do {
            _ = try FileManager.default.replaceItemAt(scratch, withItemAt: missing)
            report("새 파일 없음: ✕ 실패하지 않았다 — 예상 밖")
        } catch {
            let survived = FileManager.default.fileExists(atPath: scratch.path)
            let sizeAfter = Self.fileSize(of: scratch)
            report("새 파일 없음: ✓ throw"
                   + "  원본 \(survived ? "살아남음" : "✕ 사라짐")"
                   + (survived && sizeBefore == sizeAfter ? " (크기 동일)" : "")
                   + "  — \((error as NSError).code)")
        }

        // 정상 재생은 눈으로 본다. 사진 앱에 넣어야 확인할 수 있다.
        //    save 가 파일 소유권을 가져가므로 스펙 확인을 모두 끝낸 뒤에 부른다.
        do {
            _ = try await PhotoLibrarySaver.save(temporaryVideoAt: scratch, moveFile: false)
            report("사진 앱 저장: ✓ — 정방향인지 눈으로 확인")
        } catch {
            let message = (error as? PhotoLibrarySaveError)?.description ?? "\(error)"
            report("사진 앱 저장: ✕ \(message)")
        }

        state = .done("교체 확인 완료 — 아래 \(replaceReport.count)줄")
    }

    /// 한 조건의 결과를 기록에 덧붙인다. 방향을 머리줄에 남겨 세로·가로가 섞이지
    /// 않게 한다 — 두 값 다 필요하고, 나중에 어느 쪽이었는지 되짚을 수 없으면
    /// 측정 자체가 무의미해진다.
    private func record(title: String,
                        _ measured: [NormalizeMeasurement],
                        _ summary: NormalizeRunSummary) {
        guard let first = measured.first else { return }
        history.append("── \(title)  \(first.orientationLabel)"
                       + "  \(Int(first.renderSize.width))x\(Int(first.renderSize.height))")
        history.append(contentsOf: measured.map(\.compact))
        history.append(String(format: "   중앙값 %.0fms  1-21 대비 %.2f배",
                              summary.medianTotal * 1000,
                              summary.medianTotal * 1000 / NormalizeMeasurement.baseline1_21))
    }

    private func report(_ line: String) {
        replaceReport.append(line)
        if CaptureTrace.isEnabled {
            print("[trace]   \(line)")
        }
    }

    // MARK: - 한 회차

    private struct Prepared {
        let asset: AVComposition
        let videoComposition: AVVideoComposition
        let renderSize: CGSize
        let sourceTransform: CGAffineTransform
    }

    /// 원본을 라운드 디렉터리로 복사해 그 사본을 정규화하고 교체까지 한다.
    /// 복사는 측정 밖이다 — 실제 흐름에는 복사가 없다.
    private func normalizeOnce(source: URL,
                               round: Int,
                               cameraRunning: Bool) async throws -> NormalizeMeasurement {

        var measurement = NormalizeMeasurement()
        measurement.round = round
        measurement.cameraRunning = cameraRunning
        measurement.clipName = source.lastPathComponent
        measurement.thermalBefore = ProcessInfo.processInfo.thermalState

        let directory = Self.makeRoundDirectory()
        defer { Self.discardRoundDirectory(directory) }

        let scratch = directory.appendingPathComponent("scratch.mov")
        try FileManager.default.copyItem(at: source, to: scratch)

        // B-4. 정규화 전 duration. 측정 구간 밖에서 읽는다.
        let before = try await ClipSpec.load(from: scratch)
        measurement.beforeDuration = before.duration
        measurement.beforeVideoDuration = before.video?.duration
        measurement.beforeAudioDuration = before.audio?.duration
        measurement.inputDataRate = await Self.videoDataRate(of: scratch)

        let output = directory.appendingPathComponent("normalized.mov")

        // 1) 구성 — 컴포지션 + videoComposition + 스냅샷. 고정비 쪽이다.
        let startedPrepare = CFAbsoluteTimeGetCurrent()
        let prepared = try await prepareNormalization(of: scratch, output: output)
        measurement.prepare = CFAbsoluteTimeGetCurrent() - startedPrepare
        measurement.renderSize = prepared.renderSize
        measurement.sourceTransform = prepared.sourceTransform

        // 2) 익스포트 — 픽셀을 다시 그린다. 하드웨어 인코더 경로를 타지 못하는 구간.
        let startedExport = CFAbsoluteTimeGetCurrent()
        let outcome = try await ClipExporter.export(prepared.asset,
                                                    preset: AVAssetExportPreset1920x1080,
                                                    to: output,
                                                    as: .mov,
                                                    videoComposition: prepared.videoComposition)
        measurement.export = CFAbsoluteTimeGetCurrent() - startedExport
        measurement.outputBytes = outcome.fileSize ?? 0

        // 3) 파일 교체 — temp 에 쓰고 원본 자리에 넣는다.
        let startedReplace = CFAbsoluteTimeGetCurrent()
        let replaced = try FileManager.default.replaceItemAt(scratch, withItemAt: output)
        measurement.replace = CFAbsoluteTimeGetCurrent() - startedReplace

        measurement.thermalAfter = ProcessInfo.processInfo.thermalState

        // B-4. 정규화 후 duration. replaceItemAt 이 새 URL 을 돌려주면 그쪽을 읽는다.
        let resulting = replaced ?? scratch
        let after = try await ClipSpec.load(from: resulting)
        measurement.afterDuration = after.duration
        measurement.afterVideoDuration = after.video?.duration
        measurement.afterAudioDuration = after.audio?.duration
        measurement.outputDataRate = await Self.videoDataRate(of: resulting)

        return measurement
    }

    /// 클립 하나를 방향 교정 익스포트용으로 구성한다. 1-21 과 같은 구성이되
    /// 세그먼트가 하나뿐이다.
    private func prepareNormalization(of url: URL, output: URL) async throws -> Prepared {
        let merge = await ClipMerger.merge([url])
        if let fatal = merge.fatal {
            throw NormalizeError.mergeFailed(fatal)
        }
        guard let clip = merge.clips.first,
              let transform = clip.sourceTransform,
              let naturalSize = clip.sourceNaturalSize else {
            throw NormalizeError.transformMissing
        }

        // 캔버스는 이 클립 자신의 표시 규격이다. 계열 안의 180도 차이라면
        // 회전 후 규격이 renderSize 와 정확히 일치하므로 여백이 생기지 않는다.
        let renderSize = MergeReport.renderedSize(naturalSize, transform)
        let segment = OrientationFix.Segment(
            timeRange: CMTimeRange(start: clip.start, duration: clip.advance),
            transform: transform)

        guard let videoComposition = OrientationFix.prepareForOrientationFix(
            merge.composition,
            segments: [segment],
            renderSize: renderSize) else {
            throw NormalizeError.videoCompositionFailed
        }
        guard let asset = merge.composition.copy() as? AVComposition else {
            throw NormalizeError.snapshotFailed
        }

        return Prepared(asset: asset,
                        videoComposition: videoComposition,
                        renderSize: renderSize,
                        sourceTransform: transform)
    }

    // MARK: - 보조

    enum NormalizeError: Error, CustomStringConvertible {
        case mergeFailed(String)
        case transformMissing
        case videoCompositionFailed
        case snapshotFailed

        var description: String {
            switch self {
            case .mergeFailed(let reason): return "병합 실패 — \(reason)"
            case .transformMissing: return "preferredTransform 을 읽지 못했습니다."
            case .videoCompositionFailed: return "videoComposition 을 만들지 못했습니다."
            case .snapshotFailed: return "컴포지션 스냅샷을 만들지 못했습니다."
            }
        }
    }

    private static func makeRoundDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mellow-normalize-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func discardRoundDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func fileSize(of url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size])
            .flatMap { $0 as? NSNumber }?.int64Value ?? 0
    }

    private static func videoDataRate(of url: URL) async -> Float {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let rate = try? await track.load(.estimatedDataRate) else { return 0 }
        return rate
    }
}
