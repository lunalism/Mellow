import Foundation

/// A per-operation scratch directory for Project composition (ADR-020 "Temporary Workspace").
/// Transferred picker files land here; nothing in it is ever a committed Clip.
struct ProjectMediaWorkspace: Hashable, Sendable {
    let id: UUID
    let directory: URL
}

/// App-managed Project media (ARCHITECTURE §23): `Mellow/Projects/<Project UUID>/Media/<Clip UUID>.mov`
/// under Application Support, addressed by `RelativeMediaPath` from the `Mellow/` root. Owns the
/// only filesystem mutation for Project-owned copies and operation workspaces. It never touches
/// Photos originals and never reuses the Phase 4 capture staging directory.
protocol ProjectMediaStoring: Sendable {
    func beginWorkspace() async throws -> ProjectMediaWorkspace
    /// Moves a file the operation already controls into the workspace (same container → rename).
    func adopt(_ url: URL, into workspace: ProjectMediaWorkspace) async throws -> URL
    /// Atomically finalizes a validated workspace file as the Project-owned copy for `clipID`.
    func materialize(_ url: URL, projectID: UUID, clipID: UUID) async throws -> RelativeMediaPath
    func url(for path: RelativeMediaPath) async -> URL
    func fileExists(_ path: RelativeMediaPath) async -> Bool
    /// Idempotent: removes the workspace and everything in it if it still exists.
    func discard(_ workspace: ProjectMediaWorkspace) async
    /// Idempotent: removes every app-owned copy of the Project. Never Photos.
    func removeProjectMedia(projectID: UUID) async
    /// Idempotent: removes ONE app-owned copy (a file this operation created and never committed).
    /// Never Photos; never anything outside the Mellow root.
    func removeMedia(_ path: RelativeMediaPath) async
    func usableCapacityBytes() async -> Int64
}

/// Read-only resolution of a committed `RelativeMediaPath` to its local file URL, for consumers
/// that only read Project-owned media (thumbnails now; preview / export later). It never creates,
/// moves or deletes anything, and it never yields a URL outside the Mellow-owned root.
protocol ProjectMediaURLResolving: Sendable {
    /// Throws `ProjectMediaStoreError.mediaMissing` when no file exists at the path and
    /// `.pathEscapesRoot` when the resolved location would leave the Mellow root.
    func committedMediaURL(for path: RelativeMediaPath) async throws -> URL
}

enum ProjectMediaStoreError: Error, Equatable {
    case destinationAlreadyExists
    case sourceMissing
    case mediaMissing
    case pathEscapesRoot
}

actor ProjectMediaStore: ProjectMediaStoring, ProjectMediaURLResolving {
    private let root: URL
    private let fileManager = FileManager.default

    /// `root` defaults to `Application Support/Mellow`; tests inject a temporary root.
    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = support.appendingPathComponent("Mellow", isDirectory: true)
        }
    }

    private var projectsDirectory: URL { root.appendingPathComponent("Projects", isDirectory: true) }
    private var workspacesDirectory: URL { root.appendingPathComponent("ProjectWorkspace", isDirectory: true) }

    func beginWorkspace() async throws -> ProjectMediaWorkspace {
        let id = UUID()
        let directory = workspacesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try ensureDirectory(directory)
        return ProjectMediaWorkspace(id: id, directory: directory)
    }

    func adopt(_ url: URL, into workspace: ProjectMediaWorkspace) async throws -> URL {
        guard fileManager.fileExists(atPath: url.path) else { throw ProjectMediaStoreError.sourceMissing }
        try ensureDirectory(workspace.directory)
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
        let destination = workspace.directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do {
            try fileManager.moveItem(at: url, to: destination)
        } catch {
            // Cross-volume (e.g. a picker-provided location): copy, then drop the original we own.
            try fileManager.copyItem(at: url, to: destination)
            try? fileManager.removeItem(at: url)
        }
        return destination
    }

    func materialize(_ url: URL, projectID: UUID, clipID: UUID) async throws -> RelativeMediaPath {
        guard fileManager.fileExists(atPath: url.path) else { throw ProjectMediaStoreError.sourceMissing }
        let relative = try RelativeMediaPath("Projects/\(projectID.uuidString)/Media/\(clipID.uuidString).mov")
        let destination = root.appendingPathComponent(relative.value)
        guard !fileManager.fileExists(atPath: destination.path) else { throw ProjectMediaStoreError.destinationAlreadyExists }
        try ensureDirectory(destination.deletingLastPathComponent())
        // Same container: an atomic rename, so a committed copy is never partially written.
        try fileManager.moveItem(at: url, to: destination)
        return relative
    }

    func url(for path: RelativeMediaPath) async -> URL {
        root.appendingPathComponent(path.value)
    }

    func fileExists(_ path: RelativeMediaPath) async -> Bool {
        fileManager.fileExists(atPath: root.appendingPathComponent(path.value).path)
    }

    func committedMediaURL(for path: RelativeMediaPath) async throws -> URL {
        // `RelativeMediaPath` already refuses absolute and `..` components; standardizing and
        // re-checking containment keeps this read boundary safe even if that invariant ever slips.
        let rootPath = root.standardizedFileURL.path
        let url = root.appendingPathComponent(path.value).standardizedFileURL
        guard url.path.hasPrefix(rootPath + "/") else { throw ProjectMediaStoreError.pathEscapesRoot }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ProjectMediaStoreError.mediaMissing
        }
        return url
    }

    func discard(_ workspace: ProjectMediaWorkspace) async {
        guard fileManager.fileExists(atPath: workspace.directory.path) else { return }
        try? fileManager.removeItem(at: workspace.directory)
    }

    func removeProjectMedia(projectID: UUID) async {
        let directory = projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try? fileManager.removeItem(at: directory)
    }

    func removeMedia(_ path: RelativeMediaPath) async {
        let url = root.appendingPathComponent(path.value).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/"), fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    func usableCapacityBytes() async -> Int64 {
        try? ensureDirectory(root)
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func ensureDirectory(_ directory: URL) throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
