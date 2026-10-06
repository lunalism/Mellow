import Foundation
import SwiftData
import XCTest
@testable import Mellow

/// ADR-050 050-D D7a same-set Retry (internal, unwired) over the real `ImportAttemptCoordinator` on an isolated
/// SwiftData store and media root. Normalizer, capacity and materialization faults reuse the coordinator suite's
/// controlled doubles; accepted items come from the real preflight over scripted facts.
@MainActor
final class ImportRetryControllerTests: XCTestCase {
    private typealias NormalizerScript = ImportAttemptCoordinatorTests.NormalizerScript
    private typealias FakeNormalizer = ImportAttemptCoordinatorTests.FakeNormalizer
    private typealias CapacityScript = ImportAttemptCoordinatorTests.CapacityScript
    private typealias FaultyAttemptStore = ImportAttemptCoordinatorTests.FaultyAttemptStore
    private typealias Spec = ImportAttemptCoordinatorTests.Spec

    private var directory: URL!
    private var container: ModelContainer!
    private var swiftData: SwiftDataProjectRepository!
    private var repository: FailableProjectRepository!
    private var root: URL!
    private var store: ProjectMediaStore!
    private var faulty: FaultyAttemptStore!
    private var gate: ProjectLifecycleOperationGate!
    private var normalizer: NormalizerScript!
    private var capacity: CapacityScript!
    private var workspace: ProjectMediaWorkspace!
    private var events: [ImportAttemptEvent] = []

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "MellowImportRetry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = try MellowModelContainer.makePersistentContainer(storeURL: directory.appending(path: "metadata.store"))
        swiftData = SwiftDataProjectRepository(modelContext: container.mainContext)
        repository = FailableProjectRepository(inner: swiftData)
        root = TestSupport.temporaryRoot("import-retry")
        store = ProjectMediaStore(root: root)
        faulty = FaultyAttemptStore(inner: store)
        gate = ProjectLifecycleOperationGate()
        normalizer = NormalizerScript()
        capacity = CapacityScript()
        workspace = try await store.beginWorkspace()
        events = []
    }

    override func tearDown() async throws {
        if let store, let workspace { await store.discard(workspace) }
        repository = nil
        swiftData = nil
        container = nil
        try? FileManager.default.removeItem(at: directory)
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - Fixtures

    private actor ScriptedInspector: ImportSourceInspecting {
        private var facts: [URL: ImportSourceFacts] = [:]
        func set(_ value: ImportSourceFacts, for url: URL) { facts[url] = value }
        func inspect(url: URL) async throws -> ImportSourceFacts {
            guard let value = facts[url] else { throw ImportInspectionError.sourceMissing }
            return value
        }
    }

    private func request(_ specs: [Spec], target: ImportAttemptTarget = .newProject) async throws -> ImportAttemptRequest {
        let inspector = ScriptedInspector()
        var candidates: [ImportCandidate] = []
        for (index, spec) in specs.enumerated() {
            let size = spec.bytes + index
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            try Data(repeating: UInt8(index + 1), count: size).write(to: temp)
            let adopted = try await store.adopt(temp, into: workspace)
            await inspector.set(ImportAttemptCoordinatorTests.makeFacts(value: spec.seconds600, timescale: 600, fps: spec.kind == .ready ? 30 : 60,
                                                                        byteCount: Int64(size)), for: adopted)
            candidates.append(ImportCandidate(url: adopted))
        }
        let outcome = try await ImportSelectionPreflight(inspector: inspector).run(candidates, context: .multipleItems)
        XCTAssertTrue(outcome.excluded.isEmpty)
        var plans: [ImportCandidateID: WorkingMediaNormalizationPlan] = [:]
        for item in outcome.accepted where item.preparationPath.normalization != nil { plans[item.candidate.id] = try WorkingMediaPlanBuilder.plan(for: item) }
        return ImportAttemptRequest(accepted: outcome.accepted, plans: plans, workspace: workspace, target: target)
    }

    /// Counts lifecycle-gate acquisitions by observing that the gate is free whenever an attempt starts.
    private func controller(_ request: ImportAttemptRequest, faultyStore: Bool = false,
                            capacityReader: ImportAttemptCoordinator.CapacityReader? = nil) -> ImportRetryController {
        let capacity = self.capacity!
        let coordinator = ImportAttemptCoordinator(repository: repository, mediaStore: faultyStore ? faulty : store,
                                                   normalizer: FakeNormalizer(script: normalizer), lifecycle: gate,
                                                   capacity: capacityReader ?? { await capacity.next() })
        return ImportRetryController(coordinator: coordinator, workspaces: store, request: request)
    }

    private func seed(clips count: Int = 1, updatedAt seconds: TimeInterval = 500) async throws -> VlogProject {
        let projectID = UUID()
        let date = Date(timeIntervalSince1970: seconds)
        var clips: [VlogClip] = []
        for index in 0..<count {
            let path = try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: UUID())
            let url = root.appendingPathComponent(path.value)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0x5A, count: 500).write(to: url)
            clips.append(try VlogClip(id: UUID(uuidString: url.deletingPathExtension().lastPathComponent)!, projectID: projectID, sourceKind: .imported,
                                      mediaRelativePath: path, createdAt: date, sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: index))
        }
        let project = try VlogProject(id: projectID, createdAt: date, updatedAt: date, orientation: .portrait9x16, clips: clips)
        try swiftData.create(project)
        return project
    }

    private func workspaceIsLive() -> Bool { FileManager.default.fileExists(atPath: workspace.directory.path) }
    private func attemptDirectories() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: workspace.directory.path)) ?? []).filter { $0.hasPrefix("attempt-") }
    }

    private func requirement(output: Int64 = 0, metadata: Int64 = 0) throws -> ImportStorageRequirement {
        try ImportStorageEstimator.requirement(outputBytes: output, metadataBytes: metadata)
    }

    private func clean(_ cancelled: Bool = false) -> ImportAttemptRollback {
        ImportAttemptRollback(result: .verifiedClean(records: [:]), retainedSources: [], cancellationRequested: cancelled)
    }

    private var unresolved: ImportAttemptRollback {
        ImportAttemptRollback(result: .unresolved(records: [:], attemptDirectory: .removalFailed), retainedSources: [], cancellationRequested: false)
    }

    // MARK: - Pure eligibility (owner-approved 2026-10-06)

    func testEveryEligibilityCategory() throws {
        let id = ImportCandidateID()
        let short = try requirement(output: 10)
        func storage(_ boundary: ImportAttemptBoundary, _ outcome: ImportBoundaryCheckOutcome) -> ImportBoundaryCheckResult {
            ImportBoundaryCheckResult(boundary: boundary, outcome: outcome)
        }
        let eligible: [ImportAttemptOutcome] = [
            .notSaved(clean()),
            .failedBeforeSave(.storage(storage(.c2BeforeNormalizationItem, .insufficient(short, usableBytes: 1))), clean()),
            .failedBeforeSave(.storage(storage(.c3BeforeMaterialization, .insufficient(short, usableBytes: 1))), clean()),
            .failedBeforeSave(.storage(storage(.c3BeforeMaterialization, .capacityUnknown(short))), clean()),
            .failedBeforeSave(.normalizationFailed(id, .writerFailed(domain: "d", code: 1)), clean()),
            .failedBeforeSave(.normalizationFailed(id, nil), clean()),
            .failedBeforeSave(.normalizationResultRejected(id), clean()),
            .failedBeforeSave(.materializationFailed(id), clean()),
            .failedBeforeSave(.mediaVerificationFailed, clean()),
            .failedBeforeSave(.attemptDirectoryUnavailable, clean()),
        ]
        for outcome in eligible { XCTAssertEqual(ImportRetryEligibility.evaluate(outcome), .eligible, "\(outcome)") }

        let commit = ImportAttemptCommit(project: try VlogProject(orientation: .portrait9x16), clipIDs: [], saveThrew: false, replacedProjectMediaRemoved: false)
        let preserved = ImportAttemptPreservedMedia(projectID: UUID(), mediaPaths: [])
        let cleanupFailed = WorkingMediaNormalizationError.cleanupFailed(.stillExists(path: "x"), precedingError: nil, cancelled: false)
        let ineligible: [(ImportAttemptOutcome, ImportRetryIneligibility)] = [
            (.completed(commit), .completed),
            (.committedUnverified(preserved, .unreadable), .uncertainPersistence),
            (.indeterminate(preserved, .identityEvidenceMissing), .uncertainPersistence),
            (.refused(.storage(storage(.c1BeforePreparation, .insufficient(short, usableBytes: 1)))), .initialAdmissionRefusal),
            (.refused(.invalidInput(.sourceUnavailable(id))), .sourceInvalidated),
            (.refused(.invalidInput(.sourceChanged(id))), .sourceInvalidated),
            (.refused(.target(.projectAbsent)), .targetInvalidated),
            (.refused(.cancelled), .cancelled),
            (.failedBeforeSave(.sourceChanged(id), clean()), .sourceInvalidated),
            (.failedBeforeSave(.target(.notCurrentSavedProject), clean()), .targetInvalidated),
            (.failedBeforeSave(.cancelled, clean(true)), .cancelled),
            (.failedBeforeSave(.materializationFailed(id), clean(true)), .cancelled),
            (.notSaved(clean(true)), .cancelled),
            (.failedBeforeSave(.materializationFailed(id), unresolved), .cleanupUnresolved),
            (.notSaved(unresolved), .cleanupUnresolved),
            (.failedBeforeSave(.normalizationFailed(id, cleanupFailed), clean()), .cleanupUnresolved),
            (.failedBeforeSave(.inconsistentPreparation(id), clean()), .nonRetryableFailure),
            (.failedBeforeSave(.inconsistentWorkSet(.emptyAcceptedSet), clean()), .nonRetryableFailure),
            (.failedBeforeSave(.metadataInvalid, clean()), .nonRetryableFailure),
            (.failedBeforeSave(.destinationOccupied(id), clean()), .nonRetryableFailure),
            (.failedBeforeSave(.storage(storage(.c2BeforeNormalizationItem, .invalidBoundaryState(.noPendingNormalization))), clean()), .nonRetryableFailure),
        ]
        for (outcome, reason) in ineligible { XCTAssertEqual(ImportRetryEligibility.evaluate(outcome), .ineligible(reason), "\(outcome)") }
    }

    // MARK: - Same set, fresh attempt state, CR routing

    func testRetryReusesTheAcceptedSetWithFreshAttemptStateAndRunsCRNotC1() async throws {
        let request = try await request([Spec(kind: .ready), Spec(kind: .normalized), Spec(kind: .normalized)])
        await capacity.script([1 << 40, 1_000])   // C1 passes, C2 is short
        let controller = controller(request)
        guard case .attempted(.failedBeforeSave(.storage, let rollback)) = await controller.start() else { return XCTFail("\(controller.state)") }
        XCTAssertTrue(rollback.result.isVerifiedClean)
        guard case .awaitingRetry = controller.state else { return XCTFail("\(controller.state)") }
        let firstCalls = await normalizer.calls
        let readsAfterFirst = await capacity.reads

        guard case .attempted(.completed(let commit)) = await controller.retry() else { return XCTFail("\(controller.state)") }
        guard case .succeeded(commit) = controller.state else { return XCTFail("\(controller.state)") }
        let calls = await normalizer.calls
        XCTAssertEqual(Array(calls.dropFirst(firstCalls.count)), request.accepted.filter { $0.preparationPath.normalization != nil }.map(\.candidate.url),
                       "the same Accepted Set, normalized again from the retained sources")
        XCTAssertEqual(commit.project.clips.count, 3)
        let reads = await capacity.reads
        XCTAssertEqual(reads - readsAfterFirst, 3, "CR + one C2 + C3: no extra capacity read by the controller")
        XCTAssertFalse(workspaceIsLive(), "a succeeded operation releases its workspace")
        XCTAssertFalse(gate.isHeld)
    }

    func testRepeatedCRRefusalsKeepTheEligibleEvidenceThenSucceedOnCurrentMetadata() async throws {
        let previous = try await seed(clips: 1)
        let request = try await request([Spec(kind: .normalized)], target: .replacingSaved(previousID: previous.id))
        await normalizer.script([.fail])
        let controller = controller(request)
        guard case .attempted(let first) = await controller.start(), case .failedBeforeSave(.normalizationFailed, _) = first else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(controller.state, .awaitingRetry(evidence: first))

        // A gains two rows while waiting: CR charges the CURRENT metadata.
        var grown = previous
        try grown.appendClips(try (0..<2).map { index in
            try VlogClip(projectID: previous.id, sourceKind: .imported, mediaRelativePath: try ProjectMediaStore.committedMediaPath(projectID: previous.id, clipID: UUID()),
                         sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: 1 + index)
        }, appendedAt: previous.updatedAt)
        try swiftData.update(grown)

        let expectedMetadata = try ImportStorageEstimator.metadata(.replacingSaved(newClips: 1, replacedDurableClips: 3)).bytes
        for _ in 0..<2 {
            await capacity.script([1_000])
            guard case .capacityRefused(let result) = await controller.retry() else { return XCTFail("\(controller.state)") }
            XCTAssertEqual(result.boundary, .crBeforeRetry)
            XCTAssertEqual(result.failureRoute, .retryCapacityRefusal)
            if case .insufficient(let requirement, _) = result.outcome { XCTAssertEqual(requirement.metadataBytes, expectedMetadata) } else { XCTFail("\(result)") }
            XCTAssertEqual(controller.state, .awaitingRetry(evidence: first), "a CR refusal never replaces the eligible evidence")
            XCTAssertTrue(workspaceIsLive())
        }
        guard case .attempted(.completed(let commit)) = await controller.retry() else { return XCTFail("\(controller.state)") }
        XCTAssertTrue(commit.replacedProjectMediaRemoved)
        XCTAssertEqual(try swiftData.recentProjects().map(\.id), [commit.project.id])
    }

    func testPriorConfirmedIsRetried() async throws {
        let request = try await request([Spec(kind: .ready), Spec(kind: .normalized)])
        repository.createFails = true
        let controller = controller(request)
        guard case .attempted(.notSaved) = await controller.start() else { return XCTFail("\(controller.state)") }
        repository.createFails = false
        guard case .attempted(.completed) = await controller.retry() else { return XCTFail("\(controller.state)") }
    }

    // MARK: - Source / target invalidation before Retry

    func testSourceInvalidatedBeforeRetryEndsWithoutAnAttempt() async throws {
        let request = try await request([Spec(kind: .normalized), Spec(kind: .ready)])
        await normalizer.script([.fail])
        let controller = controller(request)
        _ = await controller.start()
        try FileManager.default.removeItem(at: request.accepted[1].candidate.url)
        let callsBefore = await normalizer.calls.count
        let result = await controller.retry()
        XCTAssertEqual(result, .sourceInvalid(.sourceUnavailable(request.accepted[1].candidate.id)))
        XCTAssertEqual(controller.state, .ended(.sourceInvalidated))
        let callsAfter = await normalizer.calls.count
        XCTAssertEqual(callsAfter, callsBefore)
        XCTAssertFalse(workspaceIsLive(), "verified cleanup + nothing mutated: the workspace is released")
        let again = await controller.retry()
        XCTAssertEqual(again, .ineligible(.operationEnded))
    }

    func testTargetInvalidatedBeforeRetryEndsWithoutAnAttempt() async throws {
        let base = try await seed()
        let request = try await request([Spec(kind: .normalized)], target: .add(base: base))
        await normalizer.script([.fail])
        let controller = controller(request)
        _ = await controller.start()
        try swiftData.deleteProject(id: base.id)
        let readsBefore = await capacity.reads
        let result = await controller.retry()
        XCTAssertEqual(result, .targetInvalid(.projectAbsent))
        XCTAssertEqual(controller.state, .ended(.targetInvalidated))
        let readsAfter = await capacity.reads
        XCTAssertEqual(readsAfter, readsBefore, "target before capacity: CR never ran")
    }

    // MARK: - Concurrency and cancellation

    func testDuplicateRetryRequestsAreBusy() async throws {
        let request = try await request([Spec(kind: .normalized)])
        await normalizer.script([.fail, .park])
        let controller = controller(request)
        _ = await controller.start()
        let first = Task { await controller.retry() }
        await normalizer.waitUntilParked()
        XCTAssertEqual(controller.state, .running)
        let second = await controller.retry()
        XCTAssertEqual(second, .busy)
        let startAgain = await controller.start()
        XCTAssertEqual(startAgain, .busy)
        XCTAssertFalse(gate.isHeld, "preparation runs outside the gate")
        await normalizer.release()
        guard case .attempted(.completed) = await first.value else { return XCTFail("\(controller.state)") }
    }

    func testCancellationBetweenAttemptsEndsAndReleases() async throws {
        let request = try await request([Spec(kind: .normalized)])
        await normalizer.script([.fail])
        let controller = controller(request)
        _ = await controller.start()
        await controller.cancel()
        XCTAssertEqual(controller.state, .ended(.cancelled))
        XCTAssertFalse(workspaceIsLive())
        let retry = await controller.retry()
        XCTAssertEqual(retry, .ineligible(.operationEnded))
    }

    func testCancellationDuringAnAttemptWaitsForItsRollbackBeforeReleasing() async throws {
        let request = try await request([Spec(kind: .normalized), Spec(kind: .normalized)])
        await normalizer.script([.succeed(outputDuration: nil), .park])
        let controller = controller(request)
        let start = Task { await controller.start() }
        await normalizer.waitUntilParked()
        let cancel = Task { await controller.cancel() }
        await Task.yield()
        XCTAssertEqual(controller.state, .running, "cancel waits; nothing is released while the attempt runs")
        XCTAssertTrue(workspaceIsLive())
        await normalizer.release()
        await cancel.value
        XCTAssertEqual(controller.state, .ended(.cancelled))
        XCTAssertFalse(workspaceIsLive(), "cancel() returns only after the release finished")
        guard case .attempted(.failedBeforeSave(.cancelled, let rollback)) = await start.value else { return XCTFail("\(controller.state)") }
        XCTAssertTrue(rollback.result.isVerifiedClean, "the attempt's own rollback completed before release")
        XCTAssertFalse(workspaceIsLive())
    }

    func testCompletedDespiteLateCancellationAndSaveThatThrewAfterLanding() async throws {
        let request = try await request([Spec(kind: .ready), Spec(kind: .normalized)])
        repository.createThrowsAfterCommit = true
        let controller = controller(request)
        var stateAtCancellation: ImportRetryOperationState?
        repository.onSave = {
            // Deterministically "late": the save call has begun.
            stateAtCancellation = controller.state
            controller.requestCancellation()
        }
        guard case .attempted(.completed(let commit)) = await controller.start() else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(stateAtCancellation, .running, "the cancellation really arrived while the attempt was running")
        XCTAssertTrue(commit.saveThrew)
        guard case .succeeded = controller.state else { return XCTFail("\(controller.state)") }
    }

    // MARK: - Uncertain persistence and retained ownership

    func testUncertainPersistenceIsNeverRetriedAndKeepsProjectMedia() async throws {
        let request = try await request([Spec(kind: .ready), Spec(kind: .normalized)])
        repository.stateObservationOverride = { expectation, observed in
            PersistedStateObservation(projects: Dictionary(uniqueKeysWithValues: expectation.intended.keys.map { ($0, .unreadable) }),
                                      createdIdentityHolders: observed.createdIdentityHolders)
        }
        let controller = controller(request)
        guard case .attempted(.committedUnverified(let preserved, _)) = await controller.start() else { return XCTFail("\(controller.state)") }
        guard case .uncertain = controller.state else { return XCTFail("\(controller.state)") }
        for path in preserved.mediaPaths { XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path.value).path)) }
        let retry = await controller.retry()
        XCTAssertEqual(retry, .ineligible(.operationEnded))
        XCTAssertEqual(repository.createCount, 1)
    }

    func testUnresolvedRestorationKeepsTheWorkspaceAndItsEvidence() async throws {
        let request = try await request([Spec(kind: .ready), Spec(kind: .ready)])
        let occupied = request.accepted[0].candidate.url
        await faulty.failMaterialize(at: 1, afterMove: false, before: { try? Data(repeating: 0x77, count: 9).write(to: occupied) })
        let controller = controller(request, faultyStore: true)
        guard case .attempted(.failedBeforeSave(.materializationFailed, let rollback)) = await controller.start() else { return XCTFail("\(controller.state)") }
        XCTAssertFalse(rollback.result.isVerifiedClean)
        guard case .retainedUnresolved = controller.state else { return XCTFail("\(controller.state)") }
        await controller.cancel()
        let retry = await controller.retry()
        XCTAssertEqual(retry, .ineligible(.operationEnded))
        XCTAssertTrue(workspaceIsLive(), "never discarded while restoration is unresolved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: occupied.path))
        let live = await store.liveWorkspaceCount
        XCTAssertEqual(live, 1, "still owned (registered live)")
    }

    func testNormalizerCleanupEvidenceIsRetained() async throws {
        let request = try await request([Spec(kind: .normalized)])
        await normalizer.script([.cleanupFailure(cancelled: false)])
        let controller = controller(request)
        _ = await controller.start()
        guard case .retainedUnresolved = controller.state else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(attemptDirectories().count, 1)
        XCTAssertTrue(workspaceIsLive())
    }

    func testIneligibleVerifiedFailureEndsAndReleases() async throws {
        let request = try await request([Spec(kind: .ready)])
        await faulty.reportOccupied(1)
        let controller = controller(request, faultyStore: true)
        guard case .attempted(.failedBeforeSave(.destinationOccupied, _)) = await controller.start() else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(controller.state, .ended(.nonRetryableFailure))
        XCTAssertFalse(workspaceIsLive(), "verified cleanup: release follows the evidence, not the ineligibility")
    }

    func testInitialAdmissionRefusalEndsWithoutRetry() async throws {
        let request = try await request([Spec(kind: .normalized)])
        await capacity.script([1_000])
        let controller = controller(request)
        guard case .attempted(.refused(.storage(let result))) = await controller.start() else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(result.boundary, .c1BeforePreparation)
        XCTAssertEqual(controller.state, .ended(.initialAdmissionRefusal))
        XCTAssertFalse(workspaceIsLive())
    }

    // MARK: - Review follow-ups

    func testCancelWhileIdleEndsAndReleases() async throws {
        let request = try await request([Spec(kind: .ready)])
        let controller = controller(request)
        await controller.cancel()
        XCTAssertEqual(controller.state, .ended(.cancelled))
        XCTAssertFalse(workspaceIsLive())
        let start = await controller.start()
        XCTAssertEqual(start, .ineligible(.operationEnded))
    }

    func testChangedSourceAtRetry() async throws {
        let changed = try await request([Spec(kind: .normalized), Spec(kind: .ready)])
        await normalizer.script([.fail])
        let first = controller(changed)
        _ = await first.start()
        try Data(repeating: 0, count: 3).write(to: changed.accepted[1].candidate.url)
        let changedResult = await first.retry()
        XCTAssertEqual(changedResult, .sourceInvalid(.sourceChanged(changed.accepted[1].candidate.id)))
        XCTAssertEqual(first.state, .ended(.sourceInvalidated))
    }

    @MainActor final class ControllerBox { var controller: ImportRetryController? }
    actor ReadCounter { var count = 0; func next() -> Int { count += 1; return count } }

    func testCancellationRacingACRRefusalEndsAsCancelled() async throws {
        let request = try await request([Spec(kind: .normalized)])
        await normalizer.script([.fail])
        let box = ControllerBox(), reads = ReadCounter()
        let controller = controller(request, capacityReader: {
            guard await reads.next() > 1 else { return 1 << 40 }   // C1 passes; the CR read races a cancellation
            await MainActor.run { box.controller?.requestCancellation() }
            return 1_000
        })
        box.controller = controller
        _ = await controller.start()
        guard case .attempted(.refused(.storage(let result))) = await controller.retry() else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(result.boundary, .crBeforeRetry)
        XCTAssertEqual(controller.state, .ended(.cancelled), "a requested cancellation wins over keep-waiting")
        XCTAssertFalse(workspaceIsLive())
    }

    func testUnrequestedCancellationFromTheCapacityReaderKeepsWaiting() async throws {
        let request = try await request([Spec(kind: .normalized)])
        await normalizer.script([.fail])
        let reads = ReadCounter()
        let controller = controller(request, capacityReader: {
            guard await reads.next() > 1 else { return 1 << 40 }
            throw CancellationError()
        })
        guard case .attempted(let first) = await controller.start() else { return XCTFail() }
        let result = await controller.retry()
        XCTAssertEqual(result, .attempted(.refused(.cancelled)))
        XCTAssertEqual(controller.state, .awaitingRetry(evidence: first), "nothing was mutated and nobody cancelled")
        XCTAssertTrue(workspaceIsLive())
    }

    // MARK: - Owner clarifications 2026-10-06 (A: target unavailable, B: CR defects)

    func testUnreadableTargetKeepsWaitingThenAnExplicitRetrySucceeds() async throws {
        let base = try await seed()
        let request = try await request([Spec(kind: .normalized), Spec(kind: .ready)], target: .add(base: base))
        await normalizer.script([.fail])
        let controller = controller(request)
        guard case .attempted(let evidence) = await controller.start() else { return XCTFail() }
        repository.priorObservationOverride = { _ in .unreadable }
        let readsBefore = await capacity.reads
        for _ in 0..<2 {
            let result = await controller.retry()
            XCTAssertEqual(result, .targetUnavailable)
            XCTAssertEqual(controller.state, .awaitingRetry(evidence: evidence), "evidence and waiting state preserved")
        }
        let readsAfter = await capacity.reads
        XCTAssertEqual(readsAfter, readsBefore, "target before CR: no capacity read while unavailable")
        XCTAssertTrue(workspaceIsLive())
        for item in request.accepted { XCTAssertEqual(try? FileManager.default.attributesOfItem(atPath: item.candidate.url.path)[.size] as? Int64, item.facts.byteCount) }
        let live = await store.liveWorkspaceCount
        XCTAssertEqual(live, 1, "the workspace is still owned")

        repository.priorObservationOverride = nil
        guard case .attempted(.completed) = await controller.retry() else { return XCTFail("\(controller.state)") }
    }

    func testConfirmedChangedTargetEndsRetryEligibility() async throws {
        let base = try await seed()
        let request = try await request([Spec(kind: .normalized)], target: .add(base: base))
        await normalizer.script([.fail])
        let controller = controller(request)
        _ = await controller.start()
        var edited = base
        edited.updatedAt = Date(timeIntervalSince1970: 900)
        try swiftData.update(edited)
        let result = await controller.retry()
        XCTAssertEqual(result, .targetInvalid(.projectChanged), "stale state is never read as unreadable")
        XCTAssertEqual(controller.state, .ended(.targetInvalidated))
    }

    func testUnknownCRCapacityPermitsRepeatedExplicitChecks() async throws {
        let request = try await request([Spec(kind: .normalized)])
        await normalizer.script([.fail])
        let controller = controller(request)
        guard case .attempted(let evidence) = await controller.start() else { return XCTFail() }
        await capacity.script([nil, 1_000])
        guard case .capacityRefused(let unknown) = await controller.retry(), case .capacityUnknown = unknown.outcome else { return XCTFail("\(controller.state)") }
        guard case .capacityRefused(let short) = await controller.retry(), case .insufficient = short.outcome else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(controller.state, .awaitingRetry(evidence: evidence))
        guard case .attempted(.completed) = await controller.retry() else { return XCTFail("\(controller.state)") }
    }

    /// Scripted outcomes for states the real coordinator cannot reach with valid inputs (a CR defect).
    @MainActor final class ScriptedAttempts: ImportAttemptRunning {
        var outcomes: [ImportAttemptOutcome]
        private(set) var requests: [ImportAttemptRequest] = []
        init(_ outcomes: [ImportAttemptOutcome]) { self.outcomes = outcomes }
        func runAttempt(_ request: ImportAttemptRequest) async -> ImportAttemptOutcome {
            requests.append(request)
            return outcomes.removeFirst()
        }
    }

    func testCRDefectsNeverEnterACapacityRefusalLoop() async throws {
        let request = try await request([Spec(kind: .normalized)])
        let eligible = ImportAttemptOutcome.failedBeforeSave(.materializationFailed(request.accepted[0].candidate.id), clean())
        let defects: [ImportBoundaryCheckOutcome] = [.invalidEstimate(.emptyAcceptedSet), .invalidBoundaryState(.outputsAlreadyWritten)]
        for defect in defects {
            await store.discard(workspace)   // no live registry entry leaks between iterations
            workspace = try await store.beginWorkspace()
            let scoped = ImportAttemptRequest(accepted: request.accepted, plans: request.plans, workspace: workspace, target: .newProject)
            let crDefect = ImportBoundaryCheckResult(boundary: .crBeforeRetry, outcome: defect)
            let attempts = ScriptedAttempts([eligible, .refused(.storage(crDefect))])
            let controller = ImportRetryController(coordinator: attempts, workspaces: store, request: scoped)
            _ = await controller.start()
            XCTAssertEqual(controller.state, .awaitingRetry(evidence: eligible))
            let result = await controller.retry()
            XCTAssertEqual(result, .retryAdmissionDefect(crDefect))
            XCTAssertEqual(controller.state, .ended(.retryAdmissionDefect))
            XCTAssertFalse(workspaceIsLive(), "verified prior evidence + nothing mutated: release permitted")
            let again = await controller.retry()
            XCTAssertEqual(again, .ineligible(.operationEnded), "no capacity-refusal loop")
            XCTAssertEqual(attempts.requests.map(\.admission), [.initial, .retry])
        }
    }
}
