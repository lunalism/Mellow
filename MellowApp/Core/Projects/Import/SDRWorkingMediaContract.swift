import Foundation

// Phase 6 Step 4A — the canonical SDR working-media output contract (ADR-045 §3 / §6 / §7,
// ADR-047 Decision 1, ADR-048). Pure values only: nothing here reads, decodes, encodes or writes
// media, and no writer setting that the accepted documents leave open (video bitrate, keyframe
// interval, H.264 level, pixel-buffer format) is modelled. The contract applies to normalization
// output only; a verbatim fast-path copy is never measured against it (ADR-045 §6), and it is not
// the export contract (Phase 9). Output raster sizing is `WorkingMediaRasterPolicy`.

enum WorkingMediaVideoCodec: Hashable, Sendable { case h264 }

/// H.264 High (8-bit 4:2:0) — explicitly not High 10 / 4:2:2 / 4:4:4 (ADR-045 §3).
enum WorkingMediaVideoProfile: Hashable, Sendable { case high }

/// Video (limited) range, never full range (ADR-045 §3).
enum WorkingMediaSignalRange: Hashable, Sendable { case video }

/// ADR-048 transcoded working audio.
enum WorkingMediaAudioCodec: Hashable, Sendable { case aacLC }

enum WorkingMediaAudioChannelLayout: Hashable, Sendable { case mono, stereo }

/// Immutable AAC-LC settings for one transcoded source (ADR-048 Decision 1). Built only by the
/// contract, so no caller can pick another codec, rate, layout or bitrate.
struct WorkingMediaAudioTranscodeSettings: Hashable, Sendable {
    let codec: WorkingMediaAudioCodec
    let sampleRate: Int
    let channelLayout: WorkingMediaAudioChannelLayout
    /// True when a source with more than two channels is explicitly downmixed to stereo.
    let downmixesToStereo: Bool
    let bitRate: Int

    fileprivate init(codec: WorkingMediaAudioCodec, sampleRate: Int, channelLayout: WorkingMediaAudioChannelLayout, downmixesToStereo: Bool, bitRate: Int) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channelLayout = channelLayout
        self.downmixesToStereo = downmixesToStereo
        self.bitRate = bitRate
    }
}

/// The one canonical output contract. Not constructible by callers, so no field can be overridden.
struct SDRWorkingMediaContract: Hashable, Sendable {
    let container: ImportContainer
    let videoCodec: WorkingMediaVideoCodec
    let videoProfile: WorkingMediaVideoProfile
    let bitsPerComponent: Int
    let colorPrimaries: ImportColorPrimaries
    let transferFunction: ImportTransferFunction
    let ycbcrMatrix: ImportYCbCrMatrix
    let signalRange: WorkingMediaSignalRange
    /// The source presentation transform is baked into pixels; the output track carries identity.
    let outputTransform: ImportAffineTransform
    /// Frame-rate ceiling: output frames are never shorter than 1/30 s.
    let minimumFrameDuration: MediaTime
    /// Portrait 1080p-class envelope (short edge ≤ 1080, long edge ≤ 1920).
    let rasterEnvelope: WorkingMediaRaster
    /// ADR-048: source audio with exactly this format ID passes through without re-encoding.
    let passthroughAudioFormatID: String
    let transcodedAudioCodec: WorkingMediaAudioCodec
    let transcodedAudioSampleRate: Int
    let monoAudioBitRate: Int
    let stereoAudioBitRate: Int
    /// ADR-045 §7: `source <= output <= source + 1/30 s`. Output validation only — source
    /// eligibility (ADR-042) has no tolerance.
    let outputDurationTolerance: MediaTime

    /// Timescale for converting a nominal frame rate into a frame duration. 120 000 represents
    /// every common rate exactly: 1/24, 1/25, 1/30, 1/48, 1/50, 1/60, 1/120 and the NTSC
    /// 1001/24000, 1001/30000, 1001/60000.
    static let nominalFrameDurationTimescale: Int32 = 120_000

    static let canonical = SDRWorkingMediaContract()

