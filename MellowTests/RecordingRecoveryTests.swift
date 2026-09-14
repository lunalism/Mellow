import XCTest
@testable import Mellow

@MainActor
final class RecordingRecoveryTests: XCTestCase {
    private var directory: URL!
    private var staging: RecordingStagingStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RecoveryTests-\(UUID().uuidString)")
        staging = RecordingStagingStore(directory: directory)
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func stage(named name: String, ageSeconds: TimeInterval = 60) async throws -> URL {
        _ = try await staging.newRecordingURL()
        let url = directory.appendingPathComponent(name).appendingPathExtension("mov")
        try Data([0, 1, 2]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-ageSeconds)], ofItemAtPath: url.path)
        return url
    }

    func testRecoverableFileIsSavedToPhotosAndRemoved() async throws {
        let url = try await stage(named: "good")
        let inspector = FakeRecordingMediaInspector()
        inspector.nextInfo = RecordingMediaInfo(isPlayable: true, hasVideoTrack: true, duration: 2.4)
        let photos = FakePhotosLibrarySaver()
        let report = await RecordingRecovery(staging: staging, inspector: inspector, photos: photos).run()
        XCTAssertEqual(report.saved, [url])
        XCTAssertEqual(photos.savedURLs, [url])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCorruptNoVideoAndSubSecondFilesAreDeleted() async throws {
        let corrupt = try await stage(named: "corrupt")
        let inspector = FakeRecordingMediaInspector()
        inspector.nextInfo = RecordingMediaInfo(isPlayable: false, hasVideoTrack: false, duration: 0)
        let photos = FakePhotosLibrarySaver()
        var report = await RecordingRecovery(staging: staging, inspector: inspector, photos: photos).run()
        XCTAssertEqual(report.deleted, [corrupt])
        XCTAssertTrue(photos.savedURLs.isEmpty)

        let short = try await stage(named: "short")
        inspector.nextInfo = RecordingMediaInfo(isPlayable: true, hasVideoTrack: true, duration: 0.8)
        report = await RecordingRecovery(staging: staging, inspector: inspector, photos: photos).run()
        XCTAssertEqual(report.deleted, [short])
        XCTAssertFalse(FileManager.default.fileExists(atPath: short.path))
    }

    func testPhotosUnavailableRetainsCandidateWithoutClaimingSuccess() async throws {
        let url = try await stage(named: "retained")
        let inspector = FakeRecordingMediaInspector()
        inspector.nextInfo = RecordingMediaInfo(isPlayable: true, hasVideoTrack: true, duration: 3)
        let photos = FakePhotosLibrarySaver(authorization: .denied)
        var report = await RecordingRecovery(staging: staging, inspector: inspector, photos: photos).run()
        XCTAssertEqual(report.retained, [url])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        photos.authorization = .authorized
        photos.saveFails = true
        report = await RecordingRecovery(staging: staging, inspector: inspector, photos: photos).run()
        XCTAssertEqual(report.retained, [url], "save failure keeps the candidate")
        XCTAssertTrue(report.saved.isEmpty)
    }

    func testVeryRecentFilesAreLeftAloneAsInProgress() async throws {
        let url = try await stage(named: "fresh", ageSeconds: 0)
        let inspector = FakeRecordingMediaInspector()
        inspector.nextInfo = RecordingMediaInfo(isPlayable: true, hasVideoTrack: true, duration: 3)
        let report = await RecordingRecovery(staging: staging, inspector: inspector, photos: FakePhotosLibrarySaver()).run()
        XCTAssertEqual(report, RecordingRecoveryReport())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
