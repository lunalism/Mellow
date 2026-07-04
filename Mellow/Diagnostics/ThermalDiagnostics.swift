#if DEBUG
import Foundation
import UIKit
import os

/// **열/메모리 진단 계측** (Phase 1 → Phase 2 준비, DEBUG 전용).
///
/// 목적: 하루 종일 테스트하는 동안 **언제 thermalState가 오르는지**와 **메모리가 서서히
/// 새는지**를 항상 켜진 상태로 기록해, 나중에 Instruments로 범인을 좁힐 수 있게 한다.
/// 이건 **최적화가 아니라 관측**이다 — 렌더 파이프라인 동작을 절대 바꾸지 않는다.
///
/// 설계 제약 (IMPORTANT):
/// - 기존 병목은 메인스레드 직렬화(`CA::Transaction::commit`)다. 따라서 이 계측은 **메인스레드에
///   어떤 작업도 추가하지 않는다.** 주기 샘플러는 메인 런루프의 `Timer`가 아니라 전용 시리얼
///   `DispatchQueue` 위의 `DispatchSourceTimer`로 돈다.
/// - **거의 제로 코스트** — 측정을 오염시키면 안 된다. 어떤 핫패스에서도 동기 파일 쓰기 없음.
///   파일 쓰기는 진단 시리얼 큐에서 버퍼링하고 줄마다 `fsync`하지 않는다.
/// - 전부 `#if DEBUG`. 릴리스에 절대 들어가지 않는다.
final class ThermalDiagnostics {
    static let shared = ThermalDiagnostics()

    /// 모든 파일 I/O와 상태 변경이 도는 전용 시리얼 큐. 메인스레드를 건드리지 않는다.
    private let queue = DispatchQueue(label: "com.lunalism.mellow.diagnostics", qos: .utility)

    /// Instruments 상관용 시그포스터.
    let signposter = OSSignposter(subsystem: "com.lunalism.mellow", category: "diagnostics")

    /// 한 번 연 append-only FileHandle. 큐에서만 접근.
    private var fileHandle: FileHandle?

    /// 현재 활동 태그 — 모든 샘플에 붙어 메모리/열 수치에 맥락을 준다. 큐에서만 변경.
    private var activity: String = "idle"

    /// 진행 중 시그포스트 인터벌 상태. 큐에서만 접근 → 스레드 안전.
    /// (겹치는 동종 인터벌은 단일 상태로 합쳐진다 — export/geocode는 상위 가드로 중복이 막혀 있고,
    ///  map 스냅샷의 드문 중첩은 진단 목적상 허용.)
    private var exportState: OSSignpostIntervalState?
    private var mapState: OSSignpostIntervalState?
    private var geocodeState: OSSignpostIntervalState?

    /// 주기 샘플러. 강한 참조 유지.
    private var timer: DispatchSourceTimer?

    /// 라인 프리픽스용 ISO8601 타임스탬프. 큐에서만 써서 스레드 안전.
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    // MARK: - 메모리 풋프린트

    /// phys_footprint — Xcode 메모리 게이지·jetsam이 보는 바로 그 필드.
    func currentMemoryFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    // MARK: - CPU 사용률

