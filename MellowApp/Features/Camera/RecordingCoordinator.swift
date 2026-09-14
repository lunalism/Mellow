import CoreGraphics
import Foundation
import Observation
import UIKit

enum RecordingPhase: Equatable, Sendable {
    case idle, preparing, recording, finishing, savingToPhotos
}

enum RecordingStopReason: Equatable, Sendable {
    case userRequested, maximumReached, appInactive, captureInterrupted
}

enum RecordingFailure: Equatable, Sendable {
    case storageLow
    case photosAccess(PhotosAddAuthorization)
    case photosSaveFailed
    case captureFailed

    var title: String {
        switch self {
        case .storageLow: return "Not enough storage"
        case .photosAccess: return "Couldn’t save clip"
        case .photosSaveFailed: return "Couldn’t save clip"
        case .captureFailed: return "Recording failed"
        }
    }
    var detail: String {
        switch self {
        case .storageLow: return "Free up space on your iPhone to record."
        case .photosAccess(.restricted): return "Saving to Photos isn’t available on this device."
        case .photosAccess: return "Allow Mellow to add to your Photos library in Settings."
        case .photosSaveFailed: return "The clip couldn’t be added to Photos. Try again."
        case .captureFailed: return "The clip couldn’t be recorded. Try again."
        }
    }
    var offersSettings: Bool {
        if case .photosAccess(let status) = self { return status == .denied }
        return false
    }
}

/// Brief, non-modal captions; cleared automatically.
enum RecordingNotice: Equatable, Sendable {
    case tooShort, storageLow, microphoneRestricted
    var text: String {
        switch self {
        case .tooShort: return "Too short — 1s minimum"
        case .storageLow: return "Not enough storage"
        case .microphoneRestricted: return "Microphone isn’t available on this device"
        }
    }
}

@MainActor
protocol CompletionHapticPlaying: AnyObject {
    func playCompletion()
}

/// Lets an already-started finalize/save finish if the app goes inactive; never used to keep
/// capturing in the background.
@MainActor
protocol BackgroundTaskRunning: AnyObject {
    func run(_ work: @MainActor () async -> Void) async
}

@MainActor
final class UIKitCompletionHaptic: CompletionHapticPlaying {
    private let generator = UIImpactFeedbackGenerator(style: .light)
    func playCompletion() { generator.impactOccurred(intensity: 0.7) }
}

@MainActor
final class UIApplicationBackgroundTaskRunner: BackgroundTaskRunning {
    func run(_ work: @MainActor () async -> Void) async {
        let application = UIApplication.shared
        // The expiration handler is @Sendable and captures this mutable identifier; both it and the
        // mutations below run on the main thread (this type is @MainActor and UIKit invokes the
        // handler on the main queue), so the capture is safe. `nonisolated(unsafe)` states exactly
        // that, silencing the "mutated after capture" warning without a broader concurrency change.
        nonisolated(unsafe) var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = application.beginBackgroundTask(withName: "com.mellow.recording.finalize") {
            if identifier != .invalid { application.endBackgroundTask(identifier); identifier = .invalid }
        }
        await work()
        if identifier != .invalid { application.endBackgroundTask(identifier); identifier = .invalid }
    }
}

/// Sole arbiter of Camera recording state (ADR-033):
/// `idle → preparing → recording → finishing → savingToPhotos → idle`, failures cleaning up to
/// idle. Owns the stop-reason race (first accepted reason wins) and guarantees exactly one
/// finalization/validation/save per staging file. Project creation never appears here.
@MainActor
@Observable
final class RecordingCoordinator {
    private(set) var phase: RecordingPhase = .idle
    /// Actual written media time / selected maximum, sampled from the capture pipeline.
    private(set) var progress: Double = 0
    private(set) var notice: RecordingNotice?
    var failure: RecordingFailure?
    /// Successful Photos saves this session; used to prove capture never creates a project.
    private(set) var completedSaves = 0
    private(set) var lastStopReason: RecordingStopReason?
    /// Representative frame of the most recent successfully saved clip (Phase 4 preview-tile feedback
    /// only; session-only, never persisted). Replaced only on a save that actually succeeds.
    private(set) var lastThumbnail: CGImage?

