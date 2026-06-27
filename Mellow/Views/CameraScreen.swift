import SwiftUI

/// Phase 1 · Stage 1 메인 화면.
///
/// 권한 게이트 → 들린 블랙 chrome 위의 큰 3:4 필름 카드 프리뷰 + 전/후면 전환.
/// 셔터·비율·필터·노출 등 나머지 컨트롤은 다음 단계에서 추가한다.
struct CameraScreen: View {
    @StateObject private var auth = CameraAuthorization()
    @StateObject private var vm = CameraViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGallery = false         // 보관함 그리드(4b-2) 표시
    @State private var shutterDim: Double = 0       // 셔터 블링크(프리뷰 들린-블랙 딥)

    // MARK: - 레이아웃 상수
    private enum Layout {
        static let frameMargin: CGFloat = 9     // 얇은 lifted-black 프레임 (상·좌·우)
        static let cardCorner: CGFloat = 22     // 필름 카드 모서리 (Spec §2.2)
        static let minBottomZone: CGFloat = 150 // 하단 컨트롤(필터 스트립 + 셔터 + 플립) 높이
        static let swipeThreshold: CGFloat = 40 // 필터 전환 스와이프 최소 이동
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
                    // 기존 최근 캡처가 있으면 보관함 썸네일도 띄운다(재실행 시 지속).
                    .task { vm.startSession(); vm.loadLatestThumbnail() }
            }
        }
        // 촬영 피드백: 셔터 햅틱 + 좌하단 썸네일 갱신 + 프리뷰 들린-블랙 블링크(아래).
        // 셔터 시 프리뷰만 잠깐 어두워졌다 복귀 — fade-in 80ms → fade-out 120ms(총 ~200ms).
        .onChange(of: vm.captureState) { _, state in
            guard state == .capturing else { return }
            withAnimation(.easeInOut(duration: 0.08)) { shutterDim = 0.7 }
            withAnimation(.easeInOut(duration: 0.12).delay(0.08)) { shutterDim = 0 }
        }
        // 실패 토스트 (저장공간 부족·촬영 실패).
        .overlay(alignment: .bottom) { captureToast }
        // 보관함 그리드(4b-2) — 풀스크린으로 띄우고 chevron으로 카메라 복귀.
        .fullScreenCover(isPresented: $showGallery) { GalleryView() }
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
                // 좌우 스와이프 → 필터 전환 (Spec §4.1).
                previewCard
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous))
                    // 셔터 블링크 — 들린-블랙으로 프리뷰만 살짝 어둡혔다 복귀(필름 셔터 느낌, 눈부심 없음).
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous)
                            .fill(Color.mellowShadow)
                            .opacity(shutterDim)
                            .allowsHitTesting(false)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous)
                            .stroke(Color.mellowBorder, lineWidth: 1)
                    )
                    .shadow(color: Color.mellowShadow.opacity(0.35), radius: 16, y: 8)
                    .contentShape(Rectangle())
                    .gesture(filterSwipe)
                    .frame(maxWidth: .infinity)

                // 하단 컨트롤 — 필터 스트립 + (셔터 중앙 · 플립 우측). (보관함 썸네일은 4b)
                VStack(spacing: 14) {
                    filterStrip
                    ZStack {
                        shutterButton
                        HStack {
                            libraryThumbnail
                            Spacer()
                            flipButton
                        }
                    }
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
            CameraPreviewView(sessionManager: vm.sessionManager,
                              selectedFilter: vm.selectedFilter)
        }
        #endif
    }

    // MARK: - 필터 스위칭 (Spec §4)

    /// 좌우 스와이프 → 다음/이전 필터. 수평 우세 + 임계값 통과 시에만.
    private var filterSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy), abs(dx) > Layout.swipeThreshold else { return }
                vm.cycleFilter(by: dx < 0 ? 1 : -1)  // 왼쪽 스와이프 → 다음
            }
    }

    /// 하단 필터 스트립. 칩 = 이름 + 선택 시 앰버 링 (Spec §2.3). 탭 = 선택.
    /// (필름통 아트·라이브 틴트 썸네일은 후속 폴리시.)
    private var filterStrip: some View {
        HStack(spacing: 10) {
            ForEach(vm.presets) { preset in
                filterChip(preset)
            }
        }
    }

    private func filterChip(_ preset: FilterPreset) -> some View {
        let isSelected = preset.id == vm.selectedFilter.id
        return Button {
            vm.selectFilter(preset)
        } label: {
            Text(preset.displayName)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.mellowTextPrimary : Color.mellowIvory.opacity(0.7))
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(Capsule().fill(isSelected ? Color.mellowBgRaised : Color.clear))
                .overlay(
                    Capsule().stroke(isSelected ? Color.mellowAccent : Color.mellowIvory.opacity(0.25),
                                     lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }

    /// 전/후면 전환 버튼. 어두운 chrome 위에서도 읽히는 따뜻한 칩.
    private var flipButton: some View {
        Button {
            vm.toggleCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.mellowTextPrimary)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.mellowBgRaised))
                .overlay(Circle().stroke(Color.mellowBorder, lineWidth: 1))
                .shadow(color: Color.mellowShadow.opacity(0.25), radius: 8, y: 4)
        }
        .disabled(!vm.isCameraAvailable || vm.isSwitchingCamera)
        .opacity(vm.isCameraAvailable ? 1 : 0.5)
    }

    /// 보관함 썸네일 (Spec §2.3 · Stage 4b-1). 최근 캡처의 **필터 적용** 미리보기.
    /// 셔터 반대편(leading)에 두고 셔터는 중앙 유지. 탭 → 보관함은 4b-2.
    private var libraryThumbnail: some View {
        Button {
            showGallery = true   // 탭 → 인앱 보관함 그리드(4b-2).
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.mellowBgRaised)
                if let thumb = vm.latestThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")          // 빈 상태 — 아직 촬영 없음
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.mellowTextSecondary)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.mellowBorder, lineWidth: 1)
            )
            .shadow(color: Color.mellowShadow.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(vm.latestThumbnail == nil)            // 빈 상태에선 비활성(no-op 의도 명확)
        .animation(.easeOut(duration: 0.2), value: vm.latestThumbnail != nil)
    }

    // MARK: - 셔터 (Spec §6, §9)

    /// 셔터 버튼 — 앰버 링 + 아이보리 중앙. 촬영 중 축소 + 중복 탭 무시.
    private var shutterButton: some View {
        Button {
            vm.capturePhoto()
        } label: {
            ZStack {
                Circle().fill(Color.mellowIvory).frame(width: 56, height: 56)
                Circle().stroke(Color.mellowAccent, lineWidth: 5).frame(width: 70, height: 70)
            }
            .shadow(color: Color.mellowShadow.opacity(0.3), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!vm.isCameraAvailable || vm.captureState != .idle)
        .opacity(vm.isCameraAvailable ? 1 : 0.5)
        .scaleEffect(vm.captureState == .capturing ? 0.92 : 1)
        .animation(.easeOut(duration: 0.12), value: vm.captureState)
    }

    // MARK: - 실패 토스트

    @ViewBuilder
    private var captureToast: some View {
        if let message = vm.captureError {
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.mellowIvory)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(Capsule().fill(Color.mellowShadow.opacity(0.92)))
                .overlay(Capsule().stroke(Color.mellowBorder.opacity(0.3), lineWidth: 1))
                .padding(.bottom, 44)
                .transition(.opacity)
                .task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    vm.clearCaptureError()
                }
        }
    }
}

#Preview {
    CameraScreen()
}
