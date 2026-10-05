import AVFoundation
import CoreImage
import CoreMedia
import Darwin
import Foundation

// Phase 6 Step 4B — the working-media normalizer (ADR-045 §3 / §4 / §7 / §8, ADR-047 incl. Revision 1,
// ADR-048 incl. Revision 1, ADR-049). It executes one approved `WorkingMediaNormalizationPlan`:
// reader → Rec.709 video composition → cadence grid → H.264 High writer, with AAC passthrough or
// AAC-LC transcode, then validates the output. The cadence grid (ADR-048 Revision 1) places exactly
// one already-rendered frame at every `k × outputFrameDuration` below the session end, holding the
// latest frame when the composition produced no new one; it only retimes samples. The plan's render path picks the composition: AVFoundation's built-in compositor with
// a layer instruction for a full clean aperture (ADR-045 §4, the only approved tone mapping), or a
// geometry-only custom compositor for a non-full aperture whose colour preflight proved SDR
// Rec.709 (ADR-049 Case C, no tone mapping). It owns exactly one file — the destination, once
// `startWriting()` has created it — and nothing else: no workspace, project media, persistence,
// Photos access, progress, retry or durable operation identity (ADR-047: no resume).

protocol WorkingMediaNormalizing: Sendable {
    /// The caller owns `sourceURL` and the destination's parent directory (the operation workspace)
    /// and supplies a destination that does not exist yet. On success the destination holds
    /// validated working media. On failure or cancellation:
    /// - no URL is ever returned as a successful result;
    /// - output this run created (ownership begins only once `startWriting()` succeeded, and is
    ///   tied to the file's device / inode) is removed when that is safe; AVFoundation's own
    ///   `cancelWriting()` may also delete it, outside this guard;
    /// - anything unowned, replaced, or not a regular file is never intentionally deleted: it is left
    ///   where it is, or — if it was swapped in during cleanup — moved back to its path; if a narrow
    ///   race prevents that restore it stays intact at the quarantine path the error reports. Each
    ///   case is a typed `cleanupFailed` error carrying that evidence and the original failure;
    /// - a file `startWriting()` created before reporting failure is unowned and stays for the
    ///   startup workspace sweep, as does anything else abandoned in the workspace (ADR-047);
    /// - the source and committed media are never touched.
    func normalize(sourceURL: URL, destinationURL: URL, plan: WorkingMediaNormalizationPlan) async throws -> WorkingMediaNormalizationResult
}

struct WorkingMediaNormalizationResult: Hashable, Sendable {
    let destinationURL: URL
    let outputFacts: ImportSourceFacts
    let outputEvidence: WorkingMediaOutputEvidence
    let sourceDuration: MediaTime
    let outputDuration: MediaTime
    let outputByteCount: Int64
}

enum WorkingMediaStream: Hashable, Sendable { case video, audio }

/// The filesystem identity of the output a run created, recorded right after `startWriting()`.
struct WorkingMediaFileIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
}

/// Why an owned output could not be removed. Every case means something existed at `path`.
enum WorkingMediaCleanupFailure: Error, Hashable, Sendable {
    /// Not a regular file (directory, symbolic link, …): never removed, never followed.
    case unsafeItem(path: String, fileType: String)
    /// A regular file, but not the one this run created (different device / inode): never removed.
    case identityChanged(path: String)
    /// A foreign file was found in quarantine and could not be moved back; it is left, intact, at
    /// `quarantinePath` (never deleted).
    case restoreFailed(path: String, quarantinePath: String, domain: String, code: Int)
    case removalFailed(path: String, domain: String, code: Int)
    case stillExists(path: String)
}

/// Why render geometry cannot be built for a plan (ADR-047 Revision 1, ADR-049). Each is a typed
/// normalization failure, never a crash and never an approximate render.
enum WorkingMediaGeometryProblem: Error, Hashable, Sendable {
    /// A component is NaN, infinite, or too large to convert to a raster size.
    case nonFinite
    /// A size is zero or negative, or the aperture is empty.
    case degenerate
    /// The aperture is not inside the encoded raster.
    case apertureOutsideRaster
    /// Not a bakeable axis-aligned transform (`ImportNormalizationTransform`, ADR-049 R1): shear,
    /// arbitrary-angle rotation, a non-finite or non-invertible matrix.
    case transformNotEligible
    /// The transformed aperture presentation is not the raster the plan was built for.
    case presentationMismatch
}

/// Why a normalization produced nothing. No case carries user copy; framework errors keep only
/// their domain and code.
indirect enum WorkingMediaNormalizationError: Error, Equatable, Sendable {
    case sourceNotFileURL
    case sourceMissing
    case sourceNotRegularFile
    case sourceUnreadable
    case destinationNotFileURL
    case destinationParentMissing
    /// Something already exists at the destination; it is never overwritten or removed.
    case destinationExists
    /// Another normalization in this process is writing the same destination.
    case destinationInUse
    case destinationIsSource
    case sourceInspectionFailed(ImportInspectionError)
    /// The plan is not the plan Step 4A builds for the inspected source (includes fast-path sources,
    /// a changed render path, aperture or colour).
    case planDoesNotMatchSource
    /// The plan's geometry cannot be rendered exactly (see `WorkingMediaGeometryProblem`).
    case unsupportedSourceGeometry(WorkingMediaGeometryProblem)
    case missingSourceTrack(WorkingMediaStream)
    case readerSetupFailed(domain: String, code: Int)
    case writerSetupFailed(domain: String, code: Int)
    case cannotAddReaderOutput(WorkingMediaStream)
    case cannotAddWriterInput(WorkingMediaStream)
    /// The source AAC format cannot be written without re-encoding; never silently transcoded.
    case audioPassthroughUnsupported
    case readerStartFailed(domain: String, code: Int)
    case writerStartFailed(domain: String, code: Int)
    /// The reader failed or was cancelled while samples were flowing.
    case readingFailed(domain: String, code: Int)
    /// The writer failed or was cancelled while samples were flowing.
    case writerFailed(domain: String, code: Int)
    case appendFailed(WorkingMediaStream, domain: String, code: Int)
    case finishFailed(domain: String, code: Int)
    case outputInspectionFailed(ImportInspectionError)
    case outputValidationFailed([WorkingMediaOutputViolation])
    /// The rendered video could not be placed on the cadence grid (ADR-048 Revision 1).
    case videoTimingFailed(WorkingMediaVideoTimingFailure)
    /// The owned output could not be removed after `precedingError` (nil with `cancelled == true`
    /// when the run was cancelled). Takes precedence over both, because a file is left behind.
    case cleanupFailed(WorkingMediaCleanupFailure, precedingError: WorkingMediaNormalizationError?, cancelled: Bool)
}

/// Why rendered video frames could not be placed on the ADR-048 Revision 1 cadence grid.
enum WorkingMediaVideoTimingFailure: Error, Hashable, Sendable {
    case cadence(WorkingMediaCadenceError)
    /// A composition sample was not exactly one uncompressed image (it cannot be retimed as one frame).
    case unexpectedSample(sampleCount: Int)
    /// `CMSampleBufferCreateCopyWithNewTiming` failed with this status.
    case retimingFailed(status: Int32)
}

/// The single terminal outcome of the sample-flow phase of one run. Set once; later signals lose.
enum WorkingMediaRunTermination: Hashable, Sendable {
    case streamsCompleted
    case cancelled
    case appendFailed(WorkingMediaStream)
    case videoTimingFailed(WorkingMediaVideoTimingFailure)
    case writerFailed
    case readerFailed
}

// MARK: - Test seams

