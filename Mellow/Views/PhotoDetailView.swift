import SwiftUI

/// 사진 상세 뷰 (Phase 1 · Stage 4b-3, 1/n). 단일 캡처를 **9:16 전체 프레이밍**으로 크게 보여준다.
///
/// 색은 **비파괴 재렌더** — 무필터 원본 + `filterID`를 라이브 프리뷰·썸네일·갤러리 셀과
/// **같은 `FilterPreset.makeChain`**으로 렌더한다(WYSIWYG). 처음으로 (거의) 전체 해상도에
/// 필터를 적용하는 화면이다.
///
/// 성능: 풀해상도(2268×4032)를 굳이 처리하지 않고 **화면 크기로 다운스케일**해 렌더한다
/// (화면에선 동일하게 보인다). 렌더는 메인 밖에서 수행하고 그동안 짧은 로딩을 보여준다.
///
/// 범위(1/n): 단일 사진 표시만. 사진 간 스와이프·줌/팬·삭제·사진앱 내보내기는 이후 단계.
struct PhotoDetailView: View {
    let capture: Capture

    @State private var image: UIImage?

    /// 상세 렌더 해상도 = 화면 긴 변 px(**다운스케일, 풀해상도 아님**). 화면에선 풀해상도와 동일하게 보인다.
    private let maxPixels = Int(max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height))

    var body: some View {
        ZStack {
            Color.mellowShadow.ignoresSafeArea()   // 들린 블랙 chrome (#3B362E)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()                 // 9:16 전체가 보이도록(크롭 없음)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.mellowBorder.opacity(0.6), lineWidth: 1)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                ProgressView()                     // 짧은 로딩 — 백그라운드 렌더 동안
                    .tint(Color.mellowAccent)
            }
        }
        .navigationTitle(Self.dateText(capture.createdAt))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.mellowShadow, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task(id: capture.id) { await load() }
    }

    @MainActor private func load() async {
        // 1) 캐시 즉시 조회 — 재진입은 깜빡임 없이 바로.
        if let cached = CaptureThumbnailRenderer.shared.cachedFullFrame(id: capture.id, maxPixelSize: maxPixels) {
            image = cached
            return
        }
        // 2) 미스 → 백그라운드 렌더(메인 비차단). 사용자가 기다리는 화면이라 .userInitiated.
        let cap = capture
        let url = CaptureStore.shared.url(for: cap)
        let px = maxPixels
        let rendered = await Task.detached(priority: .userInitiated) {
            CaptureThumbnailRenderer.shared.fullFrameThumbnail(id: cap.id, url: url,
                                                               filterID: cap.filterID, maxPixelSize: px)
        }.value
        if let rendered { image = rendered }       // UI 설정은 메인(@MainActor)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("yMMMdjm")   // 지역화된 날짜·시간
        return f
    }()

    private static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }
}
