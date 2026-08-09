@preconcurrency import AVFoundation
import Observation
import Foundation

/// 병합·재생 오케스트레이션. (Tasks 1-12 ~ 1-16)
///
/// 익스포트하지 않는다. AVMutableComposition 을 AVPlayer 에 직접 물린다 —
/// "사용자에게 합치는 중 로딩을 보여주지 않는다"가 확정 결정이다.
/// 그 약속이 지켜지는지 탭 → readyToPlay 경과 시간으로 측정한다.
@MainActor
@Observable
final class CompositionController {

    private(set) var groups: [ClipGroup] = []
    private(set) var skipped: [String] = []
    private(set) var libraryState = "미스캔"
    private(set) var buildState = "-"
    /// 탭에서 재생 준비까지 걸린 시간.
    private(set) var readyMilliseconds: Double?

    private(set) var player: AVPlayer?
    var isPlayerPresented = false

    private var statusObservation: NSKeyValueObservation?
    private var tappedAt: Date?

    func scan() async {
        libraryState = "스캔 중"
        let result = await ClipLibrary.scan()
        groups = result.groups
        skipped = result.skipped
        let summary = groups.map(\.label).joined(separator: " ")
        libraryState = groups.isEmpty
            ? "클립 없음"
            : "\(groups.reduce(0) { $0 + $1.specs.count })개 — \(summary)"
        if !skipped.isEmpty {
            libraryState += " (제외 \(skipped.count))"
            for name in skipped { print("MCOMP skipped \(name)") }
        }
        print("MCOMP scan \(libraryState)")
    }

    func play(group: ClipGroup) {
        build(specs: group.specs, label: "\(group.rotationDegrees)°×\(group.specs.count)")
    }

    /// 자세를 섞어서 병합한다. "이렇게 하면 안 된다"를 실증하는 것이 목적이다.
    /// 세로(90°)를 먼저 넣어 컴포지션이 세로가 되게 하면 나머지가 어떻게 되는지 드러난다.
    func playMixed() {
        var ordered = groups.sorted { lhs, rhs in
            if lhs.rotationDegrees == 90 { return true }
            if rhs.rotationDegrees == 90 { return false }
            return lhs.rotationDegrees < rhs.rotationDegrees
        }
        ordered = ordered.filter { !$0.specs.isEmpty }
        guard ordered.count >= 2 else {
            buildState = "섞을 그룹이 부족하다"
            return
        }
        let picked = ordered.compactMap(\.specs.first)
        build(specs: picked, label: "섞기 \(picked.count)개")
    }

    private func build(specs: [ClipSpec], label: String) {
        tappedAt = Date()
        readyMilliseconds = nil
        buildState = "조립 중 (\(label))"

        Task {
            do {
                let result = try await ClipComposer.compose(specs)
                print("########## 병합 \(label) ##########")
                print(result.report)

                let item = AVPlayerItem(asset: result.composition)
                let player = AVPlayer(playerItem: item)
                self.player = player
                observeReady(item: item, player: player)
                buildState = "조립 완료 (\(label)) transform \(result.appliedDegrees)°"
                    + (result.transformConflicts > 0
                       ? " · 불일치 \(result.transformConflicts)" : "")
                isPlayerPresented = true
            } catch {
                buildState = "조립 실패: \(error)"
                print("MCOMP build-failed \(error)")
            }
        }
    }

    private func observeReady(item: AVPlayerItem, player: AVPlayer) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            MainActor.assumeIsolated {
                guard let self, item.status != .unknown else { return }
                guard self.readyMilliseconds == nil else { return }
                let elapsed = (self.tappedAt.map { Date().timeIntervalSince($0) } ?? 0) * 1000
                self.readyMilliseconds = elapsed
                if item.status == .readyToPlay {
                    print(String(format: "MCOMP ready %.1f ms (탭 → readyToPlay)", elapsed))
                    player.play()
                } else {
                    self.buildState = "재생 실패: \(item.error?.localizedDescription ?? "알 수 없음")"
                    print("MCOMP play-failed \(item.error?.localizedDescription ?? "알 수 없음")")
                }
            }
        }
    }

    func dismissPlayer() {
        player?.pause()
        statusObservation = nil
        player = nil
        isPlayerPresented = false
    }
}
