import CoreMedia
import XCTest
@testable import Mellow

/// ADR-048 Revision 1: the pure cadence grid. Inputs are labelled frames; every expectation is a
/// literal written from the rule, never derived from the scheduler.
final class WorkingMediaCadenceSchedulerTests: XCTestCase {
    private struct Pick: Equatable {
        let target: Int
        let time: CMTime
        let duration: CMTime
        let frame: Int
        let ordinal: Int
        let held: Bool
    }

    private func t(_ value: Int64, _ timescale: Int32 = 600) -> CMTime { CMTime(value: value, timescale: timescale) }

    /// Drives the scheduler exactly as the video pump does: decide a target when possible, otherwise
    /// offer the next frame, otherwise finish the input.
    private func schedule(_ frames: [(Int, CMTime)], d: CMTime, end: CMTime) throws -> [Pick] {
        var scheduler = try WorkingMediaCadenceScheduler<Int>(frameDuration: d, sessionEnd: end)
        var input = frames[...]
        var picks: [Pick] = []
        while true {
            if let selection = try scheduler.next() {
                picks.append(Pick(target: selection.target.index, time: selection.target.presentationTime, duration: selection.target.duration,
                                  frame: selection.frame, ordinal: selection.frameOrdinal, held: selection.isHeld))
                continue
            }
            if scheduler.isComplete { return picks }
            if let (frame, time) = input.popFirst() { try scheduler.offer(frame, at: time) } else { scheduler.finishInput() }
        }
    }

    /// Frames labelled 0, 1, 2, … at the given times (timescale 600).
    private func frames(_ values: [Int64], timescale: Int32 = 600) -> [(Int, CMTime)] {
        values.enumerated().map { ($0.offset, CMTime(value: $0.element, timescale: timescale)) }
    }

    /// Exact rational equality (CMTime `==` compares structure only when timescales match).
    private func assertSame(_ actual: CMTime, _ expected: CMTime, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(actual.isNumeric, "\(message) not numeric: \(actual)", file: file, line: line)
        let a = actual.value.multipliedFullWidth(by: Int64(expected.timescale)), b = expected.value.multipliedFullWidth(by: Int64(actual.timescale))
        XCTAssertTrue(a.high == b.high && a.low == b.low, "\(message) \(actual.value)/\(actual.timescale) ≠ \(expected.value)/\(expected.timescale)", file: file, line: line)
    }

    private func assertTimes(_ picks: [Pick], step: Int64, timescale: Int32 = 600, file: StaticString = #filePath, line: UInt = #line) {
        for (k, pick) in picks.enumerated() {
            XCTAssertEqual(pick.target, k, file: file, line: line)
            assertSame(pick.time, t(Int64(k) * step, timescale), "target \(k)", file: file, line: line)
        }
    }

    private func expectError(_ expected: WorkingMediaCadenceError, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Any) {
        do { _ = try body(); XCTFail("expected \(expected)", file: file, line: line) }
        catch let error as WorkingMediaCadenceError { XCTAssertEqual(error, expected, file: file, line: line) }
        catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }

    // MARK: - Selection

