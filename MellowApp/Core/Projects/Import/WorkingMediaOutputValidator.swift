import Foundation

// Phase 6 Step 4B — validation of a normalized output against its plan (ADR-045 §3 / §7, ADR-047,
// ADR-048). Pure: it judges inspected facts and evidence, never media. The source-eligibility
// classifier is not reused as-is because an output answers a different question: it must *be* the
// canonical working media, not merely be acceptable input.

/// Output facts the shared inspector does not carry: the H.264 profile byte, the actual video
/// presentation timestamps (ascending), the track census and the AAC decoder configuration.
struct WorkingMediaOutputEvidence: Hashable, Sendable {
    enum PresentationTimes: Hashable, Sendable {
        case times([MediaTime])
        /// No video track, unreadable samples, or timing that could not be fully read for any
        /// sample (see `WorkingMediaOutputValidator.presentationTimes(from:)`).
        case unavailable
    }

    struct TrackCounts: Hashable, Sendable {
        let video: Int, audio: Int, other: Int
    }

    /// `AVCProfileIndication` from `avcC`; nil when the record is absent or malformed.
    let avcProfileIndication: UInt8?
    let videoPresentationTimes: PresentationTimes
    let trackCounts: TrackCounts
    /// The output audio's MPEG-4 decoder configuration (`esds`), when it has an AAC track.
    let aacDecoderConfiguration: WorkingMediaAACDecoderConfiguration?
}

/// What an AAC track's `esds` declares: the AudioSpecificConfig object type (2 = AAC-LC) and the
/// encoder's declared bit rates. The bytes actually spent are content-dependent (the encoder spends
/// far less on a pure tone or silence), so the declared rate — what the encoder was configured to
/// target — is the observable bit-rate contract.
struct WorkingMediaAACDecoderConfiguration: Hashable, Sendable {
    let audioObjectType: Int
    let averageBitRate: Int
    let maximumBitRate: Int
}

/// One compressed video sample buffer's timing as read back from the output.
struct WorkingMediaSampleTimingObservation: Hashable, Sendable {
    /// `CMSampleBufferGetNumSamples`: 0 for a marker buffer, which carries no frame.
    let sampleCount: Int
    /// One entry per timing record; an entry is nil when that presentation time is not numeric.
    /// nil when the timing records could not be read at all.
    let presentationTimes: [MediaTime?]?
}

/// One way a normalized output fails its plan. Diagnostic only; no user copy.
enum WorkingMediaOutputViolation: Hashable, Sendable {
    case emptyFile
    case notQuickTime(ImportContainer)
    case notH264(ImportVideoCodec)
    /// Profile other than H.264 High (`profile_idc` 100), or no reliable profile evidence.
    case notHighProfile(profileIndication: UInt8?)
    /// Unreadable, unplayable, unexportable or without a video track.
    case unusable
    case protectedContent
    case rasterMismatch(expected: WorkingMediaRaster, actualWidth: Int, actualHeight: Int)
    case transformNotIdentity
    case colorNotRec709
    case fullRangeVideo
    /// Any HDR / high-bit-depth / Dolby Vision signal, or AVE / MDCV / CLLI metadata.
    case hdrSignalling
    /// The planned frame duration is faster than the 1/30 s ceiling (ADR-048 Decision 3).
    case frameDurationFasterThanCeiling(MediaTime)
    /// No video sample or unusable timestamps: the cadence cannot be verified.
    case cadenceUnverifiable
    /// Two samples share a presentation time.
    case timestampsNotIncreasing
    /// The interval after sample `index` is not exactly the planned frame duration.
    case cadenceMismatch(index: Int, interval: MediaTime)
    /// The first frame is not presented at time zero (the session starts at zero).
    case cadenceDoesNotStartAtZero(MediaTime)
    /// The last frame is not the last grid target before the session end: a final target is
    /// missing (`last + d < E`) or a frame sits at or after the end (ADR-048 Revisions 1 and 2).
    case gridEndMismatch(lastPresentation: MediaTime)
    /// Not exactly one video track, the planned number of audio tracks (0 or 1) and nothing else.
    case unexpectedTracks(video: Int, audio: Int, other: Int)
    /// A transcoded track that does not declare AAC-LC at the planned bit rate (ADR-048).
    case audioEncodingMismatch(WorkingMediaAACDecoderConfiguration?)
    case invalidDuration
    /// Outside `source <= output <= source + 1/30 s` (ADR-045 §7).
    case durationOutsideWindow(MediaTime)
    case audioMismatch
}

