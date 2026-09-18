import Foundation

// ADR-046 §2 — canonical direct-camera capture contract. Pure value types and decisions so the
// codec / SDR rules are unit-testable without hardware; `CameraSessionWorker` feeds it the actual
// AVFoundation capabilities and applies the results.

/// Capture color spaces as `AVCaptureColorSpace` raw values, kept framework-free for tests.
enum CaptureColorSpace: Int, Equatable, Sendable {
    case sRGB = 0
    case p3D65 = 1
    case hlgBT2020 = 2
    case appleLog = 3
    case appleLog2 = 4
    case unknown = -1

    /// SDR in the ADR-046 sense: not an HDR transfer (HLG) and not a log curve.
    var isSDR: Bool { self == .sRGB || self == .p3D65 }
}

enum CaptureFormatPolicy {
    /// `AVVideoCodecType.h264.rawValue`.
    static let requiredVideoCodec = "avc1"
    /// `AVVideoCodecKey`.
    static let videoCodecSettingsKey = "AVVideoCodecKey"
    static let requiredWidth: Int32 = 1920
    static let requiredHeight: Int32 = 1080
    static let requiredFrameRate = 30.0
    /// The only accepted capture color space: SDR with Rec.709-compatible gamut. P3 is SDR too but
    /// would tag capture as wide-gamut, which the approved working-media contract does not want.
    static let requiredColorSpace: CaptureColorSpace = .sRGB

    enum Rejection: Error, Equatable, Sendable {
        case h264Unavailable(available: [String])
        case codecKeyNotSettable
        case codecNotApplied(applied: String?)
        case formatNot1080p(width: Int32, height: Int32)
        case formatLacks30fps
        case sdrColorSpaceUnsupported(supported: [CaptureColorSpace])
        case colorSpaceNotApplied(active: CaptureColorSpace)
        case hdrStillEnabled
        case automaticHDRStillEnabled
        case missingVideoConnection
    }

    /// Output settings to apply to the movie output's video connection. Never falls back to the
    /// list's first / default codec: H.264 must be explicitly available.
    static func videoOutputSettings(availableCodecs: [String], supportedKeys: [String]) -> Result<[String: String], Rejection> {
        guard availableCodecs.contains(requiredVideoCodec) else { return .failure(.h264Unavailable(available: availableCodecs)) }
        guard supportedKeys.contains(videoCodecSettingsKey) else { return .failure(.codecKeyNotSettable) }
        return .success([videoCodecSettingsKey: requiredVideoCodec])
    }

    /// The applied settings must report exactly the required codec.
    static func verifyAppliedCodec(_ applied: String?) -> Rejection? {
        applied == requiredVideoCodec ? nil : .codecNotApplied(applied: applied)
    }

    static func verifyFormat(width: Int32, height: Int32, supports30fps: Bool) -> Rejection? {
        guard width == requiredWidth, height == requiredHeight else { return .formatNot1080p(width: width, height: height) }
        guard supports30fps else { return .formatLacks30fps }
        return nil
    }

    /// The SDR color space to request, or a rejection when the active format cannot provide it.
    static func sdrColorSpace(supported: [CaptureColorSpace]) -> Result<CaptureColorSpace, Rejection> {
        supported.contains(requiredColorSpace) ? .success(requiredColorSpace) : .failure(.sdrColorSpaceUnsupported(supported: supported))
    }

    static func verifyAppliedColor(active: CaptureColorSpace, hdrEnabled: Bool, automaticHDR: Bool) -> Rejection? {
        if automaticHDR { return .automaticHDRStillEnabled }
        if hdrEnabled { return .hdrStillEnabled }
        if active != requiredColorSpace { return .colorSpaceNotApplied(active: active) }
        return nil
    }
}

/// What the worker verified after configuration; published in `CameraSessionState` so recording
/// can refuse to start under an unverified contract and so device evidence is observable.
struct CaptureFormatVerification: Equatable, Sendable {
    var videoCodec: String
    var colorSpace: CaptureColorSpace
    var hdrEnabled: Bool
    var automaticHDR: Bool
    var width: Int32
    var height: Int32
    var frameRate: Double
    var audioAttached: Bool

    var satisfiesContract: Bool {
        CaptureFormatPolicy.verifyAppliedCodec(videoCodec) == nil
            && CaptureFormatPolicy.verifyAppliedColor(active: colorSpace, hdrEnabled: hdrEnabled, automaticHDR: automaticHDR) == nil
            && CaptureFormatPolicy.verifyFormat(width: width, height: height, supports30fps: frameRate == CaptureFormatPolicy.requiredFrameRate) == nil
    }
}

#if DEBUG
extension CaptureFormatVerification {
    /// The contract a real prepared session reports on a supported iPhone; used by the fake
    /// capture service so coordinator tests model production state.
    static let verifiedForTests = CaptureFormatVerification(
        videoCodec: CaptureFormatPolicy.requiredVideoCodec, colorSpace: .sRGB, hdrEnabled: false, automaticHDR: false,
        width: CaptureFormatPolicy.requiredWidth, height: CaptureFormatPolicy.requiredHeight,
        frameRate: CaptureFormatPolicy.requiredFrameRate, audioAttached: false)
}
#endif
