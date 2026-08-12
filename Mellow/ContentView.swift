import SwiftUI
import UIKit

// 1-1 / 1-2 확인용 화면. 프리뷰와 디버그 오버레이만 있다.
// 녹화 버튼은 1-4 에서 붙인다.
struct ContentView: View {
    @StateObject private var controller = CaptureSessionController()
    @StateObject private var saver = SaveToPhotosController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPreview = false

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
