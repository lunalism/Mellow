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

    /// **freeze-last-frame 오버레이** (블랙 플래시 방지). 세션 정지 시 마지막 프레임을 이 UIImageView에
    /// 얹어 재시작 갭 동안 검정 대신 정지 프레임을 보여준다. metal 레이어가 아니라 일반 UIImageView라
    /// 윈도우 detach에도 내용이 유지된다(CAMetalLayer의 콘텐츠 손실 함정을 피함).
    private let freezeOverlay = UIImageView()
    /// videoQueue(renderFrame)와 메인(freeze/clear) 사이의 frozen 상태 보호.
    private let freezeLock = NSLock()
    private var frozen = false
    /// freeze 세대 토큰. freeze(with:)마다 증가(freezeLock 하). presented-handler hide는
    /// encode 시점에 캡처한 세대와 비교해, 그 사이 새 freeze가 오면 스킵한다.
    /// 공유 Bool 재검사만으로는 부족 — 세션 정지 중 대기열의 낙오 프레임이 frozen을 다시
    /// 내려 버리면 더 오래된 hide가 통과해 새 오버레이를 걷어낸다(Codex 리뷰 지적).
    private var freezeGeneration: UInt64 = 0

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
        // 세션 재시작 갭(~0.2–0.3s): drawable을 잃은 빈 metal 표면은 컴포지터에서 순검정(#000)으로
        // 뜬다. backgroundColor를 들린 블랙(#3B362E)으로 깔아 그 갭이 순검정 대신 브랜드 톤이 되게 한다.
        metalLayer.backgroundColor = UIColor(red: 0x3B/255, green: 0x36/255, blue: 0x2E/255, alpha: 1).cgColor
        // ⚠️ metalLayer.colorspace는 **미설정(default)**으로 둔다. bgra8Unorm 픽셀은 이미
        //    sRGB 인코딩됨 — colorspace=sRGB로 강제하면 이중 해석되어 색이 밀린다. MTKView 이전
        //    동작과 동일하게 default 유지(이것이 β에서 색이 드리프트할 수 있는 유일한 지점).

        isOpaque = false
        isUserInteractionEnabled = false             // 스와이프/엣지 제스처가 상위 SwiftUI로 전달되도록

        // freeze 오버레이 — 라이브 프리뷰와 동일한 aspect-fill 크롭. 기본 숨김.
        freezeOverlay.frame = bounds
        freezeOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        freezeOverlay.contentMode = .scaleAspectFill
        freezeOverlay.clipsToBounds = true
        freezeOverlay.isUserInteractionEnabled = false
        freezeOverlay.isHidden = true
        addSubview(freezeOverlay)                     // metal 콘텐츠 위(서브뷰)에 합성됨
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
        freezeOverlay.frame = bounds          // 오버레이를 항상 프리뷰 카드에 정확히 맞춤
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
        #if DEBUG
        // MTRACE5 폴트 인젝션: 렌더 커밋 스톨 재현(워치독 검증용). drawable 획득 **전** 리턴 —
        // 백프레셔·풀 상태를 건드리지 않고 "커밋이 멈춘" 상황만 만든다. 릴리스엔 없음.
        if ThermalDiagnostics.suppressRenderForTesting { return }
        #endif
        sizeLock.lock()
        let size = drawablePixelSize
        sizeLock.unlock()
        guard size.width > 0, size.height > 0 else { return }

        // 진입 세대 캡처 — 블로킹 작업(nextDrawable~렌더) **전**. 이 프레임이 시작된 뒤
        // freeze가 도착하면(세대 증가) 아래 clearing 판정에서 탈락시켜, freeze 이전에 시작된
        // 프레임이 post-freeze 프레임으로 위장해 새 오버레이를 걷어내는 것을 막는다(Codex P1).
        freezeLock.lock()
        let entryGeneration = freezeGeneration
        freezeLock.unlock()

        // nextDrawable() 블로킹 = 의도된 백프레셔(videoQueue에서만; 늦은 프레임은 상류에서 폐기).
        #if DEBUG
        // 프리즈 진단: nextDrawable 소요 측정. nil(≈1s 타임아웃=drawable 고갈) 또는 >100ms면 기록.
        // (성공 프레임마다 찍지 않아 near-zero. 영구 블록이면 이 호출이 반환 안 해 로그도 안 남 —
        //  그 경우는 SAMPLE의 frames=0 + 이 라인 부재로 판별.)
        let drawStart = CACurrentMediaTime()
        let nextDrawable = metalLayer.nextDrawable()
        let drawMs = (CACurrentMediaTime() - drawStart) * 1000
        if nextDrawable == nil { ThermalDiagnostics.shared.noteDrawableNil() }
        else if drawMs > 100 { ThermalDiagnostics.shared.noteDrawableStall(ms: drawMs) }
        guard let drawable = nextDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        #else
        guard let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        #endif

        let target = CGRect(origin: .zero, size: size)
        let filled = Self.aspectFill(image, into: target)

        ciContext.render(filled,
                         to: drawable.texture,
                         commandBuffer: commandBuffer,
                         bounds: target,
                         colorSpace: renderColorSpace)

        // freeze 해제: 재시작 후 첫 실제 프레임에서만(타이머 아님). drawable이 **화면에 뜬 순간**
        // (presented handler) 오버레이를 숨겨 검정도 seam도 없이 라이브로 스왑한다.
        freezeLock.lock()
        // clearing 조건: frozen이고 **이 프레임 진입 후 새 freeze가 없었을 때만**.
        // 세대가 다르면 이 프레임은 freeze 이전에 시작된 낙오 프레임 — frozen을 건드리지 않고
        // hide도 걸지 않는다(프레임 자체는 present돼도 무해 — 오버레이가 위에 있다).
        let clearing = frozen && freezeGeneration == entryGeneration
        if clearing { frozen = false }
        let encodedGeneration = freezeGeneration
        freezeLock.unlock()
        if clearing {
            drawable.addPresentedHandler { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    // 오래된 hide 가드: 이 프레임 encode 이후 새 freeze가 도착했으면 이 hide는
                    // 무효 — 오버레이·미러를 건드리지 않는다. 세대 비교로 판정한다(frozen 재검사는
                    // 불충분 — 낙오 프레임이 그 사이 frozen을 다시 내릴 수 있다). frozen이 다시
                    // true가 되는 경로는 freeze뿐이고 freeze는 항상 세대를 올리므로 비교가 포섭한다.
                    self.freezeLock.lock()
                    let stale = self.freezeGeneration != encodedGeneration
                    self.freezeLock.unlock()
                    if stale {
                        #if DEBUG
                        ThermalDiagnostics.shared.noteStaleHideSkipped()
                        #endif
                        return
                    }
                    self.freezeOverlay.isHidden = true
                    self.freezeOverlay.image = nil
                    self.mirrorOverlayVisible(false)   // 워치독 미러 — 가시성 변화 지점 2/2
                }
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
        // 성공-프레임 하트비트(스톨 워치독 신호). commit **직후**에만 — 위의 조기 리턴
        // (사이즈 0·nil drawable·nil 커맨드버퍼)은 성공으로 세지 않는다.
        recordRenderCommit()
    }

    // MARK: 스톨 워치독 신호 (production — 복구 킥이 Release에서 돌므로 DEBUG 아님)

    /// 마지막 성공 렌더 커밋의 단조 시각(CACurrentMediaTime). 0 = 아직 커밋 없음.
    /// videoQueue에서 쓰고 워치독 큐·(DEBUG) 진단 큐에서 읽는다 → NSLock 보호.
    /// ⚠️ 벽시계(Date) 금지 — 시계 조정에 흔들리지 않는 단조 시계만 쓴다.
    private let commitLock = NSLock()
    private var lastRenderCommit: CFTimeInterval = 0

    func lastRenderCommitTime() -> CFTimeInterval {
        commitLock.lock()
        defer { commitLock.unlock() }
        return lastRenderCommit
    }

    private func recordRenderCommit() {
        let now = CACurrentMediaTime()
        commitLock.lock()
        lastRenderCommit = now
        commitLock.unlock()
    }

    /// UIView.isHidden은 메인 전용이라 워치독(비메인 큐)이 직접 읽을 수 없다. 가시성이 바뀌는
    /// 두 지점(freeze / presented-handler 해제) 모두 메인에서 이 미러를 세트하고, 워치독은
    /// 잠금으로 읽는다. **freeze/해제 로직 자체는 건드리지 않는다** — 순수 관측.
    private let overlayMirrorLock = NSLock()
    private var overlayVisibleMirror = false
    var isOverlayVisible: Bool {
        overlayMirrorLock.lock()
        defer { overlayMirrorLock.unlock() }
        return overlayVisibleMirror
    }
    private func mirrorOverlayVisible(_ visible: Bool) {
        overlayMirrorLock.lock()
        overlayVisibleMirror = visible
        overlayMirrorLock.unlock()
    }

    /// 세션 정지 시 마지막 프레임을 오버레이에 얹는다(메인). 이미 표시 중이면 재변환하지 않는다.
    /// ciImage가 nil이면 caller에서 걸러진다 — 최초 시작(보관 프레임 없음)엔 호출되지 않아 오버레이는 숨김 유지.
    /// 변환은 정지 시 1회뿐(프레임당 아님) — 정지 순간(보관함 커버 애니메이션 중)의 짧은 GPU readback.
    func freeze(with ciImage: CIImage) {
        guard freezeOverlay.isHidden else {
            // 이미 정지 프레임 표시 중 → 중복 변환은 스킵하되 frozen은 다시 세운다.
            // 레이스 클로저: renderFrame이 encode 시점에 frozen을 내렸지만 presented-handler
            // hide가 아직 안 돈 갭에 freeze가 오면, 여기서 frozen을 재세트하지 않으면
            // pending hide가 새 freeze 의도를 무시하고 오버레이를 걷어낸다.
            // (미러는 이 경로에서 이미 true — hide 클로저만 false로 내리는데 아직 안 돌았다.)
            freezeLock.lock()
            frozen = true
            freezeGeneration &+= 1
            freezeLock.unlock()
            return
        }
        guard let cg = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        freezeOverlay.image = UIImage(cgImage: cg)
        freezeOverlay.isHidden = false
        mirrorOverlayVisible(true)   // 워치독 미러 — 가시성 변화 지점 1/2
        freezeLock.lock()
        frozen = true
        freezeGeneration &+= 1
        freezeLock.unlock()
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
