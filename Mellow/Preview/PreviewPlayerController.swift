@preconcurrency import AVFoundation
import Foundation

// 컴포지션을 AVPlayer 에 물려 재생하고, 이음새 검증에 필요한 값을 노출한다
// (1-13, 1-14).
//
// 핵심 확인은 "합치는 중" 로딩 없이 즉시 재생되는가다. 익스포트를 하지 않으므로
// 병합은 편집 목록을 만드는 것뿐이고 파일을 쓰지 않는다. 그 전제가 맞는지
// 진입부터 첫 프레임까지의 시간으로 확인한다.
@MainActor
final class PreviewPlayerController: ObservableObject {

    enum State: Equatable {
        case idle
        case preparing
        case playing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentTime: CMTime = .zero
    @Published private(set) var duration: CMTime = .zero
    /// 각 클립이 시작하는 시각. 이음새를 눈으로 대조할 기준이다.
    @Published private(set) var boundaries: [CMTime] = []
    /// 지금 몇 번째 클립을 재생 중인지 (0-based).
    @Published private(set) var currentClipIndex = 0
    /// 진입 → 첫 프레임 표시까지 걸린 시간.
    @Published private(set) var firstFrameMilliseconds: Double?
    /// 병합에 쓰인 클립 수.
    @Published private(set) var clipCount = 0
    /// 컴포지션 비디오 트랙이 갖게 된 표시 규격.
    @Published private(set) var renderedSize: CGSize?
    /// 앞 클립의 오디오가 짧아 무음이 삽입된 경계의 인덱스.
    /// 청취 검증에서 어느 이음새를 들어야 하는지 알려준다.
    @Published private(set) var silenceGapBoundaries: Set<Int> = []
    /// 재생이 멈칫한 정황. 첫 프레임 이후에 발생한 것만 담는다.
    ///
    /// 시작 직후에는 버퍼가 비어 있고 keepUp 도 false 인 것이 정상이라,
    /// 그것까지 담으면 진짜 문제가 묻힌다. 전체 기록은 CaptureTrace 에 남는다.
    @Published private(set) var stallEvents: [String] = []

    let player = AVPlayer()

    private var readyForDisplayObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    /// 멈칫 감지용 관찰들.
    private var stallObservations: [NSKeyValueObservation] = []
    private var stalledNotificationObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var boundaryObserver: Any?
    /// 진입 시각. 첫 프레임까지의 경과를 재는 기준점.
    private var enteredAt: UInt64?

    deinit {
        // deinit 은 nonisolated 다. 관찰만 끊는다.
        readyForDisplayObservation?.invalidate()
        itemStatusObservation?.invalidate()
    }

    // MARK: - 준비

    /// 클립들을 병합해 재생을 시작한다.
    func prepare(urls: [URL]) async {
        guard state == .idle else { return }
        enteredAt = DispatchTime.now().uptimeNanoseconds
        CaptureTrace.shared.begin("미리보기 진입 (클립 \(urls.count)개)")
        state = .preparing

        let report = await ClipMerger.merge(urls)
        CaptureTrace.shared.mark("병합 완료")

        guard report.succeeded else {
            state = .failed(report.fatal ?? "알 수 없는 실패")
            return
        }

        clipCount = report.clips.count
        boundaries = report.clips.map(\.start)
        duration = report.compositionDuration

        // 오디오가 짧은 클립 뒤에 1.67ms 무음이 들어간다. 그 무음은 다음 클립이
        // 시작하기 직전에 위치하므로 경계 인덱스는 i+1 이다.
        silenceGapBoundaries = Set(report.clips.indices.compactMap { i in
            guard let video = report.clips[i].videoDuration,
                  let audio = report.clips[i].audioDuration,
                  CMTimeCompare(audio, video) < 0,
                  i + 1 < report.clips.count else { return nil }
            return i + 1
        })
        if let size = report.videoTrackNaturalSize, let transform = report.videoTrackTransform {
            renderedSize = MergeReport.renderedSize(size, transform)
        }

        // 익스포트 없이 컴포지션을 그대로 물린다. 파일을 쓰지 않으므로
        // "합치는 중" 로딩이 필요 없다는 것이 이 설계의 전제다.
        let item = AVPlayerItem(asset: report.composition)
        CaptureTrace.shared.mark("AVPlayerItem 생성")

        observeItemStatus(item)
        observeStalls(item)
        player.replaceCurrentItem(with: item)
        installTimeObservers()

        player.play()
        state = .playing
        CaptureTrace.shared.mark("play() 호출")
    }

