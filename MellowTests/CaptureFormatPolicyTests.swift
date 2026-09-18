import XCTest
@testable import Mellow

/// ADR-046 §2 direct-camera contract decisions, tested without hardware: the worker feeds real
/// AVFoundation capabilities into these pure functions and applies / verifies the results.
final class CaptureFormatPolicyTests: XCTestCase {
    private let codecKey = CaptureFormatPolicy.videoCodecSettingsKey

    // MARK: Codec

    func testH264AvailableSelectsExactlyH264OutputSettings() throws {
        let settings = try CaptureFormatPolicy.videoOutputSettings(availableCodecs: ["avc1", "hvc1"], supportedKeys: [codecKey, "AVVideoCompressionPropertiesKey"]).get()
        XCTAssertEqual(settings, [codecKey: "avc1"], "exactly the codec key, nothing else")
    }

    func testH264NotFirstInListIsStillSelectedNeverTheDefault() throws {
        // AVCaptureMovieFileOutput records with availableVideoCodecTypes.first by default (HEVC on
        // modern iPhones); the policy must pick H.264 regardless of position.
        let settings = try CaptureFormatPolicy.videoOutputSettings(availableCodecs: ["hvc1", "avc1", "jpeg"], supportedKeys: [codecKey]).get()
        XCTAssertEqual(settings[codecKey], "avc1")
    }

    func testH264UnavailableFailsWithoutFallback() {
        for available in [["hvc1"], ["hvc1", "ap4h"], ["apcn", "jpeg"], []] {
            switch CaptureFormatPolicy.videoOutputSettings(availableCodecs: available, supportedKeys: [codecKey]) {
            case .success(let settings): XCTFail("must not fall back to \(settings) for \(available)")
            case .failure(let rejection): XCTAssertEqual(rejection, .h264Unavailable(available: available))
            }
        }
    }

    func testCodecKeyNotSettableFails() {
        switch CaptureFormatPolicy.videoOutputSettings(availableCodecs: ["avc1"], supportedKeys: ["AVVideoCompressionPropertiesKey"]) {
        case .success: XCTFail("cannot apply H.264 when the key is unsupported")
        case .failure(let rejection): XCTAssertEqual(rejection, .codecKeyNotSettable)
        }
    }

    func testAppliedCodecMustReadBackAsH264() {
        XCTAssertNil(CaptureFormatPolicy.verifyAppliedCodec("avc1"))
        XCTAssertEqual(CaptureFormatPolicy.verifyAppliedCodec("hvc1"), .codecNotApplied(applied: "hvc1"))
        XCTAssertEqual(CaptureFormatPolicy.verifyAppliedCodec(nil), .codecNotApplied(applied: nil))
        XCTAssertEqual(CaptureFormatPolicy.verifyAppliedCodec("AVC1"), .codecNotApplied(applied: "AVC1"))
    }

    // MARK: Format (1080p / 30 fps)

    func testFormatMustBe1080pWith30fps() {
        XCTAssertNil(CaptureFormatPolicy.verifyFormat(width: 1920, height: 1080, supports30fps: true))
        XCTAssertEqual(CaptureFormatPolicy.verifyFormat(width: 3840, height: 2160, supports30fps: true), .formatNot1080p(width: 3840, height: 2160))
        XCTAssertEqual(CaptureFormatPolicy.verifyFormat(width: 1280, height: 720, supports30fps: true), .formatNot1080p(width: 1280, height: 720))
        XCTAssertEqual(CaptureFormatPolicy.verifyFormat(width: 1920, height: 1080, supports30fps: false), .formatLacks30fps)
    }

    // MARK: SDR

