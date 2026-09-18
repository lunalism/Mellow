import XCTest
@testable import Mellow

/// Root-containment behaviour of `ProjectMediaStore` under filesystem path aliases (ADR-020 /
/// ADR-037 / ADR-039 media-safety rules). Motivated by the LunaTestphone finding that a test root
/// created from the raw `/private/var/...` temp directory made every *missing* in-root candidate
/// report `pathEscapesRoot` instead of `mediaMissing`, because `standardizedFileURL` drops the
/// `/private` prefix only for paths that exist. Production roots (`Application Support`) are
/// already in the `/var/...` form; `TestSupport.temporaryRoot` now models that.
final class ProjectMediaPathContainmentTests: XCTestCase {
    private var base: URL!

    override func setUp() {
        base = TestSupport.temporaryRoot("containment")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: base) }

    private func canonical(_ projectID: UUID = UUID(), _ clipID: UUID = UUID()) throws -> RelativeMediaPath {
        try ProjectMediaStore.committedMediaPath(projectID: projectID, clipID: clipID)
    }

    private func write(_ store: ProjectMediaStore, _ path: RelativeMediaPath) async throws -> URL {
        let url = await store.url(for: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 16).write(to: url)
        return url
    }

    // MARK: Alias form of the test root (the actual root cause)

    func testTemporaryRootUsesOneStableAliasFormLikeProductionRoots() {
        let root = TestSupport.temporaryRoot("alias")
        // The root is already standardized, so an existing/missing child never changes form.
        XCTAssertEqual(root.path, root.standardizedFileURL.path)
        XCTAssertEqual(root.appendingPathComponent("missing/leaf.mov").standardizedFileURL.path, root.path + "/missing/leaf.mov")
        // On hosts where `/var` is an alias of `/private/var` (physical iPhone), the root must not
        // carry the `/private` form that only existing paths get normalized away from.
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var")) == "private/var" {
            XCTAssertFalse(root.path.hasPrefix("/private/"), root.path)
        }
        let production = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(production.path, production.standardizedFileURL.path, "production root is already in canonical alias form")
    }

    func testRawPrivateTempRootReproducesTheDeviceMismatchOnlyOnAliasHosts() async throws {
        // Documents the failure mode with the raw temp directory, without asserting `/var` exists
        // on every host: where the raw form differs from the standardized one, a missing leaf keeps
        // the raw form while the existing root loses it.
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("raw-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raw) }
        let missing = raw.appendingPathComponent("Projects/P/Media/missing.mov")
        if raw.path != raw.standardizedFileURL.path {
            XCTAssertNotEqual(missing.standardizedFileURL.path.hasPrefix(raw.standardizedFileURL.path + "/"), true, "alias host: raw-form root would mis-classify a missing leaf")
        } else {
            XCTAssertTrue(missing.standardizedFileURL.path.hasPrefix(raw.standardizedFileURL.path + "/"))
        }
        // Either way the standardized root is safe to use.
        let store = ProjectMediaStore(root: raw.standardizedFileURL)
        await assertMissing(store, try RelativeMediaPath("Projects/P/Media/missing.mov"))
    }

    // MARK: Valid in-root candidates

    func testExistingAndMissingCandidatesInsideRoot() async throws {
        let store = ProjectMediaStore(root: base.appendingPathComponent("root", isDirectory: true))
        let path = try canonical()
        let url = try await write(store, path)
        let resolved = try await store.committedMediaURL(for: path)
        XCTAssertEqual(resolved.standardizedFileURL.path, url.standardizedFileURL.path)
        // Missing leaf in an existing directory → mediaMissing, never pathEscapesRoot.
        await assertMissing(store, try RelativeMediaPath(url.deletingLastPathComponent().lastPathComponent == "Media" ? path.value.replacingOccurrences(of: ".mov", with: "-gone.mov") : path.value))
        // Missing intermediate directories → mediaMissing.
        await assertMissing(store, try canonical())
        // Cleanup / removal of a missing canonical file is a no-op success.
        await store.removeMedia(try canonical())
        try await store.removeCommittedMedia(path, projectID: projectID(of: path), clipID: clipID(of: path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try await store.removeCommittedMedia(path, projectID: projectID(of: path), clipID: clipID(of: path)) // idempotent
    }

    func testRootExpressedThroughASymlinkAliasStaysConsistent() async throws {
        // A deterministic alias: `link -> real`. Root and candidates share the alias form, so an
        // existing file resolves and a missing one is "missing" — the alias never becomes an escape.
        let real = base.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let store = ProjectMediaStore(root: link)
        let path = try canonical()
        _ = try await write(store, path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: real.appendingPathComponent(path.value).path), "written through the alias into the real root")
        _ = try await store.committedMediaURL(for: path)
        await assertMissing(store, try canonical())
        // The reverse form (real root, alias-created file) is the same physical file.
        let realStore = ProjectMediaStore(root: real)
        _ = try await realStore.committedMediaURL(for: path)
    }

    // MARK: Security boundary

    func testTraversalAndAbsolutePathsAreRejectedBeforeAnyFilesystemAccess() {
        XCTAssertThrowsError(try RelativeMediaPath("../outside.mov"))
        XCTAssertThrowsError(try RelativeMediaPath("Projects/../../outside.mov"))
        XCTAssertThrowsError(try RelativeMediaPath("/private/var/outside.mov"))
        XCTAssertThrowsError(try RelativeMediaPath("/var/outside.mov"))
    }

    func testSiblingPrefixDirectoryIsNotTreatedAsInsideTheRoot() async throws {
        let root = base.appendingPathComponent("root", isDirectory: true)
        let sibling = base.appendingPathComponent("root-sibling", isDirectory: true)
        let path = try canonical()
        let siblingFile = sibling.appendingPathComponent(path.value)
        try FileManager.default.createDirectory(at: siblingFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 9, count: 4).write(to: siblingFile)
        let store = ProjectMediaStore(root: root)
        await assertMissing(store, path)
        try await store.removeCommittedMedia(path, projectID: projectID(of: path), clipID: clipID(of: path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: siblingFile.path), "cleanup never touches a sibling-prefixed directory")
    }

    func testInRootSymlinkToOutsideIsRefusedByCleanupAndTheTargetSurvives() async throws {
        let root = base.appendingPathComponent("root", isDirectory: true)
        let external = base.appendingPathComponent("external.mov")
        try Data(repeating: 7, count: 8).write(to: external)
        let store = ProjectMediaStore(root: root)
        let path = try canonical()
        let url = await store.url(for: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: external)
        do {
            try await store.removeCommittedMedia(path, projectID: projectID(of: path), clipID: clipID(of: path))
            XCTFail("a symlink at the canonical path must be refused")
        } catch let error as ProjectMediaStoreError {
            XCTAssertEqual(error, .symbolicLink)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: url.path), "the link itself is left in place")
        // Recovery classifies the link as noncanonical and never removes through it.
        let entries = try await store.enumerateCommittedMedia(projectID: projectID(of: path))
        XCTAssertEqual(entries, [.noncanonical(name: url.lastPathComponent, reason: "symlink")])
    }

    func testExternalPathCannotBeReachedThroughAliasNormalization() async throws {
        let root = base.appendingPathComponent("root", isDirectory: true)
        let store = ProjectMediaStore(root: root)
        let outside = base.appendingPathComponent("Projects/\(UUID().uuidString)/Media/\(UUID().uuidString).mov")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 3, count: 4).write(to: outside)
        // The same relative layout exists one level above the root; the store must not see it.
        let path = try RelativeMediaPath(outside.path.replacingOccurrences(of: base.path + "/", with: ""))
        await assertMissing(store, path)
        await store.removeMedia(path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    // MARK: Helpers

    private func assertMissing(_ store: ProjectMediaStore, _ path: RelativeMediaPath, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await store.committedMediaURL(for: path)
            XCTFail("expected mediaMissing for \(path.value)", file: file, line: line)
        } catch let error as ProjectMediaStoreError {
            XCTAssertEqual(error, .mediaMissing, path.value, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }

    private func projectID(of path: RelativeMediaPath) -> UUID { UUID(uuidString: path.value.split(separator: "/")[1].description)! }
    private func clipID(of path: RelativeMediaPath) -> UUID { UUID(uuidString: String(path.value.split(separator: "/")[3].dropLast(4)))! }
}