/// Lifecycle points a test can observe. Production passes no hooks.
enum WorkingMediaNormalizationStage: Hashable, Sendable {
    case willStartWriting
    case pipelineStarted
    case sampleAppended(WorkingMediaStream, count: Int)
    /// Cadence target `target` was appended showing input frame `sourceFrame` (source order);
    /// `held` when it repeats the previous target's frame (ADR-048 Revision 1).
    case videoFrameScheduled(target: Int, sourceFrame: Int, held: Bool)
    /// The stream's writer input was marked finished.
    case streamFinished(WorkingMediaStream)
    case terminated(WorkingMediaRunTermination)
    case willFinishWriting
    case didFinishWriting
    /// The video composition was configured for `path`; `customCompositor` says whether a custom
    /// compositor class was installed (only ever on `.sdrApertureGeometry`).
    case videoPathConfigured(WorkingMediaRenderPath, customCompositor: Bool)
    /// Cleanup verified the owned file's identity and is about to move it into quarantine.
    case willQuarantineOwnedOutput
}

/// Points where a test can force the failure the real framework would report there.
enum WorkingMediaNormalizationFault: Hashable, Sendable {
    case writerStart, readerStart, append(WorkingMediaStream), finishWriting, outputValidation
    /// The writer input refuses a held (repeated) video frame.
    case appendHeldVideoFrame
    /// The stream never receives a readiness callback (models an input that stays not-ready).
    case stall(WorkingMediaStream)
    /// Removing the owned output fails and leaves it in place.
    case cleanupRemoval
    /// The geometry compositor's render of every frame fails (as a failed Core Image task would).
    case render
}

/// A terminal reader / writer status a test can report in place of the real one.
enum WorkingMediaSimulatedTerminalStatus: Hashable, Sendable { case writerFailed, readerFailed }

/// Internal observation / fault-injection seam. It adds no timing and no product behavior: with
/// the default `.none` every check is a no-op.
struct WorkingMediaNormalizerHooks: Sendable {
    var observe: (@Sendable (WorkingMediaNormalizationStage) -> Void)?
    var injectFault: (@Sendable (WorkingMediaNormalizationFault) -> Bool)?
    var simulatedTerminalStatus: (@Sendable () -> WorkingMediaSimulatedTerminalStatus?)?
    /// Replaces the video format descriptions the run loaded from the source, to model a source that
    /// changed after the plan was made (or a multi-description track a writer cannot produce).
    var currentVideoFormatDescriptions: (@Sendable ([CMFormatDescription]) -> [CMFormatDescription])?

    static let none = WorkingMediaNormalizerHooks()

    func fault(_ point: WorkingMediaNormalizationFault) -> Bool { injectFault?(point) ?? false }
}

// MARK: - Normalizer

struct AVFoundationWorkingMediaNormalizer: WorkingMediaNormalizing {
    let inspector: any ImportSourceInspecting
    let hooks: WorkingMediaNormalizerHooks

    /// Interval of the terminal-status supervisor. AVAssetReader / AVAssetWriter `status` is
    /// thread-safe but not documented as key-value observable, and a writer that fails while an
    /// input is not ready is not documented to invoke the readiness block again. Only this
    /// supervisor reads `status` on a timer; samples still flow purely on readiness callbacks.
    static let terminalStatusInterval: Duration = .milliseconds(50)

    init(inspector: any ImportSourceInspecting = AVAssetImportSourceInspector(), hooks: WorkingMediaNormalizerHooks = .none) {
        self.inspector = inspector
        self.hooks = hooks
    }

    func normalize(sourceURL: URL, destinationURL: URL, plan: WorkingMediaNormalizationPlan) async throws -> WorkingMediaNormalizationResult {
        try Task.checkCancellation()
        try Self.validateEntry(source: sourceURL, destination: destinationURL)
        guard let claim = WorkingMediaDestinationClaims.shared.claim(destinationURL) else {
            throw WorkingMediaNormalizationError.destinationInUse
        }
        defer { claim.release() }
        // Re-checked under the claim: from here on nothing else in this process creates the file.
        guard !Self.itemExists(at: destinationURL) else { throw WorkingMediaNormalizationError.destinationExists }

        let sourceFacts = try await inspect(sourceURL, failure: WorkingMediaNormalizationError.sourceInspectionFailed)
        try Task.checkCancellation()
        // The plan must be exactly what Step 4A builds for these facts: a fast-path source, a
        // rejected source or a stale plan all fail here, before any media work.
        let rebuilt = try? WorkingMediaPlanBuilder.plan(
            preparationPath: ImportPreparationPath(reasons: plan.reasons, renderPath: plan.renderPath), facts: sourceFacts, sourceDuration: plan.sourceDuration)
        guard rebuilt == plan else { throw WorkingMediaNormalizationError.planDoesNotMatchSource }

        let run = NormalizationRun(source: sourceURL, destination: destinationURL, plan: plan, hooks: hooks)
        do {
            try await withTaskCancellationHandler {
                try await run.write()
            } onCancel: {
                run.terminate(.cancelled)
            }
            let outputFacts = try await inspect(destinationURL, failure: WorkingMediaNormalizationError.outputInspectionFailed)
            let evidence = try await Self.outputEvidence(at: destinationURL)
            var violations = WorkingMediaOutputValidator.violations(of: outputFacts, evidence: evidence, plan: plan, sourceAudio: sourceFacts.audio)
            if hooks.fault(.outputValidation) { violations.append(.emptyFile) }
            guard violations.isEmpty else { throw WorkingMediaNormalizationError.outputValidationFailed(violations) }
            guard case .exact(let outputDuration) = outputFacts.duration else {
                throw WorkingMediaNormalizationError.outputValidationFailed([.invalidDuration])
            }
            // A cancellation that lands during finalization or validation still wins: no result.
            try Task.checkCancellation()
            return WorkingMediaNormalizationResult(
                destinationURL: destinationURL, outputFacts: outputFacts, outputEvidence: evidence, sourceDuration: plan.sourceDuration,
                outputDuration: outputDuration, outputByteCount: outputFacts.byteCount)
        } catch {
            await run.abort()
            let cancelled = error is CancellationError
            if let failure = run.removeOwnedOutput() {
                throw WorkingMediaNormalizationError.cleanupFailed(
                    failure, precedingError: cancelled ? nil : Self.normalizationError(error), cancelled: cancelled)
            }
            if cancelled { throw CancellationError() }
            throw error
        }
    }

    private static func normalizationError(_ error: Error) -> WorkingMediaNormalizationError {
        if let typed = error as? WorkingMediaNormalizationError { return typed }
        let details = error as NSError
        return .readerSetupFailed(domain: details.domain, code: details.code)
    }

    private func inspect(_ url: URL, failure: (ImportInspectionError) -> WorkingMediaNormalizationError) async throws -> ImportSourceFacts {
        do {
            return try await inspector.inspect(url: url)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let inspection as ImportInspectionError {
            throw failure(inspection)
        } catch {
            let details = error as NSError
            throw failure(.assetLoadFailed(domain: details.domain, code: details.code))
        }
    }

    // MARK: Entry validation

    static func validateEntry(source: URL, destination: URL) throws {
        guard source.isFileURL else { throw WorkingMediaNormalizationError.sourceNotFileURL }
        guard destination.isFileURL else { throw WorkingMediaNormalizationError.destinationNotFileURL }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else { throw WorkingMediaNormalizationError.sourceMissing }
        guard !isDirectory.boolValue, (try? fileManager.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType) == .typeRegular else {
            throw WorkingMediaNormalizationError.sourceNotRegularFile
        }
        guard fileManager.isReadableFile(atPath: source.path) else { throw WorkingMediaNormalizationError.sourceUnreadable }
        if canonicalPath(source) == canonicalPath(destination) { throw WorkingMediaNormalizationError.destinationIsSource }
        var parentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.deletingLastPathComponent().path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
            throw WorkingMediaNormalizationError.destinationParentMissing
        }
        guard !itemExists(at: destination) else { throw WorkingMediaNormalizationError.destinationExists }
    }

