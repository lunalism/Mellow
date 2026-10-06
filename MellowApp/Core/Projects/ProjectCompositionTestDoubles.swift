#if DEBUG
import AVFoundation
import CoreGraphics
import Foundation

/// Deterministic stand-ins for the Phase 5 composition boundaries. Shared by unit tests and the
/// opted-in simulator UI tests; never compiled into release.

/// Writes tiny real H.264 QuickTime files so validation / materialization run against actual media.
enum FixtureVideoWriter {
    /// Solid-colour frames at `size` for `seconds` at `fps` (default 30), no audio. Portrait when height > width.
    /// 60 fps makes a normalization-required (frame-rate) source for Phase 6 tests.
    static func write(to url: URL, size: CGSize = CGSize(width: 540, height: 960), seconds: Double = 2, fps: Int32 = 30) async throws {
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
        let frames = Int((seconds * Double(fps)).rounded())
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
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
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
                // Same sequence as the production bridge: size (unknown refuses) → C0 admission → first Mellow-owned copy
                // → adopt (whose C0a refusal is a storage outcome too).
                guard let incoming = ImportCopyAdmission.sourceByteCount(of: fixture) else { return .insufficientStorage }
                admittedBytes.append(incoming)
                if case .insufficient = await admission.check(additionalBytes: incoming) { return .insufficientStorage }
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                do {
                    try FileManager.default.copyItem(at: fixture, to: temp)
                    let adopted = try await store.adopt(temp, into: workspace)
                    let bytes = (try? adopted.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    sources.append(SelectedVideoSource(url: adopted, byteCount: bytes))
                } catch is ProjectMediaAdmissionRefused {
                    try? FileManager.default.removeItem(at: temp)
                    return .insufficientStorage
                } catch {
                    try? FileManager.default.removeItem(at: temp)
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

/// UI-test normalizer (DEBUG only): the REAL normalizer, optionally held for `-uiTestNormalizerDelay=<ms>` before each
/// item (so the Preparation Sheet is observable and cancellable) and failing its first `-uiTestNormalizerFailures=<n>`
/// items (so the R4 §3 Retry path can be driven). Progress is the real normalizer's.
struct UITestScriptedNormalizer: WorkingMediaNormalizing {
    private final class Failures: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: Int
        init(_ count: Int) { remaining = count }
        func take() -> Bool { lock.lock(); defer { lock.unlock() }; guard remaining > 0 else { return false }; remaining -= 1; return true }
    }
    private let inner = AVFoundationWorkingMediaNormalizer()
    private let delay: Duration
    private let failures: Failures

    init(arguments: [String]) {
        func value(_ key: String) -> Int {
            arguments.first { $0.hasPrefix(key) }.flatMap { Int($0.replacingOccurrences(of: key, with: "")) } ?? 0
        }
        delay = .milliseconds(value("-uiTestNormalizerDelay="))
        failures = Failures(value("-uiTestNormalizerFailures="))
    }

    func normalize(sourceURL: URL, destinationURL: URL, plan: WorkingMediaNormalizationPlan) async throws -> WorkingMediaNormalizationResult {
        try await normalize(sourceURL: sourceURL, destinationURL: destinationURL, plan: plan, progress: nil)
    }

    func normalize(sourceURL: URL, destinationURL: URL, plan: WorkingMediaNormalizationPlan,
                   progress: (@Sendable (Double) -> Void)?) async throws -> WorkingMediaNormalizationResult {
        try await Task.sleep(for: delay)
        if failures.take() { throw WorkingMediaNormalizationError.writerFailed(domain: "UITest", code: 1) }
        return try await inner.normalize(sourceURL: sourceURL, destinationURL: destinationURL, plan: plan, progress: progress)
    }
}
#endif
