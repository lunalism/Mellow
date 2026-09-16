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

/// The one filesystem surface physical cleanup (STEP 12A) may use: removal of exactly one canonical
/// committed copy plus the existence check that verifies it. Nothing here can reach a workspace,
/// capture staging, Photos or anything outside the Mellow root.
protocol ProjectMediaCleanupStoring: Sendable {
    /// Removes the committed copy at `path`, which MUST equal
    /// `Projects/<projectID>/Media/<clipID>.mov` (`ProjectMediaStoreError.pathNotCanonical` otherwise).
    /// Idempotent: an already-absent file is success. Throws `removalFailed` when the file still
    /// exists afterwards, so a caller can never finalize metadata over a surviving file.
    func removeCommittedMedia(_ path: RelativeMediaPath, projectID: UUID, clipID: UUID) async throws
    func fileExists(_ path: RelativeMediaPath) async -> Bool
}

/// Pure, exhaustive classifier of the three filesystem shapes Mellow owns under its root (STEP 12B,
/// ADR-039). Everything it does not recognise is "noncanonical" and is preserved by every caller.
/// Names are matched by UUID round-trip (`UUID(uuidString:)` then `uuidString` equality), so a
/// lowercase / braced / 32-hex spelling that Mellow never writes is rejected, and the media extension
/// must be exactly lowercase `mov` — the only form `materialize` produces.
enum ProjectMediaLayout {
    static let projectsComponent = "Projects"
    static let mediaComponent = "Media"
    static let workspacesComponent = "ProjectWorkspace"
    static let mediaExtension = "mov"

    /// A canonical UUID as Mellow writes it (`UUID().uuidString`): uppercase, hyphenated.
    static func canonicalUUID(_ name: String) -> UUID? {
        guard let uuid = UUID(uuidString: name), uuid.uuidString == name else { return nil }
        return uuid
    }

    /// The Clip ID of a canonical committed media file name (`<UUID>.mov`), else nil.
    static func committedMediaClipID(fileName: String) -> UUID? {
        let url = URL(fileURLWithPath: fileName)
        guard url.pathExtension == mediaExtension, fileName == url.deletingPathExtension().lastPathComponent + "." + mediaExtension else { return nil }
        return canonicalUUID(url.deletingPathExtension().lastPathComponent)
    }
}

/// One directory entry as the store classified it. `noncanonical` carries a short reason for logs
/// only; the entry itself is never touched by recovery.
enum ProjectRecoveryEntry: Equatable, Sendable {
    case canonical(UUID)
    case noncanonical(name: String, reason: String)
}

/// The filesystem surface startup orphan recovery (STEP 12B) may use: shallow classified enumeration
/// of the two Mellow-owned roots plus the strict removal primitives. Every removal is built from a
/// UUID (never a caller path), root-contained, symlink-refusing, idempotent and observable.
protocol ProjectOrphanRecoveryStoring: Sendable {
    /// Direct children of `Projects/`.
    func enumerateProjectDirectories() async throws -> [ProjectRecoveryEntry]
    /// Direct children of `Projects/<projectID>/Media/` (empty when the directory does not exist).
    func enumerateCommittedMedia(projectID: UUID) async throws -> [ProjectRecoveryEntry]
    /// Direct children of `ProjectWorkspace/`; a workspace owned by a live operation of THIS process
    /// is reported as `noncanonical(reason: "live")` so callers never consider it.
    func enumerateWorkspaces() async throws -> [ProjectRecoveryEntry]
    func removeCommittedMedia(_ path: RelativeMediaPath, projectID: UUID, clipID: UUID) async throws
    /// Removes the whole canonical `Projects/<projectID>/` directory. Missing = success.
    func removeOrphanProjectDirectory(projectID: UUID) async throws
    /// Removes the canonical `ProjectWorkspace/<id>/` directory unless the operation is live in this
    /// process (then nothing happens and `false` is returned). Missing = success (`true`).
    func removeAbandonedWorkspace(id: UUID) async throws -> Bool
}

enum ProjectMediaStoreError: Error, Equatable {
    case destinationAlreadyExists
    case sourceMissing
    case mediaMissing
    case pathEscapesRoot
    /// Cleanup was handed a path that is not the canonical committed copy of that Project / Clip.
    case pathNotCanonical
    /// The committed copy still exists after a removal attempt.
    case removalFailed
    /// A recovery candidate is (or sits behind) a symbolic link; it is never followed or removed.
    case symbolicLink
}

