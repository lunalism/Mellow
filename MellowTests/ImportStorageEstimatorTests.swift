import AVFoundation
import XCTest
@testable import Mellow

/// ADR-050 050-A / 050-B / 050-C (calculation policy). Every expectation is a literal computed
/// from the documented formula with exact rational arithmetic, never derived from the estimator.
final class ImportStorageEstimatorTests: XCTestCase {
    private func time(_ value: Int64, _ timescale: Int32) throws -> MediaTime { try MediaTime(value: value, timescale: timescale) }

    private func output(_ value: Int64, _ timescale: Int32, _ audio: ImportOutputAudioEstimate = .none) throws -> ImportNormalizedOutputEstimate {
        try ImportStorageEstimator.normalizedOutput(sourceDuration: time(value, timescale), audio: audio)
    }

    private func assertThrows(_ expected: ImportStorageEstimateError, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? ImportStorageEstimateError, expected, file: file, line: line) }
    }

    // MARK: Policy constants (accepted values)

    func testAcceptedPolicyConstants() {
        XCTAssertEqual(ImportStoragePolicy.videoBytesPerSecond, 7_500_000)
        XCTAssertEqual(ImportStoragePolicy.videoMarginNumerator, 3)
        XCTAssertEqual(ImportStoragePolicy.videoMarginDenominator, 2)
        XCTAssertEqual(ImportStoragePolicy.outputFileAllowanceBytes, 2_097_152)
        XCTAssertEqual(ImportStoragePolicy.transcodeAudioBytesPerSecond, 32_000)
        XCTAssertEqual(ImportStoragePolicy.transcodeAudioPaddingSamples, 3_136)
        XCTAssertEqual(ImportStoragePolicy.transcodeAudioSampleRate, 48_000)
        XCTAssertEqual(ImportStoragePolicy.metadataBytesPerSave, 196_608)
        XCTAssertEqual(ImportStoragePolicy.metadataBytesPerRow, 512)
        XCTAssertEqual(ImportStoragePolicy.importSafetyReserveBytes, 268_435_456)
        XCTAssertNotEqual(ImportStoragePolicy.importSafetyReserveBytes, ProjectCompositionPolicy.materializationSafetyReserveBytes)
    }

    // MARK: 050-A documented examples

    func testIMG0130PassthroughExample() throws {
        let e = try output(2722, 600, .passthrough(sourcePayloadBytes: 0))
        XCTAssertEqual(e.videoBaseBytes, 34_275_000)
        XCTAssertEqual(e.videoMarginBytes, 17_137_500)
        XCTAssertEqual(e.videoBytes, 51_412_500)
        XCTAssertEqual(e.fileAllowanceBytes, 2_097_152)
        XCTAssertEqual(e.totalBytes, 53_509_652)
        XCTAssertEqual(try output(2722, 600, .passthrough(sourcePayloadBytes: 123_456)).totalBytes, 53_509_652 + 123_456)
    }

    func testFiveSecondSilentExampleIsTimescaleIndependent() throws {
        for (value, timescale) in [(Int64(5), Int32(1)), (3000, 600), (4_999_999_999, 1_000_000_000)] {
            let e = try output(value, timescale)
            XCTAssertEqual(e.videoBaseBytes, 37_750_000)
            XCTAssertEqual(e.videoMarginBytes, 18_875_000)
            XCTAssertEqual(e.audioBytes, 0)
            XCTAssertEqual(e.totalBytes, 58_722_152)
        }
    }

    func testOneSecondSilentExample() throws {
        XCTAssertEqual(try output(1, 1).totalBytes, 13_722_152)
    }

    func testTranscodeExample() throws {
        let e = try output(5, 1, .transcode)
        XCTAssertEqual(e.audioBytes, 163_158)
        XCTAssertEqual(e.totalBytes, 58_885_310)
    }

    // MARK: Unusual timescales and rounding

    func testUnusualTimescalesRoundUpExactly() throws {
        let a = try output(7, 3)
        XCTAssertEqual([a.videoBaseBytes, a.videoMarginBytes, a.totalBytes], [17_750_000, 8_875_000, 28_722_152])
        let b = try output(1, 7)
        XCTAssertEqual([b.videoBaseBytes, b.videoMarginBytes, b.totalBytes], [1_321_429, 660_714, 4_079_295])
        let c = try output(1, 7, .transcode)
        XCTAssertEqual([c.audioBytes, c.totalBytes], [7_729, 4_087_024])
        let d = try output(30030, 30000, .transcode)
        XCTAssertEqual([d.videoBaseBytes, d.videoMarginBytes, d.audioBytes, d.totalBytes], [7_757_500, 3_878_750, 35_190, 13_768_592])
        let e = try output(Int64(Int32.max), .max, .transcode)
        XCTAssertEqual([e.videoBaseBytes, e.audioBytes, e.totalBytes], [7_750_000, 35_158, 13_757_310])
    }

    func testLargeTimescalesDoNotFalselyOverflow() throws {
        // Nanosecond and Int32.max timescales must not fail closed through an unreduced intermediate.
        XCTAssertEqual(try output(5_000_000_000, 1_000_000_000, .transcode).audioBytes, 163_158)
        XCTAssertEqual(try output(4_999_999_999, 1_000_000_000, .transcode).audioBytes, 163_158)
        let longAtMaxTimescale = try output(10 * Int64(Int32.max), .max, .transcode)
        XCTAssertEqual([longAtMaxTimescale.videoBaseBytes, longAtMaxTimescale.videoBytes, longAtMaxTimescale.audioBytes], [75_250_000, 112_875_000, 323_158])
    }

    func testNoClipDurationCap() throws {
        // A source longer than 5 s still estimates (eligibility is not the estimator's job).
        XCTAssertEqual(try output(10, 1).totalBytes, 114_972_152)
    }

    // MARK: Audio variants and invalid inputs

    func testAudioVariants() throws {
        XCTAssertEqual(try output(5, 1, .none).audioBytes, 0)
        XCTAssertEqual(try output(5, 1, .passthrough(sourcePayloadBytes: 0)).audioBytes, 0)
        XCTAssertEqual(try output(5, 1, .passthrough(sourcePayloadBytes: 80_000)).audioBytes, 80_000)
        XCTAssertEqual(try output(5, 1, .transcode).audioBytes, 163_158)
    }

    func testInvalidInputsThrow() throws {
        assertThrows(.nonPositiveDuration) { _ = try self.output(0, 600) }
        assertThrows(.nonPositiveDuration) { _ = try self.output(-1, 600) }
        assertThrows(.negativeByteCount) { _ = try self.output(5, 1, .passthrough(sourcePayloadBytes: -1)) }
        assertThrows(.negativeRowCount) { _ = try ImportStorageEstimator.metadata(.createProject(newClips: -1)) }
        assertThrows(.negativeRowCount) { _ = try ImportStorageEstimator.metadata(.add(existingDurableClips: -5, newClips: 10)) }
        assertThrows(.negativeRowCount) { _ = try ImportStorageEstimator.metadata(.replacingSaved(newClips: 1, replacedDurableClips: -1)) }
        assertThrows(.negativeByteCount) { _ = try ImportStorageEstimator.requirement(outputBytes: -1, metadataBytes: 0) }
        assertThrows(.negativeByteCount) { _ = try ImportStorageEstimator.requirement(outputBytes: 0, metadataBytes: -1) }
    }

    func testOverflowThrows() throws {
        assertThrows(.arithmeticOverflow) { _ = try self.output(.max, 1) }
        assertThrows(.arithmeticOverflow) { _ = try self.output(.max / 30, 1) }
        assertThrows(.arithmeticOverflow) { _ = try self.output(5, 1, .passthrough(sourcePayloadBytes: .max)) }
        assertThrows(.arithmeticOverflow) { _ = try ImportStorageEstimator.metadata(.add(existingDurableClips: .max, newClips: 1)) }
        assertThrows(.arithmeticOverflow) { _ = try ImportStorageEstimator.metadata(.replace(existingDurableClips: .max)) }
        assertThrows(.arithmeticOverflow) { _ = try ImportStorageEstimator.requirement(outputBytes: .max, metadataBytes: 0) }
        // Each item fits (112,500,000,002,472,152 B) but 100 of them overflow the sum.
        let huge = ImportStorageItem.normalized(sourceDuration: try time(10_000_000_000, 1), audio: .none)
        XCTAssertEqual(try ImportStorageEstimator.remainingOutputBytes([huge]), 112_500_000_002_472_152)
        assertThrows(.arithmeticOverflow) { _ = try ImportStorageEstimator.remainingOutputBytes(Array(repeating: huge, count: 100)) }
    }

    // MARK: Item sets and remaining output

    func testReadyOnlyAddsZero() throws {
        XCTAssertEqual(try ImportStorageEstimator.remainingOutputBytes([]), 0)
        XCTAssertEqual(try ImportStorageEstimator.remainingOutputBytes([.ready, .ready, .ready]), 0)
    }

    func testMixedSet() throws {
        let img = ImportStorageItem.normalized(sourceDuration: try time(2722, 600), audio: .passthrough(sourcePayloadBytes: 100_000))
        XCTAssertEqual(try ImportStorageEstimator.remainingOutputBytes([.ready, img]), 53_609_652)
    }

    func testOutputsAlreadyWrittenAreNotCountedAgain() throws {
        let five = ImportStorageItem.normalized(sourceDuration: .seconds(5), audio: .none)
        let all = Array(repeating: five, count: 10)
        XCTAssertEqual(try ImportStorageEstimator.remainingOutputBytes(all), 587_221_520)
        let afterFirst = [ImportStorageItem.normalizedOutputWritten] + Array(repeating: five, count: 9)
        XCTAssertEqual(try ImportStorageEstimator.remainingOutputBytes(afterFirst), 528_499_368)
        XCTAssertEqual(try ImportStorageEstimator.remainingOutputBytes(Array(repeating: .normalizedOutputWritten, count: 10)), 0)
    }

    func testMoreThanOneHundredItemsHaveNoCap() throws {
        let five = ImportStorageItem.normalized(sourceDuration: .seconds(5), audio: .none)
        XCTAssertEqual(try ImportStorageEstimator.remainingOutputBytes(Array(repeating: five, count: 150)), 8_808_322_800)
        XCTAssertEqual(try ImportStorageEstimator.metadata(.add(existingDurableClips: 1_000, newClips: 150)).bytes, 196_608 + 512 * 1_150)
    }

    // MARK: 050-B metadata

    func testMetadataPerOperation() throws {
        let create = try ImportStorageEstimator.metadata(.createProject(newClips: 2))
        XCTAssertEqual([create.saveCount, create.rowCount], [1, 2])
        XCTAssertEqual(create.bytes, 197_632)
        XCTAssertEqual(try ImportStorageEstimator.metadata(.createProject(newClips: 10)).bytes, 201_728)
        let replacing = try ImportStorageEstimator.metadata(.replacingSaved(newClips: 10, replacedDurableClips: 200))
        XCTAssertEqual([replacing.saveCount, replacing.rowCount], [2, 210])
        XCTAssertEqual(replacing.bytes, 500_736)
        let add = try ImportStorageEstimator.metadata(.add(existingDurableClips: 40, newClips: 3))
        XCTAssertEqual([add.saveCount, add.rowCount], [1, 43])
        XCTAssertEqual(add.bytes, 218_624)
        let replace = try ImportStorageEstimator.metadata(.replace(existingDurableClips: 40))
        XCTAssertEqual([replace.saveCount, replace.rowCount], [1, 41])
        XCTAssertEqual(replace.bytes, 217_600)
        XCTAssertEqual(try ImportStorageEstimator.metadata(.add(existingDurableClips: 0, newClips: 0)).bytes, 196_608)
    }

    // MARK: Requirement — documented 050-C examples

    func testRequirementExamples() throws {
        let img = ImportStorageItem.normalized(sourceDuration: try time(2722, 600), audio: .passthrough(sourcePayloadBytes: 0))
        let mixed = try ImportStorageEstimator.requirement(remaining: [.ready, img], metadata: .createProject(newClips: 2))
        XCTAssertEqual([mixed.outputBytes, mixed.metadataBytes, mixed.reserveBytes], [53_509_652, 197_632, 268_435_456])
        XCTAssertEqual(mixed.additionalBytes, 53_707_284)
        XCTAssertEqual(mixed.requiredBytes, 322_142_740)

        let five = ImportStorageItem.normalized(sourceDuration: .seconds(5), audio: .none)
        let ten = Array(repeating: five, count: 10)
        XCTAssertEqual(try ImportStorageEstimator.requirement(remaining: ten, metadata: .createProject(newClips: 10)).requiredBytes, 855_858_704)
        XCTAssertEqual(try ImportStorageEstimator.requirement(remaining: [.normalizedOutputWritten] + Array(ten.dropFirst()), metadata: .createProject(newClips: 10)).requiredBytes, 797_136_552)
        XCTAssertEqual(try ImportStorageEstimator.requirement(remaining: ten, metadata: .replacingSaved(newClips: 10, replacedDurableClips: 200)).requiredBytes, 856_157_712)
        XCTAssertEqual(try ImportStorageEstimator.requirement(remaining: Array(repeating: five, count: 3), metadata: .add(existingDurableClips: 40, newClips: 3)).requiredBytes, 444_820_536)
        // C3-style: no outputs left, metadata + reserve only.
        XCTAssertEqual(try ImportStorageEstimator.requirement(remaining: Array(repeating: .normalizedOutputWritten, count: 3), metadata: .add(existingDurableClips: 40, newClips: 3)).requiredBytes, 268_654_080)
        // Transfer-style: caller-supplied bytes for one volume, no metadata.
        XCTAssertEqual(try ImportStorageEstimator.requirement(outputBytes: 149_619_684, metadataBytes: 0).requiredBytes, 418_055_140)
        // Reserve-only requirement is never 0.
        XCTAssertEqual(try ImportStorageEstimator.requirement(remaining: [.ready], metadata: nil).requiredBytes, 268_435_456)
    }

    // MARK: Capacity check

    func testEqualityPassesAndOneByteShortFails() throws {
        let r = try ImportStorageEstimator.requirement(outputBytes: 1_000, metadataBytes: 24)
        XCTAssertEqual(r.requiredBytes, 268_436_480)
        XCTAssertEqual(ImportStorageEstimator.check(r, usableCapacityBytes: 268_436_480), .sufficient(requiredBytes: 268_436_480, usableBytes: 268_436_480))
        XCTAssertEqual(ImportStorageEstimator.check(r, usableCapacityBytes: 268_436_479), .insufficient(requiredBytes: 268_436_480, usableBytes: 268_436_479))
        XCTAssertTrue(ImportStorageEstimator.check(r, usableCapacityBytes: .max).passes)
    }

    func testUnknownOrNegativeCapacityNeverPasses() throws {
        let r = try ImportStorageEstimator.requirement(outputBytes: 0, metadataBytes: 0)
        XCTAssertEqual(ImportStorageEstimator.check(r, usableCapacityBytes: nil), .capacityUnknown(requiredBytes: 268_435_456))
        XCTAssertEqual(ImportStorageEstimator.check(r, usableCapacityBytes: -1), .capacityUnknown(requiredBytes: 268_435_456))
        XCTAssertFalse(ImportStorageEstimator.check(r, usableCapacityBytes: nil).passes)
        XCTAssertFalse(ImportStorageEstimator.check(r, usableCapacityBytes: 0).passes)
    }

    func testInjectedProviderCheck() async throws {
        let five = ImportStorageItem.normalized(sourceDuration: .seconds(5), audio: .none)
        let pass = await ImportStorageEstimator.check(requirement: { () throws(ImportStorageEstimateError) -> ImportStorageRequirement in try ImportStorageEstimator.requirement(remaining: [five], metadata: .createProject(newClips: 1)) }, capacity: { 327_354_728 })
        XCTAssertEqual(pass, .sufficient(requiredBytes: 327_354_728, usableBytes: 327_354_728))
        let unknown = await ImportStorageEstimator.check(requirement: { () throws(ImportStorageEstimateError) -> ImportStorageRequirement in try ImportStorageEstimator.requirement(remaining: [five], metadata: nil) }, capacity: { nil })
        XCTAssertFalse(unknown.passes)

        var capacityRead = false
        let invalid = await ImportStorageEstimator.check(
            requirement: { () throws(ImportStorageEstimateError) -> ImportStorageRequirement in try ImportStorageEstimator.requirement(remaining: [.normalized(sourceDuration: .zero, audio: .none)], metadata: nil) },
            capacity: { capacityRead = true; return .max }
        )
        XCTAssertEqual(invalid, .invalidEstimate(.nonPositiveDuration))
        XCTAssertFalse(invalid.passes)
        XCTAssertFalse(capacityRead)
        let overflow = await ImportStorageEstimator.check(requirement: { () throws(ImportStorageEstimateError) -> ImportStorageRequirement in try ImportStorageEstimator.requirement(outputBytes: .max, metadataBytes: 0) }, capacity: { .max })
        XCTAssertEqual(overflow, .invalidEstimate(.arithmeticOverflow))
    }

    func testCheckReturnsTheEstimateErrorItReceives() async {
        // The requirement closure is `throws(ImportStorageEstimateError)`: only estimate errors can reach
        // `check`, and each is reported as itself — never relabelled as overflow.
        for expected in [ImportStorageEstimateError.nonPositiveDuration, .negativeByteCount, .negativeRowCount, .arithmeticOverflow, .invalidRational] {
            let result = await ImportStorageEstimator.check(requirement: { () throws(ImportStorageEstimateError) -> ImportStorageRequirement in throw expected }, capacity: { .max })
            XCTAssertEqual(result, .invalidEstimate(expected))
        }
        let negativeRows = await ImportStorageEstimator.check(requirement: { () throws(ImportStorageEstimateError) -> ImportStorageRequirement in try ImportStorageEstimator.requirement(remaining: [], metadata: .replace(existingDurableClips: -1)) }, capacity: { .max })
        XCTAssertEqual(negativeRows, .invalidEstimate(.negativeRowCount))
    }

    // MARK: Internal exact rational

    func testRationalReducesAndRoundsUp() throws {
        let r = try ImportStorageRatio(6, 4)
        XCTAssertEqual([r.numerator, r.denominator, r.ceiling], [3, 2, 2])
        XCTAssertEqual(try ImportStorageRatio(0, 7).ceiling, 0)
        let sum = try ImportStorageRatio(1, 6).adding(try ImportStorageRatio(1, 10))
        XCTAssertEqual([sum.numerator, sum.denominator], [4, 15])
        let scaled = try ImportStorageRatio(31, 30).scaled(by: 7_500_000, over: 2)
        XCTAssertEqual([scaled.numerator, scaled.denominator], [3_875_000, 1])
    }

    func testRationalRejectsInvalidValuesWithNeutralError() {
        assertThrows(.invalidRational) { _ = try ImportStorageRatio(-1, 1) }
        assertThrows(.invalidRational) { _ = try ImportStorageRatio(1, 0) }
        assertThrows(.invalidRational) { _ = try ImportStorageRatio(1, -3) }
        assertThrows(.invalidRational) { _ = try ImportStorageRatio(1, 2).scaled(by: -1) }
        assertThrows(.invalidRational) { _ = try ImportStorageRatio(1, 2).scaled(by: 1, over: 0) }
        assertThrows(.invalidRational) { _ = try ImportStorageRatio(1, 5).scaled(by: .min) }
        assertThrows(.invalidRational) { _ = try ImportStorageRatio(1, 5).scaled(by: 1, over: .min) }
        // A genuinely non-positive source duration keeps its own, more specific error.
        assertThrows(.nonPositiveDuration) { _ = try self.output(0, 1) }
    }

    // MARK: Out-of-space classification

    func testOutOfSpacePositives() {
        let positives: [Error] = [
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError),
            CocoaError(.fileWriteOutOfSpace),
            NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)),
            POSIXError(.ENOSPC),
            NSError(domain: AVFoundationErrorDomain, code: AVError.Code.diskFull.rawValue),
            AVError(.diskFull),
            NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue,
                    userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))]),
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                    userInfo: [NSUnderlyingErrorKey: NSError(domain: "Outer", code: 1, userInfo: [NSUnderlyingErrorKey: AVError(.diskFull) as NSError])]),
            NSError(domain: "Wrapper", code: 7, userInfo: [NSMultipleUnderlyingErrorsKey: [NSError(domain: "A", code: 1), CocoaError(.fileWriteOutOfSpace) as NSError]]),
        ]
        for error in positives { XCTAssertEqual(ImportWriteFailureClassifier.classify(error), .outOfSpace, "\(error)") }
    }

    func testOutOfSpaceNegatives() {
        var deep: NSError = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        for level in 0..<12 { deep = NSError(domain: "Level", code: level, userInfo: [NSUnderlyingErrorKey: deep]) }
        let negatives: [Error] = [
            CocoaError(.fileWriteVolumeReadOnly),
            CocoaError(.fileWriteNoPermission),
            NSError(domain: NSPOSIXErrorDomain, code: Int(EDQUOT)),
            NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)),
            NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue),
            NSError(domain: NSOSStatusErrorDomain, code: Int(ENOSPC)),
            NSError(domain: "Other", code: NSFileWriteOutOfSpaceError),
            CancellationError(),
            deep,
        ]
        for error in negatives { XCTAssertEqual(ImportWriteFailureClassifier.classify(error), .other, "\(error)") }
    }

    // MARK: Accepted-set composition (unwired inputs for the accepted calculation)

    /// Serves scripted facts by URL so the real preflight builds the accepted items.
    private actor ScriptedInspector: ImportSourceInspecting {
        private var facts: [URL: ImportSourceFacts] = [:]
        func set(_ value: ImportSourceFacts, for url: URL) { facts[url] = value }
        func inspect(url: URL) async throws -> ImportSourceFacts {
            guard let value = facts[url] else { throw ImportInspectionError.sourceMissing }
            return value
        }
    }

    private enum SourceAudio { case none, aac(ImportAudioPayloadMeasurement), lpcm }

    /// A 2.0 s portrait H.264 source; 60 fps makes it normalization-required, 30 fps fast-path ready.
    private func sourceFacts(fps: Float, audio: SourceAudio) throws -> ImportSourceFacts {
        var facts = ImportSourceFacts(
            duration: .exact(try time(1200, 600)), isReadable: true, isPlayable: true, isExportable: true, hasProtectedContent: false,
            hasVideoTrack: true, hasAudioTrack: false, container: .quickTime, videoCodec: .h264(fourCC: "avc1"),
            naturalWidth: 1080, naturalHeight: 1920, preferredTransform: .identity,
            nominalFrameRate: fps, minimumFrameDuration: nil, bitsPerComponent: 8, highBitDepthProfile: .no,
            fullRangeVideo: .no, colorPrimaries: .rec709, transferFunction: .rec709, ycbcrMatrix: .rec709,
            hasDolbyVisionConfiguration: false, ancillaryHDRMetadata: [],
            aperture: .classify(encodedWidth: 1080, encodedHeight: 1920, cleanAperture: nil, pixelAspectRatio: nil),
            audio: nil, byteCount: 4_000_000, modificationDate: nil)
        switch audio {
        case .none:
            facts.audioPayload = .noAudioTrack
        case .aac(let payload):
            facts.hasAudioTrack = true
            facts.audio = ImportAudioFacts(fourCC: "aac ", sampleRate: 48_000, channelCount: 2)
            facts.audioPayload = payload
        case .lpcm:
            facts.hasAudioTrack = true
            facts.audio = ImportAudioFacts(fourCC: "lpcm", sampleRate: 48_000, channelCount: 2)
        }
        return facts
    }

    private func accepted(_ list: [ImportSourceFacts]) async throws -> [ImportAcceptedItem] {
        let inspector = ScriptedInspector()
        var candidates: [ImportCandidate] = []
        for (index, facts) in list.enumerated() {
            let url = URL(fileURLWithPath: "/workspace/storage-\(index).mov")
            await inspector.set(facts, for: url)
            candidates.append(ImportCandidate(url: url))
        }
        let outcome = try await ImportSelectionPreflight(inspector: inspector).run(candidates, context: .multipleItems)
        XCTAssertTrue(outcome.excluded.isEmpty, "\(outcome.excluded)")
        return outcome.accepted
    }

    private func plans(_ items: [ImportAcceptedItem]) throws -> [ImportCandidateID: WorkingMediaNormalizationPlan] {
        var plans: [ImportCandidateID: WorkingMediaNormalizationPlan] = [:]
        for item in items where item.preparationPath.normalization != nil { plans[item.candidate.id] = try WorkingMediaPlanBuilder.plan(for: item) }
        return plans
    }

    private func project(active: Int, pendingDeleted: Int) throws -> VlogProject {
        let id = UUID()
        let clips = try (0..<(active + pendingDeleted)).map { index in
            try VlogClip(projectID: id, sourceKind: .imported, mediaRelativePath: try RelativeMediaPath("Projects/\(id.uuidString)/Media/\(UUID().uuidString).mov"),
                         sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: index)
        }
        var project = try VlogProject(id: id, orientation: .portrait9x16, clips: clips)
        for _ in 0..<pendingDeleted { try project.deleteClip(id: project.clips[project.clips.count - 1].id) }
        XCTAssertEqual(project.durableClips.count, active + pendingDeleted)
        return project
    }

    private func assertCompositionThrows(_ expected: ImportStorageCompositionError, file: StaticString = #filePath, line: UInt = #line,
                                         _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? ImportStorageCompositionError, expected, file: file, line: line) }
    }

    /// 2.0 s normalized output: V = ceil(7,500,000 × (2 + 1/30) × 3/2) = 22,875,000; C_out = 2,097,152.
    /// No audio 24,972,152; passthrough S_audio 50,000 → 25,022,152; transcode ceil((61/30 + 3136/48000) × 32,000)
    /// = 67,158 → 25,039,310.
    func testMixedAcceptedSetComposesExactRemainingOutputsAndMetadata() async throws {
        let measured = ImportAudioPayloadMeasurement.combining(trackID: 2, stored: .bytes(50_000), delivered: .bytes(49_000))
        let items = try await accepted([
            try sourceFacts(fps: 30, audio: .aac(.unavailable(.notMeasured))),   // ready: no measurement needed
            try sourceFacts(fps: 60, audio: .aac(measured)),                      // passthrough, S_audio = max = 50,000
            try sourceFacts(fps: 60, audio: .none),
            try sourceFacts(fps: 60, audio: .lpcm),                               // the PLAN transcodes
        ])
        XCTAssertEqual(items.map { $0.preparationPath.normalization == nil }, [true, false, false, false])
        var set = try ImportStorageWorkSet(accepted: items, plans: try plans(items), operation: .createProject)
        XCTAssertEqual(set.items, [.ready, .normalized(sourceDuration: try time(1200, 600), audio: .passthrough(sourcePayloadBytes: 50_000)),
                                   .normalized(sourceDuration: try time(1200, 600), audio: .none),
                                   .normalized(sourceDuration: try time(1200, 600), audio: .transcode)])
        XCTAssertEqual(set.metadataOperation, .createProject(newClips: 4))

        // C1-shaped: every normalization output still to write + W(4 rows) — reserve kept separate.
        var requirement = try set.requirement()
        XCTAssertEqual(requirement.outputBytes, 25_022_152 + 24_972_152 + 25_039_310)        // 75,033,614
        XCTAssertEqual(requirement.metadataBytes, 198_656)
        XCTAssertEqual(requirement.reserveBytes, 268_435_456)
        XCTAssertEqual(requirement.requiredBytes, 343_667_726)

        // As work finishes, written outputs leave the remaining sum exactly once; metadata stays.
        try set.markOutputWritten(items[1].candidate.id)
        requirement = try set.requirement()
        XCTAssertEqual(requirement.outputBytes, 24_972_152 + 25_039_310)
        XCTAssertEqual(set.pendingNormalizationIDs, [items[2].candidate.id, items[3].candidate.id])
        try set.markOutputWritten(items[2].candidate.id)
        try set.markOutputWritten(items[3].candidate.id)
        requirement = try set.requirement()
        XCTAssertEqual(requirement.outputBytes, 0, "C3-shaped: nothing left but metadata")
        XCTAssertEqual(requirement.metadataBytes, 198_656)
        XCTAssertEqual(requirement.requiredBytes, 198_656 + 268_435_456)

        assertCompositionThrows(.outputAlreadyWritten(items[1].candidate.id)) { try set.markOutputWritten(items[1].candidate.id) }
        assertCompositionThrows(.notANormalizationItem(items[0].candidate.id)) { try set.markOutputWritten(items[0].candidate.id) }
        let unknown = ImportCandidateID()
        assertCompositionThrows(.unknownItem(unknown)) { try set.markOutputWritten(unknown) }
    }

    func testUnavailablePassthroughFailsClosedButReadyItemsNeverNeedIt() async throws {
        let items = try await accepted([try sourceFacts(fps: 30, audio: .aac(.unavailable(.readingFailed))),
                                        try sourceFacts(fps: 60, audio: .aac(.unavailable(.notMeasured)))])
        assertCompositionThrows(.estimate(.sourceAudioPayloadUnavailable)) {
            _ = try ImportStorageWorkSet(accepted: items, plans: try self.plans(items), operation: .createProject)
        }
        let readyOnly = try ImportStorageWorkSet(accepted: [items[0]], plans: [:], operation: .createProject)
        XCTAssertEqual(try readyOnly.requirement().outputBytes, 0, "a ready item adds nothing and needs no measurement")
    }

    func testEveryNormalizationItemNeedsItsOwnActualPlan() async throws {
        let items = try await accepted([try sourceFacts(fps: 30, audio: .none), try sourceFacts(fps: 60, audio: .none), try sourceFacts(fps: 60, audio: .lpcm)])
        let all = try plans(items)
        var missing = all; missing[items[1].candidate.id] = nil
        assertCompositionThrows(.missingPlan(items[1].candidate.id)) { _ = try ImportStorageWorkSet(accepted: items, plans: missing, operation: .createProject) }
        var forReady = all; forReady[items[0].candidate.id] = all[items[1].candidate.id]
        assertCompositionThrows(.unexpectedPlan(items[0].candidate.id)) { _ = try ImportStorageWorkSet(accepted: items, plans: forReady, operation: .createProject) }
        var swapped = all; swapped[items[1].candidate.id] = all[items[2].candidate.id]
        assertCompositionThrows(.planDoesNotMatchItem(items[1].candidate.id)) { _ = try ImportStorageWorkSet(accepted: items, plans: swapped, operation: .createProject) }
        let stray = ImportCandidateID()
        var extra = all; extra[stray] = all[items[1].candidate.id]
        assertCompositionThrows(.unexpectedPlan(stray)) { _ = try ImportStorageWorkSet(accepted: items, plans: extra, operation: .createProject) }
        assertCompositionThrows(.duplicateItem(items[1].candidate.id)) {
            _ = try ImportStorageWorkSet(accepted: items + [items[1]], plans: all, operation: .createProject)
        }
        assertCompositionThrows(.emptyAcceptedSet) { _ = try ImportStorageWorkSet(accepted: [], plans: [:], operation: .createProject) }
    }

    /// Durable rows include pending-deleted Clips (050-B). Target: 3 active + 2 pending-deleted = 5 rows.
    func testMetadataForEachOperationUsesDurableRowCounts() async throws {
        let target = try project(active: 3, pendingDeleted: 2)
        let items = try await accepted((0..<4).map { _ in try sourceFacts(fps: 30, audio: .none) })
        let plans = try plans(items)
        func metadata(_ accepted: [ImportAcceptedItem], _ operation: ImportStorageOperation) throws -> Int64 {
            try ImportStorageWorkSet(accepted: accepted, plans: plans.filter { id, _ in accepted.contains { $0.candidate.id == id } }, operation: operation).requirement().metadataBytes
        }
        XCTAssertEqual(try metadata(items, .createProject), 196_608 + 512 * 4)
        // Conservative two-save replacement charge: create(B, 4 rows) + delete(A, 5 durable rows).
        XCTAssertEqual(try ImportStorageWorkSet(accepted: items, plans: plans, operation: .replacingSaved(previous: target)).metadataOperation,
                       .replacingSaved(newClips: 4, replacedDurableClips: 5))
        XCTAssertEqual(try metadata(items, .replacingSaved(previous: target)), (196_608 + 512 * 4) + (196_608 + 512 * 5))
        XCTAssertEqual(try metadata(items, .add(to: target)), 196_608 + 512 * (5 + 4))
        XCTAssertEqual(try metadata([items[0]], .replaceClip(in: target)), 196_608 + 512 * (5 + 1))
        assertCompositionThrows(.invalidAcceptedCount(expected: 1, actual: 2)) {
            _ = try ImportStorageWorkSet(accepted: Array(items.prefix(2)), plans: plans, operation: .replaceClip(in: target))
        }
    }

    func testCompositionHasNoClipCap() async throws {
        let items = try await accepted((0..<150).map { _ in try sourceFacts(fps: 60, audio: .none) })
        let set = try ImportStorageWorkSet(accepted: items, plans: try plans(items), operation: .createProject)
        let requirement = try set.requirement()
        XCTAssertEqual(requirement.outputBytes, 150 * 24_972_152)
        XCTAssertEqual(requirement.metadataBytes, 196_608 + 512 * 150)
    }
}
