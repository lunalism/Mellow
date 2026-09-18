import AVFoundation
import CoreMedia
import CryptoKit
import XCTest
@testable import Mellow

/// Step 3 tests: the selection preflight over an injected fake inspector (pure facts matrices,
/// ordering, notice derivation, failure / cancellation) plus a few real-adapter cases against
/// generated fixtures. Nothing here touches Photos, user media or a project store.
final class ImportSelectionPreflightTests: XCTestCase {
    // MARK: - Fake inspector

    /// Scripted facts per URL; records every request in call order; can throw a chosen error and
    /// can pause deterministically before answering the Nth request (for cancellation tests).
    actor FakeImportSourceInspector: ImportSourceInspecting {
        enum Script { case facts(ImportSourceFacts), inspectionError(ImportInspectionError), otherError(NSError) }
        private var scripts: [URL: Script] = [:]
        private(set) var requested: [URL] = []
        private var pauseBefore: Int?
        private var arrived = false
        private var released = false
        private var arrival: CheckedContinuation<Void, Never>?
        private var release: CheckedContinuation<Void, Never>?

        func set(_ script: Script, for url: URL) { scripts[url] = script }
        func pause(beforeRequest index: Int) { pauseBefore = index }

        func inspect(url: URL) async throws -> ImportSourceFacts {
            let index = requested.count
            requested.append(url)
            if index == pauseBefore {
                arrived = true
                arrival?.resume(); arrival = nil
                if !released { await withCheckedContinuation { release = $0 } }
            }
            switch scripts[url] {
            case .facts(let facts): return facts
            case .inspectionError(let error): throw error
            case .otherError(let error): throw error
            case nil: XCTFail("unscripted url \(url.lastPathComponent)"); throw ImportInspectionError.sourceMissing
            }
        }

        /// Suspends until the paused request has been reached (returns at once if it already was).
        func waitUntilPaused() async {
            if arrived { return }
            await withCheckedContinuation { arrival = $0 }
        }

        func resumePaused() {
            released = true
            release?.resume(); release = nil
        }
    }

    private var fake: FakeImportSourceInspector!
    private var preflight: ImportSelectionPreflight!

    override func setUp() {
        fake = FakeImportSourceInspector()
        preflight = ImportSelectionPreflight(inspector: fake)
    }

    // MARK: - Facts builders (same shape as the Step 1 tests)