enum WorkingMediaOutputValidator {
    /// `profile_idc` of H.264 High.
    static let highProfileIndication: UInt8 = 100

    /// Every violation, in a fixed order; an empty result means the output satisfies the plan.
    /// `sourceAudio` is the inspected source audio, needed to confirm a passthrough kept its format.
    static func violations(of output: ImportSourceFacts, evidence: WorkingMediaOutputEvidence, plan: WorkingMediaNormalizationPlan, sourceAudio: ImportAudioFacts?) -> [WorkingMediaOutputViolation] {
        let contract = plan.contract
        var found: [WorkingMediaOutputViolation] = []

        if output.byteCount <= 0 { found.append(.emptyFile) }
        if output.container != contract.container { found.append(.notQuickTime(output.container)) }
        if output.videoCodec != .h264(fourCC: "avc1") { found.append(.notH264(output.videoCodec)) }
        if evidence.avcProfileIndication != highProfileIndication { found.append(.notHighProfile(profileIndication: evidence.avcProfileIndication)) }
        if !(output.isReadable && output.isPlayable && output.isExportable && output.hasVideoTrack) { found.append(.unusable) }
        if output.hasProtectedContent { found.append(.protectedContent) }

        let expected = plan.raster.output
        if output.naturalWidth != expected.width || output.naturalHeight != expected.height {
            found.append(.rasterMismatch(expected: expected, actualWidth: output.naturalWidth, actualHeight: output.naturalHeight))
        }
        if output.preferredTransform != contract.outputTransform { found.append(.transformNotIdentity) }

        if output.colorPrimaries != contract.colorPrimaries || output.transferFunction != contract.transferFunction || output.ycbcrMatrix != contract.ycbcrMatrix {
            found.append(.colorNotRec709)
        }
        if output.fullRangeVideo == .yes { found.append(.fullRangeVideo) }
        if !ImportPreflightClassifier.hdrSignals(in: output).isEmpty || !output.ancillaryHDRMetadata.isEmpty {
            found.append(.hdrSignalling)
        }

        // ADR-048 Revision 2: the cadence is proven only by the exact presentation-time grid. An
        // average or metadata rate (`nominalFrameRate`, sample count / duration) can exceed 30
        // because the session ends at the exact source end, which shortens the last sample; it is
        // never a reason to reject. The 30 fps ceiling is the planned frame duration itself.
        if plan.outputFrameDuration < contract.minimumFrameDuration {
            found.append(.frameDurationFasterThanCeiling(plan.outputFrameDuration))
        }
        let cadence = cadenceViolations(evidence.videoPresentationTimes, frameDuration: plan.outputFrameDuration)
        found.append(contentsOf: cadence)
        if cadence.isEmpty {
            found.append(contentsOf: gridEndViolations(evidence.videoPresentationTimes, frameDuration: plan.outputFrameDuration, sessionEnd: plan.sourceDuration))
        }

        switch output.duration {
        case .invalid:
            found.append(.invalidDuration)
        case .exact(let duration):
            if !plan.acceptedOutputDuration.contains(duration) { found.append(.durationOutsideWindow(duration)) }
        }

        if !audioMatches(output, plan.audio, sourceAudio: sourceAudio) { found.append(.audioMismatch) }
        if case .transcode(let settings) = plan.audio {
            let declared = evidence.aacDecoderConfiguration
            if declared?.audioObjectType != aacLowComplexityObjectType || declared?.averageBitRate != settings.bitRate {
                found.append(.audioEncodingMismatch(declared))
            }
        }
        let counts = evidence.trackCounts
        if counts.video != 1 || counts.audio != (plan.audio == .none ? 0 : 1) || counts.other != 0 {
            found.append(.unexpectedTracks(video: counts.video, audio: counts.audio, other: counts.other))
        }
        return found
    }