    /// Also true for a dangling symlink, which must not be written through.
    static func itemExists(at url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    /// The parent resolved through symlinks plus the last component, so an existing source and a
    /// not-yet-existing destination compare in the same form.
    static func canonicalPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL
        return standardized.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(standardized.lastPathComponent).path
    }

    // MARK: Owned-output cleanup

    /// The identity of the regular file at `url` (`lstat`, never followed); nil when absent or not
    /// a regular file.
    static func fileIdentity(at url: URL) -> WorkingMediaFileIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return WorkingMediaFileIdentity(device: UInt64(bitPattern: Int64(info.st_dev)), inode: UInt64(info.st_ino))
    }

    /// Removes the file this run created, and nothing else. Idempotent: an absent path is success.
    ///
    /// 1. `lstat` the path (never followed): a non-regular item is refused (`unsafeItem`), a
    ///    regular file whose device / inode is not `identity` is refused (`identityChanged`).
    /// 2. Atomically rename it to a fresh, unique quarantine name in the same directory
    ///    (`renamex_np` + `RENAME_EXCL`: never overwrites).
    /// 3. `lstat` the quarantined file: if it is not the owned identity (something replaced the path
    ///    between 1 and 2) it is renamed back without overwriting and reported, never deleted.
    /// 4. `unlink` the quarantined owned file and confirm it is gone. Never recursive.
    ///
    /// Residual trust boundary: between 3 and 4 the quarantine name could only be replaced by an
    /// actor inside the operation workspace that knows the random name; the workspace is private
    /// to the operation. AVFoundation's own `cancelWriting()` may delete the output by path, which
    /// this guard does not control.
    static func removeOwnedOutput(at url: URL, identity: WorkingMediaFileIdentity, injectRemovalFailure: Bool = false,
                                  willQuarantine: (() -> Void)? = nil) -> WorkingMediaCleanupFailure? {
        let path = url.path
        var info = stat()
        if lstat(path, &info) != 0 {
            let code = errno
            return code == ENOENT ? nil : .removalFailed(path: path, domain: NSPOSIXErrorDomain, code: Int(code))
        }
        let type = info.st_mode & S_IFMT
        guard type == S_IFREG else { return .unsafeItem(path: path, fileType: fileTypeName(type)) }
        guard Self.identity(of: info) == identity else { return .identityChanged(path: path) }
        if injectRemovalFailure { return .removalFailed(path: path, domain: "WorkingMediaNormalizerHooks", code: 1) }

        willQuarantine?()
        let quarantine = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).discard-\(UUID().uuidString)").path
        if renamex_np(path, quarantine, UInt32(RENAME_EXCL)) != 0 {
            let code = errno
            return code == ENOENT ? nil : .removalFailed(path: path, domain: NSPOSIXErrorDomain, code: Int(code))
        }
        guard lstat(quarantine, &info) == 0 else { return nil }
        let quarantinedType = info.st_mode & S_IFMT
        guard quarantinedType == S_IFREG, Self.identity(of: info) == identity else {
            // Not ours: put it back exactly where it was, without overwriting anything.
            if renamex_np(quarantine, path, UInt32(RENAME_EXCL)) != 0 {
                return .restoreFailed(path: path, quarantinePath: quarantine, domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            return quarantinedType == S_IFREG ? .identityChanged(path: path) : .unsafeItem(path: path, fileType: fileTypeName(quarantinedType))
        }
        if unlink(quarantine) != 0 {
            let code = errno
            if code != ENOENT { return .removalFailed(path: quarantine, domain: NSPOSIXErrorDomain, code: Int(code)) }
        }
        return lstat(quarantine, &info) == 0 ? .stillExists(path: quarantine) : nil
    }

    private static func identity(of info: stat) -> WorkingMediaFileIdentity {
        WorkingMediaFileIdentity(device: UInt64(bitPattern: Int64(info.st_dev)), inode: UInt64(info.st_ino))
    }

    private static func fileTypeName(_ type: mode_t) -> String {
        switch type {
        case S_IFDIR: return "directory"
        case S_IFLNK: return "symbolicLink"
        case S_IFREG: return "regular"
        default: return "other"
        }
    }

    // MARK: Output evidence (H.264 profile, actual presentation timestamps, track census)

    /// Reads the profile byte of the output's `avcC`, every video sample's timing (compressed
    /// samples only — nothing is decoded), the track census and the AAC decoder configuration. Timing is
    /// judged by `WorkingMediaOutputValidator.presentationTimes(from:)`, which fails closed.
    static func outputEvidence(at url: URL) async throws -> WorkingMediaOutputEvidence {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        do {
            let tracks = try await asset.load(.tracks)
            let counts = WorkingMediaOutputEvidence.TrackCounts(
                video: tracks.filter { $0.mediaType == .video }.count,
                audio: tracks.filter { $0.mediaType == .audio }.count,
                other: tracks.filter { $0.mediaType != .video && $0.mediaType != .audio }.count)
            var aacConfiguration: WorkingMediaAACDecoderConfiguration?
            if let audioTrack = tracks.first(where: { $0.mediaType == .audio }), let description = try await audioTrack.load(.formatDescriptions).first {
                var size = 0
                if let cookie = CMAudioFormatDescriptionGetMagicCookie(description, sizeOut: &size), size > 0 {
                    let bytes = Array(UnsafeBufferPointer(start: cookie.assumingMemoryBound(to: UInt8.self), count: size))
                    aacConfiguration = WorkingMediaOutputValidator.aacDecoderConfiguration(fromMagicCookie: bytes)
                }
            }
            guard let track = tracks.first(where: { $0.mediaType == .video }) else {
                return WorkingMediaOutputEvidence(avcProfileIndication: nil, videoPresentationTimes: .unavailable, trackCounts: counts, aacDecoderConfiguration: aacConfiguration)
            }
            let descriptions = try await track.load(.formatDescriptions)
            try Task.checkCancellation()
            let atoms = descriptions.first.flatMap {
                CMFormatDescriptionGetExtension($0, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any]
            }
            let profile = WorkingMediaOutputValidator.avcProfileIndication(fromAvcC: atoms?["avcC"] as? Data)
            func evidence(_ times: WorkingMediaOutputEvidence.PresentationTimes) -> WorkingMediaOutputEvidence {
                WorkingMediaOutputEvidence(avcProfileIndication: profile, videoPresentationTimes: times, trackCounts: counts, aacDecoderConfiguration: aacConfiguration)
            }

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return evidence(.unavailable) }
            reader.add(output)
            guard reader.startReading() else { return evidence(.unavailable) }
            var observations: [WorkingMediaSampleTimingObservation] = []
            while let sample = output.copyNextSampleBuffer() {
                let count = CMSampleBufferGetNumSamples(sample)
                let entries: [MediaTime?]?
                do {
                    entries = try sample.sampleTimingInfos().map { timing in
                        let pts = timing.presentationTimeStamp
                        return pts.isNumeric ? try? MediaTime(value: pts.value, timescale: pts.timescale) : nil
                    }
                } catch {
                    entries = nil   // unreadable timing: recorded, and judged unavailable below
                }
                observations.append(WorkingMediaSampleTimingObservation(sampleCount: count, presentationTimes: entries))
            }
            guard reader.status == .completed else { return evidence(.unavailable) }
            return evidence(WorkingMediaOutputValidator.presentationTimes(from: observations))
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            let details = error as NSError
            throw WorkingMediaNormalizationError.outputInspectionFailed(.assetLoadFailed(domain: details.domain, code: details.code))
        }
    }

    // MARK: Writer / reader settings (the whole policy surface; tested directly)

    /// A copy of one rendered video sample presented at `presentationTime` for `duration`, with no
    /// decode time (uncompressed frames are presented in order). The copy shares the original's image
    /// buffer and carries its attachments, so a held frame is appended again without re-rendering.
    static func retimedVideoSample(_ sample: CMSampleBuffer, presentationTime: CMTime, duration: CMTime) -> Result<CMSampleBuffer, WorkingMediaVideoTimingFailure> {
        let count = CMSampleBufferGetNumSamples(sample)
        guard count == 1, CMSampleBufferGetImageBuffer(sample) != nil else { return .failure(.unexpectedSample(sampleCount: count)) }
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
        guard status == noErr, let copy else { return .failure(.retimingFailed(status: status)) }
        return .success(copy)
    }

    static func videoOutputSettings(for plan: WorkingMediaNormalizationPlan) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: plan.raster.output.width,
            AVVideoHeightKey: plan.raster.output.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ]
    }

    /// 8-bit 4:2:0 video-range buffers rendered by the Rec.709 composition (ADR-045 §4).
    static let compositionPixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    /// A video media timescale in which every planned frame time is exact: the plan's own
    /// timescale, multiplied up to at least 600 (1/30 → 600, 1001/30000 → 30000).
    static func videoMediaTimeScale(for plan: WorkingMediaNormalizationPlan) -> CMTimeScale {
        scaledTimeScale(plan.outputFrameDuration.timescale)
    }

    /// `base` multiplied up to at least 600, so every multiple of `1 / base` stays exact.
    static func scaledTimeScale(_ base: CMTimeScale) -> CMTimeScale {
        let factor = max(1, (600 + base - 1) / base)
        return base.multipliedReportingOverflow(by: factor).overflow ? base : base * factor
    }

    /// Decoded-PCM reader settings and AAC-LC writer settings for an ADR-048 transcode. The mix
    /// output renders the source to the planned channel count, which is the explicit stereo
    /// downmix for sources above two channels. It keeps the source sample rate; the writer input
    /// converts to the planned 48 kHz while encoding.
    static func audioTranscodeSettings(_ settings: WorkingMediaAudioTranscodeSettings) -> (reader: [String: Any], writer: [String: Any]) {
        let channels = settings.channelLayout == .mono ? 1 : 2
        let layout = channelLayoutData(settings.channelLayout == .mono ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo)
        let reader: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: layout,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let writer: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: settings.sampleRate,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: layout,
            AVEncoderBitRateKey: settings.bitRate,
        ]
        return (reader, writer)
    }

    static func channelLayoutData(_ tag: AudioChannelLayoutTag) -> Data {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = tag
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }

    /// The built-in path's layer transform (ADR-045 §4): bake the presentation transform, move the
    /// result into positive space, then map the full presentation raster onto the planned even
    /// raster. ADR-047 Revision 1: where even alignment shortened an odd edge by one pixel the two
    /// axes are resampled independently — bounded parity quantization, not a stretch policy.
    /// `naturalSize` is the track's, i.e. the full encoded raster with its pixel aspect applied.
    static func layerTransform(naturalSize: CGSize, plan: WorkingMediaNormalizationPlan) -> CGAffineTransform {
        let transform = plan.sourcePresentationTransform.cgAffineTransform
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let presentation = plan.raster.presentation, output = plan.raster.output
        return transform
            .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: CGFloat(output.width) / CGFloat(presentation.width),
                                             y: CGFloat(output.height) / CGFloat(presentation.height)))
    }
}

