import XCTest
@testable import Mellow

@MainActor
final class ProjectsEntryModelTests: XCTestCase {
    private final class Recorder {
        var continued: [UUID] = []
        var newProject: [ProjectsEntryModel.NewProjectIntent] = []
        var committed: [UUID] = []
    }

    private var root: URL!
    private var store: ProjectMediaStore!
    override func setUp() {
        root = TestSupport.temporaryRoot("entry-model")
        store = ProjectMediaStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func makeModel(
        repository: any ProjectRepository,
        recorder: Recorder,
        selector: FakeProjectMediaSelector? = nil,
        gate: (any ProjectStorageGating)? = nil
    ) -> ProjectsEntryModel {
        let selector = selector ?? FakeProjectMediaSelector(script: .cancel)
        let gate = gate ?? FakeProjectStorageGate(verdict: .sufficient)
        return ProjectsEntryModel(
            composition: ProjectCompositionCoordinator(
                repository: repository,
                mediaStore: store,
                validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()),
                storage: gate,
                lifecycle: ProjectLifecycleOperationGate()
            ),
            mediaStore: store,
            mediaSelector: selector,
            storageGate: gate,
            onContinueEditing: { recorder.continued.append($0) },
            onNewProject: { recorder.newProject.append($0) },
            onProjectCommitted: { recorder.committed.append($0) }
        )
    }

