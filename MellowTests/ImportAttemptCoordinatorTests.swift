import Foundation
import SwiftData
import XCTest
@testable import Mellow

/// One internal import attempt (ADR-050 050-D D7a, 050-C C1 / C2 / C3, D8.0) on an isolated SwiftData store
/// and media root. Accepted items come from the real preflight over scripted facts; the normalizer, capacity
/// and materialization faults are controlled test doubles. Nothing here touches private media or a device store.
@MainActor
final class ImportAttemptCoordinatorTests: XCTestCase {
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
    /// Media of Projects seeded directly into the store (never an attempt's candidate).
    private var seededMedia: Set<String> = []

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "MellowImportAttempt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = try MellowModelContainer.makePersistentContainer(storeURL: directory.appending(path: "metadata.store"))
        swiftData = SwiftDataProjectRepository(modelContext: container.mainContext)
        repository = FailableProjectRepository(inner: swiftData)
        root = TestSupport.temporaryRoot("import-attempt")
        store = ProjectMediaStore(root: root)
        faulty = FaultyAttemptStore(inner: store)
        gate = ProjectLifecycleOperationGate()
        normalizer = NormalizerScript()
        capacity = CapacityScript()
        workspace = try await store.beginWorkspace()
    }

    override func tearDown() async throws {
        if let store, let workspace { await store.discard(workspace) }
        repository = nil
        swiftData = nil
        container = nil
        try? FileManager.default.removeItem(at: directory)
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - Doubles

    /// Serves scripted facts by URL so the real preflight builds the accepted items.
    private actor ScriptedInspector: ImportSourceInspecting {
        private var facts: [URL: ImportSourceFacts] = [:]
        func set(_ value: ImportSourceFacts, for url: URL) { facts[url] = value }
        func inspect(url: URL) async throws -> ImportSourceFacts {
            guard let value = facts[url] else { throw ImportInspectionError.sourceMissing }
            return value
        }
    }

    /// Scripted normalizer behaviour, consumed one call at a time (default: succeed with output = source).
    enum NormalizerStep: Sendable {
        case succeed(outputDuration: MediaTime?)
        case fail
        /// Parks until the test releases it, then honours cancellation and succeeds.
        case park
        /// Leaves a file it could not resolve beside the destination and reports `cleanupFailed`.
        case cleanupFailure(cancelled: Bool)
        /// Fails and keeps its progress callback, which the test fires later (`fireLateProgress`) — a stale callback.
        case failWithLateProgress
    }

    actor NormalizerScript {
        private var steps: [NormalizerStep] = []
        private(set) var calls: [URL] = []
        private(set) var gateHeldDuringCalls: [Bool] = []
        private var parked: CheckedContinuation<Void, Never>?
        private var arrivals: [CheckedContinuation<Void, Never>] = []
        private var hasParked = false
        var gateProbe: (@Sendable () async -> Bool)?

        func script(_ steps: [NormalizerStep]) { self.steps = steps }
        private var lateProgress: (@Sendable (Double) -> Void)?
        private(set) var lateProgressFired = false
        func keepLateProgress(_ progress: (@Sendable (Double) -> Void)?) { lateProgress = progress }
        /// Delivers the kept stale callback now (deterministic, test-triggered).
        func fireLateProgress(_ value: Double) { lateProgress?(value); lateProgressFired = lateProgress != nil }
        func setProbe(_ probe: @escaping @Sendable () async -> Bool) { gateProbe = probe }

        func nextStep(source: URL) async -> NormalizerStep {
            calls.append(source)
            if let gateProbe { gateHeldDuringCalls.append(await gateProbe()) }
            return steps.isEmpty ? .succeed(outputDuration: nil) : steps.removeFirst()
        }

        func park() async {
            hasParked = true
            for waiter in arrivals { waiter.resume() }
            arrivals.removeAll()
            await withCheckedContinuation { parked = $0 }
        }

        func waitUntilParked() async {
            if hasParked, parked != nil { return }
            await withCheckedContinuation { arrivals.append($0) }
            while parked == nil { await Task.yield() }
        }

        func release() {
            parked?.resume()
            parked = nil
        }
    }

    struct FakeNormalizer: WorkingMediaNormalizing {
        let script: NormalizerScript
        enum Failure: Error { case injected }

        func normalize(sourceURL: URL, destinationURL: URL, plan: WorkingMediaNormalizationPlan) async throws -> WorkingMediaNormalizationResult {
            try await normalize(sourceURL: sourceURL, destinationURL: destinationURL, plan: plan, progress: nil)
        }

        /// Reports progress 0.5 before parking (so a parked item shows real callback-driven progress).
        func normalize(sourceURL: URL, destinationURL: URL, plan: WorkingMediaNormalizationPlan,
                       progress: (@Sendable (Double) -> Void)?) async throws -> WorkingMediaNormalizationResult {
            try Task.checkCancellation()
            var step = await script.nextStep(source: sourceURL)
            if case .failWithLateProgress = step {
                await script.keepLateProgress(progress)
                throw Failure.injected
            }
            if case .park = step {
                progress?(0.5)
                await script.park()
                step = .succeed(outputDuration: nil)
            }
            if case .cleanupFailure(let cancelled) = step {
                let evidence = destinationURL.deletingLastPathComponent().appendingPathComponent("quarantine.mov")
                try Data(repeating: 0x99, count: 7).write(to: evidence)
                throw WorkingMediaNormalizationError.cleanupFailed(.stillExists(path: "quarantine.mov"), precedingError: nil, cancelled: cancelled)
            }
            try Task.checkCancellation()
            guard case .succeed(let duration) = step else { throw Failure.injected }
            guard FileManager.default.fileExists(atPath: destinationURL.deletingLastPathComponent().path),
                  !FileManager.default.fileExists(atPath: destinationURL.path) else { throw WorkingMediaNormalizationError.destinationExists }
            try Data(repeating: 0xEE, count: ImportAttemptCoordinatorTests.outputBytes).write(to: destinationURL)
            let outputDuration = duration ?? plan.sourceDuration
            let facts = ImportAttemptCoordinatorTests.makeFacts(value: outputDuration.value, timescale: outputDuration.timescale, fps: 30,
                                                                byteCount: Int64(ImportAttemptCoordinatorTests.outputBytes))
            return WorkingMediaNormalizationResult(
                destinationURL: destinationURL, outputFacts: facts,
                outputEvidence: WorkingMediaOutputEvidence(avcProfileIndication: nil, videoPresentationTimes: .unavailable,
                                                           trackCounts: .init(video: 1, audio: 0, other: 0), aacDecoderConfiguration: nil),
                sourceDuration: plan.sourceDuration, outputDuration: outputDuration, outputByteCount: Int64(ImportAttemptCoordinatorTests.outputBytes))
        }
    }

    /// Capacity readings in order; afterwards plenty. `nil` models an unreadable capacity.
    actor CapacityScript {
        private var values: [Int64?] = []
        private(set) var reads = 0
        func script(_ values: [Int64?]) { self.values = values }
        func next() -> Int64? {
            reads += 1
            return values.isEmpty ? 1 << 40 : values.removeFirst()
        }
    }

    /// The real store with injectable materialization faults and rollback probes.
    actor FaultyAttemptStore: ImportAttemptMediaStoring {
        let inner: ProjectMediaStore
        private(set) var materializeCalls = 0
        private(set) var rollbackCalls = 0
        private(set) var gateHeldDuringRollback: [Bool] = []
        private var failAt: Int?
        private var failAfterMove = false
        private var beforeFailure: (@Sendable () async -> Void)?
        private var gateProbe: (@Sendable () async -> Bool)?
        private var afterMaterialize: (@Sendable (Int, RelativeMediaPath) async -> Void)?
        private var occupiedNodeChecks = 0

        init(inner: ProjectMediaStore) { self.inner = inner }

        func setAfterMaterialize(_ hook: @escaping @Sendable (Int, RelativeMediaPath) async -> Void) { afterMaterialize = hook }
        /// The next `count` destination checks report something already there.
        func reportOccupied(_ count: Int) { occupiedNodeChecks = count }

        func failMaterialize(at index: Int, afterMove: Bool, before: (@Sendable () async -> Void)? = nil) {
            failAt = index
            failAfterMove = afterMove
            beforeFailure = before
        }
        func setProbe(_ probe: @escaping @Sendable () async -> Bool) { gateProbe = probe }

        func createAttemptDirectory(named name: String, in workspace: ProjectMediaWorkspace) async throws -> URL {
            try await inner.createAttemptDirectory(named: name, in: workspace)
        }
        func workspaceFileByteCount(_ url: URL, in workspace: ProjectMediaWorkspace) async -> Int64? {
            await inner.workspaceFileByteCount(url, in: workspace)
        }
        func mediaNode(_ path: RelativeMediaPath) async -> ImportMediaNode {
            if occupiedNodeChecks > 0 { occupiedNodeChecks -= 1; return .other }
            return await inner.mediaNode(path)
        }
        func materialize(_ url: URL, projectID: UUID, clipID: UUID) async throws -> RelativeMediaPath {
            let index = materializeCalls
            materializeCalls += 1
            guard index == failAt else {
                let path = try await inner.materialize(url, projectID: projectID, clipID: clipID)
                await afterMaterialize?(index, path)
                return path
            }
            if failAfterMove { _ = try await inner.materialize(url, projectID: projectID, clipID: clipID) }
            await beforeFailure?()
            throw ProjectMediaStoreError.destinationAlreadyExists
        }
        func removeProjectMedia(projectID: UUID) async { await inner.removeProjectMedia(projectID: projectID) }
        func rollBackAttempt(_ plan: ImportRollbackPlan) async -> ImportRollbackOutcome {
            rollbackCalls += 1
            if let gateProbe { gateHeldDuringRollback.append(await gateProbe()) }
            return await inner.rollBackAttempt(plan)
        }
    }

    // MARK: - Fixtures

    nonisolated static let outputBytes = 3_000

    nonisolated static func makeFacts(value: Int64, timescale: Int32, fps: Float, byteCount: Int64) -> ImportSourceFacts {
        var facts = ImportSourceFacts(
            duration: .exact(try! MediaTime(value: value, timescale: timescale)), isReadable: true, isPlayable: true, isExportable: true,
            hasProtectedContent: false, hasVideoTrack: true, hasAudioTrack: false, container: .quickTime, videoCodec: .h264(fourCC: "avc1"),
            naturalWidth: 1080, naturalHeight: 1920, preferredTransform: .identity,
            nominalFrameRate: fps, minimumFrameDuration: nil, bitsPerComponent: 8, highBitDepthProfile: .no,
            fullRangeVideo: .no, colorPrimaries: .rec709, transferFunction: .rec709, ycbcrMatrix: .rec709,
            hasDolbyVisionConfiguration: false, ancillaryHDRMetadata: [],
            aperture: .classify(encodedWidth: 1080, encodedHeight: 1920, cleanAperture: nil, pixelAspectRatio: nil),
            audio: nil, byteCount: byteCount, modificationDate: nil)
        facts.audioPayload = .noAudioTrack
        return facts
    }

    /// One accepted source: `.ready` (30 fps fast path) or `.normalized` (60 fps), `seconds600` long in 1/600 s.
    enum Kind { case ready, normalized }
    struct Spec {
        let kind: Kind
        var seconds600: Int64 = 1_200
        var bytes: Int = 1_000
    }

    private struct Prepared {
        let request: ImportAttemptRequest
        var accepted: [ImportAcceptedItem] { request.accepted }
        var urls: [URL] { accepted.map(\.candidate.url) }
    }

    /// Adopts one file per spec into the live workspace (sizes differ per item) and runs the real preflight.
    private func prepare(_ specs: [Spec], target: ImportAttemptTarget = .newProject) async throws -> Prepared {
        let inspector = ScriptedInspector()
        var candidates: [ImportCandidate] = []
        for (index, spec) in specs.enumerated() {
            let size = spec.bytes + index
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            try Data(repeating: UInt8(index + 1), count: size).write(to: temp)
            let adopted = try await store.adopt(temp, into: workspace)
            await inspector.set(Self.makeFacts(value: spec.seconds600, timescale: 600, fps: spec.kind == .ready ? 30 : 60, byteCount: Int64(size)), for: adopted)
            candidates.append(ImportCandidate(url: adopted))
        }
        let outcome = try await ImportSelectionPreflight(inspector: inspector).run(candidates, context: .multipleItems)
        XCTAssertTrue(outcome.excluded.isEmpty, "\(outcome.excluded)")
        XCTAssertEqual(outcome.accepted.map { $0.preparationPath.normalization == nil }, specs.map { $0.kind == .ready })
        var plans: [ImportCandidateID: WorkingMediaNormalizationPlan] = [:]
        for item in outcome.accepted where item.preparationPath.normalization != nil { plans[item.candidate.id] = try WorkingMediaPlanBuilder.plan(for: item) }
        return Prepared(request: ImportAttemptRequest(accepted: outcome.accepted, plans: plans, workspace: workspace, target: target))
    }

    private func coordinator(faultyStore: Bool = false) -> ImportAttemptCoordinator {
        let capacity = self.capacity!
        return ImportAttemptCoordinator(repository: repository, mediaStore: faultyStore ? faulty : store, normalizer: FakeNormalizer(script: normalizer),
                                        lifecycle: gate, capacity: { await capacity.next() })
    }

    private func run(_ prepared: Prepared, faultyStore: Bool = false, events: ((ImportAttemptEvent) -> Void)? = nil) async -> ImportAttemptOutcome {
        let outcome = await coordinator(faultyStore: faultyStore).run(prepared.request, events: events)
        XCTAssertFalse(gate.isHeld, "the gate is released on every outcome")
        XCTAssertEqual(gate.waitingCount, 0)
        return outcome
    }

    /// A saved Project with `clips` real Project-owned media files, created directly in the store.
    private func seed(clips count: Int = 1, updatedAt seconds: TimeInterval = 500) async throws -> VlogProject {
        let projectID = UUID()
        let date = Date(timeIntervalSince1970: seconds)
        var clips: [VlogClip] = []
        for index in 0..<count {
            let seedWorkspace = try await store.beginWorkspace()
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            try Data(repeating: 0x5A, count: 500).write(to: temp)
            let adopted = try await store.adopt(temp, into: seedWorkspace)
            let clipID = UUID()
            let path = try await store.materialize(adopted, projectID: projectID, clipID: clipID)
            await store.discard(seedWorkspace)
            seededMedia.insert(path.value)
            clips.append(try VlogClip(id: clipID, projectID: projectID, sourceKind: .imported, mediaRelativePath: path, createdAt: date,
                                      sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: index))
        }
        let project = try VlogProject(id: projectID, createdAt: date, updatedAt: date, orientation: .portrait9x16, clips: clips)
        try swiftData.create(project)
        return project
    }

    private func time(_ value: Int64) -> MediaTime { try! MediaTime(value: value, timescale: 600) }
    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private func size(_ url: URL) -> Int64? { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value }
    private func url(_ path: RelativeMediaPath) -> URL { root.appendingPathComponent(path.value) }
    private func attemptDirectories() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: workspace.directory.path)) ?? []).filter { $0.hasPrefix("attempt-") }
    }
    private func savedProjects() throws -> [VlogProject] { try swiftData.recentProjects() }

    private struct UnexpectedOutcome: Error {}

    private func committed(_ outcome: ImportAttemptOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> ImportAttemptCommit {
        guard case .completed(let commit) = outcome else { XCTFail("expected completed, got \(outcome)", file: file, line: line); throw UnexpectedOutcome() }
        return commit
    }

    private func failed(_ outcome: ImportAttemptOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> (ImportAttemptFailure, ImportAttemptRollback) {
        guard case .failedBeforeSave(let failure, let rollback) = outcome else { XCTFail("expected failedBeforeSave, got \(outcome)", file: file, line: line); throw UnexpectedOutcome() }
        return (failure, rollback)
    }

    /// `MediaTime ==` is structural; durations are compared as instants.
    private func assertSameInstant(_ a: MediaTime, _ b: MediaTime, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(!(a < b) && !(b < a), "\(a) vs \(b)", file: file, line: line)
    }

    /// Every accepted source is back in the workspace with its recorded size, `Projects/` holds exactly the
    /// seeded media (untouched, no candidate left), no attempt directory remains and nothing was saved.
    private func assertRolledBackClean(_ prepared: Prepared, _ rollback: ImportAttemptRollback, saves: Int = 0, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(rollback.result.isVerifiedClean, "\(rollback.result)", file: file, line: line)
        XCTAssertEqual(rollback.retainedSources.map(\.candidateID), prepared.accepted.map(\.candidate.id), file: file, line: line)
        for (item, retained) in zip(prepared.accepted, rollback.retainedSources) {
            XCTAssertEqual(retained.workspaceFileName, item.candidate.url.lastPathComponent, file: file, line: line)
            XCTAssertEqual(size(item.candidate.url), retained.recordedByteCount, "source restored with its recorded size", file: file, line: line)
            XCTAssertEqual(retained.recordedByteCount, item.facts.byteCount, file: file, line: line)
        }
        XCTAssertTrue(attemptDirectories().isEmpty, "the attempt directory is removed", file: file, line: line)
        let media = ((try? FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent("Projects").path)) ?? [])
            .filter { $0.hasSuffix(".mov") }.map { "Projects/" + $0 }
        XCTAssertEqual(Set(media), seededMedia, "no candidate remains in Projects/ and seeded media is untouched", file: file, line: line)
        XCTAssertEqual(repository.createCount + repository.replaceCount + repository.updateCount, saves, file: file, line: line)
    }

    // MARK: - Success: ready-only, normalized-only, mixed

    func testReadyOnlyNewProjectCommitsInAcceptedOrderWithoutNormalization() async throws {
        let prepared = try await prepare([Spec(kind: .ready, seconds600: 900), Spec(kind: .ready, seconds600: 2_700)])
        var events: [ImportAttemptEvent] = []
        let outcome = await run(prepared) { events.append($0) }
        let commit = try committed(outcome)

        XCTAssertEqual(commit.project.clips.map(\.id), commit.clipIDs)
        XCTAssertEqual(commit.project.clips.map(\.sortOrder), [0, 1])
        for (clip, expected) in zip(commit.project.clips, [time(900), time(2_700)]) {
            assertSameInstant(clip.sourceDuration, expected)
            assertSameInstant(clip.trimDuration, expected)
        }
        XCTAssertFalse(commit.saveThrew)
        for (clip, item) in zip(commit.project.clips, prepared.accepted) {
            XCTAssertEqual(size(url(clip.mediaRelativePath)), item.facts.byteCount, "ready file moved in accepted order")
            XCTAssertFalse(exists(item.candidate.url))
        }
        XCTAssertEqual(try savedProjects().map(\.id), [commit.project.id])
        let normalizerCalls = await normalizer.calls
        XCTAssertTrue(normalizerCalls.isEmpty)
        XCTAssertTrue(attemptDirectories().isEmpty, "ready-only attempts create no attempt directory")
        let boundaries = events.compactMap { if case .boundaryChecked(let result) = $0 { return result.boundary } else { return nil } }
        XCTAssertEqual(boundaries, [.c1BeforePreparation, .c3BeforeMaterialization])
    }

    func testNormalizedOnlyNewProjectChecksC2BeforeEachLaterItem() async throws {
        let prepared = try await prepare([Spec(kind: .normalized), Spec(kind: .normalized), Spec(kind: .normalized)])
        var events: [ImportAttemptEvent] = []
        let commit = try committed(await run(prepared) { events.append($0) })

        let boundaries = events.compactMap { if case .boundaryChecked(let result) = $0 { return result.boundary } else { return nil } }
        XCTAssertEqual(boundaries, [.c1BeforePreparation, .c2BeforeNormalizationItem, .c2BeforeNormalizationItem, .c3BeforeMaterialization])
        let calls = await normalizer.calls
        XCTAssertEqual(calls, prepared.urls, "normalization runs in accepted order")
        for clip in commit.project.clips { XCTAssertEqual(size(url(clip.mediaRelativePath)), Int64(Self.outputBytes)) }
        for source in prepared.urls { XCTAssertTrue(exists(source), "a normalization item's source never leaves the workspace") }
        XCTAssertEqual(attemptDirectories().count, 1)
    }

    func testMixedSetKeepsAcceptedOrderAcrossReadyAndNormalizedItems() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized), Spec(kind: .ready), Spec(kind: .normalized)])
        let commit = try committed(await run(prepared))
        XCTAssertEqual(commit.project.clips.map(\.sortOrder), [0, 1, 2, 3])
        let sizes = commit.project.clips.map { size(url($0.mediaRelativePath)) }
        XCTAssertEqual(sizes, [prepared.accepted[0].facts.byteCount, Int64(Self.outputBytes), prepared.accepted[2].facts.byteCount, Int64(Self.outputBytes)])
        XCTAssertTrue(exists(prepared.urls[1]) && exists(prepared.urls[3]))
        XCTAssertFalse(exists(prepared.urls[0]) || exists(prepared.urls[2]))
    }

    // MARK: - Normalized clip metadata (owner decision 2026-10-06)

    func testFiveSecondSourceWithLongerPermittedOutputKeepsSourceTrim() async throws {
        let prepared = try await prepare([Spec(kind: .normalized, seconds600: 3_000)])
        await normalizer.script([.succeed(outputDuration: time(3_020))])   // 5 s + 1/30 s: the window's upper edge
        let commit = try committed(await run(prepared))
        let clip = try XCTUnwrap(commit.project.clips.first)
        assertSameInstant(clip.sourceDuration, time(3_020))   // the referenced output's real duration, not clamped to 5 s
        XCTAssertEqual(clip.trimStart, .zero)
        assertSameInstant(clip.trimDuration, .seconds(5))      // the accepted source duration; the tail stays outside the trim
        assertSameInstant(clip.trimDuration, prepared.accepted[0].sourceDuration)
    }

    func testEqualOutputDurationUsesTheSameValueForSourceAndTrim() async throws {
        let prepared = try await prepare([Spec(kind: .normalized, seconds600: 1_500)])
        let commit = try committed(await run(prepared))
        let clip = try XCTUnwrap(commit.project.clips.first)
        assertSameInstant(clip.sourceDuration, time(1_500))
        assertSameInstant(clip.trimDuration, time(1_500))
    }

    func testOutputShorterThanTheTrimOrOutsideTheWindowIsRejectedBeforeSave() async throws {
        for output in [time(2_999), time(3_021)] {
            let prepared = try await prepare([Spec(kind: .normalized, seconds600: 3_000)])
            await normalizer.script([.succeed(outputDuration: output)])
            let (failure, rollback) = try failed(await run(prepared))
            XCTAssertEqual(failure, .normalizationResultRejected(prepared.accepted[0].candidate.id))
            try assertRolledBackClean(prepared, rollback)
            XCTAssertTrue(try savedProjects().isEmpty)
        }
    }

    // MARK: - Storage boundaries

    func testC1RefusalMutatesNothing() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized)])
        await capacity.script([1_000])
        guard case .refused(.storage(let result)) = await run(prepared) else { return XCTFail("expected a C1 refusal") }
        XCTAssertEqual(result.boundary, .c1BeforePreparation)
        XCTAssertEqual(result.failureRoute, .initialStorageRefusal)
        let calls = await normalizer.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(attemptDirectories().isEmpty)
        for item in prepared.accepted { XCTAssertEqual(size(item.candidate.url), item.facts.byteCount) }
        XCTAssertEqual(repository.createCount, 0)
    }

    // MARK: - DEBUG device capacity control (simulated C1 / CR outcomes)

    func testDeviceCapacityControlSimulatesOneC1ShortageThenReadsRealCapacity() async throws {
        let script = try XCTUnwrap(UITestImportCapacityScript(arguments: ["-uiTestImportCapacityShortage=c1:1"]))
        let coordinator = coordinator()
        coordinator.debugCapacityOverride = { script.override(at: $0) }

        let first = try await prepare([Spec(kind: .ready), Spec(kind: .normalized)])
        guard case .refused(.storage(let result)) = await coordinator.run(first.request, events: nil),
              case .insufficient(_, let usable) = result.outcome else { return XCTFail("expected a simulated C1 shortage") }
        XCTAssertEqual(result.boundary, .c1BeforePreparation)
        XCTAssertEqual(result.failureRoute, .initialStorageRefusal)
        XCTAssertEqual(usable, 0)
        var reads = await capacity.reads
        XCTAssertEqual(reads, 0, "the simulated check does not read the real capacity")
        let calls = await normalizer.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(attemptDirectories().isEmpty)
        for item in first.accepted { XCTAssertEqual(size(item.candidate.url), item.facts.byteCount) }
        XCTAssertEqual(repository.createCount, 0)

        // The single scripted check is consumed: the next operation reads real capacity at C1 / C2 / C3 and commits.
        await store.discard(workspace)
        workspace = try await store.beginWorkspace()
        let second = try await prepare([Spec(kind: .normalized)])
        _ = try committed(await coordinator.run(second.request, events: nil))
        reads = await capacity.reads
        XCTAssertEqual(reads, 2, "C1 and C3 read the real capacity")
        XCTAssertFalse(gate.isHeld)
    }

    func testDeviceCapacityControlSimulatesOneCRShortageAndLeavesC1Alone() async throws {
        let script = try XCTUnwrap(UITestImportCapacityScript(arguments: ["-uiTestImportCapacityShortage=cr:1"]))
        let coordinator = coordinator()
        coordinator.debugCapacityOverride = { script.override(at: $0) }
        let prepared = try await prepare([Spec(kind: .normalized)])
        let retry = ImportAttemptRequest(accepted: prepared.request.accepted, plans: prepared.request.plans, workspace: workspace,
                                         target: prepared.request.target, admission: .retry)

        guard case .refused(.storage(let result)) = await coordinator.run(retry, events: nil),
              case .insufficient(_, let usable) = result.outcome else { return XCTFail("expected a simulated CR shortage") }
        XCTAssertEqual(result.boundary, .crBeforeRetry)
        XCTAssertEqual(result.failureRoute, .retryCapacityRefusal)
        XCTAssertEqual(usable, 0)
        let calls = await normalizer.calls
        XCTAssertTrue(calls.isEmpty)
        for item in prepared.accepted { XCTAssertEqual(size(item.candidate.url), item.facts.byteCount, "the retained source is untouched") }

        // The next Retry reads real capacity and commits the same Accepted Set.
        _ = try committed(await coordinator.run(retry, events: nil))
        XCTAssertFalse(gate.isHeld)
    }

    func testDeviceCapacityControlParsesOnlyC1AndCRCounts() {
        XCTAssertNil(UITestImportCapacityScript(arguments: []))
        XCTAssertNil(UITestImportCapacityScript(arguments: ["-uiTestImportCapacityShortage=c2:1,c3:1,c0:2"]))
        XCTAssertNil(UITestImportCapacityScript(arguments: ["-uiTestImportCapacityShortage=c1:0,cr:x,garbage"]))
        let script = UITestImportCapacityScript(arguments: ["-uiTestImportCapacityShortage=c1:2,c3:1,cr:1"])
        XCTAssertNil(script?.override(at: .c3BeforeMaterialization), "C3 is never overridden")
        XCTAssertNil(script?.override(at: .c2BeforeNormalizationItem), "C2 is never overridden")
        XCTAssertEqual(script?.override(at: .c1BeforePreparation), 0)
        XCTAssertEqual(script?.override(at: .c1BeforePreparation), 0)
        XCTAssertNil(script?.override(at: .c1BeforePreparation), "only the first two C1 checks")
        XCTAssertEqual(script?.override(at: .crBeforeRetry), 0)
        XCTAssertNil(script?.override(at: .crBeforeRetry))
    }

    func testDeviceImportControlsAreInactiveWithoutTheirArguments() {
        XCTAssertNil(UITestDeviceImportControls(arguments: []))
        XCTAssertNil(UITestDeviceImportControls(arguments: ["-uiTestEditorSaveFailure", "-uiTestSeedPortrait", "-uiTestImportCapacityShortage=c3:1"]))
        XCTAssertNotNil(UITestDeviceImportControls(arguments: ["-uiTestNormalizerFailures=1"]))
        XCTAssertNotNil(UITestDeviceImportControls(arguments: ["-uiTestImportCapacityShortage=cr:1"]))
        XCTAssertFalse(UITestScriptedNormalizer.isRequested(by: ["-uiTestImportCapacityShortage=c1:1"]))
        XCTAssertNil(UITestDeviceImportControls(arguments: ["-uiTestNormalizerMidWrite=hold:0:100", "-uiTestNormalizerMidWrite=bogus"]),
                     "a malformed mid-write argument activates nothing")
        XCTAssertNil(UITestScriptedNormalizer(arguments: ["-uiTestNormalizerDelay=0"]).midWrite)
        XCTAssertEqual(try XCTUnwrap(UITestDeviceImportControls(arguments: ["-uiTestNormalizerMidWrite=fail:3"])).normalizer?.midWrite?.summary, "fail:3")
    }

    func testMidWriteControlParsesOnlyBoundedWellFormedArguments() {
        func parsed(_ value: String) -> UITestMidWriteControl? { UITestMidWriteControl(arguments: ["-uiTestNormalizerMidWrite=\(value)"]) }
        XCTAssertNil(UITestMidWriteControl(arguments: []))
        XCTAssertEqual(parsed("hold:30:20000")?.mode, .hold(milliseconds: 20_000))
        XCTAssertEqual(parsed("hold:30:20000")?.frames, 30)
        XCTAssertEqual(parsed("hold:1:60000")?.mode, .hold(milliseconds: 60_000))
        XCTAssertEqual(parsed("fail:5")?.mode, .fail)
        XCTAssertEqual(parsed("fail:5")?.frames, 5)
        for malformed in ["hold:30", "hold:30:0", "hold:30:60001", "hold:0:100", "hold:-1:100", "hold:x:100", "hold:30:20000:1",
                          "fail:0", "fail:", "fail:5:100", "fail:x", "kill:5", "", ":5"] {
            XCTAssertNil(parsed(malformed), malformed)
            XCTAssertTrue(UITestMidWriteControl.isMalformed(in: ["-uiTestNormalizerMidWrite=\(malformed)"]), malformed)
            XCTAssertFalse(UITestScriptedNormalizer.isRequested(by: ["-uiTestNormalizerMidWrite=\(malformed)"]), malformed)
        }
        XCTAssertFalse(UITestMidWriteControl.isMalformed(in: ["-uiTestNormalizerMidWrite=fail:5"]))
        XCTAssertFalse(UITestMidWriteControl.isMalformed(in: []))
    }

    /// The claim is launch-wide: copies of one controls instance share it, so the control acts exactly once per process.
    func testMidWriteClaimIsOneShotAcrossCopies() throws {
        let controls = try XCTUnwrap(UITestDeviceImportControls(arguments: ["-uiTestNormalizerMidWrite=fail:1"]))
        let first = try XCTUnwrap(controls.normalizer), second = try XCTUnwrap(controls.normalizer)
        XCTAssertTrue(first.midWriteState === second.midWriteState)
        XCTAssertTrue(first.midWriteState.claim())
        XCTAssertFalse(second.midWriteState.claim())
        XCTAssertFalse(first.midWriteState.claim())
    }

    func testDeviceImportControlsAttachTheCapacityOverrideOnlyWhenRequested() throws {
        let normalizerOnly = try XCTUnwrap(UITestDeviceImportControls(arguments: ["-uiTestNormalizerFailures=1"]))
            .services(repository: repository, store: store, lifecycle: gate)
        XCTAssertNil(try XCTUnwrap(normalizerOnly.attempts as? ImportAttemptCoordinator).debugCapacityOverride)
        let withCapacity = try XCTUnwrap(UITestDeviceImportControls(arguments: ["-uiTestImportCapacityShortage=c1:1"]))
            .services(repository: repository, store: store, lifecycle: gate)
        let override = try XCTUnwrap(try XCTUnwrap(withCapacity.attempts as? ImportAttemptCoordinator).debugCapacityOverride)
        XCTAssertNil(override(.c3BeforeMaterialization))
        XCTAssertEqual(override(.c1BeforePreparation), 0)
        XCTAssertNil(override(.c1BeforePreparation))
        XCTAssertNil(try XCTUnwrap(AppEnvironment.makeImportFlowServices(repository: repository, store: store, lifecycle: gate).attempts
            as? ImportAttemptCoordinator).debugCapacityOverride, "the production factory never attaches a control")
    }

    /// Select Clips and Editor services built from one launch's controls consume ONE capacity count: the Select Clips
    /// attempt takes the scripted C1 shortage, so the Editor attempt that follows reads real capacity and commits.
    func testServicesFromOneControlsInstanceShareTheCapacityCount() async throws {
        let controls = try XCTUnwrap(UITestDeviceImportControls(arguments: ["-uiTestImportCapacityShortage=c1:1"]))
        let selectClips = controls.services(repository: repository, store: store, lifecycle: gate)
        let editor = controls.services(repository: repository, store: store, lifecycle: gate)
        XCTAssertFalse(selectClips.attempts === editor.attempts, "each flow has its own coordinator")

        let first = try await prepare([Spec(kind: .ready)])
        guard case .refused(.storage(let result)) = await selectClips.attempts.runAttempt(first.request, events: nil) else {
            return XCTFail("the first flow takes the scripted C1 shortage")
        }
        XCTAssertEqual(result.boundary, .c1BeforePreparation)

        await store.discard(workspace)
        workspace = try await store.beginWorkspace()
        let second = try await prepare([Spec(kind: .ready)])
        _ = try committed(await editor.attempts.runAttempt(second.request, events: nil))
    }

    /// Every service carries a copy of the controls' normalizer; the copies share one failure counter, so
    /// `-uiTestNormalizerFailures=1` fails exactly one item per launch across all flows.
    func testNormalizerCopiesFromOneControlsInstanceShareTheFailureCount() async throws {
        let controls = try XCTUnwrap(UITestDeviceImportControls(arguments: ["-uiTestNormalizerFailures=1"]))
        let selectClipsCopy = try XCTUnwrap(controls.normalizer)
        let editorCopy = try XCTUnwrap(controls.normalizer)
        let prepared = try await prepare([Spec(kind: .normalized)])
        let plan = try XCTUnwrap(prepared.request.plans.values.first)
        let missing = root.appendingPathComponent("missing-source.mov")
        func injected(_ normalizer: UITestScriptedNormalizer) async -> Bool {
            do {
                _ = try await normalizer.normalize(sourceURL: missing, destinationURL: root.appendingPathComponent("\(UUID()).mov"), plan: plan)
                return false
            } catch WorkingMediaNormalizationError.writerFailed(let domain, _) where domain == "UITest" {
                return true
            } catch {
                return false   // reached the real normalizer, which fails on the missing source
            }
        }
        let firstInjected = await injected(selectClipsCopy)
        let secondInjected = await injected(editorCopy)
        XCTAssertTrue(firstInjected, "the first item anywhere takes the one scripted failure")
        XCTAssertFalse(secondInjected, "the other copy sees the consumed count and runs the real normalizer")
    }

    func testC1UnknownCapacityFailsClosed() async throws {
        let prepared = try await prepare([Spec(kind: .ready)])
        await capacity.script([nil])
        guard case .refused(.storage(let result)) = await run(prepared), case .capacityUnknown = result.outcome else { return XCTFail("expected fail-closed C1") }
    }

    func testC2ShortageRollsBackTheWrittenOutputVerified() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized), Spec(kind: .normalized)])
        await capacity.script([1 << 40, 1_000])
        let (failure, rollback) = try failed(await run(prepared))
        guard case .storage(let result) = failure else { return XCTFail("\(failure)") }
        XCTAssertEqual(result.boundary, .c2BeforeNormalizationItem)
        XCTAssertEqual(result.failureRoute, .attemptFailure)
        try assertRolledBackClean(prepared, rollback)
        let calls = await normalizer.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testC3ShortageRollsBackBeforeMaterialization() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized), Spec(kind: .normalized)])
        await capacity.script([1 << 40, 1 << 40, 1_000])
        let (failure, rollback) = try failed(await run(prepared, faultyStore: true))
        guard case .storage(let result) = failure else { return XCTFail("\(failure)") }
        XCTAssertEqual(result.boundary, .c3BeforeMaterialization)
        try assertRolledBackClean(prepared, rollback)
        let materialized = await faulty.materializeCalls
        XCTAssertEqual(materialized, 0)
    }

    // MARK: - Partial preparation / materialization

    func testNormalizationFailureAfterAnEarlierOutputRollsBackVerified() async throws {
        let prepared = try await prepare([Spec(kind: .normalized), Spec(kind: .ready), Spec(kind: .normalized)])
        await normalizer.script([.succeed(outputDuration: nil), .fail])
        let (failure, rollback) = try failed(await run(prepared))
        XCTAssertEqual(failure, .normalizationFailed(prepared.accepted[2].candidate.id, nil))
        try assertRolledBackClean(prepared, rollback)
    }

    func testPartialMaterializationRestoresEveryCandidateIncludingTheFailingItem() async throws {
        for afterMove in [false, true] {
            let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized), Spec(kind: .ready), Spec(kind: .ready)])
            await faulty.failMaterialize(at: 2, afterMove: afterMove)
            let (failure, rollback) = try failed(await run(prepared, faultyStore: true))
            XCTAssertEqual(failure, .materializationFailed(prepared.accepted[2].candidate.id))
            guard case .verifiedClean(let records) = rollback.result else { return XCTFail("\(rollback.result)") }
            XCTAssertEqual(records.count, 3, "items 0…2 recorded (the failing one included), item 3 never touched")
            XCTAssertEqual(Set(records.values), afterMove ? [.restored, .removed] : [.restored, .removed, .alreadyInWorkspace])
            try assertRolledBackClean(prepared, rollback)
            await store.discard(workspace)
            workspace = try await store.beginWorkspace()
            faulty = FaultyAttemptStore(inner: store)
        }
    }

    func testFailedRestorationIsUnresolvedAndPreservesTheFile() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .ready)])
        let occupied = prepared.urls[0]
        // Before item 1 fails, something occupies item 0's original workspace name: restoring must not overwrite it.
        await faulty.failMaterialize(at: 1, afterMove: false, before: { try? Data(repeating: 0x77, count: 9).write(to: occupied) })
        let (failure, rollback) = try failed(await run(prepared, faultyStore: true))
        XCTAssertEqual(failure, .materializationFailed(prepared.accepted[1].candidate.id))
        guard case .unresolved(let records, _) = rollback.result else { return XCTFail("restoration failure is never reported clean") }
        XCTAssertTrue(records.values.contains(.unresolved(.destinationOccupied)))
        XCTAssertEqual(size(occupied), 9, "the occupying file is not overwritten")
        let media = try FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent("Projects").path).filter { $0.hasSuffix(".mov") }
        XCTAssertEqual(media.count, 1, "the unrestorable candidate is preserved, not deleted")
        XCTAssertEqual(rollback.retainedSources.count, 2, "retained-source facts are still reported for the controller")
        XCTAssertTrue(try savedProjects().isEmpty)
    }

    // MARK: - Cancellation

    func testCancellationDuringPreparationRollsBackVerified() async throws {
        let prepared = try await prepare([Spec(kind: .normalized), Spec(kind: .normalized)])
        await normalizer.script([.succeed(outputDuration: nil), .park])
        let coordinator = coordinator()
        let task = Task { await coordinator.run(prepared.request) }
        await normalizer.waitUntilParked()
        task.cancel()
        await normalizer.release()
        let (failure, rollback) = try failed(await task.value)
        XCTAssertEqual(failure, .cancelled)
        XCTAssertTrue(rollback.cancellationRequested)
        try assertRolledBackClean(prepared, rollback)
        XCTAssertFalse(gate.isHeld)
    }

    func testCancellationImmediatelyBeforeSaveRollsBackVerified() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized), Spec(kind: .ready)])
        let outcome = await run(prepared) { event in
            if event == .saveImminent { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let (failure, rollback) = try failed(outcome)
        XCTAssertEqual(failure, .cancelled)
        XCTAssertTrue(rollback.cancellationRequested)
        try assertRolledBackClean(prepared, rollback)
    }

    func testCancellationAfterTheSaveBeganStillCompletes() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized)])
        repository.onSave = { withUnsafeCurrentTask { $0?.cancel() } }
        let commit = try committed(await run(prepared))
        XCTAssertEqual(try savedProjects().map(\.id), [commit.project.id])
    }

    // MARK: - Save outcomes

    func testSaveThatLandsThenThrowsIsCompleted() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized)])
        repository.createThrowsAfterCommit = true
        let commit = try committed(await run(prepared))
        XCTAssertTrue(commit.saveThrew)
        for clip in commit.project.clips { XCTAssertTrue(exists(url(clip.mediaRelativePath))) }
    }

    func testSuccessfulSaveWithUnavailableVerificationPreservesMediaWithoutRollback() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized)])
        repository.stateObservationOverride = { expectation, observed in
            PersistedStateObservation(projects: Dictionary(uniqueKeysWithValues: expectation.intended.keys.map { ($0, .unreadable) }),
                                      createdIdentityHolders: observed.createdIdentityHolders)
        }
        guard case .committedUnverified(let preserved, let reason) = await run(prepared, faultyStore: true) else { return XCTFail("expected committedUnverified") }
        XCTAssertEqual(reason, .unreadable)
        for path in preserved.mediaPaths { XCTAssertTrue(exists(url(path)), "potentially referenced media is preserved") }
        XCTAssertFalse(exists(prepared.urls[0]), "the ready file is not moved back")
        let rollbacks = await faulty.rollbackCalls
        XCTAssertEqual(rollbacks, 0)
    }

    func testIndeterminateReplacementPreservesBothProjectsMedia() async throws {
        let previous = try await seed()
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized)], target: .replacingSaved(previousID: previous.id))
        repository.replaceThrowsAfterCommit = true
        repository.stateObservationOverride = { _, observed in PersistedStateObservation(projects: observed.projects, createdIdentityHolders: nil) }
        guard case .indeterminate(let preserved, let reason) = await run(prepared, faultyStore: true) else { return XCTFail("expected indeterminate") }
        XCTAssertEqual(reason, .identityEvidenceMissing)
        for path in preserved.mediaPaths { XCTAssertTrue(exists(url(path))) }
        XCTAssertTrue(exists(url(previous.clips[0].mediaRelativePath)), "A's media is never removed without a completed replacement")
        let rollbacks = await faulty.rollbackCalls
        XCTAssertEqual(rollbacks, 0)
    }

    func testPriorConfirmedSaveRollsBackVerifiedInsideTheGate() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized), Spec(kind: .ready)])
        repository.createFails = true
        let gate = self.gate!
        await faulty.setProbe { await MainActor.run { gate.isHeld } }
        guard case .notSaved(let rollback) = await run(prepared, faultyStore: true) else { return XCTFail("expected notSaved") }
        XCTAssertFalse(rollback.cancellationRequested)
        try assertRolledBackClean(prepared, rollback, saves: 1)
        XCTAssertTrue(try savedProjects().isEmpty)
        let held = await faulty.gateHeldDuringRollback
        XCTAssertEqual(held, [true], "post-save rollback runs inside the commit section")
    }

    // MARK: - Targets and current metadata

    func testReplacementTargetDeletedWhilePreparationSuspendsNeverCreatesBAlone() async throws {
        let previous = try await seed()
        let prepared = try await prepare([Spec(kind: .normalized), Spec(kind: .ready)], target: .replacingSaved(previousID: previous.id))
        await normalizer.script([.park])
        let coordinator = coordinator()
        let task = Task { await coordinator.run(prepared.request) }
        await normalizer.waitUntilParked()
        XCTAssertFalse(gate.isHeld, "preparation does not hold the gate")
        try swiftData.deleteProject(id: previous.id)
        await normalizer.release()
        let (failure, rollback) = try failed(await task.value)
        XCTAssertEqual(failure, .target(.projectAbsent))
        try assertRolledBackClean(prepared, rollback)
        XCTAssertTrue(try savedProjects().isEmpty, "B is never created alone")
    }

    func testReplacementTargetNoLongerCurrentIsInvalidated() async throws {
        let previous = try await seed(updatedAt: 500)
        let prepared = try await prepare([Spec(kind: .normalized)], target: .replacingSaved(previousID: previous.id))
        await normalizer.script([.park])
        let coordinator = coordinator()
        let task = Task { await coordinator.run(prepared.request) }
        await normalizer.waitUntilParked()
        _ = try await seed(updatedAt: 900)
        await normalizer.release()
        let (failure, rollback) = try failed(await task.value)
        XCTAssertEqual(failure, .target(.notCurrentSavedProject))
        try assertRolledBackClean(prepared, rollback)
    }

    func testReplacementRevalidatesCurrentMetadataBeforeC3() async throws {
        let previous = try await seed(clips: 1)
        let prepared = try await prepare([Spec(kind: .normalized)], target: .replacingSaved(previousID: previous.id))
        await normalizer.script([.park])
        var events: [ImportAttemptEvent] = []
        let coordinator = coordinator()
        let task = Task { await coordinator.run(prepared.request) { events.append($0) } }
        await normalizer.waitUntilParked()
        // A gains durable rows while preparation is suspended; it is still the current saved Project.
        var grown = previous
        let extra = try (0..<2).map { index in
            try VlogClip(projectID: previous.id, sourceKind: .imported, mediaRelativePath: try ProjectMediaStore.committedMediaPath(projectID: previous.id, clipID: UUID()),
                         sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: 1 + index)
        }
        try grown.appendClips(extra, appendedAt: previous.updatedAt)
        try swiftData.update(grown)
        await normalizer.release()

        let commit = try committed(await task.value)
        XCTAssertTrue(commit.replacedProjectMediaRemoved)
        XCTAssertFalse(exists(url(previous.clips[0].mediaRelativePath)))
        let checks = events.compactMap { if case .boundaryChecked(let result) = $0 { return result } else { return nil } }
        func metadataBytes(_ result: ImportBoundaryCheckResult) -> Int64? { if case .sufficient(let requirement, _) = result.outcome { return requirement.metadataBytes } else { return nil } }
        XCTAssertEqual(checks.map(\.boundary), [.c1BeforePreparation, .c3BeforeMaterialization])
        XCTAssertEqual(metadataBytes(checks[0]), try ImportStorageEstimator.metadata(.replacingSaved(newClips: 1, replacedDurableClips: 1)).bytes)
        XCTAssertEqual(metadataBytes(checks[1]), try ImportStorageEstimator.metadata(.replacingSaved(newClips: 1, replacedDurableClips: 3)).bytes,
                       "C3 is charged from the current A, not the admission snapshot")
        XCTAssertEqual(try savedProjects().map(\.id), [commit.project.id])
    }

    func testAddTargetChangedWhilePreparationSuspendsStopsBeforeMaterialization() async throws {
        let base = try await seed()
        let prepared = try await prepare([Spec(kind: .normalized), Spec(kind: .ready)], target: .add(base: base))
        await normalizer.script([.park])
        let coordinator = coordinator(faultyStore: true)
        let task = Task { await coordinator.run(prepared.request) }
        await normalizer.waitUntilParked()
        var edited = base
        edited.updatedAt = Date(timeIntervalSince1970: 700)
        try swiftData.update(edited)
        await normalizer.release()
        let (failure, rollback) = try failed(await task.value)
        XCTAssertEqual(failure, .target(.projectChanged))
        try assertRolledBackClean(prepared, rollback)
        let materialized = await faulty.materializeCalls
        XCTAssertEqual(materialized, 0)
        XCTAssertEqual(try swiftData.project(id: base.id), edited, "no partial metadata commit")
    }

    func testAddAppendsInAcceptedOrderThroughUpdate() async throws {
        let base = try await seed(clips: 1)
        let prepared = try await prepare([Spec(kind: .normalized), Spec(kind: .ready)], target: .add(base: base))
        let commit = try committed(await run(prepared))
        XCTAssertEqual(repository.updateCount, 1)
        XCTAssertEqual(commit.project.id, base.id)
        XCTAssertEqual(commit.project.clips.map(\.id), [base.clips[0].id] + commit.clipIDs)
        XCTAssertEqual(try swiftData.project(id: base.id), commit.project)
    }

    func testReplaceClipPutsTheNewClipAtTheTargetIndex() async throws {
        let base = try await seed(clips: 2)
        let prepared = try await prepare([Spec(kind: .ready)], target: .replaceClip(base: base, clipID: base.clips[0].id))
        let commit = try committed(await run(prepared))
        XCTAssertEqual(commit.project.clips.map(\.id), [commit.clipIDs[0], base.clips[1].id])
        XCTAssertEqual(commit.project.deletedClips.map(\.id), [base.clips[0].id])
        XCTAssertTrue(exists(url(base.clips[0].mediaRelativePath)), "the replaced Clip's media is untouched")
    }

    func testUnreadableTargetIsRefusedNeverReadAsAbsence() async throws {
        let base = try await seed()
        let prepared = try await prepare([Spec(kind: .ready)], target: .add(base: base))
        repository.priorObservationOverride = { _ in .unreadable }
        let unreadable = await run(prepared)
        XCTAssertEqual(unreadable, .refused(.target(.unreadable)))
        XCTAssertTrue(exists(prepared.urls[0]))
    }

    // MARK: - Inputs

    func testInvalidInputsAreRefusedBeforeAnyMutation() async throws {
        let empty = ImportAttemptRequest(accepted: [], plans: [:], workspace: workspace, target: .newProject)
        let emptyOutcome = await coordinator().run(empty)
        XCTAssertEqual(emptyOutcome, .refused(.invalidInput(.emptyAcceptedSet)))

        let base = try await seed(clips: 1)
        let two = try await prepare([Spec(kind: .ready), Spec(kind: .ready)], target: .replaceClip(base: base, clipID: base.clips[0].id))
        let twoItems = await run(two)
        XCTAssertEqual(twoItems, .refused(.invalidInput(.replaceRequiresOneItem(count: 2))))

        let changed = try await prepare([Spec(kind: .ready)])
        try Data(repeating: 0, count: 5).write(to: changed.urls[0])
        let sizeChanged = await run(changed)
        XCTAssertEqual(sizeChanged, .refused(.invalidInput(.sourceChanged(changed.accepted[0].candidate.id))))

        let missingPlan = try await prepare([Spec(kind: .normalized)])
        let noPlans = ImportAttemptRequest(accepted: missingPlan.accepted, plans: [:], workspace: workspace, target: .newProject)
        let missingOutcome = await coordinator().run(noPlans)
        XCTAssertEqual(missingOutcome, .refused(.invalidInput(.workSet(.missingPlan(missingPlan.accepted[0].candidate.id)))))

        XCTAssertTrue(attemptDirectories().isEmpty)
        XCTAssertEqual(repository.createCount + repository.updateCount, 0)
    }

    // MARK: - Gate ownership

    func testGateIsHeldForCommitButNotForPreparationAndNeverReacquired() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized), Spec(kind: .normalized)])
        let gate = self.gate!
        await normalizer.setProbe { await MainActor.run { gate.isHeld } }
        var heldAtSave: [Bool] = []
        repository.onSave = { heldAtSave.append(gate.isHeld && gate.waitingCount == 0) }
        _ = try committed(await run(prepared))
        let heldDuringNormalization = await normalizer.gateHeldDuringCalls
        XCTAssertEqual(heldDuringNormalization, [false, false])
        XCTAssertEqual(heldAtSave, [true])
        XCTAssertEqual(repository.stateObservations.count, 1)

        // A preparation-phase rollback runs outside the gate, and the gate is free afterwards.
        let second = try await prepare([Spec(kind: .normalized), Spec(kind: .normalized)])
        await capacity.script([1 << 40, 1_000])
        await faulty.setProbe { await MainActor.run { gate.isHeld } }
        _ = try failed(await run(second, faultyStore: true))
        let heldAtRollback = await faulty.gateHeldDuringRollback
        XCTAssertEqual(heldAtRollback, [false])
    }

    // MARK: - Review follow-ups

    // MARK: - Normalized Editor Replace (ADR-040 §6 Revision 2026-10-06)

    /// A B C with B replaced by a normalized D: D takes B's exact index with a new identity, B becomes durable
    /// pending with its media untouched, every other identity / order / pending Clip is unchanged.
    private func assertReplaced(_ commit: ImportAttemptCommit, base: VlogProject, at index: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let d = try XCTUnwrap(commit.clipIDs.first, file: file, line: line)
        var expectedOrder = base.clips.map(\.id)
        expectedOrder[index] = d
        XCTAssertEqual(commit.project.clips.map(\.id), expectedOrder, file: file, line: line)
        XCTAssertEqual(commit.project.clips.map(\.sortOrder), Array(0..<base.clips.count), file: file, line: line)
        XCTAssertEqual(commit.project.deletedClips.map(\.id), [base.clips[index].id], file: file, line: line)
        XCTAssertNotNil(commit.project.deletedClips.first?.deletion, file: file, line: line)
        XCTAssertNotEqual(d, base.clips[index].id, file: file, line: line)
        let replacement = try XCTUnwrap(commit.project.clips.first { $0.id == d }, file: file, line: line)
        XCTAssertEqual(replacement.sourceKind, .imported, file: file, line: line)
        XCTAssertNil(replacement.framing, file: file, line: line)
        XCTAssertEqual(replacement.trimStart, .zero, file: file, line: line)
        XCTAssertEqual(replacement.mediaRelativePath, try ProjectMediaStore.committedMediaPath(projectID: base.id, clipID: d), file: file, line: line)
        XCTAssertEqual(size(url(replacement.mediaRelativePath)), Int64(Self.outputBytes), file: file, line: line)
        for clip in base.clips { XCTAssertTrue(exists(url(clip.mediaRelativePath)), "existing media untouched", file: file, line: line) }
        XCTAssertEqual(try swiftData.project(id: base.id), commit.project, file: file, line: line)
    }

    func testNormalizedReplaceWithEqualOutputDuration() async throws {
        let base = try await seed(clips: 3)
        let prepared = try await prepare([Spec(kind: .normalized, seconds600: 1_500)], target: .replaceClip(base: base, clipID: base.clips[1].id))
        let commit = try committed(await run(prepared))
        try assertReplaced(commit, base: base, at: 1)
        XCTAssertEqual(repository.updateCount, 1)
        let replacement = try XCTUnwrap(commit.project.clips.first { $0.id == commit.clipIDs[0] })
        assertSameInstant(replacement.sourceDuration, time(1_500))
        assertSameInstant(replacement.trimDuration, time(1_500))
    }

    func testNormalizedReplaceFiveSecondSourceRecordsTheLongerOutputAndKeepsTheTrim() async throws {
        let base = try await seed(clips: 2)
        let prepared = try await prepare([Spec(kind: .normalized, seconds600: 3_000)], target: .replaceClip(base: base, clipID: base.clips[0].id))
        await normalizer.script([.succeed(outputDuration: time(3_020))])
        let commit = try committed(await run(prepared))
        try assertReplaced(commit, base: base, at: 0)
        let replacement = try XCTUnwrap(commit.project.clips.first)
        assertSameInstant(replacement.sourceDuration, time(3_020))   // actual output duration, never clamped to 5 s
        assertSameInstant(replacement.trimDuration, .seconds(5))     // the accepted source duration, never extended
    }

    func testNormalizedReplaceOutputTooShortForTheTrimIsRefusedBeforeSave() async throws {
        let base = try await seed(clips: 2)
        let prepared = try await prepare([Spec(kind: .normalized, seconds600: 3_000)], target: .replaceClip(base: base, clipID: base.clips[0].id))
        await normalizer.script([.succeed(outputDuration: time(2_999))])
        let (failure, rollback) = try failed(await run(prepared))
        XCTAssertEqual(failure, .normalizationResultRejected(prepared.accepted[0].candidate.id))
        try assertRolledBackClean(prepared, rollback)
        XCTAssertEqual(try swiftData.project(id: base.id), base)
    }

    func testNormalizedReplaceUncertainSaveOutcomesPreserveMedia() async throws {
        // Save returned, verification unavailable → committedUnverified.
        let base = try await seed(clips: 2)
        let first = try await prepare([Spec(kind: .normalized)], target: .replaceClip(base: base, clipID: base.clips[1].id))
        repository.stateObservationOverride = { expectation, observed in
            PersistedStateObservation(projects: Dictionary(uniqueKeysWithValues: expectation.intended.keys.map { ($0, .unreadable) }),
                                      createdIdentityHolders: observed.createdIdentityHolders)
        }
        guard case .committedUnverified(let preserved, .unreadable) = await run(first, faultyStore: true) else { return XCTFail("expected committedUnverified") }
        for path in preserved.mediaPaths { XCTAssertTrue(exists(url(path))) }
        for clip in base.clips { XCTAssertTrue(exists(url(clip.mediaRelativePath))) }

        // Save landed then threw, identity evidence missing → indeterminate.
        let other = try await seed(clips: 2, updatedAt: 800)
        let second = try await prepare([Spec(kind: .normalized)], target: .replaceClip(base: other, clipID: other.clips[0].id))
        repository.updateThrowsAfterCommit = true
        repository.stateObservationOverride = { _, observed in PersistedStateObservation(projects: observed.projects, createdIdentityHolders: nil) }
        guard case .indeterminate(let uncertain, .identityEvidenceMissing) = await run(second, faultyStore: true) else { return XCTFail("expected indeterminate") }
        for path in uncertain.mediaPaths { XCTAssertTrue(exists(url(path))) }
        for clip in other.clips { XCTAssertTrue(exists(url(clip.mediaRelativePath))) }
        let rollbacks = await faulty.rollbackCalls
        XCTAssertEqual(rollbacks, 0, "no rollback after an uncertain save")
    }

    func testNormalizedReplacePriorConfirmedRestoresOnlyTheAttemptsCandidates() async throws {
        let base = try await seed(clips: 2)
        let prepared = try await prepare([Spec(kind: .normalized)], target: .replaceClip(base: base, clipID: base.clips[0].id))
        repository.updateFails = true
        guard case .notSaved(let rollback) = await run(prepared) else { return XCTFail("expected notSaved") }
        guard case .verifiedClean(let records) = rollback.result else { return XCTFail("\(rollback.result)") }
        XCTAssertEqual(Array(records.values), [.removed], "only the new attempt's normalized candidate")
        try assertRolledBackClean(prepared, rollback, saves: 1)   // also: Projects/ holds exactly the existing media
        XCTAssertEqual(try swiftData.project(id: base.id), base)
    }

    func testMoreInvalidInputsAreRefused() async throws {
        let base = try await seed(clips: 1)
        let notActive = try await prepare([Spec(kind: .ready)], target: .replaceClip(base: base, clipID: UUID()))
        let notActiveOutcome = await run(notActive)
        XCTAssertEqual(notActiveOutcome, .refused(.invalidInput(.replaceTargetNotActive)))

        // The source lives in this request's workspace, but the request names another workspace.
        let outside = try await prepare([Spec(kind: .ready)])
        let foreignWorkspace = try await store.beginWorkspace()
        let foreign = ImportAttemptRequest(accepted: outside.accepted, plans: [:], workspace: foreignWorkspace, target: .newProject)
        let outsideOutcome = await coordinator().run(foreign)
        XCTAssertEqual(outsideOutcome, .refused(.invalidInput(.sourceOutsideWorkspace(outside.accepted[0].candidate.id))))
        await store.discard(foreignWorkspace)

        let duplicated = try await prepare([Spec(kind: .ready)])
        let twice = ImportAttemptRequest(accepted: duplicated.accepted + duplicated.accepted, plans: [:], workspace: workspace, target: .newProject)
        let duplicateOutcome = await coordinator().run(twice)
        XCTAssertEqual(duplicateOutcome, .refused(.invalidInput(.duplicateSource(duplicated.accepted[0].candidate.id))))
        XCTAssertEqual(repository.createCount + repository.updateCount, 0)
    }

    func testC2ChargesCurrentMetadataAndStopsEarlyOnAnInvalidTarget() async throws {
        // Growth of A before the second normalization is charged at C2.
        let previous = try await seed(clips: 1)
        let prepared = try await prepare([Spec(kind: .normalized), Spec(kind: .normalized)], target: .replacingSaved(previousID: previous.id))
        await normalizer.script([.park])
        var events: [ImportAttemptEvent] = []
        let coordinator = coordinator()
        let task = Task { await coordinator.run(prepared.request) { events.append($0) } }
        await normalizer.waitUntilParked()
        var grown = previous
        try grown.appendClips([try VlogClip(projectID: previous.id, sourceKind: .imported,
                                            mediaRelativePath: try ProjectMediaStore.committedMediaPath(projectID: previous.id, clipID: UUID()),
                                            sourceDuration: .seconds(2), trimDuration: .seconds(2), sortOrder: 1)], appendedAt: previous.updatedAt)
        try swiftData.update(grown)
        await normalizer.release()
        _ = try committed(await task.value)
        let checks = events.compactMap { if case .boundaryChecked(let result) = $0 { return result } else { return nil } }
        XCTAssertEqual(checks.map(\.boundary), [.c1BeforePreparation, .c2BeforeNormalizationItem, .c3BeforeMaterialization])
        if case .sufficient(let requirement, _) = checks[1].outcome {
            XCTAssertEqual(requirement.metadataBytes, try ImportStorageEstimator.metadata(.replacingSaved(newClips: 2, replacedDurableClips: 2)).bytes)
        } else { XCTFail("\(checks[1])") }

        // A deleted before the second normalization stops at C2's target read.
        let again = try await seed(clips: 1, updatedAt: Date().timeIntervalSince1970 + 86_400)
        let second = try await prepare([Spec(kind: .normalized), Spec(kind: .normalized)], target: .replacingSaved(previousID: again.id))
        await normalizer.script([.park])
        let calls = await normalizer.calls.count
        let directoriesBefore = Set(attemptDirectories())   // the completed first attempt's own (empty) directory
        let task2 = Task { await coordinator.run(second.request) }
        await normalizer.waitUntilParked()
        try swiftData.deleteProject(id: again.id)
        await normalizer.release()
        let (failure, rollback) = try failed(await task2.value)
        XCTAssertEqual(failure, .target(.projectAbsent))
        let callsAfter = await normalizer.calls.count
        XCTAssertEqual(callsAfter - calls, 1, "the second normalization never starts")
        XCTAssertTrue(rollback.result.isVerifiedClean)
        XCTAssertEqual(Set(attemptDirectories()), directoriesBefore, "the failed attempt's directory is removed")
    }

    func testNormalizerCleanupFailureKeepsTheAttemptDirectoryAndIsNeverClean() async throws {
        for cancelled in [false, true] {
            let prepared = try await prepare([Spec(kind: .normalized), Spec(kind: .normalized)])
            await normalizer.script([.succeed(outputDuration: nil), .cleanupFailure(cancelled: cancelled)])
            let (failure, rollback) = try failed(await run(prepared))
            guard case .normalizationFailed(let id, .cleanupFailed?) = failure else { return XCTFail("\(failure)") }
            XCTAssertEqual(id, prepared.accepted[1].candidate.id)
            XCTAssertEqual(rollback.result, .unresolved(records: [:], attemptDirectory: .normalizerCleanupUnresolved))
            let directories = attemptDirectories()
            XCTAssertEqual(directories.count, 1)
            XCTAssertTrue(exists(workspace.directory.appendingPathComponent(directories[0]).appendingPathComponent("quarantine.mov")), "evidence preserved")
            await store.discard(workspace)
            workspace = try await store.beginWorkspace()
        }
    }

    func testOccupiedDestinationIsNeverClaimed() async throws {
        let prepared = try await prepare([Spec(kind: .ready), Spec(kind: .normalized)])
        await faulty.reportOccupied(1)
        let (failure, rollback) = try failed(await run(prepared, faultyStore: true))
        XCTAssertEqual(failure, .destinationOccupied(prepared.accepted[0].candidate.id))
        guard case .verifiedClean(let records) = rollback.result else { return XCTFail("\(rollback.result)") }
        XCTAssertTrue(records.isEmpty, "no record claims an unverified destination")
        try assertRolledBackClean(prepared, rollback)
    }

    func testReadySourceChangedBeforeItsMaterializationFailsBeforeSave() async throws {
        let prepared = try await prepare([Spec(kind: .normalized), Spec(kind: .ready)])
        await normalizer.script([.park])
        let coordinator = coordinator()
        let task = Task { await coordinator.run(prepared.request) }
        await normalizer.waitUntilParked()
        try Data(repeating: 0, count: 3).write(to: prepared.urls[1])
        await normalizer.release()
        let (failure, rollback) = try failed(await task.value)
        XCTAssertEqual(failure, .sourceChanged(prepared.accepted[1].candidate.id))
        XCTAssertTrue(rollback.result.isVerifiedClean)
        XCTAssertEqual(size(prepared.urls[1]), 3, "the changed file is left where it is")
        XCTAssertEqual(repository.createCount, 0)
    }

    func testMediaThatChangedAfterTheMoveFailsVerificationBeforeSave() async throws {
        let prepared = try await prepare([Spec(kind: .normalized)])
        let root = self.root!
        await faulty.setAfterMaterialize { _, path in
            if let handle = try? FileHandle(forWritingTo: root.appendingPathComponent(path.value)) { handle.seekToEndOfFile(); handle.write(Data([1])); try? handle.close() }
        }
        let (failure, rollback) = try failed(await run(prepared, faultyStore: true))
        XCTAssertEqual(failure, .mediaVerificationFailed)
        try assertRolledBackClean(prepared, rollback)
    }

    func testTargetRecheckImmediatelyBeforeSave() async throws {
        let base = try await seed()
        let prepared = try await prepare([Spec(kind: .ready)], target: .add(base: base))
        let repository = self.repository!
        let outcome = await run(prepared) { event in
            if event == .materializationStarted { repository.priorObservationOverride = { _ in .unreadable } }
        }
        let (failure, rollback) = try failed(outcome)
        XCTAssertEqual(failure, .target(.unreadable))
        try assertRolledBackClean(prepared, rollback)
        XCTAssertEqual(try swiftData.project(id: base.id), base)
    }

    func testPriorConfirmedReplacementAndAddLeaveTheExistingProjectUntouched() async throws {
        let previous = try await seed()
        let replacing = try await prepare([Spec(kind: .ready), Spec(kind: .normalized)], target: .replacingSaved(previousID: previous.id))
        repository.replaceFails = true
        guard case .notSaved(let rollback) = await run(replacing) else { return XCTFail("expected notSaved") }
        try assertRolledBackClean(replacing, rollback, saves: 1)
        XCTAssertEqual(try swiftData.project(id: previous.id), previous)
        XCTAssertTrue(exists(url(previous.clips[0].mediaRelativePath)))

        let adding = try await prepare([Spec(kind: .normalized), Spec(kind: .ready)], target: .add(base: previous))
        repository.updateFails = true
        guard case .notSaved(let addRollback) = await run(adding) else { return XCTFail("expected notSaved") }
        try assertRolledBackClean(adding, addRollback, saves: 2)
        XCTAssertEqual(try swiftData.project(id: previous.id), previous)
    }

    func testPriorConfirmedAfterACancellationReportsIt() async throws {
        let prepared = try await prepare([Spec(kind: .ready)])
        repository.createFails = true
        repository.onSave = { withUnsafeCurrentTask { $0?.cancel() } }
        guard case .notSaved(let rollback) = await run(prepared) else { return XCTFail("expected notSaved") }
        XCTAssertTrue(rollback.cancellationRequested, "D7a §3: the operation ends without Retry")
        try assertRolledBackClean(prepared, rollback, saves: 1)
    }

    func testEditorUpdateUnverifiedPreservesMedia() async throws {
        let base = try await seed()
        let prepared = try await prepare([Spec(kind: .normalized), Spec(kind: .ready)], target: .add(base: base))
        repository.stateObservationOverride = { expectation, observed in
            PersistedStateObservation(projects: Dictionary(uniqueKeysWithValues: expectation.intended.keys.map { ($0, .unreadable) }),
                                      createdIdentityHolders: observed.createdIdentityHolders)
        }
        guard case .committedUnverified(let preserved, _) = await run(prepared, faultyStore: true) else { return XCTFail("expected committedUnverified") }
        for path in preserved.mediaPaths { XCTAssertTrue(exists(url(path))) }
        XCTAssertTrue(exists(url(base.clips[0].mediaRelativePath)))
        let rollbacks = await faulty.rollbackCalls
        XCTAssertEqual(rollbacks, 0)
    }
}
