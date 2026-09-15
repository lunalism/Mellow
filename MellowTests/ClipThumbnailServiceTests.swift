import AVFoundation
import CoreGraphics
import XCTest
@testable import Mellow

/// Counts generations and can hold them open so coalescing is observable. Delegates to a real or
/// synthetic generator.
actor CountingThumbnailGenerator: ClipThumbnailGenerating {
    private let inner: any ClipThumbnailGenerating
    private let gated: Bool
    private var gate: [CheckedContinuation<Void, Never>] = []
    private var started: [CheckedContinuation<Void, Never>] = []
    private(set) var generations = 0

    init(inner: any ClipThumbnailGenerating = SyntheticGenerator(), gated: Bool = false) {
        self.inner = inner
        self.gated = gated
    }

    func generate(from url: URL, request: ClipThumbnailRequest) async throws -> CGImage {
        generations += 1
        for waiter in started { waiter.resume() }
        started.removeAll()
        if gated { await withCheckedContinuation { gate.append($0) } }
        return try await inner.generate(from: url, request: request)
    }

    func waitUntilStarted() async {
        guard generations == 0 else { return }
        await withCheckedContinuation { started.append($0) }
    }

    func release() {
        for waiter in gate { waiter.resume() }
        gate.removeAll()
    }

    struct SyntheticGenerator: ClipThumbnailGenerating {
        func generate(from url: URL, request: ClipThumbnailRequest) async throws -> CGImage {
            SyntheticThumbnailImage.make(seed: 1, size: request.maximumPixelSize.cgSize)
        }
    }
}