// MARK: - Render geometry (geometry-only SDR path, ADR-049 Case C)

/// One explicit source → output mapping (ADR-047 Revision 1). The complete clean aperture of the
/// encoded frame — not the encoded raster, and not a pixel-rounded aperture — is mapped exactly
/// onto the planned output raster: aperture origin removed, pixel aspect applied, preferred
/// transform baked, transformed bounds moved to the origin, then each axis scaled to the plan's
/// output edge. Nothing is cropped and nothing is padded; the only shape change is the plan's
/// even-alignment remainder (at most one output pixel per affected edge, enforced by the plan),
/// resampled across the whole frame. Built only from the plan, which stays the only output-size
/// authority.
struct WorkingMediaRenderGeometry: Equatable, Sendable {
    let encodedWidth: Int, encodedHeight: Int
    /// Top-left origin, encoded samples; may be fractional (an odd aperture centred in an even raster).
    let cleanAperture: CGRect
    let outputWidth: Int, outputHeight: Int
    /// Encoded top-left pixel space → output top-left pixel space. Maps `cleanAperture` exactly onto
    /// `(0, 0, outputWidth, outputHeight)`.
    let sourceToOutput: CGAffineTransform

    /// The whole encoded pixels the aperture touches — the only pixels rendering reads. A
    /// half-covered boundary pixel belongs to the aperture's edge, so it is included rather than
    /// dropped; a pixel wholly outside the aperture never is.
    var sourceCoverage: CGRect {
        cleanAperture.integral.intersection(CGRect(x: 0, y: 0, width: encodedWidth, height: encodedHeight))
    }

    /// Every component is checked finite and in range before any integer conversion; the
    /// transformed presentation must round to exactly the plan's presentation raster.
    init(plan: WorkingMediaNormalizationPlan) throws {
        let geometry = plan.aperture, transform = plan.sourcePresentationTransform
        let aperture = geometry.cleanAperture, ratio = geometry.pixelAspectRatio
        let output = plan.raster.output, presentation = plan.raster.presentation
        let maximum = Double(Int32.max)
        guard [aperture.x, aperture.y, aperture.width, aperture.height].allSatisfy(\.isFinite) else { throw WorkingMediaGeometryProblem.nonFinite }
        guard geometry.encodedWidth > 0, geometry.encodedHeight > 0, aperture.width > 0, aperture.height > 0,
              ratio.horizontalSpacing > 0, ratio.verticalSpacing > 0, output.width > 0, output.height > 0
        else { throw WorkingMediaGeometryProblem.degenerate }
        guard ImportNormalizationTransform.isEligible(transform) else { throw WorkingMediaGeometryProblem.transformNotEligible }
        let raster = CGRect(x: 0, y: 0, width: geometry.encodedWidth, height: geometry.encodedHeight)
        let apertureRect = CGRect(x: aperture.x, y: aperture.y, width: aperture.width, height: aperture.height)
        let tolerance = ImportApertureFacts.fullApertureTolerance
        guard raster.insetBy(dx: -tolerance, dy: -tolerance).contains(apertureRect) else { throw WorkingMediaGeometryProblem.apertureOutsideRaster }

        let presentationSize = CGSize(width: aperture.width * Double(ratio.horizontalSpacing) / Double(ratio.verticalSpacing), height: aperture.height)
        let bounds = CGRect(origin: .zero, size: presentationSize).applying(transform.cgAffineTransform)
        guard [presentationSize.width, bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy({ $0.isFinite && abs($0) <= maximum }),
              bounds.width > 0, bounds.height > 0
        else { throw WorkingMediaGeometryProblem.nonFinite }
        guard Int(bounds.width.rounded()) == presentation.width, Int(bounds.height.rounded()) == presentation.height else {
            throw WorkingMediaGeometryProblem.presentationMismatch
        }
        encodedWidth = geometry.encodedWidth
        encodedHeight = geometry.encodedHeight
        cleanAperture = apertureRect
        outputWidth = output.width
        outputHeight = output.height
        sourceToOutput = CGAffineTransform(translationX: -apertureRect.minX, y: -apertureRect.minY)
            .concatenating(CGAffineTransform(scaleX: presentationSize.width / apertureRect.width, y: 1))
            .concatenating(transform.cgAffineTransform)
            .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: CGFloat(output.width) / bounds.width, y: CGFloat(output.height) / bounds.height))
    }
}

