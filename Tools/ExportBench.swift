import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 1-17 익스포트 측정 하네스.
//
// Mellow/ 밖에 둔다. project.yml 의 sources 는 Mellow 디렉터리만 훑으므로
// 여기 있는 파일은 앱 타깃에 들어가지 않는다. 앱에 들어갈 코드는
// Mellow/Merge/ClipExporter.swift 쪽이고, 이 파일은 그것을 여러 번 돌려
// 시간을 재고 결과 파일을 뜯어보는 도구다.
//
// 빌드:
//   swiftc -O -parse-as-library \
//     Mellow/Diagnostics/ClipSpec.swift \
//     Mellow/Merge/ClipMerger.swift \
//     Mellow/Merge/ClipExporter.swift \
//     Tools/ExportBench.swift -o /tmp/exportbench
//
// 측정 규칙
//   - 익스포트마다 3회 반복해 중앙값을 쓴다. 1회차를 따로 표기한다
//     (1-15 에서 첫 회 일회성 비용 204.8ms 를 겪었다)
//   - 출력 파일이 남아 있으면 익스포트가 실패하므로 매 회 지운다
//   - outputFileType 은 .mov 고정. 컨테이너 변환을 변수로 만들지 않는다

// MARK: - 유틸

func ms(_ seconds: TimeInterval) -> String {
    String(format: "%.1fms", seconds * 1000)
}

func mb(_ bytes: Int64) -> String {
    String(format: "%.2fMB", Double(bytes) / 1_000_000)
}

func mbps(_ bitsPerSecond: Float) -> String {
    String(format: "%.3fMbps", bitsPerSecond / 1_000_000)
}

func median(_ values: [TimeInterval]) -> TimeInterval {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

func fileSize(_ url: URL) -> Int64 {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size])
        .flatMap { $0 as? NSNumber }?.int64Value ?? 0
}

func removeIfExists(_ url: URL) {
    if FileManager.default.fileExists(atPath: url.path) {
        try? FileManager.default.removeItem(at: url)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✕ \(message)\n".utf8))
    exit(1)
}

/// 명령이 요구하는 인자가 다 왔는지 본다.
/// 측정 도구라 조용히 크래시하는 것보다 무엇이 빠졌는지 말하고 멈추는 편이 낫다.
func require(_ args: [String], _ count: Int, usage: String) {
    guard args.count >= count else {
        fail("인자가 부족합니다. 사용법: \(usage)")
    }
}

func readList(_ path: String) -> [URL] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("목록 파일을 읽을 수 없습니다: \(path)")
    }
    let urls = text.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        .map { URL(fileURLWithPath: $0) }

    guard !urls.isEmpty else { fail("목록이 비어 있습니다: \(path)") }

    let missing = urls.filter { !FileManager.default.fileExists(atPath: $0.path) }
    guard missing.isEmpty else {
        fail("목록에 없는 파일이 \(missing.count)개 있습니다. 첫 항목: \(missing[0].path)")
    }
    return urls
}

// MARK: - 출력 파일 검사
//
// ClipSpec 이 안 읽는 항목(비트레이트, 트랙 세그먼트 수)을 여기서 따로 읽는다.
// ClipSpec 은 앱 타깃 코드이므로 이 실험 때문에 고치지 않는다.

struct TrackExtras {
    let estimatedDataRate: Float
    let segmentCount: Int
    let formatDescriptionCount: Int
}

func loadExtras(_ url: URL, mediaType: AVMediaType) async -> TrackExtras? {
    let asset = AVURLAsset(url: url)
    guard let track = try? await asset.loadTracks(withMediaType: mediaType).first else {
        return nil
    }
    let rate = (try? await track.load(.estimatedDataRate)) ?? 0
    let segments = (try? await track.load(.segments)) ?? []
    let formats = (try? await track.load(.formatDescriptions)) ?? []
    return TrackExtras(estimatedDataRate: rate,
                       segmentCount: segments.count,
                       formatDescriptionCount: formats.count)
}

/// 방향 이름. 실측 transform 표(CLAUDE.md)와 대조해 붙인다.
/// 하드코딩 매핑 테이블을 만들지 않는다는 제약이 있으므로, 표시용으로만 쓴다.
func orientationLabel(_ t: CGAffineTransform) -> String {
    if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 { return "세로(90)" }
    if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 { return "거꾸로(270)" }
    if t.a == 1 && t.b == 0 && t.c == 0 && t.d == 1 { return "가로L(0)" }
    if t.a == -1 && t.b == 0 && t.c == 0 && t.d == -1 { return "가로R(180)" }
    return "기타"
}

// MARK: - Round 0. 입력 세트 점검