final class ClipThumbnailServiceTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!

    override func setUp() {
        root = TestSupport.temporaryRoot("thumbnails")
        store = ProjectMediaStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private let pixels = ClipThumbnailPixelSize(points: CGSize(width: 54, height: 96), scale: 3)

    /// Materializes a real portrait fixture as Project-owned media and returns the committed clip.
    private func committedClip(seconds: Double = 2, trimStart: MediaTime = .zero, trimSeconds: Int64 = 2, projectID: UUID = UUID()) async throws -> VlogClip {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: seconds)
        let workspace = try await store.beginWorkspace()
        let adopted = try await store.adopt(try TestSupport.transferCopy(of: fixture), into: workspace)
        let clipID = UUID()
        let path = try await store.materialize(adopted, projectID: projectID, clipID: clipID)
        await store.discard(workspace)
        return try VlogClip(
            id: clipID, projectID: projectID, sourceKind: .imported, mediaRelativePath: path,
            sourceDuration: try MediaTime(value: Int64(seconds * 600), timescale: 600),
            trimStart: trimStart, trimDuration: .seconds(trimSeconds), sortOrder: 0
        )
    }

    // MARK: - Production generation against real Project-owned media

    func testGeneratesUprightPortraitThumbnailWithinPixelBudget() async throws {
        let clip = try await committedClip()
        let service = ClipThumbnailService(resolver: store)
        let image = try await service.thumbnail(for: ClipThumbnailRequest(clip: clip, maximumPixelSize: pixels))
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
        // Portrait source (540×960) stays portrait after the preferred transform, and is scaled down
        // to the request instead of decoded at source size.
        XCTAssertGreaterThan(image.height, image.width)
        XCTAssertLessThanOrEqual(image.width, pixels.width)
        XCTAssertLessThanOrEqual(image.height, pixels.height)
        XCTAssertEqual(Double(image.height) / Double(image.width), 960.0 / 540.0, accuracy: 0.05, "aspect preserved, no crop")
    }

    func testPreferredTransformIsAppliedForRotatedPortraitMedia() async throws {
        // A landscape raster tagged with a 90° preferred transform presents as portrait; the
        // thumbnail must follow the transform, not the raw raster.
        let landscapeFixture = root.appendingPathComponent("landscape-source").appendingPathExtension("mov")
        let rotated = root.appendingPathComponent("rotated").appendingPathExtension("mov")
        try await FixtureVideoWriter.write(to: landscapeFixture, size: CGSize(width: 960, height: 540), seconds: 1)
        try await Self.writeWithRotation(source: landscapeFixture, to: rotated)
        let workspace = try await store.beginWorkspace()
        let adopted = try await store.adopt(try TestSupport.transferCopy(of: rotated), into: workspace)
        let projectID = UUID(), clipID = UUID()
        let path = try await store.materialize(adopted, projectID: projectID, clipID: clipID)
        let clip = try VlogClip(id: clipID, projectID: projectID, sourceKind: .imported, mediaRelativePath: path, sourceDuration: .seconds(1), trimDuration: .seconds(1), sortOrder: 0)

        let service = ClipThumbnailService(resolver: store)
        let image = try await service.thumbnail(for: ClipThumbnailRequest(clip: clip, maximumPixelSize: pixels))
        XCTAssertGreaterThan(image.height, image.width, "upright: the 90° preferred transform was applied")
    }

    func testRepresentativeTimeFollowsEffectiveTrimRange() throws {
        let zero = ClipThumbnailFrameRule.representativeTime(trimStart: .zero, trimDuration: .seconds(2))
        XCTAssertEqual(zero.seconds, 1.0, accuracy: 0.001)
        let trimmed = ClipThumbnailFrameRule.representativeTime(trimStart: try MediaTime(value: 1800, timescale: 600), trimDuration: .seconds(2))
        XCTAssertEqual(trimmed.seconds, 4.0, accuracy: 0.001, "midpoint of [3, 5], not source time zero")
        // The request carries the same rule and includes trim in its identity.
        let projectID = UUID()
        let a = try VlogClip(projectID: projectID, sourceKind: .recorded, mediaRelativePath: try RelativeMediaPath("x.mov"), sourceDuration: .seconds(5), trimDuration: .seconds(2), sortOrder: 0)
        let b = try VlogClip(id: a.id, projectID: projectID, sourceKind: .recorded, mediaRelativePath: a.mediaRelativePath, sourceDuration: .seconds(5), trimStart: .seconds(3), trimDuration: .seconds(2), sortOrder: 0)
        let ra = ClipThumbnailRequest(clip: a, maximumPixelSize: pixels), rb = ClipThumbnailRequest(clip: b, maximumPixelSize: pixels)
        XCTAssertNotEqual(ra, rb)
        XCTAssertEqual(rb.representativeTime.seconds, 4.0, accuracy: 0.001)
    }

    func testTrimmedRequestDecodesFrameInsideTheTrimRange() async throws {
        // 5 s fixture; effective range [3, 5] → representative time 4 s must still decode.
        let clip = try await committedClip(seconds: 5, trimStart: .seconds(3), trimSeconds: 2)
        let service = ClipThumbnailService(resolver: store)
        let image = try await service.thumbnail(for: ClipThumbnailRequest(clip: clip, maximumPixelSize: pixels))
        XCTAssertGreaterThan(image.height, image.width)
    }

    // MARK: - Failures never mutate anything

    func testMissingMediaIsTypedFailureWithoutMutation() async throws {
        let clip = try await committedClip()
        let path = await store.url(for: clip.mediaRelativePath)
        try FileManager.default.removeItem(at: path)
        let service = ClipThumbnailService(resolver: store)
        do {
            _ = try await service.thumbnail(for: ClipThumbnailRequest(clip: clip, maximumPixelSize: pixels))
            XCTFail("missing media must fail")
        } catch let error as ClipThumbnailError {
            XCTAssertEqual(error, .mediaMissing)
        }
        let cached = await service.cachedCount
        XCTAssertEqual(cached, 0)
        XCTAssertFalse(TestSupport.exists(path), "nothing is recreated")
    }

    func testCorruptMediaIsTypedFailureAndFileIsLeftIntact() async throws {
        let corrupt = try await TestMediaFixtures.shared.corrupt()
        let workspace = try await store.beginWorkspace()
        let adopted = try await store.adopt(try TestSupport.transferCopy(of: corrupt), into: workspace)
        let projectID = UUID(), clipID = UUID()
        let path = try await store.materialize(adopted, projectID: projectID, clipID: clipID)
        let clip = try VlogClip(id: clipID, projectID: projectID, sourceKind: .imported, mediaRelativePath: path, sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: 0)
        let url = await store.url(for: path)
        let bytesBefore = try Data(contentsOf: url)

        let service = ClipThumbnailService(resolver: store)
        do {
            _ = try await service.thumbnail(for: ClipThumbnailRequest(clip: clip, maximumPixelSize: pixels))
            XCTFail("corrupt media must fail")
        } catch let error as ClipThumbnailError {
            XCTAssertTrue([.unreadable, .noVideoFrame, .generationFailed].contains(error), "\(error)")
        }
        XCTAssertEqual(try Data(contentsOf: url), bytesBefore, "the committed file is untouched")
        let inFlight = await service.inFlightCount
        XCTAssertEqual(inFlight, 0)
    }

    // MARK: - Cache and coalescing

    func testCacheHitDoesNotRepeatGeneration() async throws {
        let clip = try await committedClip()
        let generator = CountingThumbnailGenerator()
        let service = ClipThumbnailService(resolver: store, generator: generator)
        let request = ClipThumbnailRequest(clip: clip, maximumPixelSize: pixels)
        let first = try await service.thumbnail(for: request)
        let second = try await service.thumbnail(for: request)
        XCTAssertTrue(first === second)
        let generations = await generator.generations
        XCTAssertEqual(generations, 1)
    }

    func testConcurrentIdenticalRequestsAreCoalesced() async throws {
        let clip = try await committedClip()
        let generator = CountingThumbnailGenerator(gated: true)
        let service = ClipThumbnailService(resolver: store, generator: generator)
        let request = ClipThumbnailRequest(clip: clip, maximumPixelSize: pixels)

        let awaiters = (0..<5).map { _ in Task { try await service.thumbnail(for: request) } }
        await generator.waitUntilStarted()
        try await Task.sleep(for: .milliseconds(50)) // let every awaiter reach the shared task
        let inFlight = await service.inFlightCount
        XCTAssertEqual(inFlight, 1)
        await generator.release()

        var images: [CGImage] = []
        for awaiter in awaiters { images.append(try await awaiter.value) }
        XCTAssertEqual(images.count, 5)
        XCTAssertTrue(images.allSatisfy { $0 === images[0] }, "every awaiter received the one generated image")
        let generations = await generator.generations
        XCTAssertEqual(generations, 1)
    }

    func testCancellingOneAwaiterDoesNotAffectOthers() async throws {
        let clip = try await committedClip()
        let generator = CountingThumbnailGenerator(gated: true)
        let service = ClipThumbnailService(resolver: store, generator: generator)
        let request = ClipThumbnailRequest(clip: clip, maximumPixelSize: pixels)

        let cancelled = Task { try await service.thumbnail(for: request) }
        let survivor = Task { try await service.thumbnail(for: request) }
        await generator.waitUntilStarted()
        try await Task.sleep(for: .milliseconds(50))
        cancelled.cancel()
        await generator.release()

        let image = try await survivor.value
        XCTAssertGreaterThan(image.width, 0)
        do {
            _ = try await cancelled.value
            // Acceptable: the value may already have been produced before cancellation was observed.
        } catch let error as ClipThumbnailError {
            XCTAssertEqual(error, .cancelled)
        }
        let generations = await generator.generations
        XCTAssertEqual(generations, 1)
    }

    func testDifferentClipsAndIdentitiesUseSeparateCacheEntries() async throws {
        let projectID = UUID()
        let a = try await committedClip(projectID: projectID)
        let b = try await committedClip(projectID: projectID)
        let generator = CountingThumbnailGenerator()
        let service = ClipThumbnailService(resolver: store, generator: generator)

        let imageA = try await service.thumbnail(for: ClipThumbnailRequest(clip: a, maximumPixelSize: pixels))
        let imageB = try await service.thumbnail(for: ClipThumbnailRequest(clip: b, maximumPixelSize: pixels))
        XCTAssertFalse(imageA === imageB)
        // Same clip, different pixel budget → different identity → separate generation.
        let larger = ClipThumbnailPixelSize(points: CGSize(width: 54, height: 96), scale: 4)
        _ = try await service.thumbnail(for: ClipThumbnailRequest(clip: a, maximumPixelSize: larger))
        let generations = await generator.generations
        XCTAssertEqual(generations, 3)
        let cached = await service.cachedCount
        XCTAssertEqual(cached, 3)
    }

    func testCacheIsBounded() async throws {
        let projectID = UUID()
        let clips = try await [committedClip(projectID: projectID), committedClip(projectID: projectID), committedClip(projectID: projectID)]
        let generator = CountingThumbnailGenerator()
        let service = ClipThumbnailService(resolver: store, generator: generator, cacheLimit: 2)
        for clip in clips { _ = try await service.thumbnail(for: ClipThumbnailRequest(clip: clip, maximumPixelSize: pixels)) }
        let cached = await service.cachedCount
        XCTAssertEqual(cached, 2)
        // The evicted (oldest) entry is generated again; the newest two are hits.
        _ = try await service.thumbnail(for: ClipThumbnailRequest(clip: clips[2], maximumPixelSize: pixels))
        _ = try await service.thumbnail(for: ClipThumbnailRequest(clip: clips[0], maximumPixelSize: pixels))
        let generations = await generator.generations
        XCTAssertEqual(generations, 4)
    }

    // MARK: - Helpers

    /// Re-muxes `source` with a 90° preferred transform on the video track (no re-encode).
    private static func writeWithRotation(source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let composition = AVMutableComposition()
        let sourceTrack = try await asset.loadTracks(withMediaType: .video)[0]
        let duration = try await asset.load(.duration)
        let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: .zero)
        track.preferredTransform = CGAffineTransform(rotationAngle: .pi / 2).translatedBy(x: 0, y: -540)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try? FileManager.default.removeItem(at: destination)
        try await export.export(to: destination, as: .mov)
    }
}

final class ProjectMediaURLResolverTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!

    override func setUp() {
        root = TestSupport.temporaryRoot("resolver")
        store = ProjectMediaStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func testCommittedPathResolvesInsideProjectOwnedRoot() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let workspace = try await store.beginWorkspace()
        let adopted = try await store.adopt(try TestSupport.transferCopy(of: fixture), into: workspace)
        let projectID = UUID(), clipID = UUID()
        let path = try await store.materialize(adopted, projectID: projectID, clipID: clipID)

        let url = try await store.committedMediaURL(for: path)
        XCTAssertTrue(url.path.hasPrefix(root.standardizedFileURL.path + "/Projects/\(projectID.uuidString)/Media/"))
        XCTAssertEqual(url.lastPathComponent, "\(clipID.uuidString).mov")
        XCTAssertTrue(TestSupport.exists(url))
        XCTAssertEqual(path.value, "Projects/\(projectID.uuidString)/Media/\(clipID.uuidString).mov", "the persisted reference stays relative")
    }

    func testAbsoluteAndTraversalPathsAreRejectedBeforeResolution() {
        XCTAssertThrowsError(try RelativeMediaPath("/etc/passwd"))
        XCTAssertThrowsError(try RelativeMediaPath("../outside.mov"))
        XCTAssertThrowsError(try RelativeMediaPath("Projects/../../outside.mov"))
        XCTAssertThrowsError(try RelativeMediaPath("./Projects/x.mov"))
        XCTAssertThrowsError(try RelativeMediaPath(""))
    }

    func testMissingFileSurfacesAsMissing() async throws {
        let path = try RelativeMediaPath("Projects/\(UUID().uuidString)/Media/\(UUID().uuidString).mov")
        do {
            _ = try await store.committedMediaURL(for: path)
            XCTFail()
        } catch let error as ProjectMediaStoreError {
            XCTAssertEqual(error, .mediaMissing)
        }
        // A directory is not media either.
        let directory = try RelativeMediaPath("Projects")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        do {
            _ = try await store.committedMediaURL(for: directory)
            XCTFail()
        } catch let error as ProjectMediaStoreError {
            XCTAssertEqual(error, .mediaMissing)
        }
    }

    func testResolutionIsReadOnly() async throws {
        let path = try RelativeMediaPath("Projects/\(UUID().uuidString)/Media/\(UUID().uuidString).mov")
        _ = try? await store.committedMediaURL(for: path)
        XCTAssertFalse(TestSupport.exists(root.appendingPathComponent(path.value).deletingLastPathComponent()), "resolving never creates directories")
        XCTAssertTrue(TestSupport.noProjectMedia(under: root))
    }
}
