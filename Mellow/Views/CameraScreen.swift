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
        static let hMargin: CGFloat = 11        // 카드 좌우 여백(= 얇은 chrome 프레임)
        static let cardCorner: CGFloat = 22     // 필름 카드 모서리 (Spec §2.2)
        static let topBarHeight: CGFloat = 40   // 슬림 상단 바 영역 (Stage 3: 플래시·비율·설정)
        static let cardTopGap: CGFloat = 4      // 상단 바 바로 아래에 카드를 붙인다
        /// 프리뷰 카드 비율 = 폭:높이. Spec §3 기본 4:3 → 세로 3:4. WYSIWYG 위해 고정.
        static let previewRatio: CGFloat = 3.0 / 4.0
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
            let cardWidth = geo.size.width - Layout.hMargin * 2
            let cardHeight = cardWidth / Layout.previewRatio   // 4:3 세로 → 폭 × 4/3

            VStack(spacing: 0) {
                // (1) 슬림 상단 바 — Stage 1은 예약 공간. (플래시·비율·설정은 Stage 3)
                topBarZone

                // (2) 프리뷰 — 화면을 지배하는 큰 3:4 필름 카드. 가장자리엔 닿지 않음(얇은 프레임).
                previewCard
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous)
                            .stroke(Color.mellowBorder, lineWidth: 1)
                    )
                    .shadow(color: Color.mellowShadow.opacity(0.35), radius: 16, y: 8)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Layout.cardTopGap)

                // (3) 하단 컨트롤 — 남는 세로 공간 흡수(데드 갭 방지).
                //     Stage 3: 필름통 필터 스트립 + 셔터. 지금은 전/후면 플립만.
                ZStack {
                    flipButton
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Layout.hMargin)
            }
        }
    }

    /// (1) 슬림 상단 바 영역. Stage 1은 비워 둔 예약 공간.
    private var topBarZone: some View {
        Color.clear
            .frame(height: Layout.topBarHeight)
    }

    /// (2) 프리뷰 카드 내용. 카메라 피드는 레이어의 resizeAspectFill로 카드를
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
            CameraPreviewView(session: vm.sessionManager.session)
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