/// The composition instruction carrying the render geometry to `WorkingMediaFrameCompositor`.
/// Immutable after creation, so sharing it across AVFoundation's callback threads is safe.
final class WorkingMediaFrameInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let geometry: WorkingMediaRenderGeometry
    /// Test seam (`.render` fault): every render reports failure.
    let injectRenderFailure: Bool

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, geometry: WorkingMediaRenderGeometry, injectRenderFailure: Bool = false) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.geometry = geometry
        self.injectRenderFailure = injectRenderFailure
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

/// Why a geometry render produced no frame.
enum WorkingMediaRenderFailure: Error, Hashable, Sendable {
    case sourceRasterMismatch
    case destinationRasterMismatch
    case injected
}

/// Geometry-only renderer for ADR-049 Case C — used only for a non-full clean aperture whose source
/// colour preflight proved SDR Rec.709 (primaries, transfer and matrix), so no tone mapping is
/// needed or performed. It reads the whole decoded raster and maps the exact clean aperture onto the
/// planned raster; AVFoundation's built-in compositor cannot, for such an aperture (a device probe
/// showed it dropping the far boundary sample of a half-pixel aperture and blending pixels from
/// outside an offset one).
///
/// Colour: the source frame arrives as 8-bit BGRA. For an SDR Rec.709 source with a Rec.709
/// composition that is a Y'CbCr → R'G'B' format conversion, not a colour-space change. Core Image
/// runs with colour management off, so the Rec.709-encoded values are only resampled, and the
/// output buffer is tagged Rec.709. HDR and wide-colour sources never reach this class.
///
/// Each request is rendered and finished synchronously inside `startRequest` — exactly once, with
/// either a fully rendered frame or an error — so none is ever pending and cancellation has
/// nothing to drain. The only state is an immutable, thread-safe `CIContext`.
final class WorkingMediaFrameCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let pixelFormat = kCVPixelFormatType_32BGRA
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])

    var sourcePixelBufferAttributes: [String: any Sendable]? { [kCVPixelBufferPixelFormatTypeKey as String: Self.pixelFormat] }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { [kCVPixelBufferPixelFormatTypeKey as String: Self.pixelFormat] }
    var supportsWideColorSourceFrames: Bool { false }
    var supportsHDRSourceFrames: Bool { false }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? WorkingMediaFrameInstruction,
              let source = request.sourceFrame(byTrackID: instruction.trackID),
              let destination = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "WorkingMediaFrameCompositor", code: 1))
            return
        }
        do {
            try Self.render(source, geometry: instruction.geometry, into: destination, context: context, injectFailure: instruction.injectRenderFailure)
        } catch {
            // The destination may be partially written: it is dropped, never published.
            request.finish(with: NSError(domain: "WorkingMediaFrameCompositor", code: 2))
            return
        }
        request.finish(withComposedVideoFrame: destination)
    }

    func cancelAllPendingVideoCompositionRequests() {}

    /// Maps the decoded frame's clean aperture onto the whole destination and waits for the Core
    /// Image task, so a render failure is observed (it throws) instead of a stale buffer being
    /// published. Only the aperture's pixel coverage is read; every output pixel centre maps inside
    /// the aperture (the plan never upscales, so an output step spans at least one source sample),
    /// and filter support beyond the aperture edge sees the edge sample extended (`clampedToExtent`)
    /// — sub-pixel support, never a visible border and never raster from outside the aperture.
    static func render(_ source: CVPixelBuffer, geometry: WorkingMediaRenderGeometry, into destination: CVPixelBuffer, context: CIContext, injectFailure: Bool = false) throws {
        guard CVPixelBufferGetWidth(source) == geometry.encodedWidth, CVPixelBufferGetHeight(source) == geometry.encodedHeight else {
            throw WorkingMediaRenderFailure.sourceRasterMismatch
        }
        guard CVPixelBufferGetWidth(destination) == geometry.outputWidth, CVPixelBufferGetHeight(destination) == geometry.outputHeight else {
            throw WorkingMediaRenderFailure.destinationRasterMismatch
        }
        if injectFailure { throw WorkingMediaRenderFailure.injected }
        let output = CGRect(x: 0, y: 0, width: geometry.outputWidth, height: geometry.outputHeight)
        let image = CIImage(cvPixelBuffer: source, options: [.colorSpace: NSNull()])
        guard image.extent == CGRect(x: 0, y: 0, width: geometry.encodedWidth, height: geometry.encodedHeight) else {
            throw WorkingMediaRenderFailure.sourceRasterMismatch
        }
        // Core Image uses a bottom-left origin; the geometry is top-left.
        let flipSource = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(geometry.encodedHeight))
        let flipOutput = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(geometry.outputHeight))
        let mapped = image
            .cropped(to: geometry.sourceCoverage.applying(flipSource))
            .clampedToExtent()
            .transformed(by: flipSource.concatenating(geometry.sourceToOutput).concatenating(flipOutput), highQualityDownsample: true)
            .cropped(to: output)
        for (key, value) in [(kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2),
                             (kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2),
                             (kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2)] {
            CVBufferSetAttachment(destination, key, value, .shouldPropagate)
        }
        let target = CIRenderDestination(pixelBuffer: destination)
        target.colorSpace = nil
        let task = try context.startTask(toRender: mapped, from: output, to: target, at: .zero)
        _ = try task.waitUntilCompleted()
    }
}

// MARK: - Destination claims

/// Process-wide set of destinations being written, so two normalizations can never race on one
/// path (the loser fails without touching the file).
final class WorkingMediaDestinationClaims: @unchecked Sendable {
    static let shared = WorkingMediaDestinationClaims()
    private let lock = NSLock()
    private var claimed = Set<String>()

    struct Claim {
        fileprivate let path: String
        fileprivate let owner: WorkingMediaDestinationClaims
        func release() { owner.release(path) }
    }

    func claim(_ url: URL) -> Claim? {
        let path = AVFoundationWorkingMediaNormalizer.canonicalPath(url)
        lock.lock(); defer { lock.unlock() }
        guard claimed.insert(path).inserted else { return nil }
        return Claim(path: path, owner: self)
    }

    private func release(_ path: String) {
        lock.lock(); claimed.remove(path); lock.unlock()
    }
}

// MARK: - One run

/// The AVFoundation objects of one normalization. Isolation: reader outputs and writer inputs are
/// touched only on their stream's serial queue while samples flow; the reader and writer are started,
/// ended, finished and cancelled only by the owning task, and cancellation first quiesces every
/// stream queue so `cancelReading` / `cancelWriting` never run concurrently with
/// `copyNextSampleBuffer` / `append` (AVAssetReader.h / AVAssetWriter.h). `status` is read from the
/// supervisor, which the headers document as thread-safe. The lock guards only the terminal state,
/// ownership and the object references read by the cancellation handler.
private final class NormalizationRun: @unchecked Sendable {
    private let source: URL
    private let destination: URL
    private let plan: WorkingMediaNormalizationPlan
    private let hooks: WorkingMediaNormalizerHooks

    private let lock = NSLock()
    private var termination: WorkingMediaRunTermination?
    /// Device / inode of the file this run created; nil until `startWriting()` has created it.
    private var ownedIdentity: WorkingMediaFileIdentity?
    private var readers: [AVAssetReader] = []
    private var writer: AVAssetWriter?
    private var pumps: [SamplePump] = []

    init(source: URL, destination: URL, plan: WorkingMediaNormalizationPlan, hooks: WorkingMediaNormalizerHooks) {
        self.source = source
        self.destination = destination
        self.plan = plan
        self.hooks = hooks
    }

    private var currentTermination: WorkingMediaRunTermination? { lock.withLock { termination } }

