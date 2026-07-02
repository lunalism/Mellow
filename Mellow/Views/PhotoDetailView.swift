import SwiftUI

/// 사진 상세 뷰 (Phase 1 · Stage 4b-3, 2/n). 갤러리 그리드와 **같은 최신순 배열** 위를
/// 가로로 페이징한다. 셀을 열면 그 캡처 페이지에서 시작하고, 좌우 스와이프로 이전/다음
/// 캡처로 넘어간다. 날짜 헤더는 현재 보이는 사진을 따라 갱신된다.
///
/// 색은 **비파괴 재렌더** — 각 페이지는 무필터 원본 + `filterID`를 라이브 프리뷰·썸네일·
/// 갤러리 셀과 **같은 `FilterPreset.makeChain`**으로 9:16 전체 프레이밍으로 렌더한다(WYSIWYG).
/// step 1의 `fullFrameThumbnail` + `fullCache` 경로를 그대로 재사용한다(두 번째 렌더 경로 없음).
///
/// 부드러움(이 슬라이스 핵심):
/// - **프리페치(±1):** 인접 페이지를 미리 백그라운드 렌더해 캐시에 넣어 둔다 →
///   스와이프 시 흰 깜빡임·디코드 끊김 없이 즉시 표시.
/// - **축출:** 풀해상도는 화면 크기라 무거우므로 `fullCache`(NSCache)의 `countLimit = 6`으로
///   메모리 상한을 둔다. 먼 페이지는 자동 축출 → 수백 장을 넘겨도 메모리·발열이 누적되지 않는다.
///   (윈도우는 보이는 페이지 + 양옆 = 최대 3장이 "핫" → 상한 6은 왕복 스와이프에 충분한 여유.)
///
/// 범위(2/n + Stage 2a 삭제): 페이징 + **단일 삭제(삭제 후 dismiss)**. 삭제 모션은 그리드에서만
/// 일어난다 — 여기선 스토어에서 지우고 바로 그리드로 돌아가며, .page TabView 전환 문제를 피한다.
struct PhotoDetailView: View {
    let captures: [Capture]
    @State private var selection: UUID
    @State private var showDeleteConfirm = false
    @State private var deleteFailed = false
    @State private var showInfo = false
    /// 현재 보이는 페이지가 줌 상태인지. 줌 중엔 TabView 페이징을 억제하는 보조 신호로 쓴다.
    @State private var isCurrentZoomed = false
    @Environment(\.dismiss) private var dismiss

    /// 상세 렌더 해상도 = 화면 긴 변 px(**다운스케일, 풀해상도 아님**). 화면에선 풀해상도와 동일하게 보인다.
    private let maxPixels = Int(max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height))

    init(captures: [Capture], startID: UUID) {
        self.captures = captures
        _selection = State(initialValue: startID)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(captures) { capture in
                PhotoDetailPage(capture: capture, maxPixels: maxPixels,
                                isActive: capture.id == selection,
                                onZoomChange: { zoomed in
                                    // 활성(보이는) 페이지의 줌만 페이징 게이트에 반영.
                                    // 리셋으로 비활성 이웃이 false를 올려도 무시된다.
                                    if capture.id == selection { isCurrentZoomed = zoomed }
                                })
                    .tag(capture.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))   // 가로 페이징, 점 인디케이터 없음
        // 보조 안전장치: 줌 중 페이징 억제. 주 기제는 내부 UIScrollView가 팬을 소비하는 것.
        .scrollDisabled(isCurrentZoomed)
        .background(Color.mellowShadow.ignoresSafeArea())  // 들린 블랙 chrome (#3B362E)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(currentDateText)                // 헤더는 현재 보이는 사진을 따라 갱신
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.mellowShadow, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            // ⓘ 인포 — nav 바(chrome)에 있어 ZoomableScrollView 위에 뜨고 항상 탭 가능하며,
            // 핀치/팬/페이징 제스처와 히트 영역이 분리돼 간섭하지 않는다.
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.mellowIvory)
                }
                .accessibilityLabel("사진 정보")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.mellowIvory)   // 들린 블랙 바 위 따뜻한 아이보리(§9)
                }
                .accessibilityLabel("이 사진 삭제")
            }
        }
        // ⓘ 바텀시트 — 사진은 위에 그대로 보이고(Photos식), 스와이프 다운·바깥 탭으로 닫힘.
        // 콘텐츠에 맞춘 고정 높이 디텐트. 표면은 페이퍼 크림(§9, 순수 흰색 아님).
        .sheet(isPresented: $showInfo) {
            if let cap = captures.first(where: { $0.id == selection }) {
                PhotoInfoSheet(capture: cap)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.mellowPaper)
            }
        }
        // 파괴적·되돌릴 수 없음(휴지통·실행취소 없음) → 확인 후에만 삭제.
        .confirmationDialog("이 사진을 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("삭제", role: .destructive) { deleteCurrentAndDismiss() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("되돌릴 수 없어요. 원본도 함께 삭제됩니다.")
        }
        .alert("삭제하지 못했어요", isPresented: $deleteFailed) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("잠시 후 다시 시도해 주세요. 사진은 그대로 남아 있어요.")
        }
        .task(id: selection) { prefetchNeighbors() }     // 선택이 바뀔 때마다 인접 페이지 프리페치
    }

    /// 현재 보이는 사진을 삭제하고 **그리드로 dismiss**. 이웃 이동·크로스페이드 없음 —
    /// 사라짐 애니메이션은 그리드 복귀 시 `reconcileAfterDetail`이 처리한다(삭제 모션 일원화).
    @MainActor private func deleteCurrentAndDismiss() {
        guard let cap = captures.first(where: { $0.id == selection }) else { return }
        do {
            try CaptureStore.shared.delete(cap)               // 원자적: 레코드+파일(실패 시 throw)
        } catch {
            deleteFailed = true                                // 실패 → 알림, dismiss 안 함
            return
        }
        CaptureThumbnailRenderer.shared.evict(id: cap.id)      // 두 캐시에서 스테일 이미지 제거
        dismiss()                                              // 그리드로 복귀 → 거기서 사라짐 애니메이션
    }

    /// 현재 선택된 캡처의 지역화된 날짜·시간. 스와이프로 selection이 바뀌면 헤더가 따라간다.
    private var currentDateText: String {
        guard let cap = captures.first(where: { $0.id == selection }) else { return "" }
        return Self.dateText(cap.createdAt)
    }

    /// ±1 이웃을 백그라운드에서 미리 렌더해 `fullCache`에 채운다(이미 캐시면 건너뜀).
    /// 먼 페이지는 따로 비우지 않아도 NSCache 상한(6)이 자동 축출한다 → 메모리·발열 누적 방지.
    private func prefetchNeighbors() {
        guard let idx = captures.firstIndex(where: { $0.id == selection }) else { return }
        for n in [idx - 1, idx + 1] where captures.indices.contains(n) {
            let cap = captures[n]
            // 이미 캐시에 있으면 렌더 안 함 — 메인에서 안전한 조회.
            if CaptureThumbnailRenderer.shared.cachedFullFrame(id: cap.id, maxPixelSize: maxPixels) != nil { continue }
            let url = CaptureStore.shared.url(for: cap)
            let px = maxPixels
            Task.detached(priority: .utility) {   // 보이는 페이지(.userInitiated)보다 낮은 우선순위
                _ = CaptureThumbnailRenderer.shared.fullFrameThumbnail(id: cap.id, url: url,
                                                                       filterID: cap.filterID, maxPixelSize: px)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("yMMMdjm")   // 지역화된 날짜·시간
        return f
    }()

    private static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }
}

