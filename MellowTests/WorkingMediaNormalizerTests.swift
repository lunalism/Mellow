import AVFoundation
import CoreMedia
import CryptoKit
import VideoToolbox
import XCTest
@testable import Mellow

/// Phase 6 Step 4B tests: the real AVFoundation normalizer over fixtures generated here with
/// AVAssetWriter in the test host's temporary root (SDR H.264, 10-bit HEVC tagged HLG / PQ, AAC and
/// LPCM audio), plus pure validator and configuration tests. No Photos, no user media, no
/// repository media. Cancellation is driven deterministically through the stage hooks.
final class WorkingMediaNormalizerTests: XCTestCase {
    private var root: URL!
    private var sourceDir: URL!
    private var workDir: URL!
    private let inspector = AVAssetImportSourceInspector()

    override func setUpWithError() throws {
        root = TestSupport.temporaryRoot("normalizer")
        sourceDir = root.appendingPathComponent("sources", isDirectory: true)
        workDir = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    // MARK: - Fixtures

    enum VideoKind { case sdrH264, hevcHLG, hevcPQ }
    enum AudioKind: Equatable { case none, aac(channels: Int, rate: Int), lpcm(channels: Int, rate: Int) }

    struct Fixture {
        var width = 1080, height = 1920
        var transform: CGAffineTransform = .identity
        var frames = 36
        var frameDuration = CMTime(value: 20, timescale: 600)   // 30 fps → 1.2 s
        var video: VideoKind = .sdrH264
        var audio: AudioKind = .none
        /// Ends the fixture's session here (a duration that need not be frame-aligned).
        var endTime: CMTime?
        /// Explicit PCM frame count (default: the video length).
        var audioFrames: Int?
        /// One sine frequency per channel (Hz); nil writes silence.
        var tones: [Double]?
        /// `.edges`: bright 3-px border on all four sides, a 3-px vertical line at x = 270 and a
        /// vertical luminance gradient inside (render-geometry evidence). Default: corner marker.
        var pattern: Pattern = .marker
        /// Pixel aspect ratio (presentation metadata). H.264 cannot encode an odd edge, but a
        /// 1920×1080 encode with a 1919:1920 pixel aspect presents as 1919×1080 — a genuine odd
        /// presentation raster — and rotated 90° it is a 1080×1919 portrait.
        var pixelAspect: (horizontal: Int, vertical: Int)?
        /// Clean aperture in encoded-raster pixels (top-left origin). Its centre offset from the
        /// raster centre is what the file stores, so a half-pixel origin (e.g. 1919 rows centred in
        /// 1920) is representable.
        var cleanAperture: CGRect?
        /// 10-bit luma codes of the HDR fixtures' marker block and background (video range, 64–940).
        var tenBitLevels: (marker: UInt16, background: UInt16) = (900, 120)
        /// Explicit presentation time of each frame (overrides `frames` × `frameDuration`), e.g. the
        /// timing jitter of a real camera file.
        var presentationTimes: [CMTime]?
        /// Video media and movie timescale (e.g. 30000 so 1001/30000 frame times and the duration are
        /// stored exactly).
        var mediaTimeScale: CMTimeScale?
        /// Append each frame as a sample buffer carrying `frameDuration` explicitly (the pixel
        /// buffer adaptor gives the writer no duration, so a lone frame's duration is inferred).
        var explicitFrameDurations = false
    }

    /// `.aperture` (render-geometry evidence for a clean aperture, see `paintAperture`).
    /// `.frameLevel`: a flat frame whose level identifies the frame index (see `frameLevel`).
    enum Pattern { case marker, edges, aperture, frameLevel }

    /// `.frameLevel` 8-bit grey of SDR frame `index` (adjacent frames differ by 5 codes).
    private static func sdrFrameLevel(_ index: Int) -> Int { 40 + 5 * index }
    /// `.frameLevel` 10-bit luma of HDR frame `index` (adjacent frames differ by 16 codes).
    private static func hdrFrameLevel(_ index: Int) -> UInt16 { UInt16(120 + 16 * index) }

    private static let rotate90 = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)  // natural 1920×1080 → 1080×1920
    private static let mirrorX = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1080, ty: 0)    // natural 1080×1920, mirrored

    /// The marker is a bright block in the natural raster's top-left (`width/4 × height/8`).
    private static func markerRect(_ f: Fixture) -> CGRect { CGRect(x: 0, y: 0, width: f.width / 4, height: f.height / 8) }

    private static func layoutTag(_ channels: Int) -> AudioChannelLayoutTag {
        switch channels {
        case 1: return kAudioChannelLayoutTag_Mono
        case 2: return kAudioChannelLayoutTag_Stereo
        default: return kAudioChannelLayoutTag_MPEG_5_1_A
        }
    }

    private func write(_ f: Fixture) async throws -> URL {
        let url = sourceDir.appendingPathComponent("source-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var settings: [String: Any] = [AVVideoWidthKey: f.width, AVVideoHeightKey: f.height]
        let pixelFormat: OSType
        switch f.video {
        case .sdrH264:
            settings[AVVideoCodecKey] = AVVideoCodecType.h264
            settings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
            pixelFormat = kCVPixelFormatType_32BGRA
        case .hevcHLG, .hevcPQ:
            settings[AVVideoCodecKey] = AVVideoCodecType.hevc
            settings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: f.video == .hevcHLG ? AVVideoTransferFunction_ITU_R_2100_HLG : AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]
            settings[AVVideoCompressionPropertiesKey] = [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String]
            pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        }
        if let aspect = f.pixelAspect {
            settings[AVVideoPixelAspectRatioKey] = [
                AVVideoPixelAspectRatioHorizontalSpacingKey: aspect.horizontal, AVVideoPixelAspectRatioVerticalSpacingKey: aspect.vertical]
        }
        if let aperture = f.cleanAperture {
            settings[AVVideoCleanApertureKey] = [
                AVVideoCleanApertureWidthKey: aperture.width, AVVideoCleanApertureHeightKey: aperture.height,
                AVVideoCleanApertureHorizontalOffsetKey: aperture.midX - CGFloat(f.width) / 2,
                AVVideoCleanApertureVerticalOffsetKey: aperture.midY - CGFloat(f.height) / 2]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        input.transform = f.transform
        if let scale = f.mediaTimeScale {
            input.mediaTimeScale = scale
            writer.movieTimeScale = scale
        }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: f.width, kCVPixelBufferHeightKey as String: f.height])
        writer.add(input)

        var audioInput: AVAssetWriterInput?
        var channels = 0, rate = 0
        switch f.audio {
        case .none: break
        case .aac(let c, let r), .lpcm(let c, let r):
            channels = c; rate = r
            let layout = AVFoundationWorkingMediaNormalizer.channelLayoutData(Self.layoutTag(c))
            var audioSettings: [String: Any] = [AVSampleRateKey: r, AVNumberOfChannelsKey: c, AVChannelLayoutKey: layout]
            if case .aac = f.audio {
                audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
                audioSettings[AVEncoderBitRateKey] = 64_000 * c
            } else {
                audioSettings[AVFormatIDKey] = kAudioFormatLinearPCM
                audioSettings[AVLinearPCMBitDepthKey] = 16
                audioSettings[AVLinearPCMIsFloatKey] = false
                audioSettings[AVLinearPCMIsBigEndianKey] = false
                audioSettings[AVLinearPCMIsNonInterleaved] = false
            }
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            a.expectsMediaDataInRealTime = false
            writer.add(a)
            audioInput = a
        }

        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        // Whole audio first (one buffer, then finished) so interleaving never waits on it.
        if let audioInput {
            let seconds = CMTimeMultiply(f.frameDuration, multiplier: Int32(f.frames)).seconds
            let sample = try Self.pcm(channels: channels, rate: rate, frames: f.audioFrames ?? Int(Double(rate) * seconds), tones: f.tones)
            while !audioInput.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard audioInput.append(sample) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            audioInput.markAsFinished()
        }
        for index in 0..<(f.presentationTimes?.count ?? f.frames) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let pixelBuffer = buffer else { throw CocoaError(.fileWriteUnknown) }
            Self.paint(pixelBuffer, fixture: f, index: index)
            let time = f.presentationTimes?[index] ?? CMTimeMultiply(f.frameDuration, multiplier: Int32(index))
            if f.explicitFrameDurations {
                var format: CMVideoFormatDescription?
                var timing = CMSampleTimingInfo(duration: f.frameDuration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
                var sample: CMSampleBuffer?
                guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &format) == noErr,
                      let format, CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: format,
                                                                            sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
                      let sample, input.append(sample) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                continue
            }
            guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        if let endTime = f.endTime { writer.endSession(atSourceTime: endTime) }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }

    /// Dark frame with a bright marker block in the natural top-left.
    private static func paint(_ buffer: CVPixelBuffer, fixture f: Fixture, index: Int = 0) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let marker = markerRect(f)
        if CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA {
            let base = CVPixelBufferGetBaseAddress(buffer)!, bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<f.height {
                let line = base.advanced(by: row * bytesPerRow)
                switch f.pattern {
                case .marker:
                    memset(line, 0x30, f.width * 4)
                    if row < Int(marker.maxY) { memset(line, 0xF0, Int(marker.maxX) * 4) }
                case .edges:
                    if row < 3 || row >= f.height - 3 {
                        memset(line, 0xF0, f.width * 4)
                    } else {
                        memset(line, Int32(Self.gradient(row: row, height: f.height)), f.width * 4)
                        memset(line, 0xF0, 3 * 4)
                        memset(line.advanced(by: (f.width - 3) * 4), 0xF0, 3 * 4)
                        memset(line.advanced(by: 270 * 4), 0xF0, 3 * 4)
                    }
                case .aperture:
                    Self.paintAperture(line.assumingMemoryBound(to: UInt8.self), row: row, fixture: f)
                case .frameLevel:
                    memset(line, Int32(Self.sdrFrameLevel(index)), f.width * 4)
                }
            }
        } else {
            // 10-bit 4:2:0 video range, values in the high bits of 16-bit words.
            let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!, lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            for row in 0..<f.height {
                let line = luma.advanced(by: row * lumaRow).assumingMemoryBound(to: UInt16.self)
                for column in 0..<f.width {
                    if f.pattern == .frameLevel { line[column] = Self.hdrFrameLevel(index) << 6; continue }
                    line[column] = (row < Int(marker.maxY) && column < Int(marker.maxX) ? f.tenBitLevels.marker : f.tenBitLevels.background) << 6
                }
            }
            let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!, chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            for row in 0..<CVPixelBufferGetHeightOfPlane(buffer, 1) {
                let line = chroma.advanced(by: row * chromaRow).assumingMemoryBound(to: UInt16.self)
                for index in 0..<(CVPixelBufferGetWidthOfPlane(buffer, 1) * 2) { line[index] = 512 << 6 }
            }
        }
    }

    /// `.aperture` pattern, one encoded row. Outside the clean aperture: saturated green (never
    /// black, never grey, so leaked raster is identifiable). Inside, in aperture-local pixels: a
    /// 4-px edge band on all four sides made of 40-px dashes alternating 240 / 176 (bright, never
    /// black, and varying along the edge, so neither padding nor a flat synthetic border passes), a
    /// grey interior gradient 40 → 120 down the aperture, a 4-px vertical line at local x 270–273
    /// and a 4-px horizontal line at local y 480–483 (column / row position markers).
    /// Pixel rows / columns that the aperture covers at all (half-pixel origins included) count
    /// as inside.
    private static func paintAperture(_ line: UnsafeMutablePointer<UInt8>, row: Int, fixture f: Fixture) {
        let aperture = f.cleanAperture ?? CGRect(x: 0, y: 0, width: f.width, height: f.height)
        let top = Int(aperture.minY.rounded(.down)), bottom = Int(aperture.maxY.rounded(.up))
        let left = Int(aperture.minX.rounded(.down)), right = Int(aperture.maxX.rounded(.up))
        for column in 0..<f.width {
            let pixel = line.advanced(by: column * 4)   // BGRA
            guard (top..<bottom).contains(row), (left..<right).contains(column) else {
                pixel[0] = 0x20; pixel[1] = 0xC0; pixel[2] = 0x20; pixel[3] = 0xFF
                continue
            }
            let x = column - left, y = row - top, w = right - left, h = bottom - top
            let value: UInt8
            if x < 4 || x >= w - 4 || y < 4 || y >= h - 4 {
                value = ((x + y) / 40) % 2 == 0 ? 240 : 176
            } else if (270..<274).contains(x) || (480..<484).contains(y) {
                value = 240
            } else {
                value = UInt8(gradient(row: y, height: h))
            }
            pixel[0] = value; pixel[1] = value; pixel[2] = value; pixel[3] = 0xFF
        }
    }

    /// Interior luminance of the `.edges` pattern: 40 at the top rising to 120 at the bottom.
    private static func gradient(row: Int, height: Int) -> Int { 40 + row * 80 / height }

    /// Interleaved 16-bit PCM: silence, or one sine per channel at 0.1 full scale (no clipping
    /// even when a downmix sums several channels).
    private static func pcm(channels: Int, rate: Int, frames: Int, tones: [Double]?) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(2 * channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = layoutTag(channels)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: MemoryLayout<AudioChannelLayout>.size, layout: &layout,
                                             magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr else {
            throw CocoaError(.fileWriteUnknown)
        }
        let length = frames * 2 * channels
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
                                           offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block)
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: length)
        if let tones {
            var samples = [Int16](repeating: 0, count: frames * channels)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    let phase = 2 * Double.pi * tones[channel] * Double(frame) / Double(rate)
                    samples[frame * channels + channel] = Int16(0.1 * 32_767 * sin(phase))
                }
            }
            samples.withUnsafeBytes { raw in
                _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: length)
            }
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(rate)), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreate(allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
                             sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
        return try XCTUnwrap(sample)
    }

    // MARK: - Helpers

    /// Real Step 1–4A path: inspect → classify → build the plan.
    private func plan(for url: URL, file: StaticString = #filePath, line: UInt = #line) async throws -> WorkingMediaNormalizationPlan {
        let facts = try await inspector.inspect(url: url)
        guard case .normalizationRequired(let reasons, let renderPath, let duration) = ImportPreflightClassifier.classify(facts) else {
            XCTFail("fixture is not normalization-required: \(ImportPreflightClassifier.classify(facts))", file: file, line: line)
            throw CocoaError(.featureUnsupported)
        }
        return try WorkingMediaPlanBuilder.plan(preparationPath: ImportPreparationPath(reasons: reasons, renderPath: renderPath), facts: facts, sourceDuration: duration)
    }

    private func destination(_ name: String = "output") -> URL { workDir.appendingPathComponent("\(name)-\(UUID().uuidString).mov") }

    private struct Stamp: Equatable { let size: Int64; let modified: Date?; let sha256: String }

    private func stamp(_ url: URL) throws -> Stamp {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        return Stamp(size: (attributes[.size] as? NSNumber)?.int64Value ?? -1, modified: attributes[.modificationDate] as? Date, sha256: digest)
    }

    private func workspaceEntries() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: workDir.path)) ?? [] }

    private func expectError(_ expected: WorkingMediaNormalizationError, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Any) async {
        do { _ = try await body(); XCTFail("expected \(expected)", file: file, line: line) }
        catch let error as WorkingMediaNormalizationError { XCTAssertEqual(error, expected, file: file, line: line) }
        catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }

    private func expectCancellation(file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Any) async {
        do { _ = try await body(); XCTFail("expected cancellation", file: file, line: line) }
        catch is CancellationError {}
        catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }

    /// Mean RGB of one output pixel, sampled from the first decoded frame.
    private func frame(_ url: URL) async throws -> (width: Int, height: Int, luminance: (CGPoint) -> Double, rgb: (CGPoint) -> (r: Double, g: Double, b: Double)) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(value: 1, timescale: 10)).image
        let width = image.width, height = image.height, bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        let context = try XCTUnwrap(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data
        let rgb: (CGPoint) -> (r: Double, g: Double, b: Double) = { point in
            let x = min(max(Int(point.x), 0), width - 1), y = min(max(Int(point.y), 0), height - 1)
            let offset = y * bytesPerRow + x * 4
            return (Double(pixels[offset]), Double(pixels[offset + 1]), Double(pixels[offset + 2]))
        }
        return (width, height, { point in let c = rgb(point); return (c.r + c.g + c.b) / 3 }, rgb)
    }

    /// Where the natural-top-left marker must land in the output, per ADR-047 sizing of the plan.
    private func expectedMarkerCenter(_ f: Fixture, plan: WorkingMediaNormalizationPlan) -> CGPoint {
        let bounds = CGRect(x: 0, y: 0, width: f.width, height: f.height).applying(f.transform)
        let presented = Self.markerRect(f).applying(f.transform).offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        let sx = CGFloat(plan.raster.output.width) / CGFloat(plan.raster.presentation.width)
        let sy = CGFloat(plan.raster.output.height) / CGFloat(plan.raster.presentation.height)
        return CGPoint(x: presented.midX * sx, y: presented.midY * sy)
    }

    private func assertMarker(_ url: URL, fixture f: Fixture, plan: WorkingMediaNormalizationPlan, file: StaticString = #filePath, line: UInt = #line) async throws {
        let decoded = try await frame(url)
        XCTAssertEqual(decoded.width, plan.raster.output.width, file: file, line: line)
        XCTAssertEqual(decoded.height, plan.raster.output.height, file: file, line: line)
        let marker = expectedMarkerCenter(f, plan: plan)
        let opposite = CGPoint(x: CGFloat(decoded.width) - marker.x, y: CGFloat(decoded.height) - marker.y)
        XCTAssertGreaterThan(decoded.luminance(marker), 170, "marker missing at \(marker)", file: file, line: line)
        XCTAssertLessThan(decoded.luminance(opposite), 110, "unexpected bright content at \(opposite)", file: file, line: line)
    }

    private func assertCanonical(_ result: WorkingMediaNormalizationResult, plan: WorkingMediaNormalizationPlan, file: StaticString = #filePath, line: UInt = #line) {
        let facts = result.outputFacts
        XCTAssertEqual(facts.container, .quickTime, file: file, line: line)
        XCTAssertEqual(facts.videoCodec, .h264(fourCC: "avc1"), file: file, line: line)
        XCTAssertEqual(facts.naturalWidth, plan.raster.output.width, file: file, line: line)
        XCTAssertEqual(facts.naturalHeight, plan.raster.output.height, file: file, line: line)
        XCTAssertEqual(facts.naturalWidth % 2, 0, file: file, line: line)
        XCTAssertEqual(facts.naturalHeight % 2, 0, file: file, line: line)
        XCTAssertEqual(facts.preferredTransform, .identity, file: file, line: line)
        XCTAssertEqual(facts.presentationOrientation, .portrait, file: file, line: line)
        XCTAssertEqual(facts.colorPrimaries, .rec709, file: file, line: line)
        XCTAssertEqual(facts.transferFunction, .rec709, file: file, line: line)
        XCTAssertEqual(facts.ycbcrMatrix, .rec709, file: file, line: line)
        XCTAssertNotEqual(facts.fullRangeVideo, .yes, file: file, line: line)
        XCTAssertEqual(ImportPreflightClassifier.hdrSignals(in: facts), [], file: file, line: line)
        XCTAssertFalse(facts.hasDolbyVisionConfiguration, file: file, line: line)
        XCTAssertTrue(facts.ancillaryHDRMetadata.isEmpty, file: file, line: line)
        // ADR-048 Revision 2: the 30 fps ceiling is the planned frame duration plus the exact grid
        // below; the average / metadata rate is never asserted (a short final sample can lift it).
        XCTAssertFalse(plan.outputFrameDuration < plan.contract.minimumFrameDuration, file: file, line: line)
        XCTAssertTrue(plan.acceptedOutputDuration.contains(result.outputDuration), "\(result.outputDuration)", file: file, line: line)
        XCTAssertEqual(result.sourceDuration, plan.sourceDuration, file: file, line: line)
        XCTAssertGreaterThan(result.outputByteCount, 0, file: file, line: line)
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: facts, evidence: result.outputEvidence, plan: plan, sourceAudio: nil).filter { $0 != .audioMismatch }, [], file: file, line: line)
        // H.264 High from the output's own avcC, and a cadence proven by actual sample times.
        XCTAssertEqual(result.outputEvidence.avcProfileIndication, 100, file: file, line: line)
        guard case .times(let times) = result.outputEvidence.videoPresentationTimes else { return XCTFail("no timestamps", file: file, line: line) }
        XCTAssertFalse(times.isEmpty, file: file, line: line)   // one sample at zero is a valid grid when E <= d
        XCTAssertEqual(WorkingMediaOutputValidator.cadenceViolations(.times(times), frameDuration: plan.outputFrameDuration), [], file: file, line: line)
        // The output is canonical working media: it would itself classify as ready — except for the
        // source preflight's nominal-rate trigger, which a short final sample can lift above 30.5
        // although the grid above is exact (ADR-048 Revision 2: never an output-validity signal).
        if case .normalizationRequired(let reasons, _, _) = ImportPreflightClassifier.classify(facts) {
            let remaining = reasons.filter { if case .frameRate = $0 { return false } else { return true } }
            if !remaining.isEmpty { XCTFail("output still needs normalization: \(reasons)", file: file, line: line) }
        }
    }

    // MARK: - Entry and file safety

    func testNonFileURLsAreRejected() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let normalizer = AVFoundationWorkingMediaNormalizer()
        await expectError(.sourceNotFileURL) { try await normalizer.normalize(sourceURL: URL(string: "https://example.com/a.mov")!, destinationURL: self.destination(), plan: plan) }
        await expectError(.destinationNotFileURL) { try await normalizer.normalize(sourceURL: source, destinationURL: URL(string: "https://example.com/b.mov")!, plan: plan) }
        XCTAssertEqual(workspaceEntries(), [])
    }

    func testMissingDirectoryAndInvalidSourcesAreRejected() async throws {
        let valid = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: valid)
        let normalizer = AVFoundationWorkingMediaNormalizer()
        await expectError(.sourceMissing) { try await normalizer.normalize(sourceURL: self.sourceDir.appendingPathComponent("missing.mov"), destinationURL: self.destination(), plan: plan) }
        await expectError(.sourceNotRegularFile) { try await normalizer.normalize(sourceURL: self.sourceDir, destinationURL: self.destination(), plan: plan) }
        let garbage = sourceDir.appendingPathComponent("garbage.mov")
        try Data(repeating: 0xAB, count: 4096).write(to: garbage)
        let garbageStamp = try stamp(garbage)
        await expectError(.planDoesNotMatchSource) { try await normalizer.normalize(sourceURL: garbage, destinationURL: self.destination(), plan: plan) }
        XCTAssertEqual(try stamp(garbage), garbageStamp)
        XCTAssertEqual(workspaceEntries(), [])
    }

    func testDestinationParentMustExistAndSourceCannotBeDestination() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let before = try stamp(source)
        let normalizer = AVFoundationWorkingMediaNormalizer()
        let orphan = workDir.appendingPathComponent("missing-dir", isDirectory: true).appendingPathComponent("out.mov")
        await expectError(.destinationParentMissing) { try await normalizer.normalize(sourceURL: source, destinationURL: orphan, plan: plan) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.deletingLastPathComponent().path), "no parent directory is created")
        await expectError(.destinationIsSource) { try await normalizer.normalize(sourceURL: source, destinationURL: source, plan: plan) }
        XCTAssertEqual(try stamp(source), before)
    }

    func testPreExistingDestinationIsRefusedAndPreserved() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let existing = destination()
        try Data("keep me".utf8).write(to: existing)
        let before = try stamp(existing)
        await expectError(.destinationExists) { try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: existing, plan: plan) }
        XCTAssertEqual(try stamp(existing), before)
    }

    func testFastPathSourceIsRefused() async throws {
        let ready = try await write(Fixture())   // 1080×1920 30 fps SDR H.264, no audio → fast path
        let readyFacts = try await inspector.inspect(url: ready)
        guard case .readyFastPath = ImportPreflightClassifier.classify(readyFacts) else { return XCTFail("fixture should be fast path") }
        let other = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: other)
        await expectError(.planDoesNotMatchSource) { try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: ready, destinationURL: self.destination(), plan: plan) }
        XCTAssertEqual(workspaceEntries(), [])
    }

    // MARK: - Video end to end

    func testRotatedLandscapeNaturalSizeBecomesPortraitWithIdentityTransform() async throws {
        let f = Fixture(width: 1920, height: 1080, transform: Self.rotate90, frames: 72, frameDuration: CMTime(value: 10, timescale: 600))
        let source = try await write(f)
        let before = try stamp(source)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.raster.presentation, WorkingMediaRaster(width: 1080, height: 1920))
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        try await assertMarker(result.destinationURL, fixture: f, plan: plan)
        XCTAssertEqual(try stamp(source), before)
    }

    func testMirroredPortraitIsBakedIntoPixels() async throws {
        let f = Fixture(transform: Self.mirrorX, frames: 72, frameDuration: CMTime(value: 10, timescale: 600))
        let source = try await write(f)
        let plan = try await plan(for: source)
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        // The natural top-left marker is presented top-right once mirrored.
        try await assertMarker(result.destinationURL, fixture: f, plan: plan)
        XCTAssertGreaterThan(expectedMarkerCenter(f, plan: plan).x, CGFloat(plan.raster.output.width) / 2)
    }

    func testOversizedRasterIsScaledToThePlannedRaster() async throws {
        let f = Fixture(width: 2160, height: 3840, frames: 33)
        let source = try await write(f)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.reasons, [.raster(presentationWidth: 2160, presentationHeight: 3840)])
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        XCTAssertEqual(result.outputFacts.naturalWidth, 1080)
        XCTAssertEqual(result.outputFacts.naturalHeight, 1920)
        try await assertMarker(result.destinationURL, fixture: f, plan: plan)
    }

    func testHighFrameRateIsCappedToThePlannedCadence() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))   // 60 fps, 1.2 s
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.reasons, [.frameRate(nominal: 60)])
        XCTAssertEqual(plan.outputFrameDuration, try MediaTime(value: 1, timescale: 30))
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        XCTAssertEqual(Double(result.outputFacts.nominalFrameRate), 30, accuracy: 0.5)
    }

    func testCombinedRasterAndFrameRate() async throws {
        let f = Fixture(width: 1440, height: 2560, frames: 72, frameDuration: CMTime(value: 10, timescale: 600))
        let source = try await write(f)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.reasons, [.frameRate(nominal: 60), .raster(presentationWidth: 1440, presentationHeight: 2560)])
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        try await assertMarker(result.destinationURL, fixture: f, plan: plan)
    }

    func testNonNineSixteenAspectIsPreservedWithoutCropOrPad() async throws {
        let f = Fixture(width: 1620, height: 2160, frames: 36)
        let source = try await write(f)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.raster.output, WorkingMediaRaster(width: 1080, height: 1440))
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        XCTAssertEqual(Double(result.outputFacts.naturalWidth) / Double(result.outputFacts.naturalHeight), 1620.0 / 2160.0, accuracy: 0.002)
        try await assertMarker(result.destinationURL, fixture: f, plan: plan)
    }

    // MARK: - HDR end to end (synthetic 10-bit HEVC tagged HLG / PQ, Rec.2020)

    func testHLGTenBitHEVCBecomesSDRRec709H264() async throws {
        try await assertHDRFixtureNormalizes(.hevcHLG, transfer: .hlg)
    }

    func testPQTenBitHEVCBecomesSDRRec709H264() async throws {
        try await assertHDRFixtureNormalizes(.hevcPQ, transfer: .pq)
    }

    private func assertHDRFixtureNormalizes(_ kind: VideoKind, transfer: ImportTransferFunction, file: StaticString = #filePath, line: UInt = #line) async throws {
        let f = Fixture(frames: 36, video: kind)
        let source = try await write(f)
        let sourceFacts = try await inspector.inspect(url: source)
        XCTAssertEqual(sourceFacts.transferFunction, transfer, file: file, line: line)
        XCTAssertEqual(sourceFacts.colorPrimaries, .rec2020, file: file, line: line)
        let plan = try await plan(for: source, file: file, line: line)
        guard case .hdr(let signals) = plan.reasons.first else { return XCTFail("expected an HDR reason: \(plan.reasons)", file: file, line: line) }
        XCTAssertTrue(signals.contains(transfer == .hlg ? .hlgTransfer : .pqTransfer), file: file, line: line)
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan, file: file, line: line)
        XCTAssertNotEqual(result.outputFacts.highBitDepthProfile, .yes, file: file, line: line)
        XCTAssertLessThanOrEqual(result.outputFacts.bitsPerComponent ?? 8, 8, file: file, line: line)
        try await assertMarker(result.destinationURL, fixture: f, plan: plan, file: file, line: line)
    }

    // MARK: - Audio end to end

    func testNoAudioProducesNoAudioTrack() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.audio, .none)
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        XCTAssertFalse(result.outputFacts.hasAudioTrack)
        XCTAssertNil(result.outputFacts.audio)
    }

    func testAACIsPassedThroughUnchanged() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600), audio: .aac(channels: 2, rate: 44_100)))
        let sourceAudio = try await inspector.inspect(url: source).audio
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.audio, .passthroughAAC)
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        XCTAssertEqual(result.outputFacts.audio, sourceAudio, "passthrough keeps the exact AAC format (44.1 kHz stays 44.1 kHz)")
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: result.outputFacts, evidence: result.outputEvidence, plan: plan, sourceAudio: sourceAudio), [])
    }

    func testStereoLPCMIsTranscodedToAACLC48k() async throws {
        try await assertTranscode(sourceChannels: 2, expectedChannels: 2, expectedBitRate: 128_000)
    }

    func testMonoLPCMIsTranscodedToMonoAAC() async throws {
        try await assertTranscode(sourceChannels: 1, expectedChannels: 1, expectedBitRate: 96_000)
    }

    func testSixChannelLPCMIsDownmixedToStereoAAC() async throws {
        try await assertTranscode(sourceChannels: 6, expectedChannels: 2, expectedBitRate: 128_000)
    }

    private func assertTranscode(sourceChannels: Int, expectedChannels: Int, expectedBitRate: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        // 1080×1920 30 fps SDR: the audio is the only reason.
        let source = try await write(Fixture(audio: .lpcm(channels: sourceChannels, rate: 44_100)))
        let plan = try await plan(for: source, file: file, line: line)
        XCTAssertEqual(plan.reasons, [.audioTranscode], file: file, line: line)
        guard case .transcode(let settings) = plan.audio else { return XCTFail("expected transcode", file: file, line: line) }
        XCTAssertEqual(settings.bitRate, expectedBitRate, file: file, line: line)
        XCTAssertEqual(settings.downmixesToStereo, sourceChannels > 2, file: file, line: line)
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan, file: file, line: line)
        XCTAssertEqual(result.outputFacts.audio?.fourCC, "aac ", file: file, line: line)
        XCTAssertEqual(result.outputFacts.audio?.sampleRate, 48_000, file: file, line: line)
        XCTAssertEqual(result.outputFacts.audio?.channelCount, expectedChannels, file: file, line: line)
        // The video is re-encoded to the canonical contract even when audio is the only reason.
        XCTAssertEqual(result.outputFacts.videoCodec, .h264(fourCC: "avc1"), file: file, line: line)
    }

    // MARK: - Configuration (exact writer / reader policy)

    private func syntheticPlan(natural: (Int, Int) = (1080, 1920), transform: ImportAffineTransform = .identity, fps: Float = 60, audio: ImportAudioFacts? = nil,
                               duration: MediaTime = try! MediaTime(value: 720, timescale: 600), aperture: ImportApertureFacts? = nil) throws -> WorkingMediaNormalizationPlan {
        let facts = ImportSourceFacts(
            duration: .exact(duration), isReadable: true, isPlayable: true, isExportable: true, hasProtectedContent: false,
            hasVideoTrack: true, hasAudioTrack: audio != nil, container: .quickTime, videoCodec: .h264(fourCC: "avc1"),
            naturalWidth: natural.0, naturalHeight: natural.1, preferredTransform: transform, nominalFrameRate: fps, minimumFrameDuration: nil,
            bitsPerComponent: 8, highBitDepthProfile: .no, fullRangeVideo: .no, colorPrimaries: .rec709, transferFunction: .rec709, ycbcrMatrix: .rec709,
            hasDolbyVisionConfiguration: false, ancillaryHDRMetadata: [],
            aperture: aperture ?? .classify(encodedWidth: natural.0, encodedHeight: natural.1, cleanAperture: nil, pixelAspectRatio: nil),
            audio: audio, byteCount: 1, modificationDate: nil)
        guard case .normalizationRequired(let reasons, let renderPath, let duration) = ImportPreflightClassifier.classify(facts) else { throw CocoaError(.featureUnsupported) }
        return try WorkingMediaPlanBuilder.plan(preparationPath: ImportPreparationPath(reasons: reasons, renderPath: renderPath), facts: facts, sourceDuration: duration)
    }

    func testVideoWriterSettingsAreTheCanonicalContract() throws {
        let plan = try syntheticPlan(natural: (1620, 2160))
        let settings = AVFoundationWorkingMediaNormalizer.videoOutputSettings(for: plan)
        XCTAssertEqual(settings[AVVideoCodecKey] as? AVVideoCodecType, .h264)
        XCTAssertEqual(settings[AVVideoWidthKey] as? Int, 1080)
        XCTAssertEqual(settings[AVVideoHeightKey] as? Int, 1440)
        let color = try XCTUnwrap(settings[AVVideoColorPropertiesKey] as? [String: String])
        XCTAssertEqual(color, [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2])
        let compression = try XCTUnwrap(settings[AVVideoCompressionPropertiesKey] as? [String: String])
        XCTAssertEqual(compression[AVVideoProfileLevelKey], AVVideoProfileLevelH264HighAutoLevel)
        XCTAssertEqual(AVFoundationWorkingMediaNormalizer.compositionPixelFormat, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    }

    func testAudioTranscodeSettingsByChannelCount() throws {
        for (source, channels, bitRate, tag) in [(1, 1, 96_000, kAudioChannelLayoutTag_Mono), (2, 2, 128_000, kAudioChannelLayoutTag_Stereo), (6, 2, 128_000, kAudioChannelLayoutTag_Stereo)] {
            let settings = try XCTUnwrap(SDRWorkingMediaContract.canonical.audioTranscodeSettings(sourceChannelCount: source))
            let configuration = AVFoundationWorkingMediaNormalizer.audioTranscodeSettings(settings)
            XCTAssertEqual(configuration.reader[AVFormatIDKey] as? AudioFormatID, kAudioFormatLinearPCM)
            XCTAssertNil(configuration.reader[AVSampleRateKey], "the reader keeps the source rate; the writer converts")
            XCTAssertEqual(configuration.reader[AVNumberOfChannelsKey] as? Int, channels, "reader renders \(source) → \(channels)")
            XCTAssertEqual(configuration.writer[AVFormatIDKey] as? AudioFormatID, kAudioFormatMPEG4AAC)
            XCTAssertEqual(configuration.writer[AVSampleRateKey] as? Int, 48_000)
            XCTAssertEqual(configuration.writer[AVNumberOfChannelsKey] as? Int, channels)
            XCTAssertEqual(configuration.writer[AVEncoderBitRateKey] as? Int, bitRate)
            let layout = try XCTUnwrap(configuration.writer[AVChannelLayoutKey] as? Data)
            XCTAssertEqual(layout, AVFoundationWorkingMediaNormalizer.channelLayoutData(tag))
            XCTAssertEqual(configuration.reader[AVChannelLayoutKey] as? Data, layout)
        }
    }

    // MARK: - Render geometry (pure) and the codec-free geometry renderer (ADR-047 R1, ADR-049, F2 / F5 / F6)

    enum Orientation { case identity, rotate90, rotate180, rotate270, mirrorX, mirrorY, transpose }

    /// The track transform for `kind` on a natural raster `w × h`, as track headers carry them
    /// (rotation / mirror plus the translation that keeps the frame in positive space).
    private static func trackTransform(_ kind: Orientation, w: Double, h: Double) -> ImportAffineTransform {
        switch kind {
        case .identity: return .identity
        case .rotate90: return ImportAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        case .rotate180: return ImportAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case .rotate270: return ImportAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case .mirrorX: return ImportAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case .mirrorY: return ImportAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case .transpose: return ImportAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        }
    }

    /// One codec-free geometry case: an encoded raster, its clean aperture (nil = whole raster),
    /// pixel aspect, orientation, and the output the plan must produce.
    struct GeometryCase {
        let name: String
        let encoded: (Int, Int)
        let aperture: CGRect?
        var par: (Int, Int) = (1, 1)
        var orientation: Orientation = .identity
        /// Declared presentation scale applied after the orientation (ADR-049 R1: baked, not a
        /// Mellow stretch).
        var scale: (Double, Double) = (1, 1)
        let output: (Int, Int)
        /// Every output step spans about one source sample (no real downscale): pixel values follow
        /// a bilinear model. Otherwise only structural checks apply (downsampling filters differ).
        var nearUnitScale = true

        var apertureRect: CGRect { aperture ?? CGRect(x: 0, y: 0, width: encoded.0, height: encoded.1) }
        /// Natural (pre-transform) presentation size: the aperture with its pixel aspect applied.
        var natural: (w: Double, h: Double) { (Double(apertureRect.width) * Double(par.0) / Double(par.1), Double(apertureRect.height)) }
        var swapsAxes: Bool { [.rotate90, .rotate270, .transpose].contains(orientation) }

        /// Independent of the production matrix: the encoded-sample position an output pixel centre
        /// must sample, from hand-written inverses of each orientation.
        func sourcePoint(u: Double, v: Double) -> (x: Double, y: Double) {
            let (w, h) = natural
            let oriented = swapsAxes ? (w: h, h: w) : (w: w, h: h)
            let presentation = (w: oriented.w * scale.0, h: oriented.h * scale.1)
            // Output pixel centre → scaled presentation → unscaled oriented presentation.
            let px = (u + 0.5) * presentation.w / Double(output.0) / scale.0, py = (v + 0.5) * presentation.h / Double(output.1) / scale.1
            let n: (x: Double, y: Double)
            switch orientation {
            case .identity: n = (px, py)
            case .rotate90: n = (py, h - px)
            case .rotate180: n = (w - px, h - py)
            case .rotate270: n = (w - py, px)
            case .mirrorX: n = (w - px, py)
            case .mirrorY: n = (px, h - py)
            case .transpose: n = (py, px)
            }
            let a = apertureRect
            return (Double(a.minX) + n.x * Double(a.width) / w, Double(a.minY) + n.y)
        }
    }

    private static let geometryCases: [GeometryCase] = [
        GeometryCase(name: "1080×1919 → 1080×1918", encoded: (1080, 1919), aperture: nil, output: (1080, 1918)),
        GeometryCase(name: "2160×3842 → 1078×1920", encoded: (2160, 3842), aperture: nil, output: (1078, 1920), nearUnitScale: false),
        GeometryCase(name: "719×1279 → 718×1278", encoded: (719, 1279), aperture: nil, output: (718, 1278)),
        GeometryCase(name: "integer offset aperture", encoded: (1080, 1920), aperture: CGRect(x: 60, y: 100, width: 1000, height: 1800), output: (1000, 1800)),
        GeometryCase(name: "half-pixel centred aperture", encoded: (1080, 1920), aperture: CGRect(x: 0, y: 0.5, width: 1080, height: 1919), output: (1080, 1918)),
        GeometryCase(name: "rotated half-pixel aperture", encoded: (1920, 1080), aperture: CGRect(x: 0.5, y: 0, width: 1919, height: 1080), orientation: .rotate90, output: (1080, 1918)),
        GeometryCase(name: "mirrored offset aperture", encoded: (1080, 1920), aperture: CGRect(x: 60, y: 100, width: 1000, height: 1800), orientation: .mirrorX, output: (1000, 1800)),
        GeometryCase(name: "offset aperture, 270° rotation", encoded: (1920, 1080), aperture: CGRect(x: 100, y: 60, width: 1800, height: 1000), orientation: .rotate270, output: (1000, 1800)),
        GeometryCase(name: "offset aperture, rotation + mirror", encoded: (1920, 1080), aperture: CGRect(x: 100, y: 60, width: 1800, height: 1000), orientation: .transpose, output: (1000, 1800)),
        GeometryCase(name: "offset aperture, 180° rotation", encoded: (1080, 1920), aperture: CGRect(x: 60, y: 100, width: 1000, height: 1800), orientation: .rotate180, output: (1000, 1800)),
        GeometryCase(name: "vertical mirror", encoded: (1080, 1920), aperture: CGRect(x: 60, y: 100, width: 1000, height: 1800), orientation: .mirrorY, output: (1000, 1800)),
        GeometryCase(name: "pixel aspect 1919:1920, rotated", encoded: (1920, 1080), aperture: nil, par: (1919, 1920), orientation: .rotate90, output: (1080, 1918)),
        // A non-aligned downsampling filter's footprint reaches past the aperture edge: only reading the
        // aperture's own coverage keeps the surround out.
        // ADR-049 R1: declared axis-aligned scale is baked (uniform, non-uniform, with rotation / mirror).
        GeometryCase(name: "offset aperture, non-uniform scale 0.8 × 1", encoded: (1080, 1920), aperture: CGRect(x: 60, y: 100, width: 1000, height: 1800),
                     scale: (0.8, 1), output: (800, 1800), nearUnitScale: false),
        GeometryCase(name: "rotated offset aperture, scale 1 × 0.9", encoded: (1920, 1080), aperture: CGRect(x: 100, y: 60, width: 1800, height: 1000),
                     orientation: .rotate90, scale: (1, 0.9), output: (1000, 1620), nearUnitScale: false),
        GeometryCase(name: "mirrored offset aperture, uniform scale 0.5", encoded: (1080, 1920), aperture: CGRect(x: 60, y: 100, width: 1000, height: 1800),
                     orientation: .mirrorX, scale: (0.5, 0.5), output: (500, 900), nearUnitScale: false),
        GeometryCase(name: "offset aperture, 0.6× downscale", encoded: (2000, 3400), aperture: CGRect(x: 100, y: 60, width: 1800, height: 3200), output: (1080, 1920), nearUnitScale: false),
    ]

    private func plan(for c: GeometryCase) throws -> WorkingMediaNormalizationPlan {
        let facts = ImportApertureFacts.classify(
            encodedWidth: c.encoded.0, encodedHeight: c.encoded.1,
            cleanAperture: c.aperture.map { ImportCleanAperture(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) },
            pixelAspectRatio: c.par == (1, 1) ? nil : ImportPixelAspectRatio(horizontalSpacing: c.par.0, verticalSpacing: c.par.1))
        let (w, h) = c.natural
        let o = Self.trackTransform(c.orientation, w: w, h: h), (sx, sy) = c.scale
        let transform = ImportAffineTransform(a: o.a * sx, b: o.b * sy, c: o.c * sx, d: o.d * sy, tx: o.tx * sx, ty: o.ty * sy)
        return try syntheticPlan(natural: (Int(w.rounded()), Int(h.rounded())), transform: transform, fps: 30,
                                 audio: ImportAudioFacts(fourCC: "lpcm", sampleRate: 44_100, channelCount: 2), aperture: facts)
    }

    func testRenderGeometryMatchesAnIndependentMapping() throws {
        for c in Self.geometryCases {
            let plan = try plan(for: c)
            XCTAssertEqual(plan.raster.output, WorkingMediaRaster(width: c.output.0, height: c.output.1), c.name)
            let geometry = try WorkingMediaRenderGeometry(plan: plan)
            XCTAssertEqual(geometry.outputWidth, c.output.0, c.name); XCTAssertEqual(geometry.outputHeight, c.output.1, c.name)
            let back = geometry.sourceToOutput.inverted()
            // Corners, edge midpoints and interior points of the output, pixel centres.
            let W = Double(c.output.0), H = Double(c.output.1)
            for (u, v) in [(0.0, 0.0), (W - 1, 0), (0, H - 1), (W - 1, H - 1), (W / 2, 0), (0, H / 2), (W - 1, H / 2), (W / 2, H - 1), (123, 457), (W * 0.37, H * 0.81)] {
                let mapped = CGPoint(x: u + 0.5, y: v + 0.5).applying(back)
                let expected = c.sourcePoint(u: u, v: v)
                XCTAssertEqual(Double(mapped.x), expected.x, accuracy: 1e-6, "\(c.name) x at (\(u), \(v))")
                XCTAssertEqual(Double(mapped.y), expected.y, accuracy: 1e-6, "\(c.name) y at (\(u), \(v))")
                // Every output pixel centre samples inside the clean aperture.
                XCTAssertTrue(c.apertureRect.insetBy(dx: -1e-9, dy: -1e-9).contains(mapped), "\(c.name) (\(u), \(v)) → \(mapped)")
            }
            // The whole aperture maps onto the whole output.
            let mappedAperture = c.apertureRect.applying(geometry.sourceToOutput)
            XCTAssertEqual(mappedAperture.minX, 0, accuracy: 1e-6, c.name); XCTAssertEqual(mappedAperture.minY, 0, accuracy: 1e-6, c.name)
            XCTAssertEqual(mappedAperture.width, W, accuracy: 1e-6, c.name); XCTAssertEqual(mappedAperture.height, H, accuracy: 1e-6, c.name)
            XCTAssertLessThanOrEqual(plan.raster.alignmentLoss.width, 1); XCTAssertLessThanOrEqual(plan.raster.alignmentLoss.height, 1)
        }
    }

    /// ADR-049 Revision 1 Decision B, with hand-written matrices on both sides of the tolerance.
    func testNormalizationTransformEligibilityOnBothSides() {
        let angle = 1.0 * Double.pi / 180
        let accepted: [(String, ImportAffineTransform)] = [
            ("identity", .identity),
            ("90°", ImportAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)),
            ("180°", ImportAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1080, ty: 1920)),
            ("270°", ImportAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)),
            ("mirror X", ImportAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1080, ty: 0)),
            ("mirror Y", ImportAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1920)),
            ("mirror both", ImportAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1080, ty: 1920)),
            ("transpose", ImportAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)),
            ("translation", ImportAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: -37, ty: 12)),
            ("fractional translation", ImportAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0.5, ty: -10.25)),
            ("uniform scale", ImportAffineTransform(a: 0.5, b: 0, c: 0, d: 0.5, tx: 0, ty: 0)),
            ("non-uniform scale", ImportAffineTransform(a: 0.75, b: 0, c: 0, d: 1.3, tx: 0, ty: 0)),
            ("rotation + scale", ImportAffineTransform(a: 0, b: 0.9, c: -1.2, d: 0, tx: 1296, ty: 0)),
            ("mirror + scale", ImportAffineTransform(a: -0.8, b: 0, c: 0, d: 2, tx: 864, ty: 0)),
            ("small valid scale", ImportAffineTransform(a: 1e-3, b: 0, c: 0, d: 2e-3, tx: 0, ty: 0)),
            ("16.16 fixed-point noise", ImportAffineTransform(a: 1, b: 1.0 / 65536, c: -1.0 / 65536, d: 1, tx: 0, ty: 0)),
            ("just inside (0.99e-4)", ImportAffineTransform(a: 2, b: 2 * 0.99e-4, c: 0, d: 1, tx: 0, ty: 0)),
            ("swapped, just inside", ImportAffineTransform(a: 0.99e-4, b: 1, c: -1, d: 0, tx: 0, ty: 0)),
        ]
        for (label, t) in accepted { XCTAssertTrue(ImportNormalizationTransform.isEligible(t), label) }
        let rejected: [(String, ImportAffineTransform)] = [
            ("just outside (1.01e-4)", ImportAffineTransform(a: 2, b: 2 * 1.01e-4, c: 0, d: 1, tx: 0, ty: 0)),
            ("swapped, just outside", ImportAffineTransform(a: 1.01e-4, b: 1, c: -1, d: 0, tx: 0, ty: 0)),
            ("1° rotation", ImportAffineTransform(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle), tx: 0, ty: 0)),
            ("45° rotation", ImportAffineTransform(a: 0.7071, b: 0.7071, c: -0.7071, d: 0.7071, tx: 0, ty: 0)),
            ("shear", ImportAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)),
            ("zero determinant", ImportAffineTransform(a: 1, b: 0, c: 1, d: 0, tx: 0, ty: 0)),
            ("zero matrix", ImportAffineTransform(a: 0, b: 0, c: 0, d: 0, tx: 0, ty: 0)),
            ("near-zero basis", ImportAffineTransform(a: 1e-9, b: 0, c: 0, d: 1, tx: 0, ty: 0)),
            ("huge basis", ImportAffineTransform(a: 1e7, b: 0, c: 0, d: 1, tx: 0, ty: 0)),
            ("NaN", ImportAffineTransform(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0)),
            ("infinite translation", ImportAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: .infinity, ty: 0)),
        ]
        for (label, t) in rejected { XCTAssertFalse(ImportNormalizationTransform.isEligible(t), label) }
    }

    func testRenderGeometryRefusesUnsafeValues() throws {
        let lpcm = ImportAudioFacts(fourCC: "lpcm", sampleRate: 44_100, channelCount: 2)
        // A sheared transform never reaches a plan (preflight rejects it, ADR-049 R1).
        XCTAssertThrowsError(try syntheticPlan(natural: (1080, 1920), transform: ImportAffineTransform(a: 1, b: 0, c: 0.05, d: 1, tx: 0, ty: 0), fps: 30, audio: lpcm))
        // A finite translation so large the transformed bounds leave the representable range.
        let far = try syntheticPlan(natural: (1080, 1920), transform: ImportAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 1e10, ty: 0), fps: 30, audio: lpcm)
        XCTAssertThrowsError(try WorkingMediaRenderGeometry(plan: far)) { XCTAssertEqual($0 as? WorkingMediaGeometryProblem, .nonFinite) }
        // A malformed transform never traps the facts' integer conversion either.
        var facts = ImportSourceFacts(
            duration: .exact(try MediaTime(value: 720, timescale: 600)), isReadable: true, isPlayable: true, isExportable: true, hasProtectedContent: false,
            hasVideoTrack: true, hasAudioTrack: false, container: .quickTime, videoCodec: .h264(fourCC: "avc1"),
            naturalWidth: 1080, naturalHeight: 1920, preferredTransform: ImportAffineTransform(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0),
            nominalFrameRate: 30, minimumFrameDuration: nil, bitsPerComponent: 8, highBitDepthProfile: .no, fullRangeVideo: .no,
            colorPrimaries: .rec709, transferFunction: .rec709, ycbcrMatrix: .rec709, hasDolbyVisionConfiguration: false, ancillaryHDRMetadata: [],
            aperture: .classify(encodedWidth: 1080, encodedHeight: 1920, cleanAperture: nil, pixelAspectRatio: nil), audio: nil, byteCount: 1, modificationDate: nil)
        XCTAssertEqual(facts.presentationSize.width, 0); XCTAssertEqual(facts.presentationSize.height, 0)
        facts.preferredTransform = ImportAffineTransform(a: .infinity, b: 0, c: 0, d: 1, tx: 0, ty: 0)
        XCTAssertEqual(facts.presentationSize.width, 0)
        XCTAssertNotEqual(ImportPreflightClassifier.classify(facts), .readyFastPath(sourceDuration: try MediaTime(value: 720, timescale: 600)))
    }

    // MARK: Codec-free renderer

    /// The synthetic source: green-and-red sentinel outside the aperture's pixel coverage; inside,
    /// a 40 grey field with 1-px boundary lines that each carry one signal — top row R 240, bottom
    /// row R 140, left column G 240, right column G 140 — and 1-px B 240 marker rows / columns at
    /// irregular offsets. Channels never mix (no colour management), so each signal is traced
    /// independently and any sentinel (R = G = 255) bleed shows up in the channel a boundary does
    /// not carry.
    private struct BoundaryPainting {
        let left: Int, top: Int, right: Int, bottom: Int
        var markerRows: [Int] { [top + (bottom - top) / 4 + 1, top + (bottom - top) / 2 + 2] }
        var markerColumns: [Int] { [left + (right - left) / 4 + 1, left + (right - left) / 2 + 2] }

        init(_ aperture: CGRect) {
            left = Int(aperture.minX.rounded(.down)); top = Int(aperture.minY.rounded(.down))
            right = Int(aperture.maxX.rounded(.up)); bottom = Int(aperture.maxY.rounded(.up))
        }

        func rgb(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double) {
            guard (left..<right).contains(x), (top..<bottom).contains(y) else { return (255, 255, 40) }
            var r = 40.0, g = 40.0, b = 40.0
            if y == top { r = 240 } else if y == bottom - 1 { r = 140 }
            if x == left { g = 240 } else if x == right - 1 { g = 140 }
            if markerRows.contains(y) || markerColumns.contains(x) { b = 240 }
            return (r, g, b)
        }

        /// Bilinear sample at a continuous encoded position, with the renderer's edge extension.
        func bilinear(_ x: Double, _ y: Double) -> (r: Double, g: Double, b: Double) {
            let fx = x - 0.5, fy = y - 0.5
            let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
            let wx = fx - Double(x0), wy = fy - Double(y0)
            func at(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double) { rgb(min(max(x, left), right - 1), min(max(y, top), bottom - 1)) }
            let p00 = at(x0, y0), p10 = at(x0 + 1, y0), p01 = at(x0, y0 + 1), p11 = at(x0 + 1, y0 + 1)
            func mix(_ k: KeyPath<(r: Double, g: Double, b: Double), Double>) -> Double {
                (p00[keyPath: k] * (1 - wx) + p10[keyPath: k] * wx) * (1 - wy) + (p01[keyPath: k] * (1 - wx) + p11[keyPath: k] * wx) * wy
            }
            return (mix(\.r), mix(\.g), mix(\.b))
        }
    }

    private func bgraBuffer(_ width: Int, _ height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        XCTAssertEqual(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer), kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    private func fill(_ buffer: CVPixelBuffer, _ pixel: (Int, Int) -> (r: Double, g: Double, b: Double)) {
        CVPixelBufferLockBaseAddress(buffer, []); defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<CVPixelBufferGetHeight(buffer) {
            for x in 0..<CVPixelBufferGetWidth(buffer) {
                let p = pixel(x, y), o = y * stride + x * 4
                base[o] = UInt8(p.b); base[o + 1] = UInt8(p.g); base[o + 2] = UInt8(p.r); base[o + 3] = 255
            }
        }
    }

    private func read(_ buffer: CVPixelBuffer) -> (Int, Int) -> (r: Double, g: Double, b: Double) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = [UInt8](UnsafeBufferPointer(start: CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self), count: stride * height))
        return { x, y in
            let o = min(max(y, 0), height - 1) * stride + min(max(x, 0), width - 1) * 4
            return (Double(bytes[o + 2]), Double(bytes[o + 1]), Double(bytes[o]))
        }
    }

    private static let rendererContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])

    /// Renders one case through the production renderer and checks it against the independent
    /// mapping. Tolerances: ±18 levels between Core Image's resampler and the bilinear model for
    /// near-unit scales (sharp 200-level steps; a one-pixel error moves a boundary value by ≥ 100);
    /// ±2 on the channel an edge does not carry (exactly the field when nothing outside bleeds);
    /// marker centroids within 0.35 px (0.6 px below unit scale, where a 1-px line falls inside one
    /// output pixel), so a 1–3 px crop, pad or shift cannot pass.
    private func assertRenders(_ c: GeometryCase, file: StaticString = #filePath, line: UInt = #line) throws {
        let plan = try plan(for: c)
        let geometry = try WorkingMediaRenderGeometry(plan: plan)
        let painting = BoundaryPainting(c.apertureRect)
        let source = try bgraBuffer(c.encoded.0, c.encoded.1)
        fill(source) { painting.rgb($0, $1) }
        let destination = try bgraBuffer(c.output.0, c.output.1)
        fill(destination) { _, _ in (0, 0, 255) }   // stale content that must be fully overwritten
        try WorkingMediaFrameCompositor.render(source, geometry: geometry, into: destination, context: Self.rendererContext)
        let out = read(destination)
        XCTAssertEqual(CVPixelBufferGetWidth(destination), c.output.0, file: file, line: line)
        XCTAssertEqual(CVPixelBufferGetHeight(destination), c.output.1, file: file, line: line)
        let W = c.output.0, H = c.output.1
        let a = c.apertureRect

        // Each output edge carries exactly the source boundary the independent mapping puts there.
        let edges: [(String, [(Int, Int)], (Int, Int) -> (Int, Int))] = [
            ("top", stride(from: 8, to: W - 8, by: 7).map { ($0, 0) }, { ($0, $1 + 1) }),
            ("bottom", stride(from: 8, to: W - 8, by: 7).map { ($0, H - 1) }, { ($0, $1 - 1) }),
            ("left", stride(from: 8, to: H - 8, by: 7).map { (0, $0) }, { ($0 + 1, $1) }),
            ("right", stride(from: 8, to: H - 8, by: 7).map { (W - 1, $0) }, { ($0 - 1, $1) }),
        ]
        for (name, points, inward) in edges {
            let mid = points[points.count / 2]
            let s = c.sourcePoint(u: Double(mid.0), v: Double(mid.1))
            let distances = [("top", s.y - Double(a.minY)), ("bottom", Double(a.maxY) - s.y), ("left", s.x - Double(a.minX)), ("right", Double(a.maxX) - s.x)]
            let boundary = distances.min { $0.1 < $1.1 }!.0
            let carriesRed = boundary == "top" || boundary == "bottom"
            let level = (boundary == "top" || boundary == "left") ? 240.0 : 140.0
            for (u, v) in points {
                let value = out(u, v)
                let signal = carriesRed ? value.r : value.g, other = carriesRed ? value.g : value.r
                let label = "\(c.name): \(name) edge (source \(boundary)) at (\(u), \(v))"
                // The boundary contributes (no crop), and nothing from outside the aperture does.
                XCTAssertGreaterThan(signal, 40 + 0.25 * (level - 40), label, file: file, line: line)
                // Uncompressed and colour-managed off: the off-channel is exactly the 40 field (±2 for
                // 8-bit rounding), so any sentinel contribution shows.
                XCTAssertEqual(other, 40, accuracy: 2, "\(label): outside-aperture bleed", file: file, line: line)
                guard c.nearUnitScale else { continue }
                let model = { (p: (Int, Int)) -> (Double, Double) in
                    let s = c.sourcePoint(u: Double(p.0), v: Double(p.1)); let m = painting.bilinear(s.x, s.y)
                    return carriesRed ? (m.r, m.g) : (m.g, m.r)
                }
                XCTAssertEqual(signal, model((u, v)).0, accuracy: 18, label, file: file, line: line)
                // One pixel in: no duplicated boundary, no 1-px inward shift.
                let inner = inward(u, v), innerValue = out(inner.0, inner.1)
                XCTAssertEqual(carriesRed ? innerValue.r : innerValue.g, model(inner).0, accuracy: 18, "\(label) +1 inward", file: file, line: line)
            }
        }

        // Interior 1-px markers land where the whole-aperture mapping puts them (centroid ±0.35 px).
        for (isRow, marker) in painting.markerRows.map({ (true, $0) }) + painting.markerColumns.map({ (false, $0) }) {
            let target = Double(marker) + 0.5
            func coordinate(_ u: Double, _ v: Double) -> Double { let s = c.sourcePoint(u: u, v: v); return isRow ? s.y : s.x }
            // Which output axis crosses the marker line?
            let alongV = abs(coordinate(100, 101) - coordinate(100, 100)) > abs(coordinate(101, 100) - coordinate(100, 100))
            let probe = alongV ? Double(W) * 0.37 : Double(H) * 0.37
            let s0 = alongV ? coordinate(probe, 0) : coordinate(0, probe), k = alongV ? coordinate(probe, 1) - s0 : coordinate(1, probe) - s0
            let expected = (target - s0) / k   // continuous output pixel index of the line centre
            var weight = 0.0, moment = 0.0
            for i in (Int(expected.rounded()) - 4)...(Int(expected.rounded()) + 4) {
                let value = alongV ? out(Int(probe), i) : out(i, Int(probe))
                let w = max(0, value.b - 40)
                weight += w; moment += w * Double(i)
            }
            XCTAssertGreaterThan(weight, 60, "\(c.name): marker \(isRow ? "row" : "column") \(marker) missing", file: file, line: line)
            // Below unit scale a 1-px line is narrower than an output pixel and its centroid is
            // quantized to that pixel (error up to 0.5); a 1-px shift still errs by ≥ 0.9.
            XCTAssertEqual(moment / max(weight, 1), expected, accuracy: c.nearUnitScale ? 0.35 : 0.6, "\(c.name): marker \(isRow ? "row" : "column") \(marker)", file: file, line: line)
        }
    }

    func testGeometryRendererMapsEveryApertureExactly() throws {
        for c in Self.geometryCases { try assertRenders(c) }
    }

    func testGeometryRendererReportsFailureInsteadOfPublishing() throws {
        let c = Self.geometryCases[4]
        let geometry = try WorkingMediaRenderGeometry(plan: try plan(for: c))
        let source = try bgraBuffer(c.encoded.0, c.encoded.1)
        let destination = try bgraBuffer(c.output.0, c.output.1)
        XCTAssertThrowsError(try WorkingMediaFrameCompositor.render(source, geometry: geometry, into: destination, context: Self.rendererContext, injectFailure: true)) {
            XCTAssertEqual($0 as? WorkingMediaRenderFailure, .injected)
        }
        let wrongSource = try bgraBuffer(c.encoded.0, c.encoded.1 - 2)
        XCTAssertThrowsError(try WorkingMediaFrameCompositor.render(wrongSource, geometry: geometry, into: destination, context: Self.rendererContext)) {
            XCTAssertEqual($0 as? WorkingMediaRenderFailure, .sourceRasterMismatch)
        }
        let wrongDestination = try bgraBuffer(c.output.0 + 2, c.output.1)
        XCTAssertThrowsError(try WorkingMediaFrameCompositor.render(source, geometry: geometry, into: wrongDestination, context: Self.rendererContext)) {
            XCTAssertEqual($0 as? WorkingMediaRenderFailure, .destinationRasterMismatch)
        }
    }

    // MARK: - Cancellation

    /// Lets a hook cancel the normalization task deterministically: the task waits until it is armed
    /// before normalizing, so the cancel action always exists when the hook fires.
    final class CancelSwitch: @unchecked Sendable {
        private let lock = NSLock()
        private var action: (@Sendable () -> Void)?
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var fired = false

        func arm(_ action: @escaping @Sendable () -> Void) {
            lock.lock(); self.action = action; let pending = waiters; waiters = []; lock.unlock()
            pending.forEach { $0.resume() }
        }
        func waitUntilArmed() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if action != nil { lock.unlock(); continuation.resume() } else { waiters.append(continuation); lock.unlock() }
            }
        }
        func fire() { lock.lock(); let action = self.action; fired = true; lock.unlock(); action?() }
    }

    private func runCancelled(at stage: WorkingMediaNormalizationStage, fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) async throws {
        let source = try await write(fixture)
        let before = try stamp(source)
        let plan = try await plan(for: source, file: file, line: line)
        let target = destination()
        let cancelSwitch = CancelSwitch()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { observed in
            if observed == stage { cancelSwitch.fire() }
        }))
        let task = Task { () -> WorkingMediaNormalizationResult in
            await cancelSwitch.waitUntilArmed()
            return try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
        }
        cancelSwitch.arm { task.cancel() }
        await expectCancellation(file: file, line: line) { try await task.value }
        XCTAssertTrue(cancelSwitch.fired, "stage \(stage) was never reached", file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "partial output left behind", file: file, line: line)
        XCTAssertEqual(workspaceEntries(), [], file: file, line: line)
        XCTAssertEqual(try stamp(source), before, file: file, line: line)
    }

    func testPreCancelledTaskDoesNothing() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let task = Task { () -> WorkingMediaNormalizationResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: self.destination(), plan: plan)
        }
        await expectCancellation { try await task.value }
        XCTAssertEqual(workspaceEntries(), [])
    }

    func testCancellationAfterThePipelineStarted() async throws {
        try await runCancelled(at: .pipelineStarted, fixture: Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
    }

    func testCancellationDuringVideo() async throws {
        try await runCancelled(at: .sampleAppended(.video, count: 5), fixture: Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
    }

    func testCancellationWhileAudioIsActive() async throws {
        try await runCancelled(at: .sampleAppended(.audio, count: 1), fixture: Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600), audio: .aac(channels: 2, rate: 48_000)))
    }

    func testCancellationJustBeforeFinishWriting() async throws {
        try await runCancelled(at: .willFinishWriting, fixture: Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600), audio: .lpcm(channels: 2, rate: 44_100)))
    }

    func testCancellationJustAfterFinishWritingStillWins() async throws {
        try await runCancelled(at: .didFinishWriting, fixture: Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
    }

    // MARK: - Failure

    func testEveryInjectedFailureRemovesTheDestinationAndPreservesTheSource() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600), audio: .aac(channels: 2, rate: 48_000)))
        let before = try stamp(source)
        let plan = try await plan(for: source)
        let cases: [(WorkingMediaNormalizationFault, (WorkingMediaNormalizationError) -> Bool)] = [
            (.writerStart, { if case .writerStartFailed = $0 { return true }; return false }),
            (.readerStart, { if case .readerStartFailed = $0 { return true }; return false }),
            (.append(.video), { if case .appendFailed(.video, _, _) = $0 { return true }; return false }),
            (.append(.audio), { if case .appendFailed(.audio, _, _) = $0 { return true }; return false }),
            (.finishWriting, { if case .finishFailed = $0 { return true }; return false }),
            (.outputValidation, { if case .outputValidationFailed = $0 { return true }; return false }),
        ]
        for (fault, matches) in cases {
            let target = destination("\(fault)")
            let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(injectFault: { $0 == fault }))
            do {
                _ = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
                XCTFail("\(fault) did not fail")
            } catch let error as WorkingMediaNormalizationError {
                XCTAssertTrue(matches(error), "\(fault) → \(error)")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "\(fault) left the destination")
            XCTAssertEqual(workspaceEntries(), [], "\(fault) left files")
            XCTAssertEqual(try stamp(source), before, "\(fault) touched the source")
            // Cleanup left the path free: the same destination normalizes cleanly afterwards.
            let retry = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: target, plan: plan)
            XCTAssertEqual(retry.destinationURL, target)
            try FileManager.default.removeItem(at: target)
        }
    }

    // MARK: - Concurrency

    func testConcurrentNormalizationsAreIndependent() async throws {
        let fixture = Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600), audio: .aac(channels: 2, rate: 48_000))
        let a = try await write(fixture), b = try await write(fixture)
        let planA = try await plan(for: a), planB = try await plan(for: b)
        let targetA = destination("a"), targetB = destination("b")
        let cancelSwitch = CancelSwitch()
        let cancelling = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { if $0 == .sampleAppended(.video, count: 8) { cancelSwitch.fire() } }))
        let taskA = Task { () -> WorkingMediaNormalizationResult in
            await cancelSwitch.waitUntilArmed()
            return try await cancelling.normalize(sourceURL: a, destinationURL: targetA, plan: planA)
        }
        cancelSwitch.arm { taskA.cancel() }
        let taskB = Task { try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: b, destinationURL: targetB, plan: planB) }
        await expectCancellation { try await taskA.value }
        let resultB = try await taskB.value
        assertCanonical(resultB, plan: planB)
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetA.path))
        XCTAssertEqual(workspaceEntries(), [targetB.lastPathComponent])
    }

    func testSameDestinationCollisionFailsWithoutTouchingTheWinner() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let target = destination()
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let winner = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stage in
            if stage == .sampleAppended(.video, count: 3) { started.signal(); release.wait() }
        }))
        let first = Task { try await winner.normalize(sourceURL: source, destinationURL: target, plan: plan) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { started.wait(); continuation.resume() }
        }
        // The winner's file already exists, so the loser stops at the existence check.
        await expectError(.destinationExists) { try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: target, plan: plan) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path), "the loser must not remove the winner's file")
        release.signal()
        let result = try await first.value
        assertCanonical(result, plan: plan)
    }

    func testClaimedDestinationIsRefusedBeforeAnyFileExists() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let target = destination()
        // Another normalization holds the claim but has not created the file yet.
        let claim = try XCTUnwrap(WorkingMediaDestinationClaims.shared.claim(target))
        XCTAssertNil(WorkingMediaDestinationClaims.shared.claim(target))
        await expectError(.destinationInUse) { try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: target, plan: plan) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        claim.release()
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: target, plan: plan)
        assertCanonical(result, plan: plan)
    }

    // MARK: - Terminal failure liveness (Correction A)

    final class Recorder<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Value] = []
        func append(_ value: Value) { lock.lock(); values.append(value); lock.unlock() }
        var all: [Value] { lock.lock(); defer { lock.unlock() }; return values }
    }

    /// The video stream never gets a readiness callback (stall seam) and the writer / reader then
    /// reports a terminal failure that no callback announces. Only the status supervisor can end
    /// the run; the 60 s guard exists solely so a regression fails instead of hanging the suite.
    private func runStalled(simulating status: WorkingMediaSimulatedTerminalStatus) async throws -> (error: Error, terminations: [WorkingMediaRunTermination], target: URL, source: URL, before: Stamp) {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let before = try stamp(source)
        let plan = try await plan(for: source)
        let target = destination()
        let started = Recorder<Bool>(), terminations = Recorder<WorkingMediaRunTermination>()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(
            observe: { stage in
                if stage == .pipelineStarted { started.append(true) }
                if case .terminated(let reason) = stage { terminations.append(reason) }
            },
            injectFault: { $0 == .stall(.video) },
            simulatedTerminalStatus: { started.all.isEmpty ? nil : status }))
        let task = Task { try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan) }
        let safetyGuard = Task { try await Task.sleep(for: .seconds(60)); task.cancel() }
        defer { safetyGuard.cancel() }
        do {
            _ = try await task.value
            XCTFail("a stalled run must not succeed")
            throw CocoaError(.featureUnsupported)
        } catch {
            return (error, terminations.all, target, source, before)
        }
    }

    func testAsynchronousWriterFailureEndsAStalledRun() async throws {
        let outcome = try await runStalled(simulating: .writerFailed)
        guard case .writerFailed = outcome.error as? WorkingMediaNormalizationError else { return XCTFail("expected writerFailed, got \(outcome.error)") }
        XCTAssertEqual(outcome.terminations, [.writerFailed], "exactly one terminal transition")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outcome.target.path))
        XCTAssertEqual(workspaceEntries(), [])
        XCTAssertEqual(try stamp(outcome.source), outcome.before)
    }

    func testAsynchronousReaderFailureEndsAStalledRun() async throws {
        let outcome = try await runStalled(simulating: .readerFailed)
        guard case .readingFailed = outcome.error as? WorkingMediaNormalizationError else { return XCTFail("expected readingFailed, got \(outcome.error)") }
        XCTAssertEqual(outcome.terminations, [.readerFailed], "exactly one terminal transition")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outcome.target.path))
        XCTAssertEqual(workspaceEntries(), [])
    }

    func testSuccessfulRunTerminatesExactlyOnce() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600), audio: .aac(channels: 2, rate: 48_000)))
        let plan = try await plan(for: source)
        let terminations = Recorder<WorkingMediaRunTermination>()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stage in
            if case .terminated(let reason) = stage { terminations.append(reason) }
        }))
        let result = try await normalizer.normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        XCTAssertEqual(terminations.all, [.streamsCompleted])
    }

    // MARK: - Session end at the source duration (Correction B)

    private func assertEndsAtSourceDuration(_ f: Fixture, expectedFrameDuration: MediaTime, file: StaticString = #filePath, line: UInt = #line) async throws {
        let source = try await write(f)
        let facts = try await inspector.inspect(url: source)
        guard case .exact(let sourceDuration) = facts.duration else { return XCTFail("source duration", file: file, line: line) }
        let plan = try await plan(for: source, file: file, line: line)
        XCTAssertEqual(plan.outputFrameDuration, expectedFrameDuration, file: file, line: line)
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan, file: file, line: line)
        XCTAssertFalse(result.outputDuration < sourceDuration, "\(result.outputDuration) shorter than \(sourceDuration)", file: file, line: line)
        XCTAssertTrue(plan.acceptedOutputDuration.contains(result.outputDuration), "\(result.outputDuration)", file: file, line: line)
    }

    func testMisaligned24FpsDurationEndsAtTheSourceDuration() async throws {
        // 29 frames at 1/24 s, session ended at 702/600 = 1.17 s (28.08 frames): rounding the last
        // frame up would overshoot by 0.038 s, more than 1/30 s.
        let f = Fixture(frames: 29, frameDuration: CMTime(value: 25, timescale: 600), audio: .lpcm(channels: 2, rate: 44_100),
                        endTime: CMTime(value: 702, timescale: 600), audioFrames: 51_597)
        try await assertEndsAtSourceDuration(f, expectedFrameDuration: try MediaTime(value: 1, timescale: 24))
    }

    func testMisaligned25FpsDurationEndsAtTheSourceDuration() async throws {
        // 31 frames at 1/25 s, session ended at 723/600 = 1.205 s: rounding up would overshoot by 0.035 s.
        let f = Fixture(frames: 31, frameDuration: CMTime(value: 24, timescale: 600), audio: .lpcm(channels: 2, rate: 48_000),
                        endTime: CMTime(value: 723, timescale: 600), audioFrames: 57_840)
        try await assertEndsAtSourceDuration(f, expectedFrameDuration: try MediaTime(value: 1, timescale: 25))
    }

    func testLongerAudioDoesNotExtendTheOutput() async throws {
        // 1.0 s of video, 1.2 s of audio: the source (and output) duration is the audio's.
        let f = Fixture(frames: 30, audio: .lpcm(channels: 2, rate: 44_100), audioFrames: 52_920)
        try await assertEndsAtSourceDuration(f, expectedFrameDuration: try MediaTime(value: 1, timescale: 30))
    }

    // MARK: - Cleanup and ownership (Corrections C and D)

    private func identity(_ url: URL) throws -> WorkingMediaFileIdentity { try XCTUnwrap(AVFoundationWorkingMediaNormalizer.fileIdentity(at: url)) }

    func testOwnedOutputCleanupPrimitive() throws {
        let regular = workDir.appendingPathComponent("regular.mov")
        try Data("partial".utf8).write(to: regular)
        let owned = try identity(regular)
        XCTAssertNil(AVFoundationWorkingMediaNormalizer.removeOwnedOutput(at: regular, identity: owned))
        XCTAssertFalse(FileManager.default.fileExists(atPath: regular.path))
        XCTAssertNil(AVFoundationWorkingMediaNormalizer.removeOwnedOutput(at: regular, identity: owned), "repeated cleanup is idempotent")
        XCTAssertEqual(workspaceEntries(), [], "no quarantine file is left behind")

        let directory = workDir.appendingPathComponent("directory.mov", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: directory.appendingPathComponent("child"))
        XCTAssertEqual(AVFoundationWorkingMediaNormalizer.removeOwnedOutput(at: directory, identity: owned), .unsafeItem(path: directory.path, fileType: "directory"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("child").path))

        let target = sourceDir.appendingPathComponent("decoy.txt")
        try Data("decoy".utf8).write(to: target)
        let link = workDir.appendingPathComponent("link.mov")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(AVFoundationWorkingMediaNormalizer.removeOwnedOutput(at: link, identity: try identity(target)), .unsafeItem(path: link.path, fileType: "symbolicLink"))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))
        XCTAssertEqual(try Data(contentsOf: target), Data("decoy".utf8))

        let stubborn = workDir.appendingPathComponent("stubborn.mov")
        try Data("partial".utf8).write(to: stubborn)
        XCTAssertEqual(AVFoundationWorkingMediaNormalizer.removeOwnedOutput(at: stubborn, identity: try identity(stubborn), injectRemovalFailure: true),
                       .removalFailed(path: stubborn.path, domain: "WorkingMediaNormalizerHooks", code: 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stubborn.path))
    }

    func testCleanupRefusesAFileWithAnotherIdentity() throws {
        // The owned file is renamed away and a foreign regular file takes its path: never removed.
        let path = workDir.appendingPathComponent("owned.mov")
        try Data("owned".utf8).write(to: path)
        let owned = try identity(path)
        try FileManager.default.moveItem(at: path, to: workDir.appendingPathComponent("moved-away.mov"))
        try Data("foreign".utf8).write(to: path)
        XCTAssertEqual(AVFoundationWorkingMediaNormalizer.removeOwnedOutput(at: path, identity: owned), .identityChanged(path: path.path))
        XCTAssertEqual(try Data(contentsOf: path), Data("foreign".utf8))
        XCTAssertEqual(try Data(contentsOf: workDir.appendingPathComponent("moved-away.mov")), Data("owned".utf8))
    }

    func testCleanupRaceReplacementIsRestoredNotDeleted() throws {
        // The path is replaced after the identity check and before quarantine (the lstat → remove
        // window): the quarantine re-check finds a foreign file, moves it back, and reports.
        let path = workDir.appendingPathComponent("owned.mov")
        try Data("owned".utf8).write(to: path)
        let owned = try identity(path)
        let failure = AVFoundationWorkingMediaNormalizer.removeOwnedOutput(at: path, identity: owned, willQuarantine: {
            try? FileManager.default.removeItem(at: path)
            try? Data("foreign".utf8).write(to: path)
        })
        XCTAssertEqual(failure, .identityChanged(path: path.path))
        XCTAssertEqual(try Data(contentsOf: path), Data("foreign".utf8), "the replacement survives at its path")
        XCTAssertEqual(workspaceEntries(), ["owned.mov"], "nothing left in quarantine")
    }

    func testCleanupFailureAfterAConversionFailureIsReported() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let target = destination()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(injectFault: { $0 == .finishWriting || $0 == .cleanupRemoval }))
        do {
            _ = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
            XCTFail("no result may be published")
        } catch let error as WorkingMediaNormalizationError {
            guard case .cleanupFailed(.removalFailed(let path, _, _), let preceding, let cancelled) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(path, target.path)
            XCTAssertFalse(cancelled)
            guard case .finishFailed = preceding else { return XCTFail("preceding \(String(describing: preceding))") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path), "the failure is reported, not hidden")
        try FileManager.default.removeItem(at: target)
    }

    func testCleanupFailureAfterCancellationIsReported() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let target = destination()
        let cancelSwitch = CancelSwitch()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(
            observe: { if $0 == .didFinishWriting { cancelSwitch.fire() } },
            injectFault: { $0 == .cleanupRemoval }))
        let task = Task { () -> WorkingMediaNormalizationResult in
            await cancelSwitch.waitUntilArmed()
            return try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
        }
        cancelSwitch.arm { task.cancel() }
        do {
            _ = try await task.value
            XCTFail("no result may be published")
        } catch let error as WorkingMediaNormalizationError {
            XCTAssertEqual(error, .cleanupFailed(.removalFailed(path: target.path, domain: "WorkingMediaNormalizerHooks", code: 1), precedingError: nil, cancelled: true))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        try FileManager.default.removeItem(at: target)
    }

    func testReplacedOwnedOutputIsNeverRemoved() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let decoy = sourceDir.appendingPathComponent("decoy.txt")
        try Data("decoy".utf8).write(to: decoy)
        for replacement in ["directory", "symbolicLink"] {
            let target = destination(replacement)
            let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(
                observe: { stage in
                    guard stage == .didFinishWriting else { return }
                    try? FileManager.default.removeItem(at: target)
                    if replacement == "directory" {
                        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                    } else {
                        try? FileManager.default.createSymbolicLink(at: target, withDestinationURL: decoy)
                    }
                },
                injectFault: { $0 == .finishWriting }))
            do {
                _ = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
                XCTFail("no result may be published")
            } catch let error as WorkingMediaNormalizationError {
                guard case .cleanupFailed(.unsafeItem(let path, let type), let preceding, false) = error else { return XCTFail("\(error)") }
                XCTAssertEqual(path, target.path)
                XCTAssertEqual(type, replacement)
                guard case .finishFailed = preceding else { return XCTFail("preceding \(String(describing: preceding))") }
            }
            XCTAssertTrue(AVFoundationWorkingMediaNormalizer.itemExists(at: target), "\(replacement) survives")
            XCTAssertEqual(try Data(contentsOf: decoy), Data("decoy".utf8))
            try FileManager.default.removeItem(at: target)
        }
    }

    func testStartWritingFailureGrantsNoOwnership() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let foreign = Data("foreign".utf8)
        // A foreign file appears after entry validation, just before startWriting: the run never
        // owns it, so nothing removes it — with the real start and with an injected start failure.
        for injected in [false, true] {
            let target = destination(injected ? "injected" : "real")
            let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(
                observe: { if $0 == .willStartWriting { try? foreign.write(to: target) } },
                injectFault: { injected && $0 == .writerStart }))
            do {
                _ = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
                XCTFail("startWriting over a foreign file must fail")
            } catch let error as WorkingMediaNormalizationError {
                guard case .writerStartFailed = error else { return XCTFail("\(error)") }
            }
            XCTAssertEqual(try Data(contentsOf: target), foreign, "the foreign file survives")
            try FileManager.default.removeItem(at: target)
        }
    }

    func testPreExistingDirectoryAndSymlinkDestinationsSurvive() async throws {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let normalizer = AVFoundationWorkingMediaNormalizer()
        let directory = destination("dir")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        await expectError(.destinationExists) { try await normalizer.normalize(sourceURL: source, destinationURL: directory, plan: plan) }
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue)

        let decoy = sourceDir.appendingPathComponent("decoy.txt")
        try Data("decoy".utf8).write(to: decoy)
        let link = destination("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: decoy)
        await expectError(.destinationExists) { try await normalizer.normalize(sourceURL: source, destinationURL: link, plan: plan) }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), decoy.path)
        XCTAssertEqual(try Data(contentsOf: decoy), Data("decoy".utf8))

        let dangling = destination("dangling")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: sourceDir.appendingPathComponent("nothing.mov"))
        await expectError(.destinationExists) { try await normalizer.normalize(sourceURL: source, destinationURL: dangling, plan: plan) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceDir.appendingPathComponent("nothing.mov").path), "never written through")
    }

    // MARK: - Six-channel downmix (Correction G)

    /// Decoded output audio as float stereo at 48 kHz.
    private func decodeStereo(_ url: URL) async throws -> (left: [Float], right: [Float]) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var left: [Float] = [], right: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var floats = [Float](repeating: 0, count: length / 4)
            floats.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            for index in stride(from: 0, to: floats.count - 1, by: 2) { left.append(floats[index]); right.append(floats[index + 1]) }
        }
        XCTAssertEqual(reader.status, .completed)
        return (left, right)
    }

    /// Amplitude of one frequency (single-bin DFT) over `samples` at 48 kHz.
    private func amplitude(_ samples: ArraySlice<Float>, frequency: Double) -> Double {
        var real = 0.0, imaginary = 0.0
        for (offset, value) in samples.enumerated() {
            let phase = 2 * Double.pi * frequency * Double(offset) / 48_000
            real += Double(value) * cos(phase); imaginary -= Double(value) * sin(phase)
        }
        return 2 * (real * real + imaginary * imaginary).squareRoot() / Double(samples.count)
    }

    func testSixChannelSourceIsMixedIntoBothStereoChannels() async throws {
        // L 440, R 660, C 880, LFE 110, Ls 1320, Rs 1760 Hz, each at 0.1 full scale (MPEG 5.1 A order).
        let tones: [Double] = [440, 660, 880, 110, 1320, 1760]
        let source = try await write(Fixture(audio: .lpcm(channels: 6, rate: 44_100), tones: tones))
        let plan = try await plan(for: source)
        guard case .transcode(let settings) = plan.audio else { return XCTFail("expected transcode") }
        XCTAssertEqual(settings.bitRate, 128_000)
        XCTAssertTrue(settings.downmixesToStereo)
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)

        let audioTracks = try await AVURLAsset(url: result.destinationURL).loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(audioTracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let description = try XCTUnwrap(descriptions.first)
        let asbd = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee)
        XCTAssertEqual(asbd.mFormatID, kAudioFormatMPEG4AAC)
        // Core Audio identifies AAC-LC by format ID `aac ` (HE-AAC is `aach`, HE v2 `aacp`) and LC
        // packets carry 1024 frames (HE: 2048); AAC's object type is not in the ASBD flags.
        XCTAssertEqual(asbd.mFramesPerPacket, 1024, "AAC-LC")
        XCTAssertEqual(asbd.mSampleRate, 48_000)
        XCTAssertEqual(asbd.mChannelsPerFrame, 2)

        let decoded = try await decodeStereo(result.destinationURL)
        let window = 14_400..<38_400   // 0.3–0.8 s, clear of encoder priming
        let left = decoded.left[window], right = decoded.right[window]
        func amp(_ channel: ArraySlice<Float>, _ index: Int) -> Double { amplitude(channel, frequency: tones[index]) }
        // Front channels land on their own side and stay separated (this is not a mono sum).
        XCTAssertGreaterThan(amp(left, 0), 0.02); XCTAssertGreaterThan(amp(right, 1), 0.02)
        XCTAssertLessThan(amp(right, 0), amp(left, 0) * 0.3); XCTAssertLessThan(amp(left, 1), amp(right, 1) * 0.3)
        // Centre reaches both sides; each surround reaches its own side — channels beyond the front
        // pair are mixed, not dropped.
        XCTAssertGreaterThan(amp(left, 2), 0.01); XCTAssertGreaterThan(amp(right, 2), 0.01)
        XCTAssertGreaterThan(amp(left, 4), 0.01, "Ls in L"); XCTAssertGreaterThan(amp(right, 5), 0.01, "Rs in R")
    }

    // MARK: - ADR-047 Revision 1 render geometry (Correction H)

    func testOddHeightIsResampledWholeIntoTheEvenRaster() async throws {
        // 1080×1919 presentation → 1080×1918: height-only parity remainder. H.264 encodes only even
        // edges, so the fixture encodes 1920×1080 with a 1919:1920 pixel aspect (presented 1919×1080)
        // and rotates it 90° into a 1080×1919 portrait. In presentation space the natural top/bottom
        // borders become the right/left edges, the natural left/right borders the top/bottom edges,
        // the natural line at x 270 a horizontal line near y 270, and the gradient runs along x.
        let f = Fixture(width: 1920, height: 1080, transform: Self.rotate90, audio: .lpcm(channels: 2, rate: 44_100), pattern: .edges, pixelAspect: (1919, 1920))
        let source = try await write(f)
        let sourceFacts = try await inspector.inspect(url: source)
        XCTAssertEqual(sourceFacts.presentationSize.width, 1080); XCTAssertEqual(sourceFacts.presentationSize.height, 1919)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.raster.output, WorkingMediaRaster(width: 1080, height: 1918))
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)

        let decoded = try await frame(result.destinationURL)
        XCTAssertEqual(decoded.width, 1080); XCTAssertEqual(decoded.height, 1918)
        let bright = 170.0
        // All four source edges reach the output edges: nothing cropped, no black border added.
        for x in [100, 540, 980] {
            XCTAssertGreaterThan(decoded.luminance(CGPoint(x: x, y: 0)), bright, "top edge at x \(x)")
            XCTAssertGreaterThan(decoded.luminance(CGPoint(x: x, y: 1917)), bright, "bottom edge at x \(x)")
        }
        for y in [300, 960, 1600] {
            XCTAssertGreaterThan(decoded.luminance(CGPoint(x: 0, y: y)), bright, "left edge at y \(y)")
            XCTAssertGreaterThan(decoded.luminance(CGPoint(x: 1079, y: y)), bright, "right edge at y \(y)")
        }
        // Vertical mapping resamples the whole frame: the line at presented y ≈ 269.9 lands at
        // ≈ 269.7 of 1918 rows (not shifted as a top crop would, not displaced by padding).
        XCTAssertGreaterThan(decoded.luminance(CGPoint(x: 540, y: 271)), bright)
        XCTAssertLessThan(decoded.luminance(CGPoint(x: 540, y: 290)), 140)
        // Horizontal mapping is 1:1 for this height-only case: the gradient along x sits where an
        // unscaled x puts it (±15 levels for H.264 / colour conversion).
        for x in [300, 540, 800] {
            let expected = 40 + Double(1080 - x) * 80 / 1080
            XCTAssertEqual(decoded.luminance(CGPoint(x: x, y: 960)), expected, accuracy: 15, "gradient at x \(x)")
        }
    }

    // MARK: Clean aperture (ADR-047 Revision 1: the exact aperture, whole, onto the planned raster)

    typealias DecodedFrame = (width: Int, height: Int, luminance: (CGPoint) -> Double, rgb: (CGPoint) -> (r: Double, g: Double, b: Double))

    /// Decoded-pixel tolerances. The `.aperture` dash levels 240 / 176 are 64 apart; after BGRA →
    /// 4:2:0 → H.264 → RGB they land within ±25 (`dashTolerance`). Everything that is not edge
    /// content stays below `edgeFloor` (150): the interior gradient tops out at 120, black padding
    /// decodes below 20 and the outside-aperture green averages ≈ 86. Neutral grey decodes with a
    /// channel spread below 20 (`neutralSpread`); the green has a spread of ≈ 160, and even a
    /// partial bleed of it into an edge row (what the built-in compositor produced for an offset
    /// aperture) shows a spread of ≈ 35–40.
    private static let edgeFloor = 150.0, dashTolerance = 25.0, neutralSpread = 20.0

    private static func spread(_ c: (r: Double, g: Double, b: Double)) -> Double { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }

    /// Every edge row / column of the output carries the aperture's own edge band: bright, neutral
    /// (no encoded raster from outside the aperture) and varying with the dash pattern (no black or
    /// flat synthetic border), sampled every 8 px along all four edges.
    private func assertApertureEdges(_ decoded: DecodedFrame, file: StaticString = #filePath, line: UInt = #line) {
        let w = decoded.width, h = decoded.height
        let edges: [(String, [CGPoint])] = [
            ("top", stride(from: 2, to: w - 2, by: 8).map { CGPoint(x: $0, y: 0) }),
            ("bottom", stride(from: 2, to: w - 2, by: 8).map { CGPoint(x: $0, y: h - 1) }),
            ("left", stride(from: 2, to: h - 2, by: 8).map { CGPoint(x: 0, y: $0) }),
            ("right", stride(from: 2, to: h - 2, by: 8).map { CGPoint(x: w - 1, y: $0) }),
        ]
        for (name, points) in edges {
            var levels: [Double] = []
            for point in points {
                let luma = decoded.luminance(point), colour = decoded.rgb(point)
                levels.append(luma)
                XCTAssertGreaterThan(luma, Self.edgeFloor, "\(name) edge at \(point): not edge content", file: file, line: line)
                XCTAssertLessThan(Self.spread(colour), Self.neutralSpread, "\(name) edge at \(point): raster outside the aperture", file: file, line: line)
            }
            XCTAssertGreaterThan((levels.max() ?? 0) - (levels.min() ?? 0), 40, "\(name) edge has no dash variation", file: file, line: line)
        }
    }

    /// The dash level painted at aperture-local `(x, y)`.
    private static func dashLevel(x: Int, y: Int) -> Double { ((x + y) / 40) % 2 == 0 ? 240 : 176 }

    func testOddCleanApertureIsResampledWholeIntoTheEvenRaster() async throws {
        // Encoded 1080×1920 with a 1080×1919 clean aperture centred in it (origin y 0.5, the only
        // way an odd aperture fits an even raster), presented 1080×1919 → planned 1080×1918.
        let aperture = CGRect(x: 0, y: 0.5, width: 1080, height: 1919)
        let f = Fixture(width: 1080, height: 1920, audio: .lpcm(channels: 2, rate: 44_100), pattern: .aperture, cleanAperture: aperture)
        let source = try await write(f)
        let before = try stamp(source)
        let sourceFacts = try await inspector.inspect(url: source)
        XCTAssertEqual(sourceFacts.presentationSize.width, 1080); XCTAssertEqual(sourceFacts.presentationSize.height, 1919)
        let formats = try await AVURLAsset(url: source).loadTracks(withMediaType: .video).first?.load(.formatDescriptions)
        let format = try XCTUnwrap(formats?.first)
        XCTAssertEqual(CMVideoFormatDescriptionGetDimensions(format).height, 1920)
        XCTAssertEqual(CMVideoFormatDescriptionGetCleanAperture(format, originIsAtTopLeft: true), aperture)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.raster.output, WorkingMediaRaster(width: 1080, height: 1918))
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        XCTAssertEqual(try stamp(source), before)

        let decoded = try await frame(result.destinationURL)
        XCTAssertEqual(decoded.width, 1080); XCTAssertEqual(decoded.height, 1918)
        assertApertureEdges(decoded)
        // The first and last output rows hold the aperture's own top / bottom band, dash for dash
        // (painted rows 0–3 and 1916–1919, all inside one dash where (x + row) / 40 is constant).
        for x in stride(from: 8, to: 1072, by: 4) where (x + 1916) % 40 >= 6 && (x + 1916) % 40 <= 30 {
            XCTAssertEqual(decoded.luminance(CGPoint(x: x, y: 1917)), Self.dashLevel(x: x, y: 1917), accuracy: Self.dashTolerance, "last row at x \(x)")
        }
        for x in stride(from: 8, to: 1072, by: 4) where x % 40 >= 6 && x % 40 <= 30 {
            XCTAssertEqual(decoded.luminance(CGPoint(x: x, y: 0)), Self.dashLevel(x: x, y: 1), accuracy: Self.dashTolerance, "first row at x \(x)")
        }
        // Horizontal mapping is 1:1 (height-only remainder): the column marker stays at x 270–273.
        XCTAssertGreaterThan(decoded.luminance(CGPoint(x: 271, y: 1200)), 200)
        XCTAssertLessThan(decoded.luminance(CGPoint(x: 290, y: 1200)), 140)
        // Vertical mapping resamples all 1919 aperture rows onto 1918: the row marker (painted rows
        // 480–483 → output ≈ 479.3–483.2) and the gradient sit where the whole-frame mapping puts them.
        XCTAssertGreaterThan(decoded.luminance(CGPoint(x: 700, y: 481)), 200)
        XCTAssertLessThan(decoded.luminance(CGPoint(x: 700, y: 470)), 140)
        XCTAssertLessThan(decoded.luminance(CGPoint(x: 700, y: 495)), 140)
        for y in [300, 960, 1440, 1900] {
            let paintedRow = (Double(y) + 0.5) * 1919 / 1918
            XCTAssertEqual(decoded.luminance(CGPoint(x: 700, y: y)), 40 + paintedRow * 80 / 1920, accuracy: 15, "gradient at y \(y)")
        }
    }

    func testCleanApertureWithANonzeroOriginSelectsOnlyTheAperture() async throws {
        // 1000×1800 aperture at (60, 100) inside a 1080×1920 encode whose surround is green.
        let aperture = CGRect(x: 60, y: 100, width: 1000, height: 1800)
        let f = Fixture(width: 1080, height: 1920, audio: .lpcm(channels: 2, rate: 44_100), pattern: .aperture, cleanAperture: aperture)
        let source = try await write(f)
        let formats = try await AVURLAsset(url: source).loadTracks(withMediaType: .video).first?.load(.formatDescriptions)
        let format = try XCTUnwrap(formats?.first)
        XCTAssertEqual(CMVideoFormatDescriptionGetCleanAperture(format, originIsAtTopLeft: true), aperture)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.raster.presentation, WorkingMediaRaster(width: 1000, height: 1800))
        XCTAssertEqual(plan.raster.output, WorkingMediaRaster(width: 1000, height: 1800))
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)

        let decoded = try await frame(result.destinationURL)
        XCTAssertEqual(decoded.width, 1000); XCTAssertEqual(decoded.height, 1800)
        assertApertureEdges(decoded)
        // No encoded pixel from outside the aperture appears anywhere in the frame.
        for y in stride(from: 0, to: 1800, by: 45) {
            for x in stride(from: 0, to: 1000, by: 45) {
                XCTAssertLessThan(Self.spread(decoded.rgb(CGPoint(x: x, y: y))), Self.neutralSpread, "green at (\(x), \(y))")
            }
        }
        // Aperture-local markers land 1:1 at aperture-local positions (the origin is removed): the
        // column marker at x 270–273, the row marker at y 480–483 — not at encoded x 330 / y 580.
        XCTAssertGreaterThan(decoded.luminance(CGPoint(x: 271, y: 1200)), 200)
        XCTAssertGreaterThan(decoded.luminance(CGPoint(x: 700, y: 481)), 200)
        XCTAssertLessThan(decoded.luminance(CGPoint(x: 331, y: 1200)), 140)
        XCTAssertLessThan(decoded.luminance(CGPoint(x: 700, y: 581)), 140)
        for y in [300, 960, 1500] {
            XCTAssertEqual(decoded.luminance(CGPoint(x: 700, y: y)), 40 + (Double(y) + 0.5) * 80 / 1800, accuracy: 15, "gradient at y \(y)")
        }
    }

    func testRotatedOddCleanApertureKeepsItsWholeBoundary() async throws {
        // Landscape encode 1920×1080, 1919×1080 aperture centred (origin x 0.5), rotated 90° into a
        // 1080×1919 portrait → planned 1080×1918. In presentation space the natural column marker
        // (x 270–273) becomes a row near y 270, the natural row marker (y 480–483) a column at
        // x 597–600, and the natural top-to-bottom gradient runs right to left.
        let aperture = CGRect(x: 0.5, y: 0, width: 1919, height: 1080)
        let f = Fixture(width: 1920, height: 1080, transform: Self.rotate90, audio: .lpcm(channels: 2, rate: 44_100), pattern: .aperture, cleanAperture: aperture)
        let source = try await write(f)
        let sourceFacts = try await inspector.inspect(url: source)
        XCTAssertEqual(sourceFacts.presentationSize.width, 1080); XCTAssertEqual(sourceFacts.presentationSize.height, 1919)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.raster.output, WorkingMediaRaster(width: 1080, height: 1918))
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)   // identity transform, portrait, canonical codec / colour / cadence

        let decoded = try await frame(result.destinationURL)
        XCTAssertEqual(decoded.width, 1080); XCTAssertEqual(decoded.height, 1918)
        assertApertureEdges(decoded)
        XCTAssertGreaterThan(decoded.luminance(CGPoint(x: 540, y: 271)), 200)
        XCTAssertLessThan(decoded.luminance(CGPoint(x: 540, y: 290)), 140)
        XCTAssertGreaterThan(decoded.luminance(CGPoint(x: 598, y: 1200)), 200)
        XCTAssertLessThan(decoded.luminance(CGPoint(x: 620, y: 1200)), 140)
        for x in [300, 800, 1000] {
            XCTAssertEqual(decoded.luminance(CGPoint(x: x, y: 1200)), 40 + (1080 - Double(x) - 0.5) * 80 / 1080, accuracy: 15, "gradient at x \(x)")
        }
    }

    func testLowResolutionSourceIsNormalizedWithoutUpscaling() async throws {
        // 720×1280 at 60 fps: normalized for cadence only; the raster stays 720×1280, whole.
        let f = Fixture(width: 720, height: 1280, frames: 72, frameDuration: CMTime(value: 10, timescale: 600), pattern: .aperture)
        let source = try await write(f)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.reasons, [.frameRate(nominal: 60)])
        XCTAssertEqual(plan.raster.output, WorkingMediaRaster(width: 720, height: 1280))
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        let decoded = try await frame(result.destinationURL)
        XCTAssertEqual(decoded.width, 720); XCTAssertEqual(decoded.height, 1280)
        assertApertureEdges(decoded)
        XCTAssertGreaterThan(decoded.luminance(CGPoint(x: 271, y: 900)), 200)
        XCTAssertGreaterThan(decoded.luminance(CGPoint(x: 600, y: 481)), 200)
    }

    // MARK: - ADR-049 render paths (real media)

    private func recordPaths() -> (Recorder<WorkingMediaNormalizationStage>, WorkingMediaNormalizerHooks) {
        let stages = Recorder<WorkingMediaNormalizationStage>()
        return (stages, WorkingMediaNormalizerHooks(observe: { stages.append($0) }))
    }

    private func configuredPaths(_ stages: Recorder<WorkingMediaNormalizationStage>) -> [WorkingMediaNormalizationStage] {
        stages.all.filter { if case .videoPathConfigured = $0 { return true } else { return false } }
    }

    func testFullApertureSourcesUseTheBuiltInCompositorOnly() async throws {
        for f in [Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)), Fixture(frames: 36, video: .hevcHLG), Fixture(frames: 36, video: .hevcPQ)] {
            let source = try await write(f)
            let plan = try await plan(for: source)
            XCTAssertEqual(plan.renderPath, .builtInToneMap)
            let (stages, hooks) = recordPaths()
            let result = try await AVFoundationWorkingMediaNormalizer(hooks: hooks).normalize(sourceURL: source, destinationURL: destination(), plan: plan)
            assertCanonical(result, plan: plan)
            XCTAssertEqual(configuredPaths(stages), [.videoPathConfigured(.builtInToneMap, customCompositor: false)], "no custom compositor on the tone-mapping path")
        }
    }

    func testNonFullSDRApertureUsesTheGeometryCompositor() async throws {
        let f = Fixture(width: 1080, height: 1920, audio: .lpcm(channels: 2, rate: 44_100), pattern: .aperture, cleanAperture: CGRect(x: 0, y: 0.5, width: 1080, height: 1919))
        let source = try await write(f)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.renderPath, .sdrApertureGeometry)
        let (stages, hooks) = recordPaths()
        let result = try await AVFoundationWorkingMediaNormalizer(hooks: hooks).normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)   // same validator and contract as the built-in path
        XCTAssertEqual(configuredPaths(stages), [.videoPathConfigured(.sdrApertureGeometry, customCompositor: true)])
    }

    /// Discriminates real HDR → SDR conversion from re-tagging. PQ code 509 (≈ 100 cd/m²) read
    /// naively as Rec.709 video-range code would decode to ≈ 130; ADR-045's built-in compositor
    /// renders it at ≈ 197 on LunaTestphone. The bound sits 30 above the naive value (beyond H.264 /
    /// colour-conversion noise of ±15) and below clipping, with a black and a mid-grey control.
    /// Proves only that the PQ signal is interpreted, not tone-curve quality (device A/B).
    func testPQIsToneMappedNotRetagged() async throws {
        let mid = try await write(Fixture(frames: 36, video: .hevcPQ, tenBitLevels: (509, 64)))
        let midPlan = try await plan(for: mid)
        XCTAssertEqual(midPlan.renderPath, .builtInToneMap)
        let midFrame = try await frame(try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: mid, destinationURL: destination(), plan: midPlan).destinationURL)
        XCTAssertGreaterThan(midFrame.luminance(CGPoint(x: 100, y: 100)), 160, "PQ ≈100 cd/m² must not decode at its naive Rec.709 level (≈130)")
        XCTAssertLessThan(midFrame.luminance(CGPoint(x: 100, y: 100)), 250, "and is not clipped to white")
        XCTAssertLessThan(midFrame.luminance(CGPoint(x: 800, y: 1500)), 16, "PQ code 64 (black) stays black")
        let bright = try await write(Fixture(frames: 36, video: .hevcPQ, tenBitLevels: (700, 300)))
        let brightPlan = try await plan(for: bright)
        let brightFrame = try await frame(try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: bright, destinationURL: destination(), plan: brightPlan).destinationURL)
        XCTAssertGreaterThan(brightFrame.luminance(CGPoint(x: 100, y: 100)), midFrame.luminance(CGPoint(x: 100, y: 100)), "brighter PQ stays brighter")
        XCTAssertGreaterThan(brightFrame.luminance(CGPoint(x: 800, y: 1500)), 30, "PQ ≈ 5 cd/m² is not crushed to black")
    }

    private static let oddAperture = CGRect(x: 0, y: 0.5, width: 1080, height: 1919)
    /// A 60 fps SDR Rec.709 source with a non-full clean aperture: ADR-049 Case C.
    private func oddSDRSource() async throws -> URL {
        try await write(Fixture(frames: 60, frameDuration: CMTime(value: 10, timescale: 600), cleanAperture: Self.oddAperture))
    }

    func testCaseDNonFullHDRNeverReachesAMediaOperation() async throws {
        let hdr = try await write(Fixture(frames: 36, video: .hevcHLG, cleanAperture: Self.oddAperture))
        let before = try stamp(hdr)
        let facts = try await inspector.inspect(url: hdr)
        guard case .nonFull = facts.aperture else { return XCTFail("fixture must have a non-full aperture: \(facts.aperture)") }
        XCTAssertEqual(ImportPreflightClassifier.classify(facts), .rejected(.unsupportedApertureNormalization(.colorNotProvenSDRRec709)))
        // No plan can exist for it, on either path…
        for path in [ImportPreparationPath.normalizeBuiltInToneMap(reasons: [.hdr(signals: [.hlgTransfer])]), .normalizeSDRApertureGeometry(reasons: [.hdr(signals: [.hlgTransfer])])] {
            XCTAssertThrowsError(try WorkingMediaPlanBuilder.plan(preparationPath: path, facts: facts, sourceDuration: try MediaTime(value: 720, timescale: 600))) {
                XCTAssertEqual($0 as? WorkingMediaPlanError, .rejectedByPreflight(.unsupportedApertureNormalization(.colorNotProvenSDRRec709)))
            }
        }
        // …and a plan made for an SDR source is refused before any composition, reader or writer.
        let sdrPlan = try await plan(for: try await oddSDRSource())
        XCTAssertEqual(sdrPlan.renderPath, .sdrApertureGeometry)
        let (stages, hooks) = recordPaths()
        await expectError(.planDoesNotMatchSource) {
            try await AVFoundationWorkingMediaNormalizer(hooks: hooks).normalize(sourceURL: hdr, destinationURL: self.destination(), plan: sdrPlan)
        }
        XCTAssertEqual(stages.all, [], "nothing was configured or started")
        XCTAssertEqual(workspaceEntries(), [])
        XCTAssertEqual(try stamp(hdr), before)
    }

    func testRuntimeApertureMismatchIsRefused() async throws {
        // Same 1000×1800 presentation and colour, different aperture origin: a different source.
        let planned = try await write(Fixture(frames: 60, frameDuration: CMTime(value: 10, timescale: 600), cleanAperture: CGRect(x: 60, y: 100, width: 1000, height: 1800)))
        let other = try await write(Fixture(frames: 60, frameDuration: CMTime(value: 10, timescale: 600), cleanAperture: CGRect(x: 40, y: 20, width: 1000, height: 1800)))
        let plan = try await plan(for: planned)
        let (stages, hooks) = recordPaths()
        await expectError(.planDoesNotMatchSource) {
            try await AVFoundationWorkingMediaNormalizer(hooks: hooks).normalize(sourceURL: other, destinationURL: self.destination(), plan: plan)
        }
        XCTAssertEqual(stages.all, [])
        // A full-aperture source of another size is refused too.
        await expectError(.planDoesNotMatchSource) {
            try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: try await self.write(Fixture(frames: 60, frameDuration: CMTime(value: 10, timescale: 600))), destinationURL: self.destination(), plan: plan)
        }
        XCTAssertEqual(workspaceEntries(), [])
    }

    func testGeometryRenderFailureFailsTheRunWithoutOutput() async throws {
        let source = try await oddSDRSource()
        let before = try stamp(source)
        let plan = try await plan(for: source)
        let terminations = Recorder<WorkingMediaRunTermination>()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(
            observe: { if case .terminated(let reason) = $0 { terminations.append(reason) } },
            injectFault: { $0 == .render }))
        let target = destination()
        do {
            _ = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
            XCTFail("a failed render must never publish")
        } catch let error as WorkingMediaNormalizationError {
            guard case .readingFailed = error else { return XCTFail("expected readingFailed, got \(error)") }
        }
        XCTAssertEqual(terminations.all.count, 1, "one terminal outcome: \(terminations.all)")
        XCTAssertFalse(AVFoundationWorkingMediaNormalizer.itemExists(at: target))
        XCTAssertEqual(workspaceEntries(), [])
        XCTAssertEqual(try stamp(source), before)
    }

    func testRenderFailureRacingCancellationHasOneOutcome() async throws {
        let source = try await oddSDRSource()
        let plan = try await plan(for: source)
        for _ in 0..<3 {
            let terminations = Recorder<WorkingMediaRunTermination>()
            let cancelSwitch = CancelSwitch()
            let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(
                observe: { stage in
                    if stage == .pipelineStarted { cancelSwitch.fire() }
                    if case .terminated(let reason) = stage { terminations.append(reason) }
                },
                injectFault: { $0 == .render }))
            let target = destination()
            let task = Task { () -> WorkingMediaNormalizationResult in
                await cancelSwitch.waitUntilArmed()
                return try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
            }
            cancelSwitch.arm { task.cancel() }
            do {
                _ = try await task.value
                XCTFail("no result may be published")
            } catch is CancellationError {
            } catch let error as WorkingMediaNormalizationError {
                guard case .readingFailed = error else { return XCTFail("unexpected \(error)") }
            }
            XCTAssertEqual(terminations.all.count, 1, "\(terminations.all)")
            XCTAssertFalse(AVFoundationWorkingMediaNormalizer.itemExists(at: target))
        }
        XCTAssertEqual(workspaceEntries(), [])
    }

    // MARK: - F9: audio shorter than video, declared AAC bit rate

    func testAudioShorterThanVideoEndsNormally() async throws {
        // 1.2 s of video, 0.5 s of LPCM audio.
        let source = try await write(Fixture(frames: 36, audio: .lpcm(channels: 2, rate: 44_100), audioFrames: 22_050))
        let facts = try await inspector.inspect(url: source)
        let plan = try await plan(for: source)
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        XCTAssertEqual(facts.duration, .exact(plan.sourceDuration))
        XCTAssertTrue(plan.acceptedOutputDuration.contains(result.outputDuration), "\(result.outputDuration)")
        XCTAssertEqual(result.outputFacts.audio?.sampleRate, 48_000)
        XCTAssertEqual(result.outputFacts.audio?.channelCount, 2)
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: result.outputFacts, evidence: result.outputEvidence, plan: plan, sourceAudio: facts.audio), [])
    }

    func testDeclaredAACBitRateMatchesThePlan() async throws {
        for (channels, bitRate) in [(1, 96_000), (2, 128_000), (6, 128_000)] {
            let source = try await write(Fixture(frames: 36, audio: .lpcm(channels: channels, rate: 44_100), tones: Array([440.0, 660, 880, 110, 1320, 1760].prefix(channels))))
            let plan = try await plan(for: source)
            let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
            XCTAssertEqual(result.outputEvidence.aacDecoderConfiguration,
                           WorkingMediaAACDecoderConfiguration(audioObjectType: 2, averageBitRate: bitRate, maximumBitRate: bitRate), "\(channels) ch")
        }
    }

    // MARK: - F9: terminal-race stress (repeated, deterministic stage gates)

    private struct RaceOutcome { let error: Error?; let terminations: [WorkingMediaRunTermination]; let target: URL }

    private func race(source: URL, plan: WorkingMediaNormalizationPlan, cancelAt stage: WorkingMediaNormalizationStage?,
                      fault: WorkingMediaNormalizationFault? = nil, simulated: WorkingMediaSimulatedTerminalStatus? = nil) async throws -> RaceOutcome {
        let terminations = Recorder<WorkingMediaRunTermination>(), started = Recorder<Bool>()
        let cancelSwitch = CancelSwitch()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(
            observe: { observed in
                if observed == .pipelineStarted { started.append(true) }
                if let stage, observed == stage { cancelSwitch.fire() }
                if case .terminated(let reason) = observed { terminations.append(reason) }
            },
            injectFault: { fault != nil && $0 == fault },
            simulatedTerminalStatus: { started.all.isEmpty ? nil : simulated }))
        let target = destination()
        let task = Task { () -> WorkingMediaNormalizationResult in
            await cancelSwitch.waitUntilArmed()
            return try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
        }
        cancelSwitch.arm { task.cancel() }
        do {
            let result = try await task.value
            return RaceOutcome(error: nil, terminations: terminations.all, target: result.destinationURL)
        } catch {
            return RaceOutcome(error: error, terminations: terminations.all, target: target)
        }
    }

    func testTerminalRacesResolveExactlyOnce() async throws {
        let source = try await write(Fixture(frames: 36, audio: .lpcm(channels: 2, rate: 44_100)))
        let before = try stamp(source)
        let plan = try await plan(for: source)
        for iteration in 0..<4 {
            // Completion racing cancellation: cancellation after the streams finished still wins.
            for stage in [WorkingMediaNormalizationStage.willFinishWriting, .didFinishWriting] {
                let outcome = try await race(source: source, plan: plan, cancelAt: stage)
                XCTAssertTrue(outcome.error is CancellationError, "\(iteration) \(stage): \(String(describing: outcome.error))")
                XCTAssertEqual(outcome.terminations, [.streamsCompleted])
                XCTAssertFalse(AVFoundationWorkingMediaNormalizer.itemExists(at: outcome.target))
            }
            // Writer failure racing cancellation: one of the two wins, once, with no output.
            let writer = try await race(source: source, plan: plan, cancelAt: .pipelineStarted, simulated: .writerFailed)
            XCTAssertEqual(writer.terminations.count, 1, "\(iteration): \(writer.terminations)")
            if let error = writer.error as? WorkingMediaNormalizationError {
                guard case .writerFailed = error else { return XCTFail("\(error)") }
            } else { XCTAssertTrue(writer.error is CancellationError, "\(String(describing: writer.error))") }
            XCTAssertFalse(AVFoundationWorkingMediaNormalizer.itemExists(at: writer.target))
            // Reader failure racing stream completion: either a validated result or a failure, never both.
            let reader = try await race(source: source, plan: plan, cancelAt: nil, simulated: .readerFailed)
            XCTAssertEqual(reader.terminations.count, 1, "\(iteration): \(reader.terminations)")
            if let error = reader.error {
                guard case .readingFailed = error as? WorkingMediaNormalizationError else { return XCTFail("\(error)") }
                XCTAssertFalse(AVFoundationWorkingMediaNormalizer.itemExists(at: reader.target))
            } else {
                XCTAssertEqual(reader.terminations, [.streamsCompleted])
                try FileManager.default.removeItem(at: reader.target)
            }
            // Finish failure racing cancellation just before finishing: one outcome, no output.
            let finish = try await race(source: source, plan: plan, cancelAt: .willFinishWriting, fault: .finishWriting)
            XCTAssertTrue(finish.error is CancellationError || (finish.error as? WorkingMediaNormalizationError).map { if case .finishFailed = $0 { return true } else { return false } } == true,
                          "\(String(describing: finish.error))")
            XCTAssertEqual(finish.terminations, [.streamsCompleted])
            XCTAssertFalse(AVFoundationWorkingMediaNormalizer.itemExists(at: finish.target))
        }
        XCTAssertEqual(workspaceEntries(), [])
        XCTAssertEqual(try stamp(source), before)
    }

    func testReplacedRegularFileIsNeverRemoved() async throws {
        // The owned output is swapped for a foreign regular file after writing finished; a later
        // failure must not delete the foreign file (device / inode differ).
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        let target = destination()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(
            observe: { stage in
                guard stage == .didFinishWriting else { return }
                try? FileManager.default.removeItem(at: target)
                try? Data("foreign".utf8).write(to: target)
            },
            injectFault: { $0 == .outputValidation }))
        do {
            _ = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
            XCTFail("no result may be published")
        } catch let error as WorkingMediaNormalizationError {
            guard case .cleanupFailed(.identityChanged(let path), let preceding, false) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(path, target.path)
            XCTAssertNotNil(preceding, "the original failure is kept")
        }
        XCTAssertEqual(try Data(contentsOf: target), Data("foreign".utf8))
    }

    // MARK: - F3: timing evidence fails closed (pure)

    func testTimingEvidenceFailsClosed() throws {
        func t(_ v: Int64) -> MediaTime { try! MediaTime(value: v, timescale: 600) }
        let marker = WorkingMediaSampleTimingObservation(sampleCount: 0, presentationTimes: [t(0)])
        func frame(_ v: Int64) -> WorkingMediaSampleTimingObservation { .init(sampleCount: 1, presentationTimes: [t(v)]) }
        XCTAssertEqual(WorkingMediaOutputValidator.presentationTimes(from: [marker, frame(20), frame(0), frame(40), marker]), .times([t(0), t(20), t(40)]), "markers skipped, order fixed")
        XCTAssertEqual(WorkingMediaOutputValidator.presentationTimes(from: [frame(0), .init(sampleCount: 2, presentationTimes: [t(20), t(40)])]), .times([t(0), t(20), t(40)]), "multi-sample buffer")
        let broken: [(String, [WorkingMediaSampleTimingObservation])] = [
            ("unreadable timing", [frame(0), .init(sampleCount: 1, presentationTimes: nil), frame(40)]),
            ("empty timing", [frame(0), .init(sampleCount: 1, presentationTimes: []), frame(40)]),
            ("count mismatch", [frame(0), .init(sampleCount: 2, presentationTimes: [t(20)])]),
            ("extra entries", [frame(0), .init(sampleCount: 1, presentationTimes: [t(20), t(40)])]),
            ("non-numeric", [frame(0), .init(sampleCount: 1, presentationTimes: [nil])]),
            ("missing first", [.init(sampleCount: 1, presentationTimes: nil), frame(20), frame(40)]),
            ("missing final", [frame(0), frame(20), .init(sampleCount: 1, presentationTimes: nil)]),
            ("negative count", [.init(sampleCount: -1, presentationTimes: [])]),
        ]
        for (label, observations) in broken {
            XCTAssertEqual(WorkingMediaOutputValidator.presentationTimes(from: observations), .unavailable, label)
        }
        // Unavailable timing is a validation failure, never a pass over a subset.
        let plan = try syntheticPlan()
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: canonicalOutput(for: plan), evidence: evidence(plan, times: .unavailable), plan: plan, sourceAudio: nil), [.cadenceUnverifiable])
    }

    func testCadenceStartAndTrackCensus() throws {
        let plan = try syntheticPlan()
        let shifted = times(count: 36, value: 20, timescale: 600).map { $0 + (try! MediaTime(value: 20, timescale: 600)) }
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: canonicalOutput(for: plan), evidence: evidence(plan, times: .times(shifted)), plan: plan, sourceAudio: nil),
                       [.cadenceDoesNotStartAtZero(try MediaTime(value: 20, timescale: 600))])
        // Zero in another timescale is zero.
        let fine = (0..<36).map { try! MediaTime(value: Int64($0) * 1000, timescale: 30_000) }
        XCTAssertEqual(WorkingMediaOutputValidator.cadenceViolations(.times(fine), frameDuration: plan.outputFrameDuration), [])
        let extra = WorkingMediaOutputEvidence(avcProfileIndication: 100, videoPresentationTimes: canonicalEvidence(for: plan).videoPresentationTimes,
                                               trackCounts: .init(video: 1, audio: 1, other: 1), aacDecoderConfiguration: nil)
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: canonicalOutput(for: plan), evidence: extra, plan: plan, sourceAudio: nil), [.unexpectedTracks(video: 1, audio: 1, other: 1)])
    }

    func testAACDecoderConfigurationIsParsedAndEnforced() throws {
        func bytes(_ hex: String) -> [UInt8] { stride(from: 0, to: hex.count, by: 2).map { UInt8(hex.dropFirst($0).prefix(2), radix: 16)! } }
        // The exact cookies AVAssetWriter wrote on LunaTestphone for mono 96 kbps / stereo 128 kbps.
        let mono = bytes("038080802200000004808080144014001800000177000001770005808080021188068080800102")
        let stereo = bytes("0380808022000000048080801440140018000001f4000001f40005808080021190068080800102")
        XCTAssertEqual(WorkingMediaOutputValidator.aacDecoderConfiguration(fromMagicCookie: mono), .init(audioObjectType: 2, averageBitRate: 96_000, maximumBitRate: 96_000))
        XCTAssertEqual(WorkingMediaOutputValidator.aacDecoderConfiguration(fromMagicCookie: stereo), .init(audioObjectType: 2, averageBitRate: 128_000, maximumBitRate: 128_000))
        // A bare DecoderConfigDescriptor parses the same; truncation and garbage do not parse.
        XCTAssertEqual(WorkingMediaOutputValidator.aacDecoderConfiguration(fromMagicCookie: Array(stereo.dropFirst(8))), .init(audioObjectType: 2, averageBitRate: 128_000, maximumBitRate: 128_000))
        for count in [0, 5, 12, 20, stereo.count - 4] {
            XCTAssertNil(WorkingMediaOutputValidator.aacDecoderConfiguration(fromMagicCookie: Array(stereo.prefix(count))), "\(count) bytes")
        }
        XCTAssertNil(WorkingMediaOutputValidator.aacDecoderConfiguration(fromMagicCookie: [0x06, 0x01, 0x02]))
        // HE-AAC (object type 5) or a different declared rate fails a transcode plan.
        let plan = try syntheticPlan(fps: 30, audio: ImportAudioFacts(fourCC: "lpcm", sampleRate: 44_100, channelCount: 2))
        let output = canonicalOutput(for: plan, audio: ImportAudioFacts(fourCC: "aac ", sampleRate: 48_000, channelCount: 2))
        for wrong in [WorkingMediaAACDecoderConfiguration(audioObjectType: 5, averageBitRate: 128_000, maximumBitRate: 128_000),
                      WorkingMediaAACDecoderConfiguration(audioObjectType: 2, averageBitRate: 96_000, maximumBitRate: 96_000)] as [WorkingMediaAACDecoderConfiguration?] + [nil] {
            let evidence = WorkingMediaOutputEvidence(avcProfileIndication: 100, videoPresentationTimes: canonicalEvidence(for: plan).videoPresentationTimes,
                                                      trackCounts: .init(video: 1, audio: 1, other: 0), aacDecoderConfiguration: wrong)
            XCTAssertEqual(WorkingMediaOutputValidator.violations(of: output, evidence: evidence, plan: plan, sourceAudio: nil), [.audioEncodingMismatch(wrong)])
        }
    }

    // MARK: - ADR-049 Revision 1: runtime description consensus and scaled transforms

    /// A copy of `description` with some extensions replaced (nil removes one). Used only through the
    /// runtime-description seam: AVAssetWriter cannot write a track whose descriptions change, so no
    /// real multi-description file is claimed here.
    private func modified(_ description: CMFormatDescription, _ changes: [CFString: Any?]) throws -> CMFormatDescription {
        let extensions = NSMutableDictionary(dictionary: CMFormatDescriptionGetExtensions(description) as NSDictionary? ?? [:])
        for (key, value) in changes { if let value { extensions[key] = value } else { extensions.removeObject(forKey: key) } }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        var out: CMFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreate(allocator: nil, codecType: CMFormatDescriptionGetMediaSubType(description), width: dimensions.width,
                                                      height: dimensions.height, extensions: extensions, formatDescriptionOut: &out), noErr)
        return try XCTUnwrap(out)
    }

    private func firstVideoDescription(_ url: URL) async throws -> CMFormatDescription {
        let descriptions = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first?.load(.formatDescriptions)
        return try XCTUnwrap(descriptions?.first)
    }

    /// Runs `plan` on `source` with the run's loaded descriptions replaced by `descriptions`.
    private func runWithDescriptions(_ source: URL, plan: WorkingMediaNormalizationPlan, _ descriptions: [CMFormatDescription])
        async throws -> (result: Result<WorkingMediaNormalizationResult, Error>, stages: [WorkingMediaNormalizationStage]) {
        let stages = Recorder<WorkingMediaNormalizationStage>()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(
            observe: { stages.append($0) }, currentVideoFormatDescriptions: { _ in descriptions }))
        do {
            return (.success(try await normalizer.normalize(sourceURL: source, destinationURL: destination(), plan: plan)), stages.all)
        } catch {
            return (.failure(error), stages.all)
        }
    }

    private func assertRefusedBeforeMediaWork(_ outcome: (result: Result<WorkingMediaNormalizationResult, Error>, stages: [WorkingMediaNormalizationStage]),
                                              _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let error) = outcome.result else { return XCTFail("\(label): must be refused", file: file, line: line) }
        XCTAssertEqual(error as? WorkingMediaNormalizationError, .planDoesNotMatchSource, label, file: file, line: line)
        // The refusal precedes every media stage; the only event is the run's own abort bookkeeping.
        XCTAssertTrue(outcome.stages.allSatisfy { $0 == .terminated(.cancelled) }, "\(label): no composition, reader or writer: \(outcome.stages)", file: file, line: line)
    }

    func testRuntimeDescriptionsMustAgreeWithAGeometryPlan() async throws {
        let source = try await oddSDRSource()
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.renderPath, .sdrApertureGeometry)
        let original = try await firstVideoDescription(source)
        let shiftedAperture: [CFString: Any] = [kCMFormatDescriptionKey_CleanApertureWidth: 1080, kCMFormatDescriptionKey_CleanApertureHeight: 1919,
                                                kCMFormatDescriptionKey_CleanApertureHorizontalOffset: 0, kCMFormatDescriptionKey_CleanApertureVerticalOffset: 0.25]
        let changed: [(String, [CFString: Any?])] = [
            ("later HLG", [kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG]),
            ("later PQ", [kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ]),
            ("later Rec.2020", [kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020]),
            ("later Dolby Vision", [kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: ["dvvC": Data(repeating: 0, count: 24)]]),
            ("later full aperture", [kCMFormatDescriptionExtension_CleanAperture: nil]),
            ("later shifted aperture", [kCMFormatDescriptionExtension_CleanAperture: shiftedAperture]),
        ]
        for (label, change) in changed {
            assertRefusedBeforeMediaWork(try await runWithDescriptions(source, plan: plan, [original, try modified(original, change)]), label)
        }
        assertRefusedBeforeMediaWork(try await runWithDescriptions(source, plan: plan, []), "no description")
        XCTAssertEqual(workspaceEntries(), [])
        // Two agreeing descriptions are the ordinary case.
        let agreed = try await runWithDescriptions(source, plan: plan, [original, original])
        guard case .success(let result) = agreed.result else { return XCTFail("matching descriptions must normalize: \(agreed.result)") }
        assertCanonical(result, plan: plan)
    }

    func testRuntimeHDRDescriptionsOnTheBuiltInPathNeedGeometryAgreementOnly() async throws {
        // A full-aperture 10-bit HLG / Rec.2020 HEVC source at 60 fps: its plan already carries the
        // source-wide HDR reason (ahead of frame rate) and takes the built-in tone-mapping path.
        let source = try await write(Fixture(frames: 60, frameDuration: CMTime(value: 10, timescale: 600), video: .hevcHLG))
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.renderPath, .builtInToneMap)
        // What the encoded description declares (VideoToolbox's 10-bit HLG HEVC encode on LunaTestphone
        // also writes a 10-bit component depth and a Dolby Vision configuration record — a declared
        // signal only, not a Dolby Vision quality validation).
        XCTAssertEqual(plan.reasons, [.hdr(signals: [.hlgTransfer, .rec2020Primaries, .rec2020Matrix, .bitDepthAbove8, .highBitDepthProfile, .dolbyVision]),
                                      .frameRate(nominal: 60)])
        let original = try await firstVideoDescription(source)
        // Agreeing full-aperture HDR descriptions — the ones the plan represents — are valid on this path…
        let accepted = try await runWithDescriptions(source, plan: plan, [original, original])
        guard case .success(let result) = accepted.result else { return XCTFail("built-in path with agreeing HDR descriptions: \(accepted.result)") }
        assertCanonical(result, plan: plan)
        // …but a later non-full aperture is not.
        let nonFull = try modified(original, [kCMFormatDescriptionExtension_CleanAperture: [
            kCMFormatDescriptionKey_CleanApertureWidth: 1080, kCMFormatDescriptionKey_CleanApertureHeight: 1918,
            kCMFormatDescriptionKey_CleanApertureHorizontalOffset: 0, kCMFormatDescriptionKey_CleanApertureVerticalOffset: 0] as [CFString: Any]])
        assertRefusedBeforeMediaWork(try await runWithDescriptions(source, plan: plan, [original, nonFull]), "later non-full aperture")
    }

    /// A copy of `description` with another codec subtype (same dimensions and extensions).
    private func recoded(_ description: CMFormatDescription, as codec: String) throws -> CMFormatDescription {
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        let code = codec.utf8.reduce(FourCharCode(0)) { ($0 << 8) | FourCharCode($1) }
        var out: CMFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreate(allocator: nil, codecType: code, width: dimensions.width, height: dimensions.height,
                                                      extensions: CMFormatDescriptionGetExtensions(description), formatDescriptionOut: &out), noErr)
        return try XCTUnwrap(out)
    }

    func testRuntimeDescriptionsMustRemainSupportedCodecs() async throws {
        for source in [try await oddSDRSource(), try await write(Fixture(frames: 60, frameDuration: CMTime(value: 10, timescale: 600)))] {
            let plan = try await plan(for: source)
            let original = try await firstVideoDescription(source)
            for codec in ["apcn", "jpeg", "zzzz"] {
                assertRefusedBeforeMediaWork(try await runWithDescriptions(source, plan: plan, [original, try recoded(original, as: codec)]), "\(plan.renderPath) later \(codec)")
            }
            // Another supported family is still the source preflight accepted.
            let mixed = try await runWithDescriptions(source, plan: plan, [original, try recoded(original, as: "avc3")])
            guard case .success(let result) = mixed.result else { return XCTFail("supported mix must normalize: \(mixed.result)") }
            assertCanonical(result, plan: plan)
        }
        XCTAssertEqual(workspaceEntries().filter { !$0.hasPrefix("output-") }, [])
    }

    func testRuntimeTransformMismatchIsRefused() async throws {
        let planned = try await write(Fixture(width: 1920, height: 1080, transform: Self.rotate90, frames: 60, frameDuration: CMTime(value: 10, timescale: 600)))
        let rotate270 = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)
        let other = try await write(Fixture(width: 1920, height: 1080, transform: rotate270, frames: 60, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: planned)
        let stages = Recorder<WorkingMediaNormalizationStage>()
        await expectError(.planDoesNotMatchSource) {
            try await AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stages.append($0) }))
                .normalize(sourceURL: other, destinationURL: self.destination(), plan: plan)
        }
        XCTAssertEqual(stages.all, [])
        XCTAssertEqual(workspaceEntries(), [])
    }

    func testScaledAxisAlignedTransformsNormalizeOnBothPaths() async throws {
        // Built-in path: non-uniform scale 0.75 × 1 → presented 810×1920.
        let scaled = Fixture(transform: CGAffineTransform(scaleX: 0.75, y: 1), frames: 60, frameDuration: CMTime(value: 10, timescale: 600))
        let scaledSource = try await write(scaled)
        let scaledPlan = try await plan(for: scaledSource)
        XCTAssertEqual(scaledPlan.renderPath, .builtInToneMap)
        XCTAssertEqual(scaledPlan.raster.output, WorkingMediaRaster(width: 810, height: 1920))
        let scaledResult = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: scaledSource, destinationURL: destination(), plan: scaledPlan)
        assertCanonical(scaledResult, plan: scaledPlan)
        try await assertMarker(scaledResult.destinationURL, fixture: scaled, plan: scaledPlan)

        // Built-in path: 90° rotation with scale 1 × 0.9 → presented 1080×1728.
        let rotated = Fixture(width: 1920, height: 1080, transform: Self.rotate90.concatenating(CGAffineTransform(scaleX: 1, y: 0.9)),
                              frames: 60, frameDuration: CMTime(value: 10, timescale: 600))
        let rotatedSource = try await write(rotated)
        let rotatedPlan = try await plan(for: rotatedSource)
        XCTAssertEqual(rotatedPlan.raster.output, WorkingMediaRaster(width: 1080, height: 1728))
        let rotatedResult = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: rotatedSource, destinationURL: destination(), plan: rotatedPlan)
        assertCanonical(rotatedResult, plan: rotatedPlan)
        try await assertMarker(rotatedResult.destinationURL, fixture: rotated, plan: rotatedPlan)

        // Geometry path: offset clean aperture with scale 0.8 × 1 → presented 800×1800, whole aperture kept.
        let geometry = Fixture(transform: CGAffineTransform(scaleX: 0.8, y: 1), frames: 60, frameDuration: CMTime(value: 10, timescale: 600),
                               pattern: .aperture, cleanAperture: CGRect(x: 60, y: 100, width: 1000, height: 1800))
        let geometrySource = try await write(geometry)
        let geometryPlan = try await plan(for: geometrySource)
        XCTAssertEqual(geometryPlan.renderPath, .sdrApertureGeometry)
        XCTAssertEqual(geometryPlan.raster.output, WorkingMediaRaster(width: 800, height: 1800))
        let geometryResult = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: geometrySource, destinationURL: destination(), plan: geometryPlan)
        assertCanonical(geometryResult, plan: geometryPlan)
        let decoded = try await frame(geometryResult.destinationURL)
        XCTAssertEqual(decoded.width, 800); XCTAssertEqual(decoded.height, 1800)
        assertApertureEdges(decoded)
    }

    // MARK: - Output validator (pure)

    private func canonicalOutput(for plan: WorkingMediaNormalizationPlan, audio: ImportAudioFacts? = nil) -> ImportSourceFacts {
        ImportSourceFacts(
            duration: .exact(plan.sourceDuration), isReadable: true, isPlayable: true, isExportable: true, hasProtectedContent: false,
            hasVideoTrack: true, hasAudioTrack: audio != nil, container: .quickTime, videoCodec: .h264(fourCC: "avc1"),
            naturalWidth: plan.raster.output.width, naturalHeight: plan.raster.output.height, preferredTransform: .identity,
            nominalFrameRate: 30, minimumFrameDuration: plan.outputFrameDuration, bitsPerComponent: nil, highBitDepthProfile: .no,
            fullRangeVideo: .no, colorPrimaries: .rec709, transferFunction: .rec709, ycbcrMatrix: .rec709,
            hasDolbyVisionConfiguration: false, ancillaryHDRMetadata: [],
            aperture: .classify(encodedWidth: plan.raster.output.width, encodedHeight: plan.raster.output.height, cleanAperture: nil, pixelAspectRatio: nil),
            audio: audio, byteCount: 1000, modificationDate: nil)
    }

    /// Evidence with the track census the plan implies (one video track, audio only if planned).
    private func evidence(_ plan: WorkingMediaNormalizationPlan, profile: UInt8? = 100, times: WorkingMediaOutputEvidence.PresentationTimes) -> WorkingMediaOutputEvidence {
        WorkingMediaOutputEvidence(avcProfileIndication: profile, videoPresentationTimes: times,
                                   trackCounts: .init(video: 1, audio: plan.audio == .none ? 0 : 1, other: 0), aacDecoderConfiguration: aacConfiguration(for: plan))
    }

    /// The decoder configuration a correct transcode declares (nil for none / passthrough).
    private func aacConfiguration(for plan: WorkingMediaNormalizationPlan) -> WorkingMediaAACDecoderConfiguration? {
        guard case .transcode(let settings) = plan.audio else { return nil }
        return WorkingMediaAACDecoderConfiguration(audioObjectType: 2, averageBitRate: settings.bitRate, maximumBitRate: settings.bitRate)
    }

    /// `count` presentation times at exact multiples of `value / timescale`.
    private func times(count: Int, value: Int64, timescale: Int32) -> [MediaTime] {
        (0..<count).map { try! MediaTime(value: Int64($0) * value, timescale: timescale) }
    }

    private func canonicalEvidence(for plan: WorkingMediaNormalizationPlan, profile: UInt8? = 100) -> WorkingMediaOutputEvidence {
        evidence(plan, profile: profile, times: .times(times(count: 36, value: plan.outputFrameDuration.value, timescale: plan.outputFrameDuration.timescale)))
    }

    func testValidatorAcceptsTheCanonicalOutput() throws {
        let plan = try syntheticPlan()
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: canonicalOutput(for: plan), evidence: canonicalEvidence(for: plan), plan: plan, sourceAudio: nil), [])
    }

    func testValidatorRejectsEveryContractBreach() throws {
        let plan = try syntheticPlan()
        let good = canonicalOutput(for: plan), evidence = canonicalEvidence(for: plan)
        func check(_ mutate: (inout ImportSourceFacts) -> Void, _ expected: WorkingMediaOutputViolation, line: UInt = #line) {
            var facts = good
            mutate(&facts)
            XCTAssertTrue(WorkingMediaOutputValidator.violations(of: facts, evidence: evidence, plan: plan, sourceAudio: nil).contains(expected), "\(expected)", line: line)
        }
        check({ $0.byteCount = 0 }, .emptyFile)
        check({ $0.container = .isoBaseMedia(brands: ["mp42"]) }, .notQuickTime(.isoBaseMedia(brands: ["mp42"])))
        check({ $0.videoCodec = .hevc(fourCC: "hvc1") }, .notH264(.hevc(fourCC: "hvc1")))
        check({ $0.videoCodec = .h264(fourCC: "avc3") }, .notH264(.h264(fourCC: "avc3")))
        check({ $0.isPlayable = false }, .unusable)
        check({ $0.hasVideoTrack = false }, .unusable)
        check({ $0.hasProtectedContent = true }, .protectedContent)
        check({ $0.naturalWidth = 1078 }, .rasterMismatch(expected: plan.raster.output, actualWidth: 1078, actualHeight: 1920))
        check({ $0.preferredTransform = ImportAffineTransform(Self.mirrorX) }, .transformNotIdentity)
        check({ $0.transferFunction = .hlg }, .colorNotRec709)
        check({ $0.colorPrimaries = .rec2020 }, .colorNotRec709)
        check({ $0.ycbcrMatrix = .unknown }, .colorNotRec709)
        check({ $0.fullRangeVideo = .yes }, .fullRangeVideo)
        check({ $0.transferFunction = .pq }, .hdrSignalling)
        check({ $0.bitsPerComponent = 10 }, .hdrSignalling)
        check({ $0.highBitDepthProfile = .yes }, .hdrSignalling)
        check({ $0.hasDolbyVisionConfiguration = true }, .hdrSignalling)
        check({ $0.ancillaryHDRMetadata = [.ambientViewingEnvironment] }, .hdrSignalling)
        check({ $0.duration = .invalid }, .invalidDuration)
        check({ $0.hasAudioTrack = true; $0.audio = ImportAudioFacts(fourCC: "aac ", sampleRate: 48_000, channelCount: 2) }, .audioMismatch)
    }

    func testValidatorRequiresH264HighProfile() throws {
        let plan = try syntheticPlan()
        let output = canonicalOutput(for: plan)
        func violations(_ profile: UInt8?) -> [WorkingMediaOutputViolation] {
            WorkingMediaOutputValidator.violations(of: output, evidence: canonicalEvidence(for: plan, profile: profile), plan: plan, sourceAudio: nil)
        }
        XCTAssertEqual(violations(100), [])
        for profile: UInt8? in [66, 77, 110, nil] {   // Baseline, Main, High 10, absent / malformed
            XCTAssertEqual(violations(profile), [.notHighProfile(profileIndication: profile)], "\(String(describing: profile))")
        }
        // avcC parsing: version 1, then the profile byte; short or wrong-version records give nil.
        func record(_ profile: UInt8, version: UInt8 = 1) -> Data { Data([version, profile, 0x00, 0x28, 0xFF, 0xE1, 0x00]) }
        XCTAssertEqual(WorkingMediaOutputValidator.avcProfileIndication(fromAvcC: record(100)), 100)
        XCTAssertEqual(WorkingMediaOutputValidator.avcProfileIndication(fromAvcC: record(66)), 66)
        XCTAssertEqual(WorkingMediaOutputValidator.avcProfileIndication(fromAvcC: record(77)), 77)
        XCTAssertEqual(WorkingMediaOutputValidator.avcProfileIndication(fromAvcC: record(110)), 110)
        XCTAssertNil(WorkingMediaOutputValidator.avcProfileIndication(fromAvcC: nil))
        XCTAssertNil(WorkingMediaOutputValidator.avcProfileIndication(fromAvcC: Data()))
        XCTAssertNil(WorkingMediaOutputValidator.avcProfileIndication(fromAvcC: Data([1, 100])))
        XCTAssertNil(WorkingMediaOutputValidator.avcProfileIndication(fromAvcC: record(100, version: 0)))
        // A non-avc1 output fails even with a High profile byte.
        var hevc = output
        hevc.videoCodec = .hevc(fourCC: "hvc1")
        XCTAssertTrue(WorkingMediaOutputValidator.violations(of: hevc, evidence: canonicalEvidence(for: plan), plan: plan, sourceAudio: nil).contains(.notH264(.hevc(fourCC: "hvc1"))))
    }

    func testCadenceIsProvenFromActualPresentationTimes() throws {
        for (value, timescale) in [(Int64(1), Int32(24)), (1, 25), (1001, 30_000), (1, 30)] {
            let frame = try MediaTime(value: value, timescale: timescale)
            XCTAssertEqual(WorkingMediaOutputValidator.cadenceViolations(.times(times(count: 30, value: value, timescale: timescale)), frameDuration: frame), [], "\(frame)")
            // Same instants in a finer timescale still pass (rational comparison, not structural).
            XCTAssertEqual(WorkingMediaOutputValidator.cadenceViolations(.times(times(count: 30, value: value * 120, timescale: timescale * 120)), frameDuration: frame), [])
            // One middle interval one tick fast (and the next one tick slow) fails.
            var fast = times(count: 30, value: value * 120, timescale: timescale * 120)
            fast[10] = try MediaTime(value: fast[10].value - 1, timescale: fast[10].timescale)
            XCTAssertEqual(WorkingMediaOutputValidator.cadenceViolations(.times(fast), frameDuration: frame),
                           [.cadenceMismatch(index: 9, interval: try MediaTime(value: value * 120 - 1, timescale: timescale * 120))], "\(frame) fast")
            var slow = times(count: 30, value: value * 120, timescale: timescale * 120)
            slow[10] = try MediaTime(value: slow[10].value + 1, timescale: slow[10].timescale)
            XCTAssertEqual(WorkingMediaOutputValidator.cadenceViolations(.times(slow), frameDuration: frame),
                           [.cadenceMismatch(index: 9, interval: try MediaTime(value: value * 120 + 1, timescale: timescale * 120))], "\(frame) slow")
        }
    }

    func testCadenceEdgeCases() throws {
        let frame = try MediaTime(value: 1, timescale: 30)
        XCTAssertEqual(WorkingMediaOutputValidator.cadenceViolations(.unavailable, frameDuration: frame), [.cadenceUnverifiable])
        XCTAssertEqual(WorkingMediaOutputValidator.cadenceViolations(.times([]), frameDuration: frame), [.cadenceUnverifiable])
        // ADR-048 R1 / R2: one sample at zero has no interval; the grid end decides its validity.
        XCTAssertEqual(WorkingMediaOutputValidator.cadenceViolations(.times([.zero]), frameDuration: frame), [])
        let duplicate = [MediaTime.zero, try MediaTime(value: 1, timescale: 30), try MediaTime(value: 20, timescale: 600)]
        XCTAssertEqual(WorkingMediaOutputValidator.cadenceViolations(.times(duplicate), frameDuration: frame), [.timestampsNotIncreasing])

        // A final frame truncated by the session end is not an interval: 29 frames at 1/24 s with a
        // 702/600 s output duration pass.
        let plan = try syntheticPlan(fps: 24, audio: ImportAudioFacts(fourCC: "lpcm", sampleRate: 44_100, channelCount: 2), duration: try MediaTime(value: 702, timescale: 600))
        XCTAssertEqual(plan.outputFrameDuration, try MediaTime(value: 1, timescale: 24))
        let output = canonicalOutput(for: plan, audio: ImportAudioFacts(fourCC: "aac ", sampleRate: 48_000, channelCount: 2))
        let evidence = evidence(plan, times: .times(times(count: 29, value: 1, timescale: 24)))
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: output, evidence: evidence, plan: plan, sourceAudio: nil), [])
    }

    func testFrameMetadataNeverProvesOrDisprovesCadence() throws {
        let plan = try syntheticPlan()   // 1/30
        var output = canonicalOutput(for: plan)
        // Metadata claims a clean 30 fps, the actual timestamps contain a 1/60 s interval: rejected.
        var lying = times(count: 36, value: 20, timescale: 600)
        lying[12] = try MediaTime(value: 230, timescale: 600)
        let mismatch = WorkingMediaOutputValidator.violations(of: output, evidence: evidence(plan, times: .times(lying)), plan: plan, sourceAudio: nil)
        XCTAssertEqual(mismatch, [.cadenceMismatch(index: 11, interval: try MediaTime(value: 10, timescale: 600))])
        // Noisy metadata (minimum 1/60 s, nominal 29.4) with exact timestamps: accepted.
        output.minimumFrameDuration = try MediaTime(value: 1, timescale: 60)
        output.nominalFrameRate = 29.4
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: output, evidence: canonicalEvidence(for: plan), plan: plan, sourceAudio: nil), [])
    }

    func testValidatorDurationWindowBoundaries() throws {
        let plan = try syntheticPlan()   // source 720/600 = 1.2 s
        func violations(_ duration: MediaTime) -> [WorkingMediaOutputViolation] {
            var facts = canonicalOutput(for: plan)
            facts.duration = .exact(duration)
            return WorkingMediaOutputValidator.violations(of: facts, evidence: canonicalEvidence(for: plan), plan: plan, sourceAudio: nil)
        }
        XCTAssertEqual(violations(try MediaTime(value: 720, timescale: 600)), [])
        XCTAssertEqual(violations(try MediaTime(value: 740, timescale: 600)), [])    // exactly +1/30 s
        XCTAssertEqual(violations(try MediaTime(value: 741, timescale: 600)), [.durationOutsideWindow(try MediaTime(value: 741, timescale: 600))])
        XCTAssertEqual(violations(try MediaTime(value: 719, timescale: 600)), [.durationOutsideWindow(try MediaTime(value: 719, timescale: 600))])
    }

    func testValidatorAudioRules() throws {
        let aac = ImportAudioFacts(fourCC: "aac ", sampleRate: 44_100, channelCount: 2)
        let passthrough = try syntheticPlan(audio: aac)
        XCTAssertEqual(passthrough.audio, .passthroughAAC)
        let passEvidence = canonicalEvidence(for: passthrough)
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: canonicalOutput(for: passthrough, audio: aac), evidence: passEvidence, plan: passthrough, sourceAudio: aac), [])
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: canonicalOutput(for: passthrough, audio: ImportAudioFacts(fourCC: "aac ", sampleRate: 48_000, channelCount: 2)), evidence: passEvidence, plan: passthrough, sourceAudio: aac), [.audioMismatch])
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: canonicalOutput(for: passthrough), evidence: passEvidence, plan: passthrough, sourceAudio: aac), [.audioMismatch])

        let lpcm = ImportAudioFacts(fourCC: "lpcm", sampleRate: 44_100, channelCount: 6)
        let transcode = try syntheticPlan(audio: lpcm)
        let transEvidence = canonicalEvidence(for: transcode)
        let stereo48 = ImportAudioFacts(fourCC: "aac ", sampleRate: 48_000, channelCount: 2)
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: canonicalOutput(for: transcode, audio: stereo48), evidence: transEvidence, plan: transcode, sourceAudio: lpcm), [])
        for wrong in [ImportAudioFacts(fourCC: "aac ", sampleRate: 44_100, channelCount: 2), ImportAudioFacts(fourCC: "aac ", sampleRate: 48_000, channelCount: 6), ImportAudioFacts(fourCC: "lpcm", sampleRate: 48_000, channelCount: 2)] {
            XCTAssertEqual(WorkingMediaOutputValidator.violations(of: canonicalOutput(for: transcode, audio: wrong), evidence: transEvidence, plan: transcode, sourceAudio: lpcm), [.audioMismatch], "\(wrong)")
        }
    }

    // MARK: - Cadence grid and frame hold (ADR-048 Revision 1)

    /// 0, 20, …, 700, then a camera-like 21/600 step: 721, 741, … (`extra` frames), timescale 600.
    private static func jitteredTimes(extra: Int) -> [CMTime] {
        (0...35).map { CMTime(value: Int64($0) * 20, timescale: 600) } + (0..<extra).map { CMTime(value: 721 + Int64($0) * 20, timescale: 600) }
    }

    /// 40 targets (0 … 780/600) over 40 jittered frames: the composition rounds 721 up to 740, so
    /// target 36 (720/600) holds composed frame 35 and target 37 shows composed frame 36.
    private static let jitteredSchedule: [Scheduled] =
        (0..<36).map { Scheduled(target: $0, sourceFrame: $0, held: false) }
        + [Scheduled(target: 36, sourceFrame: 35, held: true), Scheduled(target: 37, sourceFrame: 36, held: false),
           Scheduled(target: 38, sourceFrame: 37, held: false), Scheduled(target: 39, sourceFrame: 38, held: false)]

    private static func jitteredHDRFixture() -> Fixture {
        Fixture(width: 540, height: 960, video: .hevcHLG, endTime: CMTime(value: 800, timescale: 600), pattern: .frameLevel,
                presentationTimes: jitteredTimes(extra: 4))
    }

    struct Scheduled: Equatable, CustomStringConvertible {
        let target: Int, sourceFrame: Int, held: Bool
        var description: String { "\(target)←\(sourceFrame)\(held ? " held" : "")" }
    }

    private func scheduled(_ stages: Recorder<WorkingMediaNormalizationStage>) -> [Scheduled] {
        stages.all.compactMap { if case .videoFrameScheduled(let target, let frame, let held) = $0 { return Scheduled(target: target, sourceFrame: frame, held: held) } else { return nil } }
    }

    private func assertGrid(_ result: WorkingMediaNormalizationResult, count: Int, step: MediaTime, file: StaticString = #filePath, line: UInt = #line) throws {
        guard case .times(let times) = result.outputEvidence.videoPresentationTimes else { return XCTFail("no timestamps", file: file, line: line) }
        XCTAssertEqual(times.count, count, "output video samples", file: file, line: line)
        for (k, time) in times.enumerated() {
            let expected = try MediaTime(value: step.value * Int64(k), timescale: step.timescale)
            XCTAssertFalse(time < expected || expected < time, "sample \(k) at \(time), expected \(expected)", file: file, line: line)
        }
    }

    private func assertSameInstant(_ actual: MediaTime, _ expected: MediaTime, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(actual < expected || expected < actual, "\(actual) ≠ \(expected)", file: file, line: line)
    }

    /// Presentation time and centre-patch mean luminance of every decoded output video frame.
    private func decodedLevels(_ url: URL) async throws -> [(time: CMTime, level: Double)] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var levels: [(time: CMTime, level: Double)] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
            let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            var sum = 0
            for row in (height / 2 - 32)..<(height / 2 + 32) {
                for column in (width / 2 - 32)..<(width / 2 + 32) {
                    let pixel = base + row * bytesPerRow + column * 4
                    sum += Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            levels.append((CMSampleBufferGetPresentationTimeStamp(sample), Double(sum) / Double(64 * 64 * 3)))
        }
        XCTAssertEqual(reader.status, .completed)
        return levels.sorted { CMTimeCompare($0.time, $1.time) < 0 }
    }

    /// The held target decodes to its predecessor's image and the next target to a new one. Flat
    /// frames survive H.264 almost exactly, so a re-encoded repeat stays within 1 code of mean
    /// luminance, while adjacent source frames differ by a 5-code (SDR) / 16-code 10-bit (HDR) step.
    private func assertHeldContent(_ url: URL, heldTarget: Int, newStep minimum: Double, file: StaticString = #filePath, line: UInt = #line) async throws {
        let levels = try await decodedLevels(url)
        let held = abs(levels[heldTarget].level - levels[heldTarget - 1].level)
        let fresh = abs(levels[heldTarget + 1].level - levels[heldTarget].level)
        let context = "levels[\(heldTarget - 1)...\(heldTarget + 1)] = \(levels[(heldTarget - 1)...(heldTarget + 1)].map { String(format: "%.2f", $0.level) })"
        XCTAssertLessThanOrEqual(held, 1.0, "held target \(heldTarget) must show its predecessor's image; \(context)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(fresh, minimum, "target \(heldTarget + 1) must show the newly available frame; \(context)", file: file, line: line)
    }

    func testJitteredHDRSourceHoldsTheSkippedTargetOnTheBuiltInPath() async throws {
        let source = try await write(Self.jitteredHDRFixture())
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.renderPath, .builtInToneMap)
        XCTAssertEqual(plan.outputFrameDuration, try MediaTime(value: 1, timescale: 30))
        assertSameInstant(plan.sourceDuration, try MediaTime(value: 800, timescale: 600))
        let stages = Recorder<WorkingMediaNormalizationStage>()
        let result = try await AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stages.append($0) }))
            .normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        XCTAssertEqual(scheduled(stages), Self.jitteredSchedule)
        try assertGrid(result, count: 40, step: try MediaTime(value: 20, timescale: 600))
        assertSameInstant(result.outputDuration, try MediaTime(value: 800, timescale: 600))
        try await assertHeldContent(result.destinationURL, heldTarget: 36, newStep: 1.5)
    }

    func testJitteredSDRSourceHoldsTheSkippedTargetOnTheGeometryPath() async throws {
        let f = Fixture(audio: .lpcm(channels: 2, rate: 44_100), endTime: CMTime(value: 800, timescale: 600), pattern: .frameLevel,
                        cleanAperture: CGRect(x: 0, y: 0.5, width: 1080, height: 1919), presentationTimes: Self.jitteredTimes(extra: 4))
        let source = try await write(f)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.renderPath, .sdrApertureGeometry)
        XCTAssertEqual(plan.outputFrameDuration, try MediaTime(value: 1, timescale: 30))
        let stages = Recorder<WorkingMediaNormalizationStage>()
        let result = try await AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stages.append($0) }))
            .normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        XCTAssertTrue(stages.all.contains(.videoPathConfigured(.sdrApertureGeometry, customCompositor: true)))
        XCTAssertEqual(scheduled(stages), Self.jitteredSchedule)
        try assertGrid(result, count: 40, step: try MediaTime(value: 20, timescale: 600))
        try await assertHeldContent(result.destinationURL, heldTarget: 36, newStep: 3.0)
    }

    func testCadenceGridAtTwentyFourTwentyFiveNTSCAndThirtyFps() async throws {
        // The 29.97 fixture stores its frames in a 30000 timescale so 1001/30000 is its exact minimum
        // frame duration (in the default 600 timescale it would be rounded).
        let cases: [(CMTime, MediaTime)] = [
            (CMTime(value: 25, timescale: 600), try MediaTime(value: 1, timescale: 24)),
            (CMTime(value: 24, timescale: 600), try MediaTime(value: 1, timescale: 25)),
            (CMTime(value: 1001, timescale: 30_000), try MediaTime(value: 1001, timescale: 30_000)),
            (CMTime(value: 20, timescale: 600), try MediaTime(value: 1, timescale: 30)),
        ]
        for (frameDuration, expected) in cases {
            let source = try await write(Fixture(width: 540, height: 960, frames: 36, frameDuration: frameDuration, audio: .lpcm(channels: 2, rate: 48_000),
                                                  mediaTimeScale: frameDuration.timescale))
            let plan = try await plan(for: source)
            XCTAssertEqual(plan.outputFrameDuration, expected)
            let stages = Recorder<WorkingMediaNormalizationStage>()
            let result = try await AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stages.append($0) }))
                .normalize(sourceURL: source, destinationURL: destination(), plan: plan)
            assertCanonical(result, plan: plan)
            XCTAssertEqual(scheduled(stages), (0..<36).map { Scheduled(target: $0, sourceFrame: $0, held: false) }, "\(expected)")
            try assertGrid(result, count: 36, step: expected)
        }
    }

    func testSixtyFpsSourceIsScheduledOnTheThirtyFpsGrid() async throws {
        let source = try await write(Fixture(width: 540, height: 960, frames: 72, frameDuration: CMTime(value: 10, timescale: 600)))
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.reasons, [.frameRate(nominal: 60)])
        let stages = Recorder<WorkingMediaNormalizationStage>()
        let result = try await AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stages.append($0) }))
            .normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        try assertGrid(result, count: 36, step: try MediaTime(value: 1, timescale: 30))
        let picks = scheduled(stages)
        XCTAssertEqual(picks.map(\.target), Array(0..<36), "\(picks)")
        XCTAssertEqual(picks.filter(\.held), [], "\(picks)")
    }

    func testAudioPastTheLastFullIntervalExtendsTheGridWithAHeldFrame() async throws {
        // 1.2 s of video, 1.21 s (726/600) of audio: targets 0 … 720/600; 720/600 holds frame 35 for 6/600.
        let source = try await write(Fixture(width: 540, height: 960, frames: 36, audio: .lpcm(channels: 2, rate: 48_000), audioFrames: 58_080))
        let plan = try await plan(for: source)
        assertSameInstant(plan.sourceDuration, try MediaTime(value: 726, timescale: 600))
        let stages = Recorder<WorkingMediaNormalizationStage>()
        let result = try await AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stages.append($0) }))
            .normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        try assertGrid(result, count: 37, step: try MediaTime(value: 20, timescale: 600))
        XCTAssertEqual(scheduled(stages).last, Scheduled(target: 36, sourceFrame: 35, held: true))
        XCTAssertEqual(scheduled(stages).filter(\.held).map(\.target), [36])
        assertSameInstant(result.outputDuration, try MediaTime(value: 726, timescale: 600))
    }

    /// Every audio packet (presentation time, duration) of the first audio track.
    private func audioPackets(_ url: URL) async throws -> [String] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var packets: [String] = []
        while let sample = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(sample)
            guard count > 0 else { continue }
            var infos = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
            var filled = 0
            XCTAssertEqual(CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &infos, entriesNeededOut: &filled), noErr)
            packets += infos.prefix(filled).map { "\($0.presentationTimeStamp.value)/\($0.presentationTimeStamp.timescale)+\($0.duration.value)/\($0.duration.timescale)" }
        }
        return packets
    }

    func testPassthroughAudioTimingIsUnchangedByTheCadenceGrid() async throws {
        let source = try await write(Fixture(width: 540, height: 960, video: .hevcHLG, audio: .aac(channels: 2, rate: 48_000), pattern: .frameLevel,
                                              presentationTimes: Self.jitteredTimes(extra: 4)))
        let sourceFacts = try await inspector.inspect(url: source)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.audio, .passthroughAAC)
        let result = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        XCTAssertEqual(result.outputFacts.audio, sourceFacts.audio)
        XCTAssertEqual(result.outputEvidence.trackCounts, .init(video: 1, audio: 1, other: 0))
        let sourcePackets = try await audioPackets(source), outputPackets = try await audioPackets(result.destinationURL)
        XCTAssertFalse(sourcePackets.isEmpty)
        XCTAssertEqual(outputPackets, sourcePackets, "AAC packets keep their exact times and durations")
    }

    func testNoVideoFrameAtOrBeforeZeroIsATypedFailure() async throws {
        let f = Fixture(width: 540, height: 960, video: .hevcHLG, endTime: CMTime(value: 740, timescale: 600), pattern: .frameLevel,
                        presentationTimes: (1...36).map { CMTime(value: Int64($0) * 20, timescale: 600) })
        let source = try await write(f)
        let before = try stamp(source)
        let plan = try await plan(for: source)
        let target = destination()
        let stages = Recorder<WorkingMediaNormalizationStage>()
        do {
            let result = try await AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stages.append($0) }))
                .normalize(sourceURL: source, destinationURL: target, plan: plan)
            let levels = try await decodedLevels(result.destinationURL)
            XCTFail("expected a typed first-frame failure; got output with schedule \(scheduled(stages).prefix(3)) first levels \(levels.prefix(3).map(\.level))")
        } catch let error as WorkingMediaNormalizationError {
            XCTAssertEqual(error, .videoTimingFailed(.cadence(.noFrameAtOrBeforeFirstTarget)))
        }
        // Refused before any media work: no writer started, so no frame (black or pulled back) was
        // ever appended and nothing was published.
        XCTAssertFalse(stages.all.contains(.willStartWriting))
        XCTAssertEqual(scheduled(stages), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(workspaceEntries(), [])
        XCTAssertEqual(try stamp(source), before)
    }

    func testWriterRejectingAHeldFrameFailsWithoutOutput() async throws {
        let source = try await write(Self.jitteredHDRFixture())
        let before = try stamp(source)
        let plan = try await plan(for: source)
        let target = destination()
        let stages = Recorder<WorkingMediaNormalizationStage>()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stages.append($0) }, injectFault: { $0 == .appendHeldVideoFrame }))
        do {
            _ = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
            XCTFail("a refused held frame must fail the run")
        } catch let error as WorkingMediaNormalizationError {
            guard case .appendFailed(.video, _, _) = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(scheduled(stages), Array(Self.jitteredSchedule.prefix(36)), "everything before the held target was appended, nothing after")
        XCTAssertEqual(stages.all.filter { if case .terminated = $0 { return true } else { return false } }, [.terminated(.appendFailed(.video))])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(workspaceEntries(), [])
        XCTAssertEqual(try stamp(source), before)
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    func testReaderFailureWhileALookAheadFrameIsRetained() async throws {
        // At the held target's observation the scheduler retains the held frame and the next
        // composed frame. The video queue waits there until the supervisor has ended the run on a
        // reader failure (60 s guard only so a regression fails instead of hanging).
        let source = try await write(Self.jitteredHDRFixture())
        let before = try stamp(source)
        let plan = try await plan(for: source)
        let target = destination()
        let failing = Flag(), ended = DispatchSemaphore(value: 0)
        let stages = Recorder<WorkingMediaNormalizationStage>()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(
            observe: { stage in
                stages.append(stage)
                if case .terminated = stage { ended.signal() }
                if stage == .videoFrameScheduled(target: 36, sourceFrame: 35, held: true) {
                    failing.set()
                    _ = ended.wait(timeout: .now() + 60)
                }
            },
            simulatedTerminalStatus: { failing.isSet ? .readerFailed : nil }))
        do {
            _ = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
            XCTFail("a reader failure must fail the run")
        } catch let error as WorkingMediaNormalizationError {
            guard case .readingFailed = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(failing.isSet)
        XCTAssertEqual(stages.all.filter { if case .terminated = $0 { return true } else { return false } }, [.terminated(.readerFailed)])
        XCTAssertEqual(scheduled(stages), Array(Self.jitteredSchedule.prefix(37)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(workspaceEntries(), [])
        XCTAssertEqual(try stamp(source), before)
    }

    func testCancellationDuringAHeldFrameAppend() async throws {
        try await runCancelled(at: .videoFrameScheduled(target: 36, sourceFrame: 35, held: true), fixture: Self.jitteredHDRFixture())
    }

    func testCancellationAfterVideoFinishedWhileAudioIsActive() async throws {
        // The audio queue waits after its first append until the video grid has finished its input;
        // the run is cancelled at that point and only then is audio released. The run must end once,
        // cancelled, with no output (60 s guard only so a regression fails instead of hanging).
        let source = try await write(Fixture(width: 540, height: 960, frames: 30, video: .hevcHLG, audio: .aac(channels: 2, rate: 48_000)))
        let before = try stamp(source)
        let plan = try await plan(for: source)
        let target = destination()
        let cancelSwitch = CancelSwitch(), videoFinished = DispatchSemaphore(value: 0)
        let stages = Recorder<WorkingMediaNormalizationStage>()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stage in
            stages.append(stage)
            if stage == .sampleAppended(.audio, count: 1) { _ = videoFinished.wait(timeout: .now() + 60) }
            if stage == .streamFinished(.video) {
                cancelSwitch.fire()
                videoFinished.signal()
            }
        }))
        let task = Task { () -> WorkingMediaNormalizationResult in
            await cancelSwitch.waitUntilArmed()
            return try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
        }
        cancelSwitch.arm { task.cancel() }
        await expectCancellation { try await task.value }
        XCTAssertTrue(cancelSwitch.fired, "the video grid never finished")
        XCTAssertTrue(stages.all.contains(.streamFinished(.video)))
        XCTAssertFalse(stages.all.contains(.streamFinished(.audio)), "audio was still active when the run was cancelled")
        XCTAssertEqual(stages.all.filter { if case .terminated = $0 { return true } else { return false } }, [.terminated(.cancelled)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(workspaceEntries(), [])
        XCTAssertEqual(try stamp(source), before)
    }

    func testRetimedSampleSharesTheRenderedImageAndAttachments() throws {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer), kCVReturnSuccess)
        let image = try XCTUnwrap(pixelBuffer)
        CVBufferSetAttachment(image, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: image, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 20, timescale: 600), presentationTimeStamp: CMTime(value: 700, timescale: 600), decodeTimeStamp: .invalid)
        var original: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: image, formatDescription: try XCTUnwrap(format),
                                                                sampleTiming: &timing, sampleBufferOut: &original), noErr)
        let sample = try XCTUnwrap(original)
        let attachments = try XCTUnwrap(CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)) as NSArray
        (attachments[0] as! NSMutableDictionary)[kCMSampleAttachmentKey_DisplayImmediately] = true

        let result = AVFoundationWorkingMediaNormalizer.retimedVideoSample(sample, presentationTime: CMTime(value: 720, timescale: 600), duration: CMTime(value: 6, timescale: 600))
        guard case .success(let retimed) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(retimed), CMTime(value: 720, timescale: 600))
        XCTAssertEqual(CMSampleBufferGetDuration(retimed), CMTime(value: 6, timescale: 600))
        XCTAssertFalse(CMSampleBufferGetDecodeTimeStamp(retimed).isValid)
        XCTAssertEqual(CMSampleBufferGetNumSamples(retimed), 1)
        XCTAssertTrue(CMSampleBufferGetImageBuffer(retimed) === image, "the held frame reuses the rendered image, never a copy")
        XCTAssertTrue(CMSampleBufferGetFormatDescription(retimed) === CMSampleBufferGetFormatDescription(sample))
        let copied = try XCTUnwrap(CMSampleBufferGetSampleAttachmentsArray(retimed, createIfNecessary: false)) as NSArray
        XCTAssertEqual((copied[0] as? NSDictionary)?[kCMSampleAttachmentKey_DisplayImmediately] as? Bool, true)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample), CMTime(value: 700, timescale: 600), "the original is unchanged")

        // Not one uncompressed image: a typed failure, never a forced retime.
        let audio = try Self.pcm(channels: 2, rate: 48_000, frames: 480, tones: nil)
        guard case .failure(let failure) = AVFoundationWorkingMediaNormalizer.retimedVideoSample(audio, presentationTime: .zero, duration: CMTime(value: 1, timescale: 30)) else {
            return XCTFail("audio retimed as a video frame")
        }
        XCTAssertEqual(failure, .unexpectedSample(sampleCount: 480))
    }

    func testValidatorStillRejectsADoubleIntervalGap() throws {
        let frame = try MediaTime(value: 1, timescale: 30)
        let gapped = [MediaTime.zero, try MediaTime(value: 1, timescale: 30), try MediaTime(value: 3, timescale: 30), try MediaTime(value: 4, timescale: 30)]
        XCTAssertEqual(WorkingMediaOutputValidator.cadenceViolations(.times(gapped), frameDuration: frame),
                       [.cadenceMismatch(index: 1, interval: try MediaTime(value: 2, timescale: 30))])
    }

    // MARK: - Exact cadence validation (ADR-048 Revision 2)

    private func mt(_ value: Int64, _ timescale: Int32 = 600) -> MediaTime { try! MediaTime(value: value, timescale: timescale) }

    /// Literal 600-timescale presentation times.
    private func ticks(_ values: [Int64]) -> WorkingMediaOutputEvidence.PresentationTimes { .times(values.map { mt($0) }) }

    private func validate(_ values: [Int64], end: Int64, nominal: Float = 30) throws -> [WorkingMediaOutputViolation] {
        let plan = try syntheticPlan(duration: mt(end))
        assertSameInstant(plan.outputFrameDuration, mt(1, 30))
        var output = canonicalOutput(for: plan)
        output.nominalFrameRate = nominal
        return WorkingMediaOutputValidator.violations(of: output, evidence: evidence(plan, times: ticks(values)), plan: plan, sourceAudio: nil)
    }

    func testExactGridWithAShortFinalSamplePassesDespiteItsApparentRate() throws {
        // 41 samples at 0/600 … 800/600, session end 801/600: the last sample lasts 1/600.
        // 41 ÷ (801/600) ≈ 30.71 — above the former 30.5 metadata ceiling, which this nominal value
        // would have tripped.
        let apparent = Float(41) / (Float(801) / 600)
        XCTAssertGreaterThan(apparent, ImportPreflightPolicy.maximumNominalFrameRate)
        XCTAssertEqual(try validate(Array(stride(from: 0, through: 800, by: 20)), end: 801, nominal: apparent), [])
        // A 1-second-class output ending one tick after a grid point: 31 samples, 0 … 600/600,
        // end 601/600, 31 ÷ (601/600) ≈ 30.95.
        let oneSecond = Float(31) / (Float(601) / 600)
        XCTAssertGreaterThan(oneSecond, 30.9)
        XCTAssertEqual(try validate(Array(stride(from: 0, through: 600, by: 20)), end: 601, nominal: oneSecond), [])
        // A metadata value alone never rejects an exact grid.
        XCTAssertEqual(try validate(Array(stride(from: 0, through: 700, by: 20)), end: 720, nominal: 60), [])
    }

    func testInexactGridsStillFail() throws {
        let grid = Array(stride(from: Int64(0), through: 800, by: 20))   // 41 targets, end 801/600
        // One 2d gap (a missing interior target, 700 → 740).
        XCTAssertEqual(try validate(grid.filter { $0 != 720 }, end: 801), [.cadenceMismatch(index: 35, interval: mt(40))])
        // A missing final target: the grid stops at 780/600 although 800/600 < 801/600.
        XCTAssertEqual(try validate(grid.filter { $0 != 800 }, end: 801), [.gridEndMismatch(lastPresentation: mt(780))])
        // A frame at the session end (800/600 with E = 800/600) is past the grid.
        XCTAssertEqual(try validate(grid, end: 800), [.gridEndMismatch(lastPresentation: mt(800))])
        // A duplicated presentation time (20/600 twice).
        XCTAssertEqual(try validate([0, 20, 20] + Array(stride(from: Int64(40), through: 800, by: 20)), end: 801), [.timestampsNotIncreasing])
        // An off-grid presentation time (41/600 instead of 40/600).
        XCTAssertEqual(try validate([0, 20, 41] + Array(stride(from: Int64(60), through: 800, by: 20)), end: 801), [.cadenceMismatch(index: 1, interval: mt(21))])
        // A first presentation time later than zero (every time one tick late).
        XCTAssertEqual(try validate(grid.map { $0 + 1 }, end: 801), [.cadenceDoesNotStartAtZero(mt(1))])
        // An output duration outside the ADR-045 window (source 801/600, output 822/600 > source + 1/30 s).
        let plan = try syntheticPlan(duration: mt(801))
        var output = canonicalOutput(for: plan)
        output.duration = .exact(mt(822))
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: output, evidence: evidence(plan, times: ticks(grid)), plan: plan, sourceAudio: nil),
                       [.durationOutsideWindow(mt(822))])
        // Sample durations are not separate evidence: a non-final sample lasts exactly until the
        // next presentation time, so a wrong one is the interval mismatch above.
    }

    func testShortFinalFrameOutputsNormalizeAndValidate() async throws {
        // Production path: 41 frames (0 … 800/600) ending at 801/600, and 31 frames (0 … 600/600)
        // ending at 601/600. Every target is kept, the session ends exactly at E, and the strict
        // validator accepts the output although its apparent rate exceeds 30.5.
        for (frames, end) in [(41, Int64(801)), (31, Int64(601))] {
            let source = try await write(Fixture(width: 540, height: 960, frames: frames, audio: .lpcm(channels: 2, rate: 48_000),
                                                  endTime: CMTime(value: end, timescale: 600)))
            let plan = try await plan(for: source)
            assertSameInstant(plan.sourceDuration, mt(end))
            let stages = Recorder<WorkingMediaNormalizationStage>()
            let result = try await AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stages.append($0) }))
                .normalize(sourceURL: source, destinationURL: destination(), plan: plan)
            assertCanonical(result, plan: plan)
            try assertGrid(result, count: frames, step: mt(20))
            XCTAssertEqual(scheduled(stages), (0..<frames).map { Scheduled(target: $0, sourceFrame: $0, held: false) })
            assertSameInstant(result.outputDuration, mt(end))
            let asset = AVURLAsset(url: result.destinationURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let range = try await XCTUnwrap(tracks.first).load(.timeRange)
            XCTAssertEqual(CMTimeCompare(range.end, CMTime(value: end, timescale: 600)), 0, "video ends exactly at E")
            let apparent = Double(frames) / (Double(end) / 600)
            XCTAssertGreaterThan(apparent, 30.5, "samples / duration; AVFoundation nominalFrameRate = \(result.outputFacts.nominalFrameRate)")
            let sourceAudio = try await inspector.inspect(url: source).audio
            XCTAssertEqual(WorkingMediaOutputValidator.violations(of: result.outputFacts, evidence: result.outputEvidence, plan: plan, sourceAudio: sourceAudio), [])
        }
    }

    // MARK: - Review corrections: single-sample grids, reader-failure precedence

    /// A synthetic plan whose frame duration is `1 / fps` s (nominal-rate path), with a raster
    /// reason so it needs normalization at a rate far below 30 fps.
    private func slowPlan(fps: Float, end: MediaTime) throws -> WorkingMediaNormalizationPlan {
        try syntheticPlan(natural: (1440, 2560), fps: fps, duration: end)
    }

    private func validateSingle(_ times: [MediaTime], plan: WorkingMediaNormalizationPlan) -> [WorkingMediaOutputViolation] {
        WorkingMediaOutputValidator.violations(of: canonicalOutput(for: plan), evidence: evidence(plan, times: .times(times)), plan: plan, sourceAudio: nil)
    }

    func testSingleSampleGridBoundaries() throws {
        // d = 1 s, E = 1 s: the only target is 0.
        let exact = try slowPlan(fps: 1, end: mt(1, 1))
        assertSameInstant(exact.outputFrameDuration, mt(1, 1))
        XCTAssertEqual(validateSingle([mt(0)], plan: exact), [])
        // d = 2 s, E = 1.5 s (0 < E < d): still only target 0, a partial single sample.
        let partial = try slowPlan(fps: 0.5, end: mt(3, 2))
        assertSameInstant(partial.outputFrameDuration, mt(2, 1))
        XCTAssertEqual(validateSingle([mt(0)], plan: partial), [])
        // No sample at all.
        XCTAssertEqual(validateSingle([], plan: exact), [.cadenceUnverifiable])
        // One sample, not at zero.
        XCTAssertEqual(validateSingle([mt(1)], plan: exact), [.cadenceDoesNotStartAtZero(mt(1))])
        // One sample at zero but E = 1.5 s > d = 1 s: target 1 s is missing.
        let longer = try slowPlan(fps: 1, end: mt(3, 2))
        XCTAssertEqual(validateSingle([mt(0)], plan: longer), [.gridEndMismatch(lastPresentation: mt(0))])
        // A single sample at or after E can only be non-zero (E > 0), so the full validator
        // reports the late start first; the grid-end rule rejects it on its own as well.
        XCTAssertEqual(validateSingle([mt(1, 1)], plan: exact), [.cadenceDoesNotStartAtZero(mt(1, 1))])
        XCTAssertEqual(WorkingMediaOutputValidator.gridEndViolations(.times([mt(1, 1)]), frameDuration: mt(1, 1), sessionEnd: mt(1, 1)),
                       [.gridEndMismatch(lastPresentation: mt(1, 1))])
        XCTAssertEqual(WorkingMediaOutputValidator.gridEndViolations(.times([mt(3, 2)]), frameDuration: mt(1, 1), sessionEnd: mt(1, 1)),
                       [.gridEndMismatch(lastPresentation: mt(3, 2))])
        // Multi-sample checks are unchanged: two samples 2d apart still fail.
        XCTAssertEqual(validateSingle([mt(0), mt(2, 1)], plan: try slowPlan(fps: 1, end: mt(5, 2))),
                       [.cadenceMismatch(index: 0, interval: mt(2, 1))])
    }

    func testOneFrameSourceNormalizesToASingleSampleGrid() async throws {
        // One 1 s frame of 10-bit HLG (HDR reason, built-in path): d = 1 s, E = 1 s, one target at 0.
        let source = try await write(Fixture(width: 540, height: 960, frames: 1, frameDuration: CMTime(value: 1, timescale: 1), video: .hevcHLG,
                                              endTime: CMTime(value: 1, timescale: 1), explicitFrameDurations: true))
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.renderPath, .builtInToneMap)
        assertSameInstant(plan.outputFrameDuration, mt(1, 1))
        assertSameInstant(plan.sourceDuration, mt(1, 1))
        let stages = Recorder<WorkingMediaNormalizationStage>()
        let result = try await AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(observe: { stages.append($0) }))
            .normalize(sourceURL: source, destinationURL: destination(), plan: plan)
        assertCanonical(result, plan: plan)
        XCTAssertEqual(scheduled(stages), [Scheduled(target: 0, sourceFrame: 0, held: false)], "exactly one target, no synthesized frame")
        guard case .times(let times) = result.outputEvidence.videoPresentationTimes else { return XCTFail("no timestamps") }
        XCTAssertEqual(times.count, 1)
        assertSameInstant(try XCTUnwrap(times.first), mt(0))
        assertSameInstant(result.outputDuration, mt(1, 1))
        XCTAssertEqual(WorkingMediaOutputValidator.violations(of: result.outputFacts, evidence: result.outputEvidence, plan: plan, sourceAudio: nil), [])
    }

    func testReaderFailureBeforeTheFirstFrameIsAReadingFailure() async throws {
        // Every geometry render fails, so the composition output ends without a frame while the
        // reader is already `.failed`. The supervisor is held inside its first status poll until
        // the run has ended, so only the video pump's exhausted-input branch can decide the
        // outcome: it must report the reader failure, not `noFrameAtOrBeforeFirstTarget`.
        // (`.cancelled` takes the same branch; it only arises from this run's own abort, after the
        // stream queues are quiesced.) 60 s guard only so a regression fails instead of hanging.
        let source = try await oddSDRSource()
        let before = try stamp(source)
        let plan = try await plan(for: source)
        XCTAssertEqual(plan.renderPath, .sdrApertureGeometry)
        let target = destination()
        let ended = DispatchSemaphore(value: 0)
        let stages = Recorder<WorkingMediaNormalizationStage>(), terminationQueues = Recorder<String>()
        let normalizer = AVFoundationWorkingMediaNormalizer(hooks: WorkingMediaNormalizerHooks(
            observe: { stage in
                stages.append(stage)
                if case .terminated = stage {
                    terminationQueues.append(String(cString: __dispatch_queue_get_label(nil)))
                    ended.signal()
                }
            },
            injectFault: { $0 == .render },
            simulatedTerminalStatus: {
                _ = ended.wait(timeout: .now() + 60)
                ended.signal()
                return nil
            }))
        do {
            _ = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
            XCTFail("a failed reader must never publish")
        } catch let error as WorkingMediaNormalizationError {
            guard case .readingFailed = error else { return XCTFail("expected readingFailed, got \(error)") }
        }
        XCTAssertEqual(stages.all.filter { if case .terminated = $0 { return true } else { return false } }, [.terminated(.readerFailed)])
        XCTAssertEqual(terminationQueues.all, ["com.mellow.working-media.video"], "decided by the video pump's exhausted-input branch")
        XCTAssertEqual(scheduled(stages), [], "no frame scheduled or appended")
        XCTAssertFalse(AVFoundationWorkingMediaNormalizer.itemExists(at: target))
        XCTAssertEqual(workspaceEntries(), [])
        XCTAssertEqual(try stamp(source), before)
    }
}

