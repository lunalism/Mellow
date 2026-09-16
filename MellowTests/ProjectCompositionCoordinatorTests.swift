import SwiftData
import XCTest
@testable import Mellow

@MainActor
final class ProjectCompositionCoordinatorTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!

    override func setUp() {
        root = TestSupport.temporaryRoot("composition")
        store = ProjectMediaStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func makeProject(orientation: ProjectOrientation = .portrait9x16, createdAt: Date, updatedAt: Date? = nil) throws -> VlogProject {
        try VlogProject(createdAt: createdAt, updatedAt: updatedAt, orientation: orientation)
    }

    private func coordinator(
        repository: any ProjectRepository,
        inspector: any ProjectMediaInspecting = AVAssetProjectMediaInspector(),
        storage: ProjectStorageVerdict = .sufficient
    ) -> ProjectCompositionCoordinator {
        ProjectCompositionCoordinator(
            repository: repository,
            mediaStore: store,
            validator: Phase5ReadyMediaValidator(inspector: inspector),
            storage: FakeProjectStorageGate(verdict: storage),
            lifecycle: ProjectLifecycleOperationGate()
        )
    }

    private func sources(_ fixtures: [URL], in workspace: ProjectMediaWorkspace) async throws -> [SelectedVideoSource] {
        try await TestSupport.adoptedSources(fixtures, into: workspace, store: store)
    }

    /// Seeds Project A with one real app-owned media file so its media lifecycle can be observed.
    private func seedSavedProject(in repository: any ProjectRepository) async throws -> (VlogProject, RelativeMediaPath) {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let workspace = try await store.beginWorkspace()
        let adopted = try await store.adopt(try TestSupport.transferCopy(of: fixture), into: workspace)
        let projectID = UUID(), clipID = UUID()
        let path = try await store.materialize(adopted, projectID: projectID, clipID: clipID)
        let clip = try VlogClip(id: clipID, projectID: projectID, sourceKind: .imported, mediaRelativePath: path, sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: 0)
        let project = try VlogProject(id: projectID, createdAt: Date(timeIntervalSince1970: 100), orientation: .portrait9x16, clips: [clip])
        try repository.create(project)
        await store.discard(workspace)
        return (project, path)
    }

    // MARK: - Append coordinator (Phase 5 STEP 11, ADR-037)

    private func appender(storage: ProjectStorageVerdict = .sufficient, inspector: any ProjectMediaInspecting = AVAssetProjectMediaInspector()) -> ProjectClipAppendCoordinator {
        ProjectClipAppendCoordinator(mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: inspector), storage: FakeProjectStorageGate(verdict: storage))
    }

    private func mediaDirectoryContents(_ projectID: UUID) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects/\(projectID.uuidString)/Media").path)) ?? []).sorted()
    }

    func testAppendMaterialisesIntoCurrentProjectDirectoryInPickerOrder() async throws {
        let repository = InMemoryProjectRepository()
        let (project, existingPath) = try await seedSavedProject(in: repository)
        let a = try await TestMediaFixtures.shared.portrait(seconds: 2, name: "append-a")
        let b = try await TestMediaFixtures.shared.portrait(seconds: 3, name: "append-b")
        let workspace = try await store.beginWorkspace()
        let sources = try await sources([a, b], in: workspace)

        let outcome = await appender().prepareClips(for: project, sources: sources)
        guard case .ready(let clips) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips.map(\.projectID), [project.id, project.id])
        XCTAssertEqual(clips.map(\.sourceKind), [.imported, .imported])
        XCTAssertEqual(Double(clips[0].sourceDuration.value) / Double(clips[0].sourceDuration.timescale), 2, accuracy: 0.001)
        XCTAssertEqual(Double(clips[1].sourceDuration.value) / Double(clips[1].sourceDuration.timescale), 3, accuracy: 0.001)
        for clip in clips {
            XCTAssertEqual(clip.mediaRelativePath.value, "Projects/\(project.id.uuidString)/Media/\(clip.id.uuidString).mov")
            let exists = await store.fileExists(clip.mediaRelativePath)
            XCTAssertTrue(exists)
        }
        let existingStillThere = await store.fileExists(existingPath)
        XCTAssertTrue(existingStillThere, "pre-existing media untouched")
        XCTAssertEqual(mediaDirectoryContents(project.id).count, 3)
        XCTAssertEqual(try repository.project(id: project.id)?.clips.count, 1, "the coordinator never persists")
        await store.discard(workspace)
    }

    func testAppendRejectsWholeBatchOnFirstNonReadyOrInvalidSource() async throws {
        let repository = InMemoryProjectRepository()
        let (project, _) = try await seedSavedProject(in: repository)
        let ready = try await TestMediaFixtures.shared.portrait(seconds: 2, name: "append-ready")
        let tooLong = try await TestMediaFixtures.shared.portrait(seconds: 7, name: "append-long")
        var workspace = try await store.beginWorkspace()
        var outcome = await appender().prepareClips(for: project, sources: try await sources([ready, tooLong], in: workspace))
        XCTAssertEqual(outcome, .requiresImportPreparation(.tooLong))
        XCTAssertEqual(mediaDirectoryContents(project.id).count, 1, "nothing materialised for a rejected batch")
        await store.discard(workspace)

        workspace = try await store.beginWorkspace()
        outcome = await appender().prepareClips(for: project, sources: try await sources([try TestMediaFixtures.shared.corrupt()], in: workspace))
        XCTAssertEqual(outcome, .invalidMedia(.unreadable))
        await store.discard(workspace)

        workspace = try await store.beginWorkspace()
        outcome = await appender(storage: .insufficient(requiredBytes: 1, usableBytes: 0)).prepareClips(for: project, sources: try await sources([ready], in: workspace))
        XCTAssertEqual(outcome, .insufficientStorage)
        XCTAssertEqual(mediaDirectoryContents(project.id).count, 1)
        await store.discard(workspace)

        let emptyOutcome = await appender().prepareClips(for: project, sources: [])
        XCTAssertEqual(emptyOutcome, .failed)
    }

    func testAppendMaterializationFailureRemovesOnlyThisOperationsFiles() async throws {
        let repository = InMemoryProjectRepository()
        let (project, existingPath) = try await seedSavedProject(in: repository)
        let a = try await TestMediaFixtures.shared.portrait(seconds: 2, name: "append-fail-a")
        let workspace = try await store.beginWorkspace()
        var sources = try await sources([a, a], in: workspace)
        // Second source vanishes before materialisation → the first, already materialised, is rolled back.
        try FileManager.default.removeItem(at: sources[1].url)
        sources[1] = SelectedVideoSource(url: sources[1].url, byteCount: 0)

        // Validation is stubbed as ready so the failure is materialisation itself, not validation.
        let outcome = await appender(inspector: FakeProjectMediaInspector(.ready())).prepareClips(for: project, sources: sources)
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(mediaDirectoryContents(project.id).count, 1, "only the pre-existing file remains")
        let existingStillThere = await store.fileExists(existingPath)
        XCTAssertTrue(existingStillThere)
        await store.discard(workspace)
    }

    // MARK: - Lookup (STEP 4, unchanged)

    func testNoProjectsReturnsNil() throws {
        XCTAssertNil(try coordinator(repository: InMemoryProjectRepository()).lastSavedProject())
    }

    func testSingleProjectReturnsThatProject() throws {
        let repository = InMemoryProjectRepository()
        let project = try makeProject(createdAt: Date(timeIntervalSince1970: 100))
        try repository.create(project)
        XCTAssertEqual(try coordinator(repository: repository).lastSavedProject()?.id, project.id)
    }

    func testMultipleProjectsReturnsMostRecentByCanonicalOrdering() throws {
        let repository = InMemoryProjectRepository()
        let older = try makeProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
        let newer = try makeProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 500))
        try repository.create(older)
        try repository.create(newer)
        XCTAssertEqual(try coordinator(repository: repository).lastSavedProject()?.id, newer.id)
    }

    func testLookupDoesNotDeleteOrMutateProjects() throws {
        let repository = InMemoryProjectRepository()
        let a = try makeProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
        let b = try makeProject(createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 500))
        try repository.create(a)
        try repository.create(b)
        let coordinator = coordinator(repository: repository)
        _ = try coordinator.lastSavedProject()
        _ = try coordinator.lastSavedProject()
        XCTAssertEqual(Set(try repository.recentProjects().map(\.id)), [a.id, b.id])
    }

    // MARK: - Fresh composition

    func testFreshCommitCreatesPortraitProjectWithOrderedClipsAndOwnedMedia() async throws {
        let repository = InMemoryProjectRepository()
        let coordinator = coordinator(repository: repository)
        let two = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let three = try await TestMediaFixtures.shared.portrait(seconds: 3)
        let workspace = try await store.beginWorkspace()
        let selected = try await sources([two, three], in: workspace)
        XCTAssertTrue(try repository.recentProjects().isEmpty, "nothing exists before commit")

        let outcome = await coordinator.compose(.fresh, sources: selected, workspace: workspace)
        guard case .committed(let projectID) = outcome else { return XCTFail("\(outcome)") }

        let project = try XCTUnwrap(repository.project(id: projectID))
        XCTAssertEqual(project.orientation, .portrait9x16)
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1])
        XCTAssertEqual(project.clips.map(\.sourceKind), [.imported, .imported])
        XCTAssertEqual(project.clips.map { Double($0.effectiveDuration.value) / Double($0.effectiveDuration.timescale) }.map { ($0 * 10).rounded() / 10 }, [2, 3])
        XCTAssertEqual(project.clips.map(\.trimStart), [.zero, .zero])
        XCTAssertTrue(project.clips.allSatisfy { $0.framing == nil })
        for clip in project.clips {
            XCTAssertTrue(clip.mediaRelativePath.value.hasPrefix("Projects/\(projectID.uuidString)/Media/"))
            await assertFileExists(store, clip.mediaRelativePath, true, "Project-owned copy exists")
        }
        XCTAssertFalse(TestSupport.exists(workspace.directory), "operation workspace cleaned")
        XCTAssertTrue(TestSupport.exists(two) && TestSupport.exists(three), "external sources untouched")
        XCTAssertEqual(try coordinator.lastSavedProject()?.id, projectID, "B is the current saved Project")
    }

    func testFreshCommitPersistsAcrossFreshSwiftDataContainer() async throws {
        let storeURL = TestSupport.temporaryRoot("swiftdata").appendingPathComponent("store.sqlite")
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        let container = try MellowModelContainer.makePersistentContainer(storeURL: storeURL)
        let repository = SwiftDataProjectRepository(modelContext: ModelContext(container))
        let coordinator = coordinator(repository: repository)
        let workspace = try await store.beginWorkspace()
        let selected = try await sources([try await TestMediaFixtures.shared.portrait(seconds: 2)], in: workspace)
        guard case .committed(let projectID) = await coordinator.compose(.fresh, sources: selected, workspace: workspace) else { return XCTFail() }

        let reopened = SwiftDataProjectRepository(modelContext: ModelContext(try MellowModelContainer.makePersistentContainer(storeURL: storeURL)))
        let project = try XCTUnwrap(reopened.project(id: projectID))
        XCTAssertEqual(project.clips.count, 1)
        await assertFileExists(store, project.clips[0].mediaRelativePath, true)
    }

    func testEmptySelectionCreatesNothing() async throws {
        let repository = InMemoryProjectRepository()
        let workspace = try await store.beginWorkspace()
        let outcome = await coordinator(repository: repository).compose(.fresh, sources: [], workspace: workspace)
        XCTAssertEqual(outcome, .failed(.noSources))
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        XCTAssertFalse(TestSupport.exists(workspace.directory))
    }

    func testRequiresPreparationCreatesNothingAllOrNothing() async throws {
        let repository = InMemoryProjectRepository()
        let coordinator = coordinator(repository: repository)
        let ready = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let long = try await TestMediaFixtures.shared.portrait(seconds: 7)
        let workspace = try await store.beginWorkspace()
        let selected = try await sources([ready, long], in: workspace)
        let outcome1 = await coordinator.compose(.fresh, sources: selected, workspace: workspace)
        XCTAssertEqual(outcome1, .requiresImportPreparation(.tooLong))
        XCTAssertTrue(try repository.recentProjects().isEmpty, "a ready + non-ready selection commits nothing")
        XCTAssertTrue(TestSupport.noProjectMedia(under: root), "no Project-owned media written")
        XCTAssertFalse(TestSupport.exists(workspace.directory))
    }

    func testInvalidMediaCreatesNothing() async throws {
        let repository = InMemoryProjectRepository()
        let workspace = try await store.beginWorkspace()
        let selected = try await sources([try await TestMediaFixtures.shared.corrupt()], in: workspace)
        let outcome = await coordinator(repository: repository).compose(.fresh, sources: selected, workspace: workspace)
        guard case .invalidMedia = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        XCTAssertFalse(TestSupport.exists(workspace.directory))
    }

    func testMaterializationFailureCreatesNothing() async throws {
        let repository = InMemoryProjectRepository()
        let workspace = try await store.beginWorkspace()
        let selected = try await sources([try await TestMediaFixtures.shared.portrait(seconds: 2)], in: workspace)
        // Validation passes via a fake inspector, then the workspace file is gone at materialization.
        try FileManager.default.removeItem(at: selected[0].url)
        let outcome = await coordinator(repository: repository, inspector: FakeProjectMediaInspector(.ready())).compose(.fresh, sources: selected, workspace: workspace)
        XCTAssertEqual(outcome, .failed(.materialization))
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        XCTAssertTrue(TestSupport.noProjectMedia(under: root))
    }

    func testPersistenceFailureCommitsNothingAndCleansMedia() async throws {
        let repository = FailableProjectRepository()
        repository.createFails = true
        let workspace = try await store.beginWorkspace()
        let selected = try await sources([try await TestMediaFixtures.shared.portrait(seconds: 2)], in: workspace)
        let outcome = await coordinator(repository: repository).compose(.fresh, sources: selected, workspace: workspace)
        XCTAssertEqual(outcome, .failed(.persistence))
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        XCTAssertTrue(TestSupport.noProjectMedia(under: root), "materialized B media removed after failed persist")
        XCTAssertFalse(TestSupport.exists(workspace.directory))
    }

    func testStorageGateBlocksBeforeAnyWrite() async throws {
        let repository = InMemoryProjectRepository()
        let workspace = try await store.beginWorkspace()
        let selected = try await sources([try await TestMediaFixtures.shared.portrait(seconds: 2)], in: workspace)
        let outcome = await coordinator(repository: repository, storage: .insufficient(requiredBytes: 1, usableBytes: 0)).compose(.fresh, sources: selected, workspace: workspace)
        XCTAssertEqual(outcome, .insufficientStorage)
        XCTAssertTrue(try repository.recentProjects().isEmpty)
        XCTAssertTrue(TestSupport.noProjectMedia(under: root))
        XCTAssertFalse(TestSupport.exists(workspace.directory), "disposable workspace cleaned; retry possible")
    }

    /// The gate runs after the sources were adopted onto the checked volume and promotion is a rename,
    /// so a volume holding exactly the Safety Reserve must pass regardless of the adopted byte size.
    func testVolumeGateDoesNotDoubleCountAdoptedWorkspaceBytes() async throws {
        let repository = InMemoryProjectRepository()
        let workspace = try await store.beginWorkspace()
        let selected = try await sources([try await TestMediaFixtures.shared.portrait(seconds: 3)], in: workspace)
        XCTAssertGreaterThan(selected[0].byteCount, 0, "real adopted bytes on disk")
        let reserve = ProjectCompositionPolicy.materializationSafetyReserveBytes

        let exactlyReserve = VolumeProjectStorageGate(capacity: { reserve }, safetyReserveBytes: reserve)
        let passing = ProjectCompositionCoordinator(repository: repository, mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()), storage: exactlyReserve, lifecycle: ProjectLifecycleOperationGate())
        guard case .committed = await passing.compose(.fresh, sources: selected, workspace: workspace) else {
            return XCTFail("usable == reserve must pass: adopted bytes are not re-counted")
        }

        let oneShort = VolumeProjectStorageGate(capacity: { reserve - 1 }, safetyReserveBytes: reserve)
        let workspace2 = try await store.beginWorkspace()
        let selected2 = try await sources([try await TestMediaFixtures.shared.portrait(seconds: 2)], in: workspace2)
        let refusing = ProjectCompositionCoordinator(repository: InMemoryProjectRepository(), mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()), storage: oneShort, lifecycle: ProjectLifecycleOperationGate())
        let outcome = await refusing.compose(.fresh, sources: selected2, workspace: workspace2)
        XCTAssertEqual(outcome, .insufficientStorage)
    }

    // MARK: - Safe Atomic Replacement

    func testReplacementFailuresLeaveProjectAIntact() async throws {
        let repository = FailableProjectRepository()
        let (a, aMedia) = try await seedSavedProject(in: repository)
        let external = try await TestMediaFixtures.shared.portrait(seconds: 2)

        func assertAIntact(_ label: String) async throws {
            XCTAssertEqual(try repository.recentProjects().map(\.id), [a.id], label)
            XCTAssertEqual(try repository.project(id: a.id)?.clips.count, 1, label)
            await assertFileExists(store, aMedia, true, "\(label): A media intact")
            XCTAssertTrue(TestSupport.exists(external), "\(label): external source intact")
        }

        // requiresImportPreparation
        var workspace = try await store.beginWorkspace()
        var selected = try await sources([try await TestMediaFixtures.shared.portrait(seconds: 7)], in: workspace)
        let outcome4 = await coordinator(repository: repository).compose(.replacingSaved(a.id), sources: selected, workspace: workspace)
        XCTAssertEqual(outcome4, .requiresImportPreparation(.tooLong))
        try await assertAIntact("preparation")

        // invalid media
        workspace = try await store.beginWorkspace()
        selected = try await sources([try await TestMediaFixtures.shared.corrupt()], in: workspace)
        guard case .invalidMedia = await coordinator(repository: repository).compose(.replacingSaved(a.id), sources: selected, workspace: workspace) else { return XCTFail() }
        try await assertAIntact("invalid")

        // B materialization failure
        workspace = try await store.beginWorkspace()
        selected = try await sources([external], in: workspace)
        try FileManager.default.removeItem(at: selected[0].url)
        let outcome5 = await coordinator(repository: repository, inspector: FakeProjectMediaInspector(.ready())).compose(.replacingSaved(a.id), sources: selected, workspace: workspace)
        XCTAssertEqual(outcome5, .failed(.materialization))
        try await assertAIntact("materialization")

        // B persistence failure
        repository.createFails = true
        workspace = try await store.beginWorkspace()
        selected = try await sources([external], in: workspace)
        let outcome6 = await coordinator(repository: repository).compose(.replacingSaved(a.id), sources: selected, workspace: workspace)
        XCTAssertEqual(outcome6, .failed(.persistence))
        try await assertAIntact("persistence")
        XCTAssertTrue(repository.deletedIDs.isEmpty, "A is never deleted on any failure path")

        // storage
        repository.createFails = false
        workspace = try await store.beginWorkspace()
        selected = try await sources([external], in: workspace)
        let outcome7 = await coordinator(repository: repository, storage: .insufficient(requiredBytes: 1, usableBytes: 0)).compose(.replacingSaved(a.id), sources: selected, workspace: workspace)
        XCTAssertEqual(outcome7, .insufficientStorage)
        try await assertAIntact("storage")
        XCTAssertFalse(TestSupport.exists(root.appendingPathComponent("ProjectWorkspace")) && !((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("ProjectWorkspace").path))?.isEmpty ?? true), "no workspace left behind")
    }

    func testSuccessfulReplacementPromotesBThenRemovesAOnly() async throws {
        let repository = FailableProjectRepository()
        let (a, aMedia) = try await seedSavedProject(in: repository)
        let external = try await TestMediaFixtures.shared.portrait(seconds: 3)
        let workspace = try await store.beginWorkspace()
        let selected = try await sources([external], in: workspace)

        let outcome = await coordinator(repository: repository).compose(.replacingSaved(a.id), sources: selected, workspace: workspace)
        guard case .committed(let bID) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertNotEqual(bID, a.id)
        XCTAssertEqual(try repository.recentProjects().map(\.id), [bID], "B is the only saved Project")
        XCTAssertNil(try repository.project(id: a.id))
        XCTAssertEqual(repository.deletedIDs, [a.id], "A removed exactly once, after B")
        await assertFileExists(store, aMedia, false, "A app-owned media cleaned up")
        let b = try XCTUnwrap(repository.project(id: bID))
        await assertFileExists(store, b.clips[0].mediaRelativePath, true)
        XCTAssertTrue(TestSupport.exists(external), "the user's original is never touched")
        XCTAssertFalse(TestSupport.exists(workspace.directory))
    }

    func testReplacementOrderIsBCommittedBeforeADeleted() async throws {
        // If deleting A fails, B still stands as the committed saved Project (A was never deleted first).
        let repository = FailableProjectRepository()
        let (a, _) = try await seedSavedProject(in: repository)
        repository.deleteFails = true
        let workspace = try await store.beginWorkspace()
        let selected = try await sources([try await TestMediaFixtures.shared.portrait(seconds: 2)], in: workspace)
        guard case .committed(let bID) = await coordinator(repository: repository).compose(.replacingSaved(a.id), sources: selected, workspace: workspace) else { return XCTFail() }
        XCTAssertNotNil(try repository.project(id: bID))
        XCTAssertNotNil(try repository.project(id: a.id), "A survives a failed cleanup rather than being destroyed first")
        XCTAssertEqual(try coordinator(repository: repository).lastSavedProject()?.id, bID, "B is current by recency")
    }
}
