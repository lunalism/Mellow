import XCTest
@testable import Mellow

/// Pure tests for the Phase 6 Step 4A SDR working-media contract, the shared raster policy and the
/// normalization-plan builder (ADR-045 §3 / §6 / §7, ADR-047 Decision 1, ADR-048). No media, no
/// files, no AVFoundation: accepted items come from the real Step 3 preflight over an in-memory
/// facts table.
final class WorkingMediaNormalizationPlanTests: XCTestCase {
    // MARK: - Fixtures

    private let contract = SDRWorkingMediaContract.canonical
    private func time(_ value: Int64, _ timescale: Int32) -> MediaTime { try! MediaTime(value: value, timescale: timescale) }
    private func raster(_ width: Int, _ height: Int) -> WorkingMediaRaster { WorkingMediaRaster(width: width, height: height) }
    private func rasterPlan(_ width: Int, _ height: Int) -> WorkingMediaRasterPlan? { WorkingMediaRasterPolicy.plan(forPresentation: raster(width, height)) }
    private let rotate90 = ImportAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 2160, ty: 0)
    private let mirrorX = ImportAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2160, ty: 0)
    private let aacStereo = ImportAudioFacts(fourCC: "aac ", sampleRate: 48_000, channelCount: 2)

    /// Same instant regardless of timescale (`MediaTime` equality is structural).
    private func assertSameInstant(_ a: MediaTime, _ b: MediaTime, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(a < b || b < a, "\(a) ≠ \(b)", file: file, line: line)
    }

    /// Defaults: QuickTime HEVC 1080×1920 portrait, 30 fps, Rec.709 SDR, 2.0 s, AAC — fast path.
    private func facts(
        duration: MediaTime = try! MediaTime(value: 1200, timescale: 600),
        natural: (Int, Int) = (1080, 1920), transform: ImportAffineTransform = .identity,
        fps: Float = 30, minFrameDuration: MediaTime? = nil,
        transfer: ImportTransferFunction = .rec709, primaries: ImportColorPrimaries = .rec709, matrix: ImportYCbCrMatrix = .rec709,
        bpc: Int? = 8, hasAudioTrack: Bool = true, audio: ImportAudioFacts? = ImportAudioFacts(fourCC: "aac ", sampleRate: 48_000, channelCount: 2)
    ) -> ImportSourceFacts {
        ImportSourceFacts(
            duration: .exact(duration), isReadable: true, isPlayable: true, isExportable: true, hasProtectedContent: false,
            hasVideoTrack: true, hasAudioTrack: hasAudioTrack, container: .quickTime, videoCodec: .hevc(fourCC: "hvc1"),
            naturalWidth: natural.0, naturalHeight: natural.1, preferredTransform: transform,
            nominalFrameRate: fps, minimumFrameDuration: minFrameDuration, bitsPerComponent: bpc, highBitDepthProfile: .no,
            fullRangeVideo: .no, colorPrimaries: primaries, transferFunction: transfer, ycbcrMatrix: matrix,
            hasDolbyVisionConfiguration: false, ancillaryHDRMetadata: [],
            audio: audio, byteCount: 4_000_000, modificationDate: nil)
    }

    private func hdr(_ natural: (Int, Int) = (1080, 1920), fps: Float = 30, transform: ImportAffineTransform = .identity) -> ImportSourceFacts {
        facts(natural: natural, transform: transform, fps: fps, transfer: .hlg, primaries: .rec2020, matrix: .rec2020, bpc: 10)
    }

    private func audio(_ fourCC: String, channels: Int = 2) -> ImportAudioFacts {
        ImportAudioFacts(fourCC: fourCC, sampleRate: 44_100, channelCount: channels)
    }

    private struct TableInspector: ImportSourceInspecting {
        let facts: ImportSourceFacts
        func inspect(url: URL) async throws -> ImportSourceFacts { facts }
    }

    private func outcome(_ facts: ImportSourceFacts) async throws -> ImportSelectionPreflightOutcome {
        let candidate = ImportCandidate(url: URL(fileURLWithPath: "/nonexistent/candidate.mov"))
        return try await ImportSelectionPreflight(inspector: TableInspector(facts: facts)).run([candidate], context: .singleCandidate)
    }

    /// A real Step 3 accepted item: the builder is exercised through the production boundary.
    private func acceptedItem(_ facts: ImportSourceFacts, file: StaticString = #filePath, line: UInt = #line) async throws -> ImportAcceptedItem {
        let accepted = try await outcome(facts).accepted.first
        return try XCTUnwrap(accepted, "expected an accepted item", file: file, line: line)
    }

    private func plan(_ facts: ImportSourceFacts, file: StaticString = #filePath, line: UInt = #line) async throws -> WorkingMediaNormalizationPlan {
        try WorkingMediaPlanBuilder.plan(for: try await acceptedItem(facts, file: file, line: line))
    }

    private func assertPlanError(_ expected: WorkingMediaPlanError, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Any) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? WorkingMediaPlanError, expected, file: file, line: line) }
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}

    // MARK: - Contract

    func testCanonicalContractFields() {
        XCTAssertEqual(contract.container, .quickTime)
        XCTAssertEqual(contract.videoCodec, .h264)
        XCTAssertEqual(contract.videoProfile, .high)
        XCTAssertEqual(contract.bitsPerComponent, 8)
        XCTAssertEqual(contract.colorPrimaries, .rec709)
        XCTAssertEqual(contract.transferFunction, .rec709)
        XCTAssertEqual(contract.ycbcrMatrix, .rec709)
        XCTAssertEqual(contract.signalRange, .video)
        XCTAssertEqual(contract.rasterEnvelope, raster(1080, 1920))
        XCTAssertEqual(contract.rasterEnvelope, WorkingMediaRasterPolicy.envelope)
        XCTAssertEqual(contract.passthroughAudioFormatID, "aac ")
        XCTAssertEqual(contract.transcodedAudioCodec, .aacLC)
        XCTAssertEqual(contract.transcodedAudioSampleRate, 48_000)
        XCTAssertEqual(contract.monoAudioBitRate, 96_000)
        XCTAssertEqual(contract.stereoAudioBitRate, 128_000)
    }

    func testOutputTransformIsIdentity() {
        XCTAssertEqual(contract.outputTransform, .identity)
        XCTAssertTrue(contract.outputTransform.cgAffineTransform.isIdentity)
    }

    func testAcceptedOutputDurationWindow() {
        let source = time(1872, 600)
        let window = contract.acceptedOutputDuration(forSource: source)
        XCTAssertTrue(window.contains(source))
        XCTAssertTrue(window.contains(time(1880, 600)))               // +0.4 frame (ADR-045 evidence)
        XCTAssertTrue(window.contains(time(1892, 600)))               // exactly +1/30 s
        XCTAssertFalse(window.contains(time(1893, 600)))              // one tick past
        XCTAssertFalse(window.contains(time(1871, 600)))              // shorter than the source
        XCTAssertEqual(contract.outputDurationTolerance, time(1, 30))
    }

    func testContractValueSemanticsHashingAndSendable() {
        XCTAssertEqual(SDRWorkingMediaContract.canonical, contract)
        XCTAssertEqual(Set([SDRWorkingMediaContract.canonical, contract]).count, 1)
        requireSendable(SDRWorkingMediaContract.self)
        requireSendable(WorkingMediaNormalizationPlan.self)
        requireSendable(WorkingMediaRasterPlan.self)
        requireSendable(WorkingMediaAudioTranscodeSettings.self)
        requireSendable(WorkingMediaPlanError.self)
    }

    // MARK: - Cadence (ADR-048 Decision 3)

    private func frameDuration(_ minimum: MediaTime?, _ nominal: Float) -> MediaTime {
        contract.outputFrameDuration(sourceMinimumFrameDuration: minimum, nominalFrameRate: nominal)
    }

    func testValidMinimumFrameDurationIsAuthoritative() {
        XCTAssertEqual(contract.minimumFrameDuration, time(1, 30))
        XCTAssertEqual(frameDuration(time(1, 24), 30), time(1, 24))
        assertSameInstant(frameDuration(time(1, 30), 30), time(1, 30))
        assertSameInstant(frameDuration(time(1, 60), 60), time(1, 30))
        assertSameInstant(frameDuration(time(1, 120), 24), time(1, 30))                 // wins over a contradictory nominal rate
        XCTAssertEqual(frameDuration(time(1001, 30_000), 60), time(1001, 30_000))       // 29.97 kept despite nominal 60
        XCTAssertEqual(frameDuration(time(1, 24), .nan), time(1, 24))
    }

    func testNominalFrameRateFallbackWhenMinimumIsMissing() {
        // Exact reduced representation (MediaTime `==` is structural), not just the same instant.
        XCTAssertEqual(frameDuration(nil, 24), time(1, 24))
        assertSameInstant(frameDuration(nil, 24), time(1, 24))
        XCTAssertEqual(frameDuration(nil, 25), time(1, 25))
        XCTAssertEqual(frameDuration(nil, 29.97), time(1001, 30_000))
        assertSameInstant(frameDuration(nil, 29.97), time(1001, 30_000))
        XCTAssertEqual(frameDuration(nil, 23.976), time(1001, 24_000))
        XCTAssertEqual(frameDuration(nil, 30), time(1, 30))
        assertSameInstant(frameDuration(nil, 30), time(1, 30))
        for capped: Float in [48, 50, 59.94, 60, 120, 240] {
            XCTAssertEqual(frameDuration(nil, capped), time(1, 30), "\(capped)")
        }
        assertSameInstant(frameDuration(nil, 59.94), time(1, 30))
        assertSameInstant(frameDuration(nil, 60), time(1, 30))
        assertSameInstant(frameDuration(nil, 240), time(1, 30))
    }

    func testNominalFrameDurationIsReducedToLowestTerms() throws {
        let cases: [(Float, MediaTime)] = [
            (24, time(1, 24)), (25, time(1, 25)), (30, time(1, 30)), (29.97, time(1001, 30_000)), (23.976, time(1001, 24_000)),
            (48, time(1, 48)), (50, time(1, 50)), (60, time(1, 60)), (120, time(1, 120)), (59.94, time(1001, 60_000)),
        ]
        for (rate, expected) in cases {
            XCTAssertEqual(SDRWorkingMediaContract.nominalFrameDuration(rate), expected, "\(rate)")
        }
        // Beyond 240 000 fps the rounded tick count is 0: reduced to 0/1, then capped by the caller.
        XCTAssertEqual(SDRWorkingMediaContract.nominalFrameDuration(1_000_000), time(0, 1))
        for invalid: Float in [0, -24, .nan, .infinity, 1e-30] {
            XCTAssertNil(SDRWorkingMediaContract.nominalFrameDuration(invalid), "\(invalid)")
        }
    }

    func testMinimumFrameDurationIsReducedBeforeCappingAndStorage() {
        XCTAssertEqual(frameDuration(time(2, 48), 60), time(1, 24))
        XCTAssertEqual(frameDuration(time(4, 120), 60), time(1, 30))
        XCTAssertEqual(frameDuration(time(2002, 60_000), 60), time(1001, 30_000))
        XCTAssertEqual(frameDuration(time(2, 120), 24), time(1, 30))        // 1/60 capped to the canonical 1/30
        XCTAssertEqual(frameDuration(time(4, 96), 30), time(1, 24))
        XCTAssertEqual(frameDuration(time(1, 25), 30), time(1, 25))
        XCTAssertEqual(frameDuration(time(3000, 90_000), .nan), time(1, 30))
        // A non-positive minimum still falls through to the nominal path.
        XCTAssertEqual(frameDuration(time(0, 48), 24), time(1, 24))
        XCTAssertEqual(frameDuration(time(-2, 48), 24), time(1, 24))
    }

    func testMissingOrInvalidTimingFallsBackToThirtyFramesPerSecond() {
        for nominal: Float in [0, -30, .nan, .infinity, -.infinity, 1e-30] {
            XCTAssertEqual(frameDuration(nil, nominal), time(1, 30), "\(nominal)")
        }
        XCTAssertEqual(frameDuration(time(0, 600), 0), time(1, 30))   // a non-positive minimum is not valid
    }

    func testNominalConversionIsDeterministicAndNeverFasterThanThirty() {
        XCTAssertEqual(SDRWorkingMediaContract.nominalFrameDurationTimescale, 120_000)
        for rate: Float in [1, 12, 15, 23.976, 24, 25, 29.97, 30, 30.3, 48, 50, 59.94, 60, 90, 120, 240, 1000] {
            let first = frameDuration(nil, rate), second = frameDuration(nil, rate)
            XCTAssertEqual(first, second)
            XCTAssertFalse(first < contract.minimumFrameDuration, "\(rate) fps faster than 30")
        }
    }

    // MARK: - Shared raster policy (ADR-047 Decision 1, ADR-048 Decision 2)

    func testRequiredRasterExamples() throws {
        let cases: [(WorkingMediaRaster, WorkingMediaRaster, Int, Int)] = [
            (raster(720, 1280), raster(720, 1280), 1, 1),
            (raster(1080, 1440), raster(1080, 1440), 1, 1),
            (raster(1080, 1920), raster(1080, 1920), 1, 1),
            (raster(2160, 3840), raster(1080, 1920), 1, 2),
            (raster(1440, 2560), raster(1080, 1920), 3, 4),
            (raster(1620, 2160), raster(1080, 1440), 2, 3),
            (raster(1080, 1919), raster(1080, 1918), 1, 1),
        ]
        for (source, expected, numerator, denominator) in cases {
            let plan = try XCTUnwrap(WorkingMediaRasterPolicy.plan(forPresentation: source))
            XCTAssertEqual(plan.output, expected, "\(source)")
            XCTAssertEqual(plan.scale.numerator, numerator, "\(source)")
            XCTAssertEqual(plan.scale.denominator, denominator, "\(source)")
            XCTAssertEqual(plan.presentation, source)
            XCTAssertTrue(plan.isFeasible)
        }
    }

    func testFeasibilityExamples() throws {
        let infeasible: [(Int, Int, WorkingMediaRaster)] = [(1080, 1081, raster(1080, 1080)), (1081, 1082, raster(1080, 1080)), (2160, 2162, raster(1080, 1080))]
        for (w, h, aligned) in infeasible {
            let plan = try XCTUnwrap(rasterPlan(w, h))
            XCTAssertEqual(plan.output, aligned, "\(w)×\(h)")
            XCTAssertFalse(plan.isFeasible, "\(w)×\(h)")
        }
        let feasible: [(Int, Int, WorkingMediaRaster)] = [(1080, 1082, raster(1080, 1082)), (1079, 1080, raster(1078, 1080)), (2160, 2164, raster(1080, 1082)), (1440, 1444, raster(1080, 1082))]
        for (w, h, aligned) in feasible {
            let plan = try XCTUnwrap(rasterPlan(w, h))
            XCTAssertEqual(plan.output, aligned, "\(w)×\(h)")
            XCTAssertTrue(plan.isFeasible, "\(w)×\(h)")
        }
    }

    func testOddLowResolutionFloorsAtMostOnePixelPerEdgeAndNeverEnlarges() throws {
        let plan = try XCTUnwrap(rasterPlan(719, 1279))
        XCTAssertEqual(plan.scale, .unity)
        XCTAssertEqual(plan.scaled, raster(719, 1279))
        XCTAssertEqual(plan.output, raster(718, 1278))
        XCTAssertEqual(plan.alignmentLoss.width, 1)
        XCTAssertEqual(plan.alignmentLoss.height, 1)

        let oneEdge = try XCTUnwrap(rasterPlan(721, 1280))
        XCTAssertEqual(oneEdge.output, raster(720, 1280))
        XCTAssertEqual(oneEdge.alignmentLoss.width, 1)
        XCTAssertEqual(oneEdge.alignmentLoss.height, 0)
    }

    func testOversizedOddScaledDimensionIsFlooredThenAligned() throws {
        // min(1080/1081, 1920/1922) = 1920/1922 → 1079.875… × 1920 → floor 1079 → even 1078.
        let plan = try XCTUnwrap(rasterPlan(1081, 1922))
        XCTAssertEqual(plan.scale.numerator, 960)
        XCTAssertEqual(plan.scale.denominator, 961)
        XCTAssertEqual(plan.scaled, raster(1079, 1920))
        XCTAssertEqual(plan.output, raster(1078, 1920))
        XCTAssertEqual(plan.alignmentLoss.width, 1)
    }

    func testUnusualPortraitAspectRatios() {
        XCTAssertEqual(rasterPlan(1080, 3840)?.output, raster(540, 1920))   // very tall
        XCTAssertEqual(rasterPlan(600, 4000)?.output, raster(288, 1920))
        XCTAssertEqual(rasterPlan(3000, 4000)?.output, raster(1080, 1440))  // 3:4, width binds
        XCTAssertEqual(rasterPlan(1200, 1600)?.output, raster(1080, 1440))
        XCTAssertEqual(rasterPlan(100, 3000)?.output, raster(64, 1920))     // 64.0 exactly
    }

    func testRasterInvariantsAcrossDeterministicGrid() throws {
        var feasible = 0, infeasible = 0
        for width in stride(from: 2, through: 4_400, by: 37) {
            for extra in [1, 2, 3, 7, 160, 911, 2_048, 5_000] {
                let source = raster(width, width + extra)
                let plan = try XCTUnwrap(WorkingMediaRasterPolicy.plan(forPresentation: source))
                let exactScale = min(1.0, 1080.0 / Double(source.width), 1920.0 / Double(source.height))
                let out = plan.output
                XCTAssertTrue(out.width % 2 == 0 && out.height % 2 == 0, "\(source)")
                XCTAssertTrue(out.width <= source.width && out.height <= source.height, "\(source) enlarged")
                XCTAssertTrue(out.width <= 1080 && out.height <= 1920, "\(source) exceeds envelope")
                XCTAssertTrue((0...1).contains(plan.alignmentLoss.width) && (0...1).contains(plan.alignmentLoss.height), "\(source)")
                XCTAssertLessThanOrEqual(plan.scale.numerator, plan.scale.denominator, "\(source) upscaled")
                if plan.scale != .unity {
                    XCTAssertTrue(plan.scaled.width == 1080 || plan.scaled.height == 1920, "\(source) binding edge missed")
                } else {
                    XCTAssertEqual(plan.scaled, source)
                }
                XCTAssertEqual(WorkingMediaRasterPolicy.plan(forPresentation: source), plan, "non-deterministic \(source)")
                if plan.isFeasible {
                    feasible += 1
                    XCTAssertTrue(out.width > 0 && out.isPortrait, "\(source)")
                } else {
                    infeasible += 1
                    // Only a near-square or sliver collapses: exact scaled edges differ by < 2 px or width < 2 px.
                    let nearSquare = Double(source.height - source.width) * exactScale < 2
                    let sliver = Double(source.width) * exactScale < 2
                    XCTAssertTrue(nearSquare || sliver, "\(source)")
                }
            }
        }
        XCTAssertEqual(feasible + infeasible, 119 * 8)
        XCTAssertGreaterThan(feasible, 600)
        XCTAssertGreaterThan(infeasible, 0)
    }

    func testRasterArithmeticIsOverflowSafe() throws {
        // Products far beyond Int.max: height binds, width = floor((2^62 - 1) × 1920 / (2^63 - 1)) = 959.
        let plan = try XCTUnwrap(rasterPlan(Int.max / 2, Int.max))
        XCTAssertEqual(plan.scaled, raster(959, 1920))
        XCTAssertEqual(plan.output, raster(958, 1920))
        XCTAssertTrue(plan.isFeasible)
    }

    func testDegenerateRastersHaveNoFeasiblePlan() {
        XCTAssertNil(rasterPlan(0, 1920))
        XCTAssertNil(rasterPlan(-2, 100))
        XCTAssertNil(rasterPlan(1080, 0))
        XCTAssertEqual(rasterPlan(1920, 1080)?.isFeasible, false)
        XCTAssertEqual(rasterPlan(1080, 1080)?.isFeasible, false)
        XCTAssertEqual(rasterPlan(1, 3)?.isFeasible, false)      // 0×2 after alignment
        XCTAssertEqual(rasterPlan(2, 3)?.isFeasible, false)      // 2×2 after alignment
    }

    // MARK: - Plans from real Step 3 accepted items

    func testHDROnlyNormalization() async throws {
        let plan = try await plan(hdr())
        XCTAssertEqual(plan.reasons, [.hdr(signals: [.hlgTransfer, .rec2020Primaries, .rec2020Matrix, .bitDepthAbove8])])
        XCTAssertEqual(plan.raster.output, raster(1080, 1920))
        XCTAssertEqual(plan.raster.scale, .unity)
        assertSameInstant(plan.outputFrameDuration, time(1, 30))
        XCTAssertEqual(plan.contract, .canonical)
        XCTAssertEqual(plan.contract.outputTransform, .identity)
        XCTAssertEqual(plan.audio, .passthroughAAC)
    }

    func testFrameRateOnlyNormalization() async throws {
        let plan = try await plan(facts(fps: 60, minFrameDuration: time(1, 60)))
        XCTAssertEqual(plan.reasons, [.frameRate(nominal: 60)])
        assertSameInstant(plan.outputFrameDuration, time(1, 30))
        XCTAssertEqual(plan.raster.output, raster(1080, 1920))
    }

    func testRasterOnlyNormalization() async throws {
        let plan = try await plan(facts(natural: (2160, 3840)))
        XCTAssertEqual(plan.reasons, [.raster(presentationWidth: 2160, presentationHeight: 3840)])
        XCTAssertEqual(plan.raster.output, raster(1080, 1920))
    }

    func testCombinedReasonsKeepCanonicalOrder() async throws {
        let plan = try await plan(hdr((2160, 3840), fps: 60))
        XCTAssertEqual(plan.reasons, [
            .hdr(signals: [.hlgTransfer, .rec2020Primaries, .rec2020Matrix, .bitDepthAbove8]),
            .frameRate(nominal: 60),
            .raster(presentationWidth: 2160, presentationHeight: 3840),
        ])
        XCTAssertEqual(plan.raster.output, raster(1080, 1920))
    }

    func testAllFourReasonsKeepCanonicalOrder() async throws {
        var f = hdr((2160, 3840), fps: 60)
        f.audio = audio("lpcm", channels: 6)
        let plan = try await plan(f)
        XCTAssertEqual(plan.reasons, [
            .hdr(signals: [.hlgTransfer, .rec2020Primaries, .rec2020Matrix, .bitDepthAbove8]),
            .frameRate(nominal: 60),
            .raster(presentationWidth: 2160, presentationHeight: 3840),
            .audioTranscode,
        ])
        guard case .transcode(let settings) = plan.audio else { return XCTFail("expected transcode") }
        XCTAssertTrue(settings.downmixesToStereo)
    }

    func testLowResolutionHDRKeepsLowRaster() async throws {
        let plan = try await plan(hdr((720, 1280)))
        XCTAssertEqual(plan.raster.output, raster(720, 1280))
        XCTAssertEqual(plan.raster.scale, .unity)
    }

    func testLowResolutionHighFrameRateKeepsRasterAndCaps() async throws {
        let plan = try await plan(facts(natural: (720, 1280), fps: 60))
        XCTAssertEqual(plan.reasons, [.frameRate(nominal: 60)])
        XCTAssertEqual(plan.raster.output, raster(720, 1280))
        assertSameInstant(plan.outputFrameDuration, time(1, 30))
    }

    func testRotatedLandscapeNaturalSizePlansFromPresentation() async throws {
        let plan = try await plan(hdr((3840, 2160), transform: rotate90))
        XCTAssertEqual(plan.raster.presentation, raster(2160, 3840))
        XCTAssertEqual(plan.raster.output, raster(1080, 1920))
        XCTAssertEqual(plan.sourcePresentationTransform, rotate90)
        XCTAssertEqual(plan.contract.outputTransform, .identity)
    }

    func testMirroredPortraitDoesNotAlterRasterPolicy() async throws {
        let mirrored = try await plan(facts(natural: (2160, 3840), transform: mirrorX))
        let plain = try await plan(facts(natural: (2160, 3840)))
        XCTAssertEqual(mirrored.raster, plain.raster)
        XCTAssertEqual(mirrored.reasons, plain.reasons)
        XCTAssertEqual(mirrored.sourcePresentationTransform, mirrorX)
    }

    func testPlanRasterIsTheSharedPolicyResult() async throws {
        for natural in [(2160, 3840), (1620, 2160), (2160, 2164), (1440, 1444), (719, 1279)] {
            var f = hdr(natural)
            f.nominalFrameRate = 30
            let plan = try await plan(f)
            XCTAssertEqual(plan.raster, rasterPlan(natural.0, natural.1), "\(natural)")
        }
    }

    func testPlanCadenceFollowsTheFallbackWithoutAddingAReason() async throws {
        // Nominal 30 but a 1/60 s minimum frame duration: no frame-rate reason; the minimum still
        // governs cadence and is capped at 1/30.
        let noisy = try await plan(facts(natural: (720, 1280), minFrameDuration: time(1, 60), transfer: .pq))
        XCTAssertEqual(noisy.reasons, [.hdr(signals: [.pqTransfer])])
        assertSameInstant(noisy.outputFrameDuration, time(1, 30))

        let film = try await plan(facts(fps: 24, transfer: .pq))
        XCTAssertEqual(film.reasons, [.hdr(signals: [.pqTransfer])])
        assertSameInstant(film.outputFrameDuration, time(1, 24))

        let filmWithMinimum = try await plan(facts(fps: 24, minFrameDuration: time(1, 24), transfer: .pq))
        XCTAssertEqual(filmWithMinimum.outputFrameDuration, time(1, 24))

        let untimed = try await plan(facts(fps: 0, transfer: .pq))
        XCTAssertEqual(untimed.reasons, [.hdr(signals: [.pqTransfer])])
        XCTAssertEqual(untimed.outputFrameDuration, time(1, 30))
    }

    func testPlanCadenceIsRepresentationEqualAcrossSourcePaths() async throws {
        let nominal24 = try await plan(facts(fps: 24, transfer: .pq))
        XCTAssertEqual(nominal24.outputFrameDuration, try MediaTime(value: 1, timescale: 24))
        let nominal2997 = try await plan(facts(fps: 29.97, transfer: .pq))
        XCTAssertEqual(nominal2997.outputFrameDuration, try MediaTime(value: 1001, timescale: 30_000))
        let nominal23976 = try await plan(facts(fps: 23.976, transfer: .pq))
        XCTAssertEqual(nominal23976.outputFrameDuration, try MediaTime(value: 1001, timescale: 24_000))

        // Same cadence via nominal 24 fps (no minimum) and via a valid 1/24 minimum.
        let viaMinimum = try await plan(facts(fps: 24, minFrameDuration: time(1, 24), transfer: .pq))
        XCTAssertEqual(nominal24.outputFrameDuration, viaMinimum.outputFrameDuration)
        XCTAssertEqual(Set([nominal24.outputFrameDuration, viaMinimum.outputFrameDuration]).count, 1)
        XCTAssertEqual(nominal24.reasons, viaMinimum.reasons)

        // Unreduced minima reach the same canonical value as the nominal path.
        let viaUnreducedMinimum = try await plan(facts(fps: 24, minFrameDuration: time(2, 48), transfer: .pq))
        XCTAssertEqual(viaUnreducedMinimum.outputFrameDuration, try MediaTime(value: 1, timescale: 24))
        XCTAssertEqual(viaUnreducedMinimum.outputFrameDuration, nominal24.outputFrameDuration)
        XCTAssertEqual(Set([nominal24.outputFrameDuration, viaUnreducedMinimum.outputFrameDuration]).count, 1)
        let ntscViaMinimum = try await plan(facts(fps: 29.97, minFrameDuration: time(2002, 60_000), transfer: .pq))
        XCTAssertEqual(ntscViaMinimum.outputFrameDuration, nominal2997.outputFrameDuration)
        XCTAssertEqual(Set([nominal2997.outputFrameDuration, ntscViaMinimum.outputFrameDuration]).count, 1)
        XCTAssertEqual(ntscViaMinimum, nominal2997, "same facts except an equivalent minimum → identical plans")
        XCTAssertEqual(Set([ntscViaMinimum, nominal2997]).count, 1)

        // Precedence is unchanged: a valid minimum wins over nominal, faster minima cap, slower are kept.
        let minimumWins = try await plan(facts(fps: 24, minFrameDuration: time(1001, 30_000), transfer: .pq))
        XCTAssertEqual(minimumWins.outputFrameDuration, time(1001, 30_000))
        let fastMinimum = try await plan(facts(fps: 24, minFrameDuration: time(1, 60), transfer: .pq))
        XCTAssertEqual(fastMinimum.outputFrameDuration, time(1, 30))
        let invalidNominal = try await plan(facts(fps: .nan, transfer: .pq))
        XCTAssertEqual(invalidNominal.outputFrameDuration, time(1, 30))
        XCTAssertEqual(invalidNominal.reasons, [.hdr(signals: [.pqTransfer])])
    }

    func testSourceDurationIsCarriedExactly() async throws {
        let duration = time(1234, 600)
        let plan = try await plan(facts(duration: duration, fps: 60))
        XCTAssertEqual(plan.sourceDuration, duration)
        XCTAssertEqual(plan.sourceDuration.timescale, 600)
        XCTAssertEqual(plan.acceptedOutputDuration, contract.acceptedOutputDuration(forSource: duration))
        XCTAssertEqual(plan.acceptedOutputDuration.lowerBound, duration)
    }

    func testPlanningIsDeterministic() async throws {
        let item = try await acceptedItem(hdr((1620, 2160), fps: 60))
        let first = try WorkingMediaPlanBuilder.plan(for: item)
        let second = try WorkingMediaPlanBuilder.plan(for: item)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
        XCTAssertEqual(first.raster.output, raster(1080, 1440))
    }

    // MARK: - Source eligibility boundaries (ADR-042 + ADR-045 §1 / §11) vs output tolerance (ADR-045 §7)

    func testExactBoundariesAreEligibleWithoutTolerance() async throws {
        for duration in [time(1, 1), time(600, 600), time(5, 1), time(3000, 600)] {
            let plan = try await plan(facts(duration: duration, fps: 60))
            XCTAssertEqual(plan.sourceDuration, duration)
        }
        for duration in [time(599, 600), time(3001, 600), time(151, 30)] {
            let result = try await outcome(facts(duration: duration, fps: 60))
            XCTAssertTrue(result.accepted.isEmpty, "\(duration)")
        }
        // The +1/30 s window applies to normalization output only, never to the source.
        let atMaximum = try await plan(facts(duration: time(5, 1), fps: 60))
        XCTAssertTrue(atMaximum.acceptedOutputDuration.contains(time(151, 30)))
    }

    // MARK: - Audio (ADR-048 Decision 1)

    func testNoAudioPlansNoAudio() async throws {
        let silent = try await plan(facts(fps: 60, hasAudioTrack: false, audio: nil))
        XCTAssertEqual(silent.reasons, [.frameRate(nominal: 60)])
        XCTAssertEqual(silent.audio, .none)
        let ready = try await acceptedItem(facts(hasAudioTrack: false, audio: nil))
        XCTAssertEqual(ready.preparationPath, .fastPathCopy)
    }

    func testAACPassesThroughAndIsNotAReason() async throws {
        let aac = try await plan(facts(fps: 60))
        XCTAssertEqual(aac.reasons, [.frameRate(nominal: 60)])
        XCTAssertEqual(aac.audio, .passthroughAAC)
    }

    func testKnownNonAACFormatsTranscode() async throws {
        for id in ["lpcm", "alac", "apac", "aach", "aacp", "ac-3"] {
            let plan = try await plan(facts(audio: audio(id)))
            XCTAssertEqual(plan.reasons, [.audioTranscode], id)
            guard case .transcode(let settings) = plan.audio else { XCTFail("\(id) expected transcode"); continue }
            XCTAssertEqual(settings.codec, .aacLC, id)
            XCTAssertEqual(settings.sampleRate, 48_000, id)
        }
    }

    func testAudioOnlyPlanStillUsesTheCanonicalVideoContract() async throws {
        let plan = try await plan(facts(audio: audio("lpcm")))
        XCTAssertEqual(plan.reasons, [.audioTranscode])
        XCTAssertEqual(plan.contract, .canonical)
        XCTAssertEqual(plan.contract.videoCodec, .h264)
        XCTAssertEqual(plan.contract.container, .quickTime)
        XCTAssertEqual(plan.contract.outputTransform, .identity)
        XCTAssertEqual(plan.raster.output, raster(1080, 1920))
        assertSameInstant(plan.outputFrameDuration, time(1, 30))
    }

    func testTranscodeSettingsByChannelCount() throws {
        let mono = try XCTUnwrap(contract.audioTranscodeSettings(sourceChannelCount: 1))
        XCTAssertEqual(mono.codec, .aacLC); XCTAssertEqual(mono.sampleRate, 48_000)
        XCTAssertEqual(mono.channelLayout, .mono); XCTAssertEqual(mono.bitRate, 96_000); XCTAssertFalse(mono.downmixesToStereo)

        let stereo = try XCTUnwrap(contract.audioTranscodeSettings(sourceChannelCount: 2))
        XCTAssertEqual(stereo.codec, .aacLC); XCTAssertEqual(stereo.sampleRate, 48_000)
        XCTAssertEqual(stereo.channelLayout, .stereo); XCTAssertEqual(stereo.bitRate, 128_000); XCTAssertFalse(stereo.downmixesToStereo)

        for channels in [3, 6, 8] {
            let many = try XCTUnwrap(contract.audioTranscodeSettings(sourceChannelCount: channels))
            XCTAssertEqual(many.channelLayout, .stereo); XCTAssertEqual(many.bitRate, 128_000); XCTAssertTrue(many.downmixesToStereo)
            XCTAssertEqual(many.sampleRate, 48_000)
        }
        XCTAssertNil(contract.audioTranscodeSettings(sourceChannelCount: 0))
    }

    func testPlanTranscodeSettingsFollowTheSourceChannelCount() async throws {
        let mono = try await plan(facts(audio: audio("alac", channels: 1)))
        XCTAssertEqual(mono.audio, .transcode(try XCTUnwrap(contract.audioTranscodeSettings(sourceChannelCount: 1))))
        let surround = try await plan(facts(audio: audio("apac", channels: 4)))
        XCTAssertEqual(surround.audio, .transcode(try XCTUnwrap(contract.audioTranscodeSettings(sourceChannelCount: 4))))
    }

    // MARK: - Construction guards and preflight ownership

    func testFastPathItemIsRejected() async throws {
        let item = try await acceptedItem(facts())
        XCTAssertEqual(item.preparationPath, .fastPathCopy)
        assertPlanError(.fastPathItem) { try WorkingMediaPlanBuilder.plan(for: item) }
    }

    func testEmptyReasonsAreRejected() {
        assertPlanError(.emptyNormalizationReasons) {
            try WorkingMediaPlanBuilder.plan(preparationPath: .normalizationRequired(reasons: []), facts: self.hdr(), sourceDuration: self.time(1200, 600))
        }
    }

    func testReasonsThatDisagreeWithPreflightAreRejected() {
        let duration = time(1200, 600)
        // HDR facts presented as a frame-rate-only path.
        assertPlanError(.preflightMismatch) {
            try WorkingMediaPlanBuilder.plan(preparationPath: .normalizationRequired(reasons: [.frameRate(nominal: 60)]), facts: self.hdr(), sourceDuration: duration)
        }
        // Right reasons, out of canonical order.
        let combined = hdr((2160, 3840), fps: 60)
        assertPlanError(.preflightMismatch) {
            try WorkingMediaPlanBuilder.plan(preparationPath: .normalizationRequired(reasons: [
                .raster(presentationWidth: 2160, presentationHeight: 3840), .frameRate(nominal: 60),
                .hdr(signals: [.hlgTransfer, .rec2020Primaries, .rec2020Matrix, .bitDepthAbove8]),
            ]), facts: combined, sourceDuration: duration)
        }
        // Audio transcode claimed for an AAC source, and omitted for an LPCM source.
        assertPlanError(.preflightMismatch) {
            try WorkingMediaPlanBuilder.plan(preparationPath: .normalizationRequired(reasons: [.frameRate(nominal: 60), .audioTranscode]), facts: self.facts(fps: 60), sourceDuration: duration)
        }
        assertPlanError(.preflightMismatch) {
            try WorkingMediaPlanBuilder.plan(preparationPath: .normalizationRequired(reasons: [.frameRate(nominal: 60)]), facts: self.facts(fps: 60, audio: self.audio("lpcm")), sourceDuration: duration)
        }
        // Right reasons, wrong duration.
        assertPlanError(.preflightMismatch) {
            try WorkingMediaPlanBuilder.plan(preparationPath: .normalizationRequired(reasons: [.frameRate(nominal: 60)]), facts: self.facts(fps: 60), sourceDuration: self.time(1201, 600))
        }
        // Fast-path facts presented as normalization-required.
        assertPlanError(.preflightMismatch) {
            try WorkingMediaPlanBuilder.plan(preparationPath: .normalizationRequired(reasons: [.frameRate(nominal: 60)]), facts: self.facts(), sourceDuration: duration)
        }
    }

    func testRejectedFactsCannotBecomeAPlan() {
        let path = ImportPreparationPath.normalizationRequired(reasons: [.frameRate(nominal: 60)])
        let tooLong = facts(duration: time(6, 1), fps: 60)
        assertPlanError(.rejectedByPreflight(.durationAboveMaximum)) {
            try WorkingMediaPlanBuilder.plan(preparationPath: path, facts: tooLong, sourceDuration: self.time(6, 1))
        }
        assertPlanError(.rejectedByPreflight(.nonPortraitPresentation(.landscape))) {
            try WorkingMediaPlanBuilder.plan(preparationPath: path, facts: self.facts(natural: (1920, 1080), fps: 60), sourceDuration: self.time(1200, 600))
        }
        assertPlanError(.rejectedByPreflight(.nonPortraitPresentation(.square))) {
            try WorkingMediaPlanBuilder.plan(preparationPath: path, facts: self.facts(natural: (0, 0), fps: 60), sourceDuration: self.time(1200, 600))
        }
    }

    func testInfeasibleRasterIsExcludedByPreflightAndNeverReachesTheBuilder() async throws {
        let nearSquare = hdr((1080, 1081), fps: 60)
        let result = try await outcome(nearSquare)
        XCTAssertTrue(result.accepted.isEmpty)
        XCTAssertEqual(result.excluded.map(\.rejection), [.unsupportedWorkingRaster(presentationWidth: 1080, presentationHeight: 1081)])
        XCTAssertEqual(result.excluded.first?.category, .invalidOrUnsupportedMedia)
        // A forged path over the same facts is refused as a preflight rejection, not a late product decision.
        assertPlanError(.rejectedByPreflight(.unsupportedWorkingRaster(presentationWidth: 1080, presentationHeight: 1081))) {
            try WorkingMediaPlanBuilder.plan(preparationPath: .normalizationRequired(reasons: [.hdr(signals: [.hlgTransfer, .rec2020Primaries, .rec2020Matrix, .bitDepthAbove8]), .frameRate(nominal: 60)]),
                                             facts: nearSquare, sourceDuration: self.time(1200, 600))
        }
    }

    func testUnreliableAudioIsExcludedByPreflightAndNeverReachesTheBuilder() async throws {
        let cases: [(ImportSourceFacts, ImportAudioFactsProblem)] = [
            (facts(fps: 60, hasAudioTrack: true, audio: nil), .missingFormatFacts),
            (facts(fps: 60, hasAudioTrack: false, audio: aacStereo), .contradictoryTrackFacts),
            (facts(fps: 60, audio: ImportAudioFacts(fourCC: "aac ", sampleRate: 0, channelCount: 2)), .invalidSampleRate),
            (facts(fps: 60, audio: ImportAudioFacts(fourCC: "lpcm", sampleRate: 48_000, channelCount: 0)), .invalidChannelCount),
            (facts(fps: 60, audio: ImportAudioFacts(fourCC: "", sampleRate: 48_000, channelCount: 2)), .malformedFormatID),
        ]
        for (f, problem) in cases {
            let result = try await outcome(f)
            XCTAssertTrue(result.accepted.isEmpty, "\(problem)")
            XCTAssertEqual(result.excluded.map(\.rejection), [.unsupportedAudioFacts(problem)])
            assertPlanError(.rejectedByPreflight(.unsupportedAudioFacts(problem))) {
                try WorkingMediaPlanBuilder.plan(preparationPath: .normalizationRequired(reasons: [.frameRate(nominal: 60)]), facts: f, sourceDuration: self.time(1200, 600))
            }
        }
    }
}
