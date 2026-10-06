import Foundation
import XCTest
@testable import Mellow

/// ADR-050 050-C C0 / C0a copy admission on isolated temporary roots with injected capacity readers. No Photos,
/// no picker automation, no real device store.
final class ImportCopyAdmissionTests: XCTestCase {
    private let reserve = ImportStoragePolicy.importSafetyReserveBytes
    private var root: URL!
    private var outside: URL!
    private var readOnly: [URL] = []

    override func setUpWithError() throws {
        root = TestSupport.temporaryRoot("copy-admission")
        outside = TestSupport.temporaryRoot("copy-admission-provider")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for directory in readOnly { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    /// Records every capacity reading and answers from a script (lock-based: the C0a reader is synchronous).
    final class CapacityLog: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URL] = []
        private let answer: Int64?
        init(_ answer: Int64?) { self.answer = answer }
        func read(_ location: URL) -> Int64? { lock.lock(); defer { lock.unlock() }; recorded.append(location); return answer }
        var locations: [URL] { lock.lock(); defer { lock.unlock() }; return recorded }
        var count: Int { locations.count }
    }

    private func file(_ bytes: Int, in directory: URL, name: String = UUID().uuidString) throws -> URL {
        let url = directory.appendingPathComponent(name).appendingPathExtension("mov")
        try Data(repeating: 0x42, count: bytes).write(to: url)
        return url
    }

