import Foundation

// 저장 한 번을 구간별로 나눠 잰 값 (1-18 에서 만들고 1-19 에서 쓴다).
//
// 1-19 의 게이트는 "클립 20개 기준 3초 이내"인데, 총합만 재면 초과했을 때
// 어디를 손봐야 하는지 알 수 없다. 세 구간의 성격이 전혀 다르기 때문이다.
//
//   병합    — 파일을 쓰지 않는다. 편집 목록 구성뿐이라 클립 수에 비례한다
//   익스포트 — passthrough 면 바이트당 비용이고 디스크 속도가 지배한다
//   저장    — 사진 앱 프로세스로 넘어간다. 우리가 줄일 수 있는 구간이 아니다
//
// CaptureTrace 와 같은 스위치를 쓴다. 실행 인자 `-MellowTrace` 로 켠다.
struct SaveTimings: Equatable {
    var clipCount = 0
    /// 권한이 정해질 때까지 기다린 시간. **총합에 넣지 않는다.**
    ///
    /// 미결정 상태의 첫 저장은 시스템 팝업을 띄우고 사용자가 누를 때까지
    /// 기다린다. 실측 22.7초였고, 그게 저장 구간 안에 있으면 다른 값이 전부
    /// 묻힌다. 두 번째부터는 0에 가깝다 — 사람이 개입하지 않기 때문이다.
    var permissionWait: TimeInterval = 0
    var merge: TimeInterval = 0
    var export: TimeInterval = 0
    var photoLibrary: TimeInterval = 0
    var total: TimeInterval = 0
    /// 익스포트 결과 파일 크기. 익스포트 구간을 바이트당 비용으로 환산할 때 쓴다.
    var exportedBytes: Int64 = 0
    /// 병합된 컴포지션의 재생 길이. 실시간 대비 배수를 내는 기준이다.
    var compositionSeconds: Double = 0
    /// 파일을 복사했는지 옮겼는지 (shouldMoveFile).
    var movedFile = false

    /// 사람이 읽는 한 줄 요약. 화면에도 이 형식으로 보여준다.
    var summary: String {
        String(format: "병합 %.0fms · 익스포트 %.0fms · 저장 %.0fms · 합계 %.0fms",
               merge * 1000, export * 1000, photoLibrary * 1000, total * 1000)
    }

    func log() {
        guard CaptureTrace.isEnabled else { return }

        print("[trace] ▶ 사진 앱 저장  클립 \(clipCount)개"
              + String(format: "  영상 %.3fs", compositionSeconds)
              + "  \(movedFile ? "이동" : "복사")")
        // 총합 밖이라 비율을 붙이지 않는다.
        if permissionWait > 0.001 {
            print("[trace]   권한 대기(총합 제외)  "
                  + String(format: "%8.1fms", permissionWait * 1000))
        }
        line("병합 (컴포지션 구성)", merge)
        line("익스포트 (passthrough)", export)
        line("사진 앱 저장", photoLibrary)
        line("합계", total)

        if exportedBytes > 0 {
            let megabytes = Double(exportedBytes) / 1_000_000
            print("[trace]   출력 " + String(format: "%.2fMB", megabytes)
                  + (export > 0
                     ? String(format: "  익스포트 %.0fMB/s", megabytes / export)
                     : ""))
        }
        if compositionSeconds > 0 {
            print("[trace]   실시간 대비 " + String(format: "%.4f배", total / compositionSeconds))
        }
        if clipCount > 0 {
            print("[trace]   클립당 " + String(format: "%.1fms", total * 1000 / Double(clipCount)))
        }
    }

    /// 라운드를 여러 번 돌릴 때 회차별로 느려지는지 보려고 붙인다.
    /// Mac 에서 같은 출력 디렉터리에 큰 파일을 쌓으며 반복했더니 30클립
    /// 익스포트가 817ms → 2194ms 로 밀렸다(1-17). 실기기에서도 나오는지 본다.
    var compact: String {
        String(format: "%.0f/%.0f/%.0f=%.0fms",
               merge * 1000, export * 1000, photoLibrary * 1000, total * 1000)
    }

    private func line(_ label: String, _ seconds: TimeInterval) {
        let width = 24
        let padded = label.count < width
            ? label + String(repeating: " ", count: width - label.count)
            : label
        let share = total > 0 ? seconds / total * 100 : 0
        print("[trace]   \(padded)" + String(format: "%8.1fms  %5.1f%%", seconds * 1000, share))
    }
}

// 단일 클립 재인코딩 한 번의 측정값 (1-19 준비, 1-18 에서 만들어 둔다).
//
// 세션 방향 모델 선택지 (c) "촬영 직후 단일 클립 정규화"의 실현 가능성이
// 이 값에 걸려 있다. 촬영이 끝날 때마다 클립 하나를 정방향으로 다시 굽는
// 방식인데, 그 비용이 촬영 흐름을 끊지 않는 수준인지가 판단 기준이다.
//
// Mac M2 에서 9.96초 클립이 1553ms 였다(1-17 B-2). 실기기 값은 미측정이다.
struct ReencodeMeasurement: Equatable {
    var clipSeconds: Double = 0
    var elapsed: TimeInterval = 0
    var outputBytes: Int64 = 0

