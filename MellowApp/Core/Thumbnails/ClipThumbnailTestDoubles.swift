#if DEBUG
import CoreGraphics
import Foundation

/// Deterministic thumbnail stand-ins shared by unit tests and the opted-in simulator UI tests. They
/// never decode media, so UI automation does not depend on AVFoundation timing. Never compiled into
/// Release.

/// Draws a portrait "frame": a warm-to-cool vertical gradient whose hue is fixed by `seed`, plus a
/// soft highlight, so fixture thumbnails are visibly distinct per clip and stable across runs.
enum SyntheticThumbnailImage {
    static func make(seed: Int, size: CGSize) -> CGImage {
        let width = max(1, Int(size.width)), height = max(1, Int(size.height))
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let hue = CGFloat((seed * 137) % 360) / 360
        let top = color(hue: hue, saturation: 0.55, brightness: 0.95)
        let bottom = color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.45)
        let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: .zero, options: [])
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
        let radius = CGFloat(min(width, height)) * 0.28
        context.fillEllipse(in: CGRect(x: CGFloat(width) * 0.5 - radius, y: CGFloat(height) * 0.62 - radius, width: radius * 2, height: radius * 2))
        return context.makeImage()!
    }

    private static func color(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> CGColor {
        // HSB → RGB without UIKit so this stays usable from any context.
        let c = brightness * saturation, x = c * (1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1)), m = brightness - c
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch Int(hue * 6) % 6 {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return CGColor(red: r + m, green: g + m, blue: b + m, alpha: 1)
    }
}

/// Scripted provider. `immediate` answers at once from the script (unknown clips get a synthetic
/// image seeded by their identity); `gated` holds every request until the test completes it by
/// clip, which is how out-of-order and stale completions are driven deterministically.
actor FakeClipThumbnailProvider: ClipThumbnailProviding {
    enum Outcome: Sendable {
        case image(seed: Int)
        case failure(ClipThumbnailError)
    }

    private let script: [UUID: Outcome]
    private let gated: Bool
    private var pending: [ClipThumbnailRequest: [CheckedContinuation<CGImage, Error>]] = [:]
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var requests: [ClipThumbnailRequest] = []

    init(script: [UUID: Outcome] = [:], gated: Bool = false) {
        self.script = script
        self.gated = gated
    }

    func thumbnail(for request: ClipThumbnailRequest) async throws -> CGImage {
        requests.append(request)
        resumeWaiters()
        if gated {
            return try await withCheckedThrowingContinuation { continuation in
                pending[request, default: []].append(continuation)
            }
        }
        return try resolve(request)
    }

    /// Completes every held request for `clipID` with the scripted outcome (or `outcome`).
    func complete(clipID: UUID, outcome: Outcome? = nil) {
        for (request, continuations) in pending where request.clipID == clipID {
            pending[request] = nil
            for continuation in continuations {
                if let outcome {
                    continuation.resume(with: Self.result(outcome, request: request))
                } else {
                    continuation.resume(with: Result { try resolve(request) })
                }
            }
        }
    }

    /// Suspends until at least `count` requests have arrived.
    func waitForRequests(count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    private func resumeWaiters() {
        let ready = waiters.filter { $0.count <= requests.count }
        waiters.removeAll { $0.count <= requests.count }
        for waiter in ready { waiter.continuation.resume() }
    }

    private func resolve(_ request: ClipThumbnailRequest) throws -> CGImage {
        let outcome = script[request.clipID] ?? .image(seed: abs(request.clipID.hashValue % 360))
        return try Self.result(outcome, request: request).get()
    }

    private static func result(_ outcome: Outcome, request: ClipThumbnailRequest) -> Result<CGImage, Error> {
        switch outcome {
        case .image(let seed): return .success(SyntheticThumbnailImage.make(seed: seed, size: request.maximumPixelSize.cgSize))
        case .failure(let error): return .failure(error)
        }
    }
}
#endif
