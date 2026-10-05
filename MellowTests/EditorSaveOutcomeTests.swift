import Foundation
import SwiftData
import XCTest
@testable import Mellow

/// Editor save-outcome integration (ADR-050 050-D D8.0 / D8.5a P1 · P2 · P4 · P6 · P7, OD-10, and the owner's
/// Editor decisions of 2026-10-05): every Editor mutation commits inside the shared lifecycle gate through
/// one inner commit — fresh prior read compared with the Editor base, update expectation, save, fresh
/// observation, classification — and publishes nothing before `completed`.
///
/// Isolated temporary SwiftData store and media root. "Throws after commit", injected observation faults
/// (`debugObservationFault`) and observation rewrites are test seams that model a save or read whose result
/// the caller cannot see; they do not prove any specific SwiftData failure mode.
@MainActor
final class EditorSaveOutcomeTests: XCTestCase {
    private var directory: URL!
    private var container: ModelContainer!
    private var swiftData: SwiftDataProjectRepository!
    private var repository: FailableProjectRepository!
    private var root: URL!
    private var store: ProjectMediaStore!
    private var gate: ProjectLifecycleOperationGate!
    private var holders: [GateHolder] = []

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "MellowEditorOutcome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = try MellowModelContainer.makePersistentContainer(storeURL: directory.appending(path: "metadata.store"))
        swiftData = SwiftDataProjectRepository(modelContext: container.mainContext)
        repository = FailableProjectRepository(inner: swiftData)
        root = TestSupport.temporaryRoot("editor-outcome")
        store = ProjectMediaStore(root: root)
        gate = ProjectLifecycleOperationGate()
    }

    override func tearDown() async throws {
        // Never leave a test-held gate behind (a failed bounded wait must not hang teardown).
        for holder in holders { holder.releaseWithoutWaiting() }
        holders = []
        repository = nil
        swiftData = nil
        container = nil
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    /// A saved Project with `count` active Clips, each with a real Project-owned file.
    private func makeProject(clips count: Int = 3) throws -> VlogProject {
        let id = UUID()
        var clips: [VlogClip] = []
        for index in 0..<count {
            let clipID = UUID()
            let path = try ProjectMediaStore.committedMediaPath(projectID: id, clipID: clipID)
            let url = root.appendingPathComponent(path.value)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: 128).write(to: url)
            clips.append(try VlogClip(id: clipID, projectID: id, sourceKind: .recorded, mediaRelativePath: path,
                                      sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: index))
        }
        let project = try VlogProject(id: id, orientation: .portrait9x16, clips: clips)
        try swiftData.create(project)
        return project
    }

    private func makeModel(_ project: VlogProject, selector: FakeProjectMediaSelector? = nil) -> ProjectEditorModel {
        let selector = selector ?? FakeProjectMediaSelector(script: .cancel)
        let appender = ProjectClipAppendCoordinator(mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: FakeProjectMediaInspector(.ready())), storage: FakeProjectStorageGate())
        let acquisition = EditorClipAcquisition(mediaStore: store, mediaSelector: selector, storageGate: FakeProjectStorageGate(), appender: appender, lifecycle: gate)
        return ProjectEditorModel(project: project, repository: repository, thumbnails: FakeClipThumbnailProvider(),
                                  acquisition: acquisition, availability: CommittedMediaAvailabilityChecker(resolver: store), lifecycle: gate)
    }

    private func mediaFiles(_ projectID: UUID) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects/\(projectID.uuidString)/Media").path)) ?? []).sorted()
    }

    private func stored(_ id: UUID) -> VlogProject? {
        if case .present(let project) = swiftData.observePersistedProject(id: id) { return project }
        return nil
    }

    /// Every observation fetch fails from the save attempt on (the in-gate prior read stays real).
    private func failObservationsAtSave() {
        let swiftData = swiftData!
        repository.onUpdate = { swiftData.debugObservationFault = { _ in true } }
    }

    private func holdGate() async -> GateHolder {
        let holder = GateHolder()
        holders.append(holder)
        holder.hold(gate)
        _ = await bounded("test holds the gate") { while !holder.isHolding { try? await Task.sleep(for: .milliseconds(2)) } }
        return holder
    }

    /// Awaits `operation` for at most `seconds`; a timeout fails the test instead of hanging it.
    private func bounded<T>(_ label: String, seconds: Double = 20, _ operation: @escaping @MainActor () async -> T) async -> T? {
        let flag = DoneFlag()
        let task = Task { @MainActor () -> T in
            let value = await operation()
            flag.done = true
            return value
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !flag.done, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        guard flag.done else {
            XCTFail("\(label): timed out (possible nested gate acquisition or a gate never released)")
            return nil
        }
        return await task.value
    }

    // MARK: Operations under test

    private enum Op: CaseIterable { case reorder, delete, undo, redo }

    /// An Editor whose history makes `op` possible (Undo needs one edit, Redo one undone edit).
    private func editor(for op: Op) async throws -> (ProjectEditorModel, VlogProject) {
        let project = try makeProject()
        let model = makeModel(project)
        switch op {
        case .reorder, .delete: break
        case .undo:
            await XCTAssertTrueAsync(await model.deleteClip(id: project.clips[1].id))
        case .redo:
            await XCTAssertTrueAsync(await model.deleteClip(id: project.clips[1].id))
            await XCTAssertTrueAsync(await model.undo())
        }
        return (model, project)
    }

    private func perform(_ op: Op, on model: ProjectEditorModel) async -> Bool {
        switch op {
        case .reorder: return await model.moveClipLater(id: model.project.clips[0].id) != nil
        case .delete: return await model.deleteClip(id: model.project.clips[0].id)
        case .undo: return await model.undo()
        case .redo: return await model.redo()
        }
    }

    private struct HistorySnapshot: Equatable {
        let undo: [EditorHistoryEntry]
        let redo: [EditorHistoryEntry]
        @MainActor init(_ model: ProjectEditorModel) { undo = model.undoStack; redo = model.redoStack }
    }

    /// The one history transition a `completed` `op` must apply.
    private func assertTransition(_ op: Op, from before: HistorySnapshot, to model: ProjectEditorModel, file: StaticString = #filePath, line: UInt = #line) {
        switch op {
        case .reorder, .delete:
            XCTAssertEqual(model.undoStack.count, before.undo.count + 1, "\(op): one entry pushed", file: file, line: line)
            XCTAssertEqual(Array(model.undoStack.dropLast()), before.undo, file: file, line: line)
            XCTAssertTrue(model.redoStack.isEmpty, "\(op): Redo branch abandoned", file: file, line: line)
        case .undo:
            XCTAssertEqual(model.undoStack, Array(before.undo.dropLast()), file: file, line: line)
            XCTAssertEqual(model.redoStack, before.redo + [before.undo.last!], "\(op): exactly one entry moved", file: file, line: line)
        case .redo:
            XCTAssertEqual(model.redoStack, Array(before.redo.dropLast()), file: file, line: line)
            XCTAssertEqual(model.undoStack, before.undo + [before.redo.last!], "\(op): exactly one entry moved", file: file, line: line)
        }
    }

    // MARK: Classifier outcomes for Reorder / Delete / Undo / Redo

    func testCompletedAdoptsTheIntendedStateWithOneHistoryTransition() async throws {
        for op in Op.allCases {
            let (model, _) = try await editor(for: op)
            let before = HistorySnapshot(model), updates = repository.updateCount
            await XCTAssertTrueAsync(await perform(op, on: model), "\(op)")
            XCTAssertEqual(repository.updateCount, updates + 1, "\(op): one save")
            XCTAssertEqual(model.project, stored(model.project.id), "\(op): the confirmed intended state")
            assertTransition(op, from: before, to: model)
            XCTAssertNil(model.editorMessage); XCTAssertNil(model.reconciliation)
            XCTAssertFalse(model.isCommittingMutation); XCTAssertFalse(model.isNavigationLocked)
        }
    }

    func testSaveThatLandsThenThrowsIsCompletedWithExactlyOneTransition() async throws {
        for op in Op.allCases {
            let (model, _) = try await editor(for: op)
            let before = HistorySnapshot(model)
            repository.updateThrowsAfterCommit = true
            await XCTAssertTrueAsync(await perform(op, on: model), "\(op): P4")
            repository.updateThrowsAfterCommit = false
            XCTAssertEqual(model.project, stored(model.project.id))
            assertTransition(op, from: before, to: model)
            XCTAssertNil(model.editorMessage, "\(op): logged only, no failure alert")
            XCTAssertNil(model.reconciliation)
        }
    }

    func testPriorConfirmedKeepsStateAndHistoryWithAcknowledgementCopy() async throws {
        for op in Op.allCases {
            let (model, _) = try await editor(for: op)
            let state = model.project, selection = model.selectedClipID, history = HistorySnapshot(model)
            repository.updateFails = true
            await XCTAssertFalseAsync(await perform(op, on: model), "\(op)")
            repository.updateFails = false
            XCTAssertEqual(model.project, state, "\(op): confirmed prior state kept")
            XCTAssertEqual(model.selectedClipID, selection)
            XCTAssertEqual(HistorySnapshot(model), history, "\(op): history unchanged")
            XCTAssertEqual(model.editorMessage, .changesNotSaved)
            XCTAssertEqual(model.editorMessage?.title, "변경사항을 저장하지 못했어요")
            XCTAssertEqual(model.editorMessage?.message, "프로젝트에 변경사항이 저장되지 않았어요.")
            XCTAssertNil(model.reconciliation, "\(op): not a lock")
            XCTAssertEqual(stored(state.id), state)
        }
    }

    func testSuccessfulSaveWithUnavailableVerificationLocksAndPreservesMedia() async throws {
        for op in Op.allCases {
            let (model, project) = try await editor(for: op)
            let state = model.project, history = HistorySnapshot(model)
            failObservationsAtSave()
            await XCTAssertFalseAsync(await perform(op, on: model), "\(op)")
            repository.onUpdate = nil; swiftData.debugObservationFault = nil
            XCTAssertEqual(model.reconciliation, .saveUnverified, "\(op): D8.0 committedUnverified, not indeterminate")
            XCTAssertEqual(model.reconciliation?.title, "저장 확인이 필요해요")
            XCTAssertEqual(model.project, state, "\(op): the unverified state is not presented as saved")
            XCTAssertEqual(HistorySnapshot(model), history)
            XCTAssertEqual(mediaFiles(project.id).count, project.clips.count, "\(op): every file preserved")
        }
    }

    func testSuccessfulSaveWithContradictoryVerificationLocks() async throws {
        for op in Op.allCases {
            let (model, project) = try await editor(for: op)
            let prior = model.project, history = HistorySnapshot(model)
            // The row reads back in its PRIOR state although the save returned.
            repository.stateObservationOverride = { _, observed in
                var projects = observed.projects
                projects[prior.id] = .present(prior)
                return PersistedStateObservation(projects: projects, createdIdentityHolders: observed.createdIdentityHolders)
            }
            await XCTAssertFalseAsync(await perform(op, on: model), "\(op)")
            repository.stateObservationOverride = nil
            XCTAssertEqual(model.reconciliation, .saveUnverified, "\(op)")
            XCTAssertEqual(model.project, prior)
            XCTAssertEqual(HistorySnapshot(model), history)
            XCTAssertEqual(mediaFiles(project.id).count, project.clips.count, "\(op): media preserved")
        }
    }

    func testThrownSaveWithUnreadableEvidenceIsIndeterminate() async throws {
        for op in Op.allCases {
            let (model, project) = try await editor(for: op)
            let state = model.project, history = HistorySnapshot(model)
            repository.updateThrowsAfterCommit = true
            failObservationsAtSave()
            await XCTAssertFalseAsync(await perform(op, on: model), "\(op)")
            repository.updateThrowsAfterCommit = false; repository.onUpdate = nil; swiftData.debugObservationFault = nil
            XCTAssertEqual(model.reconciliation, .saveIndeterminate, "\(op)")
            XCTAssertEqual(model.reconciliation?.title, "저장 결과를 확인하지 못했어요")
            XCTAssertEqual(model.project, state)
            XCTAssertEqual(HistorySnapshot(model), history)
            XCTAssertEqual(mediaFiles(project.id).count, project.clips.count)
        }
    }

    // MARK: Prior checks (before any save)

    func testStaleUnreadableAndMissingPriorStopBeforeSaving() async throws {
        for op in Op.allCases {
            // Stale: another serialized writer changed the stored Project.
            var (model, project) = try await editor(for: op)
            var other = try XCTUnwrap(stored(project.id))
            try other.reorderClip(id: other.clips[0].id, toIndex: other.clips.count - 1)
            try swiftData.update(other)
            var updates = repository.updateCount
            await XCTAssertFalseAsync(await perform(op, on: model), "\(op) stale")
            XCTAssertEqual(repository.updateCount, updates, "\(op): nothing saved")
            XCTAssertEqual(model.reconciliation, .recheckRequired)
            XCTAssertEqual(model.reconciliation?.title, "프로젝트를 다시 확인해주세요")
            XCTAssertEqual(model.reconciliation?.message, "프로젝트 화면에서 다시 열어 확인해주세요.")

            // Unreadable prior: never "unchanged".
            (model, project) = try await editor(for: op)
            swiftData.debugObservationFault = { $0 == .project(project.id) }
            updates = repository.updateCount
            await XCTAssertFalseAsync(await perform(op, on: model), "\(op) unreadable")
            swiftData.debugObservationFault = nil
            XCTAssertEqual(repository.updateCount, updates)
            XCTAssertEqual(model.reconciliation, .recheckRequired)

            // Missing Project.
            (model, project) = try await editor(for: op)
            try swiftData.deleteProject(id: project.id)
            updates = repository.updateCount
            await XCTAssertFalseAsync(await perform(op, on: model), "\(op) missing")
            XCTAssertEqual(repository.updateCount, updates)
            XCTAssertEqual(model.reconciliation, .projectMissing)
            XCTAssertEqual(model.reconciliation?.title, "프로젝트를 찾을 수 없어요")
            XCTAssertEqual(model.reconciliation?.message, "프로젝트 화면에서 다시 확인해주세요.")
            XCTAssertNil(stored(project.id), "no Project recreated")
        }
    }

    func testAddStopsBeforeMaterialisationWhenThePriorIsStale() async throws {
        let project = try makeProject()
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let model = makeModel(project, selector: FakeProjectMediaSelector(script: .fixtures([fixture])))
        var other = project
        try other.deleteClip(id: project.clips[2].id)
        try swiftData.update(other)
        let filesBefore = mediaFiles(project.id)
        let added = await model.addClips()
        XCTAssertEqual(added, 0)
        XCTAssertEqual(model.reconciliation, .recheckRequired)
        XCTAssertEqual(mediaFiles(project.id), filesBefore, "nothing materialised")
        XCTAssertEqual(repository.updateCount, 0)
    }

    // MARK: Add / Replace through the same inner commit

    func testAddAndReplaceCommitInsideTheGateWithoutNestedAcquisition() async throws {
        let project = try makeProject()
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let model = makeModel(project, selector: FakeProjectMediaSelector(script: .fixtures([fixture])))
        let gate = self.gate!
        var heldAtSave: [Bool] = []
        repository.onUpdate = { heldAtSave.append(gate.isHeld && gate.waitingCount == 0) }
        let added = await bounded("add") { await model.addClips() }
        XCTAssertEqual(added, 1)
        XCTAssertEqual(model.undoStack.map(\.kind), [.add])
        XCTAssertEqual(model.project, stored(project.id))

        // Replace: make a Clip's media unavailable, then replace it through the same path.
        try FileManager.default.removeItem(at: root.appendingPathComponent(project.clips[1].mediaRelativePath.value))
        await model.refreshAvailability()
        model.select(project.clips[1].id)
        XCTAssertTrue(model.canReplaceSelectedClip)
        let replaced = await bounded("replace") { await model.replaceSelectedClip() }
        XCTAssertNotNil(replaced ?? nil)
        XCTAssertEqual(model.undoStack.map(\.kind), [.add, .replace])
        XCTAssertEqual(heldAtSave, [true, true], "each save ran inside the one gate section")
        XCTAssertFalse(gate.isHeld)
    }

    func testAddPriorConfirmedUsesP6CopyAndKeepsTheFile() async throws {
        let project = try makeProject()
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let model = makeModel(project, selector: FakeProjectMediaSelector(script: .fixtures([fixture])))
        repository.updateFails = true
        let added = await model.addClips()
        XCTAssertEqual(added, 0)
        XCTAssertEqual(model.editorMessage, .addNotSaved)
        XCTAssertEqual(model.project, project)
        XCTAssertTrue(model.undoStack.isEmpty)
        XCTAssertEqual(mediaFiles(project.id).count, project.clips.count + 1, "candidate file left to startup recovery")
    }

    func testAddAndReplaceUncertainOutcomesLockAndPreserveTheNewFile() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        // Add: thrown save + unreadable evidence → indeterminate.
        var project = try makeProject()
        var model = makeModel(project, selector: FakeProjectMediaSelector(script: .fixtures([fixture])))
        repository.updateThrowsAfterCommit = true
        failObservationsAtSave()
        let added = await model.addClips()
        repository.updateThrowsAfterCommit = false; repository.onUpdate = nil; swiftData.debugObservationFault = nil
        XCTAssertEqual(added, 0)
        XCTAssertEqual(model.reconciliation, .saveIndeterminate)
        XCTAssertEqual(model.project, project); XCTAssertTrue(model.undoStack.isEmpty)
        XCTAssertEqual(mediaFiles(project.id).count, project.clips.count + 1, "the new file is preserved")

        // Replace: save returns + unreadable evidence → committedUnverified; indeterminate as well.
        for throwsAfterCommit in [false, true] {
            project = try makeProject()
            model = makeModel(project, selector: FakeProjectMediaSelector(script: .fixtures([fixture])))
            try FileManager.default.removeItem(at: root.appendingPathComponent(project.clips[1].mediaRelativePath.value))
            await model.refreshAvailability()
            model.select(project.clips[1].id)
            XCTAssertTrue(model.canReplaceSelectedClip)
            let filesBefore = mediaFiles(project.id)
            repository.updateThrowsAfterCommit = throwsAfterCommit
            failObservationsAtSave()
            await XCTAssertNilAsync(await model.replaceSelectedClip())
            repository.updateThrowsAfterCommit = false; repository.onUpdate = nil; swiftData.debugObservationFault = nil
            XCTAssertEqual(model.reconciliation, throwsAfterCommit ? .saveIndeterminate : .saveUnverified)
            XCTAssertEqual(model.project, project); XCTAssertTrue(model.undoStack.isEmpty)
            XCTAssertEqual(mediaFiles(project.id).count, filesBefore.count + 1, "the replacement file is preserved")
        }
    }

    // MARK: In-flight edits

    func testQueuedEditKeepsTimelineAndHistoryAndLocksControlsAndBackUntilProcessed() async throws {
        let (model, project) = try await editor(for: .undo)
        let state = model.project, history = HistorySnapshot(model)
        let holder = await holdGate()
        let undo = Task { await model.undo() }
        _ = await bounded("undo queued") { while self.gate.waitingCount < 1 { try? await Task.sleep(for: .milliseconds(2)) } }

        XCTAssertTrue(model.isCommittingMutation)
        XCTAssertTrue(model.isNavigationLocked, "Back disabled while the edit is in flight")
        XCTAssertEqual(model.project, state, "the existing timeline stays visible; nothing optimistic")
        XCTAssertEqual(HistorySnapshot(model), history)
        XCTAssertFalse(model.canUndo); XCTAssertFalse(model.canRedo); XCTAssertFalse(model.canDeleteSelectedClip); XCTAssertFalse(model.canAddClips)
        XCTAssertFalse(model.beginReorder(clipID: project.clips[0].id), "no drag while in flight")
        let selection = model.selectedClipID
        model.select(project.clips[2].id)
        XCTAssertEqual(model.selectedClipID, selection, "selection waits for the outcome")
        await XCTAssertNilAsync(await model.moveClipLater(id: model.project.clips[0].id))
        await XCTAssertFalseAsync(await model.deleteClip(id: model.project.clips[0].id))

        await holder.release()
        let done = await bounded("undo completes") { await undo.value }
        XCTAssertEqual(done, true)
        XCTAssertFalse(model.isCommittingMutation)
        XCTAssertFalse(model.isNavigationLocked, "navigation restored when processing ends")
        XCTAssertEqual(model.project, stored(project.id))
    }

    func testDropKeepsTheCommittedOrderUntilCompletedAndReservesTheFlagSynchronously() async throws {
        let project = try makeProject()
        let model = makeModel(project)
        let holder = await holdGate()
        XCTAssertTrue(model.beginReorder(clipID: project.clips[2].id))
        model.previewReorder(toIndex: 0)
        let task = model.commitReorder()
        XCTAssertNotNil(task)
        XCTAssertTrue(model.isCommittingMutation, "reserved before the gate is awaited")
        XCTAssertEqual(model.orderedClips.map(\.id), project.clips.map(\.id), "committed order shown, not the attempted one")
        await holder.release()
        let saved = await bounded("drop completes") { await task?.value }
        XCTAssertEqual(saved ?? nil, true)
        XCTAssertEqual(model.orderedClips.first?.id, project.clips[2].id)
    }

    // MARK: Reconciliation lock

    func testReconciliationRejectsEveryMutationEntryPoint() async throws {
        let project = try makeProject()
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let selector = FakeProjectMediaSelector(script: .fixtures([fixture]))
        let model = makeModel(project, selector: selector)
        await XCTAssertTrueAsync(await model.deleteClip(id: project.clips[2].id))   // history for Undo
        await XCTAssertTrueAsync(await model.undo())                                // history for Redo
        failObservationsAtSave()
        await XCTAssertFalseAsync(await model.moveClipLater(id: project.clips[0].id) != nil)
        repository.onUpdate = nil; swiftData.debugObservationFault = nil
        XCTAssertEqual(model.reconciliation, .saveUnverified)

        let updates = repository.updateCount, state = model.project, selection = model.selectedClipID
        XCTAssertFalse(model.canUndo); XCTAssertFalse(model.canRedo); XCTAssertFalse(model.canDeleteSelectedClip)
        XCTAssertFalse(model.canAddClips); XCTAssertFalse(model.canReplaceSelectedClip)
        XCTAssertFalse(model.beginReorder(clipID: project.clips[0].id))
        XCTAssertNil(model.commitReorder())
        await XCTAssertNilAsync(await model.moveClipEarlier(id: project.clips[1].id))
        await XCTAssertNilAsync(await model.moveClipLater(id: project.clips[0].id))
        await XCTAssertFalseAsync(await model.deleteClip(id: project.clips[0].id))
        await XCTAssertFalseAsync(await model.deleteSelectedClip())
        await XCTAssertFalseAsync(await model.undo())
        await XCTAssertFalseAsync(await model.redo())
        await XCTAssertEqualAsync(await model.addClips(), 0)
        await XCTAssertNilAsync(await model.replaceSelectedClip())
        model.select(project.clips[1].id)
        XCTAssertEqual(model.selectedClipID, selection, "the locked timeline ignores selection too")
        XCTAssertEqual(repository.updateCount, updates, "nothing written")
        XCTAssertEqual(selector.selectionCount, 0, "no picker presented")
        XCTAssertEqual(model.project, state)
        XCTAssertEqual(model.reconciliation, .saveUnverified, "never cleared by the model")
        XCTAssertEqual(EditorReconciliation.returnAction, "프로젝트 화면으로")
    }

    // MARK: Return to Projects and reopen

    func testReturnToProjectsLeavesTheEditorAndReopenStartsWithEmptyHistory() async throws {
        let (model, project) = try await editor(for: .undo)
        failObservationsAtSave()
        await XCTAssertFalseAsync(await model.undo())
        repository.onUpdate = nil; swiftData.debugObservationFault = nil
        XCTAssertEqual(model.reconciliation, .saveUnverified)

        let router = AppRouter()
        var removed: [UUID] = []
        router.onProjectEditorRouteRemoved = { removed.append($0) }
        router.path = [.projectsEntry, .projectEditor(project.id)]
        router.leaveProjectEditor(project.id)
        XCTAssertEqual(router.path, [.projectsEntry], "back on the Projects screen")
        XCTAssertEqual(removed, [project.id], "the usual Editor-session-ended boundary fires once")

        // Reopen through the gated load: the store's current truth, empty session history.
        let loaded = await gate.withExclusiveAccess { try? self.repository.project(id: project.id) }
        let reopened = makeModel(try XCTUnwrap(loaded ?? nil))
        XCTAssertTrue(reopened.undoStack.isEmpty); XCTAssertTrue(reopened.redoStack.isEmpty)
        XCTAssertNil(reopened.reconciliation)
        XCTAssertEqual(reopened.project, stored(project.id))
    }

    // MARK: Timestamp round trip

    func testUpdatedTimestampRoundTripsExactlyThroughTheStore() async throws {
        let project = try makeProject()
        var updated = project
        try updated.reorderClip(id: project.clips[0].id, toIndex: 2, updatedAt: .now)
        try swiftData.update(updated)
        let observed = try XCTUnwrap(stored(project.id))
        XCTAssertEqual(observed, updated, "the full value, sub-second timestamps included")
        XCTAssertEqual(ProjectStateSnapshot(observed), ProjectStateSnapshot(updated))
        XCTAssertEqual(observed.updatedAt.timeIntervalSinceReferenceDate, updated.updatedAt.timeIntervalSinceReferenceDate)
    }
}

/// Holds the shared gate from a test until released.
@MainActor
private final class GateHolder {
    private(set) var isHolding = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var task: Task<Void, Never>?

    func hold(_ gate: ProjectLifecycleOperationGate) {
        task = Task { @MainActor in
            await gate.withExclusiveAccess {
                self.isHolding = true
                await withCheckedContinuation { self.continuation = $0 }
                self.isHolding = false
            }
        }
    }

    func release() async {
        continuation?.resume()
        continuation = nil
        await task?.value
    }

    func releaseWithoutWaiting() {
        continuation?.resume()
        continuation = nil
    }
}

private final class DoneFlag { var done = false }
