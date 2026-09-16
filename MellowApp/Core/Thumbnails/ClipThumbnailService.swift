import AVFoundation
import CoreGraphics
import Foundation

/// Pixel budget for one generated thumbnail: the on-screen box in points × the display scale. Kept as
/// integers so it can take part in the request identity.
struct ClipThumbnailPixelSize: Hashable, Sendable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    init(points: CGSize, scale: CGFloat) {
        self.init(width: Int((points.width * scale).rounded(.up)), height: Int((points.height * scale).rounded(.up)))
    }

    var cgSize: CGSize { CGSize(width: width, height: height) }
}

/// Identity of one Editor thumbnail. Everything that changes the produced image is part of the key —
/// Project and Clip identity, the committed media reference, the effective trim range (which picks
/// the representative frame) and the pixel budget. Never an array index (ARCHITECTURE §56 / ADR-021).
struct ClipThumbnailRequest: Hashable, Sendable {
    let projectID: UUID
    let clipID: UUID
    let mediaRelativePath: RelativeMediaPath
    let trimStart: MediaTime
    let trimDuration: MediaTime
    let maximumPixelSize: ClipThumbnailPixelSize

    init(clip: VlogClip, maximumPixelSize: ClipThumbnailPixelSize) {
        projectID = clip.projectID
        clipID = clip.id
        mediaRelativePath = clip.mediaRelativePath
        trimStart = clip.trimStart
        trimDuration = clip.trimDuration
        self.maximumPixelSize = maximumPixelSize
    }

    /// Source time of the representative frame for this request.
    var representativeTime: CMTime {
        ClipThumbnailFrameRule.representativeTime(trimStart: trimStart, trimDuration: trimDuration)
    }
}

/// Typed thumbnail outcomes. A thumbnail failure is derived-data failure only: it never implies the
/// Clip or its media is invalid and never triggers any persistence change (ARCHITECTURE §56).
enum ClipThumbnailError: Error, Equatable {
    case mediaMissing
    case unreadable
    case noVideoFrame
    case generationFailed
    case cancelled
}

/// Narrow async boundary the Editor (and later the Project representative thumbnail / Camera content
/// slot) consumes. Implementations generate off the Main Actor.
protocol ClipThumbnailProviding: Sendable {
    func thumbnail(for request: ClipThumbnailRequest) async throws -> CGImage
}

/// Deterministic representative-frame rule: the midpoint of the CURRENT effective clip range, so a
/// later non-zero `trimStart` moves the frame with the trim instead of always sampling source time 0.
enum ClipThumbnailFrameRule {
    static func representativeTime(trimStart: MediaTime, trimDuration: MediaTime) -> CMTime {
        let start = CMTime(value: trimStart.value, timescale: trimStart.timescale)
        let duration = CMTime(value: trimDuration.value, timescale: trimDuration.timescale)
        return CMTimeAdd(start, CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2))
    }
}

/// Produces the frame for an already-resolved local media URL. Separated from the service so tests
/// can count generations and gate concurrency without touching AVFoundation.
protocol ClipThumbnailGenerating: Sendable {
    func generate(from url: URL, request: ClipThumbnailRequest) async throws -> CGImage
}

/// Production generation through `AVAssetImageGenerator`: preferred track transform applied (portrait
/// media renders upright), aspect-preserving downscale to the request's pixel budget, no cropping and
/// no Project framing baked in — the media itself is untouched.
struct AVAssetClipThumbnailGenerator: ClipThumbnailGenerating {
    func generate(from url: URL, request: ClipThumbnailRequest) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let readable: Bool
        let tracks: [AVAssetTrack]
        do {
            (readable, tracks) = try await asset.load(.isReadable, .tracks)
        } catch {
            throw ClipThumbnailError.unreadable
        }
        guard readable else { throw ClipThumbnailError.unreadable }
        guard tracks.contains(where: { $0.mediaType == .video }) else { throw ClipThumbnailError.noVideoFrame }
        try Task.checkCancellation()

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = request.maximumPixelSize.cgSize
        // Loose tolerances let AVFoundation return the nearest decoded frame rather than scanning to
        // an exact time; the rule is "a frame near the effective midpoint", not a sample-exact seek.
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        do {
            let (image, _) = try await generator.image(at: request.representativeTime)
            return image
        } catch is CancellationError {
            throw ClipThumbnailError.cancelled
        } catch {
            throw ClipThumbnailError.generationFailed
        }
    }
}

