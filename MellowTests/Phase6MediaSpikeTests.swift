#if DEBUG
import CoreMedia
import PhotosUI
import XCTest
@testable import Mellow

/// Spike-only tests for the Phase 6 Technical Device Spike policy candidates. These do not touch
/// the production validator or any Project / Clip code path and are removed with `Spike/`.
final class Phase6MediaSpikeTests: XCTestCase {
    // MARK: Exact CMTime boundary classification (inclusive 1.0–5.0 s, no tolerance)

    func testExactBoundariesAreEligibleAtAnyTimescale() {
        for t in [CMTime(value: 1, timescale: 1), CMTime(value: 30, timescale: 30), CMTime(value: 600, timescale: 600), CMTime(value: 44100, timescale: 44100), CMTime(value: 2_147_483_647, timescale: 2_147_483_647)] {
            XCTAssertEqual(Phase6SpikeDurationEligibility.classify(t), .eligible, "\(t.value)/\(t.timescale)")
        }
        for t in [CMTime(value: 5, timescale: 1), CMTime(value: 150, timescale: 30), CMTime(value: 3000, timescale: 600), CMTime(value: 220_500, timescale: 44100)] {
            XCTAssertEqual(Phase6SpikeDurationEligibility.classify(t), .eligible, "\(t.value)/\(t.timescale)")
        }
    }

    func testJustBelowAndAboveBoundariesAreRejectedWithoutFrameTolerance() {
        XCTAssertEqual(Phase6SpikeDurationEligibility.classify(CMTime(value: 29, timescale: 30)), .belowMinimum)
        XCTAssertEqual(Phase6SpikeDurationEligibility.classify(CMTime(value: 2_147_483_646, timescale: 2_147_483_647)), .belowMinimum)
        XCTAssertEqual(Phase6SpikeDurationEligibility.classify(CMTime(value: 151, timescale: 30)), .aboveMaximum, "5 s + one frame is above maximum")
        XCTAssertEqual(Phase6SpikeDurationEligibility.classify(CMTime(value: 120_120, timescale: 24000)), .aboveMaximum, "5.005 s")
        XCTAssertEqual(Phase6SpikeDurationEligibility.classify(CMTime(value: 1_000_000_001, timescale: 1_000_000_000)), .eligible)
        XCTAssertEqual(Phase6SpikeDurationEligibility.classify(CMTime(value: 24, timescale: 60)), .belowMinimum, "0.4 s")
        XCTAssertEqual(Phase6SpikeDurationEligibility.classify(CMTime(value: 78, timescale: 60)), .eligible, "1.3 s")
    }

    func testNonNumericDurationsAreInvalid() {
        for t in [CMTime.invalid, .indefinite, .positiveInfinity, .negativeInfinity] {
            XCTAssertEqual(Phase6SpikeDurationEligibility.classify(t), .invalid)
        }
        XCTAssertEqual(Phase6SpikeDurationEligibility.classify(.zero), .belowMinimum)
    }

    // MARK: Bounding-box raster

