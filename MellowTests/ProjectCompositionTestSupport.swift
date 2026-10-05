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
    /// A fresh media root in the same path form production uses. On a physical iPhone
    /// `temporaryDirectory` is reported as `/private/var/...` while `Application Support` (the
    /// production root) is `/var/...`; `standardizedFileURL` strips `/private` only for paths that
    /// exist, so a raw `/private/var` root would make every *missing* in-root candidate look like it
    /// escaped the root. Standardizing the (existing) temp directory once, up front, keeps root and
    /// candidates in one alias form exactly like production.
    static func temporaryRoot(_ label: String = "root") -> URL {
        FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    /// Thumbnail / availability requests are issued from a `withTaskGroup` fan-out, so the order in
    /// which a test double records them is not a production contract (ARCHITECTURE: the consumer
    /// gate observes no request ordering). Compare *membership and multiplicity* instead: a sorted
    /// list of identifiers keeps duplicates visible where a `Set` would hide them.
    static func sortedIDs(_ ids: [UUID]) -> [String] { ids.map(\.uuidString).sorted() }
    static func sortedClipIDs(_ requests: [ClipThumbnailRequest]) -> [String] { sortedIDs(requests.map(\.clipID)) }

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

/// Repository whose writes can be made to fail, for persistence-failure paths. Wraps an in-memory store
/// by default, or any real repository (for example SwiftData on an isolated on-disk store).
@MainActor
final class FailableProjectRepository: ProjectRepository {
    let inner: any ProjectRepository
    init(inner: (any ProjectRepository)? = nil) { self.inner = inner ?? InMemoryProjectRepository() }
    var createFails = false
    var deleteFails = false
    var updateFails = false
    var replaceFails = false
    /// The write lands, then the call throws: a save whose outcome the caller cannot see.
    var createThrowsAfterCommit = false
    var updateThrowsAfterCommit = false
    var deleteThrowsAfterCommit = false
    var replaceThrowsAfterCommit = false
    /// `project(id:)` throws for these IDs (an unreadable verification / absence read).
    var unreadableIDs: Set<UUID> = []
    /// `project(id:)` returns nil for these IDs although the row exists (a read-back that cannot see it).
    var hiddenIDs: Set<UUID> = []
    /// Every Project created while this is true is hidden from `project(id:)` read-back.
    var hideCreatedProjects = false
    var recentProjectsFails = false
    /// Replaces the fresh-read current-Project lookup (return nil to keep the real result).
    var currentProjectOverride: (() -> ObservedCurrentProject?)?
    private(set) var currentProjectObservations = 0
    /// Replaces the in-gate prior observation of one Project ID (return nil to keep the real result).
    var priorObservationOverride: ((UUID) -> ObservedProjectRecord?)?
    /// Rewrites the post-save observation (unreadable rows, missing evidence, contradictions).
    var stateObservationOverride: ((ProjectSaveExpectation, PersistedStateObservation) -> PersistedStateObservation)?
    /// Runs inside `create` / `replaceProject` before the write (gate / re-entrancy probes).
    var onSave: (() -> Void)?
    private(set) var createCount = 0
    private(set) var updateCount = 0
    private(set) var replaceCount = 0
    private(set) var deletedIDs: [UUID] = []
    private(set) var priorObservations: [UUID] = []
    private(set) var stateObservations: [ProjectSaveExpectation] = []
    /// Runs inside `update` before the write lands (re-entrancy probes).
    var onUpdate: (() -> Void)?
    enum Failure: Error { case injected }

    func create(_ project: VlogProject) throws {
        createCount += 1
        onSave?()
        if createFails { throw Failure.injected }
        try inner.create(project)
        if hideCreatedProjects { hiddenIDs.insert(project.id) }
        if createThrowsAfterCommit { throw Failure.injected }
    }
    func project(id: UUID) throws -> VlogProject? {
        if unreadableIDs.contains(id) { throw Failure.injected }
        if hiddenIDs.contains(id) { return nil }
        return try inner.project(id: id)
    }
    func recentProjects() throws -> [VlogProject] {
        if recentProjectsFails { throw Failure.injected }
        return try inner.recentProjects()
    }
    func update(_ project: VlogProject) throws {
        updateCount += 1
        onUpdate?()
        if updateFails { throw Failure.injected }
        try inner.update(project)
        if updateThrowsAfterCommit { throw Failure.injected }
    }
    func finalizeDeletedClip(projectID: UUID, clipID: UUID) throws { try inner.finalizeDeletedClip(projectID: projectID, clipID: clipID) }
    func deleteProject(id: UUID) throws {
        if deleteFails { throw Failure.injected }
        deletedIDs.append(id)
        try inner.deleteProject(id: id)
        if deleteThrowsAfterCommit { throw Failure.injected }
    }
    func replaceProject(previousID: UUID, with project: VlogProject) throws {
        replaceCount += 1
        onSave?()
        if replaceFails { throw Failure.injected }
        try inner.replaceProject(previousID: previousID, with: project)
        if replaceThrowsAfterCommit { throw Failure.injected }
    }
    func observePersistedProject(id: UUID) -> ObservedProjectRecord {
        priorObservations.append(id)
        return priorObservationOverride?(id) ?? inner.observePersistedProject(id: id)
    }
    func observeCurrentProjectID() -> ObservedCurrentProject {
        currentProjectObservations += 1
        return currentProjectOverride?() ?? inner.observeCurrentProjectID()
    }
    func observePersistedState(for expectation: ProjectSaveExpectation) -> PersistedStateObservation {
        stateObservations.append(expectation)
        let observed = inner.observePersistedState(for: expectation)
        return stateObservationOverride?(expectation, observed) ?? observed
    }
}

/// Test doubles that never compose do not observe persisted state; any accidental use fails closed
/// (unreadable / no evidence) instead of looking like a confirmed state.
/// A WRAPPER around a real repository must forward all three observation methods explicitly: these defaults
/// still compile for it and would silently fail closed (as `ProbingRepository` once did).
extension ProjectRepository {
    func observePersistedProject(id: UUID) -> ObservedProjectRecord { .unreadable }
    func observeCurrentProjectID() -> ObservedCurrentProject { .unreadable }
    func observePersistedState(for expectation: ProjectSaveExpectation) -> PersistedStateObservation {
        PersistedStateObservation(projects: [:], createdIdentityHolders: nil)
    }
}

/// Async-safe existence assertion for Project-owned media.
func assertFileExists(_ store: ProjectMediaStore, _ path: RelativeMediaPath, _ expected: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async {
    let exists = await store.fileExists(path)
    XCTAssertEqual(exists, expected, message, file: file, line: line)
}

// MARK: - Async assertions (Editor mutations commit through the lifecycle gate and are async)

@MainActor
func XCTAssertTrueAsync(_ expression: @autoclosure () async -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async {
    let value = await expression()
    XCTAssertTrue(value, message(), file: file, line: line)
}

@MainActor
func XCTAssertFalseAsync(_ expression: @autoclosure () async -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async {
    let value = await expression()
    XCTAssertFalse(value, message(), file: file, line: line)
}

@MainActor
func XCTAssertNilAsync<T>(_ expression: @autoclosure () async -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async {
    let value = await expression()
    XCTAssertNil(value, message(), file: file, line: line)
}

@MainActor
func XCTAssertEqualAsync<T: Equatable>(_ expression: @autoclosure () async -> T, _ expected: @autoclosure () -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async {
    let value = await expression()
    XCTAssertEqual(value, expected(), message(), file: file, line: line)
}

@MainActor
func XCTAssertNotNilAsync<T>(_ expression: @autoclosure () async -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async {
    let value = await expression()
    XCTAssertNotNil(value, message(), file: file, line: line)
}