// MARK: - Debug mid-write control (UITestScriptedNormalizer, `-uiTestNormalizerMidWrite=`)

extension WorkingMediaNormalizerTests {
    private func midWriteFixture() async throws -> (source: URL, plan: WorkingMediaNormalizationPlan) {
        let source = try await write(Fixture(frames: 72, frameDuration: CMTime(value: 10, timescale: 600), audio: .aac(channels: 2, rate: 48_000)))
        return (source, try await plan(for: source))
    }

    /// `fail:<n>` fails the append after the real writer accepted n video frames, the REAL normalizer removes its partial
    /// output and keeps the source, only that failure is reported as the simulated ENOSPC, and a retry in the same launch
    /// (here: the same normalizer, as Retry uses) runs without a second injection.
    func testMidWriteFailIsOneShotRemappedAndCleanedUp() async throws {
        let (source, plan) = try await midWriteFixture()
        let before = try stamp(source)
        let normalizer = UITestScriptedNormalizer(arguments: ["-uiTestNormalizerMidWrite=fail:5"])
        let target = destination("mid-write-fail")
        do {
            _ = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
            XCTFail("the injected mid-write failure did not fail the run")
        } catch WorkingMediaNormalizationError.appendFailed(.video, let domain, let code) {
            XCTAssertEqual(domain, NSPOSIXErrorDomain)
            XCTAssertEqual(code, Int(ENOSPC))
        }
        let trigger = try XCTUnwrap(normalizer.midWriteState.trigger)
        XCTAssertEqual(trigger.mode, .fail)
        XCTAssertEqual(trigger.videoFramesAccepted, 5, "triggers only after exactly the configured accepted frames")
        XCTAssertNotNil(trigger.outputLogicalBytes, "the writer's output existed at the injection point")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "partial output left behind")
        XCTAssertEqual(workspaceEntries(), [])
        XCTAssertEqual(try stamp(source), before)

