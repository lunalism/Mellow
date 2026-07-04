import SwiftUI

/// 인앱 "필름 다이어리" 갤러리 그리드 (Phase 1 Spec §2.3 · Stage 4b-2 · 2a 삭제).
///
/// 앱 **자체** 보관함(`Documents/Originals` + `captures.json`) — 시스템 사진 앱이 아니다.
/// `CaptureStore`(4a/4b-1과 동일한 단일 소스)에서 최신순으로 읽어 3열 정사각 그리드로 보여준다.
/// 셀 색은 **비파괴 재렌더**(무필터 원본 + filterID를 프리뷰와 같은 체인으로) — WYSIWYG.
///
/// 삭제(Stage 2a): **편집 모드** 멀티 선택 + 일괄 삭제(Photos식 스케일/페이드 아웃 + 리플로우),
/// 그리고 상세 뷰에서 단일 삭제 후 돌아오면 그 셀이 같은 애니메이션으로 사라진다(삭제 모션 일원화).
/// 단일 소스는 항상 captures.json — 그리드 `captures`는 그 미러이고, 상세 복귀 시 스토어와 **디핑**해
/// 사라진 셀만 애니메이션 제거한다.
struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var captures: [Capture] = []
    @State private var path: [UUID] = []            // 경로 바인딩 — pop 시점을 결정적으로 잡아 리컨사일

    // 편집 모드(2a 멀티 삭제)
    @State private var isEditing = false
    @State private var selected: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var deleteFailed = false

    private let gap: CGFloat = 3
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gap), count: 3)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.mellowShadow.ignoresSafeArea()   // 들린 블랙 chrome (#3B362E), 카메라와 연속성
                if captures.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle(isEditing ? selectionTitle : "필름 다이어리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(Color.mellowShadow, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // 셀 탭 → 상세 뷰(4b-3). UUID로 라우팅, 페이징 위해 같은 최신순 배열을 넘기고 그 id에서 시작.
            .navigationDestination(for: UUID.self) { id in
                PhotoDetailView(captures: captures, startID: id)
            }
            // ≥1 선택 시에만 하단 삭제 바(Photos식). 선택 0이면 사라진다.
            .safeAreaInset(edge: .bottom) {
                if isEditing && !selected.isEmpty { deleteBar }
            }
        }
        .tint(Color.mellowAccent)      // 편집/취소/완료·뒤로가기 등 시스템 액센트를 앰버로(온브랜드)
        .preferredColorScheme(.dark)   // 어두운 chrome → 라이트 상태바
        .onAppear { if captures.isEmpty { captures = CaptureStore.shared.allNewestFirst } }   // 최초 로드
        // 상세에서 pop된 순간(path 비워짐) — 스토어와 디핑해 삭제된 셀만 애니메이션 제거.
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty { reconcileAfterDetail() }
        }
        .confirmationDialog(deleteConfirmTitle, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("삭제", role: .destructive) { performDelete() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("되돌릴 수 없어요. 원본도 함께 삭제됩니다.")
        }
        .alert("삭제하지 못했어요", isPresented: $deleteFailed) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("잠시 후 다시 시도해 주세요. 사진은 그대로 남아 있어요.")
        }
    }

    // MARK: - Chrome

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isEditing {
                Button("취소") { exitEditMode() }        // 편집 모드 나가기(선택 해제)
            } else {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.mellowIvory)
                }
                .accessibilityLabel("카메라로 돌아가기")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isEditing {
                Button("완료") { exitEditMode() }.fontWeight(.semibold)
            } else if !captures.isEmpty {
                Button("편집") { isEditing = true }
            }
        }
    }

    private var selectionTitle: String {
        selected.isEmpty ? "사진 선택" : "\(selected.count)장 선택됨"
    }
    private var deleteConfirmTitle: String {
        "선택한 \(selected.count)장을 삭제할까요?"
    }

    /// 하단 삭제 바 — 들린 블랙 위 파괴적 액션. 탭 → 확인 다이얼로그.
    private var deleteBar: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Text("삭제 (\(selected.count))")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .background(Color.mellowShadow)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.mellowBorder.opacity(0.25)).frame(height: 0.5)   // 얇은 구분선
        }
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: gap) {
                ForEach(captures) { capture in
                    cellWrapper(for: capture)
                        .buttonStyle(.plain)   // 기본 틴트/하이라이트 제거 — 셀 그대로
                        .transition(.scale(scale: 0.8).combined(with: .opacity))   // Photos식 제거 전환
                }
            }
            .padding(gap)
        }
    }

    /// 탭 라우팅: 편집 모드 = 선택 토글(내비게이션 없음), 평소 = 상세 열기. 식별자는 ForEach id라
    /// 래퍼만 바뀌어도 셀 정체성은 유지된다.
    @ViewBuilder
    private func cellWrapper(for capture: Capture) -> some View {
        if isEditing {
            Button { toggle(capture.id) } label: {
                GalleryCell(capture: capture, isEditing: true, isSelected: selected.contains(capture.id))
            }
        } else {
            NavigationLink(value: capture.id) {
                GalleryCell(capture: capture, isEditing: false, isSelected: false)
            }
        }
    }

    /// 빈 상태 — 차분한 따뜻한 초대(빈 그리드 금지).
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Color.mellowAccent)
            Text("아직 담긴 순간이 없어요")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.mellowIvory)
            Text("셔터를 눌러 첫 필름을 남겨보세요")
                .font(.system(size: 14))
                .foregroundStyle(Color.mellowIvory.opacity(0.7))
        }
        .padding(40)
    }

    // MARK: - Actions

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func exitEditMode() {
        isEditing = false
        selected.removeAll()
    }

    /// 선택분 일괄 삭제 — 스토어 원자적 삭제(단일 쓰기) + 캐시 축출, 그 다음 그리드에서
    /// 애니메이션 제거(스케일/페이드 아웃 + 리플로우). 실패 시 알림, 아무것도 안 지움.
    private func performDelete() {
        let ids = selected
        guard !ids.isEmpty else { return }
        do {
            try CaptureStore.shared.deleteMany(ids)            // 원자적: 레코드 한 번 쓰고 파일들 제거
        } catch {
            deleteFailed = true                                 // 반쪽 삭제 없음 — 그대로 두고 알림
            return
        }
        for id in ids { CaptureThumbnailRenderer.shared.evict(id: id) }   // 두 캐시에서 스테일 제거
        withAnimation(.easeInOut(duration: 0.3)) {
            captures.removeAll { ids.contains($0.id) }
        }
        exitEditMode()
    }

    /// 상세 뷰에서 단일 삭제 후 돌아왔을 때 — 스토어(진실)와 디핑해 사라진 셀만 같은 애니메이션으로
    /// 제거한다. 그냥 뒤로 나온 경우(삭제 없음)는 liveIDs가 일치 → no-op, 깜빡임 없음.
    private func reconcileAfterDetail() {
        let liveIDs = Set(CaptureStore.shared.allNewestFirst.map(\.id))
        guard captures.contains(where: { !liveIDs.contains($0.id) }) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            captures.removeAll { !liveIDs.contains($0.id) }
        }
    }
}

