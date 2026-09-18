import AVFoundation
import CoreMedia
import CryptoKit
import XCTest
@testable import Mellow

/// Step 2 adapter tests: the inspector observes real files (programmatically generated with
/// AVAssetWriter in the test host's temporary directory) and synthetic format descriptions, and
/// never decides eligibility — the Step 1 classifier does, which the last group proves at the pure
/// boundary. No repository fixtures, no Photos, no network.
final class ImportSourceInspectorTests: XCTestCase {
    private var scratch: URL!
    private let inspector = AVAssetImportSourceInspector()

    override func setUp() {
        scratch = TestSupport.temporaryRoot("inspector")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: scratch) }

    // MARK: - Fixture generation (AVAssetWriter, tiny synthetic frames)

    struct Fixture {
        var fileType: AVFileType = .mov
        var codec: AVVideoCodecType = .h264
        var width = 1080, height = 1920
        var transform: CGAffineTransform = .identity
        var frames = 12
        var frameDuration = CMTime(value: 20, timescale: 600)   // 30 fps
        var color709 = true
        var audio = false
        var name = "fixture"
    }

    private func write(_ f: Fixture) async throws -> URL {
        let url = scratch.appendingPathComponent("\(f.name)-\(UUID().uuidString)").appendingPathExtension(f.fileType == .mp4 ? "mp4" : "mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: f.fileType)
        var settings: [String: Any] = [AVVideoCodecKey: f.codec, AVVideoWidthKey: f.width, AVVideoHeightKey: f.height]
        if f.color709 {
            settings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        input.transform = f.transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: f.width, kCVPixelBufferHeightKey as String: f.height])
        writer.add(input)
        var audioInput: AVAssetWriterInput?
        if f.audio {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
            a.expectsMediaDataInRealTime = false
            writer.add(a); audioInput = a
        }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<f.frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let pixelBuffer = buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            memset(CVPixelBufferGetBaseAddress(pixelBuffer), index % 2 == 0 ? 0x40 : 0xC0, CVPixelBufferGetDataSize(pixelBuffer))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(pixelBuffer, withPresentationTime: CMTimeMultiply(f.frameDuration, multiplier: Int32(index)))
        }
        input.markAsFinished()
        if let audioInput {
            // A single second of silence: 44.1 kHz mono, 16-bit.
            var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
            var format: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
            let frameCount = 44_100 / 4
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: frameCount * 2, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: frameCount * 2, flags: 0, blockBufferOut: &block)
            CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: frameCount * 2)
            var sample: CMSampleBuffer?
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44_100), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
            CMSampleBufferCreate(allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: format, sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
            while !audioInput.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            audioInput.append(sample!)
            audioInput.markAsFinished()
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }

    private func sha256(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }
    private func stamp(_ url: URL) throws -> (Int64, Date?, String) {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        return ((a[.size] as? NSNumber)?.int64Value ?? -1, a[.modificationDate] as? Date, try sha256(url))
    }
    private let rotate90 = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)

    // MARK: - File boundary and errors

    func testNonFileURLIsRejected() async {
        await assertThrows(ImportInspectionError.notFileURL) { try await self.inspector.inspect(url: URL(string: "https://example.com/a.mov")!) }
    }

    func testMissingFileIsRejected() async {
        await assertThrows(ImportInspectionError.sourceMissing) { try await self.inspector.inspect(url: self.scratch.appendingPathComponent("nope.mov")) }
    }

    func testDirectoryIsRejectedAsNonRegular() async {
        await assertThrows(ImportInspectionError.sourceNotRegularFile) { try await self.inspector.inspect(url: self.scratch) }
    }

    func testGarbageFileYieldsUnreadableFactsNotAnError() async throws {
        // AVFoundation opens the URL but reports the asset unreadable; that is a fact for the
        // classifier (`.unreadable` rejection), not an inspection error.
        let url = scratch.appendingPathComponent("garbage.mov")
        try Data((0..<4096).map { UInt8($0 % 251) }).write(to: url)
        let facts = try await inspector.inspect(url: url)
        XCTAssertFalse(facts.isReadable); XCTAssertFalse(facts.hasVideoTrack)
        XCTAssertEqual(facts.container, .unknown)
        XCTAssertEqual(facts.duration, .invalid)
        XCTAssertEqual(ImportPreflightClassifier.classify(facts), .rejected(.invalidDuration))
    }

    func testSuccessfulInspectionLeavesTheSourceUnchanged() async throws {
        let url = try await write(Fixture(audio: true))
        let before = try stamp(url)
        _ = try await inspector.inspect(url: url)
        _ = try await inspector.inspect(url: url)
        let after = try stamp(url)
        XCTAssertEqual(before.0, after.0); XCTAssertEqual(before.1, after.1); XCTAssertEqual(before.2, after.2)
    }

    func testConcurrentInspectionsAreIndependent() async throws {
        let portrait = try await write(Fixture(name: "p"))
        let landscape = try await write(Fixture(width: 1920, height: 1080, name: "l"))
        let mp4 = try await write(Fixture(fileType: .mp4, name: "m"))
        async let a = inspector.inspect(url: portrait)
        async let b = inspector.inspect(url: landscape)
        async let c = inspector.inspect(url: mp4)
        async let d = inspector.inspect(url: portrait)
        let (fa, fb, fc, fd) = try await (a, b, c, d)
        XCTAssertEqual(fa, fd)
        XCTAssertEqual(fa.presentationOrientation, .portrait); XCTAssertEqual(fb.presentationOrientation, .landscape)
        XCTAssertEqual(fa.container, .quickTime); XCTAssertNotEqual(fc.container, .quickTime)
    }

    // MARK: - Container (bytes, never the extension)

    func testGenuineQuickTimeIsIdentifiedFromFtyp() async throws {
        let facts = try await inspector.inspect(url: try await write(Fixture()))
        XCTAssertEqual(facts.container, .quickTime)
    }

    func testGenuineMP4IsIsoBaseMediaNotQuickTime() async throws {
        let facts = try await inspector.inspect(url: try await write(Fixture(fileType: .mp4)))
        guard case .isoBaseMedia(let brands) = facts.container else { return XCTFail("\(facts.container)") }
        XCTAssertFalse(brands.contains("qt  ")); XCTAssertFalse(brands.isEmpty)
    }

    func testRenamedMP4WithMovExtensionStaysIsoBaseMedia() async throws {
        let mp4 = try await write(Fixture(fileType: .mp4, frames: 45))
        let renamed = scratch.appendingPathComponent("looks-like-quicktime.mov")
        try FileManager.default.copyItem(at: mp4, to: renamed)
        let facts = try await inspector.inspect(url: renamed)
        guard case .isoBaseMedia = facts.container else { return XCTFail("extension must not decide: \(facts.container)") }
        XCTAssertEqual(ImportPreflightClassifier.classify(facts), .rejected(.unsupportedContainer(facts.container)))
    }

    func testQuickTimeWithMisleadingExtensionStaysQuickTime() async throws {
        let mov = try await write(Fixture())
        let renamed = scratch.appendingPathComponent("looks-like-mp4.mp4")
        try FileManager.default.copyItem(at: mov, to: renamed)
        let facts = try await inspector.inspect(url: renamed)
        XCTAssertEqual(facts.container, .quickTime)
    }

    func testContainerParserSafetyAndEdgeCases() {
        func box(_ type: String, _ payload: [UInt8], size: UInt32? = nil) -> [UInt8] {
            let total = size ?? UInt32(8 + payload.count)
            return withUnsafeBytes(of: total.bigEndian, Array.init) + Array(type.utf8) + payload
        }
        let qt = box("ftyp", Array("qt  ".utf8) + [0, 0, 0, 0] + Array("qt  ".utf8))
        let mp42 = box("ftyp", Array("mp42".utf8) + [0, 0, 2, 0] + Array("mp42".utf8) + Array("isom".utf8))
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data(qt)), .quickTime)
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data(mp42)), .isoBaseMedia(brands: ["mp42", "mp42", "isom"]))
        // `ftyp` after a leading `wide`/`free` box is still found; extended-size header is honoured.
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data(box("wide", []) + qt)), .quickTime)
        let ext = withUnsafeBytes(of: UInt32(1).bigEndian, Array.init) + Array("free".utf8) + withUnsafeBytes(of: UInt64(24).bigEndian, Array.init) + [0, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data(ext + mp42)), .isoBaseMedia(brands: ["mp42", "mp42", "isom"]))
        // Malformed / truncated / no ftyp → unknown, never QuickTime.
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data()), .unknown)
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data(Array(qt.prefix(12)))), .unknown, "truncated ftyp")
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data(box("ftyp", [], size: 8))), .unknown, "empty ftyp")
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data(box("mdat", [1, 2, 3]))), .unknown, "no ftyp in prefix")
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data(box("free", [], size: 4))), .unknown, "box smaller than its header")
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data(box("free", [], size: 0xFFFF_FFF0) + qt)), .unknown, "size beyond prefix never over-reads")
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data([0x00, 0x00, 0x00, 0x10, 0xFF, 0x01, 0x02, 0x03, 0, 0, 0, 0, 0, 0, 0, 0])), .unknown, "non-ASCII box type")
        // Recognised non-ISO signatures are `other`.
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data([0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0])), .other("EBML"))
        XCTAssertEqual(ImportContainerInspector.classify(prefix: Data(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("AVI ".utf8))), .other("RIFF"))
        XCTAssertLessThanOrEqual(ImportContainerInspector.maximumPrefixBytes, 64 * 1024)
    }

    // MARK: - Video / audio facts from real files

    func testH264QuickTimeFactsAndFastPath() async throws {
        let url = try await write(Fixture(frames: 45, audio: true, name: "h264"))
        let facts = try await inspector.inspect(url: url)
        XCTAssertEqual(facts.videoCodec, .h264(fourCC: "avc1"))
        XCTAssertEqual(facts.naturalWidth, 1080); XCTAssertEqual(facts.naturalHeight, 1920)
        XCTAssertEqual(facts.preferredTransform, .identity); XCTAssertEqual(facts.presentationOrientation, .portrait)
        // With an audio track the movie timescale follows the audio (44.1 kHz): the duration is
        // still exact (1.5 s = 66150/44100), so assert the rational, not a particular timescale.
        guard case .exact(let sourceDuration) = facts.duration else { return XCTFail("\(facts.duration)") }
        XCTAssertEqual(Double(sourceDuration.value) / Double(sourceDuration.timescale), 1.5, accuracy: 0)
        XCTAssertEqual(facts.nominalFrameRate, 30, accuracy: 0.01)
        XCTAssertEqual(facts.minimumFrameDuration, try MediaTime(value: 20, timescale: 600))
        XCTAssertEqual(facts.colorPrimaries, .rec709); XCTAssertEqual(facts.transferFunction, .rec709); XCTAssertEqual(facts.ycbcrMatrix, .rec709)
        XCTAssertEqual(facts.highBitDepthProfile, .no, "avcC High/Main profile is reliable 8-bit evidence")
        XCTAssertEqual(facts.fullRangeVideo, .no)
        XCTAssertFalse(facts.hasDolbyVisionConfiguration); XCTAssertTrue(facts.ancillaryHDRMetadata.isEmpty)
        XCTAssertTrue(facts.isReadable && facts.isPlayable && facts.isExportable && !facts.hasProtectedContent)
        XCTAssertTrue(facts.hasAudioTrack)
        XCTAssertEqual(facts.audio?.fourCC, "aac "); XCTAssertEqual(facts.audio?.sampleRate, 44_100); XCTAssertEqual(facts.audio?.channelCount, 1)
        XCTAssertGreaterThan(facts.byteCount, 0); XCTAssertNotNil(facts.modificationDate)
        XCTAssertEqual(ImportPreflightClassifier.classify(facts), .readyFastPath(sourceDuration: sourceDuration))
    }

    func testHEVCQuickTimeFactsAndFastPath() async throws {
        let url = try await write(Fixture(codec: .hevc, frames: 45, name: "hevc"))
        let facts = try await inspector.inspect(url: url)
        XCTAssertEqual(facts.videoCodec, .hevc(fourCC: "hvc1"))
        XCTAssertEqual(facts.highBitDepthProfile, .no, "hvcC Main profile")
        XCTAssertFalse(facts.hasAudioTrack); XCTAssertNil(facts.audio, "no audio is a valid source")
        XCTAssertEqual(ImportPreflightClassifier.classify(facts), .readyFastPath(sourceDuration: try MediaTime(value: 900, timescale: 600)))
    }

    func testRotatedNaturalLandscapeIsPortraitAndLandscapeSquareAreReportedAsFacts() async throws {
        let rotated = try await inspector.inspect(url: try await write(Fixture(width: 1920, height: 1080, transform: rotate90, frames: 45, name: "rot")))
        XCTAssertEqual(rotated.naturalWidth, 1920); XCTAssertEqual(rotated.naturalHeight, 1080)
        XCTAssertEqual(rotated.preferredTransform, ImportAffineTransform(rotate90))
        XCTAssertEqual(rotated.presentationSize.width, 1080); XCTAssertEqual(rotated.presentationSize.height, 1920)
        XCTAssertEqual(rotated.presentationOrientation, .portrait); XCTAssertFalse(rotated.isMirrored)
        XCTAssertEqual(ImportPreflightClassifier.classify(rotated), .readyFastPath(sourceDuration: try MediaTime(value: 900, timescale: 600)))

        let landscape = try await inspector.inspect(url: try await write(Fixture(width: 1920, height: 1080, frames: 45, name: "land")))
        XCTAssertEqual(landscape.presentationOrientation, .landscape)
        XCTAssertEqual(ImportPreflightClassifier.classify(landscape), .rejected(.nonPortraitPresentation(.landscape)))

        let square = try await inspector.inspect(url: try await write(Fixture(width: 720, height: 720, frames: 45, name: "sq")))
        XCTAssertEqual(square.presentationOrientation, .square)
        XCTAssertEqual(ImportPreflightClassifier.classify(square), .rejected(.nonPortraitPresentation(.square)))
    }

    func testMirroredTransformIsPreservedWithoutChangingEligibility() async throws {
        let mirrored = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        let facts = try await inspector.inspect(url: try await write(Fixture(width: 1920, height: 1080, transform: mirrored, frames: 45, name: "mir")))
        XCTAssertTrue(facts.isMirrored)
        XCTAssertEqual(facts.presentationOrientation, .portrait)
        XCTAssertEqual(ImportPreflightClassifier.classify(facts), .readyFastPath(sourceDuration: try MediaTime(value: 900, timescale: 600)))
    }

    func testDurationIsExactAndBoundaryDrivenByTheClassifier() async throws {
        let short = try await inspector.inspect(url: try await write(Fixture(frames: 12, name: "short")))   // 240/600 = 0.4 s
        XCTAssertEqual(short.duration, .exact(try MediaTime(value: 240, timescale: 600)))
        XCTAssertEqual(ImportPreflightClassifier.classify(short), .rejected(.durationBelowMinimum))
        let long = try await inspector.inspect(url: try await write(Fixture(frames: 160, name: "long")))   // 3200/600 = 5.333 s
        XCTAssertEqual(ImportPreflightClassifier.classify(long), .rejected(.durationAboveMaximum))
    }

    func testRasterAndFrameRateFactsProduceNormalizationReasons() async throws {
        let big = try await inspector.inspect(url: try await write(Fixture(width: 1440, height: 2560, frames: 45, name: "big")))
        XCTAssertEqual(ImportPreflightClassifier.classify(big), .normalizationRequired(reasons: [.raster(presentationWidth: 1440, presentationHeight: 2560)], sourceDuration: try MediaTime(value: 900, timescale: 600)))
        let fast = try await inspector.inspect(url: try await write(Fixture(frames: 90, frameDuration: CMTime(value: 10, timescale: 600), name: "fast")))   // 60 fps, 1.5 s
        XCTAssertEqual(fast.nominalFrameRate, 60, accuracy: 0.01)
        XCTAssertEqual(ImportPreflightClassifier.classify(fast), .normalizationRequired(reasons: [.frameRate(nominal: fast.nominalFrameRate)], sourceDuration: try MediaTime(value: 900, timescale: 600)))
    }

    // MARK: - Format-description mapping (synthetic CMFormatDescription; cases AVAssetWriter cannot encode)

    private func description(codec: FourCharCode, extensions: [CFString: Any]) throws -> CMFormatDescription {
        var out: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(allocator: nil, codecType: codec, width: 1080, height: 1920, extensions: extensions as CFDictionary, formatDescriptionOut: &out)
        XCTAssertEqual(status, noErr)
        return try XCTUnwrap(out)
    }
    private func baseFacts() -> ImportSourceFacts {
        ImportSourceFacts(duration: .exact(try! MediaTime(value: 1200, timescale: 600)), isReadable: true, isPlayable: true, isExportable: true, hasProtectedContent: false, hasVideoTrack: true, hasAudioTrack: false, container: .quickTime, videoCodec: .unknown, naturalWidth: 1080, naturalHeight: 1920, preferredTransform: .identity, nominalFrameRate: 30, minimumFrameDuration: nil, bitsPerComponent: nil, highBitDepthProfile: .unknown, fullRangeVideo: .unknown, colorPrimaries: .unknown, transferFunction: .unknown, ycbcrMatrix: .unknown, hasDolbyVisionConfiguration: false, ancillaryHDRMetadata: [], audio: nil, byteCount: 1, modificationDate: nil)
    }
    private func fourCC(_ s: String) -> FourCharCode { s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) } }

    func testCodecAliasesAndUnsupportedCodecsMapFromMediaSubtype() throws {
        for (code, expected) in [("avc1", ImportVideoCodec.h264(fourCC: "avc1")), ("avc3", .h264(fourCC: "avc3")), ("hvc1", .hevc(fourCC: "hvc1")), ("hev1", .hevc(fourCC: "hev1")), ("apcn", .unsupported(fourCC: "apcn")), ("ap4h", .unsupported(fourCC: "ap4h")), ("jpeg", .unsupported(fourCC: "jpeg")), ("av01", .unsupported(fourCC: "av01"))] {
            var facts = baseFacts()
            AVAssetImportSourceInspector.apply(videoFormatDescription: try description(codec: fourCC(code), extensions: [:]), to: &facts)
            XCTAssertEqual(facts.videoCodec, expected, code)
        }
        var facts = baseFacts()
        AVAssetImportSourceInspector.apply(videoFormatDescription: try description(codec: fourCC("apcn"), extensions: [:]), to: &facts)
        XCTAssertEqual(ImportPreflightClassifier.classify(facts), .rejected(.unsupportedCodec(.unsupported(fourCC: "apcn"))))
    }

    func testMissingColorTagsStayUnknownAndNeverDefaultToRec709() throws {
        var facts = baseFacts()
        AVAssetImportSourceInspector.apply(videoFormatDescription: try description(codec: fourCC("avc1"), extensions: [:]), to: &facts)
        XCTAssertEqual(facts.colorPrimaries, .unknown); XCTAssertEqual(facts.transferFunction, .unknown); XCTAssertEqual(facts.ycbcrMatrix, .unknown)
        XCTAssertNil(facts.bitsPerComponent); XCTAssertEqual(facts.fullRangeVideo, .unknown); XCTAssertEqual(facts.highBitDepthProfile, .unknown)
        XCTAssertFalse(facts.hasDolbyVisionConfiguration); XCTAssertTrue(facts.ancillaryHDRMetadata.isEmpty)
    }

    func testHDRColorTagsBitDepthAndProfilesMap() throws {
        let hlg2020: [CFString: Any] = [kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020, kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG, kCMFormatDescriptionExtension_YCbCrMatrix: kCMFormatDescriptionYCbCrMatrix_ITU_R_2020, kCMFormatDescriptionExtension_BitsPerComponent: 10, kCMFormatDescriptionExtension_FullRangeVideo: true]
        var facts = baseFacts()
        AVAssetImportSourceInspector.apply(videoFormatDescription: try description(codec: fourCC("hvc1"), extensions: hlg2020), to: &facts)
        XCTAssertEqual(facts.colorPrimaries, .rec2020); XCTAssertEqual(facts.transferFunction, .hlg); XCTAssertEqual(facts.ycbcrMatrix, .rec2020)
        XCTAssertEqual(facts.bitsPerComponent, 10); XCTAssertEqual(facts.fullRangeVideo, .yes)
        XCTAssertEqual(ImportPreflightClassifier.classify(facts), .normalizationRequired(reasons: [.hdr(signals: [.hlgTransfer, .rec2020Primaries, .rec2020Matrix, .bitDepthAbove8])], sourceDuration: try MediaTime(value: 1200, timescale: 600)))

        var pq = baseFacts()
        AVAssetImportSourceInspector.apply(videoFormatDescription: try description(codec: fourCC("avc1"), extensions: [kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ]), to: &pq)
        XCTAssertEqual(pq.transferFunction, .pq)

        var other = baseFacts()
        AVAssetImportSourceInspector.apply(videoFormatDescription: try description(codec: fourCC("avc1"), extensions: [kCMFormatDescriptionExtension_ColorPrimaries: "P3_D65" as CFString, kCMFormatDescriptionExtension_TransferFunction: "Gamma22" as CFString, kCMFormatDescriptionExtension_YCbCrMatrix: "SMPTE_240M_1995" as CFString]), to: &other)
        XCTAssertEqual(other.colorPrimaries, .other("P3_D65")); XCTAssertEqual(other.transferFunction, .other("Gamma22")); XCTAssertEqual(other.ycbcrMatrix, .other("SMPTE_240M_1995"))
    }

    func testProfileRecordsGiveHighBitDepthEvidenceOnlyWhenReliable() {
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: ["avcC": Data([1, 100, 0, 40])]), .no, "H.264 High")
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: ["avcC": Data([1, 110, 0, 40])]), .yes, "H.264 High 10")
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: ["avcC": Data([1, 244, 0, 40])]), .yes, "High 4:4:4")
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: ["avcC": Data([1, 250, 0, 40])]), .unknown, "unrecognised profile_idc")
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: ["hvcC": Data([1, 0x01])]), .no, "HEVC Main")
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: ["hvcC": Data([1, 0x02])]), .yes, "HEVC Main 10")
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: ["hvcC": Data([1, 0x03])]), .no, "HEVC Main Still Picture")
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: ["hvcC": Data([1, 0x04])]), .unknown, "Range Extensions spans 8–16-bit: not evidence")
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: ["hvcC": Data([1, 0x24])]), .unknown, "RExt with tier flag set stays unknown")
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: ["hvcC": Data([1, 0x61])]), .no, "profile bits masked from the tier/space flags")
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: ["hvcC": Data([1])]), .unknown, "truncated record")
        XCTAssertEqual(AVAssetImportSourceInspector.highBitDepthProfile(atoms: [:]), .unknown)
    }

    func testDolbyVisionAtomsAndAncillaryMetadataAreRecordedAsFacts() throws {
        // Dolby Vision / HDR-metadata content cannot be encoded by AVAssetWriter on device, so the
        // mapping is exercised on a synthetic format description carrying the same public extensions.
        let atoms: [String: Any] = ["hvcC": Data([1, 0x02]), "dvvC": Data([1, 0, 0, 0])]
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: atoms,
            kCMFormatDescriptionExtension_MasteringDisplayColorVolume: Data(repeating: 0, count: 24),
            kCMFormatDescriptionExtension_ContentLightLevelInfo: Data(repeating: 0, count: 4),
            kCMFormatDescriptionExtension_AmbientViewingEnvironment: Data(repeating: 0, count: 8),
        ]
        var facts = baseFacts()
        AVAssetImportSourceInspector.apply(videoFormatDescription: try description(codec: fourCC("hvc1"), extensions: extensions), to: &facts)
        XCTAssertTrue(facts.hasDolbyVisionConfiguration)
        XCTAssertEqual(facts.highBitDepthProfile, .yes)
        XCTAssertEqual(facts.ancillaryHDRMetadata, [.masteringDisplayColorVolume, .contentLightLevel, .ambientViewingEnvironment])
        // Policy stays in Step 1: DV + Main10 normalize; ancillary metadata alone does not.
        XCTAssertEqual(ImportPreflightClassifier.classify(facts), .normalizationRequired(reasons: [.hdr(signals: [.highBitDepthProfile, .dolbyVision])], sourceDuration: try MediaTime(value: 1200, timescale: 600)))
        var ancillaryOnly = baseFacts()
        AVAssetImportSourceInspector.apply(videoFormatDescription: try description(codec: fourCC("avc1"), extensions: [kCMFormatDescriptionExtension_AmbientViewingEnvironment: Data(repeating: 0, count: 8), kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: ["avcC": Data([1, 100, 0, 40])]]), to: &ancillaryOnly)
        XCTAssertEqual(ancillaryOnly.ancillaryHDRMetadata, [.ambientViewingEnvironment]); XCTAssertFalse(ancillaryOnly.hasDolbyVisionConfiguration)
        XCTAssertEqual(ImportPreflightClassifier.classify(ancillaryOnly), .readyFastPath(sourceDuration: try MediaTime(value: 1200, timescale: 600)))
    }

    // MARK: - Structured cancellation

    /// A pre-cancelled task must throw `CancellationError` and never receive facts. The gate makes
    /// the ordering deterministic: the child is parked *before* it enters the inspector, cancelled
    /// while parked, then released — so it calls `inspect` already cancelled. `wait()` uses a
    /// non-throwing continuation, so cancellation cannot wake it early.
    func testPreCancelledInspectionThrowsCancellationErrorInsteadOfFacts() async throws {
        let url = try await write(Fixture(frames: 45, name: "cancel"))   // a fixture failure throws here, never passes
        let gate = ReleaseGate()
        let inspector = self.inspector
        let child = Task<ImportSourceFacts, Error> {
            await gate.wait()
            return try await inspector.inspect(url: url)
        }
        child.cancel()
        await gate.release()
        do {
            let facts = try await child.value
            XCTFail("cancelled inspection returned facts: \(facts)")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
        // The same source inspects normally outside the cancelled task, so the failure above was
        // cancellation and nothing else.
        let facts = try await inspector.inspect(url: url)
        XCTAssertTrue(facts.isReadable)
        XCTAssertEqual(facts.videoCodec, .h264(fourCC: "avc1"))
    }

    // MARK: - Helpers

    private actor ReleaseGate {
        private var released = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if released { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() {
            released = true
            let pending = waiters
            waiters = []
            pending.forEach { $0.resume() }
        }
    }

    private func assertThrows(_ expected: ImportInspectionError, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> ImportSourceFacts) async {
        do { _ = try await body(); XCTFail("expected \(expected)", file: file, line: line) }
        catch let error as ImportInspectionError { XCTAssertEqual(error, expected, file: file, line: line) }
        catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }
}