func printClipTable(_ urls: [URL], title: String) async {
    print("══ Round 0: \(title) — \(urls.count)개")
    print("")
    print("| # | 파일 | 방향 | naturalSize | 코덱 | minFrameDur | nominalFPS | 오디오 | v.dur | a.dur | bytes | Mbps |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|")

    var jitterValues = Set<String>()

    for (index, url) in urls.enumerated() {
        guard let spec = try? await ClipSpec.load(from: url) else {
            print("| \(index) | \(url.lastPathComponent) | 읽기 실패 |")
            continue
        }
        let extras = await loadExtras(url, mediaType: .video)
        let v = spec.video
        let a = spec.audio

        let mfd = v.map { "\($0.minFrameDuration.value)/\($0.minFrameDuration.timescale)" } ?? "-"
        jitterValues.insert(mfd)

        let audioText = a.map {
            "\($0.formatID.map(ClipSpec.describe(fourCC:)) ?? "없음") "
            + "\(Int($0.sampleRate))Hz \($0.channelCount)ch"
        } ?? "없음"

        var row = "| \(index) | \(url.lastPathComponent.replacingOccurrences(of: "mellow-", with: "")) "
        row += "| \(v.map { orientationLabel($0.preferredTransform) } ?? "-") "
        row += "| \(v.map { "\(Int($0.naturalSize.width))x\(Int($0.naturalSize.height))" } ?? "-") "
        row += "| \(v?.codec.map(ClipSpec.describe(fourCC:)) ?? "-") "
        row += "| \(mfd) "
        row += "| \(v.map { String(format: "%.5f", $0.nominalFrameRate) } ?? "-") "
        row += "| \(audioText) "
        row += "| \(v.map { String(format: "%.4f", CMTimeGetSeconds($0.duration)) } ?? "-") "
        row += "| \(a.map { String(format: "%.4f", CMTimeGetSeconds($0.duration)) } ?? "-") "
        row += "| \(fileSize(url)) "
        row += "| \(extras.map { mbps($0.estimatedDataRate) } ?? "-") |"
        print(row)
    }

    print("")
    print("   minFrameDuration 관측값: \(jitterValues.sorted().joined(separator: ", "))")
    print("   → 지터 혼재: \(jitterValues.count > 1 ? "있음 (\(jitterValues.count)종)" : "없음 — 단일 값")")
    print("   입력 파일 크기 합계: \(urls.reduce(Int64(0)) { $0 + fileSize($1) }) bytes")
    print("")
}

// MARK: - 출력 파일 리포트

func reportOutput(_ url: URL, label: String) async {
    print("── 출력 검사: \(label)")
    guard let spec = try? await ClipSpec.load(from: url) else {
        print("   ✕ 읽기 실패")
        return
    }
    spec.report()
    if let extras = await loadExtras(url, mediaType: .video) {
        print("   video.estimatedDataRate \(mbps(extras.estimatedDataRate))")
        print("   video.segments          \(extras.segmentCount)")
        print("   video.formatDescs       \(extras.formatDescriptionCount)")
    }
    if let extras = await loadExtras(url, mediaType: .audio) {
        print("   audio.estimatedDataRate \(mbps(extras.estimatedDataRate))")
        print("   audio.segments          \(extras.segmentCount)")
    }
    print("   파일 크기               \(fileSize(url)) bytes (\(mb(fileSize(url))))")
    print("")
}

// MARK: - 반복 측정

struct RunStats {
    let times: [TimeInterval]
    let outputSize: Int64

    var first: TimeInterval { times.first ?? 0 }
    /// 전역 median(_:) 을 가리지 않도록 이름을 달리 둔다.
    var medianTime: TimeInterval { median(times) }
}

/// 같은 익스포트를 repeats 회 반복하고 시간을 모은다.
/// 마지막 회차 출력 파일은 지우지 않고 남긴다 — 결과 검사에 쓴다.
func repeatExport(asset: AVAsset,
                  preset: String,
                  outputURL: URL,
                  videoComposition: AVVideoComposition? = nil,
                  optimizeForNetworkUse: Bool = false,
                  repeats: Int = 3) async -> RunStats? {
    var times: [TimeInterval] = []
    for run in 1...repeats {
        removeIfExists(outputURL)
        do {
            let outcome = try await ClipExporter.export(asset,
                                                        preset: preset,
                                                        to: outputURL,
                                                        as: .mov,
                                                        videoComposition: videoComposition,
                                                        optimizeForNetworkUse: optimizeForNetworkUse)
            times.append(outcome.elapsed)
            print("   run \(run): \(ms(outcome.elapsed))  \(outcome.fileSize.map { "\($0) bytes" } ?? "크기 불명")")
        } catch {
            print("   run \(run): ✕ 실패 — \(error)")
            return nil
        }
    }
    return RunStats(times: times, outputSize: fileSize(outputURL))
}

// MARK: - 컴포지션 만들기 (시간 포함)