        let retryCopy = normalizer
        let result = try await retryCopy.normalize(sourceURL: source, destinationURL: target, plan: plan)
        XCTAssertEqual(result.destinationURL, target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(normalizer.midWriteState.trigger, trigger, "no second injection in the same launch")
        XCTAssertEqual(try stamp(source), before)
    }

    /// A run that never reaches the configured frame count is untouched and leaves the claim unused; an unrelated
    /// failure is never relabelled as the simulated ENOSPC.
    func testMidWriteFailNeverRelabelsAnUnrelatedError() async throws {
        let (source, plan) = try await midWriteFixture()
        let unreached = UITestScriptedNormalizer(arguments: ["-uiTestNormalizerMidWrite=fail:100000"])
        _ = try await unreached.normalize(sourceURL: source, destinationURL: destination("unreached"), plan: plan)
        XCTAssertNil(unreached.midWriteState.trigger)
        XCTAssertTrue(unreached.midWriteState.claim(), "the claim was never consumed")

        let normalizer = UITestScriptedNormalizer(arguments: ["-uiTestNormalizerMidWrite=fail:1"])
        let missing = sourceDir.appendingPathComponent("missing-\(UUID().uuidString).mov")
        do {
            _ = try await normalizer.normalize(sourceURL: missing, destinationURL: destination("missing"), plan: plan)
            XCTFail("a missing source cannot normalize")
        } catch WorkingMediaNormalizationError.appendFailed(_, let domain, _) where domain == NSPOSIXErrorDomain {
            XCTFail("an unrelated failure was relabelled as the simulated out-of-space error")
        } catch {}
        XCTAssertNil(normalizer.midWriteState.trigger)
    }

