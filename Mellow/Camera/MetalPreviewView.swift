import UIKit
import Metal
import QuartzCore
import CoreImage

/// Metal 기반 라이브 프리뷰 (Stage L3.5 — CAMetalLayer 직접, 오프메인 렌더).
///
/// 이전(MTKView)에는 `setNeedsDisplay` → CoreAnimation 커밋 사이클에서 draw가 **메인 스레드**로
/// 직렬화되어 프리뷰가 ~15fps에 고정됐다(draw=40.8% CPU, 실제 render는 0.0% — 구조적 병목).
/// 이제 `CAMetalLayer.nextDrawable()`(Apple 공식 오프메인 경로)로 **videoQueue에서** 직접
/// 렌더한다. 색 파이프라인은 L3와 **동일**(명시적 sRGB) — WYSIWYG 재검증 대상.
/// aspect-FILL로 drawable(= 9:16 카드)을 채우고 넘침은 크롭 — 프리뷰 레이어와 동일.
final class MetalPreviewView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }  // layerClass 보장 — 실패 불가

    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    /// 라이브 색 파이프라인을 **명시적 sRGB**로 고정(L3 Decision A). deviceRGB≈sRGB에
    /// 암묵 의존하지 않고, L2/Photoshop 검증과 동일한 WYSIWYG를 구조적으로 보장한다.
    private let renderColorSpace: CGColorSpace

    /// drawableSize 스냅샷. layoutSubviews(메인)에서 갱신, renderFrame(videoQueue)에서 읽는다.
    /// 라이브 프로퍼티를 오프메인에서 직접 읽지 않기 위한 잠금 보호 스냅샷(레이스 방지).
    private let sizeLock = NSLock()
    private var drawablePixelSize: CGSize = .zero

    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal을 사용할 수 없는 기기입니다.")
        }
        self.commandQueue = queue
        // 워킹·출력 색공간을 명시적 sRGB로 통일 → CI가 숨은 변환 커널을 끼워넣지 않음(발열↓)
        // + 프리뷰 색이 검증된 정적 결과와 일치. sRGB 생성 실패 시에만 deviceRGB로 폴백.
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        self.renderColorSpace = srgb
        // GPU 렌더 컨텍스트. 소프트웨어 렌더러 사용 안 함.
        self.ciContext = CIContext(mtlDevice: device, options: [
            .cacheIntermediates: false,
            .workingColorSpace: srgb,
            .highQualityDownsample: false,
            .name: "MellowPreview"
        ])
        super.init(frame: .zero)

        // CAMetalLayer 구성. framebufferOnly=false → CIContext가 drawable 텍스처에 직접 쓸 수 있음.
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.presentsWithTransaction = false   // present를 CA 트랜잭션에 묶지 않음(오프메인 유지)
        metalLayer.isOpaque = false                  // 첫 프레임 전, 뒤의 페이퍼 플레이스홀더가 비치도록
        // ⚠️ metalLayer.colorspace는 **미설정(default)**으로 둔다. bgra8Unorm 픽셀은 이미
        //    sRGB 인코딩됨 — colorspace=sRGB로 강제하면 이중 해석되어 색이 밀린다. MTKView 이전
        //    동작과 동일하게 default 유지(이것이 β에서 색이 드리프트할 수 있는 유일한 지점).

        isOpaque = false
        isUserInteractionEnabled = false             // 스와이프/엣지 제스처가 상위 SwiftUI로 전달되도록
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 메인 스레드. drawableSize = bounds × **화면 스케일**(MTKView가 autoResizeDrawable로
    /// 자동 공급하던 값을 재현). ⚠️ view.contentScaleFactor는 이 UIView에서 1.0으로 나와
    /// drawable이 1/3 해상도가 됐다(계단 현상). 반드시 screen.scale를 쓴다(nil이면 main 폴백).
    /// 세로 고정이라 사실상 최초 1회만 발생하지만 정확히 계산한다.
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = size
        sizeLock.lock()
        drawablePixelSize = size
        sizeLock.unlock()
    }

    /// 뷰가 윈도우에 붙는 시점에 스케일을 일관되게 맞춰 둔다(정합성용).
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let scale = window?.screen.scale {
            contentScaleFactor = scale
        }
    }

    /// **videoQueue(오프메인)에서 호출.** 자체 drawable을 받아 렌더 → present → commit.
    /// 본문은 이전 draw(_:)와 동일 — 오프메인 + 직접 drawable만 다르다.
    /// nil drawable/사이즈 0이면 프레임을 조용히 건너뛴다(크래시·블랙프레임 없음).
    func renderFrame(_ image: CIImage) {
        sizeLock.lock()
        let size = drawablePixelSize
        sizeLock.unlock()
        guard size.width > 0, size.height > 0 else { return }

        // nextDrawable() 블로킹 = 의도된 백프레셔(videoQueue에서만; 늦은 프레임은 상류에서 폐기).
        guard let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let target = CGRect(origin: .zero, size: size)
        let filled = Self.aspectFill(image, into: target)

        ciContext.render(filled,
                         to: drawable.texture,
                         commandBuffer: commandBuffer,
                         bounds: target,
                         colorSpace: renderColorSpace)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// 이미지를 rect에 꽉 채우고(cover) 넘침은 크롭. AVLayer의 resizeAspectFill과 동일.
    private static func aspectFill(_ image: CIImage, into rect: CGRect) -> CIImage {
        let ext = image.extent
        guard ext.width > 0, ext.height > 0 else { return image }
        let scale = max(rect.width / ext.width, rect.height / ext.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = rect.midX - scaled.extent.midX
        let dy = rect.midY - scaled.extent.midY
        return scaled
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .cropped(to: rect)
    }
}
