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

    private(set) var exportState = "-"
    private(set) var exportMilliseconds: Double?

    private var statusObservation: NSKeyValueObservation?
    private var tappedAt: Date?

    /// EXPORT 는 **마지막으로 조립한 컴포지션**에 대해 동작한다.
    /// 다시 조립하지 않으므로 조립 시간이 익스포트 시간에 섞이지 않는다.
    private var lastComposition: AVMutableComposition?
    private var lastSpecs: [ClipSpec] = []
    private var lastDegrees = 0
    private var lastLabel = "-"

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

    /// **측정 전용.** 전 클립을 방향 구분 없이 한 컴포지션에 넣는다.
    ///
    /// 방향이 섞이면 뒤 클립이 강제 회전되므로 화면 판정 대상이 아니다.
    /// 그러나 passthrough 익스포트는 샘플을 복사하는 작업이고 회전은 트랙 매트릭스
    /// 한 줄이라 **처리량 측정은 방향과 무관하게 정확하다.**
    /// 1-19 의 "클립 20개 기준 3초 이내"를 추가 촬영 없이 재기 위한 경로다.
    func playAllForMeasurement() {
        let all = groups.flatMap(\.specs)
        guard all.count > 1 else {
            buildState = "클립이 부족하다"
            return
        }
        build(specs: all, label: "ALL \(all.count)개 (측정 전용)")
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

                lastComposition = result.composition
                lastSpecs = specs
                lastDegrees = result.appliedDegrees
                lastLabel = label

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

    // MARK: 익스포트 (1-17 ~ 1-20)

    func exportCurrent() {
        guard let composition = lastComposition, !lastSpecs.isEmpty else {
            exportState = "먼저 병합해야 한다"
            return
        }
        let specs = lastSpecs
        let degrees = lastDegrees
        let label = lastLabel
        exportState = "익스포트 중 (\(label))"
        exportMilliseconds = nil

        Task {
            let url = ClipExporter.nextExportURL(degrees: degrees, clipCount: specs.count)
            do {
                let result = try await ClipExporter.exportPassthrough(composition, to: url)
                exportMilliseconds = result.milliseconds
                await verifyAndSave(result: result, sources: specs, label: label)
            } catch {
                exportState = "익스포트 실패: \(error.localizedDescription)"
                print("MEXP failed \(label): \(error.localizedDescription)")
            }
        }
    }

    /// 재인코딩이 정말 없었는지 세 가지로 확인하고 사진 앱에 저장한다.
    private func verifyAndSave(result: ClipExporter.Result,
                               sources: [ClipSpec],
                               label: String) async {
        let sourceBytes = sources.compactMap(\.fileSize).reduce(0, +)
        let ratio = sourceBytes > 0 && result.fileSize != nil
            ? Double(result.fileSize!) / Double(sourceBytes)
            : 0
        let sourceSeconds = sources.reduce(0) { $0 + $1.duration }

        print("########## 익스포트 \(label) ##########")
        print(String(format: "MEXP file=%@ 소요=%.0f ms  분량=%.1f s  실시간 대비 %.0f배",
                     result.url.lastPathComponent, result.milliseconds,
                     sourceSeconds, sourceSeconds * 1000 / max(result.milliseconds, 1)))
        print(String(format: "MEXP 크기 %lld B ÷ 소스 합 %lld B = %.4f",
                     result.fileSize ?? 0, sourceBytes, ratio))

        // 스펙 보존 확인. 첫 소스 클립과 대조해 길이·크기 외에 달라진 것이 있는지 본다.
        var specNote = "결과 스펙 읽기 실패"
        if let first = sources.first {
            do {
                var exported = try await ClipSpec.load(from: result.url)
                exported.name = "EXPORT " + exported.name
                print(ClipSpec.compare([first, exported]))
                specNote = "대조 완료"
            } catch {
                print("MEXP spec-load-failed \(error)")
            }
        }

        var saveNote = ""
        do {
            let status = try await PhotoLibrarySaver.save(result.url)
            saveNote = " · 사진 저장 완료(\(status.shortText))"
            print("MEXP saved-to-photos \(result.url.lastPathComponent)")
        } catch {
            saveNote = " · 사진 저장 실패: \(error.localizedDescription)"
            print("MEXP photo-save-failed \(error.localizedDescription)")
        }

        exportState = String(format: "완료 %.2f s · 비율 %.3f · %@%@",
                             result.milliseconds / 1000, ratio, specNote, saveNote)
    }

    func dismissPlayer() {
        player?.pause()
        statusObservation = nil
        player = nil
        isPlayerPresented = false
    }
}
