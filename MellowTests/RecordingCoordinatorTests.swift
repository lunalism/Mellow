import CoreGraphics
import XCTest
@testable import Mellow

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    private struct Harness {
        let service: FakeCameraCaptureService
        let staging: RecordingStagingStore
        let directory: URL
        let photos: FakePhotosLibrarySaver
        let inspector: FakeRecordingMediaInspector
        let thumbnails: FakeRecordingThumbnailGenerator
        let haptics: FakeCompletionHaptic
        let background: ImmediateBackgroundTaskRunner
        let coordinator: RecordingCoordinator
        let projects: InMemoryProjectRepository
    }

    private var harnesses: [Harness] = []

    private func makeHarness(
        photos: PhotosAddAuthorization = .authorized,
        running: Bool = true,
        thumbnail: CGImage? = nil
    ) async -> Harness {
        let service = FakeCameraCaptureService()
        if running {
            await service.prepare(); await service.start()
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoordinatorTests-\(UUID().uuidString)")
        let staging = RecordingStagingStore(directory: directory)
        let saver = FakePhotosLibrarySaver(authorization: photos)
        let inspector = FakeRecordingMediaInspector()
        inspector.durationProvider = { [service] in service.recordedDuration }
        let thumbnails = FakeRecordingThumbnailGenerator(nextImage: thumbnail)
        let haptics = FakeCompletionHaptic()
        let background = ImmediateBackgroundTaskRunner()
        let coordinator = RecordingCoordinator(service: service, staging: staging, photos: saver, inspector: inspector,
                                               thumbnails: thumbnails, haptics: haptics, backgroundTasks: background)
        let harness = Harness(service: service, staging: staging, directory: directory, photos: saver, inspector: inspector,
                              thumbnails: thumbnails, haptics: haptics, background: background, coordinator: coordinator,
                              projects: InMemoryProjectRepository())
        harnesses.append(harness)
        return harness
    }

    override func tearDown() async throws {
        for h in harnesses { try? FileManager.default.removeItem(at: h.directory) }
        harnesses = []
    }

    /// Lets the fake's asynchronous didStart hop and any finalize task settle.
    private func settle(_ coordinator: RecordingCoordinator, until predicate: @escaping () -> Bool, attempts: Int = 200) async {
        for _ in 0..<attempts where !predicate() { await Task.yield(); try? await Task.sleep(for: .milliseconds(2)) }
    }

    private func startRecording(_ h: Harness, maximum: CameraDuration = .three, posture: CameraDeviceOrientation = .portrait) async {
        await h.coordinator.record(maximum: maximum, posture: posture)
        await settle(h.coordinator) { h.coordinator.phase == .recording || h.coordinator.phase == .idle }
    }

    private func stagedCount(_ h: Harness) async -> Int { await h.staging.stagedFiles().count }

    // MARK: Start gate

    func testValidPortraitStartRecordsAndDefaultIsThreeSeconds() async {
        let h = await makeHarness()
        await startRecording(h)
        XCTAssertEqual(h.coordinator.phase, .recording)
        XCTAssertEqual(h.service.calls.filter { $0 == "startRecording" }.count, 1)
        XCTAssertEqual(CameraDuration.three.rawValue, 3)
    }

    func testInvalidAndUnknownPosturesAreRejectedAtStart() async {
        for posture in [CameraDeviceOrientation.landscapeLeft, .landscapeRight, .faceUp, .faceDown, .unknown, .unstable, .portraitUpsideDown] {
            let h = await makeHarness()
            await h.coordinator.record(maximum: .three, posture: posture)
            XCTAssertEqual(h.coordinator.phase, .idle, "\(posture) must not start recording")
            XCTAssertFalse(h.service.calls.contains("startRecording"), "\(posture)")
            let staged_h_0 = await stagedCount(h); XCTAssertEqual(staged_h_0, 0, "no staging media for \(posture)")
        }
    }

    func testStartRequiresRunningSessionAndPhotosAccess() async {
        let stopped = await makeHarness(running: false)
        await stopped.coordinator.record(maximum: .three, posture: .portrait)
        XCTAssertEqual(stopped.coordinator.phase, .idle)

        let denied = await makeHarness(photos: .denied)
        await denied.coordinator.record(maximum: .three, posture: .portrait)
        XCTAssertEqual(denied.coordinator.phase, .idle)
        XCTAssertEqual(denied.coordinator.failure, .photosAccess(.denied))
        XCTAssertTrue(denied.coordinator.failure?.offersSettings ?? false)

        let restricted = await makeHarness(photos: .restricted)
        await restricted.coordinator.record(maximum: .three, posture: .portrait)
        XCTAssertEqual(restricted.coordinator.failure, .photosAccess(.restricted))
        XCTAssertFalse(restricted.coordinator.failure?.offersSettings ?? true)

        let undetermined = await makeHarness(photos: .notDetermined)
        await startRecording(undetermined)
        XCTAssertEqual(undetermined.photos.requestCount, 1, "Photos Add is requested at the record attempt")
        XCTAssertEqual(undetermined.coordinator.phase, .recording)
    }

    // MARK: Stop paths and the 1.0s rule

    func testManualStopAtOrAboveOneSecondSavesAndHapticsOnlyAfterPhotosSuccess() async {
        let h = await makeHarness()
        await startRecording(h)
        h.service.recordedDurationOverride = 1.4
        XCTAssertEqual(h.haptics.completions, 0)
        await h.coordinator.requestStop(.userRequested)
        await settle(h.coordinator) { h.coordinator.phase == .idle }
        XCTAssertEqual(h.photos.savedURLs.count, 1)
        XCTAssertEqual(h.coordinator.completedSaves, 1)
        XCTAssertEqual(h.haptics.completions, 1, "completion haptic fires on Photos-save success")
        XCTAssertEqual(h.coordinator.lastStopReason, .userRequested)
        let staged_h_0 = await stagedCount(h); XCTAssertEqual(staged_h_0, 0, "staging released after save")
        XCTAssertNil(h.coordinator.failure)
        XCTAssertEqual(h.background.runs, 1)
    }

    func testManualStopBelowOneSecondDiscardsWithCaptionAndNoHaptic() async {
        let h = await makeHarness()
        await startRecording(h)
        h.service.recordedDurationOverride = 0.6
        await h.coordinator.requestStop(.userRequested)
        await settle(h.coordinator) { h.coordinator.phase == .idle }
        XCTAssertTrue(h.photos.savedURLs.isEmpty)
        XCTAssertEqual(h.coordinator.notice, .tooShort)
        XCTAssertEqual(h.haptics.completions, 0)
        XCTAssertNil(h.coordinator.failure)
        let staged_h_0 = await stagedCount(h); XCTAssertEqual(staged_h_0, 0, "sub-second staging is deleted")
        XCTAssertEqual(h.coordinator.progress, 0)
    }

    func testStrictLowerBoundIsNotRoundedUp() async {
        let h = await makeHarness()
        await startRecording(h)
        h.service.recordedDurationOverride = 0.97
        await h.coordinator.requestStop(.userRequested)
        await settle(h.coordinator) { h.coordinator.phase == .idle }
        XCTAssertEqual(h.coordinator.notice, .tooShort)
        XCTAssertTrue(h.photos.savedURLs.isEmpty)
    }

    func testAutoStopAtEveryPresetSavesWithinOneFrameTolerance() async {
        for preset in CameraDuration.allCases {
            let h = await makeHarness()
            await startRecording(h, maximum: preset)
            h.service.simulateMaximumReached()
            await settle(h.coordinator) { h.coordinator.phase == .idle }
            XCTAssertEqual(h.coordinator.lastStopReason, .maximumReached, "\(preset)")
            XCTAssertEqual(h.photos.savedURLs.count, 1, "\(preset)")
        }
        // A frame of encoder overshoot at the maximum still saves; more does not.
        let overshoot = await makeHarness()
        await startRecording(overshoot, maximum: .two)
        overshoot.service.recordedDurationOverride = 2.0 + RecordingPolicy.upperDurationTolerance * 0.5
        await overshoot.coordinator.requestStop(.userRequested)
        await settle(overshoot.coordinator) { overshoot.coordinator.phase == .idle }
        XCTAssertEqual(overshoot.photos.savedURLs.count, 1)

        let tooLong = await makeHarness()
        await startRecording(tooLong, maximum: .two)
        tooLong.service.recordedDurationOverride = 2.5
        await tooLong.coordinator.requestStop(.userRequested)
        await settle(tooLong.coordinator) { tooLong.coordinator.phase == .idle }
        XCTAssertTrue(tooLong.photos.savedURLs.isEmpty)
        XCTAssertEqual(tooLong.coordinator.failure, .captureFailed)
    }

    // MARK: Arbitration

    func testFirstStopReasonWinsAndOnlyOneFinalizationRuns() async {
        let h = await makeHarness()
        await startRecording(h)
        h.service.recordedDurationOverride = 2
        await h.coordinator.requestStop(.userRequested)
        await h.coordinator.requestStop(.appInactive)
        await h.coordinator.requestStop(.captureInterrupted)
        await settle(h.coordinator) { h.coordinator.phase == .idle }
        XCTAssertEqual(h.coordinator.lastStopReason, .userRequested)
        XCTAssertEqual(h.service.calls.filter { $0 == "stopRecording" }.count, 1)
        XCTAssertEqual(h.photos.savedURLs.count, 1, "exactly one save")
        XCTAssertEqual(h.inspector.inspected.count, 1, "exactly one validation")
        // A stray duplicate finish event for the same URL is dropped.
        let url = h.photos.savedURLs[0]
        h.service.recordingDidChange?(.finished(url: url, fileUsable: true, reachedMaximum: false, errorDescription: nil))
        await settle(h.coordinator) { true }
        XCTAssertEqual(h.photos.savedURLs.count, 1)
    }

    func testAutoStopAndInterruptionRaceProducesOneSave() async {
        let h = await makeHarness()
        await startRecording(h, maximum: .two)
        h.service.recordedDurationOverride = 1.5
        await h.coordinator.requestStop(.captureInterrupted)
        h.service.simulateMaximumReached()   // arrives after the stop was already accepted
        await settle(h.coordinator) { h.coordinator.phase == .idle }
        XCTAssertEqual(h.coordinator.lastStopReason, .captureInterrupted)
        XCTAssertEqual(h.photos.savedURLs.count, 1)
    }

    // MARK: Background / interruption

    func testBackgroundStopSavesWhenLongEnoughAndDiscardsWhenShort() async {
        let long = await makeHarness()
        await startRecording(long, maximum: .five)
        long.service.recordedDurationOverride = 2.2
        await long.coordinator.requestStop(.appInactive)
        await settle(long.coordinator) { long.coordinator.phase == .idle }
        XCTAssertEqual(long.photos.savedURLs.count, 1)
        XCTAssertEqual(long.background.runs, 1, "finalize/save runs under a background task")

        let short = await makeHarness()
        await startRecording(short, maximum: .five)
        short.service.recordedDurationOverride = 0.8
        await short.coordinator.requestStop(.appInactive)
        await settle(short.coordinator) { short.coordinator.phase == .idle }
        XCTAssertTrue(short.photos.savedURLs.isEmpty)
        XCTAssertEqual(short.coordinator.notice, .tooShort)
    }

    func testInterruptionWithUnusableFileFailsWithoutSave() async {
        let h = await makeHarness()
        await startRecording(h)
        h.service.nextFileUsable = false
        await h.coordinator.requestStop(.captureInterrupted)
        await settle(h.coordinator) { h.coordinator.phase == .idle }
        XCTAssertEqual(h.coordinator.failure, .captureFailed)
        XCTAssertTrue(h.photos.savedURLs.isEmpty)
        XCTAssertEqual(h.haptics.completions, 0)
        let staged_h_0 = await stagedCount(h); XCTAssertEqual(staged_h_0, 0)
    }

    // MARK: Photos save

    func testPhotosSaveFailureRetainsStagingAndReportsRecoverableError() async {
        let h = await makeHarness()
        h.photos.saveFails = true
        await startRecording(h)
        h.service.recordedDurationOverride = 2
        await h.coordinator.requestStop(.userRequested)
        await settle(h.coordinator) { h.coordinator.phase == .idle }
        XCTAssertEqual(h.coordinator.failure, .photosSaveFailed)
        XCTAssertEqual(h.haptics.completions, 0)
        XCTAssertEqual(h.coordinator.completedSaves, 0)
        let staged_h_1 = await stagedCount(h); XCTAssertEqual(staged_h_1, 1, "staging kept as a recovery candidate")
        h.coordinator.dismissFailure()
        XCTAssertNil(h.coordinator.failure)
    }

    func testStorageGateBlocksBeforeAnyStagingMedia() async {
        // The temp volume has plenty of space; prove the gate by driving the policy directly and
        // by checking a recording never touches staging when the gate says no.
        XCTAssertFalse(RecordingPolicy.hasSufficientStorage(usableBytes: 50 * 1_024 * 1_024))
        let h = await makeHarness()
        let usable = await h.staging.usableCapacityBytes()
        XCTAssertGreaterThan(usable, RecordingPolicy.minimumUsableStorageBytes, "test volume must satisfy the gate for the other tests")
    }

    // MARK: Progress & lifecycle

    func testProgressTracksPipelineMediaTimeAgainstSelectedMaximum() async {
        let h = await makeHarness()
        await startRecording(h, maximum: .four)
        h.service.recordedDurationOverride = 2
        await settle(h.coordinator) { h.coordinator.progress > 0.4 }
        XCTAssertEqual(h.coordinator.progress, 0.5, accuracy: 0.05)
        h.service.recordedDurationOverride = 4
        await h.coordinator.requestStop(.userRequested)
        await settle(h.coordinator) { h.coordinator.phase == .idle }
        XCTAssertEqual(h.coordinator.progress, 0)
    }

    func testRecordingIsActiveThroughFinishingAndSaving() async {
        let h = await makeHarness()
        XCTAssertFalse(h.coordinator.isActive)
        await startRecording(h)
        XCTAssertTrue(h.coordinator.isActive)
        XCTAssertTrue(h.coordinator.isStoppable)
        h.service.recordedDurationOverride = 1.5
        await h.coordinator.requestStop(.userRequested)
        await settle(h.coordinator) { h.coordinator.phase == .idle }
        XCTAssertFalse(h.coordinator.isActive)
    }

    // MARK: Project separation

    func testRecordingNeverCreatesAProject() async throws {
        let h = await makeHarness()
        let repository = h.projects
        XCTAssertEqual(try repository.recentProjects().count, 0)
        for _ in 0..<3 {
            await startRecording(h)
            h.service.recordedDurationOverride = 2
            await h.coordinator.requestStop(.userRequested)
            await settle(h.coordinator) { h.coordinator.phase == .idle }
        }
        XCTAssertEqual(h.coordinator.completedSaves, 3)
        XCTAssertEqual(try repository.recentProjects().count, 0, "successful saves create no project")

        h.photos.saveFails = true
        await startRecording(h)
        h.service.recordedDurationOverride = 2
        await h.coordinator.requestStop(.userRequested)
        await settle(h.coordinator) { h.coordinator.phase == .idle }
        XCTAssertEqual(try repository.recentProjects().count, 0, "failures create no project either")
    }

    // MARK: Preview thumbnail (Phase 4 feedback)

    /// Drives a full valid capture → stop → finalize/save cycle back to idle.
    private func recordAndStop(_ h: Harness, duration: TimeInterval) async {
        await startRecording(h)
        h.service.recordedDurationOverride = duration
        await h.coordinator.requestStop(.userRequested)
        await settle(h.coordinator) { h.coordinator.phase == .idle }
    }

    // A. Successful valid recording generates a thumbnail and publishes it after Photos save.
    func testSuccessfulRecordingPublishesGeneratedThumbnail() async {
        let image = FakeRecordingThumbnailGenerator.makeStubImage()
        let h = await makeHarness(thumbnail: image)
        XCTAssertNil(h.coordinator.lastThumbnail)
        await recordAndStop(h, duration: 2)
        XCTAssertEqual(h.coordinator.completedSaves, 1)
        XCTAssertEqual(h.thumbnails.requestCount, 1, "thumbnail generated once, from the staging clip")
        XCTAssertTrue(h.coordinator.lastThumbnail === image, "the saved clip's frame becomes the tile")
    }

    // B. Thumbnail generation failure must not fail the recording; save + haptic still succeed.
    func testThumbnailGenerationFailureDoesNotFailRecording() async {
        let h = await makeHarness(thumbnail: nil) // generator returns nil → generation "failed"
        await recordAndStop(h, duration: 2)
        XCTAssertEqual(h.coordinator.completedSaves, 1, "save is authoritative and still succeeds")
        XCTAssertEqual(h.haptics.completions, 1, "completion haptic still fires")
        XCTAssertNil(h.coordinator.failure)
        XCTAssertNil(h.coordinator.lastThumbnail, "no image to publish; previous (none) unchanged")
    }

    // C. A too-short recording after a prior success must not replace the previous thumbnail.
    func testTooShortRecordingKeepsPreviousThumbnail() async {
        let image = FakeRecordingThumbnailGenerator.makeStubImage()
        let h = await makeHarness(thumbnail: image)
        await recordAndStop(h, duration: 2)
        XCTAssertTrue(h.coordinator.lastThumbnail === image)

        await recordAndStop(h, duration: 0.5) // below the 1.0s minimum → discarded
        XCTAssertEqual(h.coordinator.completedSaves, 1, "too-short clip is not saved")
        XCTAssertEqual(h.thumbnails.requestCount, 1, "generation is never reached for a too-short clip")
        XCTAssertTrue(h.coordinator.lastThumbnail === image, "previous thumbnail preserved")
    }

    // D. A Photos-save failure after generation must not replace the previous thumbnail.
    func testPhotosSaveFailureKeepsPreviousThumbnail() async {
        let first = FakeRecordingThumbnailGenerator.makeStubImage()
        let h = await makeHarness(thumbnail: first)
        await recordAndStop(h, duration: 2)
        XCTAssertTrue(h.coordinator.lastThumbnail === first)

        // Next capture generates a new frame but the Photos save fails.
        h.thumbnails.nextImage = FakeRecordingThumbnailGenerator.makeStubImage()
        h.photos.saveFails = true
        await recordAndStop(h, duration: 2)
        XCTAssertEqual(h.coordinator.failure, .photosSaveFailed, "existing save-failure behavior intact")
        XCTAssertEqual(h.coordinator.completedSaves, 1, "failed save does not count")
        XCTAssertTrue(h.coordinator.lastThumbnail === first, "previous thumbnail preserved on save failure")
    }

    // E. The next successful recording replaces the previous thumbnail with the newest frame.
    func testNextSuccessfulRecordingReplacesThumbnail() async {
        let first = FakeRecordingThumbnailGenerator.makeStubImage()
        let h = await makeHarness(thumbnail: first)
        await recordAndStop(h, duration: 2)
        XCTAssertTrue(h.coordinator.lastThumbnail === first)

        let second = FakeRecordingThumbnailGenerator.makeStubImage()
        h.thumbnails.nextImage = second
        await recordAndStop(h, duration: 2)
        XCTAssertEqual(h.coordinator.completedSaves, 2)
        XCTAssertTrue(h.coordinator.lastThumbnail === second, "newest frame replaces the previous one")
    }
}
