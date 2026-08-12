import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

// 클립 **하나**를 정규화한 한 번의 측정값 (B 라운드).
//
// 1-21 은 4클립을 한 번에 교정한 9125ms 를 4로 나눠 클립당 2281ms 를 냈다.
// 실제 시나리오는 클립 하나가 단독으로 도는 것이라 조건이 다르다.
//
//   (1) 익스포트 세션 생성·videoComposition 구성·인코더 초기화는 익스포트당
//       한 번인데 1-21 에서는 4클립에 희석됐다. 단독이면 혼자 문다
//   (2) 1-21 측정 중에는 카메라가 돌지 않았다. 실제로는 촬영 화면에 머문 채
//       AVCaptureSession 이 running 인 상태에서 인코딩이 돈다
//   (3) 연속 촬영 시의 발열이 반영되지 않았다
//
// 세 요인 전부 느려지는 쪽으로만 작용한다. 2281ms 는 낙관적 하한이다.
//
// 이 측정이 필요한 이유: 정규화가 10초를 넘으면 촬영 사이클보다 길어져 큐가
// 쌓인다. 그러면 취소 정책·우선순위가 필요해지고 정규화 태스크의 규모 자체가
// 달라진다. 쌓이는지 여부가 Phase 2 태스크 구조를 가른다.
//
// 3-13 에서 걷어낸다.
struct NormalizeMeasurement: Equatable {

    /// 1-21 실측 클립당 비용(ms). 이 값 대비 배수가 이 라운드의 핵심 수치다.
    static let baseline1_21: Double = 2281

    var round = 0
    /// 측정 중 AVCaptureSession 이 running 이었는지. B-1 / B-2 를 가른다.
    var cameraRunning = false
    var clipName = ""

    // MARK: - 구간

    /// 컴포지션 구성 + videoComposition 구성 + 스냅샷. 클립 길이와 무관한 고정비.
    var prepare: TimeInterval = 0
    /// ClipExporter.export — 익스포트 세션 생성과 인코딩이 여기 함께 들어 있다.
    /// 둘을 밖에서 가를 수 없다. 세션 생성 자체는 싸고, 인코더 초기화가 고정비의
    /// 본체인데 그건 export(to:as:) 안에서 일어난다.
    var export: TimeInterval = 0
    /// FileManager.replaceItemAt 으로 원본 자리에 넣는 구간.
    var replace: TimeInterval = 0

    var total: TimeInterval { prepare + export + replace }

    // MARK: - B-4 duration 대조

    /// 정규화 **전** 애셋 duration.
    var beforeDuration: CMTime = .zero
    /// 정규화 **후** 애셋 duration.
    var afterDuration: CMTime = .zero
    var beforeVideoDuration: CMTime?
    var afterVideoDuration: CMTime?
    var beforeAudioDuration: CMTime?
    var afterAudioDuration: CMTime?

    /// 후 - 전. 양수면 길어진 것이다.
    var durationDelta: Double {
        CMTimeGetSeconds(afterDuration) - CMTimeGetSeconds(beforeDuration)
    }

    // MARK: - 출력

    var outputBytes: Int64 = 0
    var inputDataRate: Float = 0
    var outputDataRate: Float = 0
    var renderSize: CGSize = .zero
    /// 원본 preferredTransform. 어느 방향의 클립을 잰 값인지 이걸로 구분한다.
    var sourceTransform: CGAffineTransform = .identity

    // MARK: - B-3 발열

    var thermalBefore: ProcessInfo.ThermalState = .nominal
    var thermalAfter: ProcessInfo.ThermalState = .nominal

    // MARK: - 파생

    var clipSeconds: Double { CMTimeGetSeconds(beforeDuration) }
    var realtimeRatio: Double { clipSeconds > 0 ? total / clipSeconds : 0 }
    /// 1-21 클립당 2281ms 대비 배수.
    var baselineRatio: Double { total * 1000 / Self.baseline1_21 }
    /// prepare + replace 가 총합에서 차지하는 비율. 고정비의 크기.
    var fixedCostShare: Double { total > 0 ? (prepare + replace) / total : 0 }
    var dataRateRatio: Double {
        inputDataRate > 0 ? Double(outputDataRate) / Double(inputDataRate) : 0
    }

    /// 세로 계열인지 가로 계열인지. renderSize 로 판정한다 — 어느 방향의 클립을
    /// 잰 값인지 화면에서 바로 구분돼야 세로·가로 기록이 섞이지 않는다.
    var orientationLabel: String {
        renderSize.width < renderSize.height ? "세로" : "가로"
    }

    /// 화면 한 줄. 회차별 추이를 눈으로 본다.
    var compact: String {
        String(format: "%d) %.0f/%.0f/%.0f=%.0fms ×%.2f %@",
               round, prepare * 1000, export * 1000, replace * 1000, total * 1000,
               baselineRatio, Self.describe(thermalAfter))
    }