    /// 영상 길이 대비 배수. Mac M2 는 0.156배였다.
    var realtimeRatio: Double { clipSeconds > 0 ? elapsed / clipSeconds : 0 }

    var summary: String {
        String(format: "%.0fms  (영상 %.2fs 대비 %.3f배)",
               elapsed * 1000, clipSeconds, realtimeRatio)
    }

    func log() {
        guard CaptureTrace.isEnabled else { return }
        print("[trace] ▶ 단일 클립 재인코딩 (AVAssetExportPreset1920x1080)")
        print("[trace]   영상 길이  " + String(format: "%.3fs", clipSeconds))
        print("[trace]   소요      " + String(format: "%.1fms", elapsed * 1000))
        print("[trace]   실시간 대비 " + String(format: "%.4f배", realtimeRatio))
        if outputBytes > 0 {
            let megabytes = Double(outputBytes) / 1_000_000
            print("[trace]   출력      " + String(format: "%.2fMB", megabytes)
                  + (elapsed > 0 ? String(format: "  %.0fMB/s", megabytes / elapsed) : ""))
        }
    }
}

// 방향 교정 재인코딩 한 번의 측정값 (1-21).
//
// 세션 방향 모델을 정하는 마지막 값이다. 1-19 에서 단일 클립 재인코딩이
// 실기기 96ms 로 나와 Mac 환산(1553ms)이 16배 틀렸음이 드러났는데,
// 그 96ms 는 videoComposition 이 없는 단순 재인코딩이었다. 방향 교정은
// AVMutableVideoComposition 을 붙이므로 같은 하드웨어 경로를 타는지가
// 확인되지 않았다. 그 배수가 여기서 나온다.
struct OrientationFixMeasurement: Equatable {
    var clipCount = 0
    var compositionSeconds: Double = 0
    var elapsed: TimeInterval = 0
    var outputBytes: Int64 = 0
    /// 출력 비디오 트랙의 estimatedDataRate (bps). Mac 에서는 원본의 68.2% 로 떨어졌다.
    var outputDataRate: Float = 0
    /// 입력 클립들의 estimatedDataRate 평균 (bps).
    var inputDataRate: Float = 0
    /// renderSize. 계열 내 교정이면 모든 클립이 여기에 정확히 들어차야 한다.
    var renderSize: CGSize = .zero
    /// 캔버스와 규격이 어긋난 클립 수. 0 이 아니면 여백이 생긴다.
    var canvasMismatches = 0

    var realtimeRatio: Double { compositionSeconds > 0 ? elapsed / compositionSeconds : 0 }
    /// 1-19 실측 단일 클립 재인코딩 96ms 대비 배수. 클립 수를 맞춰 비교한다.
    var perClipMilliseconds: Double { clipCount > 0 ? elapsed * 1000 / Double(clipCount) : 0 }
    var dataRateRatio: Double {
        inputDataRate > 0 ? Double(outputDataRate) / Double(inputDataRate) : 0
    }

    var summary: String {
        String(format: "%.0fms  클립당 %.0fms  실시간 %.3f배  비트레이트 %.1f%%",
               elapsed * 1000, perClipMilliseconds, realtimeRatio, dataRateRatio * 100)
    }

    func log() {
        guard CaptureTrace.isEnabled else { return }
        print("[trace] ▶ 방향 교정 재인코딩 (videoComposition + Preset1920x1080)")
        print("[trace]   클립       \(clipCount)개"
              + String(format: "  영상 %.3fs", compositionSeconds))
        print("[trace]   renderSize \(Int(renderSize.width))x\(Int(renderSize.height))"
              + "  캔버스 어긋남 \(canvasMismatches)개"
              + (canvasMismatches == 0 ? " (여백 없음)" : " ← 여백 발생"))
        print("[trace]   소요       " + String(format: "%.1fms", elapsed * 1000))
        print("[trace]   클립당     " + String(format: "%.1fms", perClipMilliseconds)
              + "  ※ 단일 클립 단순 재인코딩 96ms 와 대조 (1-19)")
        print("[trace]   실시간 대비 " + String(format: "%.4f배", realtimeRatio))
        print("[trace]   비트레이트  "
              + String(format: "%.3f → %.3fMbps  (%.1f%%)",
                       inputDataRate / 1_000_000, outputDataRate / 1_000_000,
                       dataRateRatio * 100)
              + "  ※ Mac 에서는 68.2%")
        if outputBytes > 0 {
            print("[trace]   출력       "
                  + String(format: "%.2fMB", Double(outputBytes) / 1_000_000))
        }
    }
}