    @ObservationIgnored private let service: any CameraCaptureService
    @ObservationIgnored private let staging: any RecordingStagingStoring
    @ObservationIgnored private let photos: any PhotosLibrarySaving
    @ObservationIgnored private let inspector: any RecordingMediaInspecting
    @ObservationIgnored private let thumbnails: any RecordingThumbnailGenerating
    @ObservationIgnored private let haptics: any CompletionHapticPlaying
    @ObservationIgnored private let backgroundTasks: any BackgroundTaskRunning
    @ObservationIgnored private var stopReason: RecordingStopReason?
    @ObservationIgnored private var selectedMaximum: TimeInterval = 3
    @ObservationIgnored private var activeURL: URL?
    @ObservationIgnored private var finalizing = false
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init(
        service: any CameraCaptureService,
        staging: any RecordingStagingStoring,
        photos: any PhotosLibrarySaving,
        inspector: any RecordingMediaInspecting,
        thumbnails: any RecordingThumbnailGenerating,
        haptics: any CompletionHapticPlaying,
        backgroundTasks: any BackgroundTaskRunning
    ) {
        self.service = service
        self.staging = staging
        self.photos = photos
        self.inspector = inspector
        self.thumbnails = thumbnails
        self.haptics = haptics
        self.backgroundTasks = backgroundTasks
        service.recordingDidChange = { [weak self] event in self?.handle(event) }
    }

    var isActive: Bool { phase != .idle }
    var isStoppable: Bool { phase == .recording }

    /// Starts a recording. `posture` must be the *definite* physical reading: a provisional
    /// interface-derived Portrait never authorizes recording (ADR-033).
    func record(maximum: CameraDuration, posture: CameraDeviceOrientation) async {
        guard phase == .idle, !finalizing else { return }
        guard posture == .portrait else { return }
        guard service.state.isRunning else { return }
        failure = nil

        var photosStatus = photos.authorization
        if photosStatus == .notDetermined { photosStatus = await photos.requestAccess() }
        guard photosStatus == .authorized else { failure = .photosAccess(photosStatus); return }

        let usable = await staging.usableCapacityBytes()
        guard RecordingPolicy.hasSufficientStorage(usableBytes: usable) else {
            failure = .storageLow
            return
        }

        phase = .preparing
        progress = 0
        stopReason = nil
        lastStopReason = nil
        selectedMaximum = TimeInterval(maximum.rawValue)
        let url: URL
        do { url = try await staging.newRecordingURL() } catch {
            phase = .idle; failure = .captureFailed; return
        }
        activeURL = url
        let started = await service.startRecording(to: url, maximumDuration: selectedMaximum)
        if !started {
            await staging.remove(url)
            activeURL = nil
            phase = .idle
            failure = .captureFailed
        }
    }

    /// Idempotent: the first accepted reason wins; later requests are no-ops.
    func requestStop(_ reason: RecordingStopReason) async {
        guard phase == .preparing || phase == .recording, stopReason == nil else { return }
        stopReason = reason
        lastStopReason = reason
        await service.requestStopRecording()
    }

    func dismissFailure() { failure = nil }