    private func checkRunning() throws {
        try Task.checkCancellation()
        if let termination = currentTermination, termination != .streamsCompleted { throw CancellationError() }
    }

    /// The single terminal transition, safe from any thread: the first caller wins, every stream
    /// waiter is released, and later signals (completion, failure or cancellation) are ignored.
    /// Framework objects are cancelled later by `abort()`, from the owning task.
    @discardableResult
    func terminate(_ reason: WorkingMediaRunTermination) -> Bool {
        let (won, current) = lock.withLock { () -> (Bool, [SamplePump]) in
            guard termination == nil else { return (false, pumps) }
            termination = reason
            return (true, pumps)
        }
        guard won else { return false }
        hooks.observe?(.terminated(reason))
        if reason != .streamsCompleted { for pump in current { pump.resolve(.stopped) } }
        return true
    }

    func write() async throws {
        let asset = AVURLAsset(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let videoTrack: AVAssetTrack
        let timeRange: CMTimeRange, naturalSize: CGSize
        var segments: [AVAssetTrackSegment]
        var videoFormats: [CMFormatDescription]
        var audioTrack: AVAssetTrack?
        var audioFormatHint: CMFormatDescription?
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw WorkingMediaNormalizationError.missingSourceTrack(.video)
            }
            videoTrack = track
            (timeRange, naturalSize, segments) = try await track.load(.timeRange, .naturalSize, .segments)
            videoFormats = try await track.load(.formatDescriptions)
            if plan.audio != .none {
                // The same selection the `S_audio` measurement uses (ADR-050 050-A).
                guard let track = try await ImportAudioTrackSelection.passthroughSourceTrack(of: asset) else {
                    throw WorkingMediaNormalizationError.missingSourceTrack(.audio)
                }
                audioTrack = track
                audioFormatHint = try await track.load(.formatDescriptions).first
            }
        } catch let error as WorkingMediaNormalizationError {
            throw error
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw WorkingMediaNormalizationError.readerSetupFailed(domain: (error as NSError).domain, code: (error as NSError).code)
        }
        try checkRunning()
        if let override = hooks.currentVideoFormatDescriptions { videoFormats = override(videoFormats) }
        // Every description this reader may decode must still agree with the plan (ADR-049 R1):
        // the same consensus preflight required, the planned aperture, and — on the geometry path —
        // SDR Rec.709 proven by each one. Anything else is a plan / source mismatch, never a reason
        // to render differently. Checked before any media work.
        guard Self.formatsMatchPlan(videoFormats, plan: plan) else {
            throw WorkingMediaNormalizationError.planDoesNotMatchSource
        }
        // ADR-048 Revision 1: the first target (time zero) needs a source frame at or before it. A
        // track that starts later — a leading empty edit, which the composition would fill with a
        // synthesized black frame — has none; nothing is pulled back and no lead-in is generated.
        if timeRange.start > .zero || (segments.first.map { $0.isEmpty && $0.timeMapping.target.duration > .zero } ?? false) {
            throw WorkingMediaNormalizationError.videoTimingFailed(.cadence(.noFrameAtOrBeforeFirstTarget))
        }
        // The same transform rule preflight applied; a plan cannot carry another.
        guard ImportNormalizationTransform.isEligible(plan.sourcePresentationTransform) else {
            throw WorkingMediaNormalizationError.unsupportedSourceGeometry(.transformNotEligible)
        }
        var geometry: WorkingMediaRenderGeometry?
        if plan.renderPath == .sdrApertureGeometry {
            do { geometry = try WorkingMediaRenderGeometry(plan: plan) } catch let problem as WorkingMediaGeometryProblem {
                throw WorkingMediaNormalizationError.unsupportedSourceGeometry(problem)
            }
        }

