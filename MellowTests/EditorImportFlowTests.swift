import Foundation
import SwiftData
import XCTest
@testable import Mellow

/// Phase 6 Editor Add / Replace (D7b, Editor decisions 1–3, 2026-10-06): fake selection of real fixture files → real
/// preflight → `ImportAttemptCoordinator` + `ImportRetryController` → the Editor's confirmed-state adoption. Isolated
/// SwiftData store and media root; controlled normalizer / capacity. Never a device store or private media.
@MainActor
final class EditorImportFlowTests: XCTestCase {
    private typealias NormalizerScript = ImportAttemptCoordinatorTests.NormalizerScript
    private typealias FakeNormalizer = ImportAttemptCoordinatorTests.FakeNormalizer
    private typealias CapacityScript = ImportAttemptCoordinatorTests.CapacityScript

    private var directory: URL!
    private var container: ModelContainer!
    private var swiftData: SwiftDataProjectRepository!
    private var repository: FailableProjectRepository!
    private var root: URL!
    private var store: ProjectMediaStore!
    private var gate: ProjectLifecycleOperationGate!
    private var normalizer: NormalizerScript!
    private var capacity: CapacityScript!
    private var activity: ImportOperationActivity!
    private var legacyGuard: ScriptedCapacityGate!
    private var routeLive = true

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "MellowEditorImport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = try MellowModelContainer.makePersistentContainer(storeURL: directory.appending(path: "metadata.store"))
        swiftData = SwiftDataProjectRepository(modelContext: container.mainContext)
        repository = FailableProjectRepository(inner: swiftData)
        root = TestSupport.temporaryRoot("editor-import")
        store = ProjectMediaStore(root: root)
        gate = ProjectLifecycleOperationGate()
        normalizer = NormalizerScript()
        capacity = CapacityScript()
        activity = ImportOperationActivity()
        legacyGuard = ScriptedCapacityGate(capacities: [0, 0, 0, 0])   // would refuse: proves the Phase 5 guard is unused
        routeLive = true
    }

    override func tearDown() {
        repository = nil
        swiftData = nil
        container = nil
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixtures

    private func fixture(_ name: String, seconds: Double, fps: Int32 = 30) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EditorImport-\(name)-\(UUID().uuidString)").appendingPathExtension("mov")
        try await FixtureVideoWriter.write(to: url, seconds: seconds, fps: fps)
        return url
    }

    /// A saved Project with `withFile` clips (real files) followed by `withoutFile` structurally unavailable clips.
    private func seed(withFile: Int = 2, withoutFile: Int = 0) throws -> VlogProject {
        let projectID = UUID(), date = Date(timeIntervalSince1970: 500)
        var clips: [VlogClip] = []
        for index in 0..<(withFile + withoutFile) {
            let clipID = UUID()
            let path = try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID)
            if index < withFile {
                let url = root.appendingPathComponent(path.value)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(repeating: 1, count: 100).write(to: url)
            }
            clips.append(try VlogClip(id: clipID, projectID: projectID, sourceKind: .imported, mediaRelativePath: path, createdAt: date,
                                      sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: index))
        }
        let project = try VlogProject(id: projectID, createdAt: date, updatedAt: date, orientation: .portrait9x16, clips: clips)
        try swiftData.create(project)
        return project
    }

    private func makeModel(_ project: VlogProject, fixtures: [URL], selector: (any ProjectMediaSelecting)? = nil,
                           routeProbe: ((UUID) -> () -> Bool)? = nil) -> ProjectEditorModel {
        let capacity = self.capacity!
        let coordinator = ImportAttemptCoordinator(repository: repository, mediaStore: store, normalizer: FakeNormalizer(script: normalizer),
                                                   lifecycle: gate, capacity: { await capacity.next() })
        let acquisition = EditorClipAcquisition(
            mediaStore: store, mediaSelector: selector ?? FakeProjectMediaSelector(script: .fixtures(fixtures)),
            storageGate: FakeProjectStorageGate(verdict: .sufficient),
            appender: ProjectClipAppendCoordinator(mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()), storage: legacyGuard),
            lifecycle: gate,
            importServices: ImportFlowServices(store: store, preflight: ImportSelectionPreflight(inspector: AVAssetImportSourceInspector()), attempts: coordinator),
            importActivity: activity,
            makeRouteProbe: routeProbe ?? { [unowned self] _ in { self.routeLive } })
        return ProjectEditorModel(project: project, repository: repository, thumbnails: FakeClipThumbnailProvider(), acquisition: acquisition,
                                  availability: CommittedMediaAvailabilityChecker(resolver: store), lifecycle: gate)
    }

    private func eventually(_ timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock(), deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await clock.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func seconds(_ time: MediaTime) -> Double { Double(time.value) / Double(time.timescale) }
    private func persisted(_ id: UUID) throws -> VlogProject? { try swiftData.project(id: id) }
    private func workspaceCount() -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("ProjectWorkspace").path)) ?? []).count
    }

    /// Exactly one history entry: Undo is available once and restores the base exactly.
    private func assertOneHistoryEntry(_ model: ProjectEditorModel, kind: EditorHistoryEntry.Kind, base: VlogProject,
                                       file: StaticString = #filePath, line: UInt = #line) async {
        XCTAssertEqual(model.undoTarget, kind, file: file, line: line)
        let undone = await model.undo()
        XCTAssertTrue(undone, file: file, line: line)
        XCTAssertEqual(model.project.clips.map(\.id), base.clips.map(\.id), file: file, line: line)
        XCTAssertFalse(model.canUndo, "exactly one entry", file: file, line: line)
    }

    // MARK: - Add

    func testAddAcceptsInclusiveBoundariesInAcceptedOrderWithOneHistoryEntry() async throws {
        let base = try seed()
        let model = makeModel(base, fixtures: [try await fixture("one", seconds: 1), try await fixture("five", seconds: 5)])
        let added = await model.addClips()
        XCTAssertEqual(added, 2)
        XCTAssertEqual(model.project.clips.count, 4)
        XCTAssertEqual(model.project.clips.dropFirst(2).map { seconds($0.trimDuration) }, [1, 5], "Accepted Set order")
        XCTAssertEqual(model.selectedClipID, model.project.clips[2].id, "selection = first new Clip")
        XCTAssertEqual(try persisted(base.id), model.project, "the confirmed state is what was saved")
        XCTAssertTrue(legacyGuard.checks.isEmpty, "the Phase 5 final guard is retired for Add")
        XCTAssertFalse(model.isNavigationLocked)
        XCTAssertEqual(workspaceCount(), 0)
        // Synchronous Editor mutations keep working after an import settled.
        XCTAssertTrue(model.beginReorder(clipID: model.project.clips[0].id))
        model.cancelReorder()
        await assertOneHistoryEntry(model, kind: .add, base: base)
    }

    func testAddFiltersPerItemAndShowsOneNoticeAfterSuccess() async throws {
        let base = try seed()
        let model = makeModel(base, fixtures: [try await fixture("short", seconds: 0.5), try await fixture("ready", seconds: 2)])
        let added = await model.addClips()
        XCTAssertEqual(added, 1)
        XCTAssertEqual(model.editorMessage, .selectionNotice(.shortItemsExcluded))
        XCTAssertEqual(model.project.clips.count, 3)
    }

    func testAddAllExcludedChangesNothing() async throws {
        let base = try seed()
        let model = makeModel(base, fixtures: [try await fixture("short", seconds: 0.5), try await fixture("long", seconds: 7)])
        _ = await model.addClips()
        XCTAssertEqual(model.editorMessage, .selectionNotice(.shortAndLongItemsExcluded))
        XCTAssertEqual(model.project, base)
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.isNavigationLocked)
    }

    func testMixedAddShowsSheetBlocksTheEditorAndKeepsTheConfirmedTimeline() async throws {
        let base = try seed()
        let model = makeModel(base, fixtures: [try await fixture("ready", seconds: 2), try await fixture("n1", seconds: 2, fps: 60),
                                               try await fixture("n2", seconds: 1.5, fps: 60)])
        await normalizer.script([.park])
        let run = Task { await model.addClips() }
        await normalizer.waitUntilParked()
        XCTAssertEqual(model.importPreparation?.total, 2)
        XCTAssertEqual(model.importPreparation?.positionLabel, "1/2")
        XCTAssertEqual(model.project, base, "the last confirmed timeline stays until completed")
        XCTAssertTrue(model.isNavigationLocked, "Back blocked")
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.beginReorder(clipID: base.clips[0].id), "drag blocked")
        model.select(base.clips[1].id)
        XCTAssertEqual(model.selectedClipID, base.clips.first?.id, "selection blocked")
        await normalizer.release()
        let added = await run.value
        XCTAssertEqual(added, 3)
        XCTAssertEqual(model.project.clips.dropFirst(2).map { seconds($0.trimDuration) }, [2, 2, 1.5])
        XCTAssertNil(model.importPreparation)
    }

    // MARK: - Replace

    func testNormalizedReplaceKeepsTheSlotWithOneHistoryEntry() async throws {
        let base = try seed(withFile: 1, withoutFile: 2)
        let model = makeModel(base, fixtures: [try await fixture("n1", seconds: 3, fps: 60)])
        model.select(base.clips[1].id)
        await model.refreshAvailability()
        XCTAssertTrue(model.canReplaceSelectedClip)
        let replacedID = await model.replaceSelectedClip()
        let newID = try XCTUnwrap(replacedID)
        XCTAssertEqual(model.project.clips.map(\.id), [base.clips[0].id, newID, base.clips[2].id], "same logical index")
        XCTAssertEqual(model.project.deletedClips.map(\.id), [base.clips[1].id], "the old Clip is durable pending")
        XCTAssertEqual(model.selectedClipID, newID)
        let replacement = try XCTUnwrap(model.project.clips.first { $0.id == newID })
        XCTAssertEqual(seconds(replacement.trimDuration), 3, accuracy: 0.05, "trim = accepted source duration (ADR-040 §6 Revision)")
        XCTAssertEqual(try persisted(base.id), model.project)
        XCTAssertTrue(legacyGuard.checks.isEmpty, "the Phase 5 final guard is retired for Replace")
        await assertOneHistoryEntry(model, kind: .replace, base: base)
    }

    func testReplaceSingleCandidateRejectionKeepsTheClip() async throws {
        let base = try seed(withFile: 1, withoutFile: 1)
        let model = makeModel(base, fixtures: [try await fixture("short", seconds: 0.5)])
        model.select(base.clips[1].id)
        await model.refreshAvailability()
        let replaced = await model.replaceSelectedClip()
        XCTAssertNil(replaced)
        XCTAssertEqual(model.editorMessage, .selectionNotice(.candidateBelowMinimum))
        XCTAssertEqual(model.project, base)
    }

    // MARK: - Save outcomes, Retry, cancellation

    func testSaveOutcomes() async throws {
        // Thrown save confirmed by evidence → completed (one history entry).
        let completedBase = try seed()
        let completed = makeModel(completedBase, fixtures: [try await fixture("a", seconds: 2)])
        repository.updateThrowsAfterCommit = true
        let added = await completed.addClips()
        XCTAssertEqual(added, 1)
        XCTAssertNil(completed.reconciliation)
        repository.updateThrowsAfterCommit = false

        // Save returned, verification unavailable → U1 lock, media preserved.
        let unverifiedBase = try seed()
        let unverified = makeModel(unverifiedBase, fixtures: [try await fixture("b", seconds: 2)])
        repository.stateObservationOverride = { expectation, observed in
            PersistedStateObservation(projects: Dictionary(uniqueKeysWithValues: expectation.intended.keys.map { ($0, .unreadable) }),
                                      createdIdentityHolders: observed.createdIdentityHolders)
        }
        _ = await unverified.addClips()
        XCTAssertEqual(unverified.reconciliation, .saveUnverified)
        XCTAssertEqual(try persisted(unverifiedBase.id)?.clips.count, 3, "media and the landed save are preserved")
        XCTAssertEqual(unverified.project, unverifiedBase, "never shown as saved")
        XCTAssertNil(unverified.importRetryPrompt, "never retried")

        // Thrown save, evidence missing → U2 lock.
        let indeterminateBase = try seed()
        let indeterminate = makeModel(indeterminateBase, fixtures: [try await fixture("c", seconds: 2)])
        repository.updateThrowsAfterCommit = true
        repository.stateObservationOverride = { _, observed in PersistedStateObservation(projects: observed.projects, createdIdentityHolders: nil) }
        _ = await indeterminate.addClips()
        XCTAssertEqual(indeterminate.reconciliation, .saveIndeterminate)
    }

    func testPriorConfirmedAndPreparationFailureRetryThenApplyOnce() async throws {
        let base = try seed()
        let model = makeModel(base, fixtures: [try await fixture("n1", seconds: 2, fps: 60)])
        repository.updateFails = true
        _ = await model.addClips()
        XCTAssertEqual(model.importRetryPrompt, .preparationFailed, "priorConfirmed → R4 §3 Retry (D7a)")
        XCTAssertTrue(model.isNavigationLocked, "the Editor stays blocked while waiting")
        XCTAssertFalse(model.canAddClips)
        repository.updateFails = false
        model.retryImport()
        let applied = await eventually { model.project.clips.count == 3 }
        XCTAssertTrue(applied)
        XCTAssertFalse(model.isNavigationLocked)
        await assertOneHistoryEntry(model, kind: .add, base: base)
    }

    func testCancelFromTheSheetLeavesTheProjectUnchanged() async throws {
        let base = try seed()
        let model = makeModel(base, fixtures: [try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.park])
        let run = Task { await model.addClips() }
        await normalizer.waitUntilParked()
        model.cancelImport()
        await normalizer.release()
        _ = await run.value
        XCTAssertEqual(model.project, base)
        XCTAssertNil(model.editorMessage)
        XCTAssertFalse(model.isNavigationLocked)
        XCTAssertEqual(workspaceCount(), 0)
        XCTAssertEqual(try persisted(base.id), base)
    }

    func testRetryAdmissionTargets() async throws {
        // Changed → D8.5c recheck, Retry ends.
        let changedBase = try seed()
        let changed = makeModel(changedBase, fixtures: [try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.fail])
        _ = await changed.addClips()
        var edited = changedBase
        edited.updatedAt = Date(timeIntervalSince1970: 900)
        try swiftData.update(edited)
        changed.retryImport()
        let rechecked = await eventually { changed.reconciliation == .recheckRequired }
        XCTAssertTrue(rechecked)
        XCTAssertFalse(changed.isNavigationLocked)

        // Missing → D8.5c project missing.
        let missingBase = try seed()
        let missing = makeModel(missingBase, fixtures: [try await fixture("n2", seconds: 2, fps: 60)])
        await normalizer.script([.fail])
        _ = await missing.addClips()
        try swiftData.deleteProject(id: missingBase.id)
        missing.retryImport()
        let gone = await eventually { missing.reconciliation == .projectMissing }
        XCTAssertTrue(gone)

        // Unreadable → target-unavailable Retry wait, still blocked.
        let unreadableBase = try seed()
        let unreadable = makeModel(unreadableBase, fixtures: [try await fixture("n3", seconds: 2, fps: 60)])
        await normalizer.script([.fail])
        _ = await unreadable.addClips()
        repository.priorObservationOverride = { _ in .unreadable }
        unreadable.retryImport()
        let waiting = await eventually { unreadable.importRetryPrompt == .targetUnavailable }
        XCTAssertTrue(waiting)
        XCTAssertNil(unreadable.reconciliation)
        XCTAssertTrue(unreadable.isNavigationLocked)
    }

    // MARK: - Route removal and Editor-exit cleanup ordering (decision 3)

    func testRouteRemovalLetsTheImportFinishBeforeEditorExitCleanup() async throws {
        let base = try seed()
        let model = makeModel(base, fixtures: [try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.park])
        let run = Task { await model.addClips() }
        await normalizer.waitUntilParked()
        XCTAssertTrue(activity.isActive(projectID: base.id))
        var cleanupRan = false
        routeLive = false
        activity.routeRemoved(projectID: base.id)                       // a running attempt is not cancelled
        let cleanup = Task { @MainActor in
            await self.activity.waitUntilIdle(projectID: base.id)
            // What the gated Editor-exit cleanup would see at this point: outcome processing and attempt cleanup done.
            XCTAssertFalse(self.gate.isHeld, "the wait never held the gate")
            XCTAssertEqual(try self.persisted(base.id)?.clips.count, 3, "the completed save precedes cleanup")
            XCTAssertEqual(self.workspaceCount(), 0, "attempt cleanup precedes Editor-exit cleanup")
            XCTAssertFalse(model.isNavigationLocked)
            XCTAssertEqual(model.project.clips.count, 3, "the confirmed state was adopted first")
            cleanupRan = true
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(cleanupRan, "cleanup waits for the import")
        await normalizer.release()
        _ = await run.value
        try await cleanup.value
        XCTAssertTrue(cleanupRan)
        XCTAssertNil(model.editorMessage, "no late notice")
    }

    func testRouteRemovedWhileWaitingEndsTheWaitAndUnblocks() async throws {
        let base = try seed()
        let model = makeModel(base, fixtures: [try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.fail])
        _ = await model.addClips()
        XCTAssertEqual(model.importRetryPrompt, .preparationFailed)
        routeLive = false
        activity.routeRemoved(projectID: base.id)
        activity.routeRemoved(projectID: base.id)
        await activity.waitUntilIdle(projectID: base.id)
        XCTAssertFalse(model.isNavigationLocked)
        XCTAssertNil(model.importRetryPrompt)
        XCTAssertEqual(workspaceCount(), 0)
        XCTAssertEqual(try persisted(base.id), base)
    }

    /// The route leaves while the attempt RUNS (an earlier removal starts no attempt at all): the attempt continues
    /// and its unresolved / uncertain outcome keeps evidence and media, releases the block, and shows no late UI.
    func testUnresolvedAndUncertainOutcomesAfterRouteRemovalKeepEvidence() async throws {
        let base = try seed()
        let unresolved = makeModel(base, fixtures: [try await fixture("n1", seconds: 2, fps: 60), try await fixture("n2", seconds: 2, fps: 60)])
        await normalizer.script([.park, .cleanupFailure(cancelled: false)])
        let first = Task { await unresolved.addClips() }
        await normalizer.waitUntilParked()
        routeLive = false
        activity.routeRemoved(projectID: base.id)
        await normalizer.release()
        _ = await first.value
        await activity.waitUntilIdle(projectID: base.id)
        XCTAssertFalse(unresolved.isNavigationLocked, "block released")
        XCTAssertNil(unresolved.editorMessage, "no late U3")
        XCTAssertEqual(workspaceCount(), 1, "retained evidence kept")

        routeLive = true
        let uncertainBase = try seed()
        let uncertain = makeModel(uncertainBase, fixtures: [try await fixture("n3", seconds: 2, fps: 60)])
        repository.stateObservationOverride = { expectation, observed in
            PersistedStateObservation(projects: Dictionary(uniqueKeysWithValues: expectation.intended.keys.map { ($0, .unreadable) }),
                                      createdIdentityHolders: observed.createdIdentityHolders)
        }
        await normalizer.script([.park])
        let second = Task { await uncertain.addClips() }
        await normalizer.waitUntilParked()
        routeLive = false
        activity.routeRemoved(projectID: uncertainBase.id)
        await normalizer.release()
        _ = await second.value
        await activity.waitUntilIdle(projectID: uncertainBase.id)
        XCTAssertFalse(uncertain.isNavigationLocked)
        XCTAssertNil(uncertain.reconciliation, "no late lock on a removed route")
        XCTAssertEqual(try persisted(uncertainBase.id)?.clips.count, 3, "nothing rolled back after an uncertain save")
    }

    // MARK: - Review rechecks (2026-10-06)

    func testLatePickerResultOnARemovedRouteStartsNoOperation() async throws {
        let base = try seed()
        // A real router: the route leaves while the selection transfers, then the selection still delivers a READY
        // source. A probe captured after the picker would see the already-removed path as "live".
        let router = AppRouter()
        router.path = [.projectsEntry, .projectEditor(base.id)]
        router.onProjectEditorRouteRemoved = { [activity] in activity!.routeRemoved(projectID: $0) }
        let removing = RouteRemovingSelector(inner: FakeProjectMediaSelector(script: .fixtures([try await fixture("ready", seconds: 2)]))) {
            router.path = [.projectsEntry]
        }
        let model = makeModel(base, fixtures: [], selector: removing, routeProbe: { router.routeProbe(for: .projectEditor($0)) })
        let added = await model.addClips()
        await activity.waitUntilIdle(projectID: base.id)
        XCTAssertEqual(added, 0)
        XCTAssertEqual(try persisted(base.id), base, "no attempt started on the removed route")
        XCTAssertEqual(model.project, base)
        XCTAssertEqual(workspaceCount(), 0, "the transferred copies went with the workspace")
        XCTAssertNil(model.importRetryPrompt)
        XCTAssertNil(model.editorMessage)
        XCTAssertFalse(activity.isActive(projectID: base.id))
        XCTAssertFalse(model.isNavigationLocked)
        XCTAssertFalse(model.canUndo)
    }

    func testFailureTakesPrecedenceOverTheExclusionNotice() async throws {
        let base = try seed()
        let model = makeModel(base, fixtures: [try await fixture("short", seconds: 0.5), try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.fail])
        _ = await model.addClips()
        XCTAssertEqual(model.importRetryPrompt, .preparationFailed)
        XCTAssertNil(model.editorMessage, "no notice before completion")
        model.cancelImport()
        let released = await eventually { !model.isNavigationLocked }
        XCTAssertTrue(released)
        XCTAssertNil(model.editorMessage, "a cancelled Add never shows the exclusion notice")
        XCTAssertEqual(model.project, base)
    }

    func testReplaceCompletedThroughRetryAppliesOnceAndAnnounces() async throws {
        let base = try seed(withFile: 1, withoutFile: 2)
        let model = makeModel(base, fixtures: [try await fixture("n1", seconds: 3, fps: 60)])
        model.select(base.clips[1].id)
        await model.refreshAvailability()
        await normalizer.script([.fail])
        let first = await model.replaceSelectedClip()
        XCTAssertNil(first)
        XCTAssertEqual(model.importRetryPrompt, .preparationFailed)
        XCTAssertEqual(model.project, base, "the last confirmed timeline stays while waiting")
        model.retryImport()
        let applied = await eventually { model.project.clips.count == 3 && model.project.deletedClips.count == 1 }
        XCTAssertTrue(applied)
        let newID = try XCTUnwrap(model.selectedClipID)
        XCTAssertEqual(model.project.clips.map(\.id), [base.clips[0].id, newID, base.clips[2].id])
        XCTAssertEqual(model.project.deletedClips.map(\.id), [base.clips[1].id])
        XCTAssertEqual(model.completedRetryImport?.replaced, true)
        await assertOneHistoryEntry(model, kind: .replace, base: base)
    }

    // MARK: - Preparation visibility on Retry (model state only; does not show SwiftUI rendered the overlay)

    /// Editor Add: the first attempt reaches item 2 of 2 and fails; `다시 시도` clears the prompt and, while the Retry
    /// attempt is pending, `importPreparation` is a NEW progress (nothing completed, back at `1/2`). It clears once the
    /// Retry completes, and the result is applied exactly once.
    func testAddRetryShowsFreshPreparationWhilePendingThenAppliesOnce() async throws {
        let base = try seed()
        let model = makeModel(base, fixtures: [try await fixture("n1", seconds: 2, fps: 60), try await fixture("n2", seconds: 1.5, fps: 60)])
        await normalizer.script([.succeed(outputDuration: nil), .fail])
        _ = await model.addClips()
        XCTAssertEqual(model.importRetryPrompt, .preparationFailed)
        XCTAssertNil(model.importPreparation, "no sheet while the Retry prompt waits")
        XCTAssertEqual(model.project, base)

        await normalizer.script([.park])
        model.retryImport()
        XCTAssertNil(model.importRetryPrompt, "the failure prompt is cleared on 다시 시도")
        await normalizer.waitUntilParked()
        XCTAssertNil(model.importRetryPrompt)
        let pending = try XCTUnwrap(model.importPreparation, "the sheet's state is set while the Retry attempt is pending")
        XCTAssertEqual(pending.total, 2)
        XCTAssertEqual(pending.completed.count, 0, "progress resets for the Retry attempt")
        XCTAssertEqual(pending.positionLabel, "1/2")
        XCTAssertEqual(model.project, base, "the confirmed timeline stays while the Retry is pending")
        XCTAssertTrue(model.isNavigationLocked)

        await normalizer.release()
        let applied = await eventually { model.project.clips.count == base.clips.count + 2 }
        XCTAssertTrue(applied)
        XCTAssertNil(model.importPreparation, "the sheet's state clears after the Retry completes")
        XCTAssertNil(model.importRetryPrompt)
        XCTAssertFalse(model.isNavigationLocked)
        XCTAssertEqual(model.project.clips.dropFirst(base.clips.count).map { seconds($0.trimDuration) }, [2, 1.5])
        XCTAssertEqual(try persisted(base.id), model.project)
        XCTAssertEqual(model.completedRetryImport?.replaced, false)
        XCTAssertEqual(workspaceCount(), 0)
        await assertOneHistoryEntry(model, kind: .add, base: base)
    }

    /// Editor Replace: the first attempt fails; `다시 시도` clears the prompt and, while the Retry attempt is pending,
    /// `importPreparation` is a new single-item progress with the slot still the confirmed one. It clears once the
    /// Retry completes, and the replacement is applied exactly once.
    func testReplaceRetryShowsFreshPreparationWhilePendingThenAppliesOnce() async throws {
        let base = try seed(withFile: 1, withoutFile: 2)
        let model = makeModel(base, fixtures: [try await fixture("n1", seconds: 3, fps: 60)])
        model.select(base.clips[1].id)
        await model.refreshAvailability()
        await normalizer.script([.fail])
        let first = await model.replaceSelectedClip()
        XCTAssertNil(first)
        XCTAssertEqual(model.importRetryPrompt, .preparationFailed)
        XCTAssertNil(model.importPreparation, "no sheet while the Retry prompt waits")

        await normalizer.script([.park])
        model.retryImport()
        XCTAssertNil(model.importRetryPrompt, "the failure prompt is cleared on 다시 시도")
        await normalizer.waitUntilParked()
        XCTAssertNil(model.importRetryPrompt)
        let pending = try XCTUnwrap(model.importPreparation, "the sheet's state is set while the Retry attempt is pending")
        XCTAssertEqual(pending.total, 1)
        XCTAssertEqual(pending.completed.count, 0, "a fresh progress for the Retry attempt")
        XCTAssertNil(pending.positionLabel, "no N/M for a single item")
        XCTAssertEqual(model.project, base, "the slot stays the confirmed (unavailable) clip while pending")
        XCTAssertTrue(model.isNavigationLocked)

        await normalizer.release()
        let applied = await eventually { model.project.clips.count == 3 && model.project.deletedClips.count == 1 }
        XCTAssertTrue(applied)
        XCTAssertNil(model.importPreparation, "the sheet's state clears after the Retry completes")
        XCTAssertNil(model.importRetryPrompt)
        XCTAssertFalse(model.isNavigationLocked)
        let newID = try XCTUnwrap(model.selectedClipID)
        XCTAssertEqual(model.project.clips.map(\.id), [base.clips[0].id, newID, base.clips[2].id], "replaced once, same slot")
        XCTAssertEqual(model.project.deletedClips.map(\.id), [base.clips[1].id])
        XCTAssertEqual(try persisted(base.id), model.project)
        XCTAssertEqual(model.completedRetryImport?.replaced, true)
        XCTAssertEqual(workspaceCount(), 0)
        await assertOneHistoryEntry(model, kind: .replace, base: base)
    }

    func testActivityTracksEachOperationSeparately() async throws {
        let projectID = UUID()
        let first = activity.begin(projectID: projectID, presenter: ImportOperationPresenter())
        let second = activity.begin(projectID: projectID, presenter: ImportOperationPresenter())
        var resumed = false
        let waiter = Task { @MainActor in
            await self.activity.waitUntilIdle(projectID: projectID)
            resumed = true
        }
        activity.end(first)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(resumed, "another operation for the same Project is still active")
        XCTAssertTrue(activity.isActive(projectID: projectID))
        activity.end(second)
        await waiter.value
        XCTAssertTrue(resumed)
    }

    func testEditorRouteIdentityAndInstanceRemoval() {
        let router = AppRouter()
        let id = UUID()
        var exits: [UUID] = [], instances: [UUID] = []
        router.onProjectEditorRouteRemoved = { exits.append($0) }
        router.onProjectEditorRouteInstanceRemoved = { instances.append($0) }
        router.path = [.projectsEntry, .projectEditor(id)]
        let probe = router.routeProbe(for: .projectEditor(id))
        XCTAssertTrue(probe())
        router.path.append(.projectEditor(UUID()))
        XCTAssertTrue(probe(), "another route does not change this route's identity")
        router.path = [.projectsEntry, .projectEditor(id), .projectEditor(id)]
        XCTAssertFalse(probe(), "a changed count is a new identity")
        let second = router.routeProbe(for: .projectEditor(id))
        router.path = [.projectsEntry, .projectEditor(id)]
        XCTAssertFalse(second())
        XCTAssertEqual(instances, [id], "an instance left; the Editor did not exit")
        XCTAssertTrue(exits.allSatisfy { $0 != id })
        router.path = [.projectsEntry]
        XCTAssertEqual(exits.last, id)
    }

    func testRouteRemovedWhileThePickerIsUpCancelsTheSessionAndReleases() async throws {
        let base = try seed()
        let router = AppRouter()
        router.path = [.projectsEntry, .projectEditor(base.id)]
        router.onProjectEditorRouteRemoved = { [activity] in activity!.routeRemoved(projectID: $0) }
        let parking = ParkingSelector()
        let model = makeModel(base, fixtures: [], selector: parking, routeProbe: { router.routeProbe(for: .projectEditor($0)) })
        let run = Task { await model.addClips() }
        let parked = await eventually { parking.isParked }
        XCTAssertTrue(parked)
        XCTAssertTrue(activity.isActive(projectID: base.id), "the operation is visible from the picker on")
        router.path = [.projectsEntry]                     // the picker's host view is gone; no dismissal arrives
        await activity.waitUntilIdle(projectID: base.id)
        let added = await run.value
        XCTAssertEqual(added, 0)
        XCTAssertNil(model.editorMessage)
        XCTAssertFalse(model.isNavigationLocked)
        XCTAssertEqual(workspaceCount(), 0)
    }
}

/// Removes the route while the selection runs, then delegates.
@MainActor
private final class RouteRemovingSelector: ProjectMediaSelecting {
    let inner: FakeProjectMediaSelector
    let removeRoute: () -> Void
    init(inner: FakeProjectMediaSelector, removeRoute: @escaping () -> Void) { self.inner = inner; self.removeRoute = removeRoute }
    func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating) async -> ProjectMediaSelectionOutcome {
        removeRoute()
        return await inner.selectVideos(into: workspace, store: store, admission: admission)
    }
}

/// A picker session that only resolves through `cancelPendingSelection()` (its host never reports dismissal).
@MainActor
private final class ParkingSelector: ProjectMediaSelecting {
    private var continuation: CheckedContinuation<ProjectMediaSelectionOutcome, Never>?
    var isParked: Bool { continuation != nil }
    func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating) async -> ProjectMediaSelectionOutcome {
        await withCheckedContinuation { continuation = $0 }
    }
    func cancelPendingSelection() {
        continuation?.resume(returning: .cancelled)
        continuation = nil
    }
}
