#if DEBUG
import AVFoundation
import CoreMedia
import Foundation

/// Snapshot published while a diagnostic conversion runs.
struct Phase6SpikeProgress: Sendable {
    var fraction: Double = 0
    var elapsed: TimeInterval = 0
    var thermal: ProcessInfo.ThermalState = .nominal
    var footprintBytes: Int64 = -1
    var freeCapacityBytes: Int64 = -1
    var stage = "idle"
}

/// Final measurements of one conversion (success, cancellation or failure alike).
struct Phase6SpikeResult: Sendable {
    var mode: String
    var outputURL: URL
    var succeeded = false
    var cancelled = false
    var errorDescription: String?
    var readerStatus = "n/a"
    var writerStatus = "n/a"
    var elapsed: TimeInterval = 0
    var thermalBefore: ProcessInfo.ThermalState = .nominal
    var thermalPeak: ProcessInfo.ThermalState = .nominal
    var thermalAfter: ProcessInfo.ThermalState = .nominal
    var footprintBefore: Int64 = -1
    var footprintPeak: Int64 = -1
    var footprintAfter: Int64 = -1
    var capacityBefore: Int64 = -1
    var capacityMinimumDuring: Int64 = -1
    var capacityAfter: Int64 = -1
    var sourceBytes: Int64 = 0
    var outputBytes: Int64 = 0
    var videoSamples = 0
    var audioSamples = 0
    var partialOutputExistedAfterCancel: Bool?
    var cleanupSucceeded: Bool?
    var outputExistsAfterCleanup: Bool?
    var notes: [String] = []
    // Deterministic cancellation evidence (nil when the run was not cancelled / mode was OFF).
    var autoCancelThreshold: Double?
    var cancellationSource: String?
    var cancellationRequestedProgress: Double?
    var cancellationRequestedAt: Date?
    var cancellationRequestCount: Int?
    // Spike-owned source copy must be unchanged by any run.
    var sourceBytesAfter: Int64 = -1
    var sourceModificationBefore: Date?
    var sourceModificationAfter: Date?
    var sourceUnchanged: Bool? { sourceBytesAfter >= 0 ? (sourceBytesAfter == sourceBytes && sourceModificationBefore == sourceModificationAfter) : nil }

    var peakTemporaryDelta: Int64 { capacityBefore >= 0 && capacityMinimumDuring >= 0 ? capacityBefore - capacityMinimumDuring : -1 }
}

enum Phase6SpikeMetrics {
    /// Resident memory footprint through the public `task_info` / `TASK_VM_INFO` interface.
    static func footprintBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
    }

    static func freeCapacityBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? -1
    }

    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state { case .nominal: return "nominal"; case .fair: return "fair"; case .serious: return "serious"; case .critical: return "critical"; @unknown default: return "unknown" }
    }
}

/// One-shot reader → writer H.264 / 709 normalization of a QuickTime source with sample-based
/// progress, a shared idempotent cancellation token (manual button and deterministic auto-cancel
/// use the same path) and spike-owned cleanup. Output always goes to the spike `outputs/` directory.
/// ADR-044: there is no remux / rewrap mode — a non-QuickTime source never reaches this class.
final class Phase6SpikeConverter {
    let source: URL
    let output: URL
    let cancellation: Phase6SpikeCancellationToken
    /// Deterministic cancellation test mode: nil = OFF (normal conversion, no extra work).
    let autoCancelThreshold: Double?
    let onProgress: @Sendable (Phase6SpikeProgress) -> Void

    init(source: URL, output: URL, cancellation: Phase6SpikeCancellationToken, autoCancelThreshold: Double? = nil, onProgress: @escaping @Sendable (Phase6SpikeProgress) -> Void) {
        self.source = source; self.output = output; self.cancellation = cancellation; self.autoCancelThreshold = autoCancelThreshold; self.onProgress = onProgress
    }

