#if DEBUG
import AVFoundation
import CoreMedia
import Foundation

/// Everything the public SDK exposes about one file, for the diagnostic listing. Values are read
/// from the media itself (never the file name). Purely diagnostic — no production code uses this.
struct Phase6SpikeMediaInfo: Identifiable {
    let id = UUID()
    var url: URL
    var displayName: String
    var fileExtension: String
    var byteCount: Int64
    var container: Phase6SpikeContainer = .unknown
    var brands: String = ""

    var isReadable = false
    var isPlayable = false
    var isExportable = false
    var hasProtectedContent = false
    var duration: CMTime = .invalid

    var hasVideoTrack = false
    var videoCodec = "-"
    var profileDescription = "-"
    var profileIsHighBitDepth = false
    var bitsPerComponent: Int?
    var fullRangeVideo: Bool?
    var naturalSize: CGSize = .zero
    var preferredTransform: CGAffineTransform = .identity
    var presentationSize: CGSize = .zero
    var nominalFrameRate: Float = 0
    var minFrameDuration: CMTime = .invalid
    var estimatedDataRate: Float = 0
    var variableFrameRateNote = "-"
    var isVariableFrameRateSuspected = false
    var colorPrimaries: String?
    var transferFunction: String?
    var ycbcrMatrix: String?
    var hdrMetadataNotes: [String] = []

    var hasAudioTrack = false
    var audioCodec = "-"
    var audioSampleRate: Double = 0
    var audioChannels: Int = 0

    var loadError: String?
    var path: Phase6SpikePath = .preflightInvalid
    var pathReasons: [String] = []

    var durationText: String {
        guard duration.isNumeric else { return "non-numeric (flags \(duration.flags.rawValue))" }
        return "\(duration.value)/\(duration.timescale) = \(String(format: "%.6f", duration.seconds)) s"
    }
    /// ADR-043 Revision 1 wording: "portrait" or "non-portrait (landscape|square)".
    var presentationOrientation: String {
        switch Phase6SpikeOrientationEligibility.classify(presentationSize: presentationSize) {
        case .portrait: return "portrait"
        case .nonPortrait(let shape): return "non-portrait (\(shape.rawValue)) — unsupported (ADR-043)"
        }
    }
    var isMirrored: Bool { preferredTransform.a * preferredTransform.d - preferredTransform.b * preferredTransform.c < 0 }

    var classificationInput: Phase6SpikeClassificationInput {
        Phase6SpikeClassificationInput(
            duration: duration, isReadable: isReadable, isPlayable: isPlayable, hasProtectedContent: hasProtectedContent,
            hasVideoTrack: hasVideoTrack, container: container, videoCodec: videoCodec, bitsPerComponent: bitsPerComponent,
            profileIsHighBitDepth: profileIsHighBitDepth, presentationSize: presentationSize, nominalFrameRate: nominalFrameRate,
            transferFunction: transferFunction, colorPrimaries: colorPrimaries, ycbcrMatrix: ycbcrMatrix,
            hasDolbyVisionConfiguration: hasDolbyVisionConfiguration, isVariableFrameRateSuspected: isVariableFrameRateSuspected)
    }

    var hasDolbyVisionConfiguration: Bool { hdrMetadataNotes.contains { $0.contains("Dolby Vision config atom") } }

    var sdrOutputFacts: Phase6SpikeSDROutputContract.Facts {
        Phase6SpikeSDROutputContract.Facts(container: container, videoCodec: videoCodec, profileDescription: profileDescription, profileIsHighBitDepth: profileIsHighBitDepth,
            bitsPerComponent: bitsPerComponent, colorPrimaries: colorPrimaries, transferFunction: transferFunction, ycbcrMatrix: ycbcrMatrix, hdrMetadataNotes: hdrMetadataNotes,
            preferredTransform: preferredTransform, presentationSize: presentationSize, nominalFrameRate: nominalFrameRate, isReadable: isReadable, isPlayable: isPlayable, hasVideoTrack: hasVideoTrack)
    }
    /// Empty when this file satisfies the diagnostic SDR output contract.
    var sdrOutputProblems: [String] { Phase6SpikeSDROutputContract.problems(sdrOutputFacts) }

