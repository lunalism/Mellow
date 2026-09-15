import XCTest
@testable import Mellow

final class ProjectMediaStoreTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!

    override func setUp() {
        root = TestSupport.temporaryRoot("media-store")
        store = ProjectMediaStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func testAdoptMovesTransferIntoWorkspaceAndMaterializeIsStableRelativePath() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let workspace = try await store.beginWorkspace()
        let transfer = try TestSupport.transferCopy(of: fixture)
        let adopted = try await store.adopt(transfer, into: workspace)
        XCTAssertFalse(TestSupport.exists(transfer), "the picker transfer is taken over, not duplicated")
        XCTAssertTrue(adopted.path.hasPrefix(workspace.directory.path))

        let projectID = UUID(), clipID = UUID()
        let path = try await store.materialize(adopted, projectID: projectID, clipID: clipID)
        XCTAssertEqual(path.value, "Projects/\(projectID.uuidString)/Media/\(clipID.uuidString).mov")
        XCTAssertFalse(path.value.hasPrefix("/"))
        await assertFileExists(store, path, true)
        XCTAssertFalse(TestSupport.exists(adopted), "materialization is a move, no workspace duplicate")

        // The committed copy outlives the workspace and the original fixture location.
        await store.discard(workspace)
        await assertFileExists(store, path, true)
        XCTAssertTrue(TestSupport.exists(fixture), "the external source is never deleted")
    }

    func testMaterializeRefusesCollisionAndMissingSource() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let workspace = try await store.beginWorkspace()
        let projectID = UUID(), clipID = UUID()
        let a = try await store.adopt(try TestSupport.transferCopy(of: fixture), into: workspace)
        let b = try await store.adopt(try TestSupport.transferCopy(of: fixture), into: workspace)
        _ = try await store.materialize(a, projectID: projectID, clipID: clipID)
        do {
            _ = try await store.materialize(b, projectID: projectID, clipID: clipID)
            XCTFail("collision must not overwrite a committed copy")
        } catch let error as ProjectMediaStoreError {
            XCTAssertEqual(error, .destinationAlreadyExists)
        }
        do {
            _ = try await store.materialize(workspace.directory.appendingPathComponent("nope.mov"), projectID: projectID, clipID: UUID())
            XCTFail()
        } catch let error as ProjectMediaStoreError {
            XCTAssertEqual(error, .sourceMissing)
        }
    }

    func testDiscardAndRemoveProjectMediaAreIdempotent() async throws {
        let fixture = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let workspace = try await store.beginWorkspace()
        let adopted = try await store.adopt(try TestSupport.transferCopy(of: fixture), into: workspace)
        let projectID = UUID()
        let path = try await store.materialize(adopted, projectID: projectID, clipID: UUID())

        await store.discard(workspace)
        await store.discard(workspace)
        XCTAssertFalse(TestSupport.exists(workspace.directory))

        await store.removeProjectMedia(projectID: projectID)
        await store.removeProjectMedia(projectID: projectID)
        await assertFileExists(store, path, false)
        await store.removeProjectMedia(projectID: UUID()) // unknown project: no-op
    }

    func testWorkspacesAreIsolatedFromCommittedMedia() async throws {
        let a = try await store.beginWorkspace()
        let b = try await store.beginWorkspace()
        XCTAssertNotEqual(a.directory, b.directory)
        XCTAssertTrue(a.directory.path.contains("ProjectWorkspace"))
        XCTAssertFalse(a.directory.path.contains("/Projects/"))
    }
}
