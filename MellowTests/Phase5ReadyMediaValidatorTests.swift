import CoreGraphics
import XCTest
@testable import Mellow

final class Phase5ReadyMediaValidatorTests: XCTestCase {
    private func info(seconds: Double = 2, size: CGSize = CGSize(width: 1080, height: 1920), fps: Float = 30, hdr: Bool = false, audio: Bool = true, readable: Bool = true, video: Bool = true) -> ProjectMediaInfo {
        ProjectMediaInfo(isReadable: readable, hasVideoTrack: video, hasAudioTrack: audio, duration: seconds, presentationSize: size, nominalFrameRate: fps, isHDR: hdr)
    }

    // MARK: - Judgement on inspected properties

    func testReadyPortraitClipIsAccepted() {
        guard case .ready(let duration) = Phase5ReadyMediaValidator.judge(info(seconds: 2)) else { return XCTFail() }
        XCTAssertEqual(Double(duration.value) / Double(duration.timescale), 2, accuracy: 0.002)
    }

    func testExactlyFiveSecondsAndOneFrameOverAreAccepted() {
        guard case .ready(let five) = Phase5ReadyMediaValidator.judge(info(seconds: 5)) else { return XCTFail() }
        XCTAssertEqual(Double(five.value) / Double(five.timescale), 5, accuracy: 0.0001)
        guard case .ready(let clamped) = Phase5ReadyMediaValidator.judge(info(seconds: 5 + 1.0 / 30)) else { return XCTFail("one-frame quantization overshoot is tolerated") }
        XCTAssertEqual(Double(clamped.value) / Double(clamped.timescale), 5, accuracy: 0.0001, "metadata never exceeds the 5 s invariant")
    }

    func testShortClipsAreAcceptedWithoutCameraMinimum() {
        // Imported minimum is distinct from the 1.0 s direct-capture rule; only 0 < d applies.
        guard case .ready = Phase5ReadyMediaValidator.judge(info(seconds: 0.4)) else { return XCTFail() }
    }

    func testTooLongRequiresImportPreparation() {
        XCTAssertEqual(Phase5ReadyMediaValidator.judge(info(seconds: 5.5)), .requiresImportPreparation(.tooLong))
        XCTAssertEqual(Phase5ReadyMediaValidator.judge(info(seconds: 134)), .requiresImportPreparation(.tooLong))
    }

    func testNormalizationRequiredSourcesRequireImportPreparation() {
        XCTAssertEqual(Phase5ReadyMediaValidator.judge(info(hdr: true)), .requiresImportPreparation(.highDynamicRange))
        XCTAssertEqual(Phase5ReadyMediaValidator.judge(info(size: CGSize(width: 2160, height: 3840))), .requiresImportPreparation(.resolution))
        XCTAssertEqual(Phase5ReadyMediaValidator.judge(info(fps: 60)), .requiresImportPreparation(.frameRate))
        XCTAssertEqual(Phase5ReadyMediaValidator.judge(info(size: CGSize(width: 1920, height: 1080))), .requiresImportPreparation(.orientation))
    }

    func testAudioLessValidSourceIsAccepted() {
        guard case .ready = Phase5ReadyMediaValidator.judge(info(audio: false)) else { return XCTFail() }
    }

    func testUnreadableOrNonVideoIsInvalid() {
        XCTAssertEqual(Phase5ReadyMediaValidator.judge(info(readable: false)), .invalid(.unreadable))
        XCTAssertEqual(Phase5ReadyMediaValidator.judge(info(video: false)), .invalid(.noVideoTrack))
        XCTAssertEqual(Phase5ReadyMediaValidator.judge(info(seconds: 0)), .invalid(.zeroDuration))
    }

    // MARK: - Real media through AVFoundation

    func testRealPortraitFixtureIsReady() async throws {
        let url = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let validator = Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector())
        guard case .ready(let duration) = await validator.validate(url) else { return XCTFail("expected ready") }
        XCTAssertEqual(Double(duration.value) / Double(duration.timescale), 2, accuracy: 0.05)
    }

    func testRealTooLongFixtureRequiresPreparationRegardlessOfName() async throws {
        // Named like a Mellow recording on purpose: only the inspected duration decides.
        let url = try await TestMediaFixtures.shared.portrait(seconds: 7, name: "mellow-camera-recording")
        let validator = Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector())
        let verdict = await validator.validate(url)
        XCTAssertEqual(verdict, .requiresImportPreparation(.tooLong))
    }

    func testRealCorruptFixtureIsInvalid() async throws {
        let url = try await TestMediaFixtures.shared.corrupt()
        let validator = Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector())
        let verdict = await validator.validate(url)
        guard case .invalid = verdict else { return XCTFail("expected invalid, got \(verdict)") }
    }

    func testValidationHasNoSideEffects() async throws {
        let url = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let before = try Data(contentsOf: url)
        let validator = Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector())
        _ = await validator.validate(url)
        _ = await validator.validate(url)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
}