        // One reader per stream. The video reader is limited to the video track's own range, which
        // the composition instruction covers exactly; the audio reader reads the whole asset, so
        // audio that runs past the video (the asset duration) is neither cut nor padded with
        // composited frames.
        let reader = try Self.makeReader(asset)
        reader.timeRange = CMTimeRange(start: .zero, end: timeRange.end)
        var audioReader: AVAssetReader?
        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: destination, fileType: .mov) } catch {
            throw WorkingMediaNormalizationError.writerSetupFailed(domain: (error as NSError).domain, code: (error as NSError).code)
        }
        writer.shouldOptimizeForNetworkUse = false
        // The session end below is the exact source duration; a movie timescale equal to its own keeps
        // the file's duration exact (ADR-045 §7 lower bound).
        writer.movieTimeScale = AVFoundationWorkingMediaNormalizer.scaledTimeScale(plan.sourceDuration.timescale)

        // Video: a Rec.709 composition (cadence, transform bake, full-frame resample) → H.264 High.
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: plan.raster.output.width, height: plan.raster.output.height)
        composition.frameDuration = CMTime(value: plan.outputFrameDuration.value, timescale: plan.outputFrameDuration.timescale)
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let instructionRange = CMTimeRange(start: .zero, end: timeRange.end)
        switch plan.renderPath {
        case .builtInToneMap:
            // ADR-045 §4: the built-in compositor renders each frame into the Rec.709 composition
            // colour space — the approved (device A/B) HDR / wide-colour tone mapping — and bakes the
            // presentation transform from the layer instruction. No custom compositor is installed.
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = instructionRange
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layer.setTransform(AVFoundationWorkingMediaNormalizer.layerTransform(naturalSize: naturalSize, plan: plan), at: .zero)
            instruction.layerInstructions = [layer]
            composition.instructions = [instruction]
        case .sdrApertureGeometry:
            // ADR-049 Case C: geometry only, on a source proven SDR Rec.709 — no tone mapping.
            guard let geometry else { throw WorkingMediaNormalizationError.planDoesNotMatchSource }
            composition.customVideoCompositorClass = WorkingMediaFrameCompositor.self
            composition.instructions = [WorkingMediaFrameInstruction(timeRange: instructionRange, trackID: videoTrack.trackID, geometry: geometry,
                                                                     injectRenderFailure: hooks.fault(.render))]
        }
        hooks.observe?(.videoPathConfigured(plan.renderPath, customCompositor: composition.customVideoCompositorClass != nil))

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: AVFoundationWorkingMediaNormalizer.compositionPixelFormat])
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw WorkingMediaNormalizationError.cannotAddReaderOutput(.video) }
        reader.add(videoOutput)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: AVFoundationWorkingMediaNormalizer.videoOutputSettings(for: plan))
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = .identity
        // Every planned frame time is exact in this timescale, so the stored cadence is exact.
        videoInput.mediaTimeScale = AVFoundationWorkingMediaNormalizer.videoMediaTimeScale(for: plan)
        guard writer.canAdd(videoInput) else { throw WorkingMediaNormalizationError.cannotAddWriterInput(.video) }
        writer.add(videoInput)
        // ADR-048 Revision 1: every rendered frame goes through the cadence grid ending at the
        // exact session end (the source duration) before it reaches the writer.
        let cadence: WorkingMediaCadenceScheduler<CMSampleBuffer>
        do {
            cadence = try WorkingMediaCadenceScheduler(
                frameDuration: CMTime(value: plan.outputFrameDuration.value, timescale: plan.outputFrameDuration.timescale),
                sessionEnd: CMTime(value: plan.sourceDuration.value, timescale: plan.sourceDuration.timescale))
        } catch let error as WorkingMediaCadenceError {
            throw WorkingMediaNormalizationError.videoTimingFailed(.cadence(error))
        }
        var streams = [SamplePump(stream: .video, output: videoOutput, input: videoInput, hooks: hooks, cadence: cadence, sourceReader: reader)]

        // Audio, exactly as planned.
        switch plan.audio {
        case .none:
            break
        case .passthroughAAC:
            guard let audioTrack, let audioFormatHint else { throw WorkingMediaNormalizationError.missingSourceTrack(.audio) }
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let streamReader = try Self.makeReader(asset)
            guard streamReader.canAdd(output) else { throw WorkingMediaNormalizationError.cannotAddReaderOutput(.audio) }
            streamReader.add(output)
            audioReader = streamReader
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormatHint)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw WorkingMediaNormalizationError.audioPassthroughUnsupported }
            writer.add(input)
            streams.append(SamplePump(stream: .audio, output: output, input: input, hooks: hooks))
        case .transcode(let settings):
            guard let audioTrack else { throw WorkingMediaNormalizationError.missingSourceTrack(.audio) }
            let configuration = AVFoundationWorkingMediaNormalizer.audioTranscodeSettings(settings)
            let output = AVAssetReaderAudioMixOutput(audioTracks: [audioTrack], audioSettings: configuration.reader)
            output.alwaysCopiesSampleData = false
            let streamReader = try Self.makeReader(asset)
            guard streamReader.canAdd(output) else { throw WorkingMediaNormalizationError.cannotAddReaderOutput(.audio) }
            streamReader.add(output)
            audioReader = streamReader
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: configuration.writer)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw WorkingMediaNormalizationError.cannotAddWriterInput(.audio) }
            writer.add(input)
            streams.append(SamplePump(stream: .audio, output: output, input: input, hooks: hooks))
        }

        let readers = [reader] + (audioReader.map { [$0] } ?? [])
        lock.withLock {
            self.readers = readers
            self.writer = writer
            pumps = streams
        }
        try checkRunning()

        hooks.observe?(.willStartWriting)
        if hooks.fault(.writerStart) {
            throw WorkingMediaNormalizationError.writerStartFailed(domain: "WorkingMediaNormalizerHooks", code: 1)
        }
        guard writer.startWriting() else { throw Self.error(writer.error, WorkingMediaNormalizationError.writerStartFailed) }
        // Ownership begins only now, and is tied to the identity of the regular file
        // `startWriting()` created at a path verified absent under the claim. Before this point —
        // or if no regular file is there — nothing at the destination is ever removed by this run.
        let identity = AVFoundationWorkingMediaNormalizer.fileIdentity(at: destination)
        lock.withLock { ownedIdentity = identity }
        if hooks.fault(.readerStart) {
            throw WorkingMediaNormalizationError.readerStartFailed(domain: "WorkingMediaNormalizerHooks", code: 1)
        }
        for streamReader in readers {
            guard streamReader.startReading() else { throw Self.error(streamReader.error, WorkingMediaNormalizationError.readerStartFailed) }
        }
        writer.startSession(atSourceTime: .zero)
        hooks.observe?(.pipelineStarted)

        // Drain every stream concurrently on readiness callbacks; the supervisor only watches for a
        // terminal reader / writer status that no callback would report.
        let outcomes = await withTaskGroup(of: ChildResult.self) { group in
            for pump in streams {
                group.addTask { .pump(pump.stream, await pump.run(onFailure: { self.terminate($0) })) }
            }
            group.addTask {
                await self.superviseTerminalStatus(readers: readers, writer: writer)
                return .supervisor
            }
            var collected: [WorkingMediaStream: SamplePump.Outcome] = [:]
            for await child in group {
                if case .pump(let stream, let outcome) = child {
                    collected[stream] = outcome
                    if collected.count == streams.count { group.cancelAll() }
                }
            }
            return collected
        }
        if outcomes.values.allSatisfy({ $0 == .exhausted }) { terminate(.streamsCompleted) }

        switch currentTermination {
        case .appendFailed(let stream):
            throw Self.error(writer.error, { WorkingMediaNormalizationError.appendFailed(stream, domain: $0, code: $1) })
        case .videoTimingFailed(let failure):
            throw WorkingMediaNormalizationError.videoTimingFailed(failure)
        case .writerFailed:
            throw Self.error(writer.error, WorkingMediaNormalizationError.writerFailed)
        case .readerFailed:
            throw Self.error(readers.first(where: { $0.error != nil })?.error, WorkingMediaNormalizationError.readingFailed)
        case .cancelled, nil:
            throw CancellationError()
        case .streamsCompleted:
            break
        }
        try checkRunning()
        for streamReader in readers {
            switch streamReader.status {
            case .completed: break
            case .cancelled: throw CancellationError()
            default: throw Self.error(streamReader.error, WorkingMediaNormalizationError.readingFailed)
            }
        }

        // Every input is marked finished; end the session at the exact source duration so the final
        // frame is truncated rather than rounded up and longer audio is edited out (ADR-045 §7).
        writer.endSession(atSourceTime: CMTime(value: plan.sourceDuration.value, timescale: plan.sourceDuration.timescale))
        hooks.observe?(.willFinishWriting)
        try checkRunning()
        await writer.finishWriting()
        hooks.observe?(.didFinishWriting)
        if hooks.fault(.finishWriting) || writer.status != .completed {
            throw Self.error(writer.error, WorkingMediaNormalizationError.finishFailed)
        }
        try checkRunning()
    }

    private enum ChildResult: Sendable {
        case pump(WorkingMediaStream, SamplePump.Outcome)
        case supervisor
    }

    /// Terminal-status supervision only: ends the run if the writer or reader fails or is
    /// cancelled while a stream may be waiting for a readiness callback that will not come. Exits
    /// as soon as the run has a terminal state or the task group is cancelled.
    private func superviseTerminalStatus(readers: [AVAssetReader], writer: AVAssetWriter) async {
        while !Task.isCancelled && currentTermination == nil {
            let simulated = hooks.simulatedTerminalStatus?()
            if simulated == .writerFailed || writer.status == .failed || writer.status == .cancelled {
                terminate(.writerFailed)
                return
            }
            if simulated == .readerFailed || readers.contains(where: { $0.status == .failed || $0.status == .cancelled }) {
                terminate(.readerFailed)
                return
            }
            try? await Task.sleep(for: AVFoundationWorkingMediaNormalizer.terminalStatusInterval)
        }
    }

    /// Stops the pipeline after a failure or cancellation. Every stream queue is drained first so
    /// no `copyNextSampleBuffer` / `append` is in flight when the reader and writer are cancelled.
    func abort() async {
        terminate(.cancelled)
        let (current, readers, writer) = lock.withLock { (pumps, self.readers, self.writer) }
        for pump in current { pump.resolve(.stopped) }
        for pump in current { await pump.quiesce() }
        for streamReader in readers where streamReader.status == .reading { streamReader.cancelReading() }
        if writer?.status == .writing { writer?.cancelWriting() }
    }

    private static func makeReader(_ asset: AVAsset) throws -> AVAssetReader {
        do { return try AVAssetReader(asset: asset) } catch {
            throw WorkingMediaNormalizationError.readerSetupFailed(domain: (error as NSError).domain, code: (error as NSError).code)
        }
    }

    /// Removes the destination only if this run created it and it is still that same regular file
    /// (device / inode). Idempotent: an absent file is success.
    func removeOwnedOutput() -> WorkingMediaCleanupFailure? {
        guard let identity = lock.withLock({ ownedIdentity }) else { return nil }
        return AVFoundationWorkingMediaNormalizer.removeOwnedOutput(
            at: destination, identity: identity, injectRemovalFailure: hooks.fault(.cleanupRemoval),
            willQuarantine: { self.hooks.observe?(.willQuarantineOwnedOutput) })
    }

    /// The current descriptions against the plan, through the same pure rules preflight used: every
    /// one a supported codec family (ADR-046 — the plan holds no codec, any supported mix is the
    /// source preflight accepted), and the ADR-049 Revision 1 consensus — agreement among
    /// themselves, the planned aperture class and geometry, and on the geometry path each proving
    /// SDR Rec.709.
    static func formatsMatchPlan(_ descriptions: [CMFormatDescription], plan: WorkingMediaNormalizationPlan) -> Bool {
        let current = descriptions.map(AVAssetImportSourceInspector.descriptionFacts(from:))
        guard current.allSatisfy({ $0.videoCodec.isSupportedFamily }),
              case .success(let consensus) = ImportDescriptionConsensus.evaluate(current),
              let geometry = consensus.aperture.geometry, ImportDescriptionConsensus.compatible(geometry, plan.aperture)
        else { return false }
        switch (plan.renderPath, consensus.aperture) {
        case (.builtInToneMap, .full):
            return true
        case (.sdrApertureGeometry, .nonFull):
            return consensus.everyDescriptionProvenSDRRec709
        case (.builtInToneMap, .nonFull), (.builtInToneMap, .unreliable), (.sdrApertureGeometry, .full), (.sdrApertureGeometry, .unreliable):
            return false
        }
    }

    private static func error<E>(_ underlying: Error?, _ make: (String, Int) -> E) -> E {
        let details = underlying.map { $0 as NSError }
        return make(details?.domain ?? "AVFoundation", details?.code ?? 0)
    }
}