    /// 플레이어 레이어가 만들어지면 붙인다. 첫 프레임 시각은 이 레이어가 알려준다.
    func attach(playerLayer: AVPlayerLayer) {
        readyForDisplayObservation = playerLayer.observe(\.isReadyForDisplay,
                                                          options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor [weak self] in
                self?.markFirstFrame()
            }
        }
    }

    func stop() {
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let boundaryObserver {
            player.removeTimeObserver(boundaryObserver)
            self.boundaryObserver = nil
        }
        readyForDisplayObservation?.invalidate()
        readyForDisplayObservation = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        stallObservations.forEach { $0.invalidate() }
        stallObservations = []
        if let stalledNotificationObserver {
            NotificationCenter.default.removeObserver(stalledNotificationObserver)
            self.stalledNotificationObserver = nil
        }
        player.replaceCurrentItem(with: nil)
        state = .idle
    }

    // MARK: - 계측

    private func markFirstFrame() {
        guard firstFrameMilliseconds == nil, let enteredAt else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - enteredAt) / 1_000_000
        firstFrameMilliseconds = elapsed
        CaptureTrace.shared.mark("첫 프레임 표시 (isReadyForDisplay)")
        print(String(format: "[preview] 진입 → 첫 프레임 %.1fms  (클립 %d개)", elapsed, clipCount))
    }

    private func observeItemStatus(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            let label: String
            switch item.status {
            case .readyToPlay: label = "readyToPlay"
            case .failed: label = "failed: \(item.error?.localizedDescription ?? "?")"
            case .unknown: return
            @unknown default: return
            }
            CaptureTrace.shared.mark("PlayerItem status → \(label)")
        }
    }

    // MARK: - 멈칫 감지

    // "멈칫이 없었다"의 근거가 육안 관찰뿐이면 클립 수를 늘렸을 때 판정할 수 없다.
    // 버퍼 상태와 stall 알림을 전부 시각과 함께 남긴다.
    private func observeStalls(_ item: AVPlayerItem) {
        stallObservations = [
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] item, _ in
                let value = item.isPlaybackLikelyToKeepUp
                Task { @MainActor [weak self] in
                    self?.note("likelyToKeepUp = \(value)", isProblem: !value)
                }
            },
            item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] item, _ in
                let value = item.isPlaybackBufferEmpty
                Task { @MainActor [weak self] in
                    self?.note("bufferEmpty = \(value)", isProblem: value)
                }
            },
            item.observe(\.isPlaybackBufferFull, options: [.initial, .new]) { [weak self] item, _ in
                let value = item.isPlaybackBufferFull
                Task { @MainActor [weak self] in
                    self?.note("bufferFull = \(value)", isProblem: false)
                }
            }
        ]

        stalledNotificationObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.note("playbackStalled 알림", isProblem: true)
            }
        }
    }

    /// 정황 하나를 기록한다. 전체는 트레이스로, 문제로 볼 것만 화면으로.
    private func note(_ label: String, isProblem: Bool) {
        let seconds = CMTimeGetSeconds(player.currentTime())
        CaptureTrace.shared.event(String(format: "재생 %@  t=%.4fs", label, seconds))

        // 시작 직후의 버퍼 비어 있음·keepUp false 는 정상이다. 첫 프레임 이후만 센다.
        guard isProblem, firstFrameMilliseconds != nil else { return }
        stallEvents.append(String(format: "%.2fs %@", seconds, label))
    }

    private func installTimeObservers() {
        // 30fps 간격이면 프레임 단위로 시각을 따라갈 수 있다.
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30),
                                                      queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.updateCurrentTime(time)
            }
        }

        // 클립 경계를 정확히 지나는 순간을 로그로 남긴다. 이음새에서 무슨 일이
        // 벌어지는지 눈으로 본 것과 시각을 맞춰 보기 위한 것이다.
        let crossings = boundaries.dropFirst().map { NSValue(time: $0) }
        guard !crossings.isEmpty else { return }
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: crossings,
                                                          queue: .main) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = self.player.currentTime()
                CaptureTrace.shared.event(
                    String(format: "클립 경계 통과  t=%.4fs", CMTimeGetSeconds(now)))
            }
        }
    }

    private func updateCurrentTime(_ time: CMTime) {
        currentTime = time
        let seconds = CMTimeGetSeconds(time)
        // 마지막으로 지나온 경계의 인덱스가 현재 클립이다.
        var index = 0
        for (i, boundary) in boundaries.enumerated()
        where CMTimeGetSeconds(boundary) <= seconds + 0.0001 {
            index = i
        }
        currentClipIndex = index
    }
}
