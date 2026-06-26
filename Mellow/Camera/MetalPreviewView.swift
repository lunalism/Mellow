import MetalKit
import CoreImage

/// Metal 기반 라이브 프리뷰 (Phase 1 Spec §7).
///
/// CIImage를 **Metal-backed CIContext**로 MTKView의 drawable에 렌더한다(GPU 전용,
/// CPU 렌더 없음). 새 프레임이 도착할 때만 그린다(enableSetNeedsDisplay).
/// aspect-FILL로 drawable(= 9:16 카드)을 채우고 넘침은 크롭 — 프리뷰 레이어와 동일.
final class MetalPreviewView: MTKView {
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let renderColorSpace = CGColorSpaceCreateDeviceRGB()

    /// 렌더할 최신 프레임(방향 보정된 CIImage). 메인 스레드에서 설정.
    var image: CIImage? {
        didSet { setNeedsDisplay() }
    }

    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal을 사용할 수 없는 기기입니다.")
        }
        self.commandQueue = queue
        // GPU 렌더 컨텍스트. 소프트웨어 렌더러 사용 안 함.
        self.ciContext = CIContext(mtlDevice: device, options: [
            .cacheIntermediates: false,
            .name: "MellowPreview"
        ])
        super.init(frame: .zero, device: device)

        framebufferOnly = false          // CIContext가 drawable 텍스처에 직접 써야 함
        colorPixelFormat = .bgra8Unorm
        isOpaque = false                 // 첫 프레임 전, 뒤의 페이퍼 플레이스홀더가 비치도록
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        isPaused = true                  // 프레임 도착 시에만 그린다(상시 렌더 루프 없음)
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let image,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let target = CGRect(origin: .zero, size: drawableSize)
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