    /// Presentation times of every real frame, failing closed. Marker buffers (no samples) carry
    /// timing entries of their own (e.g. at 0 and at the track end) and are the only buffers
    /// skipped. Any other buffer must yield exactly one numeric presentation time per sample;
    /// unreadable timing, a missing or extra entry, or a non-numeric time makes the whole evidence
    /// `.unavailable` — never a validation over the surviving subset.
    static func presentationTimes(from observations: [WorkingMediaSampleTimingObservation]) -> WorkingMediaOutputEvidence.PresentationTimes {
        var times: [MediaTime] = []
        for observation in observations where observation.sampleCount != 0 {
            guard observation.sampleCount > 0, let entries = observation.presentationTimes, entries.count == observation.sampleCount else {
                return .unavailable
            }
            for entry in entries {
                guard let time = entry else { return .unavailable }
                times.append(time)
            }
        }
        return .times(times.sorted())
    }

    /// Fixed-cadence output: every interval between consecutive presentation times equals the
    /// planned frame duration exactly (rational comparison, timescale-independent). The last
    /// sample's own duration is not an interval, so the truncation made by ending the session at
    /// the source duration is the only shortening it can have. No tolerance. A single sample at
    /// zero has no interval to check; whether it is the whole grid (`0 < E <= d`) is decided by
    /// `gridEndViolations` (ADR-048 Revisions 1 and 2).
    static func cadenceViolations(_ times: WorkingMediaOutputEvidence.PresentationTimes, frameDuration: MediaTime) -> [WorkingMediaOutputViolation] {
        guard case .times(let sorted) = times, !sorted.isEmpty else { return [.cadenceUnverifiable] }
        // Instants, not structure: 0/30000 is zero.
        if sorted[0] < .zero || .zero < sorted[0] { return [.cadenceDoesNotStartAtZero(sorted[0])] }
        for index in 0..<(sorted.count - 1) {
            let current = sorted[index], next = sorted[index + 1]
            guard current < next else { return [.timestampsNotIncreasing] }
            let interval = next + negated(current)
            if interval < frameDuration || frameDuration < interval { return [.cadenceMismatch(index: index, interval: interval)] }
        }
        return []
    }

    /// The grid ends at the last target before the session end `E`: the last presentation time is
    /// below `E` and the next target (`last + d`) is not. Only the last sample may be shorter than
    /// `d` (it ends at `E`); a missing final target or a frame at or after `E` is rejected.
    static func gridEndViolations(_ times: WorkingMediaOutputEvidence.PresentationTimes, frameDuration: MediaTime, sessionEnd: MediaTime) -> [WorkingMediaOutputViolation] {
        guard case .times(let sorted) = times, let last = sorted.last else { return [.cadenceUnverifiable] }
        let next = last + frameDuration
        if !(last < sessionEnd) || next < sessionEnd { return [.gridEndMismatch(lastPresentation: last)] }
        return []
    }

    private static func negated(_ time: MediaTime) -> MediaTime {
        (try? MediaTime(value: -time.value, timescale: time.timescale)) ?? time
    }

    /// MPEG-4 Audio object type of AAC-LC.
    static let aacLowComplexityObjectType = 2

