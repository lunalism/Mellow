import SwiftUI
import UIKit

/// 사진 상세 뷰의 핀치/더블탭 줌 + 팬 엔진 (Phase 1 · Stage 4b-3, 3/n).
///
/// iOS 표준(사진 앱과 동일)인 `UIScrollView` + `UIImageView` 줌 파이프라인을 그대로 감싼다.
/// **이미 렌더된 이미지를 그대로 표시**한다 — `PhotoDetailPage`가 `fullCache` /
/// `FilterPreset.makeChain`으로 만든 바로 그 `UIImage`를 받아 레이어 트랜스폼만 한다.
/// 줌/팬은 필터 체인을 다시 돌리지 않는 순수 변환이므로 두 번째 렌더 경로가 없다(WYSIWYG 유지).
///
/// 제스처 핸드오프(핵심):
/// - `zoomScale == 1.0`이면 콘텐츠가 bounds에 딱 맞아(가로/세로 오버플로 없음, `alwaysBounce*` 꺼짐)
///   내부 스크롤뷰가 가로 드래그를 **가져가지 않는다** → 바깥 `.page` TabView 페이징과
///   좌측 엣지 뒤로가기(NavigationStack)가 예전 그대로 동작한다.
/// - `zoomScale > 1.0`이면 내부 스크롤뷰가 팬을 소비(경계에서 `bounces`로 러버밴드)하므로
///   가로 팬이 다음 사진으로 페이징되지 않는다. 이것이 페이징을 막는 **주** 기제다.
///   부모의 `.scrollDisabled(isZoomed)`는 보조 안전장치(§리포트 참고).
struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage
    /// 현재 보이는(선택된) 페이지인지. false로 바뀌면 그 페이지 줌을 1.0으로 리셋한다
    /// (fullCache 페이지 재사용으로 스테일 줌이 남는 것을 방지).
    let isActive: Bool
    /// 줌 여부(zoomScale > 1)를 부모로 올려 보내 TabView 페이징 억제에 쓰게 한다.
    let onZoomChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onZoomChange: onZoomChange) }

    func makeUIView(context: Context) -> CenteringScrollView {
        let scrollView = CenteringScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 3.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false   // zoom==1에서 가로 드래그를 가져가지 않도록
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear          // 페이지의 들린 블랙(mellowShadow)이 비쳐 보이게

        scrollView.imageView.image = image
        scrollView.imageView.contentMode = .scaleAspectFit
        scrollView.imageView.clipsToBounds = true
        context.coordinator.scrollView = scrollView

        // 더블탭으로 1.0 ↔ 2.5x 토글(탭 지점 기준). 단일탭 액션이 없으므로 충돌 없음.
        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: CenteringScrollView, context: Context) {
        context.coordinator.onZoomChange = onZoomChange
        if scrollView.imageView.image !== image {
            scrollView.imageView.image = image
            scrollView.setNeedsLayout()
        }
        // 이 페이지가 더 이상 활성(보이는) 페이지가 아니면 줌을 1.0으로 되돌린다(애니메이션 없음).
        if !isActive && scrollView.zoomScale != 1.0 {
            scrollView.setZoomScale(1.0, animated: false)
            context.coordinator.reportZoom(scrollView)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: CenteringScrollView?
        var onZoomChange: (Bool) -> Void
        private var lastReportedZoomed = false

        init(onZoomChange: @escaping (Bool) -> Void) { self.onZoomChange = onZoomChange }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? CenteringScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? CenteringScrollView)?.centerContent()
            reportZoom(scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            reportZoom(scrollView)
        }

        /// zoomScale > 1 여부가 바뀔 때만 부모로 알린다(불필요한 상태 갱신 방지).
        func reportZoom(_ scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > 1.0001
            guard zoomed != lastReportedZoomed else { return }
            lastReportedZoomed = zoomed
            onZoomChange(zoomed)
        }

        @objc func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let targetScale: CGFloat = 2.5
                let point = gr.location(in: scrollView.imageView)
                let size = CGSize(width: scrollView.bounds.width / targetScale,
                                  height: scrollView.bounds.height / targetScale)
                let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }
    }
}

/// `UIScrollView` 서브클래스 — 이미지를 bounds에 맞춰 배치하고(줌 1.0에서만 리핏)
/// contentInset으로 중앙 정렬한다. `layoutSubviews`에서 처리해 초기 배치·회전·bounds 변화를
/// 모두 자동으로 커버한다. 컨테이너 종횡비 == 이미지 종횡비(부모의 `.aspectRatio`)라
/// 줌 1.0에서 이미지가 bounds를 정확히 채운다 → 보더가 이미지에 딱 붙는다.
final class CenteringScrollView: UIScrollView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(imageView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        // 줌 1.0에서만 기준 프레임/콘텐츠 크기를 다시 맞춘다(줌 중엔 스크롤뷰가 관리).
        if zoomScale == 1.0 {
            let imgSize = image.size
            let scale = min(bounds.width / imgSize.width, bounds.height / imgSize.height)
            let fitted = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
            imageView.frame = CGRect(origin: .zero, size: fitted)
            contentSize = fitted
        }
        centerContent()
    }

    /// 콘텐츠가 bounds보다 작은 축은 contentInset으로 가운데 정렬(줌 최소·리셋 시 항상 중앙).
    func centerContent() {
        let content = imageView.frame.size
        let insetX = max(0, (bounds.width - content.width) / 2)
        let insetY = max(0, (bounds.height - content.height) / 2)
        contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }
}