    func testRasterDownscalesToBoundingBoxWithoutCrop() {
        XCTAssertEqual(Phase6SpikeRaster.boundingBox(forPresentation: CGSize(width: 2160, height: 3840)), CGSize(width: 1080, height: 1920))
        XCTAssertEqual(Phase6SpikeRaster.boundingBox(forPresentation: CGSize(width: 3840, height: 2160)), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(Phase6SpikeRaster.boundingBox(forPresentation: CGSize(width: 1440, height: 1440)), CGSize(width: 1080, height: 1080))
        XCTAssertEqual(Phase6SpikeRaster.boundingBox(forPresentation: CGSize(width: 1440, height: 1920)), CGSize(width: 1080, height: 1440), "4:3 portrait limited by the short edge")
    }

    func testRasterNeverUpscales() {
        XCTAssertEqual(Phase6SpikeRaster.boundingBox(forPresentation: CGSize(width: 1280, height: 720)), CGSize(width: 1280, height: 720))
        XCTAssertEqual(Phase6SpikeRaster.boundingBox(forPresentation: CGSize(width: 640, height: 480)), CGSize(width: 640, height: 480))
        XCTAssertEqual(Phase6SpikeRaster.scale(forPresentation: CGSize(width: 540, height: 960)), 1)
    }

    func testRasterRoundsToEvenDimensions() {
        XCTAssertEqual(Phase6SpikeRaster.boundingBox(forPresentation: CGSize(width: 1081, height: 1921)), CGSize(width: 1080, height: 1918), "floor-to-even after scaling never exceeds the box")
        XCTAssertEqual(Phase6SpikeRaster.boundingBox(forPresentation: CGSize(width: 641, height: 481)), CGSize(width: 640, height: 480), "odd source is never rounded up (no upscale)")
        let box = Phase6SpikeRaster.boundingBox(forPresentation: CGSize(width: 1000, height: 1777))
        XCTAssertEqual(Int(box.width) % 2, 0); XCTAssertEqual(Int(box.height) % 2, 0)
    }

    // MARK: Path classification

    private func input(duration: CMTime = CMTime(value: 2, timescale: 1), container: Phase6SpikeContainer = .quickTime, codec: String = "avc1", size: CGSize = CGSize(width: 1080, height: 1920), fps: Float = 30, transfer: String? = nil, primaries: String? = nil, matrix: String? = nil, dolbyVision: Bool = false, bpc: Int? = 8, highBitDepth: Bool = false, vfr: Bool = false, readable: Bool = true, video: Bool = true, protected: Bool = false) -> Phase6SpikeClassificationInput {
        Phase6SpikeClassificationInput(duration: duration, isReadable: readable, isPlayable: true, hasProtectedContent: protected, hasVideoTrack: video, container: container, videoCodec: codec, bitsPerComponent: bpc, profileIsHighBitDepth: highBitDepth, presentationSize: size, nominalFrameRate: fps, transferFunction: transfer, colorPrimaries: primaries, ycbcrMatrix: matrix, hasDolbyVisionConfiguration: dolbyVision, isVariableFrameRateSuspected: vfr)
    }

    // MARK: HDR / Dolby Vision → normalization-required; SDR output contract

    private let hlg = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
    private let pq = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
    private let p2020 = kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String
    private let m2020 = kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String
    private let p709 = kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String
    private let t709 = kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String
    private let m709 = kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String

    func testHDRSignalsRouteToNormalizationAndNeverToFastPath() {
        // 1. iPhone HDR capture shape: QuickTime HEVC Main10 + HLG + Rec.2020, nil bpc.
        let iphoneHDR = input(codec: "hvc1", transfer: hlg, primaries: p2020, matrix: m2020, bpc: nil, highBitDepth: true)
        var v = Phase6SpikePathClassifier.classify(iphoneHDR)
        XCTAssertEqual(v.path, .normalizeH264)
        XCTAssertTrue(v.reasons.contains { $0.contains("HLG transfer") && $0.contains("Rec.2020 primaries") && $0.contains("Rec.2020 matrix") && $0.contains("10-bit profile") }, "\(v.reasons)")
        // 2. HEVC + PQ alone.
        v = Phase6SpikePathClassifier.classify(input(codec: "hev1", transfer: pq, bpc: nil))
        XCTAssertEqual(v.path, .normalizeH264); XCTAssertTrue(v.reasons.contains { $0.contains("PQ transfer") })
        // 3. Dolby Vision atom alone (even with 709 tags) is a reliable HDR signal.
        v = Phase6SpikePathClassifier.classify(input(codec: "hvc1", transfer: t709, primaries: p709, matrix: m709, dolbyVision: true, bpc: nil))
        XCTAssertEqual(v.path, .normalizeH264); XCTAssertTrue(v.reasons.contains { $0.contains("Dolby Vision config atom") })
        // 4. Rec.2020 primaries or matrix alone.
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(primaries: p2020)).path, .normalizeH264)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(matrix: m2020)).path, .normalizeH264)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(bpc: 10)).path, .normalizeH264)
        // 5. Never fast path, and 6. never unsupported-container when the container is QuickTime.
        for i in [iphoneHDR, input(transfer: hlg), input(transfer: pq), input(dolbyVision: true), input(primaries: p2020)] {
            let verdict = Phase6SpikePathClassifier.classify(i)
            XCTAssertNotEqual(verdict.path, .readyQuickTimeFastPath)
            XCTAssertNotEqual(verdict.path, .preflightUnsupportedContainer)
            XCTAssertEqual(verdict.path, .normalizeH264)
        }
        // Plain 709 SDR HEVC stays a fast-path copy (no false HDR positive).
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(codec: "hvc1", transfer: t709, primaries: p709, matrix: m709, bpc: nil)).path, .readyQuickTimeFastPath)
    }

    private func sdrFacts() -> Phase6SpikeSDROutputContract.Facts {
        Phase6SpikeSDROutputContract.Facts(container: .quickTime, videoCodec: "avc1", profileDescription: "H.264 High L4.0", profileIsHighBitDepth: false, bitsPerComponent: nil,
            colorPrimaries: p709, transferFunction: t709, ycbcrMatrix: m709, hdrMetadataNotes: [], preferredTransform: .identity,
            presentationSize: CGSize(width: 1080, height: 1920), nominalFrameRate: 30, isReadable: true, isPlayable: true, hasVideoTrack: true)
    }

    func testSDROutputContractAcceptsOnly709H264QuickTimeWithoutHDRSignaling() {
        XCTAssertEqual(Phase6SpikeSDROutputContract.problems(sdrFacts()), [])
        var f = sdrFacts(); f.bitsPerComponent = 8
        XCTAssertEqual(Phase6SpikeSDROutputContract.problems(f), [])
        // 7. Remaining HLG / PQ / Rec.2020 / Dolby Vision signaling is rejected.
        f = sdrFacts(); f.transferFunction = hlg
        XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("HLG signaling remains") })
        f = sdrFacts(); f.transferFunction = pq
        XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("PQ signaling remains") })
        f = sdrFacts(); f.colorPrimaries = p2020
        XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("Rec.2020 signaling remains") })
        f = sdrFacts(); f.ycbcrMatrix = m2020
        XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("Rec.2020 signaling remains") })
        f = sdrFacts(); f.hdrMetadataNotes = ["Dolby Vision config atom dvcC present"]
        XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("Dolby Vision metadata remains") })
        f = sdrFacts(); f.hdrMetadataNotes = ["MasteringDisplayColorVolume", "ContentLightLevelInfo"]
        XCTAssertFalse(Phase6SpikeSDROutputContract.problems(f).isEmpty)
        // 8. Rec.709 / Rec.709 / Rec.709 is required (untagged is not accepted either).
        f = sdrFacts(); f.colorPrimaries = nil
        XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("primaries untagged != Rec.709") })
        f = sdrFacts(); f.transferFunction = nil
        XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("transfer untagged != Rec.709") })
        f = sdrFacts(); f.ycbcrMatrix = nil
        XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("matrix untagged != Rec.709") })
        // Codec / bit depth / container / transform / orientation / frame rate.
        f = sdrFacts(); f.videoCodec = "hvc1"; XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("not H.264") })
        f = sdrFacts(); f.profileIsHighBitDepth = true; f.profileDescription = "H.264 High 10"; XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("high-bit-depth") })
        f = sdrFacts(); f.bitsPerComponent = 10; XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("10 bits") })
        f = sdrFacts(); f.container = .mp4; XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("not QuickTime") })
        f = sdrFacts(); f.preferredTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0); XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("not identity") })
        f = sdrFacts(); f.presentationSize = CGSize(width: 1920, height: 1080); XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("not portrait") })
        f = sdrFacts(); f.nominalFrameRate = 60; XCTAssertTrue(Phase6SpikeSDROutputContract.problems(f).contains { $0.contains("> 30") })
        // The media-info bridge evaluates the same contract.
        var info = sampleInfo("out.mov"); info.naturalSize = CGSize(width: 1080, height: 1920); info.preferredTransform = .identity; info.presentationSize = CGSize(width: 1080, height: 1920)
        info.colorPrimaries = p709; info.transferFunction = t709; info.ycbcrMatrix = m709; info.profileDescription = "H.264 High L4.0"
        XCTAssertEqual(info.sdrOutputProblems, [])
        info.transferFunction = hlg; info.hdrMetadataNotes = ["Dolby Vision config atom dvvC present"]
        XCTAssertTrue(info.hasDolbyVisionConfiguration); XCTAssertEqual(info.sdrOutputProblems.count, 3)
    }

    func testRecordCarriesSDRContractResultOnlyForCompletedRunsAndOlderSchemasDecode() throws {
        var out = sampleInfo("out.mov"); out.naturalSize = CGSize(width: 1080, height: 1920); out.preferredTransform = .identity; out.presentationSize = CGSize(width: 1080, height: 1920)
        out.colorPrimaries = p709; out.transferFunction = t709; out.ycbcrMatrix = m709; out.profileDescription = "H.264 High L4.0"
        let ok = Phase6SpikeRunRecord.make(runID: UUID(), startedAt: Date(), endedAt: Date(), source: sampleInfo(), output: out, intendedPath: "normalize", result: sampleResult(), progressReached: 1, pollingInterval: 0.25, leftovers: [])
        XCTAssertEqual(ok.schemaVersion, 3); XCTAssertEqual(ok.outputIsValidSDR, true); XCTAssertEqual(ok.outputSDRProblems, [])
        var bad = out; bad.transferFunction = hlg
        let notSDR = Phase6SpikeRunRecord.make(runID: UUID(), startedAt: Date(), endedAt: Date(), source: sampleInfo(), output: bad, intendedPath: "normalize", result: sampleResult(), progressReached: 1, pollingInterval: 0.25, leftovers: [])
        XCTAssertEqual(notSDR.outputIsValidSDR, false); XCTAssertEqual(notSDR.outputSDRProblems?.isEmpty, false)
        var cancelled = sampleResult(); cancelled.succeeded = false; cancelled.cancelled = true
        let c = Phase6SpikeRunRecord.make(runID: UUID(), startedAt: Date(), endedAt: Date(), source: sampleInfo(), output: out, intendedPath: "normalize", result: cancelled, progressReached: 0.3, pollingInterval: 0.25, leftovers: [])
        XCTAssertNil(c.outputIsValidSDR); XCTAssertNil(c.outputSDRProblems); XCTAssertNil(c.outputSnapshot)
        // Schema-2 document (no schema-3 keys) still decodes.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Phase6SpikeResultStore.encoder().encode(ok)) as? [String: Any])
        json.removeValue(forKey: "outputIsValidSDR"); json.removeValue(forKey: "outputSDRProblems"); json["schemaVersion"] = 2
        let v2 = try Phase6SpikeResultStore.decoder().decode(Phase6SpikeRunRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(v2.schemaVersion, 2); XCTAssertNil(v2.outputIsValidSDR); XCTAssertEqual(v2.runID, ok.runID)
    }

    // MARK: ADR-044 — QuickTime-only container eligibility (no remux route)

    func testReadyQuickTimeRoutesToFastPathForH264AndHEVC() {
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input()).path, .readyQuickTimeFastPath)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(codec: "hvc1")).path, .readyQuickTimeFastPath, "QuickTime eligibility is not H.264-only")
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(codec: "hev1")).path, .readyQuickTimeFastPath)
    }

    func testNormalizationRequiredQuickTimeRoutesToNormalization() {
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(size: CGSize(width: 2160, height: 3840))).path, .normalizeH264)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(codec: "hvc1", bpc: nil, highBitDepth: true)).path, .normalizeH264, "QuickTime HEVC Main10 still normalizes")
    }

    func testActualMP4ContainerIsPreflightUnsupported() {
        let v = Phase6SpikePathClassifier.classify(input(container: .mp4))
        XCTAssertEqual(v.path, .preflightUnsupportedContainer)
        XCTAssertTrue(v.reasons.contains { $0.contains("MP4 / ISO BMFF") && $0.contains("no remux") }, "\(v.reasons)")
        // Otherwise-normalization-required MP4 must not become normalization-required either.
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(container: .mp4, size: CGSize(width: 2160, height: 3840))).path, .preflightUnsupportedContainer)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(container: .mp4, fps: 60)).path, .preflightUnsupportedContainer)
    }

    func testOtherAndUnknownContainersArePreflightUnsupported() {
        // Any non-`qt  ` ftyp brand set sniffs as ISO BMFF (e.g. 3gp / m4v / avc1 brands); no ftyp is unknown.
        XCTAssertEqual(Phase6SpikeContainer.sniff(headerBytes: Self.ftyp(["3gp4", "3gp4"])).container, .mp4)
        XCTAssertEqual(Phase6SpikeContainer.sniff(headerBytes: Self.ftyp(["M4V ", "M4V ", "mp42"])).container, .mp4)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(container: .mp4)).path, .preflightUnsupportedContainer)
        let unknown = Phase6SpikePathClassifier.classify(input(container: .unknown))
        XCTAssertEqual(unknown.path, .preflightUnsupportedContainer, "unreliable / unknown container is safely unsupported under ADR-044")
        XCTAssertTrue(unknown.reasons.contains { $0.contains("unknown") })
    }

    func testFileExtensionIsNotAuthoritativeForContainerEligibility() {
        // Renamed MP4 with a .mov extension → unsupported.
        var renamedMP4 = sampleInfo("renamed.mov"); renamedMP4.fileExtension = "mov"; renamedMP4.container = .mp4; renamedMP4.brands = "mp42,mp42,isom"
        renamedMP4.naturalSize = CGSize(width: 1080, height: 1920); renamedMP4.preferredTransform = .identity; renamedMP4.presentationSize = CGSize(width: 1080, height: 1920)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(renamedMP4.classificationInput).path, .preflightUnsupportedContainer)
        // Proven QuickTime with a .mp4 extension → container-eligible.
        var renamedMov = renamedMP4; renamedMov.fileExtension = "mp4"; renamedMov.container = .quickTime; renamedMov.brands = "qt  ,qt  "
        XCTAssertEqual(Phase6SpikePathClassifier.classify(renamedMov.classificationInput).path, .readyQuickTimeFastPath)
        // The classification input carries no extension at all.
        XCTAssertEqual(renamedMP4.classificationInput.container, .mp4); XCTAssertEqual(renamedMov.classificationInput.container, .quickTime)
    }

    @MainActor
    func testUnsupportedContainerCannotStartConversionAndCreatesNoOutput() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("spike-container-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let model = Phase6MediaSpikeModel()
        var item = sampleInfo("clip.mp4"); item.container = .mp4; item.path = .preflightUnsupportedContainer; item.pathReasons = ["actual container is MP4 / ISO BMFF"]
        model.items = [item]; model.selectedID = item.id
        XCTAssertFalse(model.canStartConversion)
        XCTAssertFalse(model.canArmAutoCancel)
        model.startConversion()
        XCTAssertFalse(model.isRunning)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.outputInfo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.directory.outputsDirectory.appendingPathComponent("\(item.id.uuidString)-h264.mov").path))
        XCTAssertTrue(model.log.last?.contains("ADR-044") == true)
    }

    func testNoRemuxRouteRemains() {
        // Every path is enumerated here; adding a remux case would have to be added to this list.
        let all: [Phase6SpikePath] = [.readyQuickTimeFastPath, .normalizeH264, .preflightInvalid, .preflightUnsupportedContainer, .preflightUnsupportedNonPortrait]
        for path in all { XCTAssertFalse(path.rawValue.lowercased().contains("remux"), path.rawValue) }
        XCTAssertEqual(all.filter(\.mayRunMediaOperation), [.readyQuickTimeFastPath, .normalizeH264])
        // A ready MP4 has no route other than unsupported.
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(container: .mp4)).path, .preflightUnsupportedContainer)
    }

    /// Regression for the first LunaTestphone run: an ordinary iPhone 1080p30 SDR QuickTime capture
    /// (nominal 29.986961 fps, minFrameDuration 19/600 → 1/minFD ≈ 31.58) was wrongly routed to
    /// normalization only because of the metadata VFR heuristic. It must be ready / fast path.
    func testFirstRunSourceWithShortMinFrameDurationIsReadyFastPath() {
        var first = input(duration: CMTime(value: 2301, timescale: 600), container: .quickTime, codec: "avc1", size: CGSize(width: 1080, height: 1920), fps: 29.986961, transfer: kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String, primaries: kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String, bpc: nil, vfr: true)
        first.isPlayable = true
        let verdict = Phase6SpikePathClassifier.classify(first)
        XCTAssertEqual(verdict.path, .readyQuickTimeFastPath)
        XCTAssertTrue(verdict.reasons.isEmpty, "VFR suspicion is diagnostic only: \(verdict.reasons)")
        // The heuristic itself would flag this file; that must not change the verdict.
        let minFD = CMTime(value: 19, timescale: 600)
        XCTAssertGreaterThan(abs(1 / minFD.seconds - 29.986961), 1.0)
    }

    func testMetadataVFRSuspicionNeverTriggersNormalizationAlone() {
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(vfr: true)).path, .readyQuickTimeFastPath)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(container: .mp4, vfr: true)).path, .preflightUnsupportedContainer)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(fps: 60, vfr: true)).path, .normalizeH264, "a reliable nominal rate above 30 still normalizes")
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(fps: 59.94)).path, .normalizeH264)
    }

    func testNormalizationTriggers() {
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(size: CGSize(width: 2160, height: 3840))).path, .normalizeH264)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(fps: 60)).path, .normalizeH264)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(transfer: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)).path, .normalizeH264)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(dolbyVision: true)).path, .normalizeH264)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(bpc: 10)).path, .normalizeH264)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(codec: "hvc1", bpc: nil, highBitDepth: true)).path, .normalizeH264)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(codec: "apcn")).path, .normalizeH264)
    }

    // MARK: ADR-043 Revision 1 — orientation eligibility (presentation geometry, strict height > width)

    private let rotate90 = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
    private let rotate90Mirrored = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)

    func testPortraitPresentationIsOrientationEligible() {
        XCTAssertEqual(Phase6SpikeOrientationEligibility.classify(presentationSize: CGSize(width: 1080, height: 1920)), .portrait)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(size: CGSize(width: 1080, height: 1920))).path, .readyQuickTimeFastPath)
    }

    func testLandscapePresentationIsPreflightUnsupported() {
        XCTAssertEqual(Phase6SpikeOrientationEligibility.classify(presentationSize: CGSize(width: 1920, height: 1080)), .nonPortrait(.landscape))
        let verdict = Phase6SpikePathClassifier.classify(input(size: CGSize(width: 1920, height: 1080)))
        XCTAssertEqual(verdict.path, .preflightUnsupportedNonPortrait)
        XCTAssertTrue(verdict.reasons.contains { $0.contains("non-portrait presentation (landscape)") }, "\(verdict.reasons)")
    }

    func testSquarePresentationIsPreflightUnsupported() {
        XCTAssertEqual(Phase6SpikeOrientationEligibility.classify(presentationSize: CGSize(width: 1080, height: 1080)), .nonPortrait(.square))
        let verdict = Phase6SpikePathClassifier.classify(input(size: CGSize(width: 1080, height: 1080)))
        XCTAssertEqual(verdict.path, .preflightUnsupportedNonPortrait)
        XCTAssertTrue(verdict.reasons.contains { $0.contains("(square)") }, "\(verdict.reasons)")
    }

    func testNaturalLandscapeWithNinetyDegreeTransformIsPortraitEligible() {
        let natural = CGSize(width: 1920, height: 1080)
        let presentation = Phase6SpikeOrientationEligibility.presentationSize(naturalSize: natural, preferredTransform: rotate90)
        XCTAssertEqual(presentation, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(Phase6SpikeOrientationEligibility.classify(naturalSize: natural, preferredTransform: rotate90), .portrait)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(size: presentation)).path, .readyQuickTimeFastPath)
        // Natural size alone would have said landscape — it must not decide.
        XCTAssertEqual(Phase6SpikeOrientationEligibility.classify(presentationSize: natural), .nonPortrait(.landscape))
    }

    func testNaturalPortraitWithIdentityTransformIsPortraitEligible() {
        XCTAssertEqual(Phase6SpikeOrientationEligibility.classify(naturalSize: CGSize(width: 1080, height: 1920), preferredTransform: .identity), .portrait)
    }

    func testMirroredPortraitPresentationStaysEligible() {
        let natural = CGSize(width: 1920, height: 1080)
        XCTAssertLessThan(rotate90Mirrored.a * rotate90Mirrored.d - rotate90Mirrored.b * rotate90Mirrored.c, 0, "fixture must be a mirroring transform")
        XCTAssertEqual(Phase6SpikeOrientationEligibility.presentationSize(naturalSize: natural, preferredTransform: rotate90Mirrored), CGSize(width: 1080, height: 1920))
        XCTAssertEqual(Phase6SpikeOrientationEligibility.classify(naturalSize: natural, preferredTransform: rotate90Mirrored), .portrait)
        XCTAssertEqual(Phase6SpikeOrientationEligibility.classify(naturalSize: CGSize(width: 1080, height: 1920), preferredTransform: CGAffineTransform(scaleX: -1, y: 1)), .portrait)
    }

    func testNonPortraitNeverBecomesNormalizationRequiredOrRoutesToAnyMediaOperation() {
        let landscape = CGSize(width: 1920, height: 1080), square = CGSize(width: 720, height: 720)
        // Every route the converter / copier knows: none may be reached from a non-portrait source,
        // regardless of container (copy) or normalization triggers (H.264 / raster / fps / HDR).
        let variants: [Phase6SpikeClassificationInput] = [
            input(container: .quickTime, size: landscape),                       // would be fast-path copy
            input(container: .mp4, size: landscape),                             // also unsupported container
            input(container: .quickTime, size: CGSize(width: 3840, height: 2160)), // would be raster normalization
            input(container: .mp4, size: landscape, fps: 60),                    // would be frame-rate normalization
            input(size: landscape, transfer: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String), // would be HDR normalization
            input(container: .quickTime, size: square),
            input(container: .mp4, size: square),
            input(container: .unknown, size: square),                            // also unsupported container
            input(codec: "apcn", size: landscape),                               // would be codec normalization
        ]
        for v in variants {
            let verdict = Phase6SpikePathClassifier.classify(v)
            // Container and orientation are independent preflight classifications; either alone blocks media work.
            XCTAssertTrue(verdict.path == .preflightUnsupportedNonPortrait || verdict.path == .preflightUnsupportedContainer, "\(v.presentationSize) \(v.container) → \(verdict.path)")
            if v.container == .quickTime { XCTAssertEqual(verdict.path, .preflightUnsupportedNonPortrait) }
            XCTAssertFalse(verdict.path.mayRunMediaOperation)
            XCTAssertNotEqual(verdict.path, .normalizeH264)
            XCTAssertNotEqual(verdict.path, .readyQuickTimeFastPath)
            XCTAssertFalse(verdict.reasons.contains { $0.contains("raster") || $0.contains("frame rate") || $0.contains("HDR") || $0.contains("codec") }, "no normalization reason may be attached: \(verdict.reasons)")
        }
    }

    @MainActor
    func testConversionControlIsDisabledForNonPortraitAndInvalidItems() {
        let model = Phase6MediaSpikeModel()
        var item = sampleInfo("landscape.mov")
        item.presentationSize = CGSize(width: 1920, height: 1080); item.path = .preflightUnsupportedNonPortrait
        model.items = [item]; model.selectedID = item.id
        XCTAssertFalse(model.canStartConversion)
        model.startConversion()
        XCTAssertFalse(model.isRunning, "a non-portrait item must never start copy / normalization")
        XCTAssertTrue(model.results.isEmpty)
        var invalid = sampleInfo("invalid.mov"); invalid.path = .preflightInvalid
        model.items = [invalid]; model.selectedID = invalid.id
        XCTAssertFalse(model.canStartConversion)
        var ready = sampleInfo("ready.mov"); ready.path = .readyQuickTimeFastPath
        model.items = [ready]; model.selectedID = ready.id
        XCTAssertTrue(model.canStartConversion)
    }

    func testPortraitNormalizationAndReadyRoutesAreUnchangedByOrientationRule() {
        // 11. portrait 4K30 SDR → raster normalization
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(size: CGSize(width: 2160, height: 3840))).reasons, ["raster > 1080p-class"])
        // 12. portrait 1080p60 SDR → frame-rate normalization
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(fps: 60)).reasons, ["frame rate > 30"])
        // 13. portrait HDR → normalization
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(transfer: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)).path, .normalizeH264)
        // 14. portrait ready QuickTime → fast-path copy
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(container: .quickTime)).path, .readyQuickTimeFastPath)
        // 15. (ADR-044) portrait ready MP4 → preflight unsupported, never remux
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(container: .mp4)).path, .preflightUnsupportedContainer)
    }

    func testPreflightInvalidVerdicts() {
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(duration: CMTime(value: 24, timescale: 60))).path, .preflightInvalid)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(duration: CMTime(value: 151, timescale: 30))).path, .preflightInvalid)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(duration: .invalid)).path, .preflightInvalid)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(readable: false)).path, .preflightInvalid)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(video: false)).path, .preflightInvalid)
        XCTAssertEqual(Phase6SpikePathClassifier.classify(input(protected: true)).path, .preflightInvalid)
    }

    static func ftyp(_ brands: [String]) -> Data {
        var data = Data(); let size = UInt32(8 + 4 + 4 + (brands.count - 1) * 4)
        data.append(contentsOf: withUnsafeBytes(of: size.bigEndian, Array.init)); data.append("ftyp".data(using: .ascii)!)
        data.append(brands[0].data(using: .ascii)!); data.append(contentsOf: [0, 0, 0, 0])
        for b in brands.dropFirst() { data.append(b.data(using: .ascii)!) }
        return data
    }

    func testContainerSniffing() {
        XCTAssertEqual(Phase6SpikeContainer.sniff(headerBytes: Self.ftyp(["qt  ", "qt  "])).container, .quickTime)
        XCTAssertEqual(Phase6SpikeContainer.sniff(headerBytes: Self.ftyp(["mp42", "mp42", "isom"])).container, .mp4)
        XCTAssertEqual(Phase6SpikeContainer.sniff(headerBytes: Data(repeating: 7, count: 32)).container, .unknown)
        XCTAssertEqual(Phase6SpikeContainer.sniff(headerBytes: Data()).container, .unknown)
    }

    // MARK: Deterministic cancellation (shared token, auto-cancel at 35%)

    func testCancellationTokenIsIdempotentAndFirstRequestWins() {
        let token = Phase6SpikeCancellationToken()
        XCTAssertFalse(token.isCancelled); XCTAssertNil(token.source); XCTAssertEqual(token.requestCount, 0)
        XCTAssertTrue(token.requestCancel(source: .automatic, progress: 0.36))
        XCTAssertFalse(token.requestCancel(source: .manual, progress: 0.40), "a nearly simultaneous manual tap is absorbed")
        XCTAssertFalse(token.requestCancel(source: .manual, progress: 0.41))
        XCTAssertTrue(token.isCancelled)
        XCTAssertEqual(token.source, .automatic)
        XCTAssertEqual(token.requestedProgress, 0.36)
        XCTAssertEqual(token.requestCount, 3)
        XCTAssertNotNil(token.requestedAt)
    }

    func testAutoCancelDisabledByDefaultAndFiresOnceAtThreshold() {
        XCTAssertEqual(Phase6SpikeAutoCancel.threshold, 0.35)
        XCTAssertFalse(Phase6SpikeAutoCancel.shouldFire(threshold: nil, progress: 0.99, alreadyFired: false), "OFF never fires")
        XCTAssertFalse(Phase6SpikeAutoCancel.shouldFire(threshold: 0.35, progress: 0.349, alreadyFired: false))
        XCTAssertTrue(Phase6SpikeAutoCancel.shouldFire(threshold: 0.35, progress: 0.35, alreadyFired: false), "fires at the first value >= threshold")
        XCTAssertTrue(Phase6SpikeAutoCancel.shouldFire(threshold: 0.35, progress: 0.70, alreadyFired: false))
        XCTAssertFalse(Phase6SpikeAutoCancel.shouldFire(threshold: 0.35, progress: 0.70, alreadyFired: true), "fires once")
        // Simulated sample-based progress sequence: exactly one firing, at the first sample >= 0.35.
        var fired = false; var firedAt: Double?
        for p in stride(from: 0.0, through: 1.0, by: 0.037) where Phase6SpikeAutoCancel.shouldFire(threshold: 0.35, progress: p, alreadyFired: fired) { fired = true; firedAt = p }
        XCTAssertEqual(firedAt.map { ($0 * 1000).rounded() / 1000 }, 0.37)
    }

    /// Regression for the HDR device runs of 2026-09-18: with the default `.automatic` encoding
    /// Photos delivered an H.264 Rec.709 compatibility transcode of an HEVC HDR capture, so the
    /// inspector never saw HDR. The spike must request the original representation, as production does.
    @MainActor
    func testPickerRequestsOriginalRepresentationAndLogsIt() {
        XCTAssertEqual(Phase6MediaSpikeModel.pickerEncoding, .current)
        let model = Phase6MediaSpikeModel()
        model.pickerItems = []
        model.handlePickerSelection()
        XCTAssertFalse(model.log.contains { $0.hasPrefix("picker encoding:") }, "no selection → no acquisition log line")
    }

    @MainActor
    func testAutoCancelDefaultsOffAndIsOnlyArmableForNormalizationRequiredQuickTime() {
        let model = Phase6MediaSpikeModel()
        XCTAssertFalse(model.autoCancelAtThresholdEnabled)
        var normalize = sampleInfo("4k.mov"); normalize.path = .normalizeH264
        var ready = sampleInfo("ready.mov"); ready.path = .readyQuickTimeFastPath
        var mp4 = sampleInfo("x.mp4"); mp4.container = .mp4; mp4.path = .preflightUnsupportedContainer
        model.items = [normalize, ready, mp4]
        model.selectedID = normalize.id; XCTAssertTrue(model.canArmAutoCancel)
        model.selectedID = ready.id; XCTAssertFalse(model.canArmAutoCancel)
        model.selectedID = mp4.id; XCTAssertFalse(model.canArmAutoCancel)
        model.selectedID = nil; XCTAssertFalse(model.canArmAutoCancel)
    }

    @MainActor
    func testManualCancelUsesSharedTokenAndIsIdempotent() {
        let model = Phase6MediaSpikeModel()
        // No run in flight: cancel is a safe no-op.
        model.cancel(); XCTAssertNil(model.activeCancellation)
        // Inject an in-flight run state and verify manual cancel goes through the same token.
        model.isRunning = true
        let token = Phase6SpikeCancellationToken()
        model.setActiveCancellationForTesting(token)
        model.cancel(); model.cancel()
        XCTAssertTrue(token.isCancelled); XCTAssertEqual(token.source, .manual); XCTAssertEqual(token.requestCount, 2)
        // Automatic request arriving after the manual one is absorbed, not a crash / flip.
        XCTAssertFalse(token.requestCancel(source: .automatic, progress: 0.35)); XCTAssertEqual(token.source, .manual)
    }

    @MainActor
    func testCancelledRunNeverBecomesSuccessOrPublishesOutput() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("spike-cancel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let model = Phase6MediaSpikeModel()
        let item = sampleInfo("4k.mov")
        var result = sampleResult()
        result.succeeded = false; result.cancelled = true; result.readerStatus = "cancelled"; result.writerStatus = "cancelled"
        result.autoCancelThreshold = 0.35; result.cancellationSource = "automatic"; result.cancellationRequestedProgress = 0.36; result.cancellationRequestCount = 1
        result.partialOutputExistedAfterCancel = true; result.cleanupSucceeded = true; result.outputExistsAfterCleanup = false
        model.isRunning = true
        model.finishRun(result: result, item: item, runID: UUID(), startedAt: Date(), intendedPath: "normalize")
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.activeCancellation)
        XCTAssertEqual(model.results.last?.cancelled, true); XCTAssertEqual(model.results.last?.succeeded, false)
        XCTAssertNil(model.outputInfo, "no output snapshot for a cancelled run")
        XCTAssertTrue(model.restoredOutputs.isEmpty, "no playable output is published")
        // A "succeeded + cancelled" contradiction still resolves to no publication.
        var contradictory = result; contradictory.succeeded = true
        model.finishRun(result: contradictory, item: item, runID: UUID(), startedAt: Date(), intendedPath: "normalize")
        XCTAssertNil(model.outputInfo); XCTAssertTrue(model.restoredOutputs.isEmpty)
    }

    func testPartialOutputCleanupIsIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spike-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let partial = dir.appendingPathComponent("x-h264.mov")
        try Data(repeating: 1, count: 4096).write(to: partial)
        let first = Phase6SpikeConverter.cleanupPartialOutput(at: partial)
        XCTAssertTrue(first.existed); XCTAssertTrue(first.succeeded); XCTAssertNil(first.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path), "partial output is removed")
        let second = Phase6SpikeConverter.cleanupPartialOutput(at: partial)
        XCTAssertFalse(second.existed); XCTAssertTrue(second.succeeded, "cleanup succeeds when no partial file exists")
        let third = Phase6SpikeConverter.cleanupPartialOutput(at: partial)
        XCTAssertTrue(third.succeeded, "repeated cleanup stays safe")
    }

    func testSourceUnchangedEvidence() {
        var r = sampleResult()
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(r.sourceUnchanged, "unknown until the after-run sample exists")
        r.sourceModificationBefore = t; r.sourceModificationAfter = t; r.sourceBytesAfter = r.sourceBytes
        XCTAssertEqual(r.sourceUnchanged, true)
        r.sourceBytesAfter = r.sourceBytes + 1
        XCTAssertEqual(r.sourceUnchanged, false)
        r.sourceBytesAfter = r.sourceBytes; r.sourceModificationAfter = t.addingTimeInterval(1)
        XCTAssertEqual(r.sourceUnchanged, false)
    }

    func testCancelledRecordRoundTripsWithCancellationEvidenceAndNoOutputSnapshot() throws {
        let (store, base) = try makeStore(); defer { try? FileManager.default.removeItem(at: base) }
        var r = sampleResult()
        r.succeeded = false; r.cancelled = true; r.readerStatus = "cancelled"; r.writerStatus = "cancelled"; r.videoSamples = 40; r.audioSamples = 3; r.elapsed = 0.31
        r.autoCancelThreshold = 0.35; r.cancellationSource = "automatic"; r.cancellationRequestedProgress = 0.361; r.cancellationRequestedAt = Date(timeIntervalSince1970: 2_000); r.cancellationRequestCount = 2
        r.partialOutputExistedAfterCancel = true; r.cleanupSucceeded = true; r.outputExistsAfterCleanup = false
        r.sourceModificationBefore = Date(timeIntervalSince1970: 500); r.sourceModificationAfter = Date(timeIntervalSince1970: 500); r.sourceBytesAfter = r.sourceBytes
        r.notes = ["DETERMINISTIC CANCELLATION TEST: auto-cancel armed at progress >= 0.35"]
        let source = sampleInfo()
        let runID = UUID()
        // Even if a caller passes an output snapshot, a cancelled record must not carry one.
        let record = Phase6SpikeRunRecord.make(runID: runID, startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_001), source: source, output: sampleInfo("should-not-appear.mov"), intendedPath: "normalize", result: r, progressReached: 0.361, pollingInterval: 0.25, leftovers: ["outputs/\(source.id.uuidString)-h264.mov", "outputs/other.mov"])
        XCTAssertEqual(record.schemaVersion, 3)
        XCTAssertNil(record.outputSnapshot); XCTAssertNil(record.outputFileName)
        XCTAssertEqual(record.outputCandidateFileName, "x-h264.mov")
        XCTAssertEqual(record.autoCancelEnabled, true); XCTAssertEqual(record.autoCancelThreshold, 0.35)
        XCTAssertEqual(record.cancellationSource, "automatic"); XCTAssertEqual(record.cancellationRequestedProgress, 0.361); XCTAssertEqual(record.cancellationRequestCount, 2)
        XCTAssertEqual(record.partialOutputExistedAfterCancel, true); XCTAssertEqual(record.cleanupSucceeded, true); XCTAssertEqual(record.outputExistsAfterCleanup, false)
        XCTAssertEqual(record.sourceUnchanged, true); XCTAssertEqual(record.sourceBytesAfter, r.sourceBytes)
        XCTAssertEqual(record.runLeftoverFiles, ["outputs/\(source.id.uuidString)-h264.mov"], "only leftovers attributable to this run / item")
        XCTAssertEqual(record.outcomeLabel, "cancelled"); XCTAssertFalse(record.succeeded)
        XCTAssertNil(store.write(record))
        let listed = store.list()
        guard case .record(let back, _)? = listed.first else { return XCTFail("record not listed") }
        XCTAssertEqual(back.runID, runID); XCTAssertEqual(back.cancellationRequestedProgress, 0.361); XCTAssertEqual(back.autoCancelThreshold, 0.35)
        XCTAssertEqual(back.cancellationRequestedAt, Date(timeIntervalSince1970: 2_000)); XCTAssertNil(back.outputSnapshot); XCTAssertTrue(back.cancelled)
        XCTAssertTrue(back.pipelineNotes.contains { $0.contains("DETERMINISTIC CANCELLATION TEST") })
    }

    func testSchemaVersionOneRecordsStillDecode() throws {
        // Build a schema-1 document: encode a current record, then strip every schema-2 key and set the version.
        let record = Phase6SpikeRunRecord.make(runID: UUID(), startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_001), source: sampleInfo(), output: sampleInfo("out.mov"), intendedPath: "normalize", result: sampleResult(), progressReached: 1, pollingInterval: 0.25, leftovers: [])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Phase6SpikeResultStore.encoder().encode(record)) as? [String: Any])
        for key in ["autoCancelEnabled", "autoCancelThreshold", "cancellationSource", "cancellationRequestedProgress", "cancellationRequestedAt", "cancellationRequestCount", "outputCandidateFileName", "outputExistsAfterCleanup", "runLeftoverFiles", "sourceBytesAfter", "sourceModificationBefore", "sourceModificationAfter", "sourceUnchanged", "outputIsValidSDR", "outputSDRProblems"] { json.removeValue(forKey: key) }
        json["schemaVersion"] = 1
        json["intendedPath"] = "remux" // an earlier build's label must still decode as data
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try Phase6SpikeResultStore.decoder().decode(Phase6SpikeRunRecord.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.runID, record.runID); XCTAssertEqual(decoded.intendedPath, "remux")
        XCTAssertNil(decoded.autoCancelEnabled); XCTAssertNil(decoded.cancellationRequestedProgress); XCTAssertNil(decoded.sourceUnchanged); XCTAssertNil(decoded.runLeftoverFiles)
        XCTAssertEqual(decoded.outcomeLabel, "success")
        XCTAssertEqual(decoded.sourceSnapshot, record.sourceSnapshot)
    }

    // MARK: Diagnostic directory isolation and cleanup

    func testDirectoryIsOutsideProductionRootAndCleanupIsIdempotent() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("spike-\(UUID().uuidString)", isDirectory: true)
        let directory = Phase6SpikeDirectory(root: base.appendingPathComponent(Phase6SpikeDirectory.componentName, isDirectory: true))
        XCTAssertFalse(directory.owns(base.appendingPathComponent("Mellow/Projects/x.mov")))
        XCTAssertFalse(Phase6SpikeDirectory.default().root.path.contains("/Mellow/"), "spike root must not live under the production Mellow root")
        try directory.prepare()
        try Data([1, 2, 3]).write(to: directory.outputsDirectory.appendingPathComponent("a.mov"))
        XCTAssertTrue(directory.owns(directory.outputsDirectory.appendingPathComponent("a.mov")))
        XCTAssertEqual(directory.leftovers().count, 1)
        XCTAssertTrue(directory.cleanup().removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.root.path))
        let second = directory.cleanup()
        XCTAssertFalse(second.removed); XCTAssertNil(second.error, "second cleanup is a no-op")
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: Playback controller (ownership / routing / errors / cleanup — no playback success is asserted)

    func testPlaybackTargetRoutesToSpikeOwnedFiles() {
        let source = URL(fileURLWithPath: "/tmp/spike/sources/a.mov"), output = URL(fileURLWithPath: "/tmp/spike/outputs/a-h264.mov")
        XCTAssertEqual(Phase6SpikePlaybackTarget.source(source).url, source)
        XCTAssertEqual(Phase6SpikePlaybackTarget.output(output).url, output)
        XCTAssertEqual(Phase6SpikePlaybackTarget.source(source).label, "원본")
        XCTAssertEqual(Phase6SpikePlaybackTarget.output(output).label, "변환 결과")
    }

    @MainActor
    func testPlaybackControllerReportsMissingFileWithoutCreatingPlayer() {
        let controller = Phase6SpikePlaybackController()
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing-\(UUID().uuidString).mov")
        XCTAssertFalse(controller.open(.source(missing)))
        XCTAssertNil(controller.player)
        XCTAssertEqual(controller.loadError, "파일 없음: \(missing.lastPathComponent)")
        XCTAssertTrue(controller.isOpen, "target is recorded so the sheet can show the error")
        controller.close()
        XCTAssertFalse(controller.isOpen); XCTAssertNil(controller.loadError)
    }

    @MainActor
    func testPlaybackControllerKeepsOnePlayerAndReleasesObserversOnClose() async throws {
        let url = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let controller = Phase6SpikePlaybackController()
        XCTAssertTrue(controller.open(.source(url)))
        let first = try XCTUnwrap(controller.player)
        XCTAssertGreaterThan(controller.observerCount, 0)
        XCTAssertTrue(controller.player === first, "same instance across reads")
        controller.play()
        XCTAssertEqual(controller.playCommands, 1)
        controller.pause()
        XCTAssertTrue(controller.player === first, "play / pause never recreate the player")
        // Opening another target replaces the player exactly once and tears the old one down.
        XCTAssertTrue(controller.open(.output(url)))
        XCTAssertFalse(controller.player === first)
        controller.close()
        XCTAssertNil(controller.player); XCTAssertEqual(controller.observerCount, 0); XCTAssertFalse(controller.isOpen)
        controller.close() // idempotent
        XCTAssertEqual(controller.observerCount, 0)
    }

    // MARK: Durable run records

    private func sampleInfo(_ name: String = "src.mov") -> Phase6SpikeMediaInfo {
        var info = Phase6SpikeMediaInfo(url: URL(fileURLWithPath: "/tmp/spike/sources/\(name)"), displayName: name, fileExtension: "mov", byteCount: 1234)
        info.container = .quickTime; info.brands = "qt  ,qt  "; info.isReadable = true; info.isPlayable = true; info.isExportable = true
        info.duration = CMTime(value: 2160, timescale: 600); info.hasVideoTrack = true; info.videoCodec = "avc1"; info.profileDescription = "H.264 High L5.1"
        info.naturalSize = CGSize(width: 3840, height: 2160); info.preferredTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 2160, ty: 0)
        info.presentationSize = CGSize(width: 2160, height: 3840); info.nominalFrameRate = 30; info.minFrameDuration = CMTime(value: 20, timescale: 600)
        info.colorPrimaries = "ITU_R_709_2"; info.transferFunction = "ITU_R_709_2"; info.ycbcrMatrix = "ITU_R_709_2"
        info.hasAudioTrack = true; info.audioCodec = "aac"; info.audioSampleRate = 48000; info.audioChannels = 2
        info.path = .normalizeH264; info.pathReasons = ["raster > 1080p-class"]
        return info
    }

    private func sampleResult() -> Phase6SpikeResult {
        var r = Phase6SpikeResult(mode: "H.264 709 normalization", outputURL: URL(fileURLWithPath: "/tmp/spike/outputs/x-h264.mov"))
        r.succeeded = true; r.readerStatus = "completed"; r.writerStatus = "completed"; r.elapsed = 0.88; r.videoSamples = 108; r.audioSamples = 7
        r.footprintBefore = 54_003_696; r.footprintPeak = 55_101_424; r.footprintAfter = 55_068_656
        r.capacityBefore = 32_042_148_725; r.capacityMinimumDuring = 32_042_148_725; r.capacityAfter = 32_042_148_725
        r.sourceBytes = 11_531_294; r.outputBytes = 4_355_325; r.notes = ["raster 1080×1920", "audio passthrough (aac)"]
        return r
    }

    private func makeStore() throws -> (Phase6SpikeResultStore, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("spike-results-\(UUID().uuidString)", isDirectory: true)
        let directory = Phase6SpikeDirectory(root: base.appendingPathComponent(Phase6SpikeDirectory.componentName, isDirectory: true))
        try directory.prepare()
        return (Phase6SpikeResultStore(directory: directory), base)
    }

    func testRunRecordEncodeDecodeRoundTrip() throws {
        let record = Phase6SpikeRunRecord.make(runID: UUID(), startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_001), source: sampleInfo(), output: sampleInfo("out.mov"), intendedPath: "normalize", result: sampleResult(), progressReached: 1, pollingInterval: 0.25, leftovers: [])
        let data = try Phase6SpikeResultStore.encoder().encode(record)
        let decoded = try Phase6SpikeResultStore.decoder().decode(Phase6SpikeRunRecord.self, from: data)
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.schemaVersion, Phase6SpikeRunRecord.currentSchemaVersion)
        XCTAssertEqual(decoded.sourceSnapshot.duration.value, 2160); XCTAssertEqual(decoded.sourceSnapshot.duration.timescale, 600)
        XCTAssertEqual(decoded.sourceSnapshot.transform, [0, 1, -1, 0, 2160, 0])
        XCTAssertEqual(decoded.classificationReasons, ["raster > 1080p-class"])
        XCTAssertEqual(decoded.measuredTemporaryDeltaBytes, 0)
        XCTAssertTrue(decoded.capacitySamplingWarning.contains("LOWER BOUND"))
        XCTAssertEqual(decoded.outcomeLabel, "success")
    }

    func testRunRecordIsWrittenAtomicallyInsideResultsDirectory() throws {
        let (store, base) = try makeStore(); defer { try? FileManager.default.removeItem(at: base) }
        let record = Phase6SpikeRunRecord.make(runID: UUID(), startedAt: Date(), endedAt: Date(), source: sampleInfo(), output: nil, intendedPath: "normalize", result: sampleResult(), progressReached: 1, pollingInterval: 0.25, leftovers: [])
        XCTAssertNil(store.write(record))
        let url = store.url(for: record)
        XCTAssertTrue(store.directory.owns(url))
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "results")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let leftoverTemps = try FileManager.default.contentsOfDirectory(atPath: store.directory.resultsDirectory.path).filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftoverTemps.isEmpty, "temporary file must be renamed away")
        // Re-writing the same run replaces the record in place (still exactly one file).
        XCTAssertNil(store.write(record))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.resultsDirectory.path).count, 1)
        guard case .record(let listed, let name)? = store.list().first else { return XCTFail("record not listed") }
        // ISO-8601 dates round-trip at second precision, so compare identity + payload, not whole-struct equality.
        XCTAssertEqual(listed.runID, record.runID); XCTAssertEqual(listed.outputBytes, record.outputBytes); XCTAssertEqual(listed.sourceSnapshot, record.sourceSnapshot)
        XCTAssertEqual(name, "\(record.runID.uuidString).json")
    }

    func testLoggingFailureIsReturnedAndDoesNotAlterResult() {
        // A results directory that cannot exist (a file occupies the spike root) makes writing fail.
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("spike-blocked-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: base.path, contents: Data([0]))
        defer { try? FileManager.default.removeItem(at: base) }
        let store = Phase6SpikeResultStore(directory: Phase6SpikeDirectory(root: base.appendingPathComponent("root", isDirectory: true)))
        let result = sampleResult()
        let record = Phase6SpikeRunRecord.make(runID: UUID(), startedAt: Date(), endedAt: Date(), source: sampleInfo(), output: nil, intendedPath: "normalize", result: result, progressReached: 1, pollingInterval: 0.25, leftovers: [])
        XCTAssertNotNil(store.write(record), "failure is reported as a value, never thrown")
        XCTAssertTrue(result.succeeded); XCTAssertEqual(result.outputBytes, 4_355_325, "the represented conversion result is untouched")
        XCTAssertEqual(store.list().count, 0)
    }

    func testCleanupRemovesResultFiles() throws {
        let (store, base) = try makeStore(); defer { try? FileManager.default.removeItem(at: base) }
        let record = Phase6SpikeRunRecord.make(runID: UUID(), startedAt: Date(), endedAt: Date(), source: sampleInfo(), output: nil, intendedPath: "copy", result: sampleResult(), progressReached: 1, pollingInterval: 0.25, leftovers: [])
        XCTAssertNil(store.write(record))
        XCTAssertEqual(store.directory.leftovers().count, 1, "the record is counted as spike content to clean")
        XCTAssertTrue(store.directory.cleanup().removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: record).path))
        XCTAssertEqual(store.list().count, 0)
    }

    func testCorruptOrMissingRecordIsSurfacedWithoutCrashing() throws {
        let (store, base) = try makeStore(); defer { try? FileManager.default.removeItem(at: base) }
        try Data("{ not json".utf8).write(to: store.directory.resultsDirectory.appendingPathComponent("broken.json"))
        try Data("ignored".utf8).write(to: store.directory.resultsDirectory.appendingPathComponent(".partial.json.tmp"))
        let good = Phase6SpikeRunRecord.make(runID: UUID(), startedAt: Date(), endedAt: Date(), source: sampleInfo(), output: nil, intendedPath: "normalize", result: sampleResult(), progressReached: 1, pollingInterval: 0.25, leftovers: [])
        XCTAssertNil(store.write(good))
        let listed = store.list()
        XCTAssertEqual(listed.count, 2, "hidden temp file is skipped; corrupt file is listed, not fatal")
        XCTAssertTrue(listed.contains { if case .unreadable(let name, _) = $0 { return name == "broken.json" } else { return false } })
        XCTAssertTrue(listed.contains { if case .record(let r, _) = $0 { return r.runID == good.runID } else { return false } })
        // Missing directory → empty list, no crash.
        let missing = Phase6SpikeResultStore(directory: Phase6SpikeDirectory(root: base.appendingPathComponent("nope", isDirectory: true)))
        XCTAssertEqual(missing.list().count, 0)
    }
}
#endif
