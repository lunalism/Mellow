import CoreGraphics
import XCTest
@testable import Mellow

/// Pure tests for the Phase 6 preflight decision core (ADR-042 R1–R4, ADR-043 R1, ADR-044 R1,
/// ADR-045, ADR-046). No media, no AVFoundation, no file URLs: every case is a facts value.
final class ImportPreflightClassifierTests: XCTestCase {
    // MARK: - Fixtures

    private func time(_ value: Int64, _ timescale: Int32) -> MediaTime { try! MediaTime(value: value, timescale: timescale) }
    private let rotate90 = ImportAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
    private let rotate90Mirrored = ImportAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
    private let mirrorX = ImportAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1080, ty: 0)

    /// An ordinary ready iPhone-style SDR clip: QuickTime, H.264, 1080×1920 portrait, 30 fps, 709.
    private func facts(
        duration: ImportSourceDuration = .exact(try! MediaTime(value: 1200, timescale: 600)),
        readable: Bool = true, video: Bool = true, audio: Bool = true, protected: Bool = false,
        container: ImportContainer = .quickTime,
        codec: ImportVideoCodec = .h264(fourCC: "avc1"),
        natural: (Int, Int) = (1080, 1920), transform: ImportAffineTransform = .identity,
        fps: Float = 30, minFrameDuration: MediaTime? = nil,
        bpc: Int? = 8, highBitDepthProfile: ImportKnownFlag = .no,
        primaries: ImportColorPrimaries = .rec709, transfer: ImportTransferFunction = .rec709, matrix: ImportYCbCrMatrix = .rec709,
        dolbyVision: Bool = false, ancillary: Set<ImportAncillaryHDRMetadata> = []
    ) -> ImportSourceFacts {
        ImportSourceFacts(
            duration: duration, isReadable: readable, isPlayable: readable, isExportable: readable, hasProtectedContent: protected,
            hasVideoTrack: video, hasAudioTrack: audio, container: container, videoCodec: codec,
            naturalWidth: natural.0, naturalHeight: natural.1, preferredTransform: transform,
            nominalFrameRate: fps, minimumFrameDuration: minFrameDuration, bitsPerComponent: bpc, highBitDepthProfile: highBitDepthProfile,
            fullRangeVideo: .no, colorPrimaries: primaries, transferFunction: transfer, ycbcrMatrix: matrix,
            hasDolbyVisionConfiguration: dolbyVision, ancillaryHDRMetadata: ancillary,
            audio: audio ? ImportAudioFacts(fourCC: "aac ", sampleRate: 48_000, channelCount: 2) : nil,
            byteCount: 4_000_000, modificationDate: Date(timeIntervalSince1970: 1_000))
    }

    private func verdict(_ f: ImportSourceFacts) -> ImportPreflightVerdict { ImportPreflightClassifier.classify(f) }

    private func assertRejected(_ f: ImportSourceFacts, _ expected: ImportPreflightRejection, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(verdict(f), .rejected(expected), file: file, line: line)
    }

    private func reasons(_ f: ImportSourceFacts, file: StaticString = #filePath, line: UInt = #line) -> [ImportNormalizationReason] {
        if case .normalizationRequired(let reasons, _) = verdict(f) { return reasons }
        XCTFail("expected normalization, got \(verdict(f))", file: file, line: line); return []
    }

    // MARK: - 1. Duration (ADR-042: exact, inclusive, no tolerance)

    func testExactBoundariesAreAcceptedAcrossTimescales() {
        for t in [time(1, 1), time(600, 600), time(30, 30), time(44_100, 44_100), time(90_000, 90_000)] {
            XCTAssertEqual(verdict(facts(duration: .exact(t))), .readyFastPath(sourceDuration: t), "\(t)")
        }
        for t in [time(5, 1), time(3000, 600), time(150, 30), time(220_500, 44_100)] {
            XCTAssertEqual(verdict(facts(duration: .exact(t))), .readyFastPath(sourceDuration: t), "\(t)")
        }
    }

    func testRepresentativeDurationsAreAccepted() {
        for t in [time(780, 600), time(1620, 600), time(2700, 600)] { // 1.3 / 2.7 / 4.5 s
            XCTAssertEqual(verdict(facts(duration: .exact(t))), .readyFastPath(sourceDuration: t))
        }
    }

    func testBelowMinimumIsRejected() {
        assertRejected(facts(duration: .exact(time(240, 600))), .durationBelowMinimum) // 0.4 s
        assertRejected(facts(duration: .exact(time(480, 600))), .durationBelowMinimum) // 0.8 s
        assertRejected(facts(duration: .exact(time(599, 600))), .durationBelowMinimum) // one tick below 1.0
        assertRejected(facts(duration: .exact(time(44_099, 44_100))), .durationBelowMinimum)
    }

    func testAboveMaximumIsRejectedWithoutFrameTolerance() {
        assertRejected(facts(duration: .exact(time(3001, 600))), .durationAboveMaximum) // one tick above 5.0
        assertRejected(facts(duration: .exact(time(151, 30))), .durationAboveMaximum)   // 5.033… (the old +1-frame tolerance)
        assertRejected(facts(duration: .exact(time(3020, 600))), .durationAboveMaximum)
        assertRejected(facts(duration: .exact(time(6, 1))), .durationAboveMaximum)
    }

    func testZeroNegativeAndInvalidDurationsAreInvalid() {
        assertRejected(facts(duration: .exact(.zero)), .invalidDuration)
        assertRejected(facts(duration: .exact(time(0, 1))), .invalidDuration)
        assertRejected(facts(duration: .exact(time(-600, 600))), .invalidDuration)
        assertRejected(facts(duration: .invalid), .invalidDuration)
    }

    func testAcceptedVerdictCarriesExactSourceDuration() {
        let t = time(2121, 600)
        XCTAssertEqual(verdict(facts(duration: .exact(t))), .readyFastPath(sourceDuration: t))
        if case .normalizationRequired(_, let d) = verdict(facts(duration: .exact(t), fps: 60)) { XCTAssertEqual(d, t) } else { XCTFail() }
    }

    // MARK: - 2. Precedence (ADR-046 §8 canonical order)

    private var everythingWrongLater: ImportSourceFacts {
        facts(container: .isoBaseMedia(brands: ["mp42", "isom"]), codec: .unsupported(fourCC: "apcn"),
              natural: (3840, 2160), fps: 60, bpc: 10, highBitDepthProfile: .yes, primaries: .rec2020, transfer: .hlg, matrix: .rec2020, dolbyVision: true)
    }

    func testDurationWinsOverEveryLaterFailure() {
        var f = everythingWrongLater; f.duration = .exact(time(240, 600))
        assertRejected(f, .durationBelowMinimum)
        f.duration = .exact(time(6, 1)); f.isReadable = false; f.hasProtectedContent = true
        assertRejected(f, .durationAboveMaximum)
        f.duration = .invalid
        assertRejected(f, .invalidDuration)
    }

    func testBasicMediaValidityWinsOverContainerCodecOrientationAndNormalization() {
        var f = everythingWrongLater; f.isReadable = false; f.hasVideoTrack = false; f.hasProtectedContent = true
        assertRejected(f, .unreadable)
        f.isReadable = true
        assertRejected(f, .noVideoTrack)
        f.hasVideoTrack = true
        assertRejected(f, .protectedContent)
    }

    func testContainerWinsOverCodecOrientationAndNormalization() {
        let f = everythingWrongLater
        assertRejected(f, .unsupportedContainer(.isoBaseMedia(brands: ["mp42", "isom"])))
        assertRejected(facts(container: .isoBaseMedia(brands: ["mp42"]), natural: (1920, 1080)), .unsupportedContainer(.isoBaseMedia(brands: ["mp42"])))
    }

    func testCodecWinsOverOrientationAndNormalization() {
        var f = everythingWrongLater; f.container = .quickTime
        assertRejected(f, .unsupportedCodec(.unsupported(fourCC: "apcn")))
        assertRejected(facts(codec: .unsupported(fourCC: "jpeg"), natural: (1920, 1080), fps: 60, transfer: .pq), .unsupportedCodec(.unsupported(fourCC: "jpeg")))
    }

    func testOrientationWinsOverNormalization() {
        var f = everythingWrongLater; f.container = .quickTime; f.videoCodec = .hevc(fourCC: "hvc1")
        assertRejected(f, .nonPortraitPresentation(.landscape)) // natural 3840×2160 identity
        f.naturalWidth = 2160; f.naturalHeight = 2160
        assertRejected(f, .nonPortraitPresentation(.square))
    }

    func testNormalizationIsOnlyConsideredAfterEveryGatePasses() {
        var f = everythingWrongLater; f.container = .quickTime; f.videoCodec = .hevc(fourCC: "hvc1"); f.preferredTransform = rotate90
        let r = reasons(f)
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r[0], .hdr(signals: [.hlgTransfer, .rec2020Primaries, .rec2020Matrix, .bitDepthAbove8, .highBitDepthProfile, .dolbyVision]))
        XCTAssertEqual(r[1], .frameRate(nominal: 60))
        XCTAssertEqual(r[2], .raster(presentationWidth: 2160, presentationHeight: 3840))
    }

    // MARK: - 3. Container (ADR-044)

    func testOnlyActualQuickTimeContainerIsEligible() {
        XCTAssertEqual(verdict(facts(container: .quickTime)), .readyFastPath(sourceDuration: time(1200, 600)))
        for c in [ImportContainer.isoBaseMedia(brands: ["isom", "iso2", "avc1", "mp41"]), .isoBaseMedia(brands: ["mp42"]), .isoBaseMedia(brands: ["3gp4"]), .isoBaseMedia(brands: ["M4V ", "mp42"]), .other("webm"), .unknown] {
            assertRejected(facts(container: c), .unsupportedContainer(c))
        }
    }

    func testFilenameCannotInfluenceContainerEligibility() {
        // The facts model has no filename / extension member at all, so a "renamed MP4" and a
        // "proven QuickTime with a .mp4 name" are exactly the same inputs as any MP4 / QuickTime.
        let mirror = Mirror(reflecting: facts())
        let labels = mirror.children.compactMap(\.label)
        XCTAssertFalse(labels.contains { $0.lowercased().contains("name") || $0.lowercased().contains("extension") || $0.lowercased().contains("url") }, "\(labels)")
        assertRejected(facts(container: .isoBaseMedia(brands: ["mp42"])), .unsupportedContainer(.isoBaseMedia(brands: ["mp42"])))
        XCTAssertEqual(verdict(facts(container: .quickTime)), .readyFastPath(sourceDuration: time(1200, 600)))
    }

    func testNoRemuxVerdictExists() {
        // Exhaustive: every verdict is ready, normalization or rejection; MP4 can only be rejected.
        switch verdict(facts(container: .isoBaseMedia(brands: ["mp42"]))) {
        case .rejected(.unsupportedContainer): break
        case .readyFastPath, .normalizationRequired, .rejected: XCTFail("MP4 must be rejected, never routed")
        }
        XCTAssertFalse(String(describing: ImportPreflightVerdict.self).lowercased().contains("remux"))
    }

    // MARK: - 4. Codec family (ADR-046)

    func testSupportedCodecFamilies() {
        XCTAssertEqual(ImportVideoCodec.classify(fourCC: "avc1"), .h264(fourCC: "avc1"))
        XCTAssertEqual(ImportVideoCodec.classify(fourCC: "avc3"), .h264(fourCC: "avc3"))
        XCTAssertEqual(ImportVideoCodec.classify(fourCC: "hvc1"), .hevc(fourCC: "hvc1"))
        XCTAssertEqual(ImportVideoCodec.classify(fourCC: "hev1"), .hevc(fourCC: "hev1"))
        for code in ["avc1", "avc3", "hvc1", "hev1"] {
            XCTAssertEqual(verdict(facts(codec: ImportVideoCodec.classify(fourCC: code))), .readyFastPath(sourceDuration: time(1200, 600)), code)
        }
    }

    func testUnsupportedAndUnknownCodecsAreRejected() {
        for code in ["apcn", "apch", "apcs", "apco", "ap4h", "ap4x", "aprn", "aprh", "jpeg", "mjpa", "mjpb", "vp09", "av01", "dvh1", "xxxx"] {
            let codec = ImportVideoCodec.classify(fourCC: code)
            XCTAssertEqual(codec, .unsupported(fourCC: code), code)
            assertRejected(facts(codec: codec), .unsupportedCodec(codec))
        }
        XCTAssertEqual(ImportVideoCodec.classify(fourCC: ""), .unknown)
        XCTAssertEqual(ImportVideoCodec.classify(fourCC: "   "), .unknown)
        assertRejected(facts(codec: .unknown), .unsupportedCodec(.unknown))
        // Case-sensitive FourCC: "AVC1" is not a reliably identified H.264 entry.
        XCTAssertEqual(ImportVideoCodec.classify(fourCC: "AVC1"), .unsupported(fourCC: "AVC1"))
    }

    func testSupportedFamilyAloneNeverNormalizesAndUnsupportedNeverNormalizes() {
        XCTAssertEqual(verdict(facts(codec: .hevc(fourCC: "hvc1"), bpc: nil)), .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(verdict(facts(codec: .h264(fourCC: "avc3"), bpc: nil)), .readyFastPath(sourceDuration: time(1200, 600)))
        let prores4KHDR60 = facts(codec: .unsupported(fourCC: "ap4h"), natural: (2160, 3840), fps: 60, bpc: 10, primaries: .rec2020, transfer: .hlg)
        assertRejected(prores4KHDR60, .unsupportedCodec(.unsupported(fourCC: "ap4h")))
    }

    // MARK: - 5. Orientation (ADR-043 R1)

    func testPresentationGeometryIsDerivedFromTransformNotNaturalSize() {
        let rotated = facts(natural: (1920, 1080), transform: rotate90)
        XCTAssertEqual(rotated.presentationSize.width, 1080); XCTAssertEqual(rotated.presentationSize.height, 1920)
        XCTAssertEqual(rotated.presentationOrientation, .portrait)
        XCTAssertEqual(verdict(rotated), .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(facts(natural: (1080, 1920)).presentationOrientation, .portrait)
        XCTAssertEqual(verdict(facts(natural: (1080, 1920))), .readyFastPath(sourceDuration: time(1200, 600)))
    }

    func testLandscapeAndSquareAreRejectedAsNonPortrait() {
        assertRejected(facts(natural: (1920, 1080)), .nonPortraitPresentation(.landscape))
        assertRejected(facts(natural: (1080, 1920), transform: rotate90), .nonPortraitPresentation(.landscape)) // portrait natural rotated to landscape
        assertRejected(facts(natural: (1080, 1080)), .nonPortraitPresentation(.square))
        assertRejected(facts(natural: (720, 720), transform: rotate90), .nonPortraitPresentation(.square))
        // A 4K / 60 fps / HDR non-portrait source is rejected, never normalized.
        assertRejected(facts(natural: (3840, 2160), fps: 60, primaries: .rec2020, transfer: .pq), .nonPortraitPresentation(.landscape))
    }

    func testMirroringAloneNeverChangesOrientation() {
        let mirrored = facts(natural: (1920, 1080), transform: rotate90Mirrored)
        XCTAssertTrue(mirrored.isMirrored)
        XCTAssertEqual(mirrored.presentationOrientation, .portrait)
        XCTAssertEqual(verdict(mirrored), .readyFastPath(sourceDuration: time(1200, 600)))
        let flipped = facts(natural: (1080, 1920), transform: mirrorX)
        XCTAssertTrue(flipped.isMirrored); XCTAssertEqual(flipped.presentationOrientation, .portrait)
        XCTAssertFalse(facts(natural: (1920, 1080), transform: rotate90).isMirrored)
    }

    func testTranslatedAndFloatingPointTransformsAreHandledDeterministically() {
        // A translated portrait bounding box is still 1080×1920; sub-pixel matrix noise rounds away.
        let translated = ImportAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 5000, ty: -300)
        XCTAssertEqual(facts(natural: (1920, 1080), transform: translated).presentationOrientation, .portrait)
        let noisy = ImportAffineTransform(a: 0.0000001, b: 1, c: -1, d: 0.0000001, tx: 1080, ty: 0)
        let f = facts(natural: (1920, 1080), transform: noisy)
        XCTAssertEqual(f.presentationSize.width, 1080); XCTAssertEqual(f.presentationSize.height, 1920)
    }

    // MARK: - Fast path (ADR-045 §2)

    func testReadySDRSourcesUseFastPath() {
        XCTAssertEqual(verdict(facts()), .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(verdict(facts(codec: .hevc(fourCC: "hvc1"))), .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(verdict(facts(audio: false, natural: (720, 1280), fps: 24, bpc: nil)), .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(verdict(facts(natural: (1080, 1920), fps: 29.97)), .readyFastPath(sourceDuration: time(1200, 600)))
    }

    func testAncillaryMetadataAloneDoesNotNormalize() {
        for meta in ImportAncillaryHDRMetadata.allCases {
            XCTAssertEqual(verdict(facts(ancillary: [meta])), .readyFastPath(sourceDuration: time(1200, 600)), "\(meta)")
        }
        XCTAssertEqual(verdict(facts(ancillary: Set(ImportAncillaryHDRMetadata.allCases))), .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(ImportPreflightClassifier.hdrSignals(in: facts(ancillary: Set(ImportAncillaryHDRMetadata.allCases))), [])
    }

    func testMinimumFrameDurationDisagreementAloneDoesNotNormalize() {
        // Real iPhone capture: nominal 29.987 fps with one 19/600 s frame (1/minFD ≈ 31.6).
        let f = facts(fps: 29.986961, minFrameDuration: time(19, 600))
        XCTAssertEqual(verdict(f), .readyFastPath(sourceDuration: time(1200, 600)))
    }

    // MARK: - 6. Normalization reasons (ADR-045 §2)

    func testEachHDRSignalNormalizesIndependently() {
        XCTAssertEqual(reasons(facts(transfer: .hlg)), [.hdr(signals: [.hlgTransfer])])
        XCTAssertEqual(reasons(facts(transfer: .pq)), [.hdr(signals: [.pqTransfer])])
        XCTAssertEqual(reasons(facts(primaries: .rec2020)), [.hdr(signals: [.rec2020Primaries])])
        XCTAssertEqual(reasons(facts(matrix: .rec2020)), [.hdr(signals: [.rec2020Matrix])])
        XCTAssertEqual(reasons(facts(bpc: 10)), [.hdr(signals: [.bitDepthAbove8])])
        XCTAssertEqual(reasons(facts(bpc: nil, highBitDepthProfile: .yes)), [.hdr(signals: [.highBitDepthProfile])])
        XCTAssertEqual(reasons(facts(dolbyVision: true)), [.hdr(signals: [.dolbyVision])])
        XCTAssertEqual(verdict(facts(bpc: nil, highBitDepthProfile: .unknown)), .readyFastPath(sourceDuration: time(1200, 600)), "unknown profile is not a signal")
    }

    func testOverlappingHDRSignalsDeduplicateInCanonicalOrder() {
        // iPhone HDR capture shape: HEVC Main10 + HLG + Rec.2020 + Dolby Vision.
        let f = facts(codec: .hevc(fourCC: "hvc1"), natural: (1920, 1080), transform: rotate90, bpc: 10, highBitDepthProfile: .yes, primaries: .rec2020, transfer: .hlg, matrix: .rec2020, dolbyVision: true)
        let expected: [ImportHDRSignal] = [.hlgTransfer, .rec2020Primaries, .rec2020Matrix, .bitDepthAbove8, .highBitDepthProfile, .dolbyVision]
        XCTAssertEqual(reasons(f), [.hdr(signals: expected)])
        XCTAssertEqual(ImportPreflightClassifier.hdrSignals(in: f), expected)
        XCTAssertEqual(Set(expected).count, expected.count, "no duplicates")
        XCTAssertEqual(ImportHDRSignal.allCases.sorted(), ImportHDRSignal.allCases, "canonical order is declaration order")
    }

    func testFrameRateThreshold() {
        for fps: Float in [23.976, 24, 25, 29.97, 29.986961, 30, 30.0001, 30.5] {
            XCTAssertEqual(verdict(facts(fps: fps)), .readyFastPath(sourceDuration: time(1200, 600)), "\(fps)")
        }
        XCTAssertEqual(reasons(facts(fps: 59.94)), [.frameRate(nominal: 59.94)])
        XCTAssertEqual(reasons(facts(fps: 60)), [.frameRate(nominal: 60)])
        XCTAssertEqual(reasons(facts(fps: 120)), [.frameRate(nominal: 120)])
        XCTAssertEqual(reasons(facts(fps: 30.51)), [.frameRate(nominal: 30.51)])
    }

    func testRasterThresholdUsesTransformedPresentation() {
        XCTAssertEqual(reasons(facts(natural: (2160, 3840))), [.raster(presentationWidth: 2160, presentationHeight: 3840)])
        XCTAssertEqual(reasons(facts(natural: (3840, 2160), transform: rotate90)), [.raster(presentationWidth: 2160, presentationHeight: 3840)])
        XCTAssertEqual(reasons(facts(natural: (1440, 2560))), [.raster(presentationWidth: 1440, presentationHeight: 2560)])
        XCTAssertEqual(reasons(facts(natural: (1088, 1920))), [.raster(presentationWidth: 1088, presentationHeight: 1920)], "short edge above 1080")
        XCTAssertEqual(reasons(facts(natural: (1080, 1921))), [.raster(presentationWidth: 1080, presentationHeight: 1921)], "long edge above 1920")
        XCTAssertEqual(verdict(facts(natural: (1080, 1920))), .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(verdict(facts(natural: (540, 960))), .readyFastPath(sourceDuration: time(1200, 600)), "low resolution is not a preflight reason (upscaling policy is pending elsewhere)")
    }

    func testCombinedReasonsAreReportedInCanonicalOrderRegardlessOfInput() {
        let f = facts(natural: (3840, 2160), transform: rotate90, fps: 59.94, bpc: 10, primaries: .rec2020, transfer: .pq)
        let r = reasons(f)
        let expected: [ImportNormalizationReason] = [
            .hdr(signals: [.pqTransfer, .rec2020Primaries, .bitDepthAbove8]),
            .frameRate(nominal: 59.94),
            .raster(presentationWidth: 2160, presentationHeight: 3840),
        ]
        XCTAssertEqual(r, expected)
        // Same facts constructed with a different Set insertion history produce an identical verdict.
        var g = f; g.ancillaryHDRMetadata = [.contentLightLevel, .ambientViewingEnvironment]
        XCTAssertEqual(verdict(g), verdict(f))
    }

    // MARK: - 7. Working-raster feasibility (ADR-048 Decision 2)

    private func audio(_ fourCC: String, rate: Double = 48_000, channels: Int = 2) -> ImportAudioFacts {
        ImportAudioFacts(fourCC: fourCC, sampleRate: rate, channelCount: channels)
    }

    private func withAudio(_ base: ImportSourceFacts, track: Bool, _ facts: ImportAudioFacts?) -> ImportSourceFacts {
        var f = base; f.hasAudioTrack = track; f.audio = facts; return f
    }

    func testNearSquarePortraitsWhoseAlignedRasterIsNotPortraitAreRejected() {
        for (w, h) in [(1080, 1081), (1081, 1082), (2160, 2162)] {
            let f = facts(natural: (w, h))
            XCTAssertEqual(f.presentationOrientation, .portrait, "ADR-043 still calls \(w)×\(h) portrait")
            assertRejected(f, .unsupportedWorkingRaster(presentationWidth: w, presentationHeight: h))
        }
    }

    func testNearbyRastersThatStayPortraitAfterAlignmentAreAccepted() {
        XCTAssertEqual(verdict(facts(natural: (1080, 1082))), .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(verdict(facts(natural: (1079, 1080))), .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(reasons(facts(natural: (2160, 2164))), [.raster(presentationWidth: 2160, presentationHeight: 2164)])
        XCTAssertEqual(reasons(facts(natural: (1440, 1444))), [.raster(presentationWidth: 1440, presentationHeight: 1444)])
    }

    func testRasterFeasibilityUsesThePresentationAfterTheTransform() {
        // Natural 1081×1080 rotated 90° presents as 1080×1081: portrait, infeasible once aligned.
        let rotated = ImportAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        assertRejected(facts(natural: (1081, 1080), transform: rotated), .unsupportedWorkingRaster(presentationWidth: 1080, presentationHeight: 1081))
    }

    func testRasterFeasibilityWinsOverAudioAndEveryNormalizationReason() {
        var f = facts(natural: (1080, 1081), fps: 60, bpc: 10, transfer: .hlg)
        f = withAudio(f, track: true, nil) // unreliable audio too: raster is gate 6, audio gate 7
        assertRejected(f, .unsupportedWorkingRaster(presentationWidth: 1080, presentationHeight: 1081))
    }

    func testEarlierGatesStillWinOverRasterFeasibility() {
        assertRejected(facts(duration: .exact(time(6, 1)), natural: (1080, 1081)), .durationAboveMaximum)
        assertRejected(facts(protected: true, natural: (1080, 1081)), .protectedContent)
        assertRejected(facts(container: .isoBaseMedia(brands: ["mp42"]), natural: (1080, 1081)), .unsupportedContainer(.isoBaseMedia(brands: ["mp42"])))
        assertRejected(facts(codec: .unsupported(fourCC: "apch"), natural: (1080, 1081)), .unsupportedCodec(.unsupported(fourCC: "apch")))
        assertRejected(facts(natural: (1081, 1080)), .nonPortraitPresentation(.landscape))
        assertRejected(facts(natural: (1080, 1080)), .nonPortraitPresentation(.square))
    }

    func testClassifierAndPlanShareOneRasterCalculation() {
        for (w, h) in [(1080, 1081), (1080, 1082), (1079, 1080), (2160, 2162), (2160, 2164), (1440, 1444), (1620, 2160), (719, 1279)] {
            let plan = WorkingMediaRasterPolicy.plan(forPresentation: WorkingMediaRaster(width: w, height: h))
            let rejected = verdict(facts(natural: (w, h))) == .rejected(.unsupportedWorkingRaster(presentationWidth: w, presentationHeight: h))
            XCTAssertEqual(plan?.isFeasible == false, rejected, "\(w)×\(h)")
        }
    }

    // MARK: - 8. Audio facts (ADR-048 Decision 1)

    func testNoAudioIsValidAndAddsNoReason() {
        XCTAssertEqual(ImportPreflightClassifier.assessAudio(facts(audio: false)), .noAudio)
        XCTAssertEqual(verdict(facts(audio: false)), .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(reasons(facts(audio: false, fps: 60)), [.frameRate(nominal: 60)])
    }

    func testAACPassesThroughAndIsNeverAReason() {
        XCTAssertEqual(ImportPreflightClassifier.assessAudio(facts()), .passthroughAAC)
        XCTAssertEqual(verdict(facts()), .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(reasons(facts(transfer: .hlg)), [.hdr(signals: [.hlgTransfer])])
    }

    func testKnownNonAACFormatsAddAudioTranscode() {
        for id in ["lpcm", "alac", "apac", "aach", "aacp", "aacl", "aace", "ac-3", "opus", "AAC ", "aac_"] {
            let f = withAudio(facts(), track: true, audio(id))
            XCTAssertEqual(ImportPreflightClassifier.assessAudio(f), .transcode(sourceChannelCount: 2), id)
            XCTAssertEqual(reasons(f), [.audioTranscode], "\(id) alone normalizes")
        }
    }

    func testAudioTranscodeIsTheLastCanonicalReason() {
        var f = facts(natural: (2160, 3840), fps: 60, bpc: 10, transfer: .hlg)
        f = withAudio(f, track: true, audio("lpcm", channels: 6))
        XCTAssertEqual(reasons(f), [
            .hdr(signals: [.hlgTransfer, .bitDepthAbove8]),
            .frameRate(nominal: 60),
            .raster(presentationWidth: 2160, presentationHeight: 3840),
            .audioTranscode,
        ])
        XCTAssertEqual(reasons(withAudio(facts(fps: 60), track: true, audio("alac"))), [.frameRate(nominal: 60), .audioTranscode])
    }

    func testUnreliableAudioFactsAreRejected() {
        let cases: [(ImportSourceFacts, ImportAudioFactsProblem)] = [
            (withAudio(facts(), track: false, audio("aac ")), .contradictoryTrackFacts),
            (withAudio(facts(), track: true, nil), .missingFormatFacts),
            (withAudio(facts(), track: true, audio("")), .malformedFormatID),
            (withAudio(facts(), track: true, audio("aac")), .malformedFormatID),
            (withAudio(facts(), track: true, audio("aac  ")), .malformedFormatID),
            (withAudio(facts(), track: true, audio("\u{0}\u{0}\u{0}\u{0}")), .malformedFormatID),  // all-zero = absent
            (withAudio(facts(), track: true, audio("a€ c")), .malformedFormatID),                  // U+20AC is not one subtype byte
            (withAudio(facts(), track: true, audio("aac ", rate: 0)), .invalidSampleRate),
            (withAudio(facts(), track: true, audio("aac ", rate: -48_000)), .invalidSampleRate),
            (withAudio(facts(), track: true, audio("lpcm", rate: .nan)), .invalidSampleRate),
            (withAudio(facts(), track: true, audio("lpcm", rate: .infinity)), .invalidSampleRate),
            (withAudio(facts(), track: true, audio("aac ", channels: 0)), .invalidChannelCount),
            (withAudio(facts(), track: true, audio("lpcm", channels: -1)), .invalidChannelCount),
        ]
        for (f, problem) in cases {
            XCTAssertEqual(ImportPreflightClassifier.assessAudio(f), .unreliable(problem), "\(problem)")
            assertRejected(f, .unsupportedAudioFacts(problem))
        }
    }

    func testAudioRejectionWinsOverEveryNormalizationReason() {
        let f = withAudio(facts(natural: (2160, 3840), fps: 60, transfer: .pq), track: true, nil)
        assertRejected(f, .unsupportedAudioFacts(.missingFormatFacts))
    }

    func testEarlierGatesStillWinOverAudioFacts() {
        let noFacts = { (f: ImportSourceFacts) in self.withAudio(f, track: true, nil) }
        assertRejected(noFacts(facts(duration: .exact(time(599, 600)))), .durationBelowMinimum)
        assertRejected(noFacts(facts(readable: false)), .unreadable)
        assertRejected(noFacts(facts(container: .unknown)), .unsupportedContainer(.unknown))
        assertRejected(noFacts(facts(codec: .unknown)), .unsupportedCodec(.unknown))
        assertRejected(noFacts(facts(natural: (1920, 1080))), .nonPortraitPresentation(.landscape))
    }

    func testEveryNonzeroNonAACSubtypeTranscodesRegardlessOfPrintability() {
        // Raw subtype bytes as the inspector renders them (one ISO Latin-1 scalar per byte).
        let cases: [(String, UInt32)] = [
            ("a\u{E9} c", 0x61E9_2063),              // high-bit byte
            ("a\u{7}cc", 0x6107_6363),               // control byte
            ("\u{0}\u{0}\u{0}\u{1}", 0x0000_0001),   // embedded NULs, nonzero overall
            ("ac\u{0}3", 0x6163_0033),               // embedded NUL mid-subtype
            ("    ", 0x2020_2020),                   // four spaces
            ("\u{FF}\u{FF}\u{FF}\u{FF}", 0xFFFF_FFFF),
        ]
        for (fourCC, raw) in cases {
            XCTAssertEqual(ImportPreflightClassifier.rawFormatID(fourCC), raw, "raw identity \(raw)")
            let f = withAudio(facts(), track: true, audio(fourCC))
            XCTAssertEqual(ImportPreflightClassifier.assessAudio(f), .transcode(sourceChannelCount: 2), "\(raw)")
            XCTAssertEqual(reasons(f), [.audioTranscode], "\(raw)")
        }
        XCTAssertEqual(ImportPreflightClassifier.rawFormatID("aac "), 0x6161_6320)
        XCTAssertEqual(ImportPreflightClassifier.rawFormatID("\u{0}\u{0}\u{0}\u{0}"), 0)
        XCTAssertNil(ImportPreflightClassifier.rawFormatID(""))
        XCTAssertNil(ImportPreflightClassifier.rawFormatID("a\u{100}cc"))
        // A "\r\n" pair is one Character but two subtype bytes: identity is by scalar, not Character.
        XCTAssertEqual(ImportPreflightClassifier.rawFormatID("a\r\nc"), 0x610D_0A63)
    }

    func testFourCCComparisonIsExactAndCaseSensitive() {
        XCTAssertEqual(ImportPreflightPolicy.passthroughAudioFormatID, "aac ")
        XCTAssertEqual(ImportPreflightClassifier.assessAudio(withAudio(facts(), track: true, audio("aac "))), .passthroughAAC)
        XCTAssertEqual(ImportPreflightClassifier.assessAudio(withAudio(facts(), track: true, audio("AAC "))), .transcode(sourceChannelCount: 2))
        XCTAssertEqual(ImportPreflightClassifier.assessAudio(withAudio(facts(), track: true, audio(" aac"))), .transcode(sourceChannelCount: 2))
    }

    // MARK: - Value semantics

    func testFactsAreEquatableHashableAndPreserveUnknownStates() {
        let a = facts(bpc: nil, highBitDepthProfile: .unknown, primaries: .unknown, transfer: .unknown, matrix: .unknown)
        let b = facts(bpc: nil, highBitDepthProfile: .unknown, primaries: .unknown, transfer: .unknown, matrix: .unknown)
        XCTAssertEqual(a, b); XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertNotEqual(a, facts(bpc: 8))
        XCTAssertEqual(a.bitsPerComponent, nil); XCTAssertEqual(a.highBitDepthProfile, .unknown)
        XCTAssertEqual(verdict(a), .readyFastPath(sourceDuration: time(1200, 600)), "unknown color tags are not HDR signals")
        XCTAssertEqual(ImportContainer.isoBaseMedia(brands: ["a", "b"]), .isoBaseMedia(brands: ["a", "b"]))
        XCTAssertNotEqual(ImportContainer.isoBaseMedia(brands: ["a"]), .other("a"))
        XCTAssertEqual(ImportVideoCodec.unknown, .unknown); XCTAssertNotEqual(ImportVideoCodec.unknown, .unsupported(fourCC: ""))
    }

    func testAffineTransformRoundTripsAndDetectsMirroring() {
        let cg = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let t = ImportAffineTransform(cg)
        XCTAssertEqual(t, rotate90)
        XCTAssertEqual(t.cgAffineTransform, cg)
        XCTAssertEqual(ImportAffineTransform.identity.determinant, 1)
        XCTAssertEqual(rotate90.determinant, 1)
        XCTAssertEqual(rotate90Mirrored.determinant, -1)
        XCTAssertEqual(mirrorX.determinant, -1)
    }

    func testVerdictsAreSendableValueTypes() {
        // Compile-time: passing across an actor boundary requires Sendable.
        let f = facts()
        let v = verdict(f)
        Task.detached { @Sendable in _ = f; _ = v }
        XCTAssertEqual(v, verdict(f))
    }
}