// MARK: - One stream

/// Moves samples from one reader output to one writer input on its own serial queue, driven by
/// `requestMediaDataWhenReady` (no polling, no sleeps). It resolves exactly once: when the output
/// is exhausted, when an append or the video timing fails, or when the run is terminated.
/// The video pump routes every rendered sample through the cadence grid (ADR-048 Revision 1); the
/// audio pump appends samples unchanged.
private final class SamplePump: @unchecked Sendable {
    enum Outcome: Hashable, Sendable { case exhausted, failed, stopped }

    let stream: WorkingMediaStream
    private let output: AVAssetReaderOutput
    private let input: AVAssetWriterInput
    private let hooks: WorkingMediaNormalizerHooks
    private let queue: DispatchQueue

    private let lock = NSLock()
    private var outcome: Outcome?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var appended = 0 // queue-confined
    /// Video only; queue-confined. Holds at most the current selection and one look-ahead sample.
    private var cadence: WorkingMediaCadenceScheduler<CMSampleBuffer>?
    /// Video only: the reader behind `output`, whose thread-safe `status` tells an exhausted
    /// composition apart from a failed one before the grid treats the input as finished.
    private let sourceReader: AVAssetReader?

    init(stream: WorkingMediaStream, output: AVAssetReaderOutput, input: AVAssetWriterInput, hooks: WorkingMediaNormalizerHooks,
         cadence: WorkingMediaCadenceScheduler<CMSampleBuffer>? = nil, sourceReader: AVAssetReader? = nil) {
        self.stream = stream
        self.output = output
        self.input = input
        self.hooks = hooks
        self.cadence = cadence
        self.sourceReader = sourceReader
        queue = DispatchQueue(label: "com.mellow.working-media.\(stream == .video ? "video" : "audio")")
    }

    private var isResolved: Bool { lock.lock(); defer { lock.unlock() }; return outcome != nil }

    func run(onFailure: @escaping @Sendable (WorkingMediaRunTermination) -> Void) async -> Outcome {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let outcome {
                lock.unlock()
                continuation.resume(returning: outcome)
                return
            }
            self.continuation = continuation
            lock.unlock()
            // A stalled stream (test seam) never gets a callback; only termination releases it.
            guard !hooks.fault(.stall(stream)) else { return }
            input.requestMediaDataWhenReady(on: queue) { [self] in
                drain(onFailure: onFailure)
            }
        }
    }

    private func drain(onFailure: @Sendable (WorkingMediaRunTermination) -> Void) {
        if cadence != nil { drainOnCadenceGrid(onFailure: onFailure); return }
        while !isResolved && input.isReadyForMoreMediaData {
            guard let sample = output.copyNextSampleBuffer() else {
                finishInput()
                resolve(.exhausted)
                return
            }
            if isResolved { return }
            if hooks.fault(.append(stream)) || !input.append(sample) {
                // Record the run's terminal state before releasing the waiter, so the owner
                // can never observe this stream finished without knowing why.
                fail(.appendFailed(stream), onFailure)
                return
            }
            appended += 1
            hooks.observe?(.sampleAppended(stream, count: appended))
        }
    }

    /// ADR-048 Revision 1: appends exactly one sample per cadence target, each a retimed copy of the
    /// selected rendered sample (same image buffer, never re-rendered). Reads ahead only when the
    /// next target cannot be decided yet. Once every target below the session end is appended the
    /// input is finished and any rendered frames past the grid are read and discarded, so the reader
    /// still completes normally.
    private func drainOnCadenceGrid(onFailure: @Sendable (WorkingMediaRunTermination) -> Void) {
        while !isResolved && input.isReadyForMoreMediaData {
            let selection: WorkingMediaCadenceScheduler<CMSampleBuffer>.Selection?
            do { selection = try cadence?.next() } catch {
                fail(.videoTimingFailed(Self.timingFailure(error)), onFailure)
                return
            }
            if let selection {
                let retimed: CMSampleBuffer
                switch AVFoundationWorkingMediaNormalizer.retimedVideoSample(
                    selection.frame, presentationTime: selection.target.presentationTime, duration: selection.target.duration) {
                case .success(let sample): retimed = sample
                case .failure(let failure):
                    fail(.videoTimingFailed(failure), onFailure)
                    return
                }
                if isResolved { return }
                if hooks.fault(.append(stream)) || (selection.isHeld && hooks.fault(.appendHeldVideoFrame)) || !input.append(retimed) {
                    fail(.appendFailed(stream), onFailure)
                    return
                }
                appended += 1
                hooks.observe?(.sampleAppended(stream, count: appended))
                hooks.observe?(.videoFrameScheduled(target: selection.target.index, sourceFrame: selection.frameOrdinal, held: selection.isHeld))
                continue
            }
            if cadence?.isComplete ?? true {
                finishInput()
                while !isResolved, output.copyNextSampleBuffer() != nil {}
                resolve(.exhausted)
                return
            }
            if let sample = output.copyNextSampleBuffer() {
                if isResolved { return }
                do { try cadence?.offer(sample, at: CMSampleBufferGetPresentationTimeStamp(sample)) } catch {
                    fail(.videoTimingFailed(Self.timingFailure(error)), onFailure)
                    return
                }
            } else {
                // No more frames: a failed reader is a reading failure, never a cadence failure.
                if let status = sourceReader?.status, status == .failed || status == .cancelled {
                    fail(.readerFailed, onFailure)
                    return
                }
                cadence?.finishInput()
            }
        }
    }

    private static func timingFailure(_ error: Error) -> WorkingMediaVideoTimingFailure {
        .cadence(error as? WorkingMediaCadenceError ?? .unexpectedInput)
    }

    private func finishInput() {
        input.markAsFinished()
        hooks.observe?(.streamFinished(stream))
    }

    private func fail(_ termination: WorkingMediaRunTermination, _ onFailure: @Sendable (WorkingMediaRunTermination) -> Void) {
        // Record the run's terminal state before releasing the waiter, so the owner can never
        // observe this stream finished without knowing why.
        onFailure(termination)
        resolve(.failed)
    }

    /// Idempotent: the first outcome wins and the waiter resumes exactly once.
    func resolve(_ value: Outcome) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = value
        let waiter = continuation
        continuation = nil
        lock.unlock()
        waiter?.resume(returning: value)
    }

    /// Returns after any drain already running on this stream's queue has returned; a drain that
    /// starts later sees the resolved outcome and touches nothing.
    func quiesce() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { continuation.resume() }
        }
    }
}