    private init() {
        container = .quickTime
        videoCodec = .h264
        videoProfile = .high
        bitsPerComponent = 8
        colorPrimaries = .rec709
        transferFunction = .rec709
        ycbcrMatrix = .rec709
        signalRange = .video
        outputTransform = .identity
        minimumFrameDuration = try! MediaTime(value: 1, timescale: 30)
        rasterEnvelope = WorkingMediaRasterPolicy.envelope
        passthroughAudioFormatID = ImportPreflightPolicy.passthroughAudioFormatID
        transcodedAudioCodec = .aacLC
        transcodedAudioSampleRate = 48_000
        monoAudioBitRate = 96_000
        stereoAudioBitRate = 128_000
        outputDurationTolerance = try! MediaTime(value: 1, timescale: 30)
    }

    /// ADR-048 Decision 3 (clarifying ADR-045 §3), in order:
    /// 1. a positive `minimumFrameDuration`, reduced to lowest terms → `max(minimumFrameDuration, 1/30)`;
    /// 2. else a finite positive nominal rate → `max(1 / nominalFrameRate, 1/30)`;
    /// 3. else `1/30`.
    /// Never faster than 30 fps and never upsampled. Duration and sample counts are not consulted.
    /// Every result is in lowest terms (the cap is the canonical `1/30`), because `MediaTime`
    /// equality and hashing compare the stored fraction: 2/48 and nominal 24 fps both give 1/24.
    func outputFrameDuration(sourceMinimumFrameDuration: MediaTime?, nominalFrameRate: Float) -> MediaTime {
        if let minimum = sourceMinimumFrameDuration, minimum.value > 0,
           let canonical = Self.lowestTerms(value: minimum.value, timescale: Int64(minimum.timescale)) {
            return max(canonical, minimumFrameDuration)
        }
        if let nominal = Self.nominalFrameDuration(nominalFrameRate) {
            return max(nominal, minimumFrameDuration)
        }
        return minimumFrameDuration
    }

    /// `1 / nominalFrameRate` as `round(120000 / rate)` ticks of 1/120000 s (ties away from zero),
    /// reduced to lowest terms, e.g. 29.97 → 4004/120000 → 1001/30000. Reduction matters because
    /// `MediaTime` equality and hashing compare the stored fraction, not the instant. `nil` when the
    /// rate is not finite and positive or the tick count cannot be represented.
    static func nominalFrameDuration(_ nominalFrameRate: Float) -> MediaTime? {
        let rate = Double(nominalFrameRate)
        guard rate.isFinite, rate > 0 else { return nil }
        let ticks = (Double(nominalFrameDurationTimescale) / rate).rounded(.toNearestOrAwayFromZero)
        guard ticks.isFinite, ticks < Double(Int64.max) else { return nil }
        return lowestTerms(value: Int64(ticks), timescale: Int64(nominalFrameDurationTimescale))
    }

    /// `value / timescale` reduced by Euclid on non-negative operands: remainders only shrink, so it
    /// terminates without overflow, and the divisor is ≥ 1 because the timescale is positive. The
    /// reduced timescale never exceeds the input, so it fits `Int32` whenever the input did.
    private static func lowestTerms(value: Int64, timescale: Int64) -> MediaTime? {
        guard value >= 0, timescale > 0, timescale <= Int64(Int32.max) else { return nil }
        var a = value, b = timescale
        while b != 0 { (a, b) = (b, a % b) }
        return try? MediaTime(value: value / a, timescale: Int32(timescale / a))
    }

    /// ADR-048 transcode settings: mono source → mono 96 kbps; two or more channels → stereo
    /// 128 kbps, with an explicit downmix above two. `nil` for a non-positive channel count, which
    /// preflight already rejects.
    func audioTranscodeSettings(sourceChannelCount: Int) -> WorkingMediaAudioTranscodeSettings? {
        guard sourceChannelCount > 0 else { return nil }
        let mono = sourceChannelCount == 1
        return WorkingMediaAudioTranscodeSettings(
            codec: transcodedAudioCodec, sampleRate: transcodedAudioSampleRate,
            channelLayout: mono ? .mono : .stereo, downmixesToStereo: sourceChannelCount > 2,
            bitRate: mono ? monoAudioBitRate : stereoAudioBitRate)
    }

    /// ADR-045 §7 output-duration window. It does not redefine the ADR-042 product bounds.
    func acceptedOutputDuration(forSource duration: MediaTime) -> ClosedRange<MediaTime> {
        duration...(duration + outputDurationTolerance)
    }
}
