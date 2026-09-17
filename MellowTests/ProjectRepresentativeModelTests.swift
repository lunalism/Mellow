import CoreGraphics
import Foundation
import XCTest
@testable import Mellow

/// Phase 5 STEP 14: representative source selection + derived thumbnail state of the saved Project.
/// The saved-Project rule is the repository's recency order (`recentProjects().first`), availability
/// is the deterministic fake (identity-based, like the seeded UI routes), thumbnails come from the
/// scripted / gated fake provider so late results can be driven exactly.
@MainActor
final class ProjectRepresentativeModelTests: XCTestCase {
    private func makeClip(projectID: UUID, seconds: Int64, order: Int) throws -> VlogClip {
        let id = UUID()
        return try VlogClip(
            id: id, projectID: projectID, sourceKind: .imported,
            mediaRelativePath: try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: id),
            sourceDuration: .seconds(seconds), trimDuration: .seconds(seconds), sortOrder: order
        )
    }

    private func makeProject(seconds: [Int64] = [2, 3, 1]) throws -> VlogProject {
        let id = UUID()
        let clips = try seconds.enumerated().map { try makeClip(projectID: id, seconds: $0.element, order: $0.offset) }
        return try VlogProject(id: id, orientation: .portrait9x16, clips: clips)
    }

    private struct Harness {
        let repository: InMemoryProjectRepository
        let availability: FakeClipAvailabilityChecker
        let provider: FakeClipThumbnailProvider
        let model: ProjectRepresentativeModel
    }

    private func makeHarness(project: VlogProject?, unavailable: Set<UUID> = [], gated: Bool = false, script: [UUID: FakeClipThumbnailProvider.Outcome] = [:]) throws -> Harness {
        let repository = InMemoryProjectRepository()
        if let project { try repository.create(project) }
        let availability = FakeClipAvailabilityChecker(unavailableClipIDs: unavailable)
        let provider = FakeClipThumbnailProvider(script: script, gated: gated)
        let model = ProjectRepresentativeModel(
            savedProject: { try repository.recentProjects().first },
            availability: availability, thumbnails: provider, lifecycle: ProjectLifecycleOperationGate()
        )
        return Harness(repository: repository, availability: availability, provider: provider, model: model)
    }

    private func representativeClipID(_ h: Harness) -> UUID? { h.model.currentRequest?.clipID }

    // MARK: - Selection (1–5, 14)

    func testNoSavedProjectYieldsNoRepresentative() async throws {
        let h = try makeHarness(project: nil)
        await h.model.refresh()
        XCTAssertEqual(h.model.state, .noProject)
        XCTAssertNil(h.model.currentRequest)
        let requests = await h.provider.requests
        XCTAssertTrue(requests.isEmpty, "nothing to generate")
    }

    func testEmptyProjectYieldsProjectPlaceholder() async throws {
        let project = try VlogProject(orientation: .portrait9x16)
        let h = try makeHarness(project: project)
        await h.model.refresh()
        XCTAssertEqual(h.model.state, .project(id: project.id, thumbnail: nil))
        XCTAssertNil(h.model.currentRequest)
    }

    func testFirstHealthyClipInLogicalOrderIsSelectedAndGenerated() async throws {
        let project = try makeProject()
        let h = try makeHarness(project: project)
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), project.clips[0].id)
        XCTAssertEqual(h.model.state.savedProjectID, project.id)
        XCTAssertNotNil(h.model.state.thumbnail, "generated through the STEP 8 boundary")
        let requests = await h.provider.requests
        XCTAssertEqual(requests.map(\.clipID), [project.clips[0].id], "only the representative is requested")
        XCTAssertEqual(requests.first?.mediaRelativePath, project.clips[0].mediaRelativePath)
        XCTAssertEqual(requests.first?.maximumPixelSize, ProjectRepresentativeModel.thumbnailPixelSize)
        let seen = await h.availability.requests
        XCTAssertEqual(seen, [project.clips[0].id], "availability stops at the first usable Clip")
    }

    func testFirstUnavailableClipIsSkippedForSelectionOnly() async throws {
        let project = try makeProject()
        let h = try makeHarness(project: project, unavailable: [project.clips[0].id])
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), project.clips[1].id)
        XCTAssertEqual(try h.repository.project(id: project.id), project, "the Project itself is never mutated to skip")
    }

    func testAllUnavailableProjectYieldsPlaceholder() async throws {
        let project = try makeProject()
        let h = try makeHarness(project: project, unavailable: Set(project.clips.map(\.id)))
        await h.model.refresh()
        XCTAssertEqual(h.model.state, .project(id: project.id, thumbnail: nil))
        XCTAssertNil(h.model.currentRequest)
        let requests = await h.provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testPendingDeletedClipIsNeverSelectedEvenWithReadableMedia() async throws {
        var project = try makeProject()
        let first = project.clips[0].id
        try project.deleteClip(id: first)
        let h = try makeHarness(project: project)
        await h.model.refresh()
        XCTAssertNotEqual(representativeClipID(h), first)
        XCTAssertEqual(representativeClipID(h), project.clips[0].id, "B, the first ACTIVE clip")
    }

    // MARK: - Re-evaluation after mutations (6–13)

    func testReorderDeleteUndoRedoAddReplaceRecomputeFromCurrentOrder() async throws {
        var project = try makeProject()                                            // A B C
        let (a, b, c) = (project.clips[0].id, project.clips[1].id, project.clips[2].id)
        let h = try makeHarness(project: project)
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), a)

        try project.reorderClip(id: b, toIndex: 0); try h.repository.update(project)     // B A C
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), b, "reorder changes the source")

        try project.deleteClip(id: b); try h.repository.update(project)                // A C, B pending
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), a, "delete changes the source")

        try project.restoreDeletedClip(id: b); try h.repository.update(project)        // B A C (undo delete)
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), b, "undo delete recomputes")

        try project.deleteClip(id: b); try h.repository.update(project)                // redo delete
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), a, "redo delete recomputes")

        let added = try makeClip(projectID: project.id, seconds: 4, order: 0)
        try project.appendClips([added]); try h.repository.update(project)            // A C D
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), a, "an appended clip is not first, so it is not representative")
        try project.reorderClip(id: added.id, toIndex: 0); try h.repository.update(project)   // D A C
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), added.id, "…until logical order makes it first")

        // Replace the (now unavailable) first clip D with E: E takes the slot and becomes representative.
        await h.availability.setUnavailable([added.id])
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), a, "unavailable D skipped → A")
        let replacement = try makeClip(projectID: project.id, seconds: 5, order: 0)
        try project.replaceClip(id: added.id, with: replacement); try h.repository.update(project)   // E A C
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), replacement.id, "replace changes the source")

        // Undo Replace (history restore, as the Editor's commitHistory would persist it): D active again
        // (still unavailable), E kept as durable pending → A. Redo: E A C again.
        let bPending = try XCTUnwrap(project.deletedClips.first { $0.id == b })
        let dPending = try XCTUnwrap(project.deletedClips.first { $0.id == added.id })
        let ePending = try replacement.assigning(sortOrder: 0, deletion: ClipDeletionRecord(deletedAt: .now, originalIndex: 0, previousClipID: nil, nextClipID: a))
        let undone = try VlogProject(id: project.id, createdAt: project.createdAt, orientation: project.orientation,
                                     clips: try [added, project.clips[1], project.clips[2]].enumerated().map { try $1.assigningSortOrder($0) },
                                     deletedClips: [bPending, ePending])
        try h.repository.update(undone)
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), a, "undo replace restores the source logic")
        let redone = try VlogProject(id: project.id, createdAt: project.createdAt, orientation: project.orientation,
                                     clips: project.clips, deletedClips: [bPending, dPending])
        try h.repository.update(redone)
        await h.model.refresh()
        XCTAssertEqual(representativeClipID(h), replacement.id, "redo replace restores the replacement source")
        _ = c
    }

    // MARK: - Thumbnail failure (15)

    func testThumbnailFailureKeepsPlaceholderAndDoesNotTouchAvailabilityOrProject() async throws {
        let project = try makeProject()
        let h = try makeHarness(project: project, script: [project.clips[0].id: .failure(.generationFailed)])
        await h.model.refresh()
        XCTAssertEqual(h.model.state, .project(id: project.id, thumbnail: nil), "placeholder, Project still valid")
        XCTAssertEqual(representativeClipID(h), project.clips[0].id, "the healthy clip stays the source")
        let availability = await h.availability.availability(for: project.clips[0])
        XCTAssertEqual(availability, .available)
        XCTAssertEqual(try h.repository.project(id: project.id), project)
    }

    // MARK: - Stale results (16–21)

    private func startGatedRefresh(_ h: Harness) async -> (Task<Void, Never>, ClipThumbnailRequest) {
        let task = Task { await h.model.refresh() }
        await h.provider.waitForRequests(count: 1)
        let request = await h.provider.requests.last!
        return (task, request)
    }

    private func image() -> CGImage { SyntheticThumbnailImage.make(seed: 7, size: CGSize(width: 4, height: 8)) }

    func testLateResultAfterReorderIsRejected() async throws {
        var project = try makeProject()
        let h = try makeHarness(project: project, gated: true)
        let (task, requestA) = await startGatedRefresh(h)
        XCTAssertEqual(requestA.clipID, project.clips[0].id)
        try project.reorderClip(id: project.clips[1].id, toIndex: 0); try h.repository.update(project)
        let second = Task { await h.model.refresh() }
        await h.provider.waitForRequests(count: 2)
        XCTAssertEqual(h.model.currentRequest?.clipID, project.clips[0].id, "B is current")
        h.model.applyThumbnailResult(.success(image()), for: requestA)
        XCTAssertNil(h.model.state.thumbnail, "late A result never becomes the representative image")
        await h.provider.complete(clipID: requestA.clipID); await h.provider.complete(clipID: project.clips[0].id)
        await task.value; await second.value
        XCTAssertEqual(h.model.currentRequest?.clipID, project.clips[0].id)
        XCTAssertNotNil(h.model.state.thumbnail, "B's own result lands")
    }

    func testLateResultAfterDeleteIsRejected() async throws {
        var project = try makeProject()
        let a = project.clips[0].id
        let h = try makeHarness(project: project, gated: true)
        let (task, requestA) = await startGatedRefresh(h)
        try project.deleteClip(id: a); try h.repository.update(project)
        let second = Task { await h.model.refresh() }
        await h.provider.waitForRequests(count: 2)
        XCTAssertEqual(h.model.currentRequest?.clipID, project.clips[0].id, "B became representative")
        h.model.applyThumbnailResult(.success(image()), for: requestA)
        XCTAssertNil(h.model.state.thumbnail)
        await h.provider.complete(clipID: a); await h.provider.complete(clipID: project.clips[0].id)
        await task.value; await second.value
        XCTAssertEqual(h.model.currentRequest?.clipID, project.clips[0].id)
    }

    func testLateResultAfterAvailabilityChangeIsRejected() async throws {
        let project = try makeProject()
        let a = project.clips[0].id
        let h = try makeHarness(project: project, gated: true)
        let (task, requestA) = await startGatedRefresh(h)
        await h.availability.setUnavailable([a])
        let second = Task { await h.model.refresh() }
        await h.provider.waitForRequests(count: 2)
        XCTAssertEqual(h.model.currentRequest?.clipID, project.clips[1].id)
        h.model.applyThumbnailResult(.success(image()), for: requestA)
        XCTAssertNil(h.model.state.thumbnail, "A's late image cannot override the availability-derived selection")
        await h.provider.complete(clipID: a); await h.provider.complete(clipID: project.clips[1].id)
        await task.value; await second.value
        XCTAssertEqual(h.model.currentRequest?.clipID, project.clips[1].id)
    }

    func testLateResultAfterReplaceIsRejected() async throws {
        var project = try makeProject()
        let x = project.clips[0].id
        let h = try makeHarness(project: project, gated: true)
        let (task, requestX) = await startGatedRefresh(h)
        let d = try makeClip(projectID: project.id, seconds: 4, order: 0)
        try project.replaceClip(id: x, with: d); try h.repository.update(project)
        let second = Task { await h.model.refresh() }
        await h.provider.waitForRequests(count: 2)
        XCTAssertEqual(h.model.currentRequest?.clipID, d.id)
        h.model.applyThumbnailResult(.success(image()), for: requestX)
        XCTAssertNil(h.model.state.thumbnail, "X's late image never overwrites D")
        await h.provider.complete(clipID: x); await h.provider.complete(clipID: d.id)
        await task.value; await second.value
        XCTAssertEqual(h.model.currentRequest?.clipID, d.id)
        XCTAssertNotNil(h.model.state.thumbnail)
    }

    func testLateResultFromReplacedProjectNeverPublishesIntoTheNewProject() async throws {
        let p1 = try makeProject()
        let h = try makeHarness(project: p1, gated: true)
        let (task, requestP1) = await startGatedRefresh(h)
        // Safe Atomic Replacement: P2 becomes the saved Project, P1 is retired.
        let p2 = try makeProject(seconds: [4, 4])
        try h.repository.deleteProject(id: p1.id)
        try h.repository.create(p2)
        let second = Task { await h.model.refresh() }
        await h.provider.waitForRequests(count: 2)
        XCTAssertEqual(h.model.state.savedProjectID, p2.id)
        h.model.applyThumbnailResult(.success(image()), for: requestP1)
        XCTAssertNil(h.model.state.thumbnail, "old Project's result cannot publish into P2's slot")
        await h.provider.complete(clipID: requestP1.clipID); await h.provider.complete(clipID: p2.clips[0].id)
        await task.value; await second.value
        XCTAssertEqual(h.model.currentRequest?.projectID, p2.id)
        XCTAssertNotNil(h.model.state.thumbnail, "P2's own representative lands")
    }

    func testProjectDeletionClearsRepresentativeAndLateResultCannotResurrectIt() async throws {
        let project = try makeProject()
        let h = try makeHarness(project: project, gated: true)
        let (task, request) = await startGatedRefresh(h)
        XCTAssertEqual(h.model.state.savedProjectID, project.id)
        try h.repository.deleteProject(id: project.id)
        await h.model.refresh()
        XCTAssertEqual(h.model.state, .noProject)
        XCTAssertNil(h.model.currentRequest)
        h.model.applyThumbnailResult(.success(image()), for: request)
        XCTAssertEqual(h.model.state, .noProject, "no resurrection")
        await h.provider.complete(clipID: request.clipID)
        await task.value
        XCTAssertEqual(h.model.state, .noProject)
    }

    // MARK: - Cache reuse / no flicker

    func testReturningToAPreviousRepresentativeReusesItsImageWithoutRegeneration() async throws {
        var project = try makeProject()
        let h = try makeHarness(project: project)
        await h.model.refresh()
        let imageA = h.model.state.thumbnail
        XCTAssertNotNil(imageA)
        try project.reorderClip(id: project.clips[1].id, toIndex: 0); try h.repository.update(project)
        await h.model.refresh()
        try project.reorderClip(id: project.clips[1].id, toIndex: 0); try h.repository.update(project)   // back to A B C
        await h.model.refresh()
        XCTAssertTrue(h.model.state.thumbnail === imageA, "same image object, no placeholder flicker")
        let requests = await h.provider.requests
        XCTAssertEqual(requests.count, 2, "A generated once, B once")
    }

    func testLookupFailureLeavesStateUnchanged() async throws {
        let project = try makeProject()
        let h = try makeHarness(project: project)
        await h.model.refresh()
        let before = h.model.state
        struct Boom: Error {}
        let failing = ProjectRepresentativeModel(savedProject: { throw Boom() }, availability: h.availability, thumbnails: h.provider)
        await failing.refresh()
        XCTAssertEqual(failing.state, .noProject, "a fresh model never invents a Project")
        XCTAssertEqual(h.model.state, before)
    }
}
