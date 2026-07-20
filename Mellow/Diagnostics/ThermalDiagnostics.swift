#if DEBUG
import Foundation
import UIKit
import QuartzCore  // CACurrentMediaTime (단조 시계 — MTRACE5)
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

    // MARK: - 프리뷰 프리즈 진단 (onFrame 하트비트 + nextDrawable 스톨)
    /// onFrame 콜백 카운터 — videoQueue(고빈도)에서 증가. NSLock으로 보호(값싼 lock/unlock).
    /// SAMPLE이 직전 샘플 이후 델타를 찍어 "프레임이 아직 도착하는가"를 판별한다.
    private let frameLock = NSLock()
    private var frameCount: UInt64 = 0
    private var lastSampledFrameCount: UInt64 = 0

    // MARK: - MTRACE5 스톨 감지 상태 (텔레메트리 전용)

    /// **폴트 인젝션(검증용):** true면 renderFrame이 drawable 획득 전에 리턴 → 프레임 공급이
    /// 살아 있어도 렌더 커밋이 멈춘 상황을 재현한다. lldb 토글(computed setter를 거치므로 그대로 동작):
    /// `expr ThermalDiagnostics.suppressRenderForTesting = true`
    /// lldb 쓰기와 videoQueue 읽기가 겹치므로 NSLock으로 동기화(무동기화 cross-thread 접근은 UB).
    private static let suppressLock = NSLock()
    private static var _suppressRenderForTesting = false
    static var suppressRenderForTesting: Bool {
        get { suppressLock.lock(); defer { suppressLock.unlock() }; return _suppressRenderForTesting }
        set { suppressLock.lock(); _suppressRenderForTesting = newValue; suppressLock.unlock() }
    }

    /// **폴트 인젝션(검증용):** 0보다 크면 presented-handler hide 본문 전체(세대 검사 포함)를
    /// 이 간격만큼 지연 → 좁은 hide 윈도우를 사람이 freeze를 끼워 넣을 수 있게 벌린다.
    /// stale_hide_skipped 검증용 — suppressRenderForTesting은 렌더 자체를 막아 pending hide가
    /// 생기지 않으므로 이 레이스를 만들 수 없다. lldb 토글:
    /// `expr ThermalDiagnostics.delayPresentedHideForTesting = 3.0` (해제는 0)
    /// lldb 쓰기와 메인 읽기가 겹치므로 suppressLock과 같은 방식으로 NSLock 동기화.
    private static let delayHideLock = NSLock()
    private static var _delayPresentedHideForTesting: TimeInterval = 0
    static var delayPresentedHideForTesting: TimeInterval {
        get { delayHideLock.lock(); defer { delayHideLock.unlock() }; return _delayPresentedHideForTesting }
        set { delayHideLock.lock(); _delayPresentedHideForTesting = newValue; delayHideLock.unlock() }
    }

    /// SAMPLE의 commitAge= 공급자. 커밋 타임스탬프가 production(MetalPreviewView)으로
    /// 승격되어 여기엔 읽기 글루만 남는다. 등록·판독 모두 진단 큐 경유(confined — 잠금 불필요).
    private var commitTimeProvider: (() -> CFTimeInterval)?

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
            // frames = 직전 샘플 이후 onFrame 콜백 수. 프리즈 시 0이면 캡처가 조용해진 것(candidate 1),
            // >0인데 화면이 멈춰 있으면 프레임은 오는데 하류 렌더/nextDrawable이 막힌 것(candidate 2).
            // commitAge = 마지막 렌더 커밋 이후 경과 ms(MTRACE5 수동 가시성 — 별도 타이머 없이
            // 기존 10s 샘플에 편승). frames>0인데 commitAge가 계속 커지면 공급은 사는데 렌더가 죽은 것.
            self.write("SAMPLE thermal=\(thermal) cpu=\(self.cpuPct()) frames=\(self.frameDeltaSinceLastSample()) commitAge=\(self.commitAgeLabel()) mem=\(self.footprintMB())MB activity=\(self.activity)")
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

    // MARK: - 프리뷰 프리즈 진단

    /// onFrame 콜백마다 호출(videoQueue, 렌더 **전에**). 값싼 lock 증가만 — 파일 I/O 없음.
    func recordFrame() {
        frameLock.lock()
        frameCount &+= 1
        frameLock.unlock()
    }

    /// 직전 샘플 이후 프레임 델타(진단 큐의 SAMPLE에서 호출). 읽고 베이스라인 갱신.
    private func frameDeltaSinceLastSample() -> UInt64 {
        frameLock.lock()
        defer { frameLock.unlock() }
        let delta = frameCount &- lastSampledFrameCount
        lastSampledFrameCount = frameCount
        return delta
    }

    // MARK: - MTRACE5 (스톨/복구 EVENT — 커밋 하트비트는 MetalPreviewView로 승격됨)

    /// commitAge= 공급자 등록(Coordinator.attach의 DEBUG 글루에서). 진단 큐로 confined.
    func setCommitTimeProvider(_ provider: @escaping () -> CFTimeInterval) {
        queue.async { self.commitTimeProvider = provider }
    }

    /// 워치독이 스톨을 판정했을 때 1회(arm 사이클당) 기록. 관측만.
    func noteStallDetected(sinceMs: Int, overlayVisible: Bool, armAgeMs: Int) {
        queue.async {
            self.write("MTRACE5 EVENT stall_detected since=\(sinceMs) overlay=\(overlayVisible) armAge=\(armAgeMs) activity=\(self.activity)")
        }
    }

    /// 복구 킥 경로 EVENT(recovery_kick / recovery_gave_up / kick_skipped_interrupted).
    /// 워치독 큐에서 호출 → 진단 큐로.
    func noteRecoveryEvent(_ name: String, attempt: Int) {
        queue.async {
            self.write("MTRACE5 EVENT \(name) attempt=\(attempt) activity=\(self.activity)")
        }
    }

    /// frozen/overlay 갈라짐 레이스 관측: 오래된 presented-handler hide가 새 freeze를 만나
    /// 스킵됐을 때 기록. 메인에서 호출 → 진단 큐로. 관측만.
    func noteStaleHideSkipped() {
        queue.async {
            self.write("MTRACE5 EVENT stale_hide_skipped activity=\(self.activity)")
        }
    }

    /// SAMPLE용 커밋 나이(ms). 커밋이 아직 없으면(또는 공급자 미등록) "-" —
    /// 스톨(큰 값)과 미시작을 구분한다. 진단 큐에서만 호출.
    private func commitAgeLabel() -> String {
        guard let last = commitTimeProvider?(), last > 0 else { return "-" }
        return String(Int((CACurrentMediaTime() - last) * 1000))
    }

    /// nextDrawable()이 nil 반환(≈1s 타임아웃 = drawable 고갈) 시 1회 기록. videoQueue에서 호출 → 진단 큐로.
    func noteDrawableNil() {
        queue.async { self.write("nextDrawable nil (drawable 고갈 의심) activity=\(self.activity)") }
    }

    /// nextDrawable()이 임계(>100ms) 초과로 반환됐을 때 기록(성공 프레임마다 찍지 않음).
    func noteDrawableStall(ms: Double) {
        queue.async { self.write("nextDrawable stalled \(String(format: "%.0f", ms))ms activity=\(self.activity)") }
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
