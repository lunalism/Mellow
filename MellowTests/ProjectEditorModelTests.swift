import CoreGraphics
import XCTest
@testable import Mellow

@MainActor
final class ProjectEditorModelTests: XCTestCase {
    private func makeClip(projectID: UUID, seconds: Int64, order: Int) throws -> VlogClip {
        try VlogClip(
            projectID: projectID,
            sourceKind: .recorded,
            mediaRelativePath: try RelativeMediaPath("seed/clip-\(order).mov"),
            sourceDuration: .seconds(seconds),
            trimDuration: .seconds(seconds),
            sortOrder: order
        )
    }

    private func isReady(_ state: ClipThumbnailPresentation) -> Bool {
        if case .ready = state { return true }
        return false
    }

    private func makeProject(clipSeconds: [Int64]) throws -> VlogProject {
        let id = UUID()
        let clips = try clipSeconds.enumerated().map {
            try makeClip(projectID: id, seconds: $0.element, order: $0.offset)
        }
        return try VlogProject(id: id, orientation: .portrait9x16, clips: clips)
    }

    func testLoadsAndHoldsProject() throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let model = ProjectEditorModel(project: project, thumbnails: FakeClipThumbnailProvider())
        XCTAssertEqual(model.project.id, project.id)
    }

    func testClipsRemainInLogicalSortOrder() throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let model = ProjectEditorModel(project: project, thumbnails: FakeClipThumbnailProvider())
        XCTAssertEqual(model.orderedClips.map(\.sortOrder), [0, 1, 2])
    }

    func testFirstClipSelectedInitiallyWhenNonEmpty() throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let model = ProjectEditorModel(project: project, thumbnails: FakeClipThumbnailProvider())
        XCTAssertEqual(model.selectedClipID, project.clips.first?.id)
        XCTAssertEqual(model.selectedClip?.id, project.clips.first?.id)
    }

    func testEmptyProjectHasNoSelection() throws {
        let project = try VlogProject(orientation: .portrait9x16)
        let model = ProjectEditorModel(project: project, thumbnails: FakeClipThumbnailProvider())
        XCTAssertNil(model.selectedClipID)
        XCTAssertNil(model.selectedClip)
    }

    func testSelectingValidClipUpdatesSelection() throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let model = ProjectEditorModel(project: project, thumbnails: FakeClipThumbnailProvider())
        let second = project.clips[1].id
        model.select(second)
        XCTAssertEqual(model.selectedClipID, second)
        XCTAssertEqual(model.selectedClip?.id, second)
    }

    func testSelectingUnknownClipIsIgnored() throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let model = ProjectEditorModel(project: project, thumbnails: FakeClipThumbnailProvider())
        let original = model.selectedClipID
        model.select(UUID())
        XCTAssertEqual(model.selectedClipID, original)
    }

    func testTotalDurationMatchesProject() throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let model = ProjectEditorModel(project: project, thumbnails: FakeClipThumbnailProvider())
        XCTAssertEqual(model.totalDuration, project.totalDuration)
        XCTAssertEqual(model.totalDuration, .seconds(6))
    }

    func testSelectionDoesNotMutatePersistedProject() throws {
        let repository = InMemoryProjectRepository()
        let project = try makeProject(clipSeconds: [2, 3])
        try repository.create(project)
        let model = ProjectEditorModel(project: project, thumbnails: FakeClipThumbnailProvider())

        model.select(project.clips[1].id)

        // Selection is view-only state; the persisted project is untouched.
        let reloaded = try repository.project(id: project.id)
        XCTAssertEqual(reloaded?.clips.map(\.id), project.clips.map(\.id))
        XCTAssertEqual(reloaded?.updatedAt, project.updatedAt)
    }

    // MARK: - Thumbnails (STEP 8)

    func testThumbnailRequestsFollowLogicalOrderAndCarryClipIdentity() async throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let provider = FakeClipThumbnailProvider()
        let model = ProjectEditorModel(project: project, thumbnails: provider)

        await model.loadThumbnails(displayScale: 3)

        let requests = await provider.requests
        XCTAssertEqual(requests.map(\.clipID), project.clips.map(\.id), "one request per clip, in logical order")
        XCTAssertEqual(requests.map(\.projectID), Array(repeating: project.id, count: 3))
        XCTAssertEqual(requests.map(\.mediaRelativePath), project.clips.map(\.mediaRelativePath))
        let expectedPixels = ClipThumbnailPixelSize(points: ProjectEditorModel.thumbnailPointSize, scale: 3)
        XCTAssertEqual(requests.first?.maximumPixelSize, expectedPixels)
        for clip in project.clips { XCTAssertTrue(isReady(model.thumbnail(for: clip.id))) }
    }

    func testOutOfOrderCompletionsMapToTheRightClips() async throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let ids = project.clips.map(\.id)
        let provider = FakeClipThumbnailProvider(gated: true)
        let model = ProjectEditorModel(project: project, thumbnails: provider)

        let load = Task { await model.loadThumbnails(displayScale: 2) }
        await provider.waitForRequests(count: 3)
        XCTAssertEqual(model.thumbnail(for: ids[0]), .loading)

        // Clip 3 first, then 1, then 2 — each lands on its own clip, nothing else changes.
        await provider.complete(clipID: ids[2], outcome: .image(seed: 30))
        await waitUntil { self.isReady(model.thumbnail(for: ids[2])) }
        XCTAssertEqual(model.thumbnail(for: ids[0]), .loading)
        XCTAssertEqual(model.thumbnail(for: ids[1]), .loading)

        await provider.complete(clipID: ids[0], outcome: .image(seed: 10))
        await waitUntil { self.isReady(model.thumbnail(for: ids[0])) }
        XCTAssertEqual(model.thumbnail(for: ids[1]), .loading)

        await provider.complete(clipID: ids[1], outcome: .image(seed: 20))
        await load.value
        XCTAssertTrue(ids.allSatisfy { isReady(model.thumbnail(for: $0)) })
        let images = ids.compactMap { id -> CGImage? in if case .ready(let image) = model.thumbnail(for: id) { return image } else { return nil } }
        XCTAssertEqual(Set(images.map { ObjectIdentifier($0) }).count, 3, "three distinct images, none reused across clips")
    }

    func testSelectionWhileThumbnailsAreLoadingIsPreserved() async throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let ids = project.clips.map(\.id)
        let provider = FakeClipThumbnailProvider(gated: true)
        let model = ProjectEditorModel(project: project, thumbnails: provider)

        let load = Task { await model.loadThumbnails(displayScale: 2) }
        await provider.waitForRequests(count: 3)
        model.select(ids[1])
        XCTAssertEqual(model.selectedClipID, ids[1])

        for id in ids { await provider.complete(clipID: id) }
        await load.value
        XCTAssertEqual(model.selectedClipID, ids[1], "thumbnail completion never changes selection")
        XCTAssertTrue(ids.allSatisfy { isReady(model.thumbnail(for: $0)) })
    }

    func testFailedThumbnailLeavesClipInPlaceAsUnavailablePlaceholder() async throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let ids = project.clips.map(\.id)
        let provider = FakeClipThumbnailProvider(script: [ids[1]: .failure(.mediaMissing)])
        let repository = InMemoryProjectRepository()
        try repository.create(project)
        let model = ProjectEditorModel(project: project, thumbnails: provider)

        await model.loadThumbnails(displayScale: 2)

        XCTAssertEqual(model.orderedClips.map(\.id), ids, "the clip keeps its logical slot")
        XCTAssertTrue(isReady(model.thumbnail(for: ids[0])))
        XCTAssertEqual(model.thumbnail(for: ids[1]), .unavailable)
        XCTAssertTrue(isReady(model.thumbnail(for: ids[2])))
        XCTAssertEqual(model.selectedClipID, ids[0])
        // Presentation fallback only: persistence is untouched.
        let reloaded = try repository.project(id: project.id)
        XCTAssertEqual(reloaded?.clips.map(\.id), ids)
        XCTAssertEqual(reloaded?.updatedAt, project.updatedAt)
    }

    func testReloadingSameProjectKeepsReadyThumbnailsAndRequestIdentity() async throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let provider = FakeClipThumbnailProvider()
        let model = ProjectEditorModel(project: project, thumbnails: provider)

        await model.loadThumbnails(displayScale: 2)
        let first = await provider.requests
        await model.loadThumbnails(displayScale: 2)
        let second = await provider.requests
        XCTAssertEqual(second.count, first.count, "ready thumbnails are not requested again")

        // A second model for the same Project derives identical request identities.
        let again = ProjectEditorModel(project: project, thumbnails: provider)
        await again.loadThumbnails(displayScale: 2)
        let third = await provider.requests
        XCTAssertEqual(Array(third.suffix(2)), first)
    }

    func testLateResultForStaleRequestIdentityIsDropped() async throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let ids = project.clips.map(\.id)
        let provider = FakeClipThumbnailProvider(gated: true)
        let model = ProjectEditorModel(project: project, thumbnails: provider)

        // Load at scale 2, then (before anything completes) at scale 3: the scale-2 identity is stale.
        let stale = Task { await model.loadThumbnails(displayScale: 2) }
        await provider.waitForRequests(count: 2)
        let current = Task { await model.loadThumbnails(displayScale: 3) }
        await provider.waitForRequests(count: 4)
        let requests = await provider.requests
        let staleRequest = requests[0], currentRequest = requests[2]
        XCTAssertEqual(staleRequest.clipID, ids[0])
        XCTAssertEqual(currentRequest.clipID, ids[0])
        XCTAssertNotEqual(staleRequest, currentRequest)

        let staleImage = SyntheticThumbnailImage.make(seed: 1, size: CGSize(width: 4, height: 8))
        model.applyThumbnailResult(.success(staleImage), for: staleRequest)
        XCTAssertEqual(model.thumbnail(for: ids[0]), .loading, "a late result for a superseded identity is not published")

        let currentImage = SyntheticThumbnailImage.make(seed: 2, size: CGSize(width: 4, height: 8))
        model.applyThumbnailResult(.success(currentImage), for: currentRequest)
        XCTAssertEqual(model.thumbnail(for: ids[0]), .ready(currentImage))

        // Settling both loads resumes the stale AND the current continuation for clip 1: only the
        // current-identity image may land; the stale-identity image never does.
        for id in ids { await provider.complete(clipID: id) }
        await stale.value
        await current.value
        guard case .ready(let final) = model.thumbnail(for: ids[0]) else { return XCTFail("clip 1 should be ready") }
        XCTAssertFalse(final === staleImage, "the settled stale task did not overwrite the current image")
        let published = await provider.requests.filter { $0 == staleRequest }.count
        XCTAssertEqual(published, 1, "the stale identity was requested exactly once and then abandoned")
    }

    func testResultForForeignProjectOrClipIsNeverApplied() async throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let other = try makeProject(clipSeconds: [2])
        let provider = FakeClipThumbnailProvider(gated: true)
        let model = ProjectEditorModel(project: project, thumbnails: provider)
        let load = Task { await model.loadThumbnails(displayScale: 2) }
        await provider.waitForRequests(count: 2)
        let pixels = ClipThumbnailPixelSize(points: ProjectEditorModel.thumbnailPointSize, scale: 2)
        let image = SyntheticThumbnailImage.make(seed: 1, size: CGSize(width: 4, height: 8))

        // Same clip position in a different Project.
        model.applyThumbnailResult(.success(image), for: ClipThumbnailRequest(clip: other.clips[0], maximumPixelSize: pixels))
        // A clip that is not part of this Project at all.
        let foreignClip = try makeClip(projectID: project.id, seconds: 1, order: 9)
        model.applyThumbnailResult(.success(image), for: ClipThumbnailRequest(clip: foreignClip, maximumPixelSize: pixels))

        XCTAssertTrue(model.thumbnailStates.isEmpty)
        XCTAssertEqual(model.thumbnail(for: other.clips[0].id), .loading)
        for clip in project.clips { await provider.complete(clipID: clip.id) }
        await load.value
    }

    func testStoppingLoadInvalidatesLateResults() async throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let ids = project.clips.map(\.id)
        let provider = FakeClipThumbnailProvider(gated: true)
        let model = ProjectEditorModel(project: project, thumbnails: provider)

        let load = Task { await model.loadThumbnails(displayScale: 2) }
        await provider.waitForRequests(count: 2)
        let request = await provider.requests[0]

        // The screen went away (Project change / navigation): the load is stopped, then a result lands.
        model.stopThumbnailLoading()
        XCTAssertNil(model.currentThumbnailRequest(for: ids[0]))
        model.applyThumbnailResult(.success(SyntheticThumbnailImage.make(seed: 1, size: CGSize(width: 4, height: 8))), for: request)
        XCTAssertEqual(model.thumbnail(for: ids[0]), .loading)

        for id in ids { await provider.complete(clipID: id) }
        await load.value
        XCTAssertTrue(model.thumbnailStates.isEmpty, "nothing from the stopped load was published")
    }

    func testCancelledLoadDoesNotMarkClipsUnavailable() async throws {
        let project = try makeProject(clipSeconds: [2])
        let provider = FakeClipThumbnailProvider(gated: true)
        let model = ProjectEditorModel(project: project, thumbnails: provider)

        let load = Task { await model.loadThumbnails(displayScale: 2) }
        await provider.waitForRequests(count: 1)
        load.cancel()
        await provider.complete(clipID: project.clips[0].id, outcome: .failure(.cancelled))
        await load.value
        XCTAssertEqual(model.thumbnail(for: project.clips[0].id), .loading)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), "condition not met within \(timeout)s")
    }
}
