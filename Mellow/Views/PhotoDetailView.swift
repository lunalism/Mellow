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
/// 범위(2/n): 페이징만. 줌/팬·삭제·사진앱 내보내기는 이후 단계.
struct PhotoDetailView: View {
    let captures: [Capture]
    @State private var selection: UUID

    /// 상세 렌더 해상도 = 화면 긴 변 px(**다운스케일, 풀해상도 아님**). 화면에선 풀해상도와 동일하게 보인다.
    private let maxPixels = Int(max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height))

    init(captures: [Capture], startID: UUID) {
        self.captures = captures
        _selection = State(initialValue: startID)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(captures) { capture in
                PhotoDetailPage(capture: capture, maxPixels: maxPixels)
                    .tag(capture.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))   // 가로 페이징, 점 인디케이터 없음
        .background(Color.mellowShadow.ignoresSafeArea())  // 들린 블랙 chrome (#3B362E)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(currentDateText)                // 헤더는 현재 보이는 사진을 따라 갱신
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.mellowShadow, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task(id: selection) { prefetchNeighbors() }     // 선택이 바뀔 때마다 인접 페이지 프리페치
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

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.mellowShadow                 // 페이지 배경(스와이프 중에도 연속된 들린 블랙)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()             // 9:16 전체가 보이도록(크롭 없음)
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