/// 병합하고 걸린 시간을 함께 돌려준다.
///
/// 병합이 실패해도 ClipMerger 는 그때까지 만든 컴포지션을 함께 돌려준다.
/// 그걸 그대로 익스포트하면 클립이 덜 들어간 결과를 정상 측정치로 기록하게
/// 되므로, 여기서 끊는다. 측정 도구에서 조용한 부분 성공은 오답보다 나쁘다.
func buildComposition(_ urls: [URL]) async -> (report: MergeReport, elapsed: TimeInterval) {
    let started = CFAbsoluteTimeGetCurrent()
    let report = await ClipMerger.merge(urls)
    let elapsed = CFAbsoluteTimeGetCurrent() - started

    if let fatal = report.fatal {
        fail("병합 실패 — \(fatal)")
    }
    guard report.clips.count == urls.count else {
        fail("병합된 클립 수가 다릅니다: 입력 \(urls.count)개, 병합 \(report.clips.count)개")
    }
    let broken = report.clips.filter { !$0.issues.isEmpty }
    guard broken.isEmpty else {
        fail("온전하지 않은 클립이 \(broken.count)개 있습니다. "
             + "첫 항목: \(broken[0].name) — \(broken[0].issues.joined(separator: ", "))")
    }
    return (report, elapsed)
}

/// AVMutableComposition 은 가변 객체다. 익스포트에 넘기기 전에 스냅샷을 뜬다.
func snapshot(_ composition: AVMutableComposition) -> AVComposition {
    composition.copy() as! AVComposition
}

// MARK: - 프레임 추출

func extractFrames(_ url: URL, seconds: [Double], to directory: URL, prefix: String) async {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    for second in seconds {
        let time = CMTime(seconds: second, preferredTimescale: 600)
        do {
            let (image, actual) = try await generator.image(at: time)
            let out = directory.appendingPathComponent(
                String(format: "%@-%06.2fs.png", prefix, second))
            removeIfExists(out)
            guard let dest = CGImageDestinationCreateWithURL(
                out as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            print("   \(String(format: "%6.2f", second))s → \(image.width)x\(image.height)  "
                  + "(실제 \(String(format: "%.4f", CMTimeGetSeconds(actual)))s)  \(out.lastPathComponent)")
        } catch {
            print("   \(second)s → ✕ \(error.localizedDescription)")
        }
    }
}

// MARK: - 인코딩 샘플 대조
//
// passthrough 판정의 결정적 근거. 시간·크기·메타데이터는 정황이지만,
// 출력의 인코딩된 비디오 샘플이 입력과 **바이트 단위로 같으면** 재인코딩이
// 없었다는 직접 증거가 된다.
//
// AVAssetReaderTrackOutput 을 outputSettings: nil 로 만들면 디코딩하지 않고
// 저장된 그대로의 샘플을 준다.

struct SampleDigest {
    let count: Int
    let totalBytes: Int
    /// 샘플 데이터 전체를 이어붙인 FNV-1a 64비트 해시.
    let hash: UInt64
    /// 앞쪽 몇 개 샘플의 (크기, PTS) — 어긋났을 때 어디부터인지 보려고.
    let head: [(Int, CMTime)]
    /// 미디어를 담지 않은 마커 버퍼 수. 아래 주석 참고.
    let markers: Int
}

func fnv1a(_ seed: UInt64, _ bytes: UnsafeRawBufferPointer) -> UInt64 {
    var hash = seed
    for byte in bytes {
        hash ^= UInt64(byte)
        hash = hash &* 0x100_0000_01b3
    }
    return hash
}

/// 여러 애셋을 순서대로 훑으며 누적한다.
///
/// 미디어를 담은 샘플을 하나라도 흘리면 요약을 내지 않는다. 이 대조의 결론은
/// "입력과 출력이 바이트 단위로 같다"이고, 양쪽에서 똑같이 샘플을 흘리면
/// 그 결론이 거짓으로 성립한다. 빠뜨리느니 판정을 포기하는 편이 맞다.
///
/// 단, **마커 버퍼는 예외다.** `AVAssetReaderTrackOutput` 은 클립마다
/// `numSamples == 0` 이고 데이터 버퍼가 없는 버퍼를 몇 개 섞어 내보낸다
/// (iPhone 12 클립 실측: 클립당 4개 — 맨 앞 pts 0 에 1개, 끝에 pts NaN 으로 3개).
/// 프레임이 아니라 경계 표시이므로 세지 않는다. 실제로 9.96초 클립에서
/// 데이터 있는 버퍼가 정확히 299개(30fps 기준 프레임 수)로 나온다.
/// numSamples 가 0 이 아닌데 데이터 버퍼가 없으면 그건 진짜 이상이므로 실패로 본다.
private struct SampleAccumulator {
    var count = 0
    var totalBytes = 0
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    var head: [(Int, CMTime)] = []
    var markers = 0

    /// 애셋 하나를 읽어 누적한다. 조금이라도 온전하지 않으면 사유를 돌려준다.
    mutating func consume(_ asset: AVAsset) async -> String? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return "비디오 트랙을 읽지 못했습니다"
        }
        guard let reader = try? AVAssetReader(asset: asset) else {
            return "AVAssetReader 를 만들지 못했습니다"
        }

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return "리더에 출력을 붙일 수 없습니다" }
        reader.add(output)
        guard reader.startReading() else {
            return "읽기를 시작하지 못했습니다: \(reader.error?.localizedDescription ?? "사유 불명")"
        }

        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) == 0 {
                markers += 1
                continue
            }
            guard let block = CMSampleBufferGetDataBuffer(sample) else {
                reader.cancelReading()
                return "샘플 \(count) 이 미디어를 담았다고 하는데 데이터 버퍼가 없습니다"
            }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [UInt8](repeating: 0, count: length)
            let status = bytes.withUnsafeMutableBytes { raw -> OSStatus in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                           destination: raw.baseAddress!)
            }
            guard status == noErr else {
                reader.cancelReading()
                return "샘플 \(count) 복사 실패 (OSStatus \(status))"
            }
            bytes.withUnsafeBytes { hash = fnv1a(hash, $0) }

            if head.count < 5 {
                head.append((length, CMSampleBufferGetPresentationTimeStamp(sample)))
            }
            count += 1
            totalBytes += length
        }

        // 루프는 nil 로도, 실패로도 끝난다. 둘을 구분해야 한다.
        guard reader.status == .completed else {
            return "읽기가 끝까지 가지 못했습니다 (status \(reader.status.rawValue)): "
                + (reader.error?.localizedDescription ?? "사유 불명")
        }
        return nil
    }

    var digest: SampleDigest {
        SampleDigest(count: count, totalBytes: totalBytes, hash: hash, head: head, markers: markers)
    }
}