    private func workspaceCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("ProjectWorkspace").path))?.count ?? 0
    }

    // MARK: - No saved Project

    func testNoSavedProjectReportsNoneAndOnlyNewProjectIntent() async throws {
        let repository = InMemoryProjectRepository()
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()

        XCTAssertNil(model.savedProjectID)
        XCTAssertFalse(model.hasSavedProject)

        // Continue is unavailable: it delivers nothing without a saved Project.
        model.continueEditing()
        XCTAssertTrue(recorder.continued.isEmpty)

        // New project goes straight through without a confirmation; the fake picker cancels.
        model.requestNewProject()
        XCTAssertFalse(model.isReplacementConfirmationPresented)
        XCTAssertEqual(recorder.newProject, [.fresh])
        await Task.yield()
        await model.runSelectClips(.fresh)
        XCTAssertTrue(try repository.recentProjects().isEmpty, "no Project may be created by the entry")
    }

    // MARK: - Saved Project

    func testSavedProjectIsIdentifiedAndContinuePreservesExactID() throws {
        let repository = InMemoryProjectRepository()
        let older = try VlogProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100), orientation: .portrait9x16)
        let newer = try VlogProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 500), orientation: .portrait9x16)
        try repository.create(older)
        try repository.create(newer)
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()

        XCTAssertEqual(model.savedProjectID, newer.id, "coordinator's canonical saved Project")
        XCTAssertTrue(model.hasSavedProject)

        model.continueEditing()
        XCTAssertEqual(recorder.continued, [newer.id], "navigation identity is the exact saved ID")
        XCTAssertTrue(recorder.newProject.isEmpty)
        XCTAssertEqual(Set(try repository.recentProjects().map(\.id)), [older.id, newer.id], "continue deletes nothing")
    }

    func testNewProjectWithSavedProjectEntersReplacementConfirmation() throws {
        let repository = InMemoryProjectRepository()
        let saved = try VlogProject(orientation: .portrait9x16)
        try repository.create(saved)
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()

        model.requestNewProject()
        XCTAssertTrue(model.isReplacementConfirmationPresented)
        XCTAssertTrue(recorder.newProject.isEmpty, "no intent before the user confirms")
        XCTAssertEqual(try repository.recentProjects().map(\.id), [saved.id])
    }

    func testCancelLeavesSavedProjectUntouched() throws {
        let repository = InMemoryProjectRepository()
        let saved = try VlogProject(orientation: .portrait9x16)
        try repository.create(saved)
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()

        model.requestNewProject()
        model.cancelReplacement()
        XCTAssertFalse(model.isReplacementConfirmationPresented)
        XCTAssertTrue(recorder.newProject.isEmpty)
        XCTAssertTrue(recorder.continued.isEmpty)
        XCTAssertEqual(model.savedProjectID, saved.id)
        XCTAssertEqual(try repository.recentProjects().map(\.id), [saved.id])
    }

    func testConfirmEmitsConfirmedIntentWithoutMutatingPersistence() async throws {
        let repository = InMemoryProjectRepository()
        let saved = try VlogProject(orientation: .portrait9x16)
        try repository.create(saved)
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()

        model.requestNewProject()
        model.confirmReplacement()
        XCTAssertFalse(model.isReplacementConfirmationPresented)
        XCTAssertEqual(recorder.newProject, [.replacingSaved(saved.id)])
        await Task.yield()
        await model.runSelectClips(.replacingSaved(saved.id)) // cancelled by the fake selector

        // Confirmation + a cancelled picker never delete, create or mutate anything.
        let all = try repository.recentProjects()
        XCTAssertEqual(all.map(\.id), [saved.id])
        XCTAssertEqual(all.first?.updatedAt, saved.updatedAt)
        XCTAssertEqual(model.savedProjectID, saved.id, "the entry still reports the same saved Project")
    }

    func testLoadFailureIsUnknownAndBlocksCreatingAndOpening() throws {
        let repository = FailingLookupRepository()
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()
        XCTAssertEqual(model.lookup, .unknown, "a failed lookup is unknown, not 'no saved Project' (D8.5a P5)")
        XCTAssertTrue(model.isLookupUnknown)
        XCTAssertNil(model.savedProjectID)
        XCTAssertFalse(model.canStartNewProject)
        model.requestNewProject()
        model.continueEditing()
        XCTAssertFalse(model.isReplacementConfirmationPresented)
        XCTAssertTrue(recorder.newProject.isEmpty, "creation is disabled while unknown")
        XCTAssertTrue(recorder.continued.isEmpty, "opening is disabled while unknown")
        XCTAssertEqual(repository.created, 0, "a failed lookup never creates a Project")
    }

    func testActionsStayDisabledUntilTheFirstSuccessfulLookup() {
        let recorder = Recorder()
        let model = makeModel(repository: InMemoryProjectRepository(), recorder: recorder)
        XCTAssertEqual(model.lookup, .notLoaded)
        XCTAssertFalse(model.canStartNewProject)
        model.requestNewProject()
        XCTAssertTrue(recorder.newProject.isEmpty)
    }

    func testExplicitReloadRestoresActionsOnlyAfterASuccessfulLoad() throws {
        let repository = FailableProjectRepository()
        let saved = try VlogProject(orientation: .portrait9x16)
        try repository.create(saved)
        repository.recentProjectsFails = true
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder)
        model.load()
        XCTAssertEqual(model.lookup, .unknown)

        model.reload()
        XCTAssertEqual(model.lookup, .unknown, "a failed reload stays unknown")
        XCTAssertFalse(model.canStartNewProject)

        repository.recentProjectsFails = false
        model.reload()
        XCTAssertEqual(model.lookup, .loaded(saved.id))
        XCTAssertTrue(model.canStartNewProject)
        model.continueEditing()
        XCTAssertEqual(recorder.continued, [saved.id])

        // A later failure (after a success) is unknown again — never "no saved Project".
        repository.recentProjectsFails = true
        model.load()
        XCTAssertEqual(model.lookup, .unknown)
        XCTAssertFalse(model.hasSavedProject)
    }

    func testSuccessfulEmptyLookupAllowsCreation() {
        let recorder = Recorder()
        let model = makeModel(repository: InMemoryProjectRepository(), recorder: recorder)
        model.load()
        XCTAssertEqual(model.lookup, .loaded(nil))
        XCTAssertFalse(model.isLookupUnknown)
        XCTAssertTrue(model.canStartNewProject)
    }

    func testUnknownLookupContentUsesTheApprovedCopy() {
        let content = ProjectsEntryContent.unknownLookup
        XCTAssertEqual(content.headline, "프로젝트를 불러오지 못했어요")
        XCTAssertEqual(content.supporting, "저장된 프로젝트를 확인할 수 없어요. 다시 불러와주세요.")
        XCTAssertEqual(content.visual, .placeholder)
        XCTAssertEqual(ProjectsEntryModel.UnknownLookupCopy.reloadAction, "다시 불러오기")
    }

    // MARK: - Select Clips flow

    func testPickerCancelIsSilentAndCleansWorkspace() async throws {
        let repository = InMemoryProjectRepository()
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder, selector: FakeProjectMediaSelector(script: .cancel))
        model.load()
        await model.runSelectClips(.fresh)
        XCTAssertNil(model.compositionMessage, "cancel is not an error")
        XCTAssertTrue(recorder.committed.isEmpty)
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        XCTAssertEqual(workspaceCount(), 0, "no leftover operation workspace")
        XCTAssertFalse(model.isComposing)
    }

    func testReadyMediaCommitsAndDeliversProjectID() async throws {
        let repository = InMemoryProjectRepository()
        let recorder = Recorder()
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let model = makeModel(repository: repository, recorder: recorder, selector: FakeProjectMediaSelector(script: .fixtures([fixture])))
        model.load()
        await model.runSelectClips(.fresh)
        XCTAssertNil(model.compositionMessage)
        XCTAssertEqual(recorder.committed.count, 1)
        XCTAssertEqual(try repository.recentProjects().map(\.id), recorder.committed)
        XCTAssertEqual(model.savedProjectID, recorder.committed.first, "entry state refreshed after commit")
        XCTAssertEqual(workspaceCount(), 0)
    }

    func testRequiresPreparationShowsMessageAndCreatesNothing() async throws {
        let repository = InMemoryProjectRepository()
        let recorder = Recorder()
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 7)
        let model = makeModel(repository: repository, recorder: recorder, selector: FakeProjectMediaSelector(script: .fixtures([fixture])))
        model.load()
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.compositionMessage, .requiresImportPreparation(.tooLong))
        XCTAssertTrue(recorder.committed.isEmpty)
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        XCTAssertEqual(workspaceCount(), 0)
        // Dismiss and retry is possible: the model is idle again.
        model.compositionMessage = nil
        XCTAssertFalse(model.isComposing)
    }

    func testSelectionFailureShowsRecoverableMessage() async throws {
        let repository = InMemoryProjectRepository()
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder, selector: FakeProjectMediaSelector(script: .fail))
        model.load()
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.compositionMessage, .preparationFailed)
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        XCTAssertEqual(workspaceCount(), 0)
    }

    // MARK: - Reason-specific preparation copy (presentation only)

    func testPreparationReasonsMapToUserFacingCopyWithoutImplementationTerms() {
        typealias Message = ProjectsEntryModel.CompositionMessage
        XCTAssertEqual(Message.requiresImportPreparation(.tooLong).title, "영상이 너무 길어요")
        XCTAssertEqual(Message.requiresImportPreparation(.tooLong).message, "5초 이하의 영상을 선택해주세요.")
        // The Editor's Add Clips shares the exact same copy through the canonical mapping.
        XCTAssertEqual(ProjectEditorMessage.addRequiresImportPreparation(.tooLong).title, "영상이 너무 길어요")
        XCTAssertEqual(ProjectEditorMessage.addRequiresImportPreparation(.tooLong).message, "5초 이하의 영상을 선택해주세요.")
        XCTAssertEqual(ProjectEditorMessage.addRequiresImportPreparation(.orientation).message, Message.requiresImportPreparation(.orientation).message)
        XCTAssertEqual(ProjectEditorMessage.addInvalidMedia.title, Message.invalidMedia.title)
        XCTAssertEqual(ProjectEditorMessage.addInsufficientStorage.message, Message.insufficientStorage.message)
        XCTAssertEqual(Message.requiresImportPreparation(.orientation).title, "세로 영상을 선택해주세요")
        XCTAssertEqual(Message.requiresImportPreparation(.orientation).message, "현재 프로젝트에서는 세로 영상을 바로 사용할 수 있어요.")
        for reason in [Phase5ReadyVerdict.PreparationReason.highDynamicRange, .resolution, .frameRate] {
            XCTAssertEqual(Message.requiresImportPreparation(reason).title, "이 영상은 바로 사용할 수 없어요", "\(reason)")
            XCTAssertEqual(Message.requiresImportPreparation(reason).message, "다른 영상을 선택해주세요.", "\(reason)")
        }
        let all: [Message] = [.requiresImportPreparation(.tooLong), .requiresImportPreparation(.orientation), .requiresImportPreparation(.highDynamicRange), .requiresImportPreparation(.resolution), .requiresImportPreparation(.frameRate), .invalidMedia, .insufficientStorage, .projectInspectionFailed, .replacementTargetInvalidated, .preparationFailed, .saveUnverified, .saveIndeterminate, .notSaved]
        for message in all {
            for banned in ["Phase", "가져오기 단계", "HDR", "transcod", "프레임", "normaliz", "정규화"] {
                XCTAssertFalse((message.title + message.message).localizedCaseInsensitiveContains(banned), "\(message) exposes '\(banned)'")
            }
        }
    }

    func testSelectClipsOutcomeCopyIsExact() {
        typealias Message = ProjectsEntryModel.CompositionMessage
        let expected: [(Message, String, String)] = [
            (.projectInspectionFailed, "프로젝트를 확인하지 못했어요", "프로젝트 화면에서 다시 확인해주세요."),
            (.replacementTargetInvalidated, "프로젝트를 교체하지 못했어요", "교체하려던 프로젝트를 찾을 수 없어요."),
            (.preparationFailed, "영상을 준비하지 못했어요", "영상을 다시 선택해주세요."),
            (.saveUnverified, "저장 확인이 필요해요", "새 프로젝트는 저장되었지만 지금은 확인하지 못했어요. 프로젝트 화면에서 다시 확인해주세요."),
            (.saveIndeterminate, "저장 결과를 확인하지 못했어요", "새 프로젝트가 만들어졌는지 지금은 알 수 없어요. 다시 만들기 전에 프로젝트 화면에서 확인해주세요."),
            (.notSaved, "프로젝트를 만들지 못했어요", "새 프로젝트가 저장되지 않았어요."),
        ]
        for (message, title, body) in expected {
            XCTAssertEqual(message.title, title, "\(message)")
            XCTAssertEqual(message.message, body, "\(message)")
            XCTAssertFalse(body.contains("다시 시도"), "no Retry wording (D8.5a P6)")
        }
    }

    // MARK: - Save outcomes → presentation and refresh (ADR-050 050-D D8.5a)

    private func composeModel(_ repository: FailableProjectRepository, _ recorder: Recorder) async throws -> ProjectsEntryModel {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let model = makeModel(repository: repository, recorder: recorder, selector: FakeProjectMediaSelector(script: .fixtures([fixture])))
        model.load()
        return model
    }

    func testCompletedAfterAThrownSaveNavigatesWithoutAnAlert() async throws {
        let repository = FailableProjectRepository()
        repository.createThrowsAfterCommit = true
        let recorder = Recorder()
        let model = try await composeModel(repository, recorder)
        await model.runSelectClips(.fresh)
        XCTAssertNil(model.compositionMessage, "P4: logged only, no failure alert")
        XCTAssertEqual(recorder.committed.count, 1)
        XCTAssertEqual(model.lookup, .loaded(recorder.committed.first))
    }

    func testNonCompletedOutcomesShowTheirCopyStayAndRefresh() async throws {
        // priorConfirmed (P6)
        var repository = FailableProjectRepository()
        var recorder = Recorder()
        var model = try await composeModel(repository, recorder)
        repository.createFails = true
        repository.onSave = { [unowned repository] in repository.recentProjectsFails = true }
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.compositionMessage, .notSaved)
        XCTAssertEqual(model.lookup, .unknown, "the lookup ran again after the outcome and its failure is unknown")
        XCTAssertTrue(recorder.committed.isEmpty, "stays on Projects")

        // committedUnverified (U1): the save returned, the observation could not read B.
        repository = FailableProjectRepository()
        recorder = Recorder()
        model = try await composeModel(repository, recorder)
        repository.stateObservationOverride = { expectation, observed in
            PersistedStateObservation(projects: observed.projects.mapValues { _ in .unreadable }, createdIdentityHolders: observed.createdIdentityHolders)
        }
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.compositionMessage, .saveUnverified)
        XCTAssertTrue(recorder.committed.isEmpty)
        let saved = try XCTUnwrap(try repository.recentProjects().first, "the saved row is never rolled back")
        XCTAssertEqual(model.lookup, .loaded(saved.id), "refreshed after a non-completed outcome")

        // indeterminate (U2): the save threw and the observation is unreadable.
        repository = FailableProjectRepository()
        recorder = Recorder()
        model = try await composeModel(repository, recorder)
        repository.createFails = true
        repository.stateObservationOverride = { _, observed in
            PersistedStateObservation(projects: observed.projects.mapValues { _ in .unreadable }, createdIdentityHolders: nil)
        }
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.compositionMessage, .saveIndeterminate)
        XCTAssertTrue(recorder.committed.isEmpty)
        XCTAssertEqual(model.lookup, .loaded(nil))
    }

    func testInspectionFailureStaysAndRefreshesTheLookup() async throws {
        let repository = FailableProjectRepository()
        let recorder = Recorder()
        let model = try await composeModel(repository, recorder)
        repository.priorObservationOverride = { [unowned repository] _ in
            repository.recentProjectsFails = true
            return .unreadable
        }
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.compositionMessage, .projectInspectionFailed)
        XCTAssertEqual(model.lookup, .unknown, "refreshed; the failed refresh stays unknown (no inferred absence)")
        XCTAssertEqual(repository.createCount, 0)
        XCTAssertTrue(TestSupport.noProjectMedia(under: root), "nothing materialized")
    }

    func testInvalidatedReplacementTargetStaysWithoutCreatingB() async throws {
        let repository = FailableProjectRepository()
        let a = try VlogProject(orientation: .portrait9x16)
        try repository.create(a)
        let recorder = Recorder()
        let model = try await composeModel(repository, recorder)
        XCTAssertEqual(model.savedProjectID, a.id)
        try repository.inner.deleteProject(id: a.id)
        await model.runSelectClips(.replacingSaved(a.id))
        XCTAssertEqual(model.compositionMessage, .replacementTargetInvalidated)
        XCTAssertEqual(model.lookup, .loaded(nil), "refreshed exactly once after invalidation (D8.5b)")
        XCTAssertTrue(recorder.committed.isEmpty)
        XCTAssertEqual(repository.createCount, 1, "only the seed: B is never created alone")
        XCTAssertEqual(repository.replaceCount, 0)
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        XCTAssertTrue(TestSupport.noProjectMedia(under: root))
    }

    func testInvalidationRefreshesOnceAndAFailedRefreshIsUnknownWithoutRetry() async throws {
        let repository = FailableProjectRepository()
        let a = try VlogProject(orientation: .portrait9x16)
        try repository.create(a)
        let recorder = Recorder()
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let selector = FakeProjectMediaSelector(script: .fixtures([fixture]))
        let model = makeModel(repository: repository, recorder: recorder, selector: selector)
        model.load()
        XCTAssertEqual(model.lookup, .loaded(a.id))
        // A newer Project takes over (A is no longer current) and the post-outcome refresh fails.
        let newer = try VlogProject(createdAt: Date(timeIntervalSinceNow: 60), updatedAt: Date(timeIntervalSinceNow: 60), orientation: .portrait9x16)
        try repository.inner.create(newer)
        repository.recentProjectsFails = true

        await model.runSelectClips(.replacingSaved(a.id))
        XCTAssertEqual(model.compositionMessage, .replacementTargetInvalidated)
        XCTAssertEqual(model.lookup, .unknown, "the one refresh failed: unknown, never inferred absence")
        XCTAssertFalse(model.canStartNewProject)
        XCTAssertEqual(selector.selectionCount, 1, "no automatic composition retry")
        XCTAssertEqual(repository.currentProjectObservations, 1, "one gated composition attempt")
        XCTAssertEqual(repository.replaceCount, 0)
        XCTAssertEqual(repository.createCount, 1, "only the seed: no B-only fallback")
        XCTAssertTrue(recorder.committed.isEmpty)

        // The explicit reload is the only way back.
        repository.recentProjectsFails = false
        model.reload()
        XCTAssertEqual(model.lookup, .loaded(newer.id))
        XCTAssertEqual(selector.selectionCount, 1)
    }

    // MARK: - Pre-copy storage admission (STEP 6B)

    private func fileSize(_ url: URL) throws -> Int64 { Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }

    func testSingleFilePreCopyAdmissionPassesAtBoundaryAndRefusesBelow() async throws {
        let reserve = ProjectCompositionPolicy.materializationSafetyReserveBytes
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let size = try fileSize(fixture)
        XCTAssertGreaterThan(size, 0)

        // available < incoming + reserve → refused before any Mellow-owned copy.
        let repository = InMemoryProjectRepository()
        let recorder = Recorder()
        let selector = FakeProjectMediaSelector(script: .fixtures([fixture]))
        let gate = ScriptedCapacityGate(capacities: [size + reserve - 1])
        let model = makeModel(repository: repository, recorder: recorder, selector: selector, gate: gate)
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.compositionMessage, .insufficientStorage)
        XCTAssertEqual(selector.admittedBytes, [size])
        XCTAssertTrue(recorder.committed.isEmpty)
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        XCTAssertEqual(workspaceCount(), 0, "no copy landed in a workspace")
        XCTAssertTrue(TestSupport.noProjectMedia(under: root), "nothing was materialized")

        // available == incoming + reserve → pass (later checks keep answering the last value).
        let passRecorder = Recorder()
        let passGate = ScriptedCapacityGate(capacities: [size + reserve])
        let passing = makeModel(repository: InMemoryProjectRepository(), recorder: passRecorder, selector: FakeProjectMediaSelector(script: .fixtures([fixture])), gate: passGate)
        await passing.runSelectClips(.fresh)
        XCTAssertEqual(passRecorder.committed.count, 1)
        XCTAssertEqual(passGate.checks.first, size, "admission asked for exactly the incoming byte size")
    }

    func testMultiFileAdmissionIsSequentialAndFailureCleansEarlierCopies() async throws {
        let reserve = ProjectCompositionPolicy.materializationSafetyReserveBytes
        let first = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let second = try await TestMediaFixtures.shared.portrait(seconds: 3)
        let s1 = try fileSize(first), s2 = try fileSize(second)
        // Capacity is queried before each copy: the first passes, the second (after s1 is on disk)
        // reports one byte short of s2 + reserve and must refuse.
        let gate = ScriptedCapacityGate(capacities: [s1 + reserve, s2 + reserve - 1])
        let repository = InMemoryProjectRepository()
        let recorder = Recorder()
        let selector = FakeProjectMediaSelector(script: .fixtures([first, second]))
        let model = makeModel(repository: repository, recorder: recorder, selector: selector, gate: gate)
        await model.runSelectClips(.fresh)

        XCTAssertEqual(gate.checks, [s1, s2], "each check carries only that file's incoming size — the copied first file is never re-counted")
        XCTAssertEqual(model.compositionMessage, .insufficientStorage)
        XCTAssertTrue(recorder.committed.isEmpty, "no partial Project B")
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        XCTAssertEqual(workspaceCount(), 0, "the first file's disposable copy was cleaned with the operation")
        XCTAssertTrue(TestSupport.exists(first) && TestSupport.exists(second), "sources untouched")
    }

    func testMultiFileAdmissionAllPassThenFinalReserveGuardRunsWithZeroAdditional() async throws {
        let reserve = ProjectCompositionPolicy.materializationSafetyReserveBytes
        let first = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let second = try await TestMediaFixtures.shared.portrait(seconds: 3)
        let s1 = try fileSize(first), s2 = try fileSize(second)
        let gate = ScriptedCapacityGate(capacities: [s1 + reserve, s2 + reserve, reserve])
        let recorder = Recorder()
        let model = makeModel(repository: InMemoryProjectRepository(), recorder: recorder, selector: FakeProjectMediaSelector(script: .fixtures([first, second])), gate: gate)
        await model.runSelectClips(.fresh)
        XCTAssertEqual(recorder.committed.count, 1)
        XCTAssertEqual(gate.checks, [s1, s2, 0], "two pre-copy admissions, then the final reserve-only guard (no 2× estimate)")
    }

    func testReplacementPreCopyRefusalLeavesAIntact() async throws {
        let reserve = ProjectCompositionPolicy.materializationSafetyReserveBytes
        let repository = InMemoryProjectRepository()
        let a = try VlogProject(orientation: .portrait9x16)
        try repository.create(a)
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let size = try fileSize(fixture)
        let recorder = Recorder()
        let model = makeModel(repository: repository, recorder: recorder, selector: FakeProjectMediaSelector(script: .fixtures([fixture])), gate: ScriptedCapacityGate(capacities: [size + reserve - 1]))
        model.load()
        await model.runSelectClips(.replacingSaved(a.id))
        XCTAssertEqual(model.compositionMessage, .insufficientStorage)
        XCTAssertEqual(try repository.recentProjects().map(\.id), [a.id], "A intact")
        XCTAssertEqual(model.savedProjectID, a.id)
        XCTAssertTrue(recorder.committed.isEmpty)
        XCTAssertEqual(workspaceCount(), 0)
    }

    /// Repository whose recency lookup fails; everything else is a no-op that counts creations.
    private final class FailingLookupRepository: ProjectRepository {
        private(set) var created = 0
        private enum LookupError: Error { case failed }
        func create(_ project: VlogProject) throws { created += 1 }
        func project(id: UUID) throws -> VlogProject? { nil }
        func recentProjects() throws -> [VlogProject] { throw LookupError.failed }
        func update(_ project: VlogProject) throws {}
        func finalizeDeletedClip(projectID: UUID, clipID: UUID) throws {}
        func deleteProject(id: UUID) throws {}
        func replaceProject(previousID: UUID, with project: VlogProject) throws {}
    }
}
