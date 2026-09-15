import Foundation
import XCTest
@testable import Mellow

/// Real fixture media generated once per test process (not per test) and shared read-only.
actor TestMediaFixtures {
    static let shared = TestMediaFixtures()
    private var cache: [String: URL] = [:]
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MellowTestFixtures-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    /// Portrait 540×960, 30 fps, SDR, no audio, `seconds` long.
    func portrait(seconds: Double, name: String? = nil) async throws -> URL {
        let key = name ?? "portrait-\(seconds)"
        if let url = cache[key] { return url }
        let url = directory.appendingPathComponent(key).appendingPathExtension("mov")
        try await FixtureVideoWriter.write(to: url, seconds: seconds)
        cache[key] = url
        return url
    }

    func corrupt() throws -> URL {
        if let url = cache["corrupt"] { return url }
        let url = directory.appendingPathComponent("corrupt").appendingPathExtension("mov")
        try FixtureVideoWriter.writeCorrupt(to: url)
        cache["corrupt"] = url
        return url
    }
}

enum TestSupport {
    static func temporaryRoot(_ label: String = "root") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    /// Copies a fixture to a fresh temporary URL (the "picker transfer"), leaving the fixture intact.
    static func transferCopy(of fixture: URL) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }

    /// Adopts fixture copies into `workspace` and returns them as selected sources.
    static func adoptedSources(_ fixtures: [URL], into workspace: ProjectMediaWorkspace, store: ProjectMediaStore) async throws -> [SelectedVideoSource] {
        var sources: [SelectedVideoSource] = []
        for fixture in fixtures {
            let adopted = try await store.adopt(try transferCopy(of: fixture), into: workspace)
            let bytes = (try? adopted.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            sources.append(SelectedVideoSource(url: adopted, byteCount: bytes))
        }
        return sources
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// True when no Project-owned media directory exists under `root` (the empty parent may remain).
    static func noProjectMedia(under root: URL) -> Bool {
        let projects = root.appendingPathComponent("Projects")
        guard exists(projects) else { return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: projects.path))?.isEmpty ?? true
    }
}

/// Repository whose writes can be made to fail, for persistence-failure paths.
@MainActor
final class FailableProjectRepository: ProjectRepository {
    let inner = InMemoryProjectRepository()
    var createFails = false
    var deleteFails = false
    private(set) var createCount = 0
    private(set) var deletedIDs: [UUID] = []
    enum Failure: Error { case injected }

    func create(_ project: VlogProject) throws {
        createCount += 1
        if createFails { throw Failure.injected }
        try inner.create(project)
    }
    func project(id: UUID) throws -> VlogProject? { try inner.project(id: id) }
    func recentProjects() throws -> [VlogProject] { try inner.recentProjects() }
    func update(_ project: VlogProject) throws { try inner.update(project) }
    func deleteProject(id: UUID) throws {
        if deleteFails { throw Failure.injected }
        deletedIDs.append(id)
        try inner.deleteProject(id: id)
    }
}

/// Async-safe existence assertion for Project-owned media.
func assertFileExists(_ store: ProjectMediaStore, _ path: RelativeMediaPath, _ expected: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async {
    let exists = await store.fileExists(path)
    XCTAssertEqual(exists, expected, message, file: file, line: line)
}
