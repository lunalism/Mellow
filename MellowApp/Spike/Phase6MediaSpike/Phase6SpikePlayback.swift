#if DEBUG
import AVFoundation
import Foundation
import Observation

/// What the diagnostic player is asked to show. Both cases carry a spike-owned local file URL —
/// never a PhotosPicker / provider URL, which is only valid inside the transfer closure.
enum Phase6SpikePlaybackTarget: Equatable {
    case source(URL)
    case output(URL)

    var url: URL { switch self { case .source(let u), .output(let u): return u } }
    var label: String { switch self { case .source: return "원본"; case .output: return "변환 결과" } }
}

/// DEBUG-only playback controller with stable ownership: exactly one `AVPlayer` for the lifetime
/// of the presented player, KVO observation of readiness / rate / waiting reason, explicit play /
/// pause / restart / close, and readable diagnostics. Never autoplays.
@Observable
@MainActor
final class Phase6SpikePlaybackController {
    private(set) var target: Phase6SpikePlaybackTarget?
    private(set) var player: AVPlayer?
    private(set) var itemStatus = "no item"
    private(set) var itemError: String?
    private(set) var playerError: String?
    private(set) var rate: Float = 0
    private(set) var timeControlStatus = "-"
    private(set) var waitingReason = "-"
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var loadError: String?
    private(set) var audioSessionNote = "-"
    private(set) var hasVideo = false
    private(set) var hasAudio = false
    private(set) var playCommands = 0

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    var isOpen: Bool { target != nil }
    var observerCount: Int { observations.count + (timeObserver == nil ? 0 : 1) + (endObserver == nil ? 0 : 1) }

    /// Pre-flight the file, then create the single player for this target. Returns false with
    /// `loadError` set when the file is missing / unreadable (no player is created in that case).
    @discardableResult
    func open(_ newTarget: Phase6SpikePlaybackTarget) -> Bool {
        close()
        target = newTarget
        let url = newTarget.url
        guard FileManager.default.fileExists(atPath: url.path) else { loadError = "파일 없음: \(url.lastPathComponent)"; return false }
        guard FileManager.default.isReadableFile(atPath: url.path) else { loadError = "읽을 수 없음: \(url.lastPathComponent)"; return false }
        loadError = nil
        configureAudioSession(active: true)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        self.player = player
        observations = [
            item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor in self?.itemStatus = Self.name(item.status); self?.itemError = item.error.map { "\(($0 as NSError).domain)/\(($0 as NSError).code): \($0.localizedDescription)" } }
            },
            player.observe(\.rate, options: [.initial, .new]) { [weak self] player, _ in
                Task { @MainActor in self?.rate = player.rate }
            },
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                Task { @MainActor in self?.timeControlStatus = Self.name(player.timeControlStatus); self?.waitingReason = player.reasonForWaitingToPlay?.rawValue ?? "-" }
            },
            player.observe(\.status, options: [.initial, .new]) { [weak self] player, _ in
                Task { @MainActor in self?.playerError = player.error.map { $0.localizedDescription } }
            },
        ]
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
                if let d = self?.player?.currentItem?.duration, d.isNumeric { self?.duration = d.seconds }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.timeControlStatus = "paused (reached end)" }
        }
        Task { [weak self] in
            let (video, audio) = ((try? await asset.loadTracks(withMediaType: .video)) ?? [], (try? await asset.loadTracks(withMediaType: .audio)) ?? [])
            await MainActor.run { self?.hasVideo = !video.isEmpty; self?.hasAudio = !audio.isEmpty }
        }
        return true
    }

    func play() { playCommands += 1; player?.play() }
    func pause() { player?.pause() }
    func restart() {
        guard let player else { return }
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in Task { @MainActor in self?.play() } }
    }

    /// Stops playback and releases the player and every observer; safe to call repeatedly.
    func close() {
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        observations.forEach { $0.invalidate() }
        observations = []
        player?.replaceCurrentItem(with: nil)
        player = nil
        if target != nil { configureAudioSession(active: false) }
        target = nil
        loadError = nil
        itemStatus = "no item"; itemError = nil; playerError = nil; rate = 0; timeControlStatus = "-"; waitingReason = "-"; currentTime = 0; duration = 0; hasVideo = false; hasAudio = false
    }

    /// Playback category so the diagnostic A/B is audible regardless of the silent switch. Scoped to
    /// this DEBUG controller's open/close; production audio behavior is untouched.
    private func configureAudioSession(active: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if active {
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
                audioSessionNote = "category=\(session.category.rawValue) active"
            } else {
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
                audioSessionNote = "deactivated"
            }
        } catch {
            audioSessionNote = "audio session error: \(error.localizedDescription)"
        }
    }

    var diagnosticsRows: [(String, String)] {
        [
            ("대상", target.map { "\($0.label) · \($0.url.lastPathComponent)" } ?? "-"),
            ("item status", itemStatus),
            ("item error", itemError ?? "none"),
            ("player error", playerError ?? "none"),
            ("rate", "\(rate)"),
            ("timeControlStatus", timeControlStatus),
            ("waiting reason", waitingReason),
            ("time / duration", String(format: "%.2f / %.2f s", currentTime, duration)),
            ("tracks", "video=\(hasVideo) audio=\(hasAudio)"),
            ("play commands issued", "\(playCommands)"),
            ("audio session", audioSessionNote),
            ("load error", loadError ?? "none"),
        ]
    }

    static func name(_ s: AVPlayerItem.Status) -> String { switch s { case .unknown: return "unknown"; case .readyToPlay: return "readyToPlay"; case .failed: return "failed"; @unknown default: return "?" } }
    static func name(_ s: AVPlayer.TimeControlStatus) -> String { switch s { case .paused: return "paused"; case .waitingToPlayAtSpecifiedRate: return "waitingToPlayAtSpecifiedRate"; case .playing: return "playing"; @unknown default: return "?" } }
}
#endif
