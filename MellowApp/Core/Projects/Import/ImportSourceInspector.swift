import AVFoundation
import CoreMedia
import Foundation

/// Why a source could not be inspected well enough to build `ImportSourceFacts`. No user copy here.
/// An inspectable file with an unsupported container / codec is NOT an error — those are facts
/// the preflight classifier rejects in canonical order.
enum ImportInspectionError: Error, Equatable, Sendable {
    case notFileURL
    case sourceMissing
    case sourceNotRegularFile
    case sourceUnreadable
    case assetLoadFailed(domain: String, code: Int)
    case videoTrackLoadFailed(domain: String, code: Int)
}

/// Observation adapter: local file URL → `ImportSourceFacts`. Pure Step 1 policy stays in
/// `ImportPreflightClassifier`; this type never decides eligibility.
protocol ImportSourceInspecting: Sendable {
    func inspect(url: URL) async throws -> ImportSourceFacts
}

/// AVFoundation-backed inspector (ADR-045 §11, ADR-046 §4). Stateless and safe to call from
/// concurrent tasks. Reads metadata only — no decode of the sample stream, no mutation of the
/// source, no copy. The caller owns the URL: Photos-import sources reach this adapter only after
/// the selector has copied them into a Mellow-owned workspace, so no security-scoped access is
/// started here.
struct AVAssetImportSourceInspector: ImportSourceInspecting {
    init() {}