    /// Removes a partial / stale output if present. Idempotent: a missing file is a success.
    static func cleanupPartialOutput(at url: URL) -> (existed: Bool, succeeded: Bool, error: Error?) {
        let existed = FileManager.default.fileExists(atPath: url.path)
        guard existed else { return (false, true, nil) }
        do { try FileManager.default.removeItem(at: url); return (true, true, nil) } catch { return (true, false, error) }
    }

    private func throwIfCancelled() throws {
        if cancellation.isCancelled || Task.isCancelled { throw CancellationError() }
    }

    func run() async -> Phase6SpikeResult {
        var result = Phase6SpikeResult(mode: "H.264 709 normalization", outputURL: output)
        result.autoCancelThreshold = autoCancelThreshold
        if let autoCancelThreshold { result.notes.append(String(format: "DETERMINISTIC CANCELLATION TEST: auto-cancel armed at progress >= %.2f via the shared cancellation token (same path as the manual 취소 button)", autoCancelThreshold)) }
        result.sourceBytes = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let sourceModificationBefore = try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        result.sourceModificationBefore = sourceModificationBefore
        result.thermalBefore = ProcessInfo.processInfo.thermalState
        result.footprintBefore = Phase6SpikeMetrics.footprintBytes()
        result.capacityBefore = Phase6SpikeMetrics.freeCapacityBytes(at: output.deletingLastPathComponent())
        result.capacityMinimumDuring = result.capacityBefore
        result.thermalPeak = result.thermalBefore; result.footprintPeak = result.footprintBefore
        try? FileManager.default.removeItem(at: output)
        let start = Date()
        var reader: AVAssetReader?
        var writer: AVAssetWriter?
        do {
            let asset = AVURLAsset(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let videoTrack = videoTracks.first else { throw Phase6SpikeError.noVideoTrack }
            let (duration, natural, transform, fps, minFD) = try await videoTrack.load(.timeRange, .naturalSize, .preferredTransform, .nominalFrameRate, .minFrameDuration)
            let r = try AVAssetReader(asset: asset)
            let w = try AVAssetWriter(outputURL: output, fileType: .mov)
            w.shouldOptimizeForNetworkUse = false
            reader = r; writer = w

            let videoOutput: AVAssetReaderOutput
            let videoInput: AVAssetWriterInput
            let presented = natural.applying(transform)
            let presentation = CGSize(width: abs(presented.width), height: abs(presented.height))
            let raster = Phase6SpikeRaster.boundingBox(forPresentation: presentation)
            let composition = AVMutableVideoComposition()
            composition.renderSize = raster
            let ceiling = CMTime(value: 1, timescale: 30)
            composition.frameDuration = (fps > 30.5 || !minFD.isNumeric || minFD.seconds <= 0) ? ceiling : (CMTimeCompare(minFD, ceiling) < 0 ? ceiling : minFD)
            composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
            composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: duration.duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            // Bake the presentation transform, move into positive space, then scale to the bounding box.
            let bounds = CGRect(origin: .zero, size: natural).applying(transform)
            var matrix = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            matrix = matrix.concatenating(CGAffineTransform(scaleX: raster.width / presentation.width, y: raster.height / presentation.height))
            layer.setTransform(matrix, at: .zero)
            instruction.layerInstructions = [layer]
            composition.instructions = [instruction]
            let out = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
            out.videoComposition = composition
            videoOutput = out
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(raster.width), AVVideoHeightKey: Int(raster.height),
                AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
                AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoAverageBitRateKey: 10_000_000, AVVideoExpectedSourceFrameRateKey: 30],
            ]
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            videoInput.transform = .identity
            result.notes.append("raster \(Int(raster.width))×\(Int(raster.height)) from presentation \(Int(presentation.width))×\(Int(presentation.height)); frameDuration \(composition.frameDuration.value)/\(composition.frameDuration.timescale)")
            result.notes.append("TONE-MAPPING MECHANISM: AVMutableVideoComposition colorPrimaries/TransferFunction/YCbCrMatrix = ITU_R_709_2 makes AVFoundation's built-in video compositor (AVAssetReaderVideoCompositionOutput) render each frame into the 709 SDR working color space, delivering 8-bit 420 video-range CVPixelBuffers (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) — this is where HLG/PQ/Rec.2020 → SDR conversion happens; AVAssetWriterInput AVVideoColorPropertiesKey 709/709/709 tags the H.264 output (and would convert if buffer attachments differed). Output tags/metadata are verifiable via public APIs; tone-curve QUALITY is not, hence the on-device A/B visual check.")
            videoInput.expectsMediaDataInRealTime = false
            r.add(videoOutput); w.add(videoInput)

            var audioOutput: AVAssetReaderTrackOutput?
            var audioInput: AVAssetWriterInput?
            if let audioTrack = audioTracks.first {
                let fd = try await audioTrack.load(.formatDescriptions).first
                let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: fd)
                input.expectsMediaDataInRealTime = false
                r.add(out); w.add(input)
                audioOutput = out; audioInput = input
                result.notes.append("audio passthrough (\(fd.map { Phase6SpikeFormat.fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "?"))")
            }

