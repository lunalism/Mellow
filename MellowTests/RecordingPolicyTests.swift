import XCTest
@testable import Mellow

final class RecordingPolicyTests: XCTestCase {
    func testStrictOneSecondLowerBound() {
        XCTAssertEqual(RecordingPolicy.judge(duration: 0.97, selectedMaximum: 3), .tooShort, "no rounding up")
        XCTAssertEqual(RecordingPolicy.judge(duration: 0.999, selectedMaximum: 3), .tooShort)
        XCTAssertEqual(RecordingPolicy.judge(duration: 1.0, selectedMaximum: 3), .valid)
        XCTAssertEqual(RecordingPolicy.judge(duration: 1.4, selectedMaximum: 3), .valid)
        XCTAssertEqual(RecordingPolicy.judge(duration: 0, selectedMaximum: 3), .tooShort)
        XCTAssertEqual(RecordingPolicy.judge(duration: .nan, selectedMaximum: 3), .tooShort)
    }

    func testOneFrameUpperToleranceOnly() {
        let frame = RecordingPolicy.upperDurationTolerance
        XCTAssertEqual(frame, 1.0 / 30.0, accuracy: 1e-9)
        XCTAssertEqual(RecordingPolicy.judge(duration: 3.0, selectedMaximum: 3), .valid)
        XCTAssertEqual(RecordingPolicy.judge(duration: 3.0 + frame * 0.9, selectedMaximum: 3), .valid, "encoder quantization absorbed")
        XCTAssertEqual(RecordingPolicy.judge(duration: 3.0 + frame * 1.5, selectedMaximum: 3), .tooLong)
        XCTAssertEqual(RecordingPolicy.judge(duration: 2.2, selectedMaximum: 5), .valid, "interruption at 2.2s under a 5s preset")
    }

    func testEveryPresetIsAMaximumCappedAtFiveSeconds() {
        for preset in CameraDuration.allCases {
            let max = TimeInterval(preset.rawValue)
            XCTAssertEqual(RecordingPolicy.judge(duration: max, selectedMaximum: max), .valid, "\(preset)")
            XCTAssertEqual(RecordingPolicy.judge(duration: max + 0.2, selectedMaximum: max), .tooLong, "\(preset)")
        }
        XCTAssertEqual(RecordingPolicy.judge(duration: 5.2, selectedMaximum: 9), .tooLong, "absolute cap is 5s")
        XCTAssertEqual(RecordingPolicy.absoluteMaximumDuration, 5)
        XCTAssertEqual(CameraDuration.three.rawValue, 3, "default preset")
    }

    func testStorageGateIs200MB() {
        XCTAssertEqual(RecordingPolicy.minimumUsableStorageBytes, 200 * 1_024 * 1_024)
        XCTAssertFalse(RecordingPolicy.hasSufficientStorage(usableBytes: 199 * 1_024 * 1_024))
        XCTAssertTrue(RecordingPolicy.hasSufficientStorage(usableBytes: 200 * 1_024 * 1_024))
    }

    func testDomainClipCapMigratedToFiveSeconds() {
        XCTAssertEqual(ClipPolicy.maximumDuration, .seconds(5))
    }
}