    func show(_ notice: RecordingNotice) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_400))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: - Pipeline events

    private func handle(_ event: CameraRecordingEvent) {
        switch event {
        case .started:
            guard phase == .preparing else { return }
            phase = .recording
            startProgressSampling()
        case .finished(let url, let fileUsable, let reachedMaximum, _):
            // Exactly one finalization path: later duplicates are dropped here.
            guard !finalizing, phase == .preparing || phase == .recording, url == activeURL else { return }
            finalizing = true
            if reachedMaximum, stopReason == nil { stopReason = .maximumReached; lastStopReason = .maximumReached }
            stopProgressSampling()
            phase = .finishing
            Task { await finalize(url: url, fileUsable: fileUsable) }
        }
    }

    private func finalize(url: URL, fileUsable: Bool) async {
        await backgroundTasks.run { [self] in
            defer {
                finalizing = false
                stopReason = nil
                activeURL = nil
            }
            MellowLog.recording.info("Recording finalized (fileUsable=\(fileUsable, privacy: .public))")
            guard fileUsable else { await discard(url, as: .captureFailed); return }
            let info = await inspector.inspect(url)
            guard info.isPlayable, info.hasVideoTrack else {
                MellowLog.recording.error("Validation failed: playable=\(info.isPlayable, privacy: .public) video=\(info.hasVideoTrack, privacy: .public)")
                await discard(url, as: .captureFailed); return
            }
            let verdict = RecordingPolicy.judge(duration: info.duration, selectedMaximum: selectedMaximum)
            MellowLog.recording.info("Validation \(String(describing: verdict), privacy: .public) duration=\(info.duration, format: .fixed(precision: 3), privacy: .public)s max=\(self.selectedMaximum, format: .fixed(precision: 1), privacy: .public)s")
            switch verdict {
            case .tooShort:
                await staging.remove(url)
                phase = .idle
                progress = 0
                show(.tooShort)
                return
            case .tooLong:
                await discard(url, as: .captureFailed); return
            case .valid:
                break
            }
            // Best-effort thumbnail from the staging file BEFORE Photos save moves it out
            // (shouldMoveFile). Held as a local pending value; only published if the save succeeds.
            // A nil here (generation failure) must not affect the save or the previous thumbnail.
            let pendingThumbnail = await thumbnails.thumbnail(for: url)
            MellowLog.recording.info("Thumbnail generation \(pendingThumbnail == nil ? "failed" : "succeeded", privacy: .public)")
            phase = .savingToPhotos
            progress = 1
            MellowLog.recording.info("Photos save started")
            do {
                try await photos.save(videoAt: url)
                await staging.remove(url)
                completedSaves += 1
                // Publish the thumbnail only now that the clip provably exists in Photos. If
                // generation failed, the previous thumbnail is intentionally left in place.
                if let pendingThumbnail { lastThumbnail = pendingThumbnail }
                phase = .idle
                progress = 0
                MellowLog.recording.info("Photos save succeeded (completedSaves=\(self.completedSaves, privacy: .public))")
                // The only completion haptic: success means the clip exists in Photos.
                haptics.playCompletion()
            } catch let error as PhotosSaveError {
                // Staging is retained as a recovery candidate; previous thumbnail is left unchanged.
                switch error {
                case .notAuthorized(let status):
                    MellowLog.recording.error("Photos save failed: notAuthorized(\(status.rawValue, privacy: .public))")
                    fail(.photosAccess(status))
                case .saveFailed:
                    MellowLog.recording.error("Photos save failed: saveFailed")
                    fail(.photosSaveFailed)
                }
            } catch {
                MellowLog.recording.error("Photos save failed: unknown")
                fail(.photosSaveFailed)
            }
        }
    }

    private func discard(_ url: URL, as failure: RecordingFailure) async {
        await staging.remove(url)
        fail(failure)
    }

    private func fail(_ reason: RecordingFailure) {
        phase = .idle
        progress = 0
        failure = reason
    }

    private func startProgressSampling() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while let self, self.phase == .recording, !Task.isCancelled {
                let elapsed = self.service.recordedDuration
                self.progress = self.selectedMaximum > 0 ? min(1, max(0, elapsed / self.selectedMaximum)) : 0
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopProgressSampling() {
        progressTask?.cancel()
        progressTask = nil
    }
}