/// Bounded, most-recently-used-first memory cache. Deterministic (unlike NSCache) so cache-hit
/// behaviour is testable; the count limit with pixel-budgeted images keeps a strip's worth resident.
struct BoundedThumbnailCache {
    let limit: Int
    private var images: [ClipThumbnailRequest: CGImage] = [:]
    private var recency: [ClipThumbnailRequest] = []

    init(limit: Int) { self.limit = max(1, limit) }

    var count: Int { images.count }

    mutating func image(for request: ClipThumbnailRequest) -> CGImage? {
        guard let image = images[request] else { return nil }
        touch(request)
        return image
    }

    mutating func insert(_ image: CGImage, for request: ClipThumbnailRequest) {
        images[request] = image
        touch(request)
        while recency.count > limit, let oldest = recency.first {
            recency.removeFirst()
            images[oldest] = nil
        }
    }

    private mutating func touch(_ request: ClipThumbnailRequest) {
        recency.removeAll { $0 == request }
        recency.append(request)
    }
}

/// `ThumbnailService` (ARCHITECTURE §56): resolves Project-owned committed media through the read-only
/// `ProjectMediaURLResolving` boundary, generates off the Main Actor, caches results in memory and
/// coalesces concurrent identical requests into one generation. Thumbnails are cache data — nothing
/// here writes to disk or touches Project metadata, Photos, or capture staging.
actor ClipThumbnailService: ClipThumbnailProviding, ProjectMediaConsumerGating {
    private let resolver: any ProjectMediaURLResolving
    private let generator: any ClipThumbnailGenerating
    private var cache: BoundedThumbnailCache
    private var inFlight: [ClipThumbnailRequest: Task<CGImage, Error>] = [:]

    init(
        resolver: any ProjectMediaURLResolving,
        generator: any ClipThumbnailGenerating = AVAssetClipThumbnailGenerator(),
        cacheLimit: Int = 64
    ) {
        self.resolver = resolver
        self.generator = generator
        self.cache = BoundedThumbnailCache(limit: cacheLimit)
    }

    var cachedCount: Int { cache.count }
    var inFlightCount: Int { inFlight.count }

    /// Media-consumer gate for physical cleanup (ADR-039 / ARCHITECTURE §56 "Thumbnail 생성이 Source
    /// Media를 Release하기 전에는 해당 File을 Physical Delete하지 않는다"). Resolves `true` once no
    /// in-flight generation reads any of `paths`; `false` when one is still busy after `timeout`,
    /// in which case the caller must leave the file alone and retry at a later boundary. It only
    /// observes the existing in-flight map — it never reorders, cancels or starts generation, and a
    /// ready cached thumbnail is not an active consumer (no cache purge). The wait is bounded on
    /// purpose: a stuck decode must never hang cleanup.
    func awaitIdle(for paths: Set<RelativeMediaPath>, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while inFlight.keys.contains(where: { paths.contains($0.mediaRelativePath) }) {
            guard clock.now < deadline, !Task.isCancelled else { return false }
            try? await clock.sleep(for: Self.idlePollInterval)
        }
        return true
    }

    private static let idlePollInterval: Duration = .milliseconds(20)

    func thumbnail(for request: ClipThumbnailRequest) async throws -> CGImage {
        if let cached = cache.image(for: request) { return cached }
        let task: Task<CGImage, Error>
        if let existing = inFlight[request] {
            task = existing
        } else {
            let resolver = self.resolver
            let generator = self.generator
            task = Task {
                let url: URL
                do {
                    url = try await resolver.committedMediaURL(for: request.mediaRelativePath)
                } catch {
                    throw ClipThumbnailError.mediaMissing
                }
                return try await generator.generate(from: url, request: request)
            }
            inFlight[request] = task
        }
        // Every awaiter shares the one generation. A caller's own cancellation only makes THIS caller
        // stop consuming the result; the shared task and the other awaiters are unaffected.
        let outcome = await task.result
        if inFlight[request] == task { inFlight[request] = nil }
        if Task.isCancelled { throw ClipThumbnailError.cancelled }
        switch outcome {
        case .success(let image):
            cache.insert(image, for: request)
            return image
        case .failure(let error):
            throw (error as? ClipThumbnailError) ?? .generationFailed
        }
    }
}