    private func time(_ value: Int64, _ timescale: Int32) -> MediaTime { try! MediaTime(value: value, timescale: timescale) }
    private let rotate90 = ImportAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
    private let mirrorX = ImportAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1080, ty: 0)

    private func facts(
        duration: ImportSourceDuration = .exact(try! MediaTime(value: 1200, timescale: 600)),
        readable: Bool = true, video: Bool = true, protected: Bool = false,
        container: ImportContainer = .quickTime,
        codec: ImportVideoCodec = .h264(fourCC: "avc1"),
        natural: (Int, Int) = (1080, 1920), transform: ImportAffineTransform = .identity,
        fps: Float = 30, transfer: ImportTransferFunction = .rec709,
        byteCount: Int64 = 4_000_000
    ) -> ImportSourceFacts {
        ImportSourceFacts(
            duration: duration, isReadable: readable, isPlayable: readable, isExportable: readable, hasProtectedContent: protected,
            hasVideoTrack: video, hasAudioTrack: true, container: container, videoCodec: codec,
            naturalWidth: natural.0, naturalHeight: natural.1, preferredTransform: transform,
            nominalFrameRate: fps, minimumFrameDuration: nil, bitsPerComponent: 8, highBitDepthProfile: .no,
            fullRangeVideo: .no, colorPrimaries: .rec709, transferFunction: transfer, ycbcrMatrix: .rec709,
            hasDolbyVisionConfiguration: false, ancillaryHDRMetadata: [],
            audio: ImportAudioFacts(fourCC: "aac ", sampleRate: 48_000, channelCount: 2),
            byteCount: byteCount, modificationDate: Date(timeIntervalSince1970: 1_000))
    }

    // Named facts used across the matrices.
    private var ready: ImportSourceFacts { facts() }
    private var hdr: ImportSourceFacts { facts(transfer: .hlg) }
    private var sixtyFPS: ImportSourceFacts { facts(fps: 60) }
    private var fourK: ImportSourceFacts { facts(natural: (2160, 3840)) }
    private var short: ImportSourceFacts { facts(duration: .exact(time(240, 600))) }          // 0.4 s
    private var long: ImportSourceFacts { facts(duration: .exact(time(3001, 600))) }          // 5.0 s + 1 tick
    private var invalidDuration: ImportSourceFacts { facts(duration: .invalid) }
    private var unreadable: ImportSourceFacts { facts(duration: .invalid, readable: false, video: false) }
    private var noVideo: ImportSourceFacts { facts(video: false) }
    private var protected: ImportSourceFacts { facts(protected: true) }
    private var mp4: ImportSourceFacts { facts(container: .isoBaseMedia(brands: ["mp42", "isom"])) }
    private var unknownContainer: ImportSourceFacts { facts(container: .unknown) }
    private var prores: ImportSourceFacts { facts(codec: .unsupported(fourCC: "apch")) }
    private var unknownCodec: ImportSourceFacts { facts(codec: .unknown) }
    private var landscape: ImportSourceFacts { facts(natural: (1920, 1080)) }
    private var square: ImportSourceFacts { facts(natural: (1080, 1080)) }
    private var rotatedPortrait: ImportSourceFacts { facts(natural: (1920, 1080), transform: rotate90) }
    private var mirroredPortrait: ImportSourceFacts { facts(transform: mirrorX) }

    /// Scripts one candidate per facts value, each at its own URL, in the given order.
    private func candidates(_ list: [ImportSourceFacts], sameURL: Bool = false) async -> [ImportCandidate] {
        var result: [ImportCandidate] = []
        let shared = URL(fileURLWithPath: "/workspace/shared.mov")
        for (index, f) in list.enumerated() {
            let url = sameURL ? shared : URL(fileURLWithPath: "/workspace/candidate-\(index).mov")
            await fake.set(.facts(f), for: url)
            result.append(ImportCandidate(url: url))
        }
        return result
    }

    private func run(_ list: [ImportSourceFacts], _ context: ImportSelectionContext = .multipleItems) async throws -> ImportSelectionPreflightOutcome {
        try await preflight.run(await candidates(list), context: context)
    }

    private func assertNotice(_ list: [ImportSourceFacts], _ context: ImportSelectionContext = .multipleItems, is expected: ImportSelectionNotice?, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let outcome = try await run(list, context)
            XCTAssertEqual(outcome.notice, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }

    private func categories(_ outcome: ImportSelectionPreflightOutcome) -> [ImportExclusionCategory] { outcome.excluded.map(\.category) }
    private func rejections(_ outcome: ImportSelectionPreflightOutcome) -> [ImportPreflightRejection] { outcome.excluded.map(\.rejection) }

    private func assertThrows<T>(_ expected: ImportSelectionPreflightError, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> T) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as ImportSelectionPreflightError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }

    // MARK: - 1. Accepted Set

    func testEmptyMultiSelectionYieldsEmptyOutcomeWithoutNotice() async throws {
        let outcome = try await run([])
        XCTAssertEqual(outcome, ImportSelectionPreflightOutcome(context: .multipleItems, accepted: [], excluded: [], notice: nil))
        XCTAssertFalse(outcome.requiresNormalization)
        let requested = await fake.requested
        XCTAssertTrue(requested.isEmpty)
    }

    func testReadyItemIsAcceptedOnFastPath() async throws {
        let outcome = try await run([ready])
        XCTAssertEqual(outcome.accepted.count, 1); XCTAssertTrue(outcome.excluded.isEmpty); XCTAssertNil(outcome.notice)
        let item = outcome.accepted[0]
        XCTAssertEqual(item.preparationPath, .fastPathCopy)
        XCTAssertEqual(item.sourceDuration, time(1200, 600))
        XCTAssertEqual(item.verdict, .readyFastPath(sourceDuration: time(1200, 600)))
        XCTAssertEqual(item.facts, ready)
        XCTAssertFalse(outcome.requiresNormalization)
    }

    func testNormalizationRequiredItemStaysAcceptedWithItsReasons() async throws {
        let outcome = try await run([hdr])
        XCTAssertEqual(outcome.accepted.count, 1); XCTAssertTrue(outcome.excluded.isEmpty); XCTAssertNil(outcome.notice)
        XCTAssertEqual(outcome.accepted[0].preparationPath, .normalizationRequired(reasons: [.hdr(signals: [.hlgTransfer])]))
        XCTAssertTrue(outcome.requiresNormalization)
    }

    func testMixedReadyAndNormalizationRequiredKeepOrderDurationsAndReasons() async throws {
        let list = [ready, sixtyFPS, fourK, ready, hdr]
        let cands = await candidates(list)
        let outcome = try await preflight.run(cands, context: .multipleItems)
        XCTAssertEqual(outcome.accepted.map(\.candidate), cands)
        XCTAssertEqual(outcome.accepted.map(\.preparationPath), [
            .fastPathCopy,
            .normalizationRequired(reasons: [.frameRate(nominal: 60)]),
            .normalizationRequired(reasons: [.raster(presentationWidth: 2160, presentationHeight: 3840)]),
            .fastPathCopy,
            .normalizationRequired(reasons: [.hdr(signals: [.hlgTransfer])])
        ])
        XCTAssertEqual(outcome.accepted.map(\.sourceDuration), Array(repeating: time(1200, 600), count: 5))
        XCTAssertTrue(outcome.excluded.isEmpty); XCTAssertNil(outcome.notice)
        XCTAssertTrue(outcome.requiresNormalization)
        let requested = await fake.requested
        XCTAssertEqual(requested, cands.map(\.url), "inspection follows input order")
    }

    func testExactBoundaryDurationsArePreservedNotCoerced() async throws {
        let one = facts(duration: .exact(time(1, 1)))
        let five = facts(duration: .exact(time(3000, 600)))
        let fractional = facts(duration: .exact(time(44_100 * 27 / 10, 44_100)))   // 2.7 s at 44.1 kHz
        let outcome = try await run([one, five, fractional])
        XCTAssertEqual(outcome.accepted.map(\.sourceDuration), [time(1, 1), time(3000, 600), time(119_070, 44_100)])
        XCTAssertTrue(outcome.excluded.isEmpty)
    }

    // MARK: - 2. Duration exclusions

    func testBelowMinimumOnly() async throws {
        let outcome = try await run([ready, short, ready])
        XCTAssertEqual(outcome.accepted.count, 2)
        XCTAssertEqual(rejections(outcome), [.durationBelowMinimum])
        XCTAssertEqual(categories(outcome), [.durationBelowMinimum])
        XCTAssertEqual(outcome.notice, .shortItemsExcluded)
    }

    func testAboveMaximumOnly() async throws {
        let outcome = try await run([long, ready])
        XCTAssertEqual(outcome.accepted.count, 1)
        XCTAssertEqual(rejections(outcome), [.durationAboveMaximum])
        XCTAssertEqual(outcome.notice, .longItemsExcluded)
    }

    func testBelowAndAboveInOneSelection() async throws {
        let outcome = try await run([short, ready, long])
        XCTAssertEqual(outcome.accepted.count, 1)
        XCTAssertEqual(categories(outcome), [.durationBelowMinimum, .durationAboveMaximum])
        XCTAssertEqual(outcome.notice, .shortAndLongItemsExcluded)
    }

    func testAllDurationIneligibleLeavesEmptyAcceptedSetWithNotice() async throws {
        let outcome = try await run([short, long, short])
        XCTAssertTrue(outcome.accepted.isEmpty)
        XCTAssertEqual(categories(outcome), [.durationBelowMinimum, .durationAboveMaximum, .durationBelowMinimum])
        XCTAssertEqual(outcome.notice, .shortAndLongItemsExcluded)
    }

    func testEligibleIncludingNormalizationRequiredSurviveDurationFiltering() async throws {
        let list = [short, hdr, ready, long]
        let cands = await candidates(list)
        let outcome = try await preflight.run(cands, context: .multipleItems)
        XCTAssertEqual(outcome.accepted.map(\.preparationPath), [.normalizationRequired(reasons: [.hdr(signals: [.hlgTransfer])]), .fastPathCopy])
        XCTAssertEqual(outcome.notice, .shortAndLongItemsExcluded)
        // Exhaustive partition: every candidate lands in exactly one list, each list in input
        // order, and the stored verdict agrees with the path + duration it was built from.
        XCTAssertEqual(outcome.accepted.count + outcome.excluded.count, list.count)
        XCTAssertEqual(outcome.accepted.map(\.candidate), [cands[1], cands[2]])
        XCTAssertEqual(outcome.excluded.map(\.candidate), [cands[0], cands[3]])
        XCTAssertEqual(outcome.accepted.map(\.verdict), [
            .normalizationRequired(reasons: [.hdr(signals: [.hlgTransfer])], sourceDuration: time(1200, 600)),
            .readyFastPath(sourceDuration: time(1200, 600))
        ])
    }

    func testInvalidDurationIsInvalidMediaNotTooShort() async throws {
        let outcome = try await run([invalidDuration])
        XCTAssertEqual(rejections(outcome), [.invalidDuration])
        XCTAssertEqual(categories(outcome), [.invalidOrUnsupportedMedia])
        XCTAssertEqual(outcome.notice, .invalidOrUnsupportedItemsExcluded)
    }

    // MARK: - 3. Invalid / unsupported exclusions (one family, exact rejection kept)

    func testEachInvalidOrUnsupportedRejectionMapsToOneCategory() async throws {
        let list = [unreadable, noVideo, protected, mp4, unknownContainer, prores, unknownCodec]
        let outcome = try await run(list)
        XCTAssertTrue(outcome.accepted.isEmpty)
        XCTAssertEqual(rejections(outcome), [
            .invalidDuration,   // an unreadable file reports no duration: duration is gate 1
            .noVideoTrack,
            .protectedContent,
            .unsupportedContainer(.isoBaseMedia(brands: ["mp42", "isom"])),
            .unsupportedContainer(.unknown),
            .unsupportedCodec(.unsupported(fourCC: "apch")),
            .unsupportedCodec(.unknown)
        ])
        XCTAssertEqual(categories(outcome), Array(repeating: .invalidOrUnsupportedMedia, count: 7))
        XCTAssertEqual(outcome.notice, .invalidOrUnsupportedItemsExcluded)
    }

    func testUnreadableWithFiniteDurationFactsIsStillInvalidMedia() async throws {
        let outcome = try await run([facts(readable: false)])
        XCTAssertEqual(rejections(outcome), [.unreadable])
        XCTAssertEqual(categories(outcome), [.invalidOrUnsupportedMedia])
    }

    func testEveryRejectionHasExactlyOneCategory() {
        let all: [ImportPreflightRejection] = [
            .durationBelowMinimum, .durationAboveMaximum, .invalidDuration, .unreadable, .noVideoTrack, .protectedContent,
            .unsupportedContainer(.unknown), .unsupportedCodec(.unknown),
            .nonPortraitPresentation(.landscape), .nonPortraitPresentation(.square)
        ]
        XCTAssertEqual(all.map(ImportExclusionCategory.init), [
            .durationBelowMinimum, .durationAboveMaximum, .invalidOrUnsupportedMedia, .invalidOrUnsupportedMedia, .invalidOrUnsupportedMedia, .invalidOrUnsupportedMedia,
            .invalidOrUnsupportedMedia, .invalidOrUnsupportedMedia, .nonPortraitPresentation, .nonPortraitPresentation
        ])
        XCTAssertEqual(ImportExclusionCategory.allCases.count, 4)
    }

    // MARK: - 4. Orientation (ADR-043 R1; ROADMAP orientation cases 1–8, 10–13)

    func testPortraitVariantsAreAcceptedAndNonPortraitIsOneCategory() async throws {
        let outcome = try await run([ready, rotatedPortrait, mirroredPortrait, landscape, square])
        XCTAssertEqual(outcome.accepted.map(\.facts), [ready, rotatedPortrait, mirroredPortrait])
        XCTAssertEqual(rejections(outcome), [.nonPortraitPresentation(.landscape), .nonPortraitPresentation(.square)])
        XCTAssertEqual(categories(outcome), [.nonPortraitPresentation, .nonPortraitPresentation])
        XCTAssertEqual(outcome.notice, .nonPortraitItemsExcluded)
    }

    func testMixedPortraitLandscapeSquareContinuesWithPortraitOnly() async throws {
        let list = [landscape, ready, square, hdr, landscape]
        let cands = await candidates(list)
        let outcome = try await preflight.run(cands, context: .multipleItems)
        XCTAssertEqual(outcome.accepted.map(\.candidate), [cands[1], cands[3]])
        XCTAssertEqual(outcome.excluded.map(\.candidate), [cands[0], cands[2], cands[4]])
        XCTAssertEqual(outcome.notice, .nonPortraitItemsExcluded)
    }

    func testAllNonPortraitLeavesEmptyAcceptedSet() async throws {
        let outcome = try await run([landscape, square])
        XCTAssertTrue(outcome.accepted.isEmpty)
        XCTAssertEqual(outcome.notice, .nonPortraitItemsExcluded)
    }

    func testNonPortraitCombinedWithOtherReasonsIsMixed() async throws {
        await assertNotice([landscape, short, ready], is: .mixedItemsExcluded)
        await assertNotice([square, mp4], is: .mixedItemsExcluded)
    }

    // MARK: - 5. Notice derivation

    func testMultiItemNoticeMatrix() async throws {
        await assertNotice([ready, hdr], is: nil)
        await assertNotice([short, ready], is: .shortItemsExcluded)
        await assertNotice([long, ready], is: .longItemsExcluded)
        await assertNotice([short, long], is: .shortAndLongItemsExcluded)
        await assertNotice([mp4, prores, ready], is: .invalidOrUnsupportedItemsExcluded)
        await assertNotice([landscape, ready], is: .nonPortraitItemsExcluded)
        await assertNotice([short, mp4, ready], is: .mixedItemsExcluded)
        await assertNotice([long, landscape], is: .mixedItemsExcluded)
        await assertNotice([unknownCodec, square, ready], is: .mixedItemsExcluded)
        await assertNotice([short, long, mp4, landscape, ready], is: .mixedItemsExcluded)
    }

    func testSingleCandidateNoticeMatrix() async throws {
        await assertNotice([ready], .singleCandidate, is: nil)
        await assertNotice([hdr], .singleCandidate, is: nil)
        await assertNotice([short], .singleCandidate, is: .candidateBelowMinimum)
        await assertNotice([long], .singleCandidate, is: .candidateAboveMaximum)
        await assertNotice([mp4], .singleCandidate, is: .candidateInvalidOrUnsupported)
        await assertNotice([unreadable], .singleCandidate, is: .candidateInvalidOrUnsupported)
        await assertNotice([prores], .singleCandidate, is: .candidateInvalidOrUnsupported)
        await assertNotice([landscape], .singleCandidate, is: .candidateNonPortrait)
        await assertNotice([square], .singleCandidate, is: .candidateNonPortrait)
    }

    func testSingleCandidateRejectionKeepsExactRejectionAndEmptyAcceptedSet() async throws {
        let outcome = try await run([square], .singleCandidate)
        XCTAssertTrue(outcome.accepted.isEmpty)
        XCTAssertEqual(rejections(outcome), [.nonPortraitPresentation(.square)])
        XCTAssertEqual(outcome.context, .singleCandidate)
    }

    func testNoticeDerivationIsPureAndOrderIndependent() {
        let a = ImportExcludedItem(candidate: ImportCandidate(url: URL(fileURLWithPath: "/a")), facts: short, rejection: .durationBelowMinimum)
        let b = ImportExcludedItem(candidate: ImportCandidate(url: URL(fileURLWithPath: "/b")), facts: mp4, rejection: .unsupportedContainer(.unknown))
        XCTAssertEqual(ImportSelectionNotice.derive(context: .multipleItems, excluded: [a, b]), .mixedItemsExcluded)
        XCTAssertEqual(ImportSelectionNotice.derive(context: .multipleItems, excluded: [b, a]), .mixedItemsExcluded)
        XCTAssertNil(ImportSelectionNotice.derive(context: .multipleItems, excluded: []))
        XCTAssertNil(ImportSelectionNotice.derive(context: .singleCandidate, excluded: []))
    }

    func testSingleCandidateCardinalityIsATypedError() async {
        let two = await candidates([ready, ready])
        await assertThrows(.invalidCardinality(context: .singleCandidate, count: 2)) { try await self.preflight.run(two, context: .singleCandidate) }
        await assertThrows(.invalidCardinality(context: .singleCandidate, count: 0)) { try await self.preflight.run([], context: .singleCandidate) }
        let requested = await fake.requested
        XCTAssertTrue(requested.isEmpty, "cardinality is checked before any inspection")
    }

    // MARK: - 6. Failure and cancellation

    func testInspectionErrorOnFirstItemIsAnOperationFailure() async {
        let cands = await candidates([ready, ready])
        await fake.set(.inspectionError(.sourceMissing), for: cands[0].url)
        await assertThrows(.inspectionFailed(candidate: cands[0].id, underlying: .sourceMissing)) {
            try await self.preflight.run(cands, context: .multipleItems)
        }
        let requested = await fake.requested
        XCTAssertEqual(requested, [cands[0].url], "nothing after the failure is inspected")
    }

    func testInspectionErrorAfterSuccessfulItemsYieldsNoPartialOutcome() async {
        let cands = await candidates([ready, hdr, ready])
        await fake.set(.inspectionError(.assetLoadFailed(domain: "AVFoundationErrorDomain", code: -11800)), for: cands[2].url)
        await assertThrows(.inspectionFailed(candidate: cands[2].id, underlying: .assetLoadFailed(domain: "AVFoundationErrorDomain", code: -11800))) {
            try await self.preflight.run(cands, context: .multipleItems)
        }
    }

    func testInspectionErrorIsNeverConvertedIntoAnExclusion() async {
        for error: ImportInspectionError in [.notFileURL, .sourceMissing, .sourceNotRegularFile, .sourceUnreadable, .videoTrackLoadFailed(domain: "d", code: 1)] {
            let fresh = FakeImportSourceInspector()
            let url = URL(fileURLWithPath: "/workspace/x.mov")
            await fresh.set(.inspectionError(error), for: url)
            let candidate = ImportCandidate(url: url)
            await assertThrows(.inspectionFailed(candidate: candidate.id, underlying: error)) {
                try await ImportSelectionPreflight(inspector: fresh).run([candidate], context: .singleCandidate)
            }
        }
    }

    func testUndeclaredInspectorErrorIsPreservedAsUnexpectedFailure() async {
        let cands = await candidates([ready])
        await fake.set(.otherError(NSError(domain: "TestDomain", code: 42)), for: cands[0].url)
        await assertThrows(.unexpectedInspectionFailure(candidate: cands[0].id, domain: "TestDomain", code: 42)) {
            try await self.preflight.run(cands, context: .multipleItems)
        }
    }

    func testPreCancelledOperationThrowsCancellationBeforeAnyInspection() async {
        let cands = await candidates([ready, ready])
        let gate = FakeImportSourceInspector()   // reused only as a deterministic start gate
        let gateURL = URL(fileURLWithPath: "/gate")
        await gate.set(.facts(ready), for: gateURL)
        await gate.pause(beforeRequest: 0)
        let task = Task { () throws -> ImportSelectionPreflightOutcome in
            _ = try? await gate.inspect(url: gateURL)   // suspends until released
            return try await self.preflight.run(cands, context: .multipleItems)
        }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.resumePaused()
        let result = await task.result
        guard case .failure(let error) = result else { return XCTFail("expected cancellation") }
        XCTAssertTrue(error is CancellationError, "\(error)")
        let requested = await fake.requested
        XCTAssertTrue(requested.isEmpty)
    }

    func testCancellationBetweenItemsThrowsCancellationWithoutPartialOutcome() async {
        let cands = await candidates([ready, hdr, ready])
        await fake.pause(beforeRequest: 1)
        let task = Task { try await self.preflight.run(cands, context: .multipleItems) }
        await fake.waitUntilPaused()
        task.cancel()
        await fake.resumePaused()
        let result = await task.result
        guard case .failure(let error) = result else { return XCTFail("expected cancellation") }
        XCTAssertTrue(error is CancellationError, "\(error)")
        let requested = await fake.requested
        XCTAssertEqual(requested, [cands[0].url, cands[1].url], "the third candidate is never inspected")
    }

    func testCancellationDuringLastItemThrowsWithoutOutcome() async {
        // Cancellation arrives while the LAST candidate is being inspected and that inspection
        // then returns facts normally: the trailing check must still refuse to build an outcome.
        let cands = await candidates([ready, short, hdr])
        await fake.pause(beforeRequest: 2)
        let task = Task { try await self.preflight.run(cands, context: .multipleItems) }
        await fake.waitUntilPaused()
        task.cancel()
        await fake.resumePaused()
        let result = await task.result
        guard case .failure(let error) = result else { return XCTFail("expected cancellation, got an outcome") }
        XCTAssertTrue(error is CancellationError, "\(error)")
        let requested = await fake.requested
        XCTAssertEqual(requested, cands.map(\.url), "every candidate was inspected, in input order")
    }

    func testCancellationThrownByTheInspectorPropagatesUnchanged() async {
        struct CancellingInspector: ImportSourceInspecting {
            func inspect(url: URL) async throws -> ImportSourceFacts { throw CancellationError() }
        }
        do {
            _ = try await ImportSelectionPreflight(inspector: CancellingInspector()).run([ImportCandidate(url: URL(fileURLWithPath: "/x"))], context: .singleCandidate)
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    // MARK: - 7. Identity and duplicates

    func testSameURLWithDistinctIdentitiesKeepsBothOccurrences() async throws {
        let cands = await candidates([ready, ready], sameURL: true)
        XCTAssertEqual(cands[0].url, cands[1].url); XCTAssertNotEqual(cands[0].id, cands[1].id)
        let outcome = try await preflight.run(cands, context: .multipleItems)
        XCTAssertEqual(outcome.accepted.map(\.candidate), cands)
        let requested = await fake.requested
        XCTAssertEqual(requested.count, 2)
    }

    func testDuplicateIdentityIsATypedErrorBeforeAnyInspection() async {
        let id = ImportCandidateID()
        let a = ImportCandidate(id: id, url: URL(fileURLWithPath: "/workspace/a.mov"))
        let b = ImportCandidate(id: id, url: URL(fileURLWithPath: "/workspace/b.mov"))
        await fake.set(.facts(ready), for: a.url); await fake.set(.facts(ready), for: b.url)
        await assertThrows(.duplicateCandidateIdentity(id)) { try await self.preflight.run([a, b], context: .multipleItems) }
        let requested = await fake.requested
        XCTAssertTrue(requested.isEmpty)
    }

    func testExplicitIdentitiesRoundTripThroughResults() async throws {
        let ids = [ImportCandidateID(rawValue: UUID()), ImportCandidateID(rawValue: UUID()), ImportCandidateID(rawValue: UUID())]
        let list = [ready, short, hdr]
        var cands: [ImportCandidate] = []
        for (index, f) in list.enumerated() {
            let url = URL(fileURLWithPath: "/workspace/id-\(index).mov")
            await fake.set(.facts(f), for: url)
            cands.append(ImportCandidate(id: ids[index], url: url))
        }
        let outcome = try await preflight.run(cands, context: .multipleItems)
        XCTAssertEqual(outcome.accepted.map(\.candidate.id), [ids[0], ids[2]])
        XCTAssertEqual(outcome.excluded.map(\.candidate.id), [ids[1]])
        XCTAssertEqual(outcome.accepted.map(\.candidate.url) + outcome.excluded.map(\.candidate.url), [cands[0].url, cands[2].url, cands[1].url])
    }

    func testModelsAreValueTypesWithoutCopyStrings() {
        XCTAssertNotEqual(ImportCandidateID(), ImportCandidateID())
        // A rejected verdict can never become an accepted item: no constructor from a verdict is
        // reachable outside the preflight file (compile-time guarantee, nothing to assert at runtime).
        let notices: [ImportSelectionNotice] = [.shortItemsExcluded, .longItemsExcluded, .shortAndLongItemsExcluded, .invalidOrUnsupportedItemsExcluded, .nonPortraitItemsExcluded, .mixedItemsExcluded, .candidateBelowMinimum, .candidateAboveMaximum, .candidateInvalidOrUnsupported, .candidateNonPortrait]
        XCTAssertEqual(Set(notices).count, 10)
        let held: any Sendable = ImportSelectionPreflightOutcome(context: .multipleItems, accepted: [], excluded: [], notice: nil)
        XCTAssertNotNil(held)
    }

    // MARK: - 8. Real adapter (few cases; Step 2 already covers the inspector itself)

    private struct RealFixtures {
        var scratch: URL
        func write(name: String, fileType: AVFileType, width: Int, height: Int, frameDuration: CMTime, frames: Int) async throws -> URL {
            let url = scratch.appendingPathComponent(name).appendingPathExtension(fileType == .mp4 ? "mp4" : "mov")
            let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            writer.startSession(atSourceTime: .zero)
            for index in 0..<frames {
                while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
                guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let pixelBuffer = buffer else { throw CocoaError(.fileWriteUnknown) }
                CVPixelBufferLockBaseAddress(pixelBuffer, [])
                memset(CVPixelBufferGetBaseAddress(pixelBuffer), index % 2 == 0 ? 0x40 : 0xC0, CVPixelBufferGetDataSize(pixelBuffer))
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                adaptor.append(pixelBuffer, withPresentationTime: CMTimeMultiply(frameDuration, multiplier: Int32(index)))
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            return url
        }
    }

    private func stamp(_ url: URL) throws -> (bytes: Int64, modified: Date?, sha256: String) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        return ((attributes[.size] as? NSNumber)?.int64Value ?? -1, attributes[.modificationDate] as? Date, digest)
    }

    private func entries(_ directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    func testRealAdapterAcceptsReadyKeepsNormalizationRequiredAndExcludesMP4WithoutTouchingSources() async throws {
        let scratch = TestSupport.temporaryRoot("selection-preflight")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let fixtures = RealFixtures(scratch: scratch)

        // Ready H.264 QuickTime from the shared device fixture generator (540×960, 30 fps, 1.5 s).
        let readyURL = scratch.appendingPathComponent("ready.mov")
        try await FixtureVideoWriter.write(to: readyURL, seconds: 1.5)
        // Same shape, but an actual MP4 container → unsupported container (ADR-044).
        let mp4URL = try await fixtures.write(name: "iso", fileType: .mp4, width: 540, height: 960, frameDuration: CMTime(value: 20, timescale: 600), frames: 45)
        // 60 fps portrait QuickTime (1.5 s) → normalization-required, never excluded.
        let sixtyURL = try await fixtures.write(name: "sixty", fileType: .mov, width: 540, height: 960, frameDuration: CMTime(value: 10, timescale: 600), frames: 90)

        let before = try [readyURL, mp4URL, sixtyURL].map(stamp)
        let listing = entries(scratch)
        let cands = [readyURL, mp4URL, sixtyURL].map { ImportCandidate(url: $0) }

        let outcome = try await ImportSelectionPreflight(inspector: AVAssetImportSourceInspector()).run(cands, context: .multipleItems)

        XCTAssertEqual(outcome.accepted.map(\.candidate), [cands[0], cands[2]])
        XCTAssertEqual(outcome.accepted[0].preparationPath, .fastPathCopy)
        XCTAssertEqual(outcome.accepted[0].facts.container, .quickTime)
        XCTAssertEqual(outcome.accepted[0].facts.videoCodec, .h264(fourCC: "avc1"))
        guard case .normalizationRequired(let reasons) = outcome.accepted[1].preparationPath, reasons.count == 1,
              case .frameRate(let nominal) = reasons[0] else { return XCTFail("expected a frame-rate normalization reason, got \(outcome.accepted[1].preparationPath)") }
        XCTAssertGreaterThan(nominal, ImportPreflightPolicy.maximumNominalFrameRate)
        XCTAssertEqual(outcome.excluded.map(\.candidate), [cands[1]])
        guard case .unsupportedContainer(.isoBaseMedia) = outcome.excluded[0].rejection else { return XCTFail("expected ISO BMFF rejection, got \(outcome.excluded[0].rejection)") }
        XCTAssertEqual(outcome.excluded[0].category, .invalidOrUnsupportedMedia)
        XCTAssertEqual(outcome.notice, .invalidOrUnsupportedItemsExcluded)
        XCTAssertTrue(outcome.requiresNormalization)

        // Sources untouched, nothing created: same bytes / mtime / checksum, same directory listing.
        let after = try [readyURL, mp4URL, sixtyURL].map(stamp)
        for (b, a) in zip(before, after) {
            XCTAssertEqual(b.bytes, a.bytes); XCTAssertEqual(b.modified, a.modified); XCTAssertEqual(b.sha256, a.sha256)
        }
        XCTAssertEqual(entries(scratch), listing)
        XCTAssertTrue(TestSupport.noProjectMedia(under: scratch))
    }

    func testRealAdapterSingleCandidateMP4IsRejectedWithoutSideEffects() async throws {
        let scratch = TestSupport.temporaryRoot("selection-preflight-single")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let mp4URL = try await RealFixtures(scratch: scratch).write(name: "iso", fileType: .mp4, width: 540, height: 960, frameDuration: CMTime(value: 20, timescale: 600), frames: 45)
        let before = try stamp(mp4URL)
        let outcome = try await ImportSelectionPreflight(inspector: AVAssetImportSourceInspector()).run([ImportCandidate(url: mp4URL)], context: .singleCandidate)
        XCTAssertTrue(outcome.accepted.isEmpty)
        XCTAssertEqual(outcome.notice, .candidateInvalidOrUnsupported)
        let after = try stamp(mp4URL)
        XCTAssertEqual(before.bytes, after.bytes); XCTAssertEqual(before.modified, after.modified); XCTAssertEqual(before.sha256, after.sha256)
        XCTAssertEqual(entries(scratch), ["iso.mp4"])
    }

    func testRealAdapterMissingFileIsAnOperationFailureNotAnExclusion() async throws {
        let scratch = TestSupport.temporaryRoot("selection-preflight-missing")
        let missing = ImportCandidate(url: scratch.appendingPathComponent("gone.mov"))
        await assertThrows(.inspectionFailed(candidate: missing.id, underlying: .sourceMissing)) {
            try await ImportSelectionPreflight(inspector: AVAssetImportSourceInspector()).run([missing], context: .singleCandidate)
        }
        XCTAssertFalse(TestSupport.exists(scratch), "preflight never creates directories")
    }
}