            try throwIfCancelled()
            guard w.startWriting() else { throw w.error ?? Phase6SpikeError.writerStartFailed }
            guard r.startReading() else { throw r.error ?? Phase6SpikeError.readerStartFailed }
            w.startSession(atSourceTime: .zero)

            let total = duration.duration.seconds
            var videoDone = false, audioDone = audioOutput == nil
            var lastPoll = Date.distantPast
            var autoCancelFired = false
            var progress = Phase6SpikeProgress(stage: "normalizing")
            while !(videoDone && audioDone) {
                try throwIfCancelled()
                if !videoDone {
                    if videoInput.isReadyForMoreMediaData {
                        if let sb = videoOutput.copyNextSampleBuffer() {
                            if !videoInput.append(sb) { throw w.error ?? Phase6SpikeError.appendFailed }
                            result.videoSamples += 1
                            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
                            if total > 0 { progress.fraction = min(1, pts.seconds / total) }
                            // Deterministic cancellation: first sample at/above the threshold requests
                            // cancellation through the SAME token the manual button uses.
                            if Phase6SpikeAutoCancel.shouldFire(threshold: autoCancelThreshold, progress: progress.fraction, alreadyFired: autoCancelFired) {
                                autoCancelFired = true
                                cancellation.requestCancel(source: .automatic, progress: progress.fraction)
                                result.notes.append(String(format: "auto-cancel requested at progress %.3f after %d video samples (%.3f s elapsed)", progress.fraction, result.videoSamples, Date().timeIntervalSince(start)))
                                onProgress(progress)
                                try throwIfCancelled()
                            }
                        } else { videoInput.markAsFinished(); videoDone = true }
                    }
                }
                if !audioDone, let audioOutput, let audioInput {
                    if audioInput.isReadyForMoreMediaData {
                        if let sb = audioOutput.copyNextSampleBuffer() {
                            if !audioInput.append(sb) { throw w.error ?? Phase6SpikeError.appendFailed }
                            result.audioSamples += 1
                        } else { audioInput.markAsFinished(); audioDone = true }
                    }
                }
                if !videoInput.isReadyForMoreMediaData && !(audioInput?.isReadyForMoreMediaData ?? true) {
                    try await Task.sleep(for: .milliseconds(2))
                }
                if Date().timeIntervalSince(lastPoll) > 0.25 {
                    lastPoll = Date()
                    progress.elapsed = Date().timeIntervalSince(start)
                    progress.thermal = ProcessInfo.processInfo.thermalState
                    progress.footprintBytes = Phase6SpikeMetrics.footprintBytes()
                    progress.freeCapacityBytes = Phase6SpikeMetrics.freeCapacityBytes(at: output.deletingLastPathComponent())
                    if progress.thermal.rawValue > result.thermalPeak.rawValue { result.thermalPeak = progress.thermal }
                    result.footprintPeak = max(result.footprintPeak, progress.footprintBytes)
                    if progress.freeCapacityBytes >= 0 { result.capacityMinimumDuring = min(result.capacityMinimumDuring, progress.freeCapacityBytes) }
                    onProgress(progress)
                }
            }
            if r.status == .failed { throw r.error ?? Phase6SpikeError.readerFailed }
            try throwIfCancelled()
            progress.stage = "finishing"; onProgress(progress)
            await w.finishWriting()
            if w.status != .completed { throw w.error ?? Phase6SpikeError.writerFailed }
            // A cancellation that raced with finishWriting must never be reported as success.
            try throwIfCancelled()
            result.succeeded = true
            progress.fraction = 1; progress.stage = "done"; onProgress(progress)
        } catch is CancellationError {
            result.cancelled = true
            result.succeeded = false
            reader?.cancelReading()
            writer?.cancelWriting()
            let cleanup = Self.cleanupPartialOutput(at: output)
            result.partialOutputExistedAfterCancel = cleanup.existed
            result.cleanupSucceeded = cleanup.succeeded
            if let error = cleanup.error { result.notes.append("cleanup error: \(error.localizedDescription)") }
            result.outputExistsAfterCleanup = FileManager.default.fileExists(atPath: output.path)
            result.notes.append("cancelled via \(cancellation.source?.rawValue ?? "task") request; partial output existed=\(cleanup.existed) removed=\(cleanup.succeeded) exists after cleanup=\(result.outputExistsAfterCleanup == true)")
        } catch {
            result.errorDescription = "\((error as NSError).domain)/\((error as NSError).code): \(error.localizedDescription)"
            reader?.cancelReading(); writer?.cancelWriting()
            try? FileManager.default.removeItem(at: output)
        }
        if result.cancelled || cancellation.isCancelled {
            result.cancellationSource = cancellation.source?.rawValue
            result.cancellationRequestedProgress = cancellation.requestedProgress
            result.cancellationRequestedAt = cancellation.requestedAt
            result.cancellationRequestCount = cancellation.requestCount
        }
        result.readerStatus = reader.map { Self.name($0.status) } ?? "n/a"
        result.writerStatus = writer.map { Self.name($0.status) } ?? "n/a"
        result.elapsed = Date().timeIntervalSince(start)
        result.thermalAfter = ProcessInfo.processInfo.thermalState
        result.footprintAfter = Phase6SpikeMetrics.footprintBytes()
        result.capacityAfter = Phase6SpikeMetrics.freeCapacityBytes(at: output.deletingLastPathComponent())
        result.outputBytes = Int64((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let sourceAfter = try? source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        result.sourceBytesAfter = Int64(sourceAfter?.fileSize ?? -1)
        result.sourceModificationAfter = sourceAfter?.contentModificationDate
        result.notes.append("source after run: \(result.sourceBytesAfter) B (before \(result.sourceBytes) B) mtime \(sourceModificationBefore.map { "\($0)" } ?? "?") → \(result.sourceModificationAfter.map { "\($0)" } ?? "?") — \(result.sourceUnchanged == true ? "unchanged" : "CHANGED")")
        return result
    }

    static func name(_ s: AVAssetReader.Status) -> String { switch s { case .unknown: return "unknown"; case .reading: return "reading"; case .completed: return "completed"; case .failed: return "failed"; case .cancelled: return "cancelled"; @unknown default: return "?" } }
    static func name(_ s: AVAssetWriter.Status) -> String { switch s { case .unknown: return "unknown"; case .writing: return "writing"; case .completed: return "completed"; case .failed: return "failed"; case .cancelled: return "cancelled"; @unknown default: return "?" } }
}

enum Phase6SpikeError: Error, LocalizedError {
    case noVideoTrack, writerStartFailed, readerStartFailed, appendFailed, readerFailed, writerFailed
    var errorDescription: String? { "\(self)" }
}
#endif