    /// Multi-line diagnostic dump shown in the UI.
    var report: [(String, String)] {
        var rows: [(String, String)] = [
            ("파일", "\(displayName) (.\(fileExtension))"),
            ("실제 컨테이너", "\(container.rawValue) [\(brands)]"),
            ("크기", Phase6SpikeFormat.bytes(byteCount)),
            ("readable/playable/exportable/protected", "\(isReadable)/\(isPlayable)/\(isExportable)/\(hasProtectedContent)"),
            ("duration (CMTime)", durationText),
            ("video codec", "\(videoCodec)  profile: \(profileDescription)  bpc: \(bitsPerComponent.map(String.init) ?? "n/a")  fullRange: \(fullRangeVideo.map(String.init) ?? "n/a")"),
            ("naturalSize", "\(Int(naturalSize.width))×\(Int(naturalSize.height))"),
            ("preferredTransform", String(format: "[a %.2f b %.2f c %.2f d %.2f tx %.0f ty %.0f]%@", preferredTransform.a, preferredTransform.b, preferredTransform.c, preferredTransform.d, preferredTransform.tx, preferredTransform.ty, isMirrored ? " mirrored" : "")),
            ("presentation", "\(Int(presentationSize.width))×\(Int(presentationSize.height)) \(presentationOrientation)"),
            ("nominal fps / minFrameDuration", "\(nominalFrameRate)  /  \(minFrameDuration.isNumeric ? "\(minFrameDuration.value)/\(minFrameDuration.timescale)" : "n/a")"),
            ("VFR", variableFrameRateNote),
            ("data rate", String(format: "%.2f Mbps", estimatedDataRate / 1_000_000)),
            ("color primaries / transfer / matrix", "\(colorPrimaries ?? "untagged") / \(transferFunction ?? "untagged") / \(ycbcrMatrix ?? "untagged")"),
            ("HDR/DV metadata", hdrMetadataNotes.isEmpty ? "none exposed" : hdrMetadataNotes.joined(separator: "; ")),
            ("audio", hasAudioTrack ? "\(audioCodec) \(Int(audioSampleRate)) Hz \(audioChannels) ch" : "none"),
            ("경로 판정", path.rawValue),
        ]
        if !pathReasons.isEmpty { rows.append(("판정 근거", pathReasons.joined(separator: ", "))) }
        if let loadError { rows.append(("load error", loadError)) }
        rows.append(("SDR output contract", sdrOutputProblems.isEmpty ? "VALID SDR (QuickTime · avc1 · 8-bit · 709/709/709 · no HDR/DV signaling · identity · portrait · ≤30 fps)" : "NOT a valid SDR output: " + sdrOutputProblems.joined(separator: " | ")))
        return rows
    }
}

enum Phase6SpikeFormat {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file) + " (\(value) B)"
    }
    static func fourCC(_ code: FourCharCode) -> String {
        String(bytes: withUnsafeBytes(of: code.bigEndian, Array.init), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
    }
}