    func inspect(url: URL) async throws -> ImportSourceFacts {
        // Structured cancellation is checked at every point where a probe below deliberately
        // suppresses its own error: a cancelled inspection throws `CancellationError` and never
        // answers with facts.
        try Task.checkCancellation()
        guard url.isFileURL else { throw ImportInspectionError.notFileURL }
        let path = url.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { throw ImportInspectionError.sourceMissing }
        guard !isDirectory.boolValue,
              (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeRegular
        else { throw ImportInspectionError.sourceNotRegularFile }
        guard FileManager.default.isReadableFile(atPath: path) else { throw ImportInspectionError.sourceUnreadable }

        let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date
        let container = (try? ImportContainerInspector.classify(fileURL: url)) ?? .unknown

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        // `isReadable` is loaded on its own first. A file AVFoundation cannot parse either reports
        // `false` or fails this load (e.g. AVErrorFileFormatNotRecognized) — both are the same fact
        // for the classifier (`.unreadable` / `.invalidDuration`), not an inspection error: the
        // file-system checks above already proved the bytes are ours to read. Only a load that
        // fails *after* the asset proved readable is an error.
        let isReadable = (try? await asset.load(.isReadable)) ?? false
        try Task.checkCancellation()
        guard isReadable else {
            return ImportSourceFacts.unreadable(container: container, byteCount: byteCount, modificationDate: modificationDate)
        }
        let isPlayable: Bool, isExportable: Bool, isProtected: Bool
        let duration: CMTime
        let tracks: [AVAssetTrack]
        do {
            (isPlayable, isExportable, isProtected, duration, tracks) =
                try await asset.load(.isPlayable, .isExportable, .hasProtectedContent, .duration, .tracks)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch { throw Self.assetError(error) }

        var facts = ImportSourceFacts(
            duration: duration.isNumeric ? (try? MediaTime(value: duration.value, timescale: duration.timescale)).map { .exact($0) } ?? .invalid : .invalid,
            isReadable: isReadable, isPlayable: isPlayable, isExportable: isExportable, hasProtectedContent: isProtected,
            hasVideoTrack: false, hasAudioTrack: false,
            container: container, videoCodec: .unknown,
            naturalWidth: 0, naturalHeight: 0, preferredTransform: .identity,
            nominalFrameRate: 0, minimumFrameDuration: nil, bitsPerComponent: nil, highBitDepthProfile: .unknown, fullRangeVideo: .unknown,
            colorPrimaries: .unknown, transferFunction: .unknown, ycbcrMatrix: .unknown,
            hasDolbyVisionConfiguration: false, ancillaryHDRMetadata: [], aperture: .unreliable,
            audio: nil, byteCount: byteCount, modificationDate: modificationDate)

        // Canonical video track: the first video track in file order (the established production
        // rule from the Phase 5 inspector; iPhone / Photos sources carry exactly one).
        if let video = tracks.first(where: { $0.mediaType == .video }) {
            facts.hasVideoTrack = true
            do {
                let (descriptions, natural, transform, nominalRate, minFrameDuration) =
                    try await video.load(.formatDescriptions, .naturalSize, .preferredTransform, .nominalFrameRate, .minFrameDuration)
                facts.naturalWidth = Int(natural.width.rounded())
                facts.naturalHeight = Int(natural.height.rounded())
                facts.preferredTransform = ImportAffineTransform(transform)
                facts.nominalFrameRate = nominalRate
                if minFrameDuration.isNumeric, minFrameDuration.value > 0 {
                    facts.minimumFrameDuration = try? MediaTime(value: minFrameDuration.value, timescale: minFrameDuration.timescale)
                }
                Self.apply(videoFormatDescriptions: descriptions, to: &facts)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                let nsError = error as NSError
                throw ImportInspectionError.videoTrackLoadFailed(domain: nsError.domain, code: nsError.code)
            }
        }

        if let audio = tracks.first(where: { $0.mediaType == .audio }) {
            facts.hasAudioTrack = true
            let descriptions = try? await audio.load(.formatDescriptions)
            try Task.checkCancellation()
            if let description = descriptions?.first {
                facts.audio = Self.audioFacts(from: description)
            }
        }
        return facts
    }

    // MARK: Format-description mapping (pure over a CMFormatDescription; unit-tested directly)

    /// Fills codec, color, bit-depth, profile, HDR-signal and ancillary-metadata facts from one
    /// video format description. Missing evidence stays `unknown` — nothing defaults to Rec.709.
    static func apply(videoFormatDescription description: CMFormatDescription, to facts: inout ImportSourceFacts) {
        // Codec, bit depth, profile, colour signalling, Dolby Vision configuration and aperture: the same
        // per-description reading every further description gets (ADR-049 Revision 1).
        let pathFacts = descriptionFacts(from: description)
        facts.videoCodec = pathFacts.videoCodec
        facts.bitsPerComponent = pathFacts.bitsPerComponent
        facts.highBitDepthProfile = pathFacts.highBitDepthProfile
        facts.colorPrimaries = pathFacts.colorPrimaries
        facts.transferFunction = pathFacts.transferFunction
        facts.ycbcrMatrix = pathFacts.ycbcrMatrix
        facts.hasDolbyVisionConfiguration = pathFacts.hasDolbyVisionConfiguration
        facts.aperture = pathFacts.aperture
        if let fullRange = (CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_FullRangeVideo) as? NSNumber)?.boolValue {
            facts.fullRangeVideo = fullRange ? .yes : .no
        }

        var ancillary = Set<ImportAncillaryHDRMetadata>()
        if CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_MasteringDisplayColorVolume) != nil { ancillary.insert(.masteringDisplayColorVolume) }
        if CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_ContentLightLevelInfo) != nil { ancillary.insert(.contentLightLevel) }
        if CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_AmbientViewingEnvironment) != nil { ancillary.insert(.ambientViewingEnvironment) }
        facts.ancillaryHDRMetadata = ancillary

    }

    /// Encoded raster, clean aperture and pixel aspect ratio exactly as the format description
    /// states them (ADR-049 Decision 1). The clean-aperture extension gives the aperture size and
    /// the offset of its centre from the raster centre (positive = right / down), each as a number
    /// or an exact rational; it is resolved to a top-left rectangle without rounding. A missing
    /// extension is the whole raster / square pixels (Core Media's definition); a present but
    /// unparseable one is never guessed at — it makes the facts unreliable.
    static func apertureFacts(from description: CMFormatDescription) -> ImportApertureFacts {
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        let width = Int(dimensions.width), height = Int(dimensions.height)

        var aperture: ImportCleanAperture?
        if let raw = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_CleanAperture) {
            guard let values = raw as? [String: Any],
                  let apertureWidth = rationalValue(values, kCMFormatDescriptionKey_CleanApertureWidthRational, kCMFormatDescriptionKey_CleanApertureWidth),
                  let apertureHeight = rationalValue(values, kCMFormatDescriptionKey_CleanApertureHeightRational, kCMFormatDescriptionKey_CleanApertureHeight),
                  let horizontalOffset = rationalValue(values, kCMFormatDescriptionKey_CleanApertureHorizontalOffsetRational, kCMFormatDescriptionKey_CleanApertureHorizontalOffset),
                  let verticalOffset = rationalValue(values, kCMFormatDescriptionKey_CleanApertureVerticalOffsetRational, kCMFormatDescriptionKey_CleanApertureVerticalOffset)
            else { return .unreliable }
            aperture = ImportCleanAperture(
                x: (Double(width) - apertureWidth) / 2 + horizontalOffset,
                y: (Double(height) - apertureHeight) / 2 + verticalOffset,
                width: apertureWidth, height: apertureHeight)
        }

        var ratio: ImportPixelAspectRatio?
        if let raw = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_PixelAspectRatio) {
            guard let values = raw as? [String: Any],
                  let horizontal = integerValue(values[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String]),
                  let vertical = integerValue(values[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String])
            else { return .unreliable }
            ratio = ImportPixelAspectRatio(horizontalSpacing: horizontal, verticalSpacing: vertical)
        }
        return .classify(encodedWidth: width, encodedHeight: height, cleanAperture: aperture, pixelAspectRatio: ratio)
    }

    /// Every video format description of the selected track (ADR-049 Revision 1): the first fills
    /// the top-level facts as before; each further one is recorded as its own aperture / colour
    /// facts, so a path decision can require all of them to agree. No description, no facts.
    static func apply(videoFormatDescriptions descriptions: [CMFormatDescription], to facts: inout ImportSourceFacts) {
        guard let first = descriptions.first else { return }
        apply(videoFormatDescription: first, to: &facts)
        facts.additionalVideoDescriptions = descriptions.dropFirst().map(descriptionFacts(from:))
    }

    /// The description-local facts of one video format description — codec family from the media
    /// subtype, bit depth, profile, colour signalling, Dolby Vision configuration, aperture. The one
    /// parser for the first description (via `apply(videoFormatDescription:to:)`) and every further
    /// one, and the normalizer's runtime view of each current description.
    static func descriptionFacts(from description: CMFormatDescription) -> ImportVideoDescriptionFacts {
        func string(_ key: CFString) -> String? { CMFormatDescriptionGetExtension(description, extensionKey: key) as? String }
        // Sample-description extension atoms carry the codec configuration records: `avcC` / `hvcC`
        // give reliable profile evidence; `dvcC` / `dvvC` / `dvwC` signal Dolby Vision configuration.
        let atoms = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any] ?? [:]
        return ImportVideoDescriptionFacts(
            videoCodec: ImportVideoCodec.classify(fourCC: fourCC(CMFormatDescriptionGetMediaSubType(description))),
            bitsPerComponent: (CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_BitsPerComponent) as? NSNumber)?.intValue,
            highBitDepthProfile: highBitDepthProfile(atoms: atoms),
            aperture: apertureFacts(from: description),
            colorPrimaries: primaries(string(kCMFormatDescriptionExtension_ColorPrimaries)),
            transferFunction: transfer(string(kCMFormatDescriptionExtension_TransferFunction)),
            ycbcrMatrix: matrix(string(kCMFormatDescriptionExtension_YCbCrMatrix)),
            hasDolbyVisionConfiguration: ["dvcC", "dvvC", "dvwC"].contains { atoms[$0] != nil })
    }

    /// A clean-aperture value: the exact rational form (`[numerator, denominator]`) when present,
    /// else the plain number. Nil when neither is a usable finite value.
    private static func rationalValue(_ values: [String: Any], _ rationalKey: CFString, _ numberKey: CFString) -> Double? {
        if let pair = values[rationalKey as String] as? [NSNumber] {
            guard pair.count == 2, pair[1].int64Value != 0 else { return nil }
            let value = pair[0].doubleValue / pair[1].doubleValue
            return value.isFinite ? value : nil
        }
        guard let number = values[numberKey as String] as? NSNumber else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    private static func integerValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double == double.rounded(), abs(double) <= Double(Int32.max) else { return nil }
        return Int(double)
    }

    /// Audio facts exactly as the format description states them (ADR-048). A missing stream basic
    /// description yields a zero rate / channel count and an absent subtype four NULs; preflight
    /// rejects those rather than this adapter guessing.
    static func audioFacts(from description: CMFormatDescription) -> ImportAudioFacts {
        let subtype = fourCC(CMFormatDescriptionGetMediaSubType(description))
        let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
        return ImportAudioFacts(fourCC: subtype, sampleRate: basic?.mSampleRate ?? 0, channelCount: Int(basic?.mChannelsPerFrame ?? 0))
    }

    private static func assetError(_ error: Error) -> ImportInspectionError {
        let nsError = error as NSError
        return .assetLoadFailed(domain: nsError.domain, code: nsError.code)
    }

    static func fourCC(_ code: FourCharCode) -> String {
        String(bytes: withUnsafeBytes(of: code.bigEndian, Array.init), encoding: .isoLatin1) ?? ""
    }

    static func primaries(_ value: String?) -> ImportColorPrimaries {
        guard let value else { return .unknown }
        if value == (kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String) { return .rec709 }
        if value == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String) { return .rec2020 }
        return .other(value)
    }

    static func transfer(_ value: String?) -> ImportTransferFunction {
        guard let value else { return .unknown }
        if value == (kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String) { return .rec709 }
        if value == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) { return .hlg }
        if value == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) { return .pq }
        return .other(value)
    }

    static func matrix(_ value: String?) -> ImportYCbCrMatrix {
        guard let value else { return .unknown }
        if value == (kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String) { return .rec709 }
        if value == (kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String) { return .rec2020 }
        return .other(value)
    }

    /// `avcC`: byte 1 = profile_idc (66 Baseline, 77 Main, 100 High, 110 High 10, 122 High 4:2:2,
    /// 244 High 4:4:4 — the last three are high-bit-depth). `hvcC`: byte 1 low 5 bits =
    /// general_profile_idc (1 Main, 2 Main 10, 3 Main Still Picture; 4 Range Extensions spans 8- to
    /// 16-bit profiles, so it proves nothing). Anything else is unknown, never assumed 8-bit.
    static func highBitDepthProfile(atoms: [String: Any]) -> ImportKnownFlag {
        if let avcC = atoms["avcC"] as? Data, avcC.count >= 2 {
            let profile = avcC[avcC.startIndex + 1]
            switch profile {
            case 66, 77, 88, 100: return .no
            case 110, 122, 244: return .yes
            default: return .unknown
            }
        }
        if let hvcC = atoms["hvcC"] as? Data, hvcC.count >= 2 {
            let profile = hvcC[hvcC.startIndex + 1] & 0x1F
            switch profile {
            case 1, 3: return .no
            case 2: return .yes
            default: return .unknown
            }
        }
        return .unknown
    }
}

private extension ImportSourceFacts {
    /// Facts for a file AVFoundation cannot read: every media fact stays at its "unknown / absent"
    /// value; only the byte-level observations are filled in.
    static func unreadable(container: ImportContainer, byteCount: Int64, modificationDate: Date?) -> ImportSourceFacts {
        ImportSourceFacts(
            duration: .invalid, isReadable: false, isPlayable: false, isExportable: false, hasProtectedContent: false,
            hasVideoTrack: false, hasAudioTrack: false, container: container, videoCodec: .unknown,
            naturalWidth: 0, naturalHeight: 0, preferredTransform: .identity,
            nominalFrameRate: 0, minimumFrameDuration: nil, bitsPerComponent: nil, highBitDepthProfile: .unknown, fullRangeVideo: .unknown,
            colorPrimaries: .unknown, transferFunction: .unknown, ycbcrMatrix: .unknown,
            hasDolbyVisionConfiguration: false, ancillaryHDRMetadata: [], aperture: .unreliable, audio: nil, byteCount: byteCount, modificationDate: modificationDate)
    }
}
