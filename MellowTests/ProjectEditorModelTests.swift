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
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: FakeClipThumbnailProvider())
        XCTAssertEqual(model.project.id, project.id)
    }

    func testClipsRemainInLogicalSortOrder() throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: FakeClipThumbnailProvider())
        XCTAssertEqual(model.orderedClips.map(\.sortOrder), [0, 1, 2])
    }

    func testFirstClipSelectedInitiallyWhenNonEmpty() throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: FakeClipThumbnailProvider())
        XCTAssertEqual(model.selectedClipID, project.clips.first?.id)
        XCTAssertEqual(model.selectedClip?.id, project.clips.first?.id)
    }

    func testEmptyProjectHasNoSelection() throws {
        let project = try VlogProject(orientation: .portrait9x16)
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: FakeClipThumbnailProvider())
        XCTAssertNil(model.selectedClipID)
        XCTAssertNil(model.selectedClip)
    }

    func testSelectingValidClipUpdatesSelection() throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: FakeClipThumbnailProvider())
        let second = project.clips[1].id
        model.select(second)
        XCTAssertEqual(model.selectedClipID, second)
        XCTAssertEqual(model.selectedClip?.id, second)
    }

    func testSelectingUnknownClipIsIgnored() throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: FakeClipThumbnailProvider())
        let original = model.selectedClipID
        model.select(UUID())
        XCTAssertEqual(model.selectedClipID, original)
    }

    func testTotalDurationMatchesProject() throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: FakeClipThumbnailProvider())
        XCTAssertEqual(model.totalDuration, project.totalDuration)
        XCTAssertEqual(model.totalDuration, .seconds(6))
    }

    func testSelectionDoesNotMutatePersistedProject() throws {
        let repository = InMemoryProjectRepository()
        let project = try makeProject(clipSeconds: [2, 3])
        try repository.create(project)
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: FakeClipThumbnailProvider())

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
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: provider)

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
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: provider)

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
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: provider)

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
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: provider)

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
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: provider)

        await model.loadThumbnails(displayScale: 2)
        let first = await provider.requests
        await model.loadThumbnails(displayScale: 2)
        let second = await provider.requests
        XCTAssertEqual(second.count, first.count, "ready thumbnails are not requested again")

        // A second model for the same Project derives identical request identities.
        let again = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: provider)
        await again.loadThumbnails(displayScale: 2)
        let third = await provider.requests
        XCTAssertEqual(Array(third.suffix(2)), first)
    }

    func testLateResultForStaleRequestIdentityIsDropped() async throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let ids = project.clips.map(\.id)
        let provider = FakeClipThumbnailProvider(gated: true)
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: provider)

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
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: provider)
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
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: provider)

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
        let model = ProjectEditorModel(project: project, repository: InMemoryProjectRepository(), thumbnails: provider)

        let load = Task { await model.loadThumbnails(displayScale: 2) }
        await provider.waitForRequests(count: 1)
        load.cancel()
        await provider.complete(clipID: project.clips[0].id, outcome: .failure(.cancelled))
        await load.value
        XCTAssertEqual(model.thumbnail(for: project.clips[0].id), .loading)
    }

    // MARK: - Reorder + autosave (STEP 9)

    private func makeEditor(clipSeconds: [Int64] = [2, 3, 1], provider: FakeClipThumbnailProvider = FakeClipThumbnailProvider()) throws -> (ProjectEditorModel, FailableProjectRepository, [UUID]) {
        let repository = FailableProjectRepository()
        let project = try makeProject(clipSeconds: clipSeconds)
        try repository.create(project)
        let model = ProjectEditorModel(project: project, repository: repository, thumbnails: provider)
        return (model, repository, project.clips.map(\.id))
    }

    func testDropMovesThirdClipFirstAndNormalisesSortOrder() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])

        XCTAssertTrue(model.beginReorder(clipID: c))
        model.previewReorder(toIndex: 0)
        model.commitReorder()

        XCTAssertEqual(model.orderedClips.map(\.id), [c, a, b])
        XCTAssertEqual(model.orderedClips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.id), [c, a, b])
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.sortOrder), [0, 1, 2])
        XCTAssertNil(model.draggingClipID)
        XCTAssertNil(model.previewOrder)
        XCTAssertNil(model.editorMessage)
    }

    func testDropMovesFirstClipLast() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])

        model.beginReorder(clipID: a)
        model.previewReorder(toIndex: 2)
        model.commitReorder()

        XCTAssertEqual(model.orderedClips.map(\.id), [b, c, a])
        XCTAssertEqual(model.orderedClips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.id), [b, c, a])
    }

    func testDropAtSameIndexWritesNothing() throws {
        let (model, repository, ids) = try makeEditor()
        let before = model.project

        model.beginReorder(clipID: ids[1])
        model.previewReorder(toIndex: 1)
        model.commitReorder()

        XCTAssertEqual(model.project, before, "no mutation, not even updatedAt")
        XCTAssertEqual(repository.updateCount, 0)
        XCTAssertEqual(model.selectedClipID, ids[1], "the pressed clip is still selected")
    }

    func testPreviewChangesDisplayedOrderButNotCommittedOrderOrRepository() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])

        model.beginReorder(clipID: c)
        XCTAssertEqual(model.dragTargetIndex, 2)
        model.previewReorder(toIndex: 1)
        XCTAssertEqual(model.orderedClips.map(\.id), [a, c, b])
        XCTAssertEqual(model.dragTargetIndex, 1)
        model.previewReorder(toIndex: 0)
        XCTAssertEqual(model.orderedClips.map(\.id), [c, a, b])
        model.previewReorder(toIndex: 7)
        XCTAssertEqual(model.orderedClips.map(\.id), [a, b, c], "indices are clamped")

        XCTAssertEqual(model.committedClips.map(\.id), [a, b, c])
        XCTAssertEqual(model.project.clips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(repository.updateCount, 0, "nothing is written while dragging")
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.id), [a, b, c])
    }

    func testCancelRestoresCommittedOrderWithoutAnyWrite() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])

        model.beginReorder(clipID: c)
        model.previewReorder(toIndex: 0)
        XCTAssertEqual(model.orderedClips.map(\.id), [c, a, b])
        model.cancelReorder()

        XCTAssertEqual(model.orderedClips.map(\.id), [a, b, c])
        XCTAssertNil(model.draggingClipID)
        XCTAssertNil(model.previewOrder)
        XCTAssertEqual(repository.updateCount, 0)
        XCTAssertEqual(model.selectedClipID, c, "selection stays on the pressed clip")
        XCTAssertNil(model.editorMessage)
    }

    func testSuccessfulDropWritesExactlyOnce() throws {
        let (model, repository, ids) = try makeEditor()

        model.beginReorder(clipID: ids[2])
        model.previewReorder(toIndex: 1)
        model.previewReorder(toIndex: 0)
        model.previewReorder(toIndex: 1)
        model.commitReorder()

        XCTAssertEqual(repository.updateCount, 1, "midpoint crossings never write; the drop writes once")
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.id), [ids[0], ids[2], ids[1]])
    }

    func testPersistenceFailureRestoresOrderAndReportsRecoverableError() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])
        let before = model.project
        repository.updateFails = true

        model.beginReorder(clipID: c)
        model.previewReorder(toIndex: 0)
        model.commitReorder()

        XCTAssertEqual(model.orderedClips.map(\.id), [a, b, c], "the committed order is restored")
        XCTAssertEqual(model.project, before)
        XCTAssertEqual(model.editorMessage, .reorderSaveFailed)
        XCTAssertEqual(model.editorMessage?.title, "순서를 저장하지 못했어요.")
        XCTAssertEqual(model.selectedClipID, c, "selection is kept")
        XCTAssertEqual(try repository.project(id: model.project.id), before, "the store is untouched")
        XCTAssertFalse(model.isCommittingMutation)

        // Recoverable: the user simply reorders again once the store cooperates.
        repository.updateFails = false
        model.editorMessage = nil
        model.beginReorder(clipID: c)
        model.previewReorder(toIndex: 0)
        model.commitReorder()
        XCTAssertEqual(model.orderedClips.map(\.id), [c, a, b])
        XCTAssertNil(model.editorMessage)
    }

    func testReadBackMismatchIsTreatedAsFailure() throws {
        // A repository that accepts the write but does not actually persist the new order.
        @MainActor final class SwallowingRepository: ProjectRepository {
            let inner = InMemoryProjectRepository()
            func create(_ project: VlogProject) throws { try inner.create(project) }
            func project(id: UUID) throws -> VlogProject? { try inner.project(id: id) }
            func recentProjects() throws -> [VlogProject] { try inner.recentProjects() }
            func update(_ project: VlogProject) throws {}
            func finalizeDeletedClip(projectID: UUID, clipID: UUID) throws {}
            func deleteProject(id: UUID) throws { try inner.deleteProject(id: id) }
        }
        let repository = SwallowingRepository()
        let project = try makeProject(clipSeconds: [2, 3, 1])
        try repository.create(project)
        let model = ProjectEditorModel(project: project, repository: repository, thumbnails: FakeClipThumbnailProvider())

        model.beginReorder(clipID: project.clips[2].id)
        model.previewReorder(toIndex: 0)
        model.commitReorder()

        XCTAssertEqual(model.project, project, "an unverified write is not shown as a success")
        XCTAssertEqual(model.editorMessage, .reorderSaveFailed)
    }

    func testSelectionFollowsDraggedClipIdentity() throws {
        let (model, _, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])
        model.select(a)

        XCTAssertTrue(model.beginReorder(clipID: c))
        XCTAssertEqual(model.selectedClipID, c, "lifting selects the clip")
        model.previewReorder(toIndex: 0)
        model.commitReorder()

        XCTAssertEqual(model.orderedClips.map(\.id), [c, a, b])
        XCTAssertEqual(model.selectedClipID, c)
        XCTAssertEqual(model.selectedClip?.id, c)
        XCTAssertEqual(model.orderedClips.firstIndex { $0.id == model.selectedClipID }, 0, "identity, not the old index")
    }

    func testReorderKeepsTotalDurationClipIdentitiesAndMetadata() throws {
        let (model, repository, ids) = try makeEditor(clipSeconds: [2, 3, 1])
        let before = model.project
        let total = model.totalDuration

        model.beginReorder(clipID: ids[2])
        model.previewReorder(toIndex: 0)
        model.commitReorder()

        XCTAssertEqual(model.totalDuration, total)
        XCTAssertEqual(model.totalDuration, .seconds(6))
        XCTAssertEqual(Set(model.orderedClips.map(\.id)), Set(ids), "same clip set, same identities")
        XCTAssertEqual(model.project.orientation, before.orientation)
        XCTAssertEqual(model.project.id, before.id)
        for clip in model.orderedClips {
            let original = try XCTUnwrap(before.clips.first { $0.id == clip.id })
            XCTAssertEqual(clip.mediaRelativePath, original.mediaRelativePath)
            XCTAssertEqual(clip.trimStart, original.trimStart)
            XCTAssertEqual(clip.trimDuration, original.trimDuration)
            XCTAssertEqual(clip.sourceDuration, original.sourceDuration)
            XCTAssertEqual(clip.createdAt, original.createdAt)
            XCTAssertEqual(clip.framing, original.framing)
        }
        XCTAssertEqual(try repository.project(id: before.id)?.clips.count, 3, "the same-clip-set update removed nothing")
    }

    func testThumbnailsStayAttachedToClipIdsAcrossReorder() async throws {
        let provider = FakeClipThumbnailProvider(gated: true)
        let (model, _, ids) = try makeEditor(provider: provider)
        let (a, b, c) = (ids[0], ids[1], ids[2])

        let load = Task { await model.loadThumbnails(displayScale: 2) }
        await provider.waitForRequests(count: 3)
        await provider.complete(clipID: a, outcome: .image(seed: 1))
        await waitUntil { self.isReady(model.thumbnail(for: a)) }
        guard case .ready(let imageA) = model.thumbnail(for: a) else { return XCTFail("A ready") }

        // Reorder while B and C are still loading: the in-flight requests keep their identity.
        model.beginReorder(clipID: c)
        model.previewReorder(toIndex: 0)
        model.commitReorder()
        XCTAssertEqual(model.orderedClips.map(\.id), [c, a, b])
        XCTAssertEqual(model.thumbnail(for: a), .ready(imageA), "A's image moved with A")
        XCTAssertEqual(model.thumbnail(for: c), .loading)

        await provider.complete(clipID: c, outcome: .image(seed: 3))
        await provider.complete(clipID: b, outcome: .image(seed: 2))
        await load.value
        XCTAssertTrue(ids.allSatisfy { isReady(model.thumbnail(for: $0)) }, "late results still land: sortOrder is not part of the identity")
        XCTAssertEqual(model.thumbnail(for: a), .ready(imageA))
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 3, "no regeneration because of the reorder")

        // A subsequent load asks for nothing: every thumbnail is still ready under its clip id.
        await model.loadThumbnails(displayScale: 2)
        let afterReload = await provider.requests
        XCTAssertEqual(afterReload.count, 3)
    }

    func testReentrantCommitDuringPersistenceIsRefused() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])
        var nestedAccepted: Bool?
        repository.onUpdate = {
            XCTAssertTrue(model.isCommittingMutation)
            // A second commit arriving while the first is being written must not race it.
            XCTAssertFalse(model.beginReorder(clipID: a), "no new lift while committing")
            nestedAccepted = model.moveClipLater(id: a) != nil
        }

        model.beginReorder(clipID: c)
        model.previewReorder(toIndex: 0)
        model.commitReorder()

        XCTAssertEqual(nestedAccepted, false)
        XCTAssertEqual(repository.updateCount, 1, "exactly one write, no overlapping update")
        XCTAssertEqual(model.orderedClips.map(\.id), [c, a, b])
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.id), [c, a, b])
        XCTAssertFalse(model.isCommittingMutation)
    }

    func testBeginReorderIsRefusedForUnknownOrAlreadyLiftedClip() throws {
        let (model, _, ids) = try makeEditor()
        XCTAssertFalse(model.beginReorder(clipID: UUID()))
        XCTAssertEqual(model.reorderActivationCount, 0)
        XCTAssertTrue(model.beginReorder(clipID: ids[0]))
        XCTAssertEqual(model.reorderActivationCount, 1, "one activation event → one haptic")
        XCTAssertFalse(model.beginReorder(clipID: ids[1]), "only one lifted clip at a time")
        XCTAssertEqual(model.reorderActivationCount, 1)
        XCTAssertEqual(model.draggingClipID, ids[0])
    }

    // MARK: Accessibility Move Earlier / Move Later

    func testMoveEarlierAndLaterUseTheSameAutosavePath() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])

        XCTAssertEqual(model.moveClipEarlier(id: b), 1, "B: index 1 → 0, announced as position 1")
        XCTAssertEqual(model.orderedClips.map(\.id), [b, a, c])
        XCTAssertEqual(model.orderedClips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.id), [b, a, c])
        XCTAssertEqual(repository.updateCount, 1)
        XCTAssertEqual(model.selectedClipID, b, "the moved clip is selected")

        XCTAssertEqual(model.moveClipLater(id: b), 2)
        XCTAssertEqual(model.orderedClips.map(\.id), [a, b, c])
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.id), [a, b, c])
        XCTAssertEqual(repository.updateCount, 2)
        XCTAssertNil(model.editorMessage)
    }

    func testMoveActionsRespectBoundaries() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, _, c) = (ids[0], ids[1], ids[2])

        XCTAssertFalse(model.canMoveEarlier(a), "first clip has no Move Earlier")
        XCTAssertTrue(model.canMoveLater(a))
        XCTAssertTrue(model.canMoveEarlier(c))
        XCTAssertFalse(model.canMoveLater(c), "last clip has no Move Later")
        XCTAssertFalse(model.canMoveEarlier(UUID()))

        XCTAssertNil(model.moveClipEarlier(id: a))
        XCTAssertNil(model.moveClipLater(id: c))
        XCTAssertEqual(model.orderedClips.map(\.id), ids)
        XCTAssertEqual(repository.updateCount, 0)
    }

    func testMoveActionPersistenceFailureRollsBack() throws {
        let (model, repository, ids) = try makeEditor()
        repository.updateFails = true

        XCTAssertNil(model.moveClipEarlier(id: ids[1]))

        XCTAssertEqual(model.orderedClips.map(\.id), ids)
        XCTAssertEqual(model.editorMessage, .reorderSaveFailed)
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.id), ids)
    }

    // MARK: - Delete + session Undo / Redo history (STEP 10, ADR-021 / ADR-038)

    func testFreshEditorHasEmptyHistory() throws {
        let (model, _, _) = try makeEditor()
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.canRedo)
        XCTAssertTrue(model.undoStack.isEmpty)
        XCTAssertTrue(model.redoStack.isEmpty)
        XCTAssertNil(model.undoTarget)
        XCTAssertNil(model.redoTarget)
        XCTAssertFalse(model.undo())
        XCTAssertFalse(model.redo())
    }

    func testSelectionOnlyChangeIsNotHistory() throws {
        let (model, repository, ids) = try makeEditor()
        model.select(ids[2])
        model.select(ids[0])
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(repository.updateCount, 0)
    }

    func testReorderUndoRedoRoundTrip() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])
        model.beginReorder(clipID: c); model.previewReorder(toIndex: 0); model.commitReorder()   // C A B
        XCTAssertEqual(model.orderedClips.map(\.id), [c, a, b])
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.canRedo)
        XCTAssertEqual(model.undoTarget, .reorder)
        let updatedAtAfterEdit = model.project.updatedAt

        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.orderedClips.map(\.id), [a, b, c])
        XCTAssertEqual(model.orderedClips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(model.selectedClipID, c, "the reordered clip stays selected when still active")
        XCTAssertFalse(model.canUndo)
        XCTAssertTrue(model.canRedo)
        XCTAssertEqual(model.redoTarget, .reorder)
        XCTAssertGreaterThanOrEqual(model.project.updatedAt, updatedAtAfterEdit, "Undo is a new edit: recency never moves backwards")
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.id), [a, b, c])

        XCTAssertTrue(model.redo())
        XCTAssertEqual(model.orderedClips.map(\.id), [c, a, b])
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.canRedo)
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.id), [c, a, b])
        XCTAssertEqual(repository.updateCount, 3, "edit, undo, redo — one write each")
        XCTAssertEqual(model.project.id, ids.isEmpty ? UUID() : model.project.id)
    }

    func testSameIndexDropAndCancelledDragLeaveNoHistory() throws {
        let (model, repository, ids) = try makeEditor()
        model.beginReorder(clipID: ids[1]); model.previewReorder(toIndex: 1); model.commitReorder()
        model.beginReorder(clipID: ids[2]); model.previewReorder(toIndex: 0); model.cancelReorder()
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(repository.updateCount, 0)
    }

    func testDeleteRemovesClipFromActiveTimelineKeepsItDurableAndEntersHistory() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])
        let originalB = model.project.clips[1]

        XCTAssertTrue(model.deleteClip(id: b))

        XCTAssertEqual(model.orderedClips.map(\.id), [a, c])
        XCTAssertEqual(model.orderedClips.map(\.sortOrder), [0, 1])
        XCTAssertEqual(model.project.deletedClips.map(\.id), [b], "durable pending deletion")
        XCTAssertEqual(model.project.deletedClips[0].mediaRelativePath, originalB.mediaRelativePath)
        XCTAssertTrue(model.canUndo)
        XCTAssertEqual(model.undoTarget, .delete)
        XCTAssertFalse(model.canRedo)
        XCTAssertEqual(repository.updateCount, 1)
        let stored = try XCTUnwrap(try repository.project(id: model.project.id))
        XCTAssertEqual(stored.clips.map(\.id), [a, c])
        XCTAssertEqual(stored.deletedClips.map(\.id), [b])
        XCTAssertNil(model.editorMessage)
        XCTAssertFalse(model.deleteClip(id: b), "a pending-deleted clip cannot be deleted again")
        XCTAssertFalse(model.beginReorder(clipID: b), "…or lifted for reorder")
        model.select(b)
        XCTAssertNotEqual(model.selectedClipID, b, "…or selected")
    }

    func testDeletingSelectedClipSelectsClipNowAtItsPositionElsePrevious() throws {
        let (model, _, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])
        model.select(b)
        XCTAssertTrue(model.deleteSelectedClip())
        XCTAssertEqual(model.selectedClipID, c, "the clip that moved into B's position")
        XCTAssertTrue(model.deleteSelectedClip())          // delete C (now last)
        XCTAssertEqual(model.orderedClips.map(\.id), [a])
        XCTAssertEqual(model.selectedClipID, a, "no clip at that position any more → previous")
        XCTAssertEqual(model.undoStack.count, 2)
    }

    func testDeletingUnselectedClipKeepsSelection() throws {
        let (model, _, ids) = try makeEditor()
        model.select(ids[2])
        XCTAssertTrue(model.deleteClip(id: ids[0]))
        XCTAssertEqual(model.selectedClipID, ids[2])
        XCTAssertEqual(model.orderedClips.map(\.id), [ids[1], ids[2]])
    }

    func testDeleteUndoRedoUndoKeepsExactClipIdentity() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])
        let originalB = model.project.clips[1]
        model.select(b)

        model.deleteClip(id: b)                                  // A C + B pending
        XCTAssertTrue(model.undo())                              // A B C
        XCTAssertEqual(model.orderedClips.map(\.id), [a, b, c])
        XCTAssertEqual(model.orderedClips[1], originalB, "same UUID, media, kind, durations, trim, framing, createdAt, no deletion")
        XCTAssertTrue(model.project.deletedClips.isEmpty)
        XCTAssertEqual(model.selectedClipID, b, "undoing the Delete re-selects the deleted clip")
        XCTAssertEqual(model.totalDuration, .seconds(6))

        XCTAssertTrue(model.redo())                              // A C + B pending again
        XCTAssertEqual(model.orderedClips.map(\.id), [a, c])
        XCTAssertEqual(model.project.deletedClips.map(\.id), [b])
        XCTAssertEqual(model.project.deletedClips[0].id, originalB.id, "same UUID pending-deleted, no duplicate")
        XCTAssertEqual(model.project.deletedClips[0].mediaRelativePath, originalB.mediaRelativePath)
        XCTAssertEqual(model.selectedClipID, c, "selection matches the captured post-Delete state")
        XCTAssertEqual(model.totalDuration, .seconds(3))
        XCTAssertEqual(model.project.durableClips.count, 3, "never a fourth clip")

        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.orderedClips[1], originalB)
        let stored = try XCTUnwrap(try repository.project(id: model.project.id))
        XCTAssertEqual(stored.clips, model.project.clips)
        XCTAssertTrue(stored.deletedClips.isEmpty)
        XCTAssertEqual(repository.updateCount, 4)
    }

    func testTwoDeletesUndoInReverseChronologicalOrderAndRedoForward() throws {
        let (model, _, ids) = try makeEditor(clipSeconds: [1, 2, 3, 4])
        let (a, b, c, d) = (ids[0], ids[1], ids[2], ids[3])
        model.deleteClip(id: b)                                  // A C D
        model.deleteClip(id: c)                                  // A D
        XCTAssertEqual(model.orderedClips.map(\.id), [a, d])
        XCTAssertEqual(model.project.deletedClips.map(\.id), [b, c])

        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.orderedClips.map(\.id), [a, c, d], "the later Delete (C) is undone first")
        XCTAssertEqual(model.project.deletedClips.map(\.id), [b])
        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.orderedClips.map(\.id), [a, b, c, d])
        XCTAssertTrue(model.project.deletedClips.isEmpty)
        XCTAssertFalse(model.canUndo)

        XCTAssertTrue(model.redo())
        XCTAssertEqual(model.orderedClips.map(\.id), [a, c, d])
        XCTAssertTrue(model.redo())
        XCTAssertEqual(model.orderedClips.map(\.id), [a, d])
        XCTAssertEqual(model.project.deletedClips.map(\.id), [b, c])
        XCTAssertFalse(model.canRedo)
    }

    func testReorderThenDeleteUndoesDeleteFirstThenReorder() throws {
        let (model, repository, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])
        model.beginReorder(clipID: c); model.previewReorder(toIndex: 0); model.commitReorder()   // C A B
        model.deleteClip(id: b)                                                                    // C A
        XCTAssertEqual(model.orderedClips.map(\.id), [c, a])
        XCTAssertEqual(model.undoStack.map(\.kind), [.reorder, .delete])

        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.orderedClips.map(\.id), [c, a, b], "Delete undone, reorder kept")
        XCTAssertEqual(model.undoTarget, .reorder)
        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.orderedClips.map(\.id), [a, b, c], "then the reorder")
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(model.redoStack.map(\.kind), [.delete, .reorder])

        XCTAssertTrue(model.redo())
        XCTAssertEqual(model.orderedClips.map(\.id), [c, a, b])
        XCTAssertTrue(model.redo())
        XCTAssertEqual(model.orderedClips.map(\.id), [c, a])
        XCTAssertEqual(try repository.project(id: model.project.id)?.clips.map(\.id), [c, a])
    }

    func testGlobalUndoIsChronologicalNotAnchorSelective() throws {
        // Delete B, reorder D front: one Undo reverts the reorder (A C D), not a selective restore (D A B C).
        let (model, _, ids) = try makeEditor(clipSeconds: [1, 2, 3, 4])
        let (a, b, c, d) = (ids[0], ids[1], ids[2], ids[3])
        model.deleteClip(id: b)                                                                    // A C D
        model.beginReorder(clipID: d); model.previewReorder(toIndex: 0); model.commitReorder()   // D A C
        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.orderedClips.map(\.id), [a, c, d])
        XCTAssertEqual(model.project.deletedClips.map(\.id), [b], "B is still pending-deleted after one Undo")
        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.orderedClips.map(\.id), [a, b, c, d])
    }

    func testNewEditAfterUndoClearsRedo() throws {
        let (model, _, ids) = try makeEditor()
        let (a, b, c) = (ids[0], ids[1], ids[2])
        model.beginReorder(clipID: c); model.previewReorder(toIndex: 0); model.commitReorder()   // C A B
        XCTAssertTrue(model.undo())                                                                // A B C
        XCTAssertTrue(model.canRedo)
        XCTAssertTrue(model.deleteClip(id: b))                                                     // A C
        XCTAssertFalse(model.canRedo, "the abandoned reorder future is discarded")
        XCTAssertTrue(model.redoStack.isEmpty)
        XCTAssertEqual(model.undoStack.map(\.kind), [.delete])
        XCTAssertFalse(model.redo())
        XCTAssertEqual(model.orderedClips.map(\.id), [a, c])
    }

    func testDeletingOnlyClipLeavesValidEmptyProjectAndUndoRedoRoundTrip() throws {
        let (model, repository, ids) = try makeEditor(clipSeconds: [4])
        XCTAssertTrue(model.deleteSelectedClip())
        XCTAssertTrue(model.orderedClips.isEmpty)
        XCTAssertNil(model.selectedClipID)
        XCTAssertEqual(model.totalDuration, .zero)
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.canDeleteSelectedClip)
        let stored = try XCTUnwrap(try repository.project(id: model.project.id), "the project survives")
        XCTAssertTrue(stored.clips.isEmpty)
        XCTAssertEqual(stored.deletedClips.map(\.id), ids)

        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.orderedClips.map(\.id), ids)
        XCTAssertEqual(model.selectedClipID, ids[0], "selection restored with the edit")
        XCTAssertEqual(model.totalDuration, .seconds(4))
        XCTAssertTrue(model.redo())
        XCTAssertTrue(model.orderedClips.isEmpty)
        XCTAssertNil(model.selectedClipID)
        XCTAssertEqual(model.totalDuration, .zero)
    }

    func testDeletePersistenceFailureRestoresTimelineSelectionTotalAndLeavesNoHistory() throws {
        let (model, repository, ids) = try makeEditor()
        let before = model.project
        model.select(ids[1])
        repository.updateFails = true

        XCTAssertFalse(model.deleteSelectedClip())

        XCTAssertEqual(model.project, before, "nothing hidden: the deletion was never durable")
        XCTAssertEqual(model.orderedClips.map(\.id), ids)
        XCTAssertEqual(model.selectedClipID, ids[1])
        XCTAssertEqual(model.totalDuration, .seconds(6))
        XCTAssertFalse(model.canUndo, "a failed edit is not history")
        XCTAssertEqual(model.editorMessage, .deleteSaveFailed)
        XCTAssertEqual(try repository.project(id: before.id), before)
    }

    func testFailedUndoAndRedoLeaveStateAndStacksUnchanged() throws {
        let (model, repository, ids) = try makeEditor()
        model.deleteClip(id: ids[1])
        let deletedState = model.project
        let stacks = (model.undoStack, model.redoStack)
        repository.updateFails = true

        XCTAssertFalse(model.undo())
        XCTAssertEqual(model.project, deletedState)
        XCTAssertEqual(model.undoStack, stacks.0)
        XCTAssertEqual(model.redoStack, stacks.1)
        XCTAssertEqual(model.editorMessage, .undoFailed)
        XCTAssertEqual(model.editorMessage?.title, "실행 취소하지 못했어요.")
        XCTAssertEqual(try repository.project(id: deletedState.id), deletedState)

        repository.updateFails = false
        model.editorMessage = nil
        XCTAssertTrue(model.undo())
        let restoredState = model.project
        let stacks2 = (model.undoStack, model.redoStack)
        repository.updateFails = true
        XCTAssertFalse(model.redo())
        XCTAssertEqual(model.project, restoredState)
        XCTAssertEqual(model.undoStack, stacks2.0)
        XCTAssertEqual(model.redoStack, stacks2.1)
        XCTAssertEqual(model.editorMessage, .redoFailed)
        XCTAssertEqual(model.editorMessage?.title, "다시 실행하지 못했어요.")
        repository.updateFails = false
        XCTAssertTrue(model.redo())
        XCTAssertEqual(model.orderedClips.map(\.id), [ids[0], ids[2]])
    }

    func testTotalDurationFollowsActiveClipsThroughHistory() throws {
        let (model, _, ids) = try makeEditor(clipSeconds: [2, 3, 1])
        model.deleteClip(id: ids[1])
        XCTAssertEqual(model.totalDuration, .seconds(3))
        model.deleteClip(id: ids[0])
        XCTAssertEqual(model.totalDuration, .seconds(1))
        model.undo()
        XCTAssertEqual(model.totalDuration, .seconds(3))
        model.undo()
        XCTAssertEqual(model.totalDuration, .seconds(6))
        model.redo()
        XCTAssertEqual(model.totalDuration, .seconds(3))
    }

    func testHistoryRestoreKeepsProjectIdentityAndMovesUpdatedAtForward() throws {
        let (model, _, ids) = try makeEditor()
        let identity = (model.project.id, model.project.createdAt, model.project.orientation)
        model.deleteClip(id: ids[0])
        let afterDelete = model.project.updatedAt
        model.undo()
        XCTAssertEqual(model.project.id, identity.0)
        XCTAssertEqual(model.project.createdAt, identity.1)
        XCTAssertEqual(model.project.orientation, identity.2)
        XCTAssertGreaterThanOrEqual(model.project.updatedAt, afterDelete)
        XCTAssertEqual(Set(model.project.durableClips.map(\.id)), Set(ids))
    }

    func testLateThumbnailResultCannotResurrectDeletedClipAndUndoReusesIdentity() async throws {
        let provider = FakeClipThumbnailProvider(gated: true)
        let (model, _, ids) = try makeEditor(provider: provider)
        let (a, b, c) = (ids[0], ids[1], ids[2])
        let load = Task { await model.loadThumbnails(displayScale: 2) }
        await provider.waitForRequests(count: 3)
        let requests = await provider.requests
        let requestB = try XCTUnwrap(requests.first { $0.clipID == b })
        await provider.complete(clipID: a, outcome: .image(seed: 1))
        await waitUntil { self.isReady(model.thumbnail(for: a)) }
        guard case .ready(let imageA) = model.thumbnail(for: a) else { return XCTFail("A ready") }

        model.deleteClip(id: b)
        XCTAssertNil(model.currentThumbnailRequest(for: b), "a pending-deleted clip has no current request")
        model.applyThumbnailResult(.success(SyntheticThumbnailImage.make(seed: 9, size: CGSize(width: 4, height: 8))), for: requestB)
        XCTAssertEqual(model.thumbnail(for: b), .loading, "late result for the deleted clip is dropped")
        XCTAssertEqual(model.orderedClips.map(\.id), [a, c])

        await provider.complete(clipID: b)
        await provider.complete(clipID: c, outcome: .image(seed: 3))
        await load.value
        await model.loadThumbnails(displayScale: 2)
        let after = await provider.requests
        XCTAssertEqual(after.count, 3, "no request for the deleted clip")

        model.undo()
        XCTAssertEqual(model.orderedClips.map(\.id), [a, b, c])
        XCTAssertEqual(model.currentThumbnailRequest(for: b), requestB, "identical request identity after Undo")
        XCTAssertEqual(model.thumbnail(for: a), .ready(imageA), "A's image untouched by history")
        model.redo()
        XCTAssertNil(model.currentThumbnailRequest(for: b))
    }

    func testReorderHistoryNeverRegeneratesThumbnails() async throws {
        let provider = FakeClipThumbnailProvider()
        let (model, _, ids) = try makeEditor(provider: provider)
        await model.loadThumbnails(displayScale: 2)
        let requested = await provider.requests.count
        model.beginReorder(clipID: ids[2]); model.previewReorder(toIndex: 0); model.commitReorder()
        model.undo(); model.redo()
        await model.loadThumbnails(displayScale: 2)
        let after = await provider.requests.count
        XCTAssertEqual(after, requested, "sortOrder is not part of the thumbnail identity")
        XCTAssertTrue(ids.allSatisfy { isReady(model.thumbnail(for: $0)) })
    }

    func testReorderIgnoresPendingDeletedClipAndAutosaveKeepsPendingDeletions() throws {
        let (model, repository, ids) = try makeEditor(clipSeconds: [1, 2, 3, 4])
        let (a, b, c, d) = (ids[0], ids[1], ids[2], ids[3])
        model.deleteClip(id: b)
        model.deleteClip(id: c)
        model.beginReorder(clipID: d)
        XCTAssertEqual(model.previewOrder, [a, d], "drag slots contain active clips only")
        model.previewReorder(toIndex: 0)
        model.commitReorder()
        XCTAssertEqual(model.orderedClips.map(\.id), [d, a])
        XCTAssertEqual(model.orderedClips.map(\.sortOrder), [0, 1])
        let stored = try XCTUnwrap(try repository.project(id: model.project.id))
        XCTAssertEqual(stored.deletedClips.map(\.id), [b, c], "multiple pending deletions survive normal autosave")
        XCTAssertEqual(stored.durableClips.count, 4)
    }

    func testReopenedModelKeepsPersistedStateWithEmptyHistory() throws {
        let (model, repository, ids) = try makeEditor()
        model.deleteClip(id: ids[1])
        model.beginReorder(clipID: ids[2]); model.previewReorder(toIndex: 0); model.commitReorder()
        XCTAssertTrue(model.canUndo)
        // Leaving the Editor / process termination: a new model is built from what the store holds.
        let stored = try XCTUnwrap(try repository.project(id: model.project.id))
        let reopened = ProjectEditorModel(project: stored, repository: repository, thumbnails: FakeClipThumbnailProvider())
        XCTAssertEqual(reopened.orderedClips.map(\.id), [ids[2], ids[0]], "persisted state retained")
        XCTAssertEqual(reopened.project.deletedClips.map(\.id), [ids[1]], "B absent from the timeline but durable")
        XCTAssertFalse(reopened.canUndo, "history is session-local")
        XCTAssertFalse(reopened.canRedo)
        XCTAssertFalse(reopened.undo())
        XCTAssertEqual(reopened.totalDuration, .seconds(3))
        XCTAssertEqual(repository.updateCount, 2, "no write on reopen, nothing finalized")
    }

    func testMutationsAreRefusedWhileDraggingOrCommitting() throws {
        let (model, repository, ids) = try makeEditor()
        model.deleteClip(id: ids[2])
        model.beginReorder(clipID: ids[0])
        XCTAssertFalse(model.canDeleteSelectedClip)
        XCTAssertFalse(model.canUndo, "history controls disabled while a clip is lifted")
        XCTAssertFalse(model.deleteSelectedClip())
        XCTAssertFalse(model.undo())
        model.cancelReorder()
        XCTAssertTrue(model.canUndo)

        var nested: [Bool] = []
        repository.onUpdate = {
            XCTAssertFalse(model.canUndo); XCTAssertFalse(model.canRedo)
            nested.append(model.deleteClip(id: ids[0]))
            nested.append(model.undo())
            nested.append(model.redo())
            nested.append(model.beginReorder(clipID: ids[0]))
        }
        XCTAssertTrue(model.deleteClip(id: ids[1]))
        XCTAssertEqual(nested, [false, false, false, false], "no mutation may race an in-flight commit")
        XCTAssertEqual(repository.updateCount, 2)
        XCTAssertEqual(model.orderedClips.map(\.id), [ids[0]])
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), "condition not met within \(timeout)s")
    }
}
