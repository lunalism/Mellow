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
                    // 세션 시작은 reconcileCamera()가 단일 불변식으로 관리(보관함 열림/scenePhase 반영).
                    // 기존 최근 캡처가 있으면 보관함 썸네일도 띄운다(재실행 시 지속).
                    // 카메라 권한이 이미 허용된 지점이므로, 위치가 미결정이면 여기서 When-In-Use 프라이밍.
                    .task { reconcileCamera(); vm.syncLatestThumbnail(); vm.requestLocationIfNeeded() }
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
        // 닫힐 때 썸네일을 단일 소스에 재동기화(상세 뷰에서 삭제했을 수 있으므로).
        .fullScreenCover(isPresented: $showGallery, onDismiss: { vm.syncLatestThumbnail() }) { GalleryView() }
        // 보관함 열림/닫힘 → 카메라 불변식 재조정(열리면 정지, 닫히면 재시작).
        .onChange(of: showGallery) { _, _ in reconcileCamera() }
        // 어두운 chrome 위에선 상태바(시계·배터리)를 라이트 콘텐츠로. 페이퍼 프라이밍 화면은 라이트.
        // (모든 색은 고정 토큰이라 colorScheme 전환은 상태바 가독성에만 영향)
        .preferredColorScheme(auth.state == .authorized ? .dark : .light)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { auth.refresh() }   // 설정 앱에서 권한 바뀐 뒤 복귀 시 갱신
            reconcileCamera()
        }
    }

    // MARK: - 카메라 수명주기 단일 불변식

    /// 카메라는 **(scenePhase == .active) && (보관함 닫힘) && (권한 authorized)** 일 때만 돈다.
    /// 이 하나의 함수가 유일한 start/stop 출처 — 보관함 위에서 카메라가 켜질 두 번째 경로를 두지 않는다.
    /// 세션 매니저의 isRunning 가드가 반복 호출을 무해하게 만들고, start/stop은 모두 세션 큐(오프메인).
    private func reconcileCamera() {
        if scenePhase == .active, !showGallery, auth.state == .authorized {
            vm.startSession()
        } else {
            vm.stopSession()
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
                              selectedSlug: vm.selectedSlug,
                              isPreviewRunning: vm.isPreviewRunning)
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

    /// 하단 필터 스트립 (10종: Original + 로스터 9). 가로 스크롤로 브라우즈 + 탭 선택.
    /// 선택 pill은 탭·스와이프 어느 쪽이든 `selectedSlug` 변화를 **단일 지점**에서 감지해 센터로
    /// 자동 스크롤한다(스와이프/탭 스크롤 애니메이션이 겹치지 않게 최신 타깃으로만 이동 — GATE 1).
    private var filterStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(vm.filterOptions) { option in
                        filterChip(option).id(option.slug)
                    }
                }
                .padding(.horizontal, Layout.frameMargin)
            }
            .mask(stripEdgeFade)   // 좌우 엣지 페이드 — 더 있음을 암시
            .onChange(of: vm.selectedSlug) { _, slug in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(slug, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(vm.selectedSlug, anchor: .center) }   // 런치: Sunday 센터
        }
    }

    /// 스트립 좌우 가장자리 페이드 마스크(알파: black=불투명, clear=투명).
    private var stripEdgeFade: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0.0),
            .init(color: .black, location: 0.05),
            .init(color: .black, location: 0.95),
            .init(color: .clear, location: 1.0),
        ], startPoint: .leading, endPoint: .trailing)
    }

    private func filterChip(_ option: CameraViewModel.FilterOption) -> some View {
        let isSelected = option.slug == vm.selectedSlug
        return Button {
            vm.selectFilter(slug: option.slug)
        } label: {
            Text(option.name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                // 선택 = 들린-블랙 잉크(크림 위), 비선택 = 뮤트 아이보리(들린-블랙 chrome 위).
                .foregroundStyle(isSelected ? Color.mellowShadow : Color.mellowIvory.opacity(0.7))
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                // 선택 = 크림 필(#F4EEE1 mellowPaper), 비선택 = 투명.
                .background(Capsule().fill(isSelected ? Color.mellowPaper : Color.clear))
                .overlay(
                    // 선택 = 2px 앰버 링(셔터 링과 동일), 비선택 = 0.5px 헤어라인.
                    Capsule().stroke(isSelected ? Color.mellowAccent : Color.mellowIvory.opacity(0.25),
                                     lineWidth: isSelected ? 2 : 0.5)
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
