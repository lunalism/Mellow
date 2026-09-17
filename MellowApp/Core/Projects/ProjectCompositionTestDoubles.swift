#if DEBUG
import AVFoundation
import CoreGraphics
import Foundation

/// Deterministic stand-ins for the Phase 5 composition boundaries. Shared by unit tests and the
/// opted-in simulator UI tests; never compiled into release.

/// Writes tiny real H.264 QuickTime files so validation / materialization run against actual media.
enum FixtureVideoWriter {
    /// Solid-colour frames at `size` for `seconds` at 30 fps, no audio. Portrait when height > width.
    static func write(to url: URL, size: CGSize = CGSize(width: 540, height: 960), seconds: Double = 2) async throws {
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let frames = Int((seconds * 30).rounded())
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, frame % 2 == 0 ? 0x80 : 0x40, CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    /// Bytes that are not a media container at all.
    static func writeCorrupt(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: url)
    }
}

/// Copies prepared fixture files into the workspace (proving the picker's temporary can vanish
/// afterwards) or reports cancel / failure.
@MainActor
final class FakeProjectMediaSelector: ProjectMediaSelecting {
    enum Script { case cancel, fixtures([URL]), fail }
    var script: Script
    /// Lets the UI-test harness generate fixture media after launch without racing the first tap.
    var pendingScript: Task<Script, Never>?
    private(set) var selectionCount = 0

    init(script: Script) { self.script = script }

    /// Every pre-copy admission the fake performed: the incoming byte size it asked for.
    private(set) var admittedBytes: [Int64] = []
    /// The selection limit each session was asked for (nil = unlimited), in call order.
    private(set) var selectionLimits: [Int?] = []

    func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating) async -> ProjectMediaSelectionOutcome {
        await selectVideos(into: workspace, store: store, admission: admission, selectionLimit: nil)
    }

    /// The scripted fixtures are returned as-is whatever the limit: a Replace test that scripts two
    /// fixtures proves the MODEL refuses the cardinality, not the fake.
    func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating, selectionLimit: Int?) async -> ProjectMediaSelectionOutcome {
        selectionCount += 1
        selectionLimits.append(selectionLimit)
        if let pendingScript {
            script = await pendingScript.value
            self.pendingScript = nil
        }
        switch script {
        case .cancel: return .cancelled
        case .fail: return .failed
        case .fixtures(let urls):
            var sources: [SelectedVideoSource] = []
            for fixture in urls {
                // Same sequence as the production bridge: size → admission → first Mellow-owned copy → adopt.
                let incoming = Int64((try? fixture.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                admittedBytes.append(incoming)
                if case .insufficient = await admission.check(additionalBytes: incoming) { return .insufficientStorage }
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                do {
                    try FileManager.default.copyItem(at: fixture, to: temp)
                    let adopted = try await store.adopt(temp, into: workspace)
                    let bytes = (try? adopted.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    sources.append(SelectedVideoSource(url: adopted, byteCount: bytes))
                } catch {
                    return .failed
                }
            }
            return .selected(sources)
        }
    }
}

@MainActor
final class FakeProjectMediaInspector: ProjectMediaInspecting {
    var nextInfo: ProjectMediaInfo
    private(set) var inspected: [URL] = []
    init(_ info: ProjectMediaInfo) { nextInfo = info }
    func inspect(_ url: URL) async -> ProjectMediaInfo {
        inspected.append(url)
        return nextInfo
    }
}

struct FakeProjectStorageGate: ProjectStorageGating {
    var verdict: ProjectStorageVerdict = .sufficient
    func check(additionalBytes: Int64) async -> ProjectStorageVerdict { verdict }
}

/// Records every check and answers from a scripted capacity sequence (last value repeats), so tests
/// can prove sequential per-file admission and that capacity is re-queried each time.
@MainActor
final class ScriptedCapacityGate: ProjectStorageGating {
    private(set) var checks: [Int64] = []
    private var capacities: [Int64]
    let safetyReserveBytes: Int64
    init(capacities: [Int64], safetyReserveBytes: Int64 = ProjectCompositionPolicy.materializationSafetyReserveBytes) {
        self.capacities = capacities
        self.safetyReserveBytes = safetyReserveBytes
    }
    func check(additionalBytes: Int64) async -> ProjectStorageVerdict {
        checks.append(additionalBytes)
        let usable = capacities.count > 1 ? capacities.removeFirst() : (capacities.first ?? 0)
        let required = VolumeProjectStorageGate.requiredBytes(additionalBytes: additionalBytes, safetyReserveBytes: safetyReserveBytes)
        return usable >= required ? .sufficient : .insufficient(requiredBytes: required, usableBytes: usable)
    }
}

extension ProjectMediaInfo {
    /// A Phase-5-ready portrait 1080p / 30 fps / SDR clip of `seconds`.
    static func ready(seconds: TimeInterval = 2) -> ProjectMediaInfo {
        ProjectMediaInfo(isReadable: true, hasVideoTrack: true, hasAudioTrack: true, duration: seconds, presentationSize: CGSize(width: 1080, height: 1920), nominalFrameRate: 30, isHDR: false)
    }
}
#endif

#if DEBUG
extension ProjectCompositionCoordinator {
    /// Lookup-only coordinator for tests that never compose (composition dependencies are inert).
    @MainActor
    static func readOnlyForTests(repository: any ProjectRepository) -> ProjectCompositionCoordinator {
        ProjectCompositionCoordinator(
            repository: repository,
            mediaStore: ProjectMediaStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("ReadOnly-\(UUID().uuidString)")),
            validator: Phase5ReadyMediaValidator(inspector: FakeProjectMediaInspector(.ready())),
            storage: FakeProjectStorageGate(verdict: .sufficient),
            lifecycle: ProjectLifecycleOperationGate()
        )
    }
}

#endif
