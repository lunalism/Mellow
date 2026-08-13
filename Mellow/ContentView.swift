import SwiftUI
import SwiftData
import CoreMedia
import UIKit

// 1-1 / 1-2 확인용 화면. 프리뷰와 디버그 오버레이만 있다.
// 녹화 버튼은 1-4 에서 붙인다.
struct ContentView: View {
    @StateObject private var controller = CaptureSessionController()
    @StateObject private var saver = SaveToPhotosController()
    @StateObject private var normalizer = ClipNormalizeController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPreview = false

    // 2-2 저장 확인용. 메인 컨텍스트만 쓴다 — 별도 컨텍스트를 만들지 않는다.
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.createdAt, order: .reverse) private var sessions: [Session]
    @State private var probeNote: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch controller.setupState {
            case .configured:
                CameraPreviewView(session: controller.session) { layer in
                    controller.attach(previewLayer: layer)
                }
                .ignoresSafeArea()

                debugOverlay
                controls

            case .permissionBlocked:
                permissionMessage

            case .failed(let reason):
                message(title: "카메라를 시작할 수 없습니다", detail: reason)

            case .idle:
                ProgressView()
                    .tint(.white)
            }

            // switch 밖에 둔다 — 시뮬레이터에는 카메라가 없어 setupState 가
            // .configured 로 가지 않는다. 저장 확인은 카메라와 무관해야 한다.
            storeProbe
        }
        .fullScreenCover(isPresented: $showingPreview) {
            PreviewScreen(urls: controller.recordedURLs) {
                showingPreview = false
            }
        }
        .task {
            CaptureTrace.shared.begin("최초 실행 (.task)")
            // 구성이 끝나는 시점에 세션을 시작해도 되는 상태인지 컨트롤러가 알아야 한다.
            controller.setSceneActive(scenePhase == .active)
            await controller.prepare()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                CaptureTrace.shared.begin("scenePhase → .active")
                controller.setSceneActive(true)
            case .background:
                CaptureTrace.shared.begin("scenePhase → .background")
                controller.setSceneActive(false)
            case .inactive:
                // 권한 팝업·제어 센터·알림 배너에서도 발생한다. 여기서 끄면 깜빡인다.
                break
            @unknown default:
                break
            }
        }
    }

    // MARK: - 디버그 오버레이

    // 0-6 에서 앱을 Portrait 로 잠갔다. 그 전제가 맞는지 확인하는 화면이다.
    // 폰을 눕혔을 때 capture 각도가 실제로 변하면 전제가 성립한다.
    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("preview 각도", Self.describe(angle: controller.previewRotationAngle))
            row("capture 각도", Self.describe(angle: controller.captureRotationAngle))
            row("기기 방향", Self.describe(orientation: controller.deviceOrientation))
            row("세션", controller.isRunning ? "running" : "stopped")
            row("녹화", controller.isRecording ? "● recording" : "idle")
            row("클립", "\(controller.recordedURLs.count)개")
            if let outcome = controller.lastOutcome {
                row("직전", Self.describe(outcome: outcome))
            }
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 저장 확인 (2-2)

    // SwiftData 가 실제로 살아남는지 눈으로 보는 자리다. 게이트 2의
    // "앱을 강제 종료했다 켜도 세션과 클립이 그대로 남아 있다" 를 미리 본다.
    //
    // 3-13 에서 다른 측정 버튼과 함께 지운다. 그때까지 남기는 이유는
    // 2-3(파일 관리자) 이후로도 세션이 제대로 쌓이는지 확인할 자리가
    // 필요하기 때문이다. 홈 화면은 3-8 에서 만든다.
    private var storeProbe: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("세션 \(sessions.count)개")
                .font(.system(.footnote, design: .monospaced))

            // 최근 3개만. 목록 화면이 아니라 살아남았는지 보는 자리다.
            ForEach(sessions.prefix(3)) { session in
                Text(verbatim: "\(session.title) · \(session.clips.count)컷 · "
                     + Self.describe(session.orientationState))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let note = probeNote {
                Text(verbatim: note)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.yellow.opacity(0.8))
            }

            HStack(spacing: 8) {
                Button {
                    // 2-6 이 아니다. 디렉터리까지 만들어 둬야 클립을 받을 수 있다.
                    let session = Session(title: Self.probeTitle())
                    do {
                        try SessionFileStore.shared.createSessionDirectory(session.id)
                        modelContext.insert(session)
                        probeNote = nil
                    } catch {
                        probeNote = "세션 디렉터리 실패: \(error)"
                    }
                } label: {
                    pill("세션 +1")
                }

                // 2-4 확인용. 자동 연결은 2-6·2-7 이 들어와야 성립한다.
                Button {
                    Task { await saveLastClipToNewestSession() }
                } label: {
                    pill("클립 저장")
                }
                .disabled(sessions.isEmpty || controller.recordedURLs.isEmpty)

                Button {
                    for session in sessions {
                        try? SessionFileStore.shared.removeSessionDirectory(session.id)
                        modelContext.delete(session)
                    }
                    probeNote = nil
                } label: {
                    pill("전부 삭제")
                }
                .disabled(sessions.isEmpty)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    /// 마지막으로 찍은 클립을 최신 세션에 저장한다 (2-4 확인용).
    ///
    /// **duration 은 파일에서 읽는다.** 버튼을 누른 시간이 아니다 (1-7).
    /// 1초 미만 폐기는 컨트롤러가 이미 걸러내므로 여기까지 오지 않는다.
    private func saveLastClipToNewestSession() async {
        guard let session = sessions.first,
              let source = controller.recordedURLs.last else { return }
        do {
            let spec = try await ClipSpec.load(from: source)
            let clip = try ClipStore(context: modelContext)
                .save(clipAt: source,
                      duration: CMTimeGetSeconds(spec.duration),
                      to: session)
            controller.forgetRecorded(source)
            probeNote = String(format: "저장 order=%d %.3fs", clip.order, clip.duration)
        } catch {
            probeNote = "저장 실패: \(error)"
        }
    }

    private static func probeTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static func describe(_ state: Session.OrientationState) -> String {
        switch state {
        case .unset: return "미정"
        case .missing: return "방향 없음(손상)"
        case .decided(let orientation): return orientation.rawValue
        case .corrupted(let raw): return "손상(\(raw))"
        }
    }

    // MARK: - 임시 컨트롤

    // Phase 1 확인용. UI 는 3-3 에서 제대로 만든다.
    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    Task { await controller.reportRecordedComparison() }
                } label: {
                    pill("전체 비교 (\(controller.recordedURLs.count))")
                }
                .disabled(controller.recordedURLs.isEmpty)

                // 1-13 확인용 임시 동선. 제대로 된 화면은 3-12 에서 만든다.
                Button {
                    showingPreview = true
                } label: {
                    pill("미리보기 (\(controller.recordedURLs.count))")
                }
                .disabled(controller.recordedURLs.isEmpty)
            }

            saveControls
            normalizeControls

            // 탭하면 녹화 시작, 10초에 자동 정지, 그전에 끊고 싶으면 다시 탭 (1-6).
            //
            // 뷰에는 녹화 상태를 두지 않는다. 시작/정지 판단은 전부 컨트롤러의
            // 의도가 하고, 여기서는 탭이 일어났다는 사실만 넘긴다.
            Button {
                controller.toggleRecording()
            } label: {
                Circle()
                    .fill(controller.isRecordingRequested ? .red : .white)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 4).padding(-6))
            }
        }
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - 사진 앱 저장 (1-18)

    // 1-18 확인용 임시 동선. 저장 화면은 3-13 에서 만든다.
    //
    // "파일 이동" 토글은 UI 가 아니라 계측 장치다. shouldMoveFile 을 켜고 끈 값을
    // 실기기에서 둘 다 재려고 열어뒀다. 판단이 끝나면 지운다.
    private var saveControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    Task { await saver.save(clips: controller.recordedURLs) }
                } label: {
                    pill("사진 앱에 저장 (\(controller.recordedURLs.count))")
                }
                .disabled(controller.recordedURLs.isEmpty || saver.state.isBusy)

                Button {
                    saver.moveFile.toggle()
                } label: {
                    pill(saver.moveFile ? "이동" : "복사")
                }
                .disabled(saver.state.isBusy)

                // 1-19 준비. 세션 방향 모델 선택지 (c) 판단에 이 값이 필요하다.
                // 사진 앱에 넣지 않고 재인코딩 비용만 잰다.
                Button {
                    Task { await saver.reencodeLastClip(controller.recordedURLs) }
                } label: {
                    pill("재인코딩 1개")
                }
                .disabled(controller.recordedURLs.isEmpty || saver.state.isBusy)

                // 1-21. 방향이 섞인 클립을 하나의 캔버스에 정방향으로 세운다.
                // 결과는 사진 앱에 넣는다 — 정방향인지는 눈으로 봐야 한다.
                Button {
                    Task { await saver.fixOrientationAndSave(clips: controller.recordedURLs) }
                } label: {
                    pill("방향 교정")
                }
                .disabled(controller.recordedURLs.count < 2 || saver.state.isBusy)
            }

            // 진행 중 / 완료 / 실패를 한 줄로. 실패 사유는 줄여 쓰지 않는다.
            Group {
                switch saver.state {
                case .idle:
                    if !saver.permission.isAuthorized && saver.permission != .undetermined {
                        Text(Self.describe(photoPermission: saver.permission))
                            .foregroundStyle(.orange)
                    }
                case .askingPermission, .merging, .exporting, .saving,
                     .reencoding, .fixingOrientation:
                    Text("\(saver.state.label)…  \(saver.timings.summary)")
                        .foregroundStyle(.white)
                case .saved(let timings):
                    Text("✓ 저장 완료  \(timings.summary)")
                        .foregroundStyle(.green)
                case .reencoded(let measurement):
                    Text("✓ 재인코딩  \(measurement.summary)")
                        .foregroundStyle(.green)
                case .orientationFixed(let measurement):
                    Text("✓ 방향 교정  \(measurement.summary)"
                         + (measurement.canvasMismatches == 0 ? "  여백 없음"
                            : "  ← 여백 \(measurement.canvasMismatches)개"))
                        .foregroundStyle(measurement.canvasMismatches == 0 ? .green : .orange)
                case .failed(let message):
                    Text("✕ \(message)")
                        .foregroundStyle(.red)
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)

            // 회차별로 느려지는지 눈으로 본다 (1-19). 형식은 병합/익스포트/저장=합계.
            if !saver.roundHistory.isEmpty {
                Text(saver.roundHistory.suffix(6).joined(separator: "  "))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - 단일 클립 정규화 측정 (B 라운드)

    // 1-21 의 클립당 2281ms 는 4클립을 한 번에 교정한 값을 나눈 것이라
    // 낙관적 하한이다. 실제 시나리오는 클립 하나가 단독으로, 카메라가 도는
    // 상태에서 정규화되는 것이다. 그 값을 재는 임시 동선이며 3-13 에서 지운다.
    //
    // "카메라" 버튼은 UI 가 아니라 측정 조건 스위치다. 세션을 멈춘 채로
    // 재면 B-1, 프리뷰가 살아 있는 채로 재면 B-2 다.
    private var normalizeControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // 녹화 중에는 누를 수 없다. 컨트롤러는 세션을 멈추기 전에
                // stopRecording() 을 먼저 부르도록 요구하는데(setSceneActive 참고),
                // 여기서 stop() 을 바로 부르면 그 순서를 건너뛰어 녹화 중이던
                // 파일이 온전하지 않게 된다. 순서를 흉내내는 대신 상황 자체를
                // 막는다 — stopRecording() 은 비동기라 같은 큐에 stop() 을 바로
                // 얹으면 파일 마무리 전에 세션이 멈출 수 있고(2-15), 3-13 에서
                // 지울 측정 버튼 때문에 그 경로를 한 군데 더 늘릴 이유가 없다.
                //
                // isRecording 과 의도를 함께 본다. 탭 직후 콜백이 오기 전
                // (.starting) 구간은 isRecording 이 아직 false 다.
                Button {
                    if controller.isRunning { controller.stop() } else { controller.start() }
                } label: {
                    pill(controller.isRunning ? "카메라 정지" : "카메라 시작")
                }
                .disabled(normalizer.state.isBusy
                          || controller.isRecording
                          || controller.isRecordingRequested)

                // B-1 / B-2. 마지막 클립 하나를 3회 정규화한다.
                Button {
                    Task {
                        await normalizer.measureRepeat(controller.recordedURLs,
                                                       cameraRunning: controller.isRunning)
                    }
                } label: {
                    pill("정규화 ×3")
                }
                .disabled(controller.recordedURLs.isEmpty || normalizer.state.isBusy)

                // B-3. 마지막 4개를 연속으로. 발열 추이를 본다.
                Button {
                    Task {
                        await normalizer.measureSequence(controller.recordedURLs,
                                                         cameraRunning: controller.isRunning)
                    }
                } label: {
                    pill("연속 4개")
                }
                .disabled(controller.recordedURLs.count < 4 || normalizer.state.isBusy)

                // B-5. 교체가 성립하는지, 실패 시 원본이 살아남는지.
                Button {
                    Task { await normalizer.checkReplace(controller.recordedURLs) }
                } label: {
                    pill("교체 확인")
                }
                .disabled(controller.recordedURLs.isEmpty || normalizer.state.isBusy)

                // 조건을 바꿔 처음부터 다시 잴 때. 앱을 재실행하지 않고
                // 세로 다음 가로를 재는 경우가 있다.
                Button {
                    normalizer.clearHistory()
                } label: {
                    pill("기록 지우기")
                }
                .disabled(normalizer.history.isEmpty || normalizer.state.isBusy)
            }

            Group {
                switch normalizer.state {
                case .idle:
                    EmptyView()
                case .running(let label):
                    Text("\(label)…").foregroundStyle(.white)
                case .done(let summary):
                    Text("✓ \(summary)").foregroundStyle(.green)
                case .failed(let message):
                    Text("✕ \(message)").foregroundStyle(.red)
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)

            // 조건을 바꿔가며 연달아 재는 화면이다. 직전 값을 덮어쓰면 콘솔을
            // 놓쳤을 때 앞 조건이 통째로 사라지므로 실행 내내 쌓아서 보여준다.
            if !normalizer.history.isEmpty {
                Text(normalizer.history.suffix(16).joined(separator: "\n"))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            if !normalizer.replaceReport.isEmpty {
                Text(normalizer.replaceReport.joined(separator: "\n"))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
    }

    /// 사진 앱 권한 안내. 설정 앱으로 보내는 버튼은 2-13 에서 붙인다.
    private static func describe(photoPermission state: PermissionState) -> String {
        switch state {
        case .authorized:
            return ""
        case .undetermined:
            return "사진 앱 권한이 아직 결정되지 않았습니다."
        case .denied:
            return "사진 앱 접근이 거부되어 있습니다. 설정 > Mellow 에서 '사진 추가만'을 허용해 주세요."
        case .restricted:
            return "사진 앱 접근이 기기 정책으로 제한되어 있습니다."
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 92, alignment: .leading)
            Text(value)
        }
    }

    /// 각도는 가공하지 않고 원본 값을 그대로 보여준다.
    private static func describe(angle: CGFloat?) -> String {
        guard let angle else { return "—" }
        return "\(angle)"
    }

    /// 폐기된 경우가 조용히 묻히지 않도록 직전 결말을 그대로 보여준다.
    private static func describe(outcome: CaptureSessionController.ClipOutcome) -> String {
        switch outcome {
        case let .saved(seconds, hitLimit):
            return String(format: "저장 %.2fs", seconds) + (hitLimit ? " (10초 자동정지)" : "")
        case let .discarded(seconds):
            return String(format: "⌫ 폐기 %.2fs (1초 미만)", seconds)
        case let .failed(message):
            return "✕ \(message)"
        }
    }

    private static func describe(orientation: UIDeviceOrientation) -> String {
        switch orientation {
        case .unknown: return "unknown"
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        @unknown default: return "unknown(\(orientation.rawValue))"
        }
    }

    // MARK: - 권한 안내

    // 거부·제한 상태에서는 안내만 한다. 설정 앱으로 보내는 버튼은 2-13 에서 붙인다.
    private var permissionMessage: some View {
        let camera = controller.cameraPermission
        let microphone = controller.microphonePermission

        return message(
            title: "촬영 권한이 필요합니다",
            detail: [Self.describe(permission: camera, name: "카메라"),
                     Self.describe(permission: microphone, name: "마이크")]
                .compactMap { $0 }
                .joined(separator: "\n")
        )
    }

    private static func describe(permission: PermissionState, name: String) -> String? {
        switch permission {
        case .authorized:
            return nil
        case .undetermined:
            return "\(name) 권한이 아직 결정되지 않았습니다."
        case .denied:
            return "\(name) 권한이 거부되어 있습니다."
        case .restricted:
            return "\(name) 사용이 기기 정책으로 제한되어 있습니다."
        }
    }

    private func message(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}