/// Reads metadata through `AVURLAsset` property loading only (no decode). Runs off the main actor.
enum Phase6SpikeInspector {
    static func inspect(_ url: URL) async -> Phase6SpikeMediaInfo {
        var info = Phase6SpikeMediaInfo(url: url, displayName: url.lastPathComponent, fileExtension: url.pathExtension, byteCount: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        if let handle = try? FileHandle(forReadingFrom: url) {
            let header = (try? handle.read(upToCount: 64)) ?? Data()
            try? handle.close()
            let sniffed = Phase6SpikeContainer.sniff(headerBytes: header)
            info.container = sniffed.container; info.brands = sniffed.brands
        }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        do {
            let (duration, tracks, readable, playable, exportable, protected) = try await asset.load(.duration, .tracks, .isReadable, .isPlayable, .isExportable, .hasProtectedContent)
            info.duration = duration; info.isReadable = readable; info.isPlayable = playable; info.isExportable = exportable; info.hasProtectedContent = protected
            if let video = tracks.first(where: { $0.mediaType == .video }) {
                info.hasVideoTrack = true
                let (natural, transform, fps, minFD, formats, rate) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .minFrameDuration, .formatDescriptions, .estimatedDataRate)
                info.naturalSize = natural; info.preferredTransform = transform; info.nominalFrameRate = fps; info.minFrameDuration = minFD; info.estimatedDataRate = rate
                info.presentationSize = Phase6SpikeOrientationEligibility.presentationSize(naturalSize: natural, preferredTransform: transform)
                if let fd = formats.first { apply(formatDescription: fd, to: &info) }
                if minFD.isNumeric, minFD.seconds > 0, fps > 0 {
                    let fromMin = 1 / minFD.seconds
                    let delta = abs(fromMin - Double(fps))
                    info.isVariableFrameRateSuspected = delta > 1.0
                    info.variableFrameRateNote = String(format: "nominal %.3f vs 1/minFrameDuration %.3f (Δ %.3f) — diagnostic only, NOT a normalization trigger; minFrameDuration is the shortest frame, true VFR is only known at decode", fps, fromMin, delta)
                } else {
                    info.variableFrameRateNote = "minFrameDuration unavailable — cannot assess"
                }
            }
            if let audio = tracks.first(where: { $0.mediaType == .audio }) {
                info.hasAudioTrack = true
                let formats = try await audio.load(.formatDescriptions)
                if let fd = formats.first {
                    info.audioCodec = Phase6SpikeFormat.fourCC(CMFormatDescriptionGetMediaSubType(fd))
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
                        info.audioSampleRate = asbd.mSampleRate; info.audioChannels = Int(asbd.mChannelsPerFrame)
                    }
                }
            }
        } catch {
            info.loadError = "\((error as NSError).domain)/\((error as NSError).code): \(error.localizedDescription)"
        }
        let verdict = Phase6SpikePathClassifier.classify(info.classificationInput)
        info.path = verdict.path; info.pathReasons = verdict.reasons
        return info
    }

    static func apply(formatDescription fd: CMFormatDescription, to info: inout Phase6SpikeMediaInfo) {
        info.videoCodec = Phase6SpikeFormat.fourCC(CMFormatDescriptionGetMediaSubType(fd))
        func ext(_ key: CFString) -> String? { CMFormatDescriptionGetExtension(fd, extensionKey: key) as? String }
        info.colorPrimaries = ext(kCMFormatDescriptionExtension_ColorPrimaries)
        info.transferFunction = ext(kCMFormatDescriptionExtension_TransferFunction)
        info.ycbcrMatrix = ext(kCMFormatDescriptionExtension_YCbCrMatrix)
        info.bitsPerComponent = (CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_BitsPerComponent) as? NSNumber)?.intValue
        info.fullRangeVideo = (CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_FullRangeVideo) as? NSNumber)?.boolValue
        if CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_MasteringDisplayColorVolume) != nil { info.hdrMetadataNotes.append("MasteringDisplayColorVolume") }
        if CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_ContentLightLevelInfo) != nil { info.hdrMetadataNotes.append("ContentLightLevelInfo") }
        if CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_AmbientViewingEnvironment) != nil { info.hdrMetadataNotes.append("AmbientViewingEnvironment") }
        // Sample-description extension atoms: avcC / hvcC carry profile; dvcC / dvvC / dvwC signal Dolby Vision configuration.
        if let atoms = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any] {
            let keys = atoms.keys.sorted()
            for dv in ["dvcC", "dvvC", "dvwC"] where atoms[dv] != nil { info.hdrMetadataNotes.append("Dolby Vision config atom \(dv) present") }
            if let avcC = atoms["avcC"] as? Data, avcC.count >= 4 {
                let profile = avcC[avcC.startIndex + 1], level = avcC[avcC.startIndex + 3]
                let name: String = [66: "Baseline", 77: "Main", 88: "Extended", 100: "High", 110: "High 10", 122: "High 4:2:2", 244: "High 4:4:4"][Int(profile)] ?? "profile_idc \(profile)"
                info.profileDescription = "H.264 \(name) L\(Double(level) / 10)"
                info.profileIsHighBitDepth = profile == 110 || profile == 122 || profile == 244
            } else if let hvcC = atoms["hvcC"] as? Data, hvcC.count >= 2 {
                let profile = Int(hvcC[hvcC.startIndex + 1] & 0x1F)
                let name = [1: "Main", 2: "Main 10", 3: "Main Still", 4: "RExt"][profile] ?? "profile_idc \(profile)"
                info.profileDescription = "HEVC \(name)"
                info.profileIsHighBitDepth = profile == 2
            } else {
                info.profileDescription = "atoms: \(keys.joined(separator: ","))"
            }
        }
    }
}
#endif