    /// 전 스레드(비유휴) 합산 CPU%. 멀티코어에서 100%를 넘을 수 있고 그게 정상 — 지속 CPU=발열.
    func currentCPUUsage() -> Double? {
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threadsList, &threadsCount) == KERN_SUCCESS,
              let threads = threadsList else { return nil }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: threads)),
                          vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        }
        var total: Double = 0
        for i in 0..<Int(threadsCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if kr == KERN_SUCCESS, (info.flags & TH_FLAGS_IDLE) == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        return total
    }

    // MARK: - 시작

    /// 앱 런치 시 1회 호출. 헤더 기록 → 열 상태 변화 구독 → 10초 주기 샘플러 시작.
    func start() {
        queue.async {
            self.openLogFile()
            let device = Self.deviceModel()
            let os = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
            let thermal = ProcessInfo.processInfo.thermalState.mellowLabel
            self.write("HEADER device=\(device) os=\(os) thermal=\(thermal) mem=\(self.footprintMB())MB")
        }

        // 열 상태 변화 구독. 핸들러는 값싸게 — 임의 큐에서 올 수 있으니 즉시 진단 큐로 넘긴다.
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                let thermal = ProcessInfo.processInfo.thermalState.mellowLabel
                self.write("THERMAL \(thermal) mem=\(self.footprintMB())MB activity=\(self.activity)")
            }
        }

        // 주기 샘플러 — 메인 런루프가 아니라 진단 큐의 DispatchSourceTimer.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let thermal = ProcessInfo.processInfo.thermalState.mellowLabel
            self.write("SAMPLE thermal=\(thermal) cpu=\(self.cpuPct()) mem=\(self.footprintMB())MB activity=\(self.activity)")
        }
        self.timer = timer
        timer.resume()
    }

    // MARK: - 활동 태그

    /// 현재 활동 태그를 갱신(진단 큐에서). 이후 샘플·이벤트에 이 맥락이 붙는다.
    func setActivity(_ a: String) {
        queue.async {
            guard self.activity != a else { return }
            self.activity = a
            self.write("ACTIVITY \(a) mem=\(self.footprintMB())MB")
        }
    }

    // MARK: - 시그포스트 인터벌 (의심 버스트 3종)

    func beginExport() {
        queue.async {
            self.exportState = self.signposter.beginInterval("Export", id: self.signposter.makeSignpostID())
            self.write("export begin mem=\(self.footprintMB())MB")
        }
    }

    func endExport() {
        queue.async {
            guard let state = self.exportState else { return }
            self.signposter.endInterval("Export", state)
            self.exportState = nil
            self.write("export end mem=\(self.footprintMB())MB")
        }
    }

    func beginMapSnapshot() {
        queue.async {
            self.mapState = self.signposter.beginInterval("MapSnapshot", id: self.signposter.makeSignpostID())
            self.write("mapSnapshot begin mem=\(self.footprintMB())MB")
        }
    }

    func endMapSnapshot() {
        queue.async {
            guard let state = self.mapState else { return }
            self.signposter.endInterval("MapSnapshot", state)
            self.mapState = nil
            self.write("mapSnapshot end mem=\(self.footprintMB())MB")
        }
    }

    func beginGeocode() {
        queue.async {
            self.geocodeState = self.signposter.beginInterval("Geocode", id: self.signposter.makeSignpostID())
            self.write("geocode begin mem=\(self.footprintMB())MB")
        }
    }

    func endGeocode() {
        queue.async {
            guard let state = self.geocodeState else { return }
            self.signposter.endInterval("Geocode", state)
            self.geocodeState = nil
            self.write("geocode end mem=\(self.footprintMB())MB")
        }
    }

    // MARK: - Private (전부 진단 큐에서만 실행)

    private func openLogFile() {
        let stamp = Self.fileStamp()
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("mellow_diag_\(stamp).log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: url)
        _ = try? fileHandle?.seekToEnd()
    }

    /// 한 줄 append. **진단 큐에서만** 호출. 줄마다 fsync 없음(핸들 버퍼).
    private func write(_ line: String) {
        guard let handle = fileHandle else { return }
        let stamped = isoFormatter.string(from: Date()) + " " + line + "\n"
        guard let data = stamped.data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
    }

    private func footprintMB() -> String {
        guard let bytes = currentMemoryFootprint() else { return "?" }
        return String(format: "%.1f", Double(bytes) / 1_048_576)
    }

    private func cpuPct() -> String {
        guard let pct = currentCPUUsage() else { return "?%" }
        return String(format: "%.1f%%", pct)
    }

    private static func deviceModel() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }

    private static func fileStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}

// MARK: - 열 상태 라벨

extension ProcessInfo.ThermalState {
    var mellowLabel: String {
        switch self {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
#endif
