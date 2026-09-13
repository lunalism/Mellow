import UIKit

enum CameraDeviceOrientation: String, Sendable, CaseIterable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown, unknown, unstable
    init(_ value: UIDeviceOrientation) {
        switch value {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        case .faceUp: self = .faceUp
        case .faceDown: self = .faceDown
        default: self = .unknown
        }
    }
    func matches(_ project: ProjectOrientation) -> Bool {
        switch (project, self) {
        case (.portrait9x16, .portrait), (.landscape16x9, .landscapeLeft), (.landscape16x9, .landscapeRight): return true
        default: return false
        }
    }
    /// A posture the device can actually be held in; face up/down, unknown and unstable are not
    /// capture postures and must never be presented as a landscape mismatch on their own.
    var isDefinite: Bool {
        switch self {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight: return true
        case .faceUp, .faceDown, .unknown, .unstable: return false
        }
    }
}

enum CameraInterfaceOrientation: Sendable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight, unknown
    init(_ orientation: UIInterfaceOrientation) {
        switch orientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: self = .unknown
        }
    }
    var previewAngle: CGFloat? {
        switch self {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        case .unknown: return nil
        }
    }
    /// Provisional physical posture before any stable device reading exists (UIDevice reports
    /// `.unknown` until the first rotation). Interface and device landscape sides are inverted.
    var provisionalPosture: CameraDeviceOrientation {
        switch self {
        case .portrait, .unknown: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        }
    }
}

struct CameraPreviewPresentation: Equatable {
    var angle: CGFloat = 90
    var mirrored = false
}

@MainActor
protocol CameraOrientationSource: AnyObject {
    var current: CameraDeviceOrientation { get }
    func start(_ update: @escaping @MainActor (CameraDeviceOrientation) -> Void)
    func stop()
}

/// UIKit classifies physical posture. Every change immediately makes capture ineligible;
/// 150ms of unchanged posture settles the signal, without changing project/interface state.
@MainActor
final class DeviceCameraOrientationSource: CameraOrientationSource {
    private(set) var current: CameraDeviceOrientation = .unknown
    private var observation: Task<Void, Never>?
    private var settle: Task<Void, Never>?
    func start(_ update: @escaping @MainActor (CameraDeviceOrientation) -> Void) {
        guard observation == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        receive(update)
        observation = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIDevice.orientationDidChangeNotification) {
                guard !Task.isCancelled else { return }
                self?.receive(update)
            }
        }
    }
    private func receive(_ update: @escaping @MainActor (CameraDeviceOrientation) -> Void) {
        settle?.cancel()
        current = .unstable
        update(.unstable)
        settle = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self else { return }
            current = CameraDeviceOrientation(UIDevice.current.orientation)
            update(current)
        }
    }
    func stop() {
        observation?.cancel(); observation = nil
        settle?.cancel(); settle = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    deinit { observation?.cancel(); settle?.cancel() }
}

#if DEBUG
@MainActor
final class FakeCameraOrientationSource: CameraOrientationSource {
    var current: CameraDeviceOrientation
    private var update: (@MainActor (CameraDeviceOrientation) -> Void)?
    init(_ orientation: CameraDeviceOrientation = .portrait) { current = orientation }
    func start(_ update: @escaping @MainActor (CameraDeviceOrientation) -> Void) { self.update = update; update(current) }
    func stop() { update = nil }
    func send(_ value: CameraDeviceOrientation) { current = value; update?(value) }
}
#endif
