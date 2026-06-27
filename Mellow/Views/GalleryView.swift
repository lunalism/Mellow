import SwiftUI

/// 인앱 "필름 다이어리" 갤러리 그리드 (Phase 1 Spec §2.3 · Stage 4b-2).
///
/// 앱 **자체** 보관함(`Documents/Originals` + `captures.json`) — 시스템 사진 앱이 아니다.
/// `CaptureStore`(4a/4b-1과 동일한 단일 소스)에서 최신순으로 읽어 3열 정사각 그리드로 보여준다.
/// 셀 색은 **비파괴 재렌더**(무필터 원본 + filterID를 프리뷰와 같은 체인으로) — WYSIWYG.
///
/// 범위: 그리드만. 상세 뷰(4b-3)·삭제·사진앱 익스포트는 아직 없다.
struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var captures: [Capture] = []

    private let gap: CGFloat = 3
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gap), count: 3)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mellowShadow.ignoresSafeArea()   // 들린 블랙 chrome (#3B362E), 카메라와 연속성
                if captures.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("필름 다이어리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.mellowIvory)
                    }
                    .accessibilityLabel("카메라로 돌아가기")
                }
            }
            .toolbarBackground(Color.mellowShadow, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // 셀 탭 → 상세 뷰(4b-3). UUID로 라우팅해 Capture 모델은 건드리지 않는다.
            .navigationDestination(for: UUID.self) { id in
                if let capture = captures.first(where: { $0.id == id }) {
                    PhotoDetailView(capture: capture)
                }
            }
        }
        .tint(Color.mellowAccent)      // 뒤로가기 등 시스템 액센트를 앰버로(온브랜드)
        .preferredColorScheme(.dark)   // 어두운 chrome → 라이트 상태바
        .onAppear { captures = CaptureStore.shared.allNewestFirst }   // 단일 소스, 최신순 스냅샷
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: gap) {
                ForEach(captures) { capture in
                    NavigationLink(value: capture.id) {
                        GalleryCell(capture: capture)
                    }
                    .buttonStyle(.plain)   // 기본 틴트/하이라이트 제거 — 셀 그대로
                }
            }
            .padding(gap)
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
}

/// 그리드 셀 — 1:1 중앙 크롭의 **필터 적용** 썸네일. 다운스케일→필터→캐시 경로 재사용.
private struct GalleryCell: View {
    let capture: Capture
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
            CaptureThumbnailRenderer.shared.squareThumbnail(id: cap.id, url: url,
                                                            filterID: cap.filterID, side: side)
        }.value
        if let rendered { image = rendered }           // UI 설정은 메인(@MainActor)
    }
}