/// 애셋의 비디오 트랙에서 인코딩된 샘플을 순서대로 읽어 요약한다.
func digestVideoSamples(_ asset: AVAsset) async -> SampleDigest? {
    var accumulator = SampleAccumulator()
    if let reason = await accumulator.consume(asset) {
        print("   ✕ 샘플 읽기 실패 — \(reason)")
        return nil
    }
    return accumulator.digest
}

/// 여러 입력 클립의 샘플을 순서대로 이어 하나의 요약으로 만든다.
func digestVideoSamples(of urls: [URL]) async -> SampleDigest? {
    var accumulator = SampleAccumulator()
    for url in urls {
        if let reason = await accumulator.consume(AVURLAsset(url: url)) {
            print("   ✕ 샘플 읽기 실패 — \(url.lastPathComponent): \(reason)")
            return nil
        }
    }
    return accumulator.digest
}

// MARK: - 진입점

@main
struct ExportBench {

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            print("""
            사용법:
              scan   <dir>                       디렉터리 안 모든 클립 스펙 표
              round0 <list> <title>              세트 하나의 입력 점검
              roundA <list> <outdir>             passthrough 성립 여부
              roundB1 <list> <outdir>            세션 전체 재인코딩
              roundB2 <list> <outdir>            단일 클립 재인코딩 (목록 첫 항목)
              roundB3 <list> <outdir> <W> <H> <label>   방향 교정 재인코딩
              roundC <list> <outdir> <n>         목록을 n배 복제해 확장성 측정
              frames <mov> <outdir> <prefix> <t,t,...>  프레임 추출
              verify <list> <mov>                출력의 인코딩 샘플이 입력과 같은 바이트인지
            """)
            exit(1)
        }

        switch command {
        case "scan":       await scan(args)
        case "round0":     await round0(args)
        case "roundA":     await roundA(args)
        case "roundB1":    await roundB1(args)
        case "roundB2":    await roundB2(args)
        case "roundB3":    await roundB3(args)
        case "roundC":     await roundC(args)
        case "frames":     await frames(args)
        case "verify":     await verify(args)
        default:
            print("알 수 없는 명령: \(command)")
            exit(1)
        }
    }

    // MARK: scan

    static func scan(_ args: [String]) async {
        require(args, 2, usage: "scan <dir>")
        let dir = URL(fileURLWithPath: args[1])
        let files = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                  includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension.lowercased() == "mov" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a < b
            } ?? []

        print("== scan: \(dir.path) — \(files.count)개 (수정시각 오름차순)")
        print("")
        print("| # | mtime | 파일 | 방향 | naturalSize | minFrameDur | nomFPS | dur(s) | bytes |")
        print("|---|---|---|---|---|---|---|---|---|")

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"

        for (index, url) in files.enumerated() {
            guard let spec = try? await ClipSpec.load(from: url) else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let v = spec.video
            var row = "| \(index) | \(formatter.string(from: mtime)) | \(url.lastPathComponent) "
            row += "| \(v.map { orientationLabel($0.preferredTransform) } ?? "-") "
            row += "| \(v.map { "\(Int($0.naturalSize.width))x\(Int($0.naturalSize.height))" } ?? "-") "
            row += "| \(v.map { "\($0.minFrameDuration.value)/\($0.minFrameDuration.timescale)" } ?? "-") "
            row += "| \(v.map { String(format: "%.4f", $0.nominalFrameRate) } ?? "-") "
            row += "| \(String(format: "%.3f", CMTimeGetSeconds(spec.duration))) "
            row += "| \(fileSize(url)) |"
            print(row)
        }
    }

    // MARK: round0

    static func round0(_ args: [String]) async {
        require(args, 2, usage: "round0 <list> [title]")
        let urls = readList(args[1])
        let title = args.count > 2 ? args[2] : args[1]
        await printClipTable(urls, title: title)
    }

    // MARK: roundA — passthrough 성립 여부

    static func roundA(_ args: [String]) async {
        require(args, 3, usage: "roundA <list> <outdir>")
        let urls = readList(args[1])
        let outdir = URL(fileURLWithPath: args[2])
        try? FileManager.default.createDirectory(at: outdir, withIntermediateDirectories: true)

        print("══ Round A — passthrough 성립 여부 (입력 \(urls.count)개)")
        print("")

        let (merge, buildTime) = await buildComposition(urls)
        merge.report(title: "Round A 입력")
        print("   컴포지션 구성 시간: \(ms(buildTime))")
        print("")

        let asset = snapshot(merge.composition)

        // 1) exportPresets(compatibleWith:) — 구 API.
        //    헤더에 "passthrough 는 이 배열에 포함되지 않는다"고 명시되어 있다.
        //    그 사실을 확인하기 위해 그대로 찍는다.
        let legacy = AVAssetExportSession.exportPresets(compatibleWith: asset)
        print("── exportPresets(compatibleWith:) — \(legacy.count)개  ※ iOS 16 deprecated")
        for preset in legacy.sorted() { print("     \(preset)") }
        print("     passthrough 포함? \(legacy.contains(AVAssetExportPresetPassthrough))")
        print("")

        // 2) determineCompatibility — 현행 API. passthrough 판정은 이쪽이 근거다.
        let passthroughOK = await ClipExporter.isCompatible(preset: ClipExporter.passthroughPreset,
                                                           with: asset,
                                                           outputFileType: .mov)
        let reencodeOK = await ClipExporter.isCompatible(preset: AVAssetExportPreset1920x1080,
                                                        with: asset,
                                                        outputFileType: .mov)
        print("── compatibility(ofExportPreset:with:outputFileType: .mov)")
        print("     Passthrough  → \(passthroughOK)")
        print("     1920x1080    → \(reencodeOK)")
        print("")

        // 3) passthrough 익스포트 3회
        let out = outdir.appendingPathComponent("roundA-passthrough.mov")
        print("── passthrough 익스포트 (3회)")
        guard let stats = await repeatExport(asset: asset,
                                             preset: ClipExporter.passthroughPreset,
                                             outputURL: out) else { return }
        print("   1회차 \(ms(stats.first))   중앙값 \(ms(stats.medianTime))")
        print("")

        // 4) shouldOptimizeForNetworkUse = true 로 1회
        let outFast = outdir.appendingPathComponent("roundA-passthrough-faststart.mov")
        print("── passthrough + shouldOptimizeForNetworkUse = true (3회)")
        let fastStats = await repeatExport(asset: asset,
                                           preset: ClipExporter.passthroughPreset,
                                           outputURL: outFast,
                                           optimizeForNetworkUse: true)
        if let fastStats {
            print("   1회차 \(ms(fastStats.first))   중앙값 \(ms(fastStats.medianTime))")
            print("   크기 \(fastStats.outputSize) bytes (기본 대비 \(fastStats.outputSize - stats.outputSize) bytes 차이)")
        }
        print("")

        // 5) 결과 대조
        let inputTotal = urls.reduce(Int64(0)) { $0 + fileSize($1) }
        print("── 크기 대조")
        print("   입력 합계   \(inputTotal) bytes (\(mb(inputTotal)))")
        print("   출력        \(stats.outputSize) bytes (\(mb(stats.outputSize)))")
        if inputTotal > 0 {
            print(String(format: "   비율        %.2f%%", Double(stats.outputSize) / Double(inputTotal) * 100))
        } else {
            print("   비율        — (입력 크기를 읽지 못했습니다)")
        }
        print("")

        await reportOutput(out, label: "roundA-passthrough.mov")

        // 입력 클립 하나와 출력의 스펙을 나란히 본다.
        if let firstSpec = try? await ClipSpec.load(from: urls[0]),
           let outSpec = try? await ClipSpec.load(from: out) {
            print("── 입력[0] vs 출력 — 차이만")
            let diffs = ClipSpec.differences(base: firstSpec, other: outSpec)
            if diffs.isEmpty {
                print("     차이 없음")
            }
            for diff in diffs {
                let mark = diff.kind == .compatibility ? "✕" : "·"
                print("     \(mark) \(diff.field)")
                print("         입력  \(diff.base)")
                print("         출력  \(diff.other)")
            }
        }
        print("")
    }

    // MARK: roundB1 — 세션 전체 재인코딩

    static func roundB1(_ args: [String]) async {
        require(args, 3, usage: "roundB1 <list> <outdir>")
        let urls = readList(args[1])
        let outdir = URL(fileURLWithPath: args[2])
        try? FileManager.default.createDirectory(at: outdir, withIntermediateDirectories: true)

        print("══ Round B-1 — 세션 전체 재인코딩 (입력 \(urls.count)개)")
        let (merge, buildTime) = await buildComposition(urls)
        print("   컴포지션 구성 \(ms(buildTime))  총 길이 \(String(format: "%.3f", CMTimeGetSeconds(merge.compositionDuration)))s")
        print("")

        let asset = snapshot(merge.composition)
        let out = outdir.appendingPathComponent("roundB1-1920x1080.mov")
        print("── AVAssetExportPreset1920x1080 (3회)")
        guard let stats = await repeatExport(asset: asset,
                                             preset: AVAssetExportPreset1920x1080,
                                             outputURL: out) else { return }
        print("   1회차 \(ms(stats.first))   중앙값 \(ms(stats.medianTime))")
        let realtime = CMTimeGetSeconds(merge.compositionDuration)
        print(String(format: "   영상 실시간 %.3fs 대비 %.4f배", realtime, stats.medianTime / realtime))
        print("")
        await reportOutput(out, label: "roundB1-1920x1080.mov")
    }

    // MARK: roundB2 — 단일 클립 재인코딩

    static func roundB2(_ args: [String]) async {
        require(args, 3, usage: "roundB2 <list> <outdir>")
        let urls = readList(args[1])
        let outdir = URL(fileURLWithPath: args[2])
        try? FileManager.default.createDirectory(at: outdir, withIntermediateDirectories: true)

        let url = urls[0]
        print("══ Round B-2 — 단일 클립 재인코딩: \(url.lastPathComponent)")
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)) ?? .zero
        print("   길이 \(String(format: "%.3f", CMTimeGetSeconds(duration)))s  크기 \(fileSize(url)) bytes")
        print("")

        let out = outdir.appendingPathComponent("roundB2-single-1920x1080.mov")
        print("── AVAssetExportPreset1920x1080 (3회)")
        guard let stats = await repeatExport(asset: asset,
                                             preset: AVAssetExportPreset1920x1080,
                                             outputURL: out) else { return }
        print("   1회차 \(ms(stats.first))   중앙값 \(ms(stats.medianTime))")
        let realtime = CMTimeGetSeconds(duration)
        print(String(format: "   영상 실시간 %.3fs 대비 %.4f배", realtime, stats.medianTime / realtime))
        print("")

        // 같은 클립 하나를 passthrough 로도 재서 배수 기준을 만든다.
        let outPass = outdir.appendingPathComponent("roundB2-single-passthrough.mov")
        print("── 같은 클립 passthrough (3회) — 배수 기준")
        if let passStats = await repeatExport(asset: asset,
                                              preset: ClipExporter.passthroughPreset,
                                              outputURL: outPass) {
            print("   1회차 \(ms(passStats.first))   중앙값 \(ms(passStats.medianTime))")
            print(String(format: "   재인코딩 / passthrough = %.1f배", stats.medianTime / passStats.medianTime))
        }
        print("")
        await reportOutput(out, label: "roundB2-single-1920x1080.mov")
    }

    // MARK: roundB3 — 방향 교정 재인코딩

    static func roundB3(_ args: [String]) async {
        require(args, 5, usage: "roundB3 <list> <outdir> <W> <H> [label]")
        let urls = readList(args[1])
        let outdir = URL(fileURLWithPath: args[2])
        let width = Double(args[3]) ?? 1920
        let height = Double(args[4]) ?? 1080
        let label = args.count > 5 ? args[5] : "B3"
        try? FileManager.default.createDirectory(at: outdir, withIntermediateDirectories: true)

        print("══ Round B-3 (\(label)) — 방향 교정 재인코딩, renderSize \(Int(width))x\(Int(height))")
        print("   입력 \(urls.count)개")
        print("")

        let (merge, buildTime) = await buildComposition(urls)
        merge.report(title: "\(label) 입력")
        print("   컴포지션 구성 \(ms(buildTime))")
        print("")

        // 클립마다 자기 원본 transform 을 그 구간에만 적용한다.
        //
        // 클립과 세그먼트를 함께 들고 다닌다. 걸러내고 나서 인덱스로 원본을
        // 다시 찾으면, transform 없는 클립이 하나만 있어도 짝이 어긋나
        // 엉뚱한 클립의 규격으로 "캔버스 일치" 판정을 내리게 된다.
        let paired: [(clip: MergedClip, segment: OrientationFix.Segment)] = merge.clips.compactMap { clip in
            guard let transform = clip.sourceTransform else { return nil }
            let segment = OrientationFix.Segment(
                timeRange: CMTimeRange(start: clip.start, duration: clip.advance),
                transform: transform)
            return (clip, segment)
        }
        guard paired.count == merge.clips.count else {
            fail("preferredTransform 을 읽지 못한 클립이 "
                 + "\(merge.clips.count - paired.count)개 있습니다. 방향 교정을 측정할 수 없습니다.")
        }
        let segments = paired.map(\.segment)

        print("── layerInstruction 구성")
        var canvasMismatch = 0
        for (index, pair) in paired.enumerated() {
            let rendered = MergeReport.renderedSize(
                pair.clip.sourceNaturalSize ?? .zero, pair.segment.transform)
            let matches = Int(rendered.width) == Int(width) && Int(rendered.height) == Int(height)
            if !matches { canvasMismatch += 1 }
            print(String(format: "   [%d] %7.3fs ~ %7.3fs  %@  → %dx%d %@",
                         index,
                         CMTimeGetSeconds(pair.segment.timeRange.start),
                         CMTimeGetSeconds(CMTimeRangeGetEnd(pair.segment.timeRange)),
                         orientationLabel(pair.segment.transform),
                         Int(rendered.width), Int(rendered.height),
                         matches ? "✓ 캔버스 일치" : "✕ 여백 발생"))
        }
        if canvasMismatch > 0 {
            print("   ⚠ 캔버스와 안 맞는 클립 \(canvasMismatch)개 — 여백이 생긴다."
                  + " 계열 간 혼재이거나 renderSize 가 틀렸다")
        }
        print("")

        // 컴포지션 트랙 transform 을 identity 로 되돌리는 것까지 여기서 일어난다.
        // 그래서 스냅샷은 이 호출 뒤에 뜬다.
        guard let videoComposition = OrientationFix.prepareForOrientationFix(
            merge.composition,
            segments: segments,
            renderSize: CGSize(width: width, height: height)) else {
            fail("videoComposition 을 만들 수 없습니다 (비디오 트랙 없음 또는 구간 없음)")
        }
        print("   videoComposition: renderSize \(Int(videoComposition.renderSize.width))x\(Int(videoComposition.renderSize.height))"
              + "  frameDuration \(videoComposition.frameDuration.value)/\(videoComposition.frameDuration.timescale)"
              + "  instructions \(videoComposition.instructions.count)")
        print("   컴포지션 트랙 transform → \(ClipSpec.describe(transform: merge.composition.tracks(withMediaType: .video).first?.preferredTransform ?? .identity))")
        print("")

        let asset = snapshot(merge.composition)
        let out = outdir.appendingPathComponent("roundB3-\(label).mov")
        print("── AVAssetExportPreset1920x1080 + videoComposition (3회)")
        guard let stats = await repeatExport(asset: asset,
                                             preset: AVAssetExportPreset1920x1080,
                                             outputURL: out,
                                             videoComposition: videoComposition) else { return }
        print("   1회차 \(ms(stats.first))   중앙값 \(ms(stats.medianTime))")
        let realtime = CMTimeGetSeconds(merge.compositionDuration)
        print(String(format: "   영상 실시간 %.3fs 대비 %.4f배", realtime, stats.medianTime / realtime))
        print("")
        await reportOutput(out, label: "roundB3-\(label).mov")

        // 각 클립 구간 중앙에서 프레임을 뽑아 육안 대조에 쓴다.
        print("── 프레임 추출 (각 구간 중앙)")
        let times = segments.map {
            CMTimeGetSeconds($0.timeRange.start) + CMTimeGetSeconds($0.timeRange.duration) / 2
        }
        await extractFrames(out, seconds: times,
                            to: outdir.appendingPathComponent("frames-\(label)"),
                            prefix: label)
        print("")
    }

    // MARK: roundC — 확장성

    static func roundC(_ args: [String]) async {
        require(args, 4, usage: "roundC <list> <outdir> <n>")
        let base = readList(args[1])
        let outdir = URL(fileURLWithPath: args[2])
        let factor = Int(args[3]) ?? 1
        try? FileManager.default.createDirectory(at: outdir, withIntermediateDirectories: true)

        // 같은 방향 클립을 복제해 늘린다. 방향이 섞이면 안 되므로 세트를 반복한다.
        var urls: [URL] = []
        for _ in 0..<factor { urls.append(contentsOf: base) }

        print("══ Round C — 클립 \(urls.count)개 (기준 세트 \(base.count)개 × \(factor))")
        print("")

        // 컴포지션 구성 3회
        var buildTimes: [TimeInterval] = []
        var lastReport: MergeReport?
        for run in 1...3 {
            let (report, elapsed) = await buildComposition(urls)
            buildTimes.append(elapsed)
            lastReport = report
            print("   구성 run \(run): \(ms(elapsed))")
        }
        guard let merge = lastReport else { return }
        let buildMedian = median(buildTimes)
        print("   구성 1회차 \(ms(buildTimes[0]))   중앙값 \(ms(buildMedian))")
        print(String(format: "   클립당 구성 비용 %.3fms", buildMedian * 1000 / Double(urls.count)))
        print("   세그먼트 video \(merge.videoSegmentCount) / audio \(merge.audioSegmentCount)")
        print("   총 길이 \(String(format: "%.3f", CMTimeGetSeconds(merge.compositionDuration)))s")
        print("")

        let asset = snapshot(merge.composition)
        let out = outdir.appendingPathComponent("roundC-\(urls.count).mov")
        print("── passthrough 익스포트 (3회)")
        guard let stats = await repeatExport(asset: asset,
                                             preset: ClipExporter.passthroughPreset,
                                             outputURL: out) else { return }
        print("   1회차 \(ms(stats.first))   중앙값 \(ms(stats.medianTime))")
        print(String(format: "   클립당 익스포트 비용 %.3fms", stats.medianTime * 1000 / Double(urls.count)))
        print("   출력 \(stats.outputSize) bytes (\(mb(stats.outputSize)))")
        print("")
    }

    // MARK: verify — 인코딩 샘플 바이트 대조

    static func verify(_ args: [String]) async {
        require(args, 3, usage: "verify <list> <mov>")
        let urls = readList(args[1])
        let out = URL(fileURLWithPath: args[2])

        print("══ 인코딩 샘플 대조: 입력 \(urls.count)개  vs  \(out.lastPathComponent)")
        print("")

        guard let inputDigest = await digestVideoSamples(of: urls) else {
            print("   ✕ 입력 샘플을 읽지 못했습니다")
            return
        }
        guard let outputDigest = await digestVideoSamples(AVURLAsset(url: out)) else {
            print("   ✕ 출력 샘플을 읽지 못했습니다")
            return
        }

        func show(_ label: String, _ digest: SampleDigest) {
            print("── \(label)")
            print("   샘플 수     \(digest.count)  (미디어 없는 마커 버퍼 \(digest.markers)개는 제외)")
            print("   샘플 총 바이트 \(digest.totalBytes)")
            print(String(format: "   FNV-1a 해시  0x%016llx", digest.hash))
            let head = digest.head.map { "\($0.0)B@\(String(format: "%.4f", CMTimeGetSeconds($0.1)))s" }
            print("   앞 5개      \(head.joined(separator: "  "))")
        }
        show("입력 클립들을 순서대로 이어 읽음", inputDigest)
        show("출력 파일", outputDigest)
        print("")

        let sameCount = inputDigest.count == outputDigest.count
        let sameBytes = inputDigest.totalBytes == outputDigest.totalBytes
        let sameHash = inputDigest.hash == outputDigest.hash
        print("── 판정")
        print("   샘플 수 일치       \(sameCount ? "✓" : "✕")")
        print("   샘플 총 바이트 일치 \(sameBytes ? "✓" : "✕")"
              + (sameBytes ? "" : "  (차이 \(outputDigest.totalBytes - inputDigest.totalBytes)B)"))
        print("   샘플 바이트 해시 일치 \(sameHash ? "✓" : "✕")")
        print("")
        if sameCount && sameBytes && sameHash {
            print("   → 출력의 인코딩된 비디오 샘플이 입력과 바이트 단위로 동일하다.")
        } else {
            print("   → 출력의 인코딩된 비디오 샘플이 입력과 다르다.")
        }
        print("")
    }

    // MARK: frames

    static func frames(_ args: [String]) async {
        require(args, 5, usage: "frames <mov> <outdir> <prefix> <t,t,...>")
        let url = URL(fileURLWithPath: args[1])
        let outdir = URL(fileURLWithPath: args[2])
        let prefix = args[3]
        let times = args[4].split(separator: ",").compactMap { Double($0) }
        print("══ 프레임 추출: \(url.lastPathComponent)")
        await extractFrames(url, seconds: times, to: outdir, prefix: prefix)
    }
}