    var summary: String {
        String(format: "%.0fms  (구성 %.0f · 익스포트 %.0f · 교체 %.0f)  1-21 대비 %.2f배",
               total * 1000, prepare * 1000, export * 1000, replace * 1000, baselineRatio)
    }

    func log() {
        guard CaptureTrace.isEnabled else { return }

        print("[trace] ▶ 단일 클립 정규화 \(round)회차"
              + "  카메라 \(cameraRunning ? "running" : "stopped")"
              + "  \(clipName)")
        print("[trace]   원본 transform \(ClipSpec.describe(transform: sourceTransform))"
              + "  renderSize \(Int(renderSize.width))x\(Int(renderSize.height))")
        line("구성 (컴포지션+VC)", prepare)
        line("익스포트", export)
        line("파일 교체", replace)
        line("합계", total)
        print("[trace]   고정비 비중 "
              + String(format: "%.1f%%  (구성+교체 %.1fms)",
                       fixedCostShare * 100, (prepare + replace) * 1000))
        print("[trace]   1-21 클립당 2281ms 대비 "
              + String(format: "%.2f배", baselineRatio))
        print("[trace]   실시간 대비 " + String(format: "%.4f배", realtimeRatio))

        // B-4. 소수점 이하까지 본다. 값이 달라지면 Clip.duration 갱신 문제가 생긴다.
        print("[trace]   duration  전 \(Self.precise(beforeDuration))"
              + "  후 \(Self.precise(afterDuration))"
              + String(format: "  차이 %+.6fs", durationDelta))
        if let before = beforeVideoDuration, let after = afterVideoDuration {
            print("[trace]     video   전 \(Self.precise(before))  후 \(Self.precise(after))")
        }
        if let before = beforeAudioDuration, let after = afterAudioDuration {
            print("[trace]     audio   전 \(Self.precise(before))  후 \(Self.precise(after))")
        }

        if outputBytes > 0 {
            print("[trace]   출력 "
                  + String(format: "%.2fMB", Double(outputBytes) / 1_000_000))
        }
        if inputDataRate > 0 {
            print("[trace]   비트레이트 "
                  + String(format: "%.3f → %.3fMbps  (%.1f%%)",
                           inputDataRate / 1_000_000, outputDataRate / 1_000_000,
                           dataRateRatio * 100)
                  + "  ※ 1-21 은 97.0%")
        }
        print("[trace]   thermal \(Self.describe(thermalBefore)) → \(Self.describe(thermalAfter))")
    }

    private func line(_ label: String, _ seconds: TimeInterval) {
        let width = 20
        let padded = label.count < width
            ? label + String(repeating: " ", count: width - label.count)
            : label
        let share = total > 0 ? seconds / total * 100 : 0
        print("[trace]   \(padded)" + String(format: "%8.1fms  %5.1f%%", seconds * 1000, share))
    }

    /// 초 단위 소수점 6자리 + 원본 유리수. 반올림에 묻히는 차이를 놓치지 않는다.
    static func precise(_ time: CMTime) -> String {
        guard time.isNumeric else { return "invalid" }
        return String(format: "%.6fs", CMTimeGetSeconds(time))
            + " (\(time.value)/\(time.timescale))"
    }

    static func describe(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }
}

// 여러 회차를 묶어 본 결과. 중앙값과 회차별 추이가 필요한 값이다.
struct NormalizeRunSummary {
    let rounds: [NormalizeMeasurement]

    var medianTotal: TimeInterval {
        let sorted = rounds.map(\.total).sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    /// 1회차는 따로 본다. 캐시·인코더 워밍업이 여기 몰린다.
    var firstTotal: TimeInterval { rounds.first?.total ?? 0 }
    var lastTotal: TimeInterval { rounds.last?.total ?? 0 }
    /// 마지막 / 첫 회차. 1보다 크면 회차가 갈수록 느려진 것이다.
    var drift: Double { firstTotal > 0 ? lastTotal / firstTotal : 0 }

    func log(title: String) {
        guard CaptureTrace.isEnabled, !rounds.isEmpty else { return }
        print("[trace] ══ \(title)  \(rounds.count)회")
        for round in rounds {
            print("[trace]   \(round.compact)")
        }
        print("[trace]   중앙값 " + String(format: "%.0fms", medianTotal * 1000)
              + String(format: "  (1-21 대비 %.2f배)",
                       medianTotal * 1000 / NormalizeMeasurement.baseline1_21))
        print("[trace]   1회차 " + String(format: "%.0fms", firstTotal * 1000)
              + "  마지막 " + String(format: "%.0fms", lastTotal * 1000)
              + String(format: "  (%.2f배)", drift))
        print("[trace]   10초 사이클 대비 "
              + (medianTotal > 10
                 ? "초과 — 큐가 쌓인다"
                 : String(format: "%.1f%% — 여유 %.1fs",
                          medianTotal / 10 * 100, 10 - medianTotal)))
    }
}