    func testSDRColorSpaceSelectionRequiresSRGB() throws {
        XCTAssertEqual(try CaptureFormatPolicy.sdrColorSpace(supported: [.sRGB, .p3D65, .hlgBT2020]).get(), .sRGB)
        XCTAssertEqual(try CaptureFormatPolicy.sdrColorSpace(supported: [.hlgBT2020, .sRGB]).get(), .sRGB)
        for supported in [[CaptureColorSpace.hlgBT2020], [.p3D65], [.appleLog, .hlgBT2020], [], [.unknown]] {
            switch CaptureFormatPolicy.sdrColorSpace(supported: supported) {
            case .success(let space): XCTFail("must not select \(space) from \(supported)")
            case .failure(let rejection): XCTAssertEqual(rejection, .sdrColorSpaceUnsupported(supported: supported))
            }
        }
        XCTAssertTrue(CaptureColorSpace.sRGB.isSDR); XCTAssertTrue(CaptureColorSpace.p3D65.isSDR)
        XCTAssertFalse(CaptureColorSpace.hlgBT2020.isSDR); XCTAssertFalse(CaptureColorSpace.appleLog.isSDR); XCTAssertFalse(CaptureColorSpace.unknown.isSDR)
    }

    func testAppliedColorRequiresHDROffAutomaticHDROffAndSRGB() {
        XCTAssertNil(CaptureFormatPolicy.verifyAppliedColor(active: .sRGB, hdrEnabled: false, automaticHDR: false))
        XCTAssertEqual(CaptureFormatPolicy.verifyAppliedColor(active: .sRGB, hdrEnabled: false, automaticHDR: true), .automaticHDRStillEnabled)
        XCTAssertEqual(CaptureFormatPolicy.verifyAppliedColor(active: .sRGB, hdrEnabled: true, automaticHDR: false), .hdrStillEnabled)
        XCTAssertEqual(CaptureFormatPolicy.verifyAppliedColor(active: .hlgBT2020, hdrEnabled: false, automaticHDR: false), .colorSpaceNotApplied(active: .hlgBT2020))
        XCTAssertEqual(CaptureFormatPolicy.verifyAppliedColor(active: .p3D65, hdrEnabled: false, automaticHDR: false), .colorSpaceNotApplied(active: .p3D65))
        XCTAssertEqual(CaptureFormatPolicy.verifyAppliedColor(active: .unknown, hdrEnabled: false, automaticHDR: false), .colorSpaceNotApplied(active: .unknown))
    }

    func testColorSpaceRawValuesMatchAVCaptureColorSpace() {
        // Raw values mirror AVCaptureColorSpace so the worker's bridging is a plain rawValue mapping.
        XCTAssertEqual(CaptureColorSpace(rawValue: 0), .sRGB); XCTAssertEqual(CaptureColorSpace(rawValue: 1), .p3D65)
        XCTAssertEqual(CaptureColorSpace(rawValue: 2), .hlgBT2020); XCTAssertEqual(CaptureColorSpace(rawValue: 3), .appleLog)
        XCTAssertEqual(CaptureColorSpace(rawValue: 4), .appleLog2); XCTAssertNil(CaptureColorSpace(rawValue: 9))
    }

    // MARK: Verified contract gate

    func testVerificationSatisfiesContractOnlyWhenEveryRequirementHolds() {
        let good = CaptureFormatVerification(videoCodec: "avc1", colorSpace: .sRGB, hdrEnabled: false, automaticHDR: false, width: 1920, height: 1080, frameRate: 30, audioAttached: true)
        XCTAssertTrue(good.satisfiesContract)
        var v = good; v.videoCodec = "hvc1"; XCTAssertFalse(v.satisfiesContract, "HEVC never satisfies the contract")
        v = good; v.colorSpace = .hlgBT2020; XCTAssertFalse(v.satisfiesContract)
        v = good; v.hdrEnabled = true; XCTAssertFalse(v.satisfiesContract)
        v = good; v.automaticHDR = true; XCTAssertFalse(v.satisfiesContract)
        v = good; v.width = 3840; v.height = 2160; XCTAssertFalse(v.satisfiesContract)
        v = good; v.frameRate = 60; XCTAssertFalse(v.satisfiesContract)
        v = good; v.audioAttached = false; XCTAssertTrue(v.satisfiesContract, "audio is optional (microphone may be denied)")
    }

    @MainActor
    func testFakeCaptureServiceExposesAVerifiedContractLikeAPreparedSession() async {
        let service = FakeCameraCaptureService()
        XCTAssertNil(service.state.captureFormat)
        await service.prepare()
        XCTAssertEqual(service.state.captureFormat?.satisfiesContract, true)
        XCTAssertEqual(service.state.captureFormat?.videoCodec, "avc1")
    }
}