    private func contents(_ directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    // MARK: - Shared check (source bytes + Import reserve)

    func testEqualityPassesAndOneByteShortFails() {
        XCTAssertTrue(ImportCopyAdmission.check(sourceBytes: 1_000, usableCapacity: 1_000 + reserve).passes, "equality passes")
        XCTAssertEqual(ImportCopyAdmission.check(sourceBytes: 1_000, usableCapacity: 999 + reserve),
                       .insufficient(requiredBytes: 1_000 + reserve, usableBytes: 999 + reserve))
        XCTAssertEqual(reserve, 268_435_456, "the accepted Import reserve, not the Phase 5 100 MiB")
    }

    func testUnknownInvalidAndOverflowFailClosed() {
        XCTAssertEqual(ImportCopyAdmission.check(sourceBytes: 1_000, usableCapacity: nil), .capacityUnknown(requiredBytes: 1_000 + reserve))
        XCTAssertEqual(ImportCopyAdmission.check(sourceBytes: 1_000, usableCapacity: -1), .capacityUnknown(requiredBytes: 1_000 + reserve))
        XCTAssertFalse(ImportCopyAdmission.check(sourceBytes: nil, usableCapacity: .max).passes, "unknown size")
        XCTAssertFalse(ImportCopyAdmission.check(sourceBytes: -1, usableCapacity: .max).passes, "invalid size")
        XCTAssertEqual(ImportCopyAdmission.check(sourceBytes: .max, usableCapacity: .max), .invalidEstimate(.arithmeticOverflow))
        for check in [ImportStorageCheck.capacityUnknown(requiredBytes: 5), .invalidEstimate(.arithmeticOverflow)] {
            guard case .insufficient = ImportCopyAdmission.verdict(check) else { return XCTFail("\(check) must refuse") }
        }
    }

    func testTransferGateUsesSourceBytesPlusImportReserve() async {
        let gate = ImportTransferCopyGate { 5_000 + self.reserve }
        let pass = await gate.check(additionalBytes: 5_000)
        XCTAssertEqual(pass, .sufficient)
        let short = await gate.check(additionalBytes: 5_001)
        XCTAssertEqual(short, .insufficient(requiredBytes: 5_001 + reserve, usableBytes: 5_000 + reserve))
        let unknown = await ImportTransferCopyGate { nil }.check(additionalBytes: 1)
        XCTAssertEqual(unknown, .insufficient(requiredBytes: 1 + reserve, usableBytes: 0))
        let negative = await gate.check(additionalBytes: -1)
        guard case .insufficient = negative else { return XCTFail("negative input fails closed") }
    }

    func testProductionReadersUseTheRequestedLocation() throws {
        XCTAssertNotNil(ImportCopyAdmission.usableCapacity(forVolumeOf: FileManager.default.temporaryDirectory), "transfer volume is readable")
        XCTAssertNil(ImportCopyAdmission.usableCapacity(forVolumeOf: outside.appendingPathComponent("missing/deeper")), "unreadable = unknown")
        let source = try file(1_234, in: outside)
        XCTAssertEqual(ImportCopyAdmission.sourceByteCount(of: source), 1_234)
        XCTAssertNil(ImportCopyAdmission.sourceByteCount(of: outside.appendingPathComponent("missing.mov")))
    }

    // MARK: - C0 in the shared received-file path

    func testC0ChecksTheExactSourceSizeBeforeCopying() async throws {
        let source = try file(4_321, in: outside)
        let log = CapacityLog(4_321 + reserve)
        let transfer = root.appendingPathComponent("ProjectMediaTransfer", isDirectory: true)
        let copied = try await ReceivedVideoFile.receive(source, into: transfer, gate: ImportTransferCopyGate { log.read(transfer) })
        let reads = log.count
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(try Data(contentsOf: copied).count, 4_321)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the provider's file is never touched")
    }

    func testC0RefusalCopiesNothingAndPreservesTheSource() async throws {
        let source = try file(4_321, in: outside)
        let transfer = root.appendingPathComponent("ProjectMediaTransfer", isDirectory: true)
        for capacity in [Int64(4_320) + reserve, nil] {
            do {
                _ = try await ReceivedVideoFile.receive(source, into: transfer, gate: ImportTransferCopyGate { capacity })
                XCTFail("must refuse")
            } catch let refusal as ProjectMediaAdmissionRefused {
                XCTAssertEqual(refusal.boundary, .c0TransferCopy)
            }
            XCTAssertTrue(contents(transfer).isEmpty, "no partial or new copy")
            XCTAssertEqual(try Data(contentsOf: source).count, 4_321)
        }
    }

    func testC0UnknownSizeOrMissingGateNeverPasses() async throws {
        let transfer = root.appendingPathComponent("ProjectMediaTransfer", isDirectory: true)
        let log = CapacityLog(.max)
        do {
            _ = try await ReceivedVideoFile.receive(outside.appendingPathComponent("vanished.mov"), into: transfer,
                                                    gate: ImportTransferCopyGate { log.read(transfer) })
            XCTFail("unknown size must refuse")
        } catch let refusal as ProjectMediaAdmissionRefused {
            XCTAssertEqual(refusal.reason, .sourceSizeUnknown)
        }
        let reads = log.count
        XCTAssertEqual(reads, 0, "an unknown size refuses before any capacity read")

        let source = try file(10, in: outside)
        do {
            _ = try await ReceivedVideoFile.receive(source, into: transfer, gate: nil)
            XCTFail("no published gate must never mean a silent pass")
        } catch is ProjectMediaAdmissionRefused {}
        XCTAssertTrue(contents(transfer).isEmpty)
    }

    // MARK: - C0a in adoption's copy fallback

    func testSuccessfulRenameNeverReadsCapacity() async throws {
        let log = CapacityLog(0)   // would refuse if it were ever consulted
        let store = ProjectMediaStore(root: root, copyFallbackCapacity: { log.read($0) })
        let workspace = try await store.beginWorkspace()
        let source = try file(2_000, in: FileManager.default.temporaryDirectory)
        let adopted = try await store.adopt(source, into: workspace)
        XCTAssertTrue(FileManager.default.fileExists(atPath: adopted.path))
        let reads = log.count
        XCTAssertEqual(reads, 0, "a rename charges no copy bytes and reads no capacity")
    }

    /// The source's parent is made read-only, so `rename` fails while `copy` still works: the real fallback path.
    private func fallbackSource(_ bytes: Int) throws -> URL {
        let directory = outside.appendingPathComponent("locked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try file(bytes, in: directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        readOnly.append(directory)
        return source
    }

    func testCopyFallbackRunsC0aOnTheMellowRootVolumeBeforeWriting() async throws {
        let log = CapacityLog(3_000 + reserve)
        let store = ProjectMediaStore(root: root, copyFallbackCapacity: { log.read($0) })
        let workspace = try await store.beginWorkspace()
        let source = try fallbackSource(3_000)
        let adopted = try await store.adopt(source, into: workspace)
        XCTAssertEqual(try Data(contentsOf: adopted).count, 3_000)
        let locations = log.locations
        XCTAssertEqual(locations.map(\.standardizedFileURL.path), [workspace.directory.standardizedFileURL.path],
                       "one reading, of the Mellow-root (workspace) volume only")
    }

    func testC0aRefusalWritesNothingAndPreservesTheSource() async throws {
        for capacity in [Int64(2_999) + reserve, nil] {
            let store = ProjectMediaStore(root: root, copyFallbackCapacity: { _ in capacity })
            let workspace = try await store.beginWorkspace()
            let source = try fallbackSource(3_000)
            do {
                _ = try await store.adopt(source, into: workspace)
                XCTFail("must refuse")
            } catch let refusal as ProjectMediaAdmissionRefused {
                XCTAssertEqual(refusal.boundary, .c0aAdoptionCopyFallback)
                XCTAssertEqual(refusal.reason, capacity == nil ? .capacityUnknown : .insufficient)
            }
            XCTAssertTrue(contents(workspace.directory).isEmpty, "no copy was started")
            XCTAssertEqual(try Data(contentsOf: source).count, 3_000, "the source is preserved")
            await store.discard(workspace)
        }
    }

    // MARK: - Presentation and the unchanged final guard

    @MainActor
    func testAdmissionRefusalUsesR4Section4CopyWhileTheFinalGuardKeepsItsOwn() {
        typealias Entry = ProjectsEntryModel.CompositionMessage
        XCTAssertEqual(Entry.importStorageInsufficient.title, "저장 공간이 부족해요")
        XCTAssertEqual(Entry.importStorageInsufficient.message, "영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.")
        XCTAssertEqual(ProjectEditorMessage.addImportStorageInsufficient.title, "저장 공간이 부족해요")
        XCTAssertEqual(ProjectEditorMessage.addImportStorageInsufficient.message, "영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.")
        // The Phase 5 commit-time final guard: same reserve, same copy as before.
        XCTAssertEqual(ProjectCompositionPolicy.materializationSafetyReserveBytes, 104_857_600)
        XCTAssertEqual(Entry.insufficientStorage.message, "공간을 확보한 뒤 다시 시도해 주세요.")
        XCTAssertEqual(ProjectEditorMessage.addInsufficientStorage.message, "공간을 확보한 뒤 다시 시도해 주세요.")
    }
}