    /// Parses an AAC magic cookie (`esds` contents: an ES_Descriptor, or a bare
    /// DecoderConfigDescriptor) per ISO/IEC 14496-1 §7.2.6: DecoderConfigDescriptor (tag 4) gives
    /// maxBitrate / avgBitrate, its DecoderSpecificInfo (tag 5) starts with the AudioSpecificConfig
    /// whose first five bits are the audio object type (31 escapes to 32 + six more bits). Nil for
    /// anything truncated or malformed.
    static func aacDecoderConfiguration(fromMagicCookie bytes: [UInt8]) -> WorkingMediaAACDecoderConfiguration? {
        func descriptor(at index: Int) -> (tag: UInt8, body: Range<Int>)? {
            guard index < bytes.count else { return nil }
            var cursor = index + 1, length = 0
            for _ in 0..<4 {
                guard cursor < bytes.count else { return nil }
                let byte = bytes[cursor]; cursor += 1
                length = (length << 7) | Int(byte & 0x7F)
                if byte & 0x80 == 0 { break }
            }
            guard length >= 0, cursor + length <= bytes.count else { return nil }
            return (bytes[index], cursor..<(cursor + length))
        }
        guard var current = descriptor(at: 0) else { return nil }
        if current.tag == 0x03 {
            // ES_Descriptor: ES_ID (2), flags (1), optional dependsOn / URL / OCR fields.
            var cursor = current.body.lowerBound + 3
            guard cursor <= current.body.upperBound else { return nil }
            let flags = bytes[current.body.lowerBound + 2]
            if flags & 0x80 != 0 { cursor += 2 }
            if flags & 0x40 != 0 { guard cursor < bytes.count else { return nil }; cursor += 1 + Int(bytes[cursor]) }
            if flags & 0x20 != 0 { cursor += 2 }
            guard let next = descriptor(at: cursor), next.body.upperBound <= current.body.upperBound else { return nil }
            current = next
        }
        guard current.tag == 0x04, current.body.count >= 13 else { return nil }
        let base = current.body.lowerBound
        func word(_ offset: Int) -> Int { (0..<4).reduce(0) { ($0 << 8) | Int(bytes[base + offset + $1]) } }
        let maximum = word(5), average = word(9)
        guard let info = descriptor(at: base + 13), info.tag == 0x05, info.body.upperBound <= current.body.upperBound, info.body.count >= 1 else { return nil }
        var objectType = Int(bytes[info.body.lowerBound] >> 3)
        if objectType == 31 {
            guard info.body.count >= 2 else { return nil }
            objectType = 32 + Int(((bytes[info.body.lowerBound] & 0x07) << 3) | (bytes[info.body.lowerBound + 1] >> 5))
        }
        return WorkingMediaAACDecoderConfiguration(audioObjectType: objectType, averageBitRate: average, maximumBitRate: maximum)
    }

    /// `AVCProfileIndication` from an `avcC` record (ISO/IEC 14496-15): configurationVersion 1,
    /// then the profile byte. Absent, short (< 7 bytes) or wrong-version records give nil.
    static func avcProfileIndication(fromAvcC data: Data?) -> UInt8? {
        guard let data, data.count >= 7 else { return nil }
        let bytes = [UInt8](data.prefix(2))
        guard bytes[0] == 1 else { return nil }
        return bytes[1]
    }

    private static func audioMatches(_ output: ImportSourceFacts, _ strategy: WorkingMediaAudioStrategy, sourceAudio: ImportAudioFacts?) -> Bool {
        switch strategy {
        case .none:
            return !output.hasAudioTrack && output.audio == nil
        case .passthroughAAC:
            guard output.hasAudioTrack, let audio = output.audio, let source = sourceAudio else { return false }
            return audio.fourCC == ImportPreflightPolicy.passthroughAudioFormatID
                && audio.sampleRate == source.sampleRate && audio.channelCount == source.channelCount
        case .transcode(let settings):
            guard output.hasAudioTrack, let audio = output.audio else { return false }
            let channels = settings.channelLayout == .mono ? 1 : 2
            return audio.fourCC == ImportPreflightPolicy.passthroughAudioFormatID
                && audio.sampleRate == Double(settings.sampleRate) && audio.channelCount == channels
        }
    }
}