/// 그리드 셀 — 1:1 중앙 크롭의 **필터 적용** 썸네일. 다운스케일→필터→캐시 경로 재사용.
/// 편집 모드에선 선택 인디케이터(§9)를 오버레이한다 — 썸네일 렌더 경로는 건드리지 않는다.
private struct GalleryCell: View {
    let capture: Capture
    var isEditing: Bool = false
    var isSelected: Bool = false
    /// 렌더 해상도(px). 셀 표시 크기와 무관한 화질 기준 — 작게 유지.
    private let renderSide = 320

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.mellowBgRaised                       // 로드 전 차분한 자리
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()                    // 1:1 셀을 꽉 채우고 넘침은 클립
            }
        }
        .aspectRatio(1, contentMode: .fill)            // 정사각 셀
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {                                     // 선택 시 앰버 링 강조
            if isEditing && isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.mellowAccent, lineWidth: 3)
            }
        }
        .overlay(alignment: .bottomTrailing) {         // 선택 인디케이터(체크/빈 원)
            if isEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(isSelected ? Color.mellowIvory : Color.mellowIvory.opacity(0.9),
                                     isSelected ? Color.mellowAccent : Color.clear)
                    .padding(6)
                    .shadow(color: Color.mellowShadow.opacity(0.45), radius: 2)
            }
        }
        .task(id: capture.id) { await load() }         // 셀 재사용 시 capture 바뀌면 재로드
    }

    @MainActor private func load() async {
        // 1) 캐시 즉시 조회 — 이미 렌더된 셀은 깜빡임 없이 바로.
        if let cached = CaptureThumbnailRenderer.shared.cachedSquare(id: capture.id, side: renderSide) {
            image = cached
            return
        }
        // 2) 미스 → 백그라운드 렌더(메인 비차단). 풀해상도 필터링 없음(다운스케일 후 필터).
        let cap = capture
        let url = CaptureStore.shared.url(for: cap)
        let side = renderSide
        let rendered = await Task.detached(priority: .utility) {
            await CaptureThumbnailRenderer.shared.squareThumbnail(id: cap.id, url: url,
                                                                  filterID: cap.filterID, side: side)
        }.value
        if let rendered { image = rendered }           // UI 설정은 메인(@MainActor)
    }
}
