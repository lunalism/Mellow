import SwiftUI

/// Phase 1 · Stage 1 메인 화면.
///
/// 권한 게이트 → 라이브(또는 더미) 프리뷰 + 전/후면 전환.
/// 셔터·비율·필터·노출 등 나머지 컨트롤은 다음 단계에서 추가한다.
struct CameraScreen: View {
    @StateObject private var auth = CameraAuthorization()
    @StateObject private var vm = CameraViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.mellowPaper.ignoresSafeArea()

            switch auth.state {
            case .notDetermined:
                PermissionPrimingView(isDenied: false) {
                    Task { await auth.request() }
                }
            case .denied:
                PermissionPrimingView(isDenied: true, onRequest: {})
            case .authorized:
                cameraInterface
                    // 세션 구성/시작은 백그라운드 큐에서. 가능한 한 일찍 시작해 런치 윈도우를 줄인다.
                    .task { vm.startSession() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                auth.refresh()
                if auth.state == .authorized { vm.startSession() }
            case .background, .inactive:
                vm.stopSession()
            @unknown default:
                break
            }
        }
    }

    // MARK: - 카메라 인터페이스

    private var cameraInterface: some View {
        VStack(spacing: 0) {
            preview
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Spacer(minLength: 0)

            bottomBar
                .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var preview: some View {
        // Stage 1: 4:3 고정. 비율 전환은 다음 단계.
        #if targetEnvironment(simulator)
        // 시뮬레이터엔 카메라가 없다. 더미는 **오직** 이 컴파일 타임 분기에서만 진입한다.
        // 실기기 빌드에는 이 코드가 포함되지 않아 더미가 도달 불가.
        DummyCameraView()
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
        #else
        // 실기기: 첫 프레임 전 짧은 윈도우 동안 차분한 페이퍼 플레이스홀더(라벨 없음)를
        // 깔고, 프레임이 들어오면 라이브 프리뷰가 그 위를 채운다. 더미 재사용 금지.
        ZStack {
            Color.mellowPaper
            CameraPreviewView(session: vm.sessionManager.session)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        #endif
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            // 전/후면 전환
            Button {
                vm.toggleCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.mellowTextPrimary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.mellowBgRaised))
                    .overlay(Circle().stroke(Color.mellowBorder, lineWidth: 1))
                    .shadow(color: Color.mellowShadow.opacity(0.12), radius: 6, y: 3)
            }
            .disabled(!vm.isCameraAvailable || vm.isSwitchingCamera)
            .opacity(vm.isCameraAvailable ? 1 : 0.4)
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    CameraScreen()
}
