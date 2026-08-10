import SwiftUI
import UIKit

// 1-1 / 1-2 확인용 화면. 프리뷰와 디버그 오버레이만 있다.
// 녹화 버튼은 1-4 에서 붙인다.
struct ContentView: View {
    @StateObject private var controller = CaptureSessionController()
    @Environment(\.scenePhase) private var scenePhase

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

    // 1-4 확인용. 탭하면 시작, 다시 탭하면 종료.
    // 누르고 있는 방식(1-6)과 10초 자동 정지(1-5)는 다음 단계다.
    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                Task { await controller.reportRecordedComparison() }
            } label: {
                Text("전체 비교 (\(controller.recordedURLs.count))")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
            }
            .disabled(controller.recordedURLs.isEmpty)

            // 누르는 동안 녹화, 떼면 종료 (1-6).
            // 10초에 도달하면 떼지 않아도 프레임워크가 끊는다 (1-5).
            //
            // Button 은 탭이 끝나야 동작하므로 쓸 수 없다.
            //
            // DragGesture 도 쓰지 않는다. onEnded 는 제스처가 취소되면(알림 배너,
            // 홈 인디케이터 스와이프, 백그라운드 전환) 호출되지 않는데, 중복
            // onChanged 를 거르려고 뷰에 누름 플래그를 두면 그 플래그가 true 로
            // 갇혀 다음 촬영 한 번을 통째로 잃는다. 플래그가 실제 상태를 따라가지
            // 못하는 것 — 컨트롤러의 녹화 의도와 같은 종류의 버그다.
            //
            // onPressingChanged 는 누를 때 true, 떼거나 취소될 때 false 로
            // 한 번씩만 온다. 뷰에 상태를 둘 필요가 없어 갇힐 플래그도 없다.
            // minimumDuration 을 길게 잡아 perform 은 실질적으로 호출되지 않고,
            // maximumDistance 를 크게 잡아 손가락이 조금 움직여도 끊기지 않는다.
            Circle()
                .fill(controller.isRecording ? .red : .white)
                .frame(width: 72, height: 72)
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 4).padding(-6))
                .onLongPressGesture(minimumDuration: 60, maximumDistance: 10_000) {
                    // 10초면 자동 정지하므로 여기까지 오지 않는다.
                } onPressingChanged: { pressing in
                    if pressing {
                        controller.startRecording()
                    } else {
                        controller.stopRecording()
                    }
                }
        }
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