    /// `hold:<n>:<ms>` waits after n accepted video frames and then lets the run finish normally.
    func testMidWriteHoldTimesOutThenCompletes() async throws {
        let (source, plan) = try await midWriteFixture()
        let normalizer = UITestScriptedNormalizer(arguments: ["-uiTestNormalizerMidWrite=hold:5:400"])
        let target = destination("mid-write-hold")
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
        XCTAssertGreaterThanOrEqual(started.duration(to: clock.now), .milliseconds(400))
        XCTAssertEqual(result.destinationURL, target)
        let trigger = try XCTUnwrap(normalizer.midWriteState.trigger)
        XCTAssertEqual(trigger.mode, .hold(milliseconds: 400))
        XCTAssertEqual(trigger.videoFramesAccepted, 5)
        XCTAssertNotNil(trigger.outputLogicalBytes)
        XCTAssertEqual(normalizer.midWriteState.holdRelease, .timeout)
        XCTAssertFalse(normalizer.midWriteState.holdActive)
    }

    /// Cancelling during a long hold releases it through the run's termination (no deadlock with `abort()` waiting for
    /// the stream queues), cleans up the partial output and keeps the source; the next item runs without a hold.
    func testMidWriteHoldIsReleasedByCancellation() async throws {
        let (source, plan) = try await midWriteFixture()
        let before = try stamp(source)
        let normalizer = UITestScriptedNormalizer(arguments: ["-uiTestNormalizerMidWrite=hold:5:30000"])
        let target = destination("mid-write-cancel")
        let task = Task { try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(20))
        while !normalizer.midWriteState.holdActive && clock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(normalizer.midWriteState.holdActive, "the hold point was never reached")
        let cancelledAt = clock.now
        task.cancel()
        await expectCancellation { try await task.value }
        XCTAssertLessThan(cancelledAt.duration(to: clock.now), .seconds(3), "cancellation waited for the hold instead of releasing it")
        XCTAssertEqual(normalizer.midWriteState.holdRelease, .terminated)
        XCTAssertFalse(normalizer.midWriteState.holdActive)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "partial output left behind")
        XCTAssertEqual(workspaceEntries(), [])
        XCTAssertEqual(try stamp(source), before)

        let next = clock.now
        _ = try await normalizer.normalize(sourceURL: source, destinationURL: target, plan: plan)
        XCTAssertLessThan(next.duration(to: clock.now), .seconds(20), "the one-shot hold did not apply again")
        XCTAssertEqual(normalizer.midWriteState.trigger?.videoFramesAccepted, 5)
    }
}