    func testAlignedCadenceSelectsEachFrameOnce() throws {
        let picks = try schedule(frames([0, 20, 40, 60, 80, 100, 120, 140, 160, 180]), d: t(1, 30), end: t(200))
        XCTAssertEqual(picks.map(\.frame), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(picks.filter(\.held).map(\.target), [])
        assertTimes(picks, step: 20)
        for pick in picks { assertSame(pick.duration, t(20)) }
    }

    func testOneJitterMissingTargetHoldsThePreviousFrame() throws {
        // The composition output observed on device: 0, 20, …, 700, then 740, 760, … (720 skipped).
        let times = Array(stride(from: Int64(0), through: 700, by: 20)) + [740, 760, 780, 800]
        let picks = try schedule(frames(times), d: t(20), end: t(820))
        XCTAssertEqual(picks.count, 41)
        assertTimes(picks, step: 20)
        XCTAssertEqual(picks.filter(\.held).map(\.target), [36])
        XCTAssertEqual(picks[35].frame, 35)
        XCTAssertEqual(picks[36].frame, 35, "720/600 shows the frame from 700/600")
        XCTAssertEqual(picks[37].frame, 36, "740/600 shows the new 740/600 frame")
        XCTAssertEqual(picks.map(\.frame), Array(0...35) + [35] + Array(36...39))
        XCTAssertEqual(Set(picks.map(\.frame)).count, 40, "no input frame dropped")
    }

    func testRawSourceJitterHoldsAtTheSameGridPoint() throws {
        // The camera's own times (721 after 700): 721 > 720, so 720 still shows 700; 740 shows 721
        // and 760 shows 741. 761 is never selected: the next target, 780, is the session end.
        let times = Array(stride(from: Int64(0), through: 700, by: 20)) + [721, 741, 761]
        let picks = try schedule(frames(times), d: t(20), end: t(780))
        XCTAssertEqual(picks.map(\.frame), Array(0...35) + [35, 36, 37])
        XCTAssertEqual(picks.filter(\.held).map(\.target), [36])
    }

    func testMultipleConsecutiveMissingTargets() throws {
        let picks = try schedule(frames([0, 20, 100, 120]), d: t(20), end: t(140))
        XCTAssertEqual(picks.map(\.frame), [0, 1, 1, 1, 1, 2, 3])
        XCTAssertEqual(picks.filter(\.held).map(\.target), [2, 3, 4])
        assertTimes(picks, step: 20)
    }

    func testLatestOfSeveralFramesBetweenTargetsWins() throws {
        let picks = try schedule(frames([0, 7, 13, 25, 31, 39]), d: t(20), end: t(60))
        XCTAssertEqual(picks.map(\.frame), [0, 2, 5])
        XCTAssertEqual(picks.map(\.held), [false, false, false])
    }

    func testEqualTimesResolveByLaterSourceOrder() throws {
        let picks = try schedule([(10, t(0)), (11, t(20)), (12, t(20)), (13, t(40))], d: t(20), end: t(60))
        XCTAssertEqual(picks.map(\.frame), [10, 12, 13])
        XCTAssertEqual(picks.map(\.ordinal), [0, 2, 3])
    }

    func testFirstFrameExactlyAtZero() throws {
        let picks = try schedule(frames([0]), d: t(20), end: t(20))
        XCTAssertEqual(picks, [Pick(target: 0, time: t(0), duration: t(20), frame: 0, ordinal: 0, held: false)])
    }

    func testFirstFrameAfterZeroIsATypedFailureNotAPullback() {
        expectError(.noFrameAtOrBeforeFirstTarget) { try self.schedule(frames([1, 20, 40]), d: t(20), end: t(60)) }
        expectError(.noFrameAtOrBeforeFirstTarget) { try self.schedule([], d: t(20), end: t(60)) }
    }

    func testFramesBeforeZeroAreEligibleForTheFirstTarget() throws {
        XCTAssertEqual(try schedule(frames([-10, -5, 0, 20]), d: t(20), end: t(40)).map(\.frame), [2, 3])
        XCTAssertEqual(try schedule(frames([-10, 15]), d: t(20), end: t(40)).map(\.frame), [0, 1])
    }

    func testExhaustedInputHoldsTheLastFrameUntilTheEnd() throws {
        let picks = try schedule(frames([0, 20]), d: t(20), end: t(100))
        XCTAssertEqual(picks.map(\.frame), [0, 1, 1, 1, 1])
        XCTAssertEqual(picks.filter(\.held).map(\.target), [2, 3, 4])
        assertSame(picks[4].time, t(80))
        assertSame(picks[4].duration, t(20))
    }

    func testFramesPastTheEndAreNeverUsed() throws {
        let picks = try schedule(frames([0, 20, 40, 60, 80]), d: t(20), end: t(41))
        XCTAssertEqual(picks.map(\.frame), [0, 1, 2])
        assertSame(picks[2].duration, t(1))
    }

    // MARK: - Frame rates (exact)

    func testTwentyFourFps() throws {
        let picks = try schedule(frames([0, 25, 50, 75, 100, 125]), d: t(1, 24), end: t(150))
        XCTAssertEqual(picks.map(\.frame), [0, 1, 2, 3, 4, 5])
        assertTimes(picks, step: 1, timescale: 24)
    }

    func testTwentyFiveFps() throws {
        let picks = try schedule(frames([0, 24, 48, 72, 96]), d: t(1, 25), end: t(120))
        XCTAssertEqual(picks.map(\.frame), [0, 1, 2, 3, 4])
        assertTimes(picks, step: 1, timescale: 25)
    }

    func testNTSCRateUsesExact1001Over30000() throws {
        let picks = try schedule(frames([0, 1001, 2002, 3003, 4004], timescale: 30_000), d: t(1001, 30_000), end: t(5005, 30_000))
        XCTAssertEqual(picks.map(\.frame), [0, 1, 2, 3, 4])
        assertTimes(picks, step: 1001, timescale: 30_000)
        for pick in picks { assertSame(pick.duration, t(1001, 30_000)) }
    }

    func testThirtyFps() throws {
        let picks = try schedule(frames([0, 1, 2, 3], timescale: 30), d: t(1, 30), end: t(4, 30))
        XCTAssertEqual(picks.map(\.frame), [0, 1, 2, 3])
        assertTimes(picks, step: 1, timescale: 30)
    }

    // MARK: - Session end

    func testFinalPartialDurationIsExact() throws {
        // 24 fps ending at 702/600: targets 0 … 700/600; the last lasts 2/600.
        let times = (0..<29).map { Int64($0) * 25 }
        let picks = try schedule(frames(times), d: t(1, 24), end: t(702))
        XCTAssertEqual(picks.count, 29)
        assertSame(picks[28].time, t(700))
        assertSame(picks[28].duration, t(2))
        for pick in picks.dropLast() { assertSame(pick.duration, t(25)) }
    }

    func testNoTargetAtOrAfterTheEnd() throws {
        XCTAssertEqual(try schedule(frames([0, 20, 40]), d: t(20), end: t(40)).map(\.target), [0, 1])
        let picks = try schedule(frames([0, 20, 40]), d: t(20), end: t(41))
        XCTAssertEqual(picks.map(\.target), [0, 1, 2])
        assertSame(picks[2].duration, t(1))
    }

    // MARK: - Invalid input

    func testInvalidDurationEndAndFrameTime() {
        for bad in [CMTime.invalid, .indefinite, .positiveInfinity, .negativeInfinity, t(0), t(-20)] {
            expectError(.invalidFrameDuration) { try WorkingMediaCadenceScheduler<Int>(frameDuration: bad, sessionEnd: self.t(600)) }
            expectError(.invalidSessionEnd) { try WorkingMediaCadenceScheduler<Int>(frameDuration: self.t(20), sessionEnd: bad) }
        }
        expectError(.invalidFrameTime(index: 1)) { try self.schedule([(0, self.t(0)), (1, .invalid)], d: self.t(20), end: self.t(60)) }
        expectError(.invalidFrameTime(index: 1)) { try self.schedule([(0, self.t(0)), (1, .indefinite)], d: self.t(20), end: self.t(60)) }
    }

    func testDecreasingTimesAreRejected() {
        expectError(.decreasingFrameTime(index: 2)) { try self.schedule(self.frames([0, 20, 10]), d: self.t(20), end: self.t(60)) }
    }

    func testOfferOutsideNeedsInputIsRejected() throws {
        var scheduler = try WorkingMediaCadenceScheduler<Int>(frameDuration: t(20), sessionEnd: t(60))
        try scheduler.offer(0, at: t(0))
        try scheduler.offer(1, at: t(30))   // look-ahead past target 0
        XCTAssertFalse(scheduler.needsInput)
        expectError(.unexpectedInput) { try scheduler.offer(2, at: self.t(40)) }
    }

    // MARK: - Exact arithmetic

    func testDifferentSourceTimescalesCompareExactly() throws {
        // 90 kHz frame times against a 600-based grid: 3000/90000 == 20/600 exactly.
        let mixed: [(Int, CMTime)] = [(0, t(0, 90_000)), (1, t(3_000, 90_000)), (2, t(2, 30)), (3, t(9_001, 90_000))]
        let picks = try schedule(mixed, d: t(20), end: t(80))
        XCTAssertEqual(picks.map(\.frame), [0, 1, 2, 2], "9001/90000 is just after 60/600, so 60/600 holds frame 2")
        XCTAssertEqual(picks.filter(\.held).map(\.target), [3])
    }

    func testLargeExactValuesDoNotOverflow() throws {
        // d = 1.5e18 / 1e9; target 2 is 3e18 / 1e9, offered as 6e18 / 2e9 (cross products exceed Int64).
        let d = t(1_500_000_000_000_000_000, 1_000_000_000)
        let picks = try schedule([(0, t(0, 1)), (1, d), (2, t(6_000_000_000_000_000_000, 2_000_000_000))],
                                 d: d, end: t(3_000_000_000_000_000_001, 1_000_000_000))
        XCTAssertEqual(picks.map(\.frame), [0, 1, 2])
        assertSame(picks[2].time, t(3_000_000_000_000_000_000, 1_000_000_000))
        assertSame(picks[2].duration, t(1, 1_000_000_000))
    }

    func testUnrepresentableTargetIsATypedFailure() {
        expectError(.unrepresentableTarget(index: 2)) {
            try self.schedule([(0, self.t(0, 1))], d: self.t(5_000_000_000_000_000_000, 1), end: self.t(Int64.max, 1))
        }
    }

    func testRepeatedRunsAreIdentical() throws {
        let times = Array(stride(from: Int64(0), through: 700, by: 20)) + [740, 760, 780, 800, 821, 900]
        let first = try schedule(frames(times), d: t(20), end: t(920))
        for _ in 0..<3 { XCTAssertEqual(try schedule(frames(times), d: t(20), end: t(920)), first) }
    }
}
