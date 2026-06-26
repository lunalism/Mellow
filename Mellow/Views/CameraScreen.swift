import SwiftUI

/// Phase 1 · Stage 1 메인 화면.
///
/// 권한 게이트 → 들린 블랙 chrome 위의 큰 3:4 필름 카드 프리뷰 + 전/후면 전환.
/// 셔터·비율·필터·노출 등 나머지 컨트롤은 다음 단계에서 추가한다.
struct CameraScreen: View {
    @StateObject private var auth = CameraAuthorization()
    @StateObject private var vm = CameraViewModel()
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - 레이아웃 상수
    private enum Layout {
        static let frameMargin: CGFloat = 9     // 얇은 lifted-black 프레임 (상·좌·우)
        static let cardCorner: CGFloat = 22     // 필름 카드 모서리 (Spec §2.2)
        static let minBottomZone: CGFloat = 88  // 하단 컨트롤(플립) 최소 높이, Stage 3에서 확장
    }

    var body: some View {
        ZStack {
            // 들린 블랙 chrome (#3B362E). 순수 검정 금지.
            Color.mellowShadow.ignoresSafeArea()

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
        // 어두운 chrome 위에선 상태바(시계·배터리)를 라이트 콘텐츠로. 페이퍼 프라이밍 화면은 라이트.
        // (모든 색은 고정 토큰이라 colorScheme 전환은 상태바 가독성에만 영향)
        .preferredColorScheme(auth.state == .authorized ? .dark : .light)
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

    // MARK: - 카메라 인터페이스 (3분할: 상단 바 · 프리뷰 · 하단 컨트롤)

    private var cameraInterface: some View {
        GeometryReader { geo in
            // 단일 출처 비율(기본 9:16). 프리뷰 카드와 (추후) 캡처가 같은 값을 쓴다.
            let ratio = vm.aspectRatio.portraitWidthOverHeight
            // 얇은 상·좌·우 프레임 + 하단 컨트롤 영역을 확보한 뒤, 들어맞는 가장 큰 비율 카드.
            let availWidth = geo.size.width - Layout.frameMargin * 2
            let availHeight = max(0, geo.size.height - Layout.frameMargin - Layout.minBottomZone)
            let cardWidth = min(availWidth, availHeight * ratio)
            let cardHeight = cardWidth / ratio

            VStack(spacing: 0) {
                // 얇은 상단 프레임 (좌우 여백과 동일 폭) — full-bleed 방지.
                Color.clear.frame(height: Layout.frameMargin)

                // 프리뷰 — 세로로 꽉 찬 9:16 필름 카드. 얇은 lifted-black 프레임이 사방에 보임.
                previewCard
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous)
                            .stroke(Color.mellowBorder, lineWidth: 1)
                    )
                    .shadow(color: Color.mellowShadow.opacity(0.35), radius: 16, y: 8)
                    .frame(maxWidth: .infinity)

                // 하단 컨트롤 — 남는 세로 공간 흡수. Stage 3: 필름통 스트립 + 셔터. 지금은 플립만.
                ZStack {
                    flipButton
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Layout.frameMargin)
            }
        }
    }

    /// 프리뷰 카드 내용. 카메라 피드는 레이어의 resizeAspectFill로 카드를
    ///     꽉 채우고 넘치는 부분은 크롭된다(내부 레터박스 없음).
    @ViewBuilder
    private var previewCard: some View {
        #if targetEnvironment(simulator)
        // 시뮬레이터엔 카메라가 없다. 더미는 **오직** 이 컴파일 타임 분기에서만 진입한다.
        // 실기기 빌드에는 이 코드가 포함되지 않아 더미가 도달 불가.
        DummyCameraView()
        #else
        // 실기기: 첫 프레임 전 짧은 윈도우 동안 차분한 페이퍼 플레이스홀더(라벨 없음)를
        // 깔고, 프레임이 들어오면 라이브 프리뷰가 그 위를 채운다. 더미 재사용 금지.
        ZStack {
            Color.mellowPaper
            CameraPreviewView(sessionManager: vm.sessionManager)
        }
        #endif
    }

    /// 전/후면 전환 버튼 (하단 chrome 영역 중앙). 어두운 chrome 위에서도 읽히는 따뜻한 칩.
    private var flipButton: some View {
        Button {
            vm.toggleCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Color.mellowTextPrimary)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.mellowBgRaised))
                .overlay(Circle().stroke(Color.mellowBorder, lineWidth: 1))
                .shadow(color: Color.mellowShadow.opacity(0.25), radius: 8, y: 4)
        }
        .disabled(!vm.isCameraAvailable || vm.isSwitchingCamera)
        .opacity(vm.isCameraAvailable ? 1 : 0.5)
    }
}

#Preview {
    CameraScreen()
}
