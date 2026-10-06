import Foundation
import SwiftData
import XCTest
@testable import Mellow

/// Phase 6 Select Clips on the Projects screen (ADR-042 R2–R4, ADR-043 R1, ADR-050 050-C / 050-D D7a / D7b / D8.5b):
/// fake selection of real fixture files → real preflight → the internal coordinator + Retry controller → presentation.
/// Isolated SwiftData store and media root; the normalizer and capacity are controlled doubles (outputs are
/// placeholder bytes, so media decoding is not under test here). Never a device store, never private media.
@MainActor
final class SelectClipsImportFlowTests: XCTestCase {
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
    private var committed: [UUID] = []
    private var routeLive = true
    private var legacyGuard: ScriptedCapacityGate!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "MellowSelectClipsFlow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = try MellowModelContainer.makePersistentContainer(storeURL: directory.appending(path: "metadata.store"))
        swiftData = SwiftDataProjectRepository(modelContext: container.mainContext)
        repository = FailableProjectRepository(inner: swiftData)
        root = TestSupport.temporaryRoot("select-clips-flow")
        store = ProjectMediaStore(root: root)
        gate = ProjectLifecycleOperationGate()
        normalizer = NormalizerScript()
        capacity = CapacityScript()
        committed = []
        routeLive = true
        // The legacy commit-time final guard: would refuse everything, so any use of it on this path would show.
        legacyGuard = ScriptedCapacityGate(capacities: [0, 0, 0, 0])
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SelectClipsFlow-\(name)-\(UUID().uuidString)").appendingPathExtension("mov")
        try await FixtureVideoWriter.write(to: url, seconds: seconds, fps: fps)
        return url
    }

    private func makeModel(_ fixtures: [URL]) -> ProjectsEntryModel {
        let capacity = self.capacity!
        let coordinator = ImportAttemptCoordinator(repository: repository, mediaStore: store, normalizer: FakeNormalizer(script: normalizer),
                                                   lifecycle: gate, capacity: { await capacity.next() })
        let model = ProjectsEntryModel(
            composition: ProjectCompositionCoordinator(repository: repository, mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()),
                                                       storage: legacyGuard, lifecycle: gate),
            mediaStore: store,
            mediaSelector: FakeProjectMediaSelector(script: .fixtures(fixtures)),
            storageGate: FakeProjectStorageGate(verdict: .sufficient),
            importServices: ImportFlowServices(store: store, preflight: ImportSelectionPreflight(inspector: AVAssetImportSourceInspector()), attempts: coordinator),
            routeProbe: { [unowned self] in { self.routeLive } },
            onContinueEditing: { _ in },
            onProjectCommitted: { [unowned self] id in self.committed.append(id) })
        model.load()
        return model
    }

    private func eventually(_ timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock(), deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await clock.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func savedProjects() throws -> [VlogProject] { try swiftData.recentProjects() }
    private func workspaceCount() -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("ProjectWorkspace").path)) ?? []).count
    }

    // MARK: - Classification, filtering and ordering

    func testFixturesClassifyAsReadyAndNormalizationRequired() async throws {
        let inspector = AVAssetImportSourceInspector()
        let ready = try await inspector.inspect(url: try await fixture("ready", seconds: 2))
        let fast = try await inspector.inspect(url: try await fixture("fast", seconds: 2, fps: 60))
        guard case .readyFastPath = ImportPreflightClassifier.classify(ready) else { return XCTFail("\(ImportPreflightClassifier.classify(ready))") }
        guard case .normalizationRequired = ImportPreflightClassifier.classify(fast) else { return XCTFail("\(ImportPreflightClassifier.classify(fast))") }
    }

    func testInclusiveDurationBoundariesAreAccepted() async throws {
        let model = makeModel([try await fixture("one", seconds: 1), try await fixture("five", seconds: 5)])
        await model.runSelectClips(.fresh)
        XCTAssertNil(model.compositionMessage, "\(String(describing: model.compositionMessage))")
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(try savedProjects().first?.clips.count, 2, "exactly 1.0 s and 5.0 s are eligible")
    }

    func testReadyOnlySetCommitsWithoutSheetOrNormalizationAndSkipsTheLegacyGuard() async throws {
        let model = makeModel([try await fixture("a", seconds: 2), try await fixture("b", seconds: 3)])
        await model.runSelectClips(.fresh)
        XCTAssertNil(model.preparation)
        XCTAssertEqual(committed.count, 1)
        let calls = await normalizer.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(legacyGuard.checks.isEmpty, "the Select Clips final guard is retired on the Phase 6 path")
        XCTAssertEqual(workspaceCount(), 0, "the workspace is released after success")
        XCTAssertFalse(model.isComposing)
    }

    func testMixedSetShowsSheetWithRealProgressAndKeepsAcceptedOrder() async throws {
        let fixtures = [try await fixture("ready", seconds: 2), try await fixture("n1", seconds: 2, fps: 60), try await fixture("n2", seconds: 1.5, fps: 60)]
        let model = makeModel(fixtures)
        await normalizer.script([.park])
        let run = Task { await model.runSelectClips(.fresh) }
        await normalizer.waitUntilParked()
        XCTAssertEqual(model.preparation?.total, 2, "only normalization items count")
        XCTAssertEqual(model.preparation?.positionLabel, "1/2")
        XCTAssertTrue(model.isComposing)
        await normalizer.release()
        await run.value
        XCTAssertNil(model.preparation, "the sheet closes with the outcome")
        let project = try XCTUnwrap(try savedProjects().first)
        XCTAssertEqual(project.clips.count, 3)
        // Accepted Set order: ready 2 s, normalized 2 s, normalized 1.5 s (trim = accepted source duration).
        let trims = project.clips.map { Double($0.trimDuration.value) / Double($0.trimDuration.timescale) }
        XCTAssertEqual(trims[0], 2, accuracy: 0.05)
        XCTAssertEqual(trims[1], 2, accuracy: 0.05)
        XCTAssertEqual(trims[2], 1.5, accuracy: 0.05)
        XCTAssertEqual(committed, [project.id])
    }

    func testExcludedItemsGiveOneNoticeAfterSuccessThenNavigation() async throws {
        let model = makeModel([try await fixture("short", seconds: 0.5), try await fixture("ready", seconds: 2)])
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.compositionMessage, .selectionNotice(.shortItemsExcluded))
        XCTAssertTrue(committed.isEmpty, "navigation waits for the notice")
        XCTAssertEqual(try savedProjects().first?.clips.count, 1)
        model.dismissCompositionMessage()
        XCTAssertEqual(committed.count, 1)
    }

    func testAllExcludedCreatesNothing() async throws {
        let multi = makeModel([try await fixture("short", seconds: 0.5), try await fixture("long", seconds: 7)])
        await multi.runSelectClips(.fresh)
        XCTAssertEqual(multi.compositionMessage, .selectionNotice(.shortAndLongItemsExcluded))
        let single = makeModel([try await fixture("short1", seconds: 0.5)])
        await single.runSelectClips(.fresh)
        XCTAssertEqual(single.compositionMessage, .selectionNotice(.candidateBelowMinimum))
        XCTAssertTrue(try savedProjects().isEmpty)
        XCTAssertEqual(workspaceCount(), 0)
    }

    // MARK: - Cancellation, failure, Retry

    func testCancelFromTheSheetClosesSilentlyWithNothingCreated() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.park])
        let run = Task { await model.runSelectClips(.fresh) }
        await normalizer.waitUntilParked()
        model.cancelPreparation()
        XCTAssertTrue(model.isCancellingPreparation)
        await normalizer.release()
        await run.value
        XCTAssertNil(model.compositionMessage)
        XCTAssertNil(model.retryPrompt)
        XCTAssertFalse(model.isComposing)
        XCTAssertTrue(try savedProjects().isEmpty)
        XCTAssertEqual(workspaceCount(), 0)
    }

    func testRuntimeFailureOffersRetryWithFreshProgressThenSucceeds() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60), try await fixture("n2", seconds: 2, fps: 60)])
        await normalizer.script([.succeed(outputDuration: nil), .fail])
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.retryPrompt, .preparationFailed)
        XCTAssertTrue(model.isComposing, "Back stays hidden while the operation waits")
        await normalizer.script([.park])
        model.retryPreparation()
        await normalizer.waitUntilParked()
        XCTAssertEqual(model.preparation?.completed.count, 0, "progress resets for the new attempt")
        XCTAssertEqual(model.preparation?.positionLabel, "1/2")
        await normalizer.release()
        let settled = await eventually { self.committed.count == 1 }
        XCTAssertTrue(settled)
        XCTAssertEqual(try savedProjects().first?.clips.count, 2)
    }

    func testPriorConfirmedSaveIsRetriedNotAcknowledged() async throws {
        let model = makeModel([try await fixture("a", seconds: 2)])
        repository.createFails = true
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.retryPrompt, .preparationFailed, "D7a: R4 §3 with 다시 시도 replaces the P6 acknowledgement")
        repository.createFails = false
        model.retryPreparation()
        let settled = await eventually { self.committed.count == 1 }
        XCTAssertTrue(settled)
    }

    func testCancelOnTheRetryPromptEndsAndReleases() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.fail])
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.retryPrompt, .preparationFailed)
        model.cancelPreparation()
        // `isComposing` (Back / `기존 프로젝트 불러오기`) must be OBSERVED to change when the operation ends, not
        // merely readable: the view only re-renders on a tracked change.
        let observedChange = ObservedFlag()
        withObservationTracking { _ = model.isComposing } onChange: { observedChange.set() }
        let settled = await eventually { !model.isComposing }
        XCTAssertTrue(settled)
        XCTAssertTrue(observedChange.value, "the end of the operation notifies observers")
        XCTAssertNil(model.compositionMessage)
        XCTAssertEqual(workspaceCount(), 0)
    }

    func testStorageRoutesAndDefects() async throws {
        // C1 shortage → R4 §4 acknowledgement.
        let c1 = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await capacity.script([1])
        await c1.runSelectClips(.fresh)
        XCTAssertEqual(c1.compositionMessage, .importStorageInsufficient)
        // C2 shortage → R4 §3 Retry; then CR shortage → the CR prompt, still waiting.
        let c2 = makeModel([try await fixture("n2", seconds: 2, fps: 60), try await fixture("n3", seconds: 2, fps: 60)])
        await capacity.script([1 << 40, 1])
        await c2.runSelectClips(.fresh)
        XCTAssertEqual(c2.retryPrompt, .preparationFailed)
        await capacity.script([1])
        c2.retryPreparation()
        let settled = await eventually { c2.retryPrompt == .storageShortage }
        XCTAssertTrue(settled)
        XCTAssertTrue(c2.isComposing)
        c2.cancelPreparation()
        let settledAgain = await eventually { !c2.isComposing }
        XCTAssertTrue(settledAgain)
    }

    func testSaveOutcomesUseU1U2AndNeverRetry() async throws {
        let unverified = makeModel([try await fixture("a", seconds: 2)])
        repository.stateObservationOverride = { expectation, observed in
            PersistedStateObservation(projects: Dictionary(uniqueKeysWithValues: expectation.intended.keys.map { ($0, .unreadable) }),
                                      createdIdentityHolders: observed.createdIdentityHolders)
        }
        await unverified.runSelectClips(.fresh)
        XCTAssertEqual(unverified.compositionMessage, .saveUnverified)
        XCTAssertNil(unverified.retryPrompt)

        let indeterminate = makeModel([try await fixture("b", seconds: 2)])
        repository.createThrowsAfterCommit = true
        repository.stateObservationOverride = { _, observed in PersistedStateObservation(projects: observed.projects, createdIdentityHolders: nil) }
        await indeterminate.runSelectClips(.fresh)
        XCTAssertEqual(indeterminate.compositionMessage, .saveIndeterminate)
        XCTAssertFalse(indeterminate.isComposing)
    }

    func testUnresolvedCleanupShowsU3AndKeepsTheWorkspace() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.cleanupFailure(cancelled: false)])
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.compositionMessage, .cleanupUnresolved)
        XCTAssertNil(model.retryPrompt)
        XCTAssertEqual(workspaceCount(), 1, "retained for the process lifetime (D7a)")
    }

    // MARK: - Targets

    func testReplacementTargetDeletedMidAttemptIsTargetInvalid() async throws {
        let previous = try seedSavedProject()
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.park])
        let run = Task { await model.runSelectClips(.replacingSaved(previous.id)) }
        await normalizer.waitUntilParked()
        try swiftData.deleteProject(id: previous.id)
        await normalizer.release()
        await run.value
        XCTAssertEqual(model.compositionMessage, .replacementTargetInvalidated)
        XCTAssertTrue(try savedProjects().isEmpty, "B is never created alone")
    }

    func testUnreadableTargetMidAttemptWaitsThenRetrySucceeds() async throws {
        let previous = try seedSavedProject()
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.park])
        let run = Task { await model.runSelectClips(.replacingSaved(previous.id)) }
        await normalizer.waitUntilParked()
        repository.priorObservationOverride = { _ in .unreadable }
        await normalizer.release()
        await run.value
        XCTAssertEqual(model.retryPrompt, .targetUnavailable, "D7b §2")
        // Still unreadable at Retry admission → the same prompt, still waiting.
        model.retryPreparation()
        let settled = await eventually { model.retryPrompt == .targetUnavailable }
        XCTAssertTrue(settled)
        repository.priorObservationOverride = nil
        model.retryPreparation()
        let settledAgain = await eventually { self.committed.count == 1 }
        XCTAssertTrue(settledAgain)
        XCTAssertNil(try swiftData.project(id: previous.id), "A replaced")
    }

    func testFirstAdmissionUnreadableTargetUsesTheExistingInspectionCopy() async throws {
        let previous = try seedSavedProject()
        let model = makeModel([try await fixture("a", seconds: 2)])
        repository.priorObservationOverride = { _ in .unreadable }
        await model.runSelectClips(.replacingSaved(previous.id))
        XCTAssertEqual(model.compositionMessage, .projectInspectionFailed)
        XCTAssertNil(model.retryPrompt)
    }

    func testSourceInvalidBeforeRetryEndsWithTheApprovedCopy() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.fail])
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.retryPrompt, .preparationFailed)
        let workspaceDirectory = root.appendingPathComponent("ProjectWorkspace")
        let workspaceID = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: workspaceDirectory.path).first)
        for name in try FileManager.default.contentsOfDirectory(atPath: workspaceDirectory.appendingPathComponent(workspaceID).path) where name.hasSuffix(".mov") {
            try FileManager.default.removeItem(at: workspaceDirectory.appendingPathComponent(workspaceID).appendingPathComponent(name))
        }
        model.retryPreparation()
        let settled = await eventually { model.compositionMessage == .sourceUnavailableForRetry }
        XCTAssertTrue(settled)
        XCTAssertFalse(model.isComposing)
    }

    // MARK: - Late presentation

    func testRemovedRouteSuppressesLateUIButKeepsTheConfirmedSave() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.park])
        let run = Task { await model.runSelectClips(.fresh) }
        await normalizer.waitUntilParked()
        routeLive = false
        await normalizer.release()
        await run.value
        XCTAssertTrue(committed.isEmpty, "no late navigation")
        XCTAssertNil(model.compositionMessage)
        XCTAssertEqual(try savedProjects().count, 1, "the confirmed save is not undone")
        XCTAssertEqual(workspaceCount(), 0, "cleanup still completed")
    }

    // MARK: - Review follow-ups

    func testNormalizerProgressReachesTheSheetAndStaleAttemptsAreIgnored() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.failWithLateProgress])
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.retryPrompt, .preparationFailed)
        await normalizer.script([.park])
        model.retryPreparation()
        await normalizer.waitUntilParked()
        let shown = await eventually { model.preparation?.currentFraction == 0.5 }
        XCTAssertTrue(shown, "the parked item's real progress callback reached the sheet")
        await normalizer.fireLateProgress(0.9)              // the first attempt's stale callback, delivered mid-Retry
        let fired = await normalizer.lateProgressFired
        XCTAssertTrue(fired)
        try await Task.sleep(for: .milliseconds(200))       // let its main-actor hop run
        XCTAssertNotNil(model.preparation, "the Retry's sheet is up while the stale value arrives")
        XCTAssertEqual(model.preparation?.currentFraction, 0.5, "a stale attempt's callback never moves the Retry's progress")
        XCTAssertEqual(model.preparation?.aggregate ?? -1, 0.5, accuracy: 1e-9)
        await normalizer.release()
        let done = await eventually { self.committed.count == 1 }
        XCTAssertTrue(done)
    }

    func testRealNormalizerReportsBoundedProgressToCompletion() async throws {
        let url = try await fixture("real", seconds: 1, fps: 60)
        let outcome = try await ImportSelectionPreflight(inspector: AVAssetImportSourceInspector()).run([ImportCandidate(url: url)], context: .singleCandidate)
        let item = try XCTUnwrap(outcome.accepted.first)
        let plan = try WorkingMediaPlanBuilder.plan(for: item)
        let count = try XCTUnwrap(WorkingMediaProgress.targetCount(plan: plan))
        final class Collector: @unchecked Sendable { let lock = NSLock(); var values: [Double] = [] }
        let collector = Collector()
        let destinationDirectory = root.appendingPathComponent("real-normalize", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        _ = try await AVFoundationWorkingMediaNormalizer().normalize(sourceURL: url, destinationURL: destinationDirectory.appendingPathComponent("out.mov"), plan: plan,
                                                                      progress: { value in collector.lock.lock(); collector.values.append(value); collector.lock.unlock() })
        XCTAssertEqual(collector.values.count, count, "one callback per cadence target written")
        XCTAssertEqual(collector.values, collector.values.sorted(), "monotonic")
        XCTAssertTrue(collector.values.allSatisfy { (0...1).contains($0) })
        XCTAssertEqual(collector.values.last, 1)
    }

    func testOpeningTheSavedProjectIsBlockedWhileAnOperationRuns() async throws {
        let previous = try seedSavedProject()
        var opened: [UUID] = []
        let capacity = self.capacity!
        let coordinator = ImportAttemptCoordinator(repository: repository, mediaStore: store, normalizer: FakeNormalizer(script: normalizer),
                                                   lifecycle: gate, capacity: { await capacity.next() })
        let model = ProjectsEntryModel(
            composition: ProjectCompositionCoordinator(repository: repository, mediaStore: store, validator: Phase5ReadyMediaValidator(inspector: AVAssetProjectMediaInspector()),
                                                       storage: legacyGuard, lifecycle: gate),
            mediaStore: store, mediaSelector: FakeProjectMediaSelector(script: .fixtures([try await fixture("n1", seconds: 2, fps: 60)])),
            storageGate: FakeProjectStorageGate(verdict: .sufficient),
            importServices: ImportFlowServices(store: store, preflight: ImportSelectionPreflight(inspector: AVAssetImportSourceInspector()), attempts: coordinator),
            onContinueEditing: { opened.append($0) }, onProjectCommitted: { _ in })
        model.load()
        await normalizer.script([.park])
        let run = Task { await model.runSelectClips(.replacingSaved(previous.id)) }
        await normalizer.waitUntilParked()
        model.continueEditing()
        XCTAssertTrue(opened.isEmpty, "A's Editor never opens while A is being replaced")
        await normalizer.release()
        await run.value
    }

    func testDoubleRetryTapStartsOneAttempt() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.fail])
        await model.runSelectClips(.fresh)
        await normalizer.script([.park])
        model.retryPreparation()
        model.retryPreparation()
        await normalizer.waitUntilParked()
        XCTAssertNotNil(model.preparation, "the second tap did not hide the sheet")
        await normalizer.release()
        let done = await eventually { self.committed.count == 1 }
        XCTAssertTrue(done)
        let calls = await normalizer.calls
        XCTAssertEqual(calls.count, 2, "first attempt + exactly one Retry")
    }

    // MARK: - D7b §4 clarification: originating route removal

    func testRouteRemovedWhileAwaitingRetryEndsTheWaitAndReleasesTheBlock() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.fail])
        await model.runSelectClips(.fresh)
        XCTAssertEqual(model.retryPrompt, .preparationFailed)
        XCTAssertTrue(model.isComposing)
        routeLive = false
        model.originatingRouteRemoved()
        model.originatingRouteRemoved()                      // repeated notifications are no-ops
        let released = await eventually { !model.isComposing }
        XCTAssertTrue(released, "Projects is not blocked until relaunch")
        XCTAssertNil(model.retryPrompt)
        XCTAssertNil(model.compositionMessage, "no late alert")
        XCTAssertEqual(workspaceCount(), 0, "the verified wait ended through the controller's cleanup")
        let calls = await normalizer.calls
        XCTAssertEqual(calls.count, 1, "no automatic Retry")
    }

    func testRouteRemovedRightAfterARetryTapNeverStartsThatAttempt() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        await normalizer.script([.fail])
        await model.runSelectClips(.fresh)
        model.retryPreparation()                             // queued, not started yet
        routeLive = false
        model.originatingRouteRemoved()
        let released = await eventually { !model.isComposing }
        XCTAssertTrue(released)
        try await Task.sleep(for: .milliseconds(200))
        let calls = await normalizer.calls
        XCTAssertEqual(calls.count, 1, "the queued Retry never ran, so removal cancelled no running attempt")
        XCTAssertNil(model.preparation)
        XCTAssertEqual(workspaceCount(), 0)
    }

    func testRouteRemovedDuringAnAttemptThatBecomesRetryableEndsSafely() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60), try await fixture("n2", seconds: 2, fps: 60)])
        await normalizer.script([.park, .fail])
        let run = Task { await model.runSelectClips(.fresh) }
        await normalizer.waitUntilParked()
        routeLive = false
        model.originatingRouteRemoved()                      // a running attempt is never cancelled by this
        XCTAssertTrue(model.isComposing)
        await normalizer.release()
        await run.value
        let released = await eventually { !model.isComposing }
        XCTAssertTrue(released)
        XCTAssertNil(model.retryPrompt, "no inaccessible Retry wait")
        XCTAssertNil(model.compositionMessage)
        XCTAssertTrue(try savedProjects().isEmpty)
        XCTAssertEqual(workspaceCount(), 0)
        let calls = await normalizer.calls
        XCTAssertEqual(calls.count, 2, "the running attempt finished; nothing was retried")
    }

    func testUncertainSaveAfterRouteRemovalKeepsMediaAndReleasesTheBlock() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        repository.stateObservationOverride = { expectation, observed in
            PersistedStateObservation(projects: Dictionary(uniqueKeysWithValues: expectation.intended.keys.map { ($0, .unreadable) }),
                                      createdIdentityHolders: observed.createdIdentityHolders)
        }
        await normalizer.script([.park])
        let run = Task { await model.runSelectClips(.fresh) }
        await normalizer.waitUntilParked()
        routeLive = false
        await normalizer.release()
        await run.value
        XCTAssertFalse(model.isComposing)
        XCTAssertNil(model.compositionMessage, "no late U1")
        let media = (try? FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent("Projects").path)) ?? []
        XCTAssertFalse(media.filter { $0.hasSuffix(".mov") }.isEmpty, "potentially referenced media is preserved")
        XCTAssertEqual(try savedProjects().count, 1, "nothing is rolled back")
    }

    func testUnresolvedCleanupAfterRouteRemovalKeepsEvidenceAndReleasesTheBlock() async throws {
        let model = makeModel([try await fixture("n1", seconds: 2, fps: 60)])
        routeLive = false
        await normalizer.script([.cleanupFailure(cancelled: false)])
        await model.runSelectClips(.fresh)
        model.originatingRouteRemoved()
        XCTAssertFalse(model.isComposing, "the block is released after terminal processing")
        XCTAssertNil(model.compositionMessage, "no late U3")
        XCTAssertEqual(workspaceCount(), 1, "retained evidence is never released by route removal")
    }

    func testRouterReportsOnlyRealProjectsRouteRemoval() {
        let router = AppRouter()
        var removals = 0
        router.onProjectsEntryRouteRemoved = { removals += 1 }
        router.path = [.projectsEntry]
        let probe = router.projectsEntryRouteProbe()
        // Pushing the Editor (or presenting a picker / sheet, which never touches the path) is not removal.
        router.path.append(.projectEditor(UUID()))
        XCTAssertTrue(probe())
        XCTAssertEqual(removals, 0)
        router.path.removeLast()
        XCTAssertTrue(probe())
        // Removing the Projects route ends that identity, once.
        router.path = []
        XCTAssertFalse(probe())
        XCTAssertEqual(removals, 1)
        // A new Projects route is a new identity: the old operation's probe stays dead.
        router.path = [.projectsEntry]
        XCTAssertFalse(probe())
        XCTAssertTrue(router.projectsEntryRouteProbe()())
    }

    private func seedSavedProject() throws -> VlogProject {
        let projectID = UUID(), clipID = UUID()
        let path = try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID)
        let url = root.appendingPathComponent(path.value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: url)
        let date = Date(timeIntervalSince1970: 500)
        let project = try VlogProject(id: projectID, createdAt: date, updatedAt: date, orientation: .portrait9x16, clips: [
            try VlogClip(id: clipID, projectID: projectID, sourceKind: .imported, mediaRelativePath: path, createdAt: date,
                         sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: 0)])
        try swiftData.create(project)
        return project
    }
}

/// A flag set from an Observation `onChange` callback.
final class ObservedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}
