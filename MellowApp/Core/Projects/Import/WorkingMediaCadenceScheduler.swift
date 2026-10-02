import CoreMedia
import Foundation

// Phase 6 Step 4B — ADR-048 Revision 1: deterministic normalized-video cadence grid with frame hold.
// Pure timing selection over exact rationals (never `Double`): it decides which already-rendered
// frame is shown at each output target and never touches pixels, files or AVFoundation objects.

/// Why the cadence grid cannot be scheduled. Every case is a typed normalization failure.
enum WorkingMediaCadenceError: Error, Hashable, Sendable {
    /// The frame duration is invalid, not numeric, zero or negative.
    case invalidFrameDuration
    /// The session end is invalid, not numeric, zero or negative.
    case invalidSessionEnd
    /// Input frame `index` (source order) has an invalid or non-numeric presentation time.
    case invalidFrameTime(index: Int)
    /// Input frame `index` is presented earlier than the frame before it.
    case decreasingFrameTime(index: Int)
    /// No frame is presented at or before the first target (time zero): nothing may be pulled back
    /// from the future and no lead-in is synthesized.
    case noFrameAtOrBeforeFirstTarget
    /// Target `index` (or its duration) cannot be represented exactly.
    case unrepresentableTarget(index: Int)
    /// A frame was offered while the scheduler was not waiting for input.
    case unexpectedInput
}

/// One output target: `presentationTime = index × d`, `duration = min(d, E − presentationTime)`.
struct WorkingMediaCadenceTarget: Hashable, Sendable {
    let index: Int
    let presentationTime: CMTime
    let duration: CMTime
}

/// ADR-048 Revision 1. Targets are `t_k = k × d` for `k = 0, 1, …` while `t_k < E`; each gets exactly
/// one selection: the latest input frame (source order) presented at or before `t_k`, or the previous
/// selection held when no newer frame qualifies. A frame presented after `t_k` is never used for it.
///
/// Streaming and bounded: it keeps at most the current selection and one look-ahead frame. The
/// caller alternates `next()` (a target that can now be decided, or nil) with `offer(_:at:)` while
/// `needsInput`, and calls `finishInput()` when the input is exhausted; after that the last frame is
/// held up to the last target before `E`. `Frame` is opaque: it is retained and handed back, never
/// inspected or modified.
struct WorkingMediaCadenceScheduler<Frame> {
    struct Selection {
        let target: WorkingMediaCadenceTarget
        let frame: Frame
        /// Source-order position of the selected input frame (0-based).
        let frameOrdinal: Int
        /// True when this selection repeats the previous target's frame.
        let isHeld: Bool
    }

    private let frameDuration: ExactTime
    private let sessionEnd: ExactTime

    private var nextIndex = 0
    /// `nextIndex × d`, or nil when it is not representable.
    private var nextTarget: ExactTime?
    private var current: (frame: Frame, ordinal: Int)?
    private var currentIsNew = false
    private var lookahead: (frame: Frame, ordinal: Int, time: ExactTime)?
    private var lastTime: ExactTime?
    private var offeredCount = 0
    private var inputFinished = false

    init(frameDuration: CMTime, sessionEnd: CMTime) throws {
        guard let d = ExactTime(frameDuration), d.isPositive else { throw WorkingMediaCadenceError.invalidFrameDuration }
        guard let e = ExactTime(sessionEnd), e.isPositive else { throw WorkingMediaCadenceError.invalidSessionEnd }
        self.frameDuration = d
        self.sessionEnd = e
        nextTarget = ExactTime.zero(timescale: d.timescale)
    }

    /// Every target below the session end has been selected.
    var isComplete: Bool {
        guard let target = nextTarget else { return false }
        return !(target < sessionEnd)
    }

    /// `offer(_:at:)` is accepted: no look-ahead frame is pending and input has not finished.
    var needsInput: Bool { !isComplete && lookahead == nil && !inputFinished }

    /// Offers the next input frame in source order. Only valid while `needsInput`.
    mutating func offer(_ frame: Frame, at presentationTime: CMTime) throws {
        guard needsInput else { throw WorkingMediaCadenceError.unexpectedInput }
        let ordinal = offeredCount
        offeredCount += 1
        guard let time = ExactTime(presentationTime) else { throw WorkingMediaCadenceError.invalidFrameTime(index: ordinal) }
        if let lastTime, time < lastTime { throw WorkingMediaCadenceError.decreasingFrameTime(index: ordinal) }
        lastTime = time
        guard let target = nextTarget else { throw WorkingMediaCadenceError.unrepresentableTarget(index: nextIndex) }
        if time <= target {
            // At or before the pending target: the latest such frame (equal times: later source order) wins.
            current = (frame, ordinal)
            currentIsNew = true
        } else {
            lookahead = (frame, ordinal, time)
        }
    }

