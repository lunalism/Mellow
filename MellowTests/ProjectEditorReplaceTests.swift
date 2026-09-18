import CoreGraphics
import Foundation
import SwiftData
import XCTest
@testable import Mellow

/// Phase 5 STEP 13 (ADR-040): derived Clip availability and user-driven Replace in the Editor model,
/// against a REAL `ProjectMediaStore` under a temporary root (so "unavailable" is a real missing
/// file), the real Phase-5 validator with real fixture media, and the deterministic fake selector.
@MainActor
final class ProjectEditorReplaceTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!

    override func setUp() {
        root = TestSupport.temporaryRoot("editor-replace")
        store = ProjectMediaStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    // MARK: helpers

    /// A canonical committed Clip; `withFile` writes a small placeholder behind it (availability
    /// never decodes, so bytes are irrelevant; thumbnails come from the fake provider).
    private func committedClip(projectID: UUID, order: Int, seconds: Int64, withFile: Bool) async throws -> VlogClip {
        let clipID = UUID()
        let path = try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID)
        if withFile {
            let url = await store.url(for: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: 128).write(to: url)
        }
        return try VlogClip(id: clipID, projectID: projectID, sourceKind: .recorded, mediaRelativePath: path,
                            sourceDuration: .seconds(seconds), trimDuration: .seconds(seconds), sortOrder: order)
    }

    /// `A B C` = 3 s / 4 s / 2 s; the listed 0-based positions have NO file.
    private func makeProject(seconds: [Int64] = [3, 4, 2], missing: Set<Int> = [1]) async throws -> VlogProject {
        let id = UUID()
        var clips: [VlogClip] = []
        for (index, duration) in seconds.enumerated() {
            clips.append(try await committedClip(projectID: id, order: index, seconds: duration, withFile: !missing.contains(index)))
        }
        return try VlogProject(id: id, orientation: .portrait9x16, clips: clips)
    }

    private struct Harness {
        let repository: FailableProjectRepository
        let selector: FakeProjectMediaSelector
        let provider: FakeClipThumbnailProvider
        let model: ProjectEditorModel
        let ids: [UUID]
    }

    private func makeEditor(
        project: VlogProject? = nil,
        script: FakeProjectMediaSelector.Script = .cancel,
        storage: ProjectStorageVerdict = .sufficient,
        provider: FakeClipThumbnailProvider = FakeClipThumbnailProvider(),
        availability: (any ClipAvailabilityChecking)? = nil
    ) async throws -> Harness {
        let loaded: VlogProject
        if let project { loaded = project } else { loaded = try await makeProject() }
        let repository = FailableProjectRepository()
        try repository.create(loaded)
        let selector = FakeProjectMediaSelector(script: script)
        let appender = ProjectClipAppendCoordinator(mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()), storage: FakeProjectStorageGate(verdict: storage))
        let acquisition = EditorClipAcquisition(mediaStore: store, mediaSelector: selector, storageGate: FakeProjectStorageGate(verdict: storage), appender: appender)
        let model = ProjectEditorModel(project: loaded, repository: repository, thumbnails: provider, acquisition: acquisition,
                                       availability: availability ?? CommittedMediaAvailabilityChecker(resolver: store))
        return Harness(repository: repository, selector: selector, provider: provider, model: model, ids: loaded.clips.map(\.id))
    }

    private func seconds(_ time: MediaTime) -> Double { Double(time.value) / Double(time.timescale) }

    private func mediaFiles(_ projectID: UUID) -> [String] {
        let directory = root.appendingPathComponent("Projects/\(projectID.uuidString)/Media")
        return ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private func isReady(_ state: ClipThumbnailPresentation) -> Bool {
        if case .ready = state { return true }
        return false
    }

    private func makeCleanup(_ h: Harness) -> (ProjectMediaCleanupCoordinator, ProjectStartupRecoveryCoordinator, LiveEditorSessions) {
        let live = LiveEditorSessions()
        let gate = ProjectLifecycleOperationGate()
        let cleanup = ProjectMediaCleanupCoordinator(repository: h.repository, mediaStore: store, consumers: IdleConsumers(), lifecycle: gate, isEditorSessionLive: { live.isLive($0) })
        let recovery = ProjectStartupRecoveryCoordinator(repository: h.repository, store: store, lifecycle: gate, isEditorSessionLive: { live.isLive($0) })
        return (cleanup, recovery, live)
    }

    // MARK: - Availability checker

    func testCheckerClassifiesOnlyMissingOrUnresolvableCommittedMedia() async throws {
        let project = try await makeProject()
        let checker = CommittedMediaAvailabilityChecker(resolver: store)
        let a = await checker.availability(for: project.clips[0])
        let b = await checker.availability(for: project.clips[1])
        XCTAssertEqual(a, .available)
        XCTAssertEqual(b, .unavailable(.mediaMissing))
        XCTAssertTrue(b.isUnavailable); XCTAssertFalse(a.isUnavailable)
        // Any other resolver error preserves the Clip as available (never "missing" by accident).
        struct OtherError: Error {}
        struct FailingResolver: ProjectMediaURLResolving {
            func committedMediaURL(for path: RelativeMediaPath) async throws -> URL { throw OtherError() }
        }
        let preserved = await CommittedMediaAvailabilityChecker(resolver: FailingResolver()).availability(for: project.clips[1])
        XCTAssertEqual(preserved, .available)
    }

    func testRepositoryLoadIsNotRejectedByMissingMediaFile() async throws {
        let project = try await makeProject(missing: [0, 1, 2])
        let directory = URL.temporaryDirectory.appending(path: "MellowReplaceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try MellowModelContainer.makePersistentContainer(storeURL: directory.appending(path: "metadata.store"))
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        try repository.create(project)
        let loaded = try XCTUnwrap(try repository.project(id: project.id))
        XCTAssertEqual(loaded.clips.map(\.id), project.clips.map(\.id), "metadata loads whatever the filesystem holds")
        XCTAssertEqual(loaded.totalDuration, .seconds(9))
    }

    // MARK: - Derived state (§39)

    func testMissingActiveMediaLoadsAsUnavailableInPlaceAndCountsInTotal() async throws {
        let h = try await makeEditor()
        XCTAssertEqual(h.model.availability(for: h.ids[1]), .available, "unknown until evaluated")
        await h.model.loadThumbnails(displayScale: 2)

        XCTAssertEqual(h.model.availability(for: h.ids[0]), .available)
        XCTAssertEqual(h.model.availability(for: h.ids[1]), .unavailable(.mediaMissing))
        XCTAssertEqual(h.model.availability(for: h.ids[2]), .available)
        XCTAssertEqual(h.model.orderedClips.map(\.id), h.ids, "B stays in its logical position")
        XCTAssertEqual(h.model.committedClips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(h.model.totalDuration, .seconds(9), "Total includes the unavailable Clip's trimDuration")
        XCTAssertEqual(h.model.thumbnail(for: h.ids[1]), .mediaUnavailable)
        XCTAssertTrue(isReady(h.model.thumbnail(for: h.ids[0]))); XCTAssertTrue(isReady(h.model.thumbnail(for: h.ids[2])))
        XCTAssertTrue(h.model.project.deletedClips.isEmpty, "never auto-deleted")
        XCTAssertEqual(h.repository.updateCount, 0, "no automatic Project rewrite")
        XCTAssertEqual(try h.repository.project(id: h.model.project.id), h.model.project)
        XCTAssertFalse(h.model.canUndo)

        // Selection: the unavailable Clip selects normally and is the only one that exposes Replace.
        XCTAssertFalse(h.model.isSelectedClipUnavailable); XCTAssertFalse(h.model.canReplaceSelectedClip, "healthy A: no Replace")
        h.model.select(h.ids[1])
        XCTAssertEqual(h.model.selectedClipID, h.ids[1])
        XCTAssertTrue(h.model.isSelectedClipUnavailable); XCTAssertTrue(h.model.canReplaceSelectedClip)
        XCTAssertTrue(h.model.canDeleteSelectedClip, "Delete stays the dock's job")
        h.model.select(h.ids[2])
        XCTAssertFalse(h.model.canReplaceSelectedClip)
    }

    func testKnownUnavailableClipMakesNoThumbnailRequestAndLateResultCannotOverrideIt() async throws {
        let h = try await makeEditor()
        await h.model.loadThumbnails(displayScale: 2)
        let requests = await h.provider.requests
        XCTAssertEqual(requests.count, 2, "only available Clips are requested")
        XCTAssertEqual(TestSupport.sortedClipIDs(requests), TestSupport.sortedIDs([h.ids[0], h.ids[2]]), "B is never requested")
        await h.model.loadThumbnails(displayScale: 2)
        let again = await h.provider.requests
        XCTAssertEqual(again.count, 2, "no retry storm for the missing Clip")

        // A late (or foreign) image for B is dropped: presentation stays derived from availability.
        let request = try XCTUnwrap(h.model.currentThumbnailRequest(for: h.ids[1]))
        h.model.applyThumbnailResult(.success(SyntheticThumbnailImage.make(seed: 1, size: CGSize(width: 4, height: 8))), for: request)
        XCTAssertEqual(h.model.thumbnail(for: h.ids[1]), .mediaUnavailable)
        XCTAssertNil(h.model.thumbnailStates[h.ids[1]])
    }

    func testThumbnailFailureOnExistingMediaIsNotStructuralUnavailability() async throws {
        let project = try await makeProject()
        let provider = FakeClipThumbnailProvider(script: [project.clips[0].id: .failure(.generationFailed)])
        let h = try await makeEditor(project: project, provider: provider)
        await h.model.loadThumbnails(displayScale: 2)
        XCTAssertEqual(h.model.thumbnail(for: h.ids[0]), .unavailable, "derived-data failure keeps its own neutral state")
        XCTAssertEqual(h.model.availability(for: h.ids[0]), .available)
        XCTAssertEqual(h.model.thumbnail(for: h.ids[1]), .mediaUnavailable)
        h.model.select(h.ids[0])
        XCTAssertFalse(h.model.canReplaceSelectedClip, "a thumbnail failure never exposes Replace")
        let requests = await h.provider.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(TestSupport.sortedClipIDs(requests), TestSupport.sortedIDs([h.ids[0], h.ids[2]]), "B (missing media) is never requested; A's failed thumbnail was")
    }

    func testUnavailableClipReordersThroughTheExistingPath() async throws {
        let h = try await makeEditor()
        await h.model.loadThumbnails(displayScale: 2)
        h.model.select(h.ids[1])
        XCTAssertEqual(h.model.moveClipLater(id: h.ids[1]), 3)                                 // A C B
        XCTAssertEqual(h.model.orderedClips.map(\.id), [h.ids[0], h.ids[2], h.ids[1]])
        XCTAssertEqual(h.model.committedClips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(h.model.selectedClipID, h.ids[1], "selection follows B")
        XCTAssertEqual(h.model.undoStack.map(\.kind), [.reorder])
        XCTAssertEqual(h.model.totalDuration, .seconds(9))
        XCTAssertEqual(h.model.availability(for: h.ids[1]), .unavailable(.mediaMissing))
        XCTAssertTrue(h.model.canMoveEarlier(h.ids[1])); XCTAssertFalse(h.model.canMoveLater(h.ids[1]))
        XCTAssertEqual(h.repository.updateCount, 1)
        // Drag path too.
        XCTAssertTrue(h.model.beginReorder(clipID: h.ids[1]))
        h.model.previewReorder(toIndex: 0)
        h.model.commitReorder()                                                                 // B A C
        XCTAssertEqual(h.model.orderedClips.map(\.id), [h.ids[1], h.ids[0], h.ids[2]])
        XCTAssertEqual(h.model.thumbnail(for: h.ids[1]), .mediaUnavailable)
    }

    func testMultipleAndAllUnavailableProjectsLoadIndependently() async throws {
        let two = try await makeEditor(project: try await makeProject(seconds: [1, 2, 3, 4], missing: [1, 3]))
        await two.model.loadThumbnails(displayScale: 2)
        XCTAssertEqual(two.ids.map { two.model.availability(for: $0).isUnavailable }, [false, true, false, true])
        XCTAssertEqual(two.model.orderedClips.map(\.id), two.ids)
        XCTAssertEqual(two.model.totalDuration, .seconds(10))
        two.model.select(two.ids[1]); XCTAssertTrue(two.model.canReplaceSelectedClip)
        two.model.select(two.ids[3]); XCTAssertTrue(two.model.canReplaceSelectedClip)
        XCTAssertTrue(two.model.deleteClip(id: two.ids[1]), "Delete affects only that Clip")
        XCTAssertEqual(two.model.orderedClips.map(\.id), [two.ids[0], two.ids[2], two.ids[3]])
        XCTAssertEqual(two.model.availability(for: two.ids[3]), .unavailable(.mediaMissing))

        let all = try await makeEditor(project: try await makeProject(missing: [0, 1, 2]))
        await all.model.loadThumbnails(displayScale: 2)
        XCTAssertEqual(all.model.orderedClips.count, 3)
        XCTAssertTrue(all.ids.allSatisfy { all.model.availability(for: $0).isUnavailable })
        XCTAssertEqual(all.model.totalDuration, .seconds(9))
        XCTAssertEqual(all.model.selectedClipID, all.ids[0])
        XCTAssertTrue(all.model.isSelectedClipUnavailable); XCTAssertTrue(all.model.canReplaceSelectedClip); XCTAssertTrue(all.model.canDeleteSelectedClip)
        let requests = await all.provider.requests
        XCTAssertTrue(requests.isEmpty, "nothing to request")
        // Deleting every Clip reaches the ordinary valid empty state; the Project is never auto-deleted.
        for id in all.ids { XCTAssertTrue(all.model.deleteClip(id: id)) }
        XCTAssertTrue(all.model.orderedClips.isEmpty); XCTAssertNil(all.model.selectedClipID)
        XCTAssertNotNil(try all.repository.project(id: all.model.project.id))
    }

    func testAvailabilityIsReEvaluatedForTheActiveSetOnEveryLoad() async throws {
        let project = try await makeProject()
        let checker = FakeClipAvailabilityChecker(unavailableClipIDs: [project.clips[1].id])
        let h = try await makeEditor(project: project, availability: checker)
        await h.model.loadThumbnails(displayScale: 2)
        var seen = await checker.requests
        XCTAssertEqual(seen.count, 3); XCTAssertEqual(Set(seen), Set(h.ids), "initial load evaluates every active Clip once")
        XCTAssertEqual(h.model.availability(for: h.ids[1]), .unavailable(.mediaMissing))

        XCTAssertTrue(h.model.deleteClip(id: h.ids[1]))
        await h.model.loadThumbnails(displayScale: 2)
        seen = await checker.requests
        XCTAssertEqual(seen.count, 5); XCTAssertEqual(Set(seen.suffix(2)), [h.ids[0], h.ids[2]], "after Delete only the active set is evaluated")
        XCTAssertTrue(h.model.undo())
        await h.model.loadThumbnails(displayScale: 2)
        seen = await checker.requests
        XCTAssertEqual(seen.count, 8); XCTAssertEqual(Set(seen.suffix(3)), Set(h.ids), "Undo brings B back into the evaluated set")
        XCTAssertEqual(h.model.availability(for: h.ids[1]), .unavailable(.mediaMissing), "re-derived, still missing")
        XCTAssertEqual(h.model.thumbnail(for: h.ids[1]), .mediaUnavailable)
    }

    // MARK: - Delete unavailable (§40)

    func testDeleteUnavailableClipUsesTheOrdinaryHistoryAndCleanupFinalizesMetadataOnly() async throws {
        let h = try await makeEditor()
        await h.model.loadThumbnails(displayScale: 2)
        h.model.select(h.ids[1])
        XCTAssertTrue(h.model.deleteSelectedClip())
        XCTAssertEqual(h.model.orderedClips.map(\.id), [h.ids[0], h.ids[2]])
        XCTAssertEqual(h.model.project.deletedClips.map(\.id), [h.ids[1]])
        XCTAssertEqual(h.model.undoStack.map(\.kind), [.delete])
        XCTAssertEqual(h.model.totalDuration, .seconds(5))
        XCTAssertEqual(h.repository.updateCount, 1)

        XCTAssertTrue(h.model.undo())
        XCTAssertEqual(h.model.orderedClips.map(\.id), h.ids)
        await h.model.loadThumbnails(displayScale: 2)
        XCTAssertEqual(h.model.availability(for: h.ids[1]), .unavailable(.mediaMissing), "back and still unavailable")
        XCTAssertEqual(h.model.selectedClipID, h.ids[1])
        XCTAssertTrue(h.model.redo())
        XCTAssertEqual(h.model.project.deletedClips.map(\.id), [h.ids[1]])

        // Editor exit: STEP 12A sees pending B with no file → metadata finalize only; 12B never
        // treats any active Clip (with or without a file) as an orphan.
        let (cleanup, recovery, live) = makeCleanup(h)
        live.live = [h.model.project.id]
        let skipped = await cleanup.reconcile(projectID: h.model.project.id)
        XCTAssertTrue(skipped.skippedForLiveEditor)
        live.live = []
        let report = await cleanup.reconcile(projectID: h.model.project.id)
        XCTAssertEqual(report.alreadyAbsent, [h.ids[1]]); XCTAssertEqual(report.finalized, [h.ids[1]]); XCTAssertTrue(report.removedFiles.isEmpty)
        let stored = try XCTUnwrap(try h.repository.project(id: h.model.project.id))
        XCTAssertEqual(stored.clips.map(\.id), [h.ids[0], h.ids[2]]); XCTAssertTrue(stored.deletedClips.isEmpty)
        let recovered = await recovery.recoverOrphans()
        XCTAssertEqual(recovered.orphanMediaRemoved, 0); XCTAssertEqual(recovered.preservedReferenced, 2)
        XCTAssertEqual(mediaFiles(h.model.project.id).count, 2, "A and C untouched")
    }

    // MARK: - Replace (§41)

    private func replaceB(_ h: Harness) async throws -> VlogClip {
        await h.model.loadThumbnails(displayScale: 2)
        h.model.select(h.ids[1])
        XCTAssertTrue(h.model.canReplaceSelectedClip)
        let result = await h.model.replaceSelectedClip()
        let newID = try XCTUnwrap(result, "Replace succeeds")
        return try XCTUnwrap(h.model.orderedClips.first { $0.id == newID })
    }

    func testReplaceCreatesNewClipInExactSlotAsOneEdit() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let h = try await makeEditor(script: .fixtures([fixture]))
        let before = h.model.project
        let b = before.clips[1]

        let d = try await replaceB(h)

        XCTAssertEqual(h.model.orderedClips.map(\.id), [h.ids[0], d.id, h.ids[2]], "A D C")
        XCTAssertNotEqual(d.id, b.id)
        XCTAssertEqual(d.projectID, before.id)
        XCTAssertEqual(d.sourceKind, .imported)
        XCTAssertEqual(d.trimStart, .zero)
        XCTAssertEqual(d.trimDuration, d.sourceDuration)
        XCTAssertEqual(seconds(d.trimDuration), 2, accuracy: 0.001)
        XCTAssertNil(d.framing)
        XCTAssertEqual(d.mediaRelativePath, try ProjectMediaStore.committedMediaPath(projectID: before.id, clipID: d.id))
        await assertFileExists(store, d.mediaRelativePath, true, "D is a Project-owned committed copy")
        XCTAssertEqual(h.model.committedClips.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(h.model.project.deletedClips.map(\.id), [b.id], "B durable pending")
        XCTAssertEqual(h.model.project.deletedClips[0].mediaRelativePath, b.mediaRelativePath)
        XCTAssertEqual(h.model.selectedClipID, d.id, "D selected")
        XCTAssertEqual(seconds(h.model.totalDuration), 3 + 2 + 2, accuracy: 0.001, "Total uses D's duration")
        XCTAssertEqual(h.repository.updateCount, 1, "one repository update")
        XCTAssertEqual(h.model.undoStack.map(\.kind), [.replace]); XCTAssertTrue(h.model.redoStack.isEmpty)
        XCTAssertEqual(h.model.undoTarget, .replace); XCTAssertEqual(EditorHistoryEntry.Kind.replace.description, "클립 교체")
        XCTAssertEqual(h.selector.selectionLimits, [1], "exactly one video")
        XCTAssertEqual(h.selector.selectionCount, 1)
        XCTAssertNil(h.model.editorMessage)
        XCTAssertFalse(h.model.isAcquiringClips); XCTAssertFalse(h.model.isReplacingClip)
        XCTAssertEqual(try h.repository.project(id: before.id), h.model.project)
        XCTAssertEqual(mediaFiles(before.id).count, 3, "A, C and D files")
        XCTAssertFalse(h.model.canReplaceSelectedClip, "healthy D: no Replace")

        // Thumbnails / availability after Replace: D is available and requested normally.
        await h.model.loadThumbnails(displayScale: 2)
        XCTAssertEqual(h.model.availability(for: d.id), .available)
        XCTAssertEqual(h.model.availability(for: b.id), .unavailable(.mediaMissing))
        let requests = await h.provider.requests
        XCTAssertEqual(requests.count, 3, "A, C and the replacement D — B never")
        XCTAssertEqual(TestSupport.sortedClipIDs(requests), TestSupport.sortedIDs([h.ids[0], h.ids[2], d.id]))
        XCTAssertTrue(isReady(h.model.thumbnail(for: d.id)))
        let entry = try XCTUnwrap(h.model.undoStack.last)
        XCTAssertEqual(entry.before.clips.map(\.id), h.ids); XCTAssertTrue(entry.before.deletedClips.isEmpty); XCTAssertEqual(entry.before.selectedClipID, b.id)
        XCTAssertEqual(entry.after.clips.map(\.id), [h.ids[0], d.id, h.ids[2]]); XCTAssertEqual(entry.after.deletedClips.map(\.id), [b.id]); XCTAssertEqual(entry.after.selectedClipID, d.id)
    }

    func testUndoAndRedoReplaceSwapIdentitiesWithoutPickerOrCopy() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let h = try await makeEditor(script: .fixtures([fixture]))
        let d = try await replaceB(h)
        let b = h.ids[1]
        let projectID = h.model.project.id
        await h.model.loadThumbnails(displayScale: 2)
        XCTAssertTrue(isReady(h.model.thumbnail(for: d.id)), "D's thumbnail generated once after Replace")

        XCTAssertTrue(h.model.undo())
        XCTAssertEqual(h.model.orderedClips.map(\.id), h.ids, "A B C")
        XCTAssertEqual(h.model.project.deletedClips.map(\.id), [d.id], "D durable pending, B active")
        XCTAssertEqual(h.model.project.deletedClips[0].mediaRelativePath, d.mediaRelativePath)
        await assertFileExists(store, d.mediaRelativePath, true, "D's file retained while the session is live")
        XCTAssertEqual(h.model.selectedClipID, b)
        XCTAssertEqual(h.model.totalDuration, .seconds(9), "Total back to B's metadata duration")
        await h.model.loadThumbnails(displayScale: 2)
        XCTAssertEqual(h.model.availability(for: b), .unavailable(.mediaMissing)); XCTAssertTrue(h.model.isSelectedClipUnavailable)
        XCTAssertEqual(h.model.thumbnail(for: b), .mediaUnavailable)
        XCTAssertEqual(h.repository.updateCount, 2, "one autosave for Undo")
        XCTAssertTrue(h.model.canRedo); XCTAssertEqual(h.model.redoTarget, .replace); XCTAssertFalse(h.model.canUndo)
        XCTAssertEqual(h.selector.selectionCount, 1, "no picker")
        XCTAssertEqual(mediaFiles(projectID).count, 3, "no file copied or removed")
        let stored = try XCTUnwrap(try h.repository.project(id: projectID))
        XCTAssertEqual(stored.clips.map(\.id), h.ids); XCTAssertEqual(stored.deletedClips.map(\.id), [d.id])

        let requestsBeforeRedo = await h.provider.requests.count
        XCTAssertTrue(h.model.redo())
        XCTAssertEqual(h.model.orderedClips.map(\.id), [h.ids[0], d.id, h.ids[2]])
        XCTAssertEqual(h.model.orderedClips[1], d, "exact same D: UUID, path, metadata")
        XCTAssertEqual(h.model.project.deletedClips.map(\.id), [b], "B pending again")
        XCTAssertEqual(h.model.selectedClipID, d.id)
        XCTAssertEqual(seconds(h.model.totalDuration), 7, accuracy: 0.001)
        XCTAssertEqual(h.repository.updateCount, 3)
        XCTAssertEqual(h.selector.selectionCount, 1, "no picker, no transfer")
        XCTAssertEqual(mediaFiles(projectID).count, 3)
        await h.model.loadThumbnails(displayScale: 2)
        let requestsAfterRedo = await h.provider.requests.count
        XCTAssertEqual(requestsAfterRedo, requestsBeforeRedo, "D's ready thumbnail is reused by identity")
        XCTAssertTrue(isReady(h.model.thumbnail(for: d.id)))
        XCTAssertTrue(h.model.canUndo); XCTAssertFalse(h.model.canRedo)
    }

    func testFailedUndoOrRedoOfReplaceLeavesStateAndStacksUnchanged() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let h = try await makeEditor(script: .fixtures([fixture]))
        let d = try await replaceB(h)
        let afterReplace = h.model.project
        h.repository.updateFails = true
        XCTAssertFalse(h.model.undo())
        XCTAssertEqual(h.model.project, afterReplace); XCTAssertEqual(h.model.selectedClipID, d.id)
        XCTAssertEqual(h.model.undoStack.map(\.kind), [.replace]); XCTAssertTrue(h.model.redoStack.isEmpty)
        XCTAssertEqual(h.model.editorMessage, .undoFailed)
        h.model.editorMessage = nil
        h.repository.updateFails = false
        XCTAssertTrue(h.model.undo())
        let afterUndo = h.model.project
        h.repository.updateFails = true
        XCTAssertFalse(h.model.redo())
        XCTAssertEqual(h.model.project, afterUndo); XCTAssertEqual(h.model.selectedClipID, h.ids[1])
        XCTAssertEqual(h.model.redoStack.map(\.kind), [.replace]); XCTAssertTrue(h.model.undoStack.isEmpty)
        XCTAssertEqual(h.model.editorMessage, .redoFailed)
        await assertFileExists(store, d.mediaRelativePath, true)
    }

    func testReplacePersistenceFailureRollsBackAndRemovesOnlyTheNewMedia() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let h = try await makeEditor(script: .fixtures([fixture]))
        await h.model.loadThumbnails(displayScale: 2)
        h.model.select(h.ids[1])
        let before = h.model.project
        let filesBefore = mediaFiles(before.id)
        h.repository.updateFails = true

        let result = await h.model.replaceSelectedClip()

        XCTAssertNil(result)
        XCTAssertEqual(h.model.project, before, "B exactly as before")
        XCTAssertEqual(h.model.selectedClipID, h.ids[1])
        XCTAssertTrue(h.model.isSelectedClipUnavailable)
        XCTAssertFalse(h.model.canUndo, "no history")
        XCTAssertEqual(h.model.editorMessage, .replaceFailed)
        XCTAssertEqual(ProjectEditorMessage.replaceFailed.title, "클립을 교체하지 못했어요")
        XCTAssertEqual(ProjectEditorMessage.replaceFailed.message, "다시 시도해주세요. 프로젝트는 그대로 있어요.")
        XCTAssertEqual(try h.repository.project(id: before.id), before)
        XCTAssertEqual(mediaFiles(before.id), filesBefore, "D's file removed, A and C kept")
        XCTAssertFalse(h.model.isAcquiringClips)
    }

    func testPickerCancelNonReadyStorageAndMultiSourceChangeNothing() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2, name: "replace-ready")
        let tooLong = try await TestMediaFixtures.shared.portrait(seconds: 7, name: "replace-too-long")
        let cases: [(String, FakeProjectMediaSelector.Script, ProjectStorageVerdict, ProjectEditorMessage?)] = [
            ("cancel", .cancel, .sufficient, nil),
            ("transfer failure", .fail, .sufficient, .replaceFailed),
            ("too long", .fixtures([tooLong]), .sufficient, .addRequiresImportPreparation(.tooLong)),
            ("storage", .fixtures([fixture]), .insufficient(requiredBytes: 1, usableBytes: 0), .addInsufficientStorage),
            ("two sources", .fixtures([fixture, tooLong]), .sufficient, .replaceFailed)
        ]
        for (label, script, storage, expected) in cases {
            let h = try await makeEditor(script: script, storage: storage)
            await h.model.loadThumbnails(displayScale: 2)
            h.model.select(h.ids[1])
            let before = h.model.project
            let filesBefore = mediaFiles(before.id)
            let result = await h.model.replaceSelectedClip()
            XCTAssertNil(result, label)
            XCTAssertEqual(h.model.project, before, "\(label): zero mutation")
            XCTAssertEqual(h.model.selectedClipID, h.ids[1], label)
            XCTAssertTrue(h.model.isSelectedClipUnavailable, label)
            XCTAssertEqual(h.model.totalDuration, .seconds(9), label)
            XCTAssertFalse(h.model.canUndo, "\(label): zero history")
            XCTAssertEqual(h.repository.updateCount, 0, "\(label): zero repository update")
            XCTAssertEqual(h.model.editorMessage, expected, label)
            XCTAssertEqual(mediaFiles(before.id), filesBefore, "\(label): zero committed replacement media")
            XCTAssertEqual(h.selector.selectionLimits, [1], label)
            XCTAssertTrue(h.model.canReplaceSelectedClip, "\(label): ready for the next attempt")
            let workspaces = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("ProjectWorkspace").path)) ?? []
            XCTAssertTrue(workspaces.isEmpty, "\(label): workspace discarded")
        }
        XCTAssertEqual(ProjectEditorMessage.addRequiresImportPreparation(.tooLong).title, "영상이 너무 길어요")
        XCTAssertEqual(ProjectEditorMessage.addRequiresImportPreparation(.tooLong).message, "5초 이하의 영상을 선택해주세요.")
    }

    func testReplaceIsRefusedForHealthySelectionNoSelectionOrWhileBlocked() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let h = try await makeEditor(script: .fixtures([fixture]))
        await h.model.loadThumbnails(displayScale: 2)
        h.model.select(h.ids[0])
        let healthy = await h.model.replaceSelectedClip()
        XCTAssertNil(healthy, "healthy clip")
        h.model.select(h.ids[1])
        h.model.beginReorder(clipID: h.ids[1])
        XCTAssertFalse(h.model.canReplaceSelectedClip)
        let lifted = await h.model.replaceSelectedClip()
        XCTAssertNil(lifted, "while a clip is lifted")
        h.model.cancelReorder()
        XCTAssertEqual(h.selector.selectionCount, 0, "picker never presented")
        for id in h.ids { XCTAssertTrue(h.model.deleteClip(id: id)) }
        XCTAssertNil(h.model.selectedClipID); XCTAssertFalse(h.model.canReplaceSelectedClip)
        let none = await h.model.replaceSelectedClip()
        XCTAssertNil(none, "no selection")
        let noAcquisition = ProjectEditorModel(project: h.model.project, repository: h.repository, thumbnails: FakeClipThumbnailProvider(), availability: CommittedMediaAvailabilityChecker(resolver: store))
        XCTAssertFalse(noAcquisition.canReplaceSelectedClip)
    }

    func testMutationsAreRefusedWhileReplaceIsInFlight() async throws {
        @MainActor final class ProbingSelector: ProjectMediaSelecting {
            var probe: (() -> Void)?
            private(set) var limits: [Int?] = []
            func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating) async -> ProjectMediaSelectionOutcome {
                await selectVideos(into: workspace, store: store, admission: admission, selectionLimit: nil)
            }
            func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating, selectionLimit: Int?) async -> ProjectMediaSelectionOutcome {
                limits.append(selectionLimit); probe?(); return .cancelled
            }
        }
        let project = try await makeProject()
        let repository = FailableProjectRepository()
        try repository.create(project)
        let selector = ProbingSelector()
        let acquisition = EditorClipAcquisition(mediaStore: store, mediaSelector: selector, storageGate: FakeProjectStorageGate(), appender: ProjectClipAppendCoordinator(mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: FakeProjectMediaInspector(.ready())), storage: FakeProjectStorageGate()))
        let model = ProjectEditorModel(project: project, repository: repository, thumbnails: FakeClipThumbnailProvider(), acquisition: acquisition, availability: CommittedMediaAvailabilityChecker(resolver: store))
        await model.loadThumbnails(displayScale: 2)
        model.select(project.clips[1].id)
        model.moveClipLater(id: project.clips[1].id)                                       // history for canUndo
        var observed: [Bool] = []
        var addAttempt: Task<Int, Never>?
        selector.probe = {
            observed = [model.isReplacingClip, model.isAcquiringClips, model.isAddingClips, model.canUndo, model.canRedo, model.canDeleteSelectedClip,
                        model.canAddClips, model.canReplaceSelectedClip, model.deleteSelectedClip(), model.undo(), model.beginReorder(clipID: project.clips[0].id)]
            addAttempt = Task { await model.addClips() }
        }
        let result = await model.replaceSelectedClip()
        XCTAssertNil(result)
        XCTAssertEqual(observed, [true, true, false, false, false, false, false, false, false, false, false], "nothing may race the Replace transaction")
        let added = await addAttempt?.value
        XCTAssertEqual(added, 0)
        XCTAssertEqual(selector.limits, [1], "a second picker (Add) was never presented")
        XCTAssertFalse(model.isAcquiringClips)
        XCTAssertTrue(model.canUndo); XCTAssertTrue(model.canReplaceSelectedClip)
    }

    // MARK: - History / lifetime (§42)

    func testReplaceThenReorderAndReplaceThenDeleteUndoRedoChronologically() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let h = try await makeEditor(script: .fixtures([fixture]))
        let d = try await replaceB(h)
        let (a, b, c) = (h.ids[0], h.ids[1], h.ids[2])

        XCTAssertTrue(h.model.beginReorder(clipID: d.id)); h.model.previewReorder(toIndex: 0); h.model.commitReorder()   // D A C
        XCTAssertEqual(h.model.orderedClips.map(\.id), [d.id, a, c])
        XCTAssertEqual(h.model.undoStack.map(\.kind), [.replace, .reorder])
        XCTAssertTrue(h.model.undo()); XCTAssertEqual(h.model.orderedClips.map(\.id), [a, d.id, c])
        XCTAssertTrue(h.model.undo()); XCTAssertEqual(h.model.orderedClips.map(\.id), [a, b, c])
        XCTAssertEqual(h.model.project.deletedClips.map(\.id), [d.id])
        XCTAssertTrue(h.model.redo()); XCTAssertEqual(h.model.orderedClips.map(\.id), [a, d.id, c])
        XCTAssertTrue(h.model.redo()); XCTAssertEqual(h.model.orderedClips.map(\.id), [d.id, a, c])
        XCTAssertEqual(h.model.project.deletedClips.map(\.id), [b])
        XCTAssertTrue(h.model.undo()); XCTAssertTrue(h.model.undo())                                                // A B C, clean stacks for part two
        XCTAssertTrue(h.model.redo())                                                                              // A D C

        XCTAssertTrue(h.model.deleteClip(id: a))                                                                   // D C
        XCTAssertEqual(h.model.orderedClips.map(\.id), [d.id, c])
        XCTAssertEqual(h.model.undoStack.map(\.kind), [.replace, .delete])
        XCTAssertTrue(h.model.undo()); XCTAssertEqual(h.model.orderedClips.map(\.id), [a, d.id, c])
        XCTAssertTrue(h.model.undo()); XCTAssertEqual(h.model.orderedClips.map(\.id), [a, b, c])
        XCTAssertTrue(h.model.redo()); XCTAssertEqual(h.model.orderedClips.map(\.id), [a, d.id, c])
        XCTAssertTrue(h.model.redo()); XCTAssertEqual(h.model.orderedClips.map(\.id), [d.id, c])
        XCTAssertEqual(Set(h.model.project.deletedClips.map(\.id)), [a, b])
        XCTAssertEqual(h.model.project.durableClips.count, 4)
        XCTAssertEqual(mediaFiles(h.model.project.id).count, 3, "A, C, D files all retained in-session")
    }

    func testNewEditAfterUndoReplaceClearsRedoAndKeepsDPendingUntilSessionEnd() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let h = try await makeEditor(script: .fixtures([fixture]))
        let d = try await replaceB(h)
        XCTAssertTrue(h.model.undo())
        XCTAssertTrue(h.model.canRedo)
        XCTAssertEqual(h.model.moveClipLater(id: h.ids[0]), 2)                                                     // B A C
        XCTAssertFalse(h.model.canRedo, "abandoned Replace future discarded")
        XCTAssertEqual(h.model.project.deletedClips.map(\.id), [d.id], "D stays durable pending in-session")
        await assertFileExists(store, d.mediaRelativePath, true, "no cleanup inside the session")
        XCTAssertEqual(h.model.availability(for: h.ids[1]), .unavailable(.mediaMissing))

        // Session end (Editor route removed): 12A removes D's file and finalizes D; B stays active + unavailable.
        let (cleanup, recovery, _) = makeCleanup(h)
        let report = await cleanup.reconcile(projectID: h.model.project.id)
        XCTAssertEqual(report.removedFiles, [d.id]); XCTAssertEqual(report.finalized, [d.id])
        await assertFileExists(store, d.mediaRelativePath, false, "no leak, no orphan")
        let stored = try XCTUnwrap(try h.repository.project(id: h.model.project.id))
        XCTAssertEqual(stored.clips.map(\.id), [h.ids[1], h.ids[0], h.ids[2]]); XCTAssertTrue(stored.deletedClips.isEmpty)
        let recovered = await recovery.recoverOrphans()
        XCTAssertEqual(recovered.orphanMediaRemoved, 0); XCTAssertEqual(recovered.preservedReferenced, 2)
        // Reopen: B still active and unavailable, history empty.
        let reopened = ProjectEditorModel(project: stored, repository: h.repository, thumbnails: FakeClipThumbnailProvider(), availability: CommittedMediaAvailabilityChecker(resolver: store))
        await reopened.loadThumbnails(displayScale: 2)
        XCTAssertEqual(reopened.availability(for: h.ids[1]), .unavailable(.mediaMissing))
        XCTAssertFalse(reopened.canUndo); XCTAssertFalse(reopened.canRedo)
    }

    func testFinalReplaceStateAtSessionEndFinalizesBMetadataOnlyAndDSurvives() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let h = try await makeEditor(script: .fixtures([fixture]))
        let d = try await replaceB(h)
        let b = h.ids[1]
        let (cleanup, recovery, _) = makeCleanup(h)
        let report = await cleanup.reconcile(projectID: h.model.project.id)
        XCTAssertEqual(report.alreadyAbsent, [b]); XCTAssertEqual(report.finalized, [b]); XCTAssertTrue(report.removedFiles.isEmpty)
        await assertFileExists(store, d.mediaRelativePath, true, "D's file survives")
        let stored = try XCTUnwrap(try h.repository.project(id: h.model.project.id))
        XCTAssertEqual(stored.clips.map(\.id), [h.ids[0], d.id, h.ids[2]]); XCTAssertTrue(stored.deletedClips.isEmpty)
        let recovered = await recovery.recoverOrphans()
        XCTAssertEqual(recovered.orphanMediaRemoved, 0)
        XCTAssertEqual(mediaFiles(stored.id).count, 3)
        // Reopen: D active, no resurrection of B, empty history.
        let reopened = ProjectEditorModel(project: stored, repository: h.repository, thumbnails: FakeClipThumbnailProvider(), availability: CommittedMediaAvailabilityChecker(resolver: store))
        await reopened.loadThumbnails(displayScale: 2)
        XCTAssertEqual(reopened.orderedClips.map(\.id), [h.ids[0], d.id, h.ids[2]])
        XCTAssertFalse(reopened.orderedClips.contains { $0.id == b })
        XCTAssertEqual(reopened.availability(for: d.id), .available)
        XCTAssertFalse(reopened.canUndo)
        // The second pass is idempotent.
        let again = await cleanup.reconcile(projectID: stored.id)
        XCTAssertEqual(again.pendingCount, 0)
    }

    func testCrashAfterDMaterializationBeforeCommitLeavesFileWithoutRowThatRecoveryRemoves() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let h = try await makeEditor()
        await h.model.loadThumbnails(displayScale: 2)
        let before = h.model.project
        // The STEP 12B crash window: D materialised under the Project, no row references it.
        let workspace = try await store.beginWorkspace()
        let sources = try await TestSupport.adoptedSources([fixture], into: workspace, store: store)
        let appender = ProjectClipAppendCoordinator(mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()), storage: FakeProjectStorageGate())
        guard case .ready(let prepared) = await appender.prepareClips(for: before, sources: sources), let d = prepared.first else { return XCTFail("fixture not ready") }
        await store.discard(workspace)
        XCTAssertEqual(mediaFiles(before.id).count, 3)
        XCTAssertEqual(try h.repository.project(id: before.id), before, "no row for D")

        let (_, recovery, _) = makeCleanup(h)
        let report = await recovery.recoverOrphans()
        XCTAssertEqual(report.orphanMediaRemoved, 1); XCTAssertEqual(report.preservedReferenced, 2)
        await assertFileExists(store, d.mediaRelativePath, false)
        XCTAssertEqual(try h.repository.project(id: before.id), before, "B still active + unavailable, A / C untouched")
        XCTAssertEqual(mediaFiles(before.id).count, 2)
    }
}