/// 단일 캡처 페이지 — 9:16 **전체 프레이밍**(크롭 없음) 비파괴 렌더. step 1과 동일한
/// 캐시 우선 → 미스 시 백그라운드 렌더 경로. 보이는 페이지에서만 `.task`가 돌고, 인접
/// 페이지는 `prefetchNeighbors`가 미리 채워 둬서 스와이프 시 캐시 히트로 즉시 표시된다.
private struct PhotoDetailPage: View {
    let capture: Capture
    let maxPixels: Int
    /// 이 페이지가 현재 보이는(선택된) 페이지인지 — 비활성이 되면 줌을 1.0으로 리셋한다.
    let isActive: Bool
    /// 줌 여부를 부모로 올려 페이징 억제에 쓴다.
    let onZoomChange: (Bool) -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.mellowShadow                 // 페이지 배경(스와이프 중에도 연속된 들린 블랙)
            if let image {
                // 렌더된 이미지를 그대로 감싸 핀치/더블탭 줌 + 팬. 컨테이너 종횡비를 이미지에
                // 맞춰(.aspectRatio) 줌 1.0에서 보더가 이미지에 딱 붙고, 필터 재렌더 없음(WYSIWYG).
                ZoomableScrollView(image: image, isActive: isActive, onZoomChange: onZoomChange)
                    .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.mellowBorder.opacity(0.6), lineWidth: 1)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                ProgressView()                 // 짧은 로딩 — 캐시 미스로 백그라운드 렌더 중
                    .tint(Color.mellowAccent)
            }
        }
        .task(id: capture.id) { await load() }
    }

    @MainActor private func load() async {
        // 1) 캐시 즉시 조회 — 프리페치된/재진입 페이지는 깜빡임 없이 바로.
        if let cached = CaptureThumbnailRenderer.shared.cachedFullFrame(id: capture.id, maxPixelSize: maxPixels) {
            image = cached
            return
        }
        // 2) 미스 → 백그라운드 렌더(메인 비차단). 사용자가 보는 페이지라 .userInitiated.
        let cap = capture
        let url = CaptureStore.shared.url(for: cap)
        let px = maxPixels
        let rendered = await Task.detached(priority: .userInitiated) {
            CaptureThumbnailRenderer.shared.fullFrameThumbnail(id: cap.id, url: url,
                                                               filterID: cap.filterID, maxPixelSize: px)
        }.value
        if let rendered { image = rendered }   // UI 설정은 메인(@MainActor)
    }
}