    /// The input is exhausted; remaining targets below `E` hold the last frame.
    mutating func finishInput() { inputFinished = true }

    /// The next target's selection when it can be decided, nil while more input is needed or once
    /// the grid is complete.
    mutating func next() throws -> Selection? {
        guard !isComplete else { return nil }
        guard let target = nextTarget else { throw WorkingMediaCadenceError.unrepresentableTarget(index: nextIndex) }
        // A look-ahead frame that the grid has caught up with becomes the current candidate; another
        // frame at or before this target may still follow, so more input is needed before deciding.
        if let pending = lookahead, pending.time <= target {
            current = (pending.frame, pending.ordinal)
            currentIsNew = true
            lookahead = nil
        }
        guard lookahead != nil || inputFinished else { return nil }
        guard let current else { throw WorkingMediaCadenceError.noFrameAtOrBeforeFirstTarget }
        guard let duration = target.duration(frame: frameDuration, end: sessionEnd) else {
            throw WorkingMediaCadenceError.unrepresentableTarget(index: nextIndex)
        }
        let selection = Selection(
            target: WorkingMediaCadenceTarget(index: nextIndex, presentationTime: target.cmTime, duration: duration.cmTime),
            frame: current.frame, frameOrdinal: current.ordinal, isHeld: !currentIsNew)
        currentIsNew = false
        nextIndex += 1
        nextTarget = frameDuration.multiplied(by: nextIndex)
        return selection
    }
}

extension WorkingMediaCadenceScheduler: Sendable where Frame: Sendable {}
extension WorkingMediaCadenceScheduler.Selection: Sendable where Frame: Sendable {}

/// An exact rational time `value / timescale` (timescale > 0). Comparisons use full-width products,
/// so no overflow and no floating point.
private struct ExactTime {
    let value: Int64
    let timescale: Int32

    init?(_ time: CMTime) {
        guard time.flags.contains(.valid), !time.flags.contains(.indefinite), !time.flags.contains(.positiveInfinity),
              !time.flags.contains(.negativeInfinity), time.timescale > 0 else { return nil }
        value = time.value
        timescale = time.timescale
    }

    private init(value: Int64, timescale: Int32) {
        self.value = value
        self.timescale = timescale
    }

    static func zero(timescale: Int32) -> ExactTime { ExactTime(value: 0, timescale: timescale) }

    var isPositive: Bool { value > 0 }
    var cmTime: CMTime { CMTime(value: value, timescale: timescale) }

    /// `self × factor`, nil on overflow.
    func multiplied(by factor: Int) -> ExactTime? {
        let (product, overflow) = value.multipliedReportingOverflow(by: Int64(factor))
        return overflow ? nil : ExactTime(value: product, timescale: timescale)
    }

    /// `min(frame, end − self)`, exact; nil when not representable.
    func duration(frame: ExactTime, end: ExactTime) -> ExactTime? {
        guard let remaining = end.subtract(self) else { return nil }
        return frame <= remaining ? frame : remaining
    }

    private func subtract(_ other: ExactTime) -> ExactTime? {
        guard let (a, b, scale) = ExactTime.common(self, other) else { return nil }
        let (difference, overflow) = a.subtractingReportingOverflow(b)
        return overflow ? nil : ExactTime(value: difference, timescale: scale)
    }

    /// Both values over their least common timescale, nil when anything overflows.
    private static func common(_ lhs: ExactTime, _ rhs: ExactTime) -> (Int64, Int64, Int32)? {
        let l = Int64(lhs.timescale), r = Int64(rhs.timescale)
        let divisor = gcd(l, r)
        let (lcm, overflow) = (l / divisor).multipliedReportingOverflow(by: r)
        guard !overflow, lcm <= Int64(Int32.max) else { return nil }
        let (a, aOverflow) = lhs.value.multipliedReportingOverflow(by: lcm / l)
        let (b, bOverflow) = rhs.value.multipliedReportingOverflow(by: lcm / r)
        guard !aOverflow, !bOverflow else { return nil }
        return (a, b, Int32(lcm))
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 { b == 0 ? a : gcd(b, a % b) }

    /// Exact `lhs.value / lhs.timescale` vs `rhs.value / rhs.timescale` by full-width cross products.
    private static func compare(_ lhs: ExactTime, _ rhs: ExactTime) -> Int {
        let left = lhs.value.multipliedFullWidth(by: Int64(rhs.timescale))
        let right = rhs.value.multipliedFullWidth(by: Int64(lhs.timescale))
        if left.high != right.high { return left.high < right.high ? -1 : 1 }
        if left.low != right.low { return left.low < right.low ? -1 : 1 }
        return 0
    }

    static func < (lhs: ExactTime, rhs: ExactTime) -> Bool { compare(lhs, rhs) < 0 }
    static func <= (lhs: ExactTime, rhs: ExactTime) -> Bool { compare(lhs, rhs) <= 0 }
}