actor ProjectMediaStore: ProjectMediaStoring, ProjectMediaURLResolving, ProjectMediaCleanupStoring, ProjectOrphanRecoveryStoring {
    private let root: URL
    private let fileManager = FileManager.default
    /// Workspaces begun by THIS process and not yet discarded (ADR-039 STEP 12B). The startup sweep
    /// removes abandoned workspaces with no age threshold; this registry is what keeps a workspace
    /// the picker is filling right now out of its reach. Registry and removal are both actor-isolated,
    /// so there is no check-then-act window.
    private var liveWorkspaceIDs: Set<UUID> = []

    /// The canonical committed location of one Clip's Project-owned copy, relative to the Mellow root.
    /// Materialization writes exactly here and cleanup accepts exactly this (nothing else).
    static func committedMediaPath(projectID: UUID, clipID: UUID) throws -> RelativeMediaPath {
        try RelativeMediaPath("Projects/\(projectID.uuidString)/Media/\(clipID.uuidString).mov")
    }

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
        liveWorkspaceIDs.insert(id)
        return ProjectMediaWorkspace(id: id, directory: directory)
    }

    var liveWorkspaceCount: Int { liveWorkspaceIDs.count }

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
        let relative = try Self.committedMediaPath(projectID: projectID, clipID: clipID)
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
        // Ownership ends here whatever the filesystem says: a directory that survives a failed
        // removal is an abandoned workspace for the next launch's sweep, never a leaked live ID.
        defer { liveWorkspaceIDs.remove(workspace.id) }
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

    func removeCommittedMedia(_ path: RelativeMediaPath, projectID: UUID, clipID: UUID) async throws {
        // Ownership is proven by exact equality with the canonical layout, not by prefix matching:
        // a workspace file, another Clip's copy, another Project's directory or a traversal attempt
        // all fail here before any filesystem call.
        guard path == (try Self.committedMediaPath(projectID: projectID, clipID: clipID)) else {
            throw ProjectMediaStoreError.pathNotCanonical
        }
        let url = root.appendingPathComponent(path.value).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw ProjectMediaStoreError.pathEscapesRoot }
        guard let type = try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType else { return }
        guard type != .typeSymbolicLink else { throw ProjectMediaStoreError.symbolicLink }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            if fileManager.fileExists(atPath: url.path) { throw ProjectMediaStoreError.removalFailed }
        }
        guard !fileManager.fileExists(atPath: url.path) else { throw ProjectMediaStoreError.removalFailed }
    }

    // MARK: - STEP 12B startup recovery surface (ADR-039)

    func enumerateProjectDirectories() async throws -> [ProjectRecoveryEntry] {
        try classifiedChildren(of: projectsDirectory, expectDirectory: true) { ProjectMediaLayout.canonicalUUID($0) }
    }

    func enumerateCommittedMedia(projectID: UUID) async throws -> [ProjectRecoveryEntry] {
        let media = projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(ProjectMediaLayout.mediaComponent, isDirectory: true)
        return try classifiedChildren(of: media, expectDirectory: false) { ProjectMediaLayout.committedMediaClipID(fileName: $0) }
    }

    func enumerateWorkspaces() async throws -> [ProjectRecoveryEntry] {
        try classifiedChildren(of: workspacesDirectory, expectDirectory: true) { ProjectMediaLayout.canonicalUUID($0) }
            .map { entry in
                if case .canonical(let id) = entry, liveWorkspaceIDs.contains(id) { return .noncanonical(name: id.uuidString, reason: "live") }
                return entry
            }
    }

    func removeOrphanProjectDirectory(projectID: UUID) async throws {
        let directory = projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        try removeOwnedDirectory(directory)
    }

    func removeAbandonedWorkspace(id: UUID) async throws -> Bool {
        guard !liveWorkspaceIDs.contains(id) else { return false }
        try removeOwnedDirectory(workspacesDirectory.appendingPathComponent(id.uuidString, isDirectory: true))
        return true
    }

    /// Shallow, non-following listing of one owned directory. A missing directory lists as empty.
    /// Every child is classified by name AND by its own (unresolved) file type: a symlink is never
    /// canonical whatever its name, and the expected type (directory / regular file) must match.
    private func classifiedChildren(of directory: URL, expectDirectory: Bool, canonical: (String) -> UUID?) throws -> [ProjectRecoveryEntry] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let names = try fileManager.contentsOfDirectory(atPath: directory.path)
        return names.sorted().map { name in
            let url = directory.appendingPathComponent(name)
            guard let type = try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType else {
                return .noncanonical(name: name, reason: "unreadable")
            }
            guard type != .typeSymbolicLink else { return .noncanonical(name: name, reason: "symlink") }
            guard type == (expectDirectory ? .typeDirectory : .typeRegular) else { return .noncanonical(name: name, reason: "type") }
            guard let id = canonical(name) else { return .noncanonical(name: name, reason: "name") }
            return .canonical(id)
        }
    }

    /// Removes one canonical Mellow-owned directory built from a UUID: root-contained, never a
    /// symlink (the link itself would be removed by `removeItem`; the target never — but recovery
    /// refuses even that), missing = success, survivor = `removalFailed`.
    private func removeOwnedDirectory(_ directory: URL) throws {
        let url = directory.standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw ProjectMediaStoreError.pathEscapesRoot }
        guard let type = try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType else { return }
        guard type != .typeSymbolicLink else { throw ProjectMediaStoreError.symbolicLink }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            if fileManager.fileExists(atPath: url.path) { throw ProjectMediaStoreError.removalFailed }
        }
        guard !fileManager.fileExists(atPath: url.path) else { throw ProjectMediaStoreError.removalFailed }
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

#if DEBUG
/// UI-test / physical-review fixture helpers (never Release): write, probe or remove one file by a
/// root-relative path. Containment is enforced; they never touch anything outside the Mellow root.
extension ProjectMediaStore {
    func debugWriteFixture(relativePath: String) async throws {
        let url = try debugContainedURL(relativePath)
        try ensureDirectory(url.deletingLastPathComponent())
        try Data(repeating: 0x4D, count: 64).write(to: url)
    }

    func debugFixtureExists(relativePath: String) async -> Bool {
        guard let url = try? debugContainedURL(relativePath) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    /// Removes the file AND its immediate parent directory when that parent became empty (fixture
    /// directories like `Projects/not-a-project/`), never the Mellow roots themselves.
    func debugRemoveFixture(relativePath: String) async {
        guard let url = try? debugContainedURL(relativePath) else { return }
        try? fileManager.removeItem(at: url)
        let parent = url.deletingLastPathComponent()
        let depth = parent.standardizedFileURL.pathComponents.count - root.standardizedFileURL.pathComponents.count
        if depth >= 2, (try? fileManager.contentsOfDirectory(atPath: parent.path))?.isEmpty == true {
            try? fileManager.removeItem(at: parent)
        }
    }

    private func debugContainedURL(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw ProjectMediaStoreError.pathEscapesRoot }
        return url
    }
}
#endif
