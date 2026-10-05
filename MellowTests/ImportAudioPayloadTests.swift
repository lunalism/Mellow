import AVFoundation
import CoreMedia
import XCTest
@testable import Mellow

/// ADR-050 050-A `S_audio`: the compressed source audio payload AAC passthrough copies, measured on the
/// track and sample scope the normalizer reads, plus the pure plan → estimator-audio mapping.
///
/// Byte accounting uses synthetic compressed packets of known sizes written as stored samples (passthrough
/// writer input), so the expected total is independent of the measurement. Files live in a temporary root;
/// no private media and no app store are touched.
final class ImportAudioPayloadTests: XCTestCase {
    private var root: URL!
    private let inspector = AVAssetImportSourceInspector()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioPayload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    // MARK: Fixtures

    private func pcmBuffer(channels: Int, rate: Int, frames: Int) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(2 * channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                             extensions: nil, formatDescriptionOut: &format) == noErr, let format else { throw CocoaError(.fileWriteUnknown) }
        let length = frames * 2 * channels
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block) == noErr, let block,
              CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) == noErr else { throw CocoaError(.fileWriteUnknown) }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(rate)), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames, sampleTimingEntryCount: 1,
                                        sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr,
              let sample else { throw CocoaError(.fileWriteUnknown) }
        return sample
    }

    /// An encoder-made AAC file (audio only).
    private func encodedAAC(seconds: Double = 1, channels: Int = 2, rate: Int = 44_100) async throws -> URL {
        try await encoded([AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 64_000 * channels],
                          seconds: seconds, channels: channels, rate: rate)
    }

    private func encoded(_ settings: [String: Any], seconds: Double, channels: Int, rate: Int) async throws -> URL {
        let url = root.appendingPathComponent("encoded-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
        guard input.append(try pcmBuffer(channels: channels, rate: rate, frames: Int(Double(rate) * seconds))) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }

    /// Apple Lossless has no encoder priming, so passthrough stores synthetic packets exactly as written
    /// (AAC passthrough pads priming with copies of the first packet — covered by the encoder-made tests).
    private func losslessFormat() async throws -> CMAudioFormatDescription {
        let asset = AVURLAsset(url: try await encoded([AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
                                                       AVEncoderBitDepthHintKey: 16], seconds: 1, channels: 2, rate: 44_100))
        guard let track = try await asset.loadTracks(withMediaType: .audio).first,
              let format = try await track.load(.formatDescriptions).first else { throw CocoaError(.fileReadUnknown) }
        return format
    }

    /// One compressed buffer of packets with exactly the given byte sizes (contents arbitrary: passthrough
    /// stores, never decodes).
    private func packets(_ sizes: [Int], format: CMAudioFormatDescription) throws -> CMSampleBuffer {
        let total = sizes.reduce(0, +)
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: total, blockAllocator: nil, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: total, flags: 0, blockBufferOut: &block) == noErr, let block,
              CMBlockBufferFillDataBytes(with: 0x5A, blockBuffer: block, offsetIntoDestination: 0, dataLength: total) == noErr else { throw CocoaError(.fileWriteUnknown) }
        var offset: Int64 = 0
        let descriptions = sizes.map { size -> AudioStreamPacketDescription in
            defer { offset += Int64(size) }
            return AudioStreamPacketDescription(mStartOffset: offset, mVariableFramesInPacket: 0, mDataByteSize: UInt32(size))
        }
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: sizes.count,
                                                                    presentationTimeStamp: .zero, packetDescriptions: descriptions, sampleBufferOut: &sample) == noErr,
              let sample else { throw CocoaError(.fileWriteUnknown) }
        return sample
    }

    /// A `.mov` whose audio tracks store exactly the given packet sizes (one passthrough input per track).
    private func aacFormat() async throws -> CMAudioFormatDescription {
        let tracks = try await AVURLAsset(url: try await encodedAAC()).loadTracks(withMediaType: .audio)
        guard let format = try await tracks.first?.load(.formatDescriptions).first else { throw CocoaError(.fileReadUnknown) }
        return format
    }

    private func syntheticAudio(tracks: [[Int]], aac: Bool = false, videoFrames60fps: Int = 0) async throws -> URL {
        let format = aac ? try await aacFormat() : try await losslessFormat()
        let url = root.appendingPathComponent("synthetic-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = videoFrames60fps > 0 ? Self.videoInput() : nil
        if let video { writer.add(video.input) }
        let inputs = tracks.map { _ -> AVAssetWriterInput in
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            return input
        }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for (input, sizes) in zip(inputs, tracks) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard input.append(try packets(sizes, format: format)) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            input.markAsFinished()
        }
        if let video { try await Self.appendFrames(videoFrames60fps, to: video, writer: writer) }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }

    // MARK: Byte accounting

    func testMeasuresExactlyTheStoredCompressedPacketBytes() async throws {
        let sizes = (0..<40).map { 120 + ($0 * 37) % 290 }       // varied, deterministic
        let url = try await syntheticAudio(tracks: [sizes])
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(audioTracks.first)
        let measurement = try await AVAssetImportSourceInspector.measureAudioPayload(asset: asset, inspectedTrackID: track.trackID)
        let written = Int64(sizes.reduce(0, +))
        XCTAssertEqual(measurement, .combining(trackID: track.trackID, stored: .bytes(written), delivered: .bytes(written)),
                       "stored and delivered both equal the written packet sizes, independent of the measurement")
        XCTAssertEqual(measurement.sAudioBytes, written)
        let fileSize = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber).int64Value
        XCTAssertNotEqual(Int64(sizes.reduce(0, +)), fileSize, "not the whole-file size")
    }

    func testEncodedAACMatchesTheIndependentTrackTotal() async throws {
        let url = try await encodedAAC(seconds: 2)
        let facts = try await inspector.inspect(url: url)
        let encodedTracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(encodedTracks.first)
        let declared = try await track.load(.totalSampleDataLength)
        guard case .measured(let payload) = facts.audioPayload else { return XCTFail("\(facts.audioPayload)") }
        XCTAssertGreaterThan(payload.deliveredBytes, 0)
        XCTAssertEqual(payload.storedBytes, declared)
        XCTAssertEqual(payload.deliveredBytes, declared, "compressed payload, not decoded PCM (2 s of 16-bit stereo PCM would be 352,800 B)")
        XCTAssertEqual(payload.sAudioBytes, declared)
    }

    func testSeveralAudioTracksMeasureTheTrackTheNormalizerSelects() async throws {
        let first = [200, 300, 400], second = [1_000, 1_000, 1_000, 1_000]
        let url = try await syntheticAudio(tracks: [first, second])
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        let inspectedFormatTrack = try XCTUnwrap(tracks.first { $0.mediaType == .audio })          // inspector's format facts
        let selected = try await ImportAudioTrackSelection.passthroughSourceTrack(of: asset)
        let normalizerTrack = try XCTUnwrap(selected)   // normalizer
        XCTAssertEqual(tracks.filter { $0.mediaType == .audio }.count, 2)
        XCTAssertEqual(inspectedFormatTrack.trackID, normalizerTrack.trackID, "one track for facts, measurement and passthrough")
        let measurement = try await AVAssetImportSourceInspector.measureAudioPayload(asset: asset, inspectedTrackID: inspectedFormatTrack.trackID)
        XCTAssertEqual(measurement, .combining(trackID: normalizerTrack.trackID, stored: .bytes(900), delivered: .bytes(900)), "the first track only")
    }

    func testInspectionMeasuresOnlyWhereAACPassthroughIsPossible() async throws {
        let aac = try await inspector.inspect(url: try await encodedAAC(seconds: 2))
        guard case .measured = aac.audioPayload else { return XCTFail("\(aac.audioPayload)") }
        let lossless = try await inspector.inspect(url: try await syntheticAudio(tracks: [[300, 300]]))
        XCTAssertTrue(lossless.hasAudioTrack)
        XCTAssertEqual(lossless.audioPayload, .unavailable(.notMeasured), "transcoded audio is never read in full")
        let long = try await inspector.inspect(url: try await encodedAAC(seconds: 6))
        XCTAssertEqual(long.audioPayload, .unavailable(.notMeasured), "a source above the eligible maximum is never read in full")
    }

    func testMeasurementOfAMismatchedSelectionIsUnavailable() async throws {
        let url = try await syntheticAudio(tracks: [[100, 100]])
        let asset = AVURLAsset(url: url)
        let measurement = try await AVAssetImportSourceInspector.measureAudioPayload(asset: asset, inspectedTrackID: 9_999)
        XCTAssertEqual(measurement, .unavailable(.trackSelectionMismatch))
    }

    func testNoAudioTrackIsExplicitAndAnUnmeasuredValueIsNeverZero() async throws {
        let video = TestSupport.temporaryRoot("payload-video").appendingPathComponent("v.mov")
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }
        try await FixtureVideoWriter.write(to: video, seconds: 1)
        let facts = try await inspector.inspect(url: video)
        XCTAssertFalse(facts.hasAudioTrack)
        XCTAssertEqual(facts.audioPayload, .noAudioTrack)

        // Facts built without a measurement (and unreadable sources) default to "not measured".
        var built = facts
        built.audioPayload = ImportSourceFacts(
            duration: .invalid, isReadable: false, isPlayable: false, isExportable: false, hasProtectedContent: false,
            hasVideoTrack: false, hasAudioTrack: false, container: .unknown, videoCodec: .unknown,
            naturalWidth: 0, naturalHeight: 0, preferredTransform: .identity, nominalFrameRate: 0, minimumFrameDuration: nil,
            bitsPerComponent: nil, highBitDepthProfile: .unknown, fullRangeVideo: .unknown, colorPrimaries: .unknown, transferFunction: .unknown,
            ycbcrMatrix: .unknown, hasDolbyVisionConfiguration: false, ancillaryHDRMetadata: [], aperture: .unreliable, audio: nil, byteCount: 0,
            modificationDate: nil).audioPayload
        XCTAssertEqual(built.audioPayload, .unavailable(.notMeasured))
        let corrupt = root.appendingPathComponent("corrupt.mov")
        try FixtureVideoWriter.writeCorrupt(to: corrupt)
        let unreadable = try await inspector.inspect(url: corrupt)
        XCTAssertEqual(unreadable.audioPayload, .unavailable(.notMeasured))
    }

    // MARK: Accumulation, failure and cancellation

    func testAccumulatorUsesCheckedArithmetic() {
        var accumulator = ImportAudioPayloadAccumulator()
        XCTAssertNil(accumulator.add(sampleCount: 0, totalSampleSize: 0), "an empty buffer adds nothing")
        XCTAssertNil(accumulator.add(sampleCount: 3, totalSampleSize: 600))
        XCTAssertEqual(accumulator.total, 600)
        XCTAssertEqual(accumulator.add(sampleCount: 2, totalSampleSize: 0), .invalidSampleSize, "samples without a size")
        XCTAssertEqual(accumulator.add(sampleCount: 1, totalSampleSize: -1), .invalidSampleSize)
        XCTAssertEqual(accumulator.total, 600, "a rejected buffer adds nothing")

        var nearMax = ImportAudioPayloadAccumulator()
        XCTAssertNil(nearMax.add(sampleCount: 1, totalSampleSize: Int(Int64.max - 1)))
        XCTAssertEqual(nearMax.add(sampleCount: 1, totalSampleSize: 2), .arithmeticOverflow)
        XCTAssertEqual(nearMax.total, Int64.max - 1)
    }

    func testAReaderThatDoesNotCompleteIsUnavailable() throws {
        var cancelled = false
        let measurement = try AVAssetImportSourceInspector.drainAudioPayload(next: { nil }, finalStatus: { .failed }, cancelReading: { cancelled = true })
        XCTAssertEqual(measurement, .unavailable(.readingFailed))
        XCTAssertFalse(cancelled)
        let empty = try AVAssetImportSourceInspector.drainAudioPayload(next: { nil }, finalStatus: { .completed }, cancelReading: {})
        XCTAssertEqual(empty, .bytes(0), "a completed read of no samples is a real count of zero")
    }

    func testCancellationThrowsAndStopsReadingRatherThanReportingUnavailable() async throws {
        let (latch, open) = AsyncStream.makeStream(of: Void.self)
        // Runs the drain inside a task that is already cancelled; the counters stay local to that task.
        let task = Task { () -> (outcome: String, cancelReadingCalls: Int, nextCalls: Int) in
            for await _ in latch { break }
            var cancelReadingCalls = 0, nextCalls = 0
            do {
                let value = try AVAssetImportSourceInspector.drainAudioPayload(next: { nextCalls += 1; return nil },
                                                                               finalStatus: { .completed }, cancelReading: { cancelReadingCalls += 1 })
                return ("value \(value)", cancelReadingCalls, nextCalls)
            } catch is CancellationError {
                return ("cancelled", cancelReadingCalls, nextCalls)
            } catch {
                return ("error \(error)", cancelReadingCalls, nextCalls)
            }
        }
        task.cancel()
        open.yield(); open.finish()
        let result = await task.value
        XCTAssertEqual(result.outcome, "cancelled", "cancellation is not an unavailable measurement")
        XCTAssertEqual(result.cancelReadingCalls, 1, "reading stopped")
        XCTAssertEqual(result.nextCalls, 0)
    }

    /// Cancellation before the inspection starts; cancellation DURING the read is covered by
    /// `testCancellationThrowsAndStopsReadingRatherThanReportingUnavailable` (the drain loop itself).
    func testInspectionCancelledBeforeItStartsThrows() async throws {
        let url = try await syntheticAudio(tracks: [[300, 300]])
        let (latch, open) = AsyncStream.makeStream(of: Void.self)
        let inspector = self.inspector
        let task = Task {
            for await _ in latch { break }
            return try await inspector.inspect(url: url)
        }
        task.cancel()
        open.yield(); open.finish()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
    }

    // MARK: S_audio = max(stored, delivered) (OA-4 clarification 2026-10-05)

    func testSAudioIsTheMaximumOfStoredAndDelivered() {
        let readerLarger = ImportAudioPayloadMeasurement.combining(trackID: 3, stored: .bytes(1_000), delivered: .bytes(1_120))
        XCTAssertEqual(readerLarger.sAudioBytes, 1_120)
        let storedLarger = ImportAudioPayloadMeasurement.combining(trackID: 3, stored: .bytes(21_320), delivered: .bytes(21_080))
        XCTAssertEqual(storedLarger.sAudioBytes, 21_320)
        let equal = ImportAudioPayloadMeasurement.combining(trackID: 3, stored: .bytes(500), delivered: .bytes(500))
        XCTAssertEqual(equal.sAudioBytes, 500)
        guard case .measured(let payload) = storedLarger else { return XCTFail("\(storedLarger)") }
        XCTAssertEqual(payload.trackID, 3)
        XCTAssertEqual(payload.storedBytes, 21_320); XCTAssertEqual(payload.deliveredBytes, 21_080)
    }

    func testEitherCountUnavailableOrInvalidMakesSAudioUnavailable() {
        XCTAssertEqual(ImportAudioPayloadMeasurement.combining(trackID: 1, stored: .unavailable(.storedSizeUnavailable), delivered: .bytes(900)),
                       .unavailable(.storedSizeUnavailable), "no fallback to the delivered count")
        XCTAssertEqual(ImportAudioPayloadMeasurement.combining(trackID: 1, stored: .bytes(900), delivered: .unavailable(.readingFailed)),
                       .unavailable(.readingFailed), "no fallback to the stored count")
        XCTAssertEqual(ImportAudioPayloadMeasurement.combining(trackID: 1, stored: .bytes(900), delivered: .unavailable(.arithmeticOverflow)),
                       .unavailable(.arithmeticOverflow), "an overflowing delivered sum is unavailable")
        XCTAssertEqual(ImportAudioPayloadMeasurement.combining(trackID: 1, stored: .bytes(-1), delivered: .bytes(900)), .unavailable(.invalidStoredSize))
        XCTAssertEqual(ImportAudioPayloadMeasurement.combining(trackID: 1, stored: .bytes(900), delivered: .bytes(-1)), .unavailable(.invalidSampleSize))
        XCTAssertEqual(ImportAudioPayloadMeasurement.combining(trackID: 1, stored: .unavailable(.storedSizeUnavailable), delivered: .unavailable(.readingFailed)),
                       .unavailable(.storedSizeUnavailable))
        XCTAssertEqual(ImportAudioPayloadMeasurement.combining(trackID: 1, stored: .bytes(0), delivered: .bytes(900)), .unavailable(.contradictoryCounts),
                       "a zero stored size never lets the delivered count stand alone")
        XCTAssertEqual(ImportAudioPayloadMeasurement.combining(trackID: 1, stored: .bytes(900), delivered: .bytes(0)), .unavailable(.contradictoryCounts),
                       "an empty read never lets the stored count stand alone")
        XCTAssertEqual(ImportAudioPayloadMeasurement.combining(trackID: 1, stored: .bytes(0), delivered: .bytes(0)).sAudioBytes, 0, "both empty: a valid zero")
        for unavailable: ImportAudioPayloadMeasurement in [.unavailable(.storedSizeUnavailable), .unavailable(.invalidStoredSize), .noAudioTrack] {
            XCTAssertNil(unavailable.sAudioBytes, "never zero")
        }
    }

    // MARK: Plan → estimator audio (pure)

    func testMappingFollowsThePlanNotTheSourceFormat() throws {
        let measured = ImportAudioPayloadMeasurement.combining(trackID: 2, stored: .bytes(12_000), delivered: .bytes(12_345))
        XCTAssertEqual(try ImportStorageEstimator.outputAudio(for: .none, sourcePayload: measured), ImportOutputAudioEstimate.none)
        XCTAssertEqual(try ImportStorageEstimator.outputAudio(for: .none, sourcePayload: .unavailable(.readingFailed)), ImportOutputAudioEstimate.none,
                       "no output audio needs no payload")
        XCTAssertEqual(try ImportStorageEstimator.outputAudio(for: .passthroughAAC, sourcePayload: measured), .passthrough(sourcePayloadBytes: 12_345))
        XCTAssertEqual(try ImportStorageEstimator.outputAudio(for: .passthroughAAC, sourcePayload: .combining(trackID: 2, stored: .bytes(0), delivered: .bytes(0))),
                       .passthrough(sourcePayloadBytes: 0))
        let transcode = WorkingMediaAudioStrategy.transcode(try XCTUnwrap(SDRWorkingMediaContract.canonical.audioTranscodeSettings(sourceChannelCount: 2)))
        XCTAssertEqual(try ImportStorageEstimator.outputAudio(for: transcode, sourcePayload: measured), .transcode, "transcode never uses S_audio")
        XCTAssertEqual(try ImportStorageEstimator.outputAudio(for: transcode, sourcePayload: .unavailable(.notMeasured)), .transcode)
    }

    func testPassthroughWithoutAMeasurementFailsClosed() {
        for payload: ImportAudioPayloadMeasurement in [.noAudioTrack, .unavailable(.notMeasured), .unavailable(.readingFailed),
                                                       .unavailable(.arithmeticOverflow), .unavailable(.trackSelectionMismatch)] {
            XCTAssertThrowsError(try ImportStorageEstimator.outputAudio(for: .passthroughAAC, sourcePayload: payload)) { error in
                XCTAssertEqual(error as? ImportStorageEstimateError, .sourceAudioPayloadUnavailable, "\(payload)")
            }
        }
        XCTAssertThrowsError(try ImportStorageEstimator.outputAudio(for: .passthroughAAC, sourcePayload: .combining(trackID: 1, stored: .bytes(-1), delivered: .bytes(10)))) { error in
            XCTAssertEqual(error as? ImportStorageEstimateError, .sourceAudioPayloadUnavailable, "an invalid count is unavailable, not a fallback")
        }
    }

    func testMappedPassthroughFeedsTheAcceptedFormulaExactly() throws {
        let duration = try MediaTime(value: 2722, timescale: 600)
        // The selected maximum (stored 98,765 > delivered 97,000) feeds the formula, nothing else.
        let audio = try ImportStorageEstimator.outputAudio(for: .passthroughAAC, sourcePayload: .combining(trackID: 2, stored: .bytes(98_765), delivered: .bytes(97_000)))
        let estimate = try ImportStorageEstimator.normalizedOutput(sourceDuration: duration, audio: audio)
        let silent = try ImportStorageEstimator.normalizedOutput(sourceDuration: duration, audio: .none)
        XCTAssertEqual(estimate.audioBytes, 98_765)
        XCTAssertEqual(estimate.totalBytes - silent.totalBytes, 98_765, "E_norm = V + S_audio + C_out (050-A)")
    }

    // MARK: Passthrough copies exactly the measured payload

    private static func videoInput() -> (input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 540, AVVideoHeightKey: 960])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 540, kCVPixelBufferHeightKey as String: 960])
        return (input, adaptor)
    }

    /// 60 fps frames (a normalization reason), after the audio inputs were written whole.
    private static func appendFrames(_ count: Int, to video: (input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor), writer: AVAssetWriter) async throws {
        for index in 0..<count {
            while !video.input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            guard let pool = video.adaptor.pixelBufferPool else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer, video.adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 60)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        video.input.markAsFinished()
    }

    /// 1.2 s of 60 fps video plus one encoder-made AAC track per entry (PCM frame count at 48 kHz), in order.
    private func normalizationSource(aacFrames: [Int]) async throws -> URL {
        let url = root.appendingPathComponent("av-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = Self.videoInput()
        writer.add(video.input)
        let audio = aacFrames.map { _ -> AVAssetWriterInput in
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            return input
        }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for (input, frames) in zip(audio, aacFrames) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard input.append(try pcmBuffer(channels: 2, rate: 48_000, frames: frames)) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            input.markAsFinished()
        }
        try await Self.appendFrames(72, to: video, writer: writer)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }

    private func normalize(_ url: URL) async throws -> (facts: ImportSourceFacts, plan: WorkingMediaNormalizationPlan, output: URL) {
        let facts = try await inspector.inspect(url: url)
        guard case .normalizationRequired(let reasons, let renderPath, let duration) = ImportPreflightClassifier.classify(facts) else {
            XCTFail("fixture must need normalization: \(ImportPreflightClassifier.classify(facts))")
            throw CocoaError(.featureUnsupported)
        }
        let plan = try WorkingMediaPlanBuilder.plan(preparationPath: ImportPreparationPath(reasons: reasons, renderPath: renderPath), facts: facts, sourceDuration: duration)
        let destination = root.appendingPathComponent("out-\(UUID().uuidString).mov")
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: url, destinationURL: destination, plan: plan)
        return (facts, plan, result.destinationURL)
    }

    private func storedAudioBytes(_ url: URL, track index: Int = 0) async throws -> Int64 {
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        return try await tracks[index].load(.totalSampleDataLength)
    }

    func testNormalizedPassthroughOutputCarriesTheMeasuredSourcePayload() async throws {
        let (facts, plan, output) = try await normalize(try await normalizationSource(aacFrames: [57_600]))
        XCTAssertEqual(plan.audio, .passthroughAAC)
        let sourceBytes = try XCTUnwrap(facts.audioPayload.sAudioBytes)
        XCTAssertEqual(try ImportStorageEstimator.outputAudio(for: plan.audio, sourcePayload: facts.audioPayload), .passthrough(sourcePayloadBytes: sourceBytes))
        let outputBytes = try await storedAudioBytes(output)
        XCTAssertEqual(outputBytes, sourceBytes, "for this encoder-made source passthrough stores exactly S_audio")
    }

    func testTwoAudioTracksPassThroughTheMeasuredFirstTrackOnly() async throws {
        let source = try await normalizationSource(aacFrames: [57_600, 28_800])
        let first = try await storedAudioBytes(source, track: 0), second = try await storedAudioBytes(source, track: 1)
        XCTAssertNotEqual(first, second, "the two tracks are distinguishable by size")
        let (facts, plan, output) = try await normalize(source)
        XCTAssertEqual(plan.audio, .passthroughAAC)
        let selected = try await ImportAudioTrackSelection.passthroughSourceTrack(of: AVURLAsset(url: source))
        guard case .measured(let payload) = facts.audioPayload else { return XCTFail("\(facts.audioPayload)") }
        XCTAssertEqual(payload.trackID, try XCTUnwrap(selected).trackID)
        XCTAssertEqual(payload.storedBytes, first, "both counts describe the first track")
        XCTAssertEqual(payload.deliveredBytes, first)
        XCTAssertEqual(payload.sAudioBytes, first)
        let outputTracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .audio)
        XCTAssertEqual(outputTracks.count, 1)
        let outputBytes = try await storedAudioBytes(output)
        XCTAssertEqual(outputBytes, first, "the normalizer passed through the measured track, not the other one")
    }

    /// Characterization behind the OA-4 byte-scope clarification (2026-10-05). Synthetic AAC packets written
    /// without priming information: the writer pads priming with copies of the first packet, the passthrough
    /// read delivers fewer bytes than are stored, and the normalizer's writer pads again. Independently
    /// observed (iOS 26 simulator): written 20,960 B, source stored 21,320 B, delivered 21,080 B, output stored
    /// 21,320 B. With S_audio = max(stored, delivered) the estimate input is 21,320 B. Only 20,960 is input; the
    /// other totals are OS-specific AVFoundation behaviour — a mismatch means that behaviour changed, so re-check
    /// the OA-4 evidence rather than treating it as a regression in the measurement.
    func testSyntheticAACPrimingCharacterization() async throws {
        let sizes = (0..<80).map { 120 + ($0 * 37) % 290 }
        let source = try await syntheticAudio(tracks: [sizes], aac: true, videoFrames60fps: 120)
        let (facts, plan, output) = try await normalize(source)
        XCTAssertEqual(plan.audio, .passthroughAAC)
        guard case .measured(let payload) = facts.audioPayload else { return XCTFail("\(facts.audioPayload)") }
        let sourceStored = try await storedAudioBytes(source), outputStored = try await storedAudioBytes(output)
        let record = "written=\(sizes.reduce(0, +)) sourceStored=\(sourceStored) delivered=\(payload.deliveredBytes) outputStored=\(outputStored) sAudio=\(payload.sAudioBytes)"
        add(XCTAttachment(string: record))
        print("S_audio characterization: \(record)")
        XCTAssertEqual(sizes.reduce(0, +), 20_960, record)
        XCTAssertEqual(sourceStored, 21_320, record)
        XCTAssertEqual(payload.storedBytes, sourceStored, record)
        XCTAssertEqual(payload.deliveredBytes, 21_080, record)
        XCTAssertEqual(outputStored, 21_320, record)
        XCTAssertEqual(payload.sAudioBytes, 21_320, record)
        let mapped = try ImportStorageEstimator.outputAudio(for: plan.audio, sourcePayload: facts.audioPayload)
        XCTAssertEqual(mapped, .passthrough(sourcePayloadBytes: 21_320))
    }
}
