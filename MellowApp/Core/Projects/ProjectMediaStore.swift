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
    /// The operation workspace is not live in this process (or is not a real directory).
    case workspaceNotLive
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

    /// The Mellow-root volume's usable capacity for C0a; nil = unknown (fails closed). Read only when `adopt`
    /// actually falls back to copying.
    private let copyFallbackCapacity: @Sendable (URL) -> Int64?

    /// `root` defaults to `Application Support/Mellow`; tests inject a temporary root and may inject the C0a
    /// capacity reader (default: the existing `volumeAvailableCapacityForImportantUsage` convention on `root`).
    init(root: URL? = nil, copyFallbackCapacity: (@Sendable (URL) -> Int64?)? = nil) {
        if let root {
            self.root = root
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = support.appendingPathComponent("Mellow", isDirectory: true)
        }
        self.copyFallbackCapacity = copyFallbackCapacity ?? { ImportCopyAdmission.usableCapacity(forVolumeOf: $0) }
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
            // Cross-volume (e.g. a picker-provided location): copy, then drop the original we own. ADR-050 050-C
            // C0a runs only here, immediately before the fallback copy: the source's logical bytes + the Import
            // reserve against the Mellow-root volume (one reading of that volume only; a rename never gets here). The
            // reader is synchronous, so adoption keeps no suspension point on this actor.
            let sourceBytes = ImportCopyAdmission.sourceByteCount(of: url)
            let check = ImportCopyAdmission.check(sourceBytes: sourceBytes, usableCapacity: copyFallbackCapacity(workspace.directory))
            if let reason = ImportCopyAdmission.refusalReason(check) {
                var required: Int64 = 0, usable: Int64 = 0
                if case .insufficient(let r, let u) = ImportCopyAdmission.verdict(check) { (required, usable) = (r, u) }
                throw ProjectMediaAdmissionRefused(requiredBytes: required, usableBytes: usable, boundary: .c0aAdoptionCopyFallback,
                                                   reason: sourceBytes == nil ? .sourceSizeUnknown : reason)
            }
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


// MARK: - Attempt rollback (ADR-050 050-D D7a §1; internal, unwired)

/// One materialized candidate of a failed import attempt, as the attempt recorded it. Nothing is
/// discovered by enumeration: the executor acts only on these exact records.
struct ImportRollbackRecord: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// A fast-path file that was renamed out of the workspace: it goes back to exactly
        /// `workspaceFileName` inside the attempt's workspace, and must then have `recordedByteCount` bytes.
        case ready(workspaceFileName: String, recordedByteCount: Int64)
        /// A normalization output owned by the failed attempt: it is removed.
        case normalizedOutput
    }

    let clipID: UUID
    /// Must be exactly the canonical `Projects/<projectID>/Media/<clipID>.mov`.
    let materializedPath: RelativeMediaPath
    let kind: Kind
}

/// One failed attempt to roll back: its live workspace, the target Project, every candidate record
/// (including the failing item's, whose file may still be on either side), and optionally the
/// attempt's own output directory inside the workspace (e.g. `attempt-<n>`), removed as a whole.
struct ImportRollbackPlan: Hashable, Sendable {
    let workspace: ProjectMediaWorkspace
    let projectID: UUID
    let records: [ImportRollbackRecord]
    /// A direct child of the workspace directory, or nil when the attempt wrote none.
    let attemptDirectoryName: String?
}

/// Why one record (or the attempt directory) could not be brought to its verified rolled-back state.
enum ImportRollbackProblem: Hashable, Sendable {
    case workspaceNotLive
    case workspaceNotADirectory
    case pathNotOwned
    case symbolicLink
    /// A path component that must be a directory is something else.
    case notADirectory
    case notARegularFile
    /// The path could not be inspected (anything but "does not exist"): never read as absent.
    case uninspectable
    case destinationOccupied
    case fileMissing
    case sizeMismatch(expected: Int64, actual: Int64?)
    case restoreFailed
    case removalFailed
    case duplicateRecord
    /// The normalizer reported that it could not remove (or had to quarantine) something in the attempt
    /// directory; the directory is preserved as evidence instead of being removed (D7a §1).
    case normalizerCleanupUnresolved
}

/// What happened to one record. Only the first four are verified states.
enum ImportRollbackRecordResult: Hashable, Sendable {
    /// Moved back to the workspace and verified (size, materialized path empty).
    case restored
    /// Already at its workspace path with the recorded size, materialized path empty (the failing
    /// item never moved, or a repeated call) — verified, nothing done.
    case alreadyInWorkspace
    /// The owned normalization output was removed and its absence verified.
    case removed
    /// The owned normalization output was not there — verified absent, nothing done.
    case alreadyAbsent
    case unresolved(ImportRollbackProblem)

    var isVerified: Bool {
        if case .unresolved = self { return false }
        return true
    }
}

/// The executor's answer. `verifiedClean` only when EVERY record and the attempt directory reached a
/// verified state; anything else is `unresolved` with the per-record detail, and D7a forbids Retry.
enum ImportRollbackOutcome: Hashable, Sendable {
    case verifiedClean(records: [UUID: ImportRollbackRecordResult])
    case unresolved(records: [UUID: ImportRollbackRecordResult], attemptDirectory: ImportRollbackProblem?)

    /// Verified cleanup is NECESSARY for Retry under D7a §2, not sufficient: valid sources and a valid
    /// target must still be established by the caller.
    var isVerifiedClean: Bool {
        if case .verifiedClean = self { return true }
        return false
    }
}

/// The media surface one import attempt uses (`ImportAttemptCoordinator`): its own attempt directory, the
/// recorded size of each workspace source, materialization by the existing store convention, the `lstat`
/// view of a canonical path (destination free; pre-save regular file of the expected size), the replaced
/// Project's media removal after a confirmed replacement, and D7a rollback. Nothing else (no enumeration,
/// no workspace discard).
protocol ImportAttemptMediaStoring: Sendable {
    func createAttemptDirectory(named name: String, in workspace: ProjectMediaWorkspace) async throws -> URL
    func workspaceFileByteCount(_ url: URL, in workspace: ProjectMediaWorkspace) async -> Int64?
    /// `lstat` view of a canonical committed path (never follows a symlink).
    func mediaNode(_ path: RelativeMediaPath) async -> ImportMediaNode
    func materialize(_ url: URL, projectID: UUID, clipID: UUID) async throws -> RelativeMediaPath
    func removeProjectMedia(projectID: UUID) async
    func rollBackAttempt(_ plan: ImportRollbackPlan) async -> ImportRollbackOutcome
}

/// What sits at a canonical committed path, without following symlinks.
enum ImportMediaNode: Equatable, Sendable {
    /// Nothing exists there (every directory component may be missing too).
    case missing
    case regularFile(byteCount: Int64)
    /// A symlink, directory, other type, an uninspectable path or a non-directory component on the way.
    case other
}

extension ProjectMediaStore: ImportAttemptMediaStoring {}

extension ProjectMediaStore {
    /// Rolls back one failed attempt's own candidates (D7a §1): ready files are renamed back to their
    /// recorded workspace paths without overwriting; owned normalization outputs (materialized copies and
    /// the attempt's own workspace directory) are removed; every result is verified. Symlinks are never
    /// followed and nothing outside the exact owned paths is touched; empty Project directories are left
    /// alone (that rule is unresolved). Independent records are still handled after one fails.
    ///
    /// The caller must already have established D7a eligibility (before any save attempt, or after a
    /// thrown save classified `priorConfirmed`) and the appropriate serialization; this never infers
    /// eligibility from an error. Repeated calls are safe: an already rolled-back record verifies again.
    func rollBackAttempt(_ plan: ImportRollbackPlan) async -> ImportRollbackOutcome {
        var results: [UUID: ImportRollbackRecordResult] = [:]
        // Without a live, real workspace nothing is mutated and nothing can be reported clean.
        if let workspaceProblem = workspaceRollbackProblem(plan.workspace) {
            for record in plan.records { results[record.clipID] = .unresolved(workspaceProblem) }
            return .unresolved(records: results, attemptDirectory: workspaceProblem)
        }
        // Duplicate identities are rejected before any mutation; the other records still proceed.
        var counts: [UUID: Int] = [:]
        for record in plan.records { counts[record.clipID, default: 0] += 1 }
        for record in plan.records {
            if counts[record.clipID, default: 0] > 1 {
                results[record.clipID] = .unresolved(.duplicateRecord)
                continue
            }
            results[record.clipID] = rollBack(record, projectID: plan.projectID, workspace: plan.workspace)
        }
        var directoryProblem: ImportRollbackProblem?
        if let name = plan.attemptDirectoryName {
            directoryProblem = removeAttemptDirectory(named: name, in: plan.workspace)
        }
        let clean = directoryProblem == nil && results.values.allSatisfy(\.isVerified)
        return clean ? .verifiedClean(records: results) : .unresolved(records: results, attemptDirectory: directoryProblem)
    }

    private enum RollbackNode: Equatable { case missing, regularFile(Int64), directory, symbolicLink, other, uninspectable, outsideRoot }

    /// `lstat` classification: a symbolic link is reported as itself, never followed. Only "does not
    /// exist" (`ENOENT` / `ENOTDIR`) is `.missing`; any other failure is `.uninspectable`.
    private func rollbackNode(_ url: URL) -> RollbackNode {
        var info = stat()
        var failure: Int32 = 0
        let status = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            let result = lstat(path, &info)
            failure = result == 0 ? 0 : errno   // captured once, immediately after the call
            return result
        }
        guard status == 0 else { return failure == ENOENT || failure == ENOTDIR ? .missing : .uninspectable }
        switch info.st_mode & S_IFMT {
        case S_IFLNK: return .symbolicLink
        case S_IFDIR: return .directory
        case S_IFREG: return .regularFile(Int64(info.st_size))
        default: return .other
        }
    }

    /// Every component from the root down to `directory` must be a real directory. Returns the first
    /// problem: `.missing` when a component does not exist, otherwise the component's offending kind.
    private func directoryChainProblem(_ directory: URL) -> RollbackNode? {
        let rootPath = root.standardizedFileURL.path
        let target = directory.standardizedFileURL.path
        guard target == rootPath || target.hasPrefix(rootPath + "/") else { return .outsideRoot }
        var current = root.standardizedFileURL
        var node = rollbackNode(current)
        guard node == .directory else { return node }
        for component in target.dropFirst(rootPath.count).split(separator: "/") {
            current = current.appendingPathComponent(String(component), isDirectory: true)
            node = rollbackNode(current)
            guard node == .directory else { return node }
        }
        return nil
    }

    private func workspaceRollbackProblem(_ workspace: ProjectMediaWorkspace) -> ImportRollbackProblem? {
        guard liveWorkspaceIDs.contains(workspace.id) else { return .workspaceNotLive }
        let expected = workspacesDirectory.appendingPathComponent(workspace.id.uuidString, isDirectory: true).standardizedFileURL
        guard workspace.directory.standardizedFileURL.path == expected.path, directoryChainProblem(expected) == nil else { return .workspaceNotADirectory }
        return nil
    }

    private static func problem(for node: RollbackNode) -> ImportRollbackProblem {
        switch node {
        case .symbolicLink: return .symbolicLink
        case .uninspectable: return .uninspectable
        case .outsideRoot: return .pathNotOwned
        case .missing: return .fileMissing
        case .regularFile, .other: return .notADirectory
        case .directory: return .notARegularFile
        }
    }

    /// A plain file name (one path component, not "." / ".."), resolved inside the workspace directory.
    private func workspaceChild(_ name: String, in workspace: ProjectMediaWorkspace) -> URL? {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return nil }
        return workspacesDirectory.appendingPathComponent(workspace.id.uuidString, isDirectory: true).appendingPathComponent(name)
    }

    private func rollBack(_ record: ImportRollbackRecord, projectID: UUID, workspace: ProjectMediaWorkspace) -> ImportRollbackRecordResult {
        guard let canonical = try? Self.committedMediaPath(projectID: projectID, clipID: record.clipID),
              record.materializedPath == canonical else { return .unresolved(.pathNotOwned) }
        let materialized = root.appendingPathComponent(canonical.value)
        // A missing directory on the way means the candidate is absent; any other non-directory component
        // (symlink, file, uninspectable) is refused.
        let materializedNode: RollbackNode
        switch directoryChainProblem(materialized.deletingLastPathComponent()) {
        case nil: materializedNode = rollbackNode(materialized)
        case .missing?: materializedNode = .missing
        case let node?: return .unresolved(Self.problem(for: node))
        }

        switch record.kind {
        case .normalizedOutput:
            switch materializedNode {
            case .missing: return .alreadyAbsent
            case .symbolicLink: return .unresolved(.symbolicLink)
            case .uninspectable: return .unresolved(.uninspectable)
            case .outsideRoot: return .unresolved(.pathNotOwned)
            case .directory, .other: return .unresolved(.notARegularFile)
            case .regularFile:
                try? fileManager.removeItem(at: materialized)
                return rollbackNode(materialized) == .missing ? .removed : .unresolved(.removalFailed)
            }

        case .ready(let name, let recordedByteCount):
            guard let original = workspaceChild(name, in: workspace) else { return .unresolved(.pathNotOwned) }
            let originalNode = rollbackNode(original)
            switch (materializedNode, originalNode) {
            case (.symbolicLink, _), (_, .symbolicLink):
                return .unresolved(.symbolicLink)
            case (.uninspectable, _), (_, .uninspectable):
                return .unresolved(.uninspectable)
            case (.regularFile(let size), .missing):
                // Only a file that matches the record leaves the Project.
                guard size == recordedByteCount else { return .unresolved(.sizeMismatch(expected: recordedByteCount, actual: size)) }
                do { try fileManager.moveItem(at: materialized, to: original) } catch { return .unresolved(.restoreFailed) }
                return verifyRestored(original: original, materialized: materialized, recordedByteCount: recordedByteCount, moved: true)
            case (.missing, .regularFile):
                return verifyRestored(original: original, materialized: materialized, recordedByteCount: recordedByteCount, moved: false)
            case (.regularFile, .regularFile), (.regularFile, .directory), (.regularFile, .other):
                return .unresolved(.destinationOccupied)
            case (.missing, .missing):
                return .unresolved(.fileMissing)
            default:
                return .unresolved(.notARegularFile)
            }
        }
    }

    private func verifyRestored(original: URL, materialized: URL, recordedByteCount: Int64, moved: Bool) -> ImportRollbackRecordResult {
        guard rollbackNode(materialized) == .missing else { return .unresolved(.restoreFailed) }
        guard case .regularFile(let size) = rollbackNode(original) else { return .unresolved(.fileMissing) }
        guard size == recordedByteCount else { return .unresolved(.sizeMismatch(expected: recordedByteCount, actual: size)) }
        return moved ? .restored : .alreadyInWorkspace
    }

    // MARK: Attempt preparation surface (ADR-050 D7a; internal, unwired)

    /// Creates the attempt's own output directory `name` directly inside a live, real workspace. Never
    /// reuses an existing entry (`destinationAlreadyExists`) and never creates intermediate directories.
    func createAttemptDirectory(named name: String, in workspace: ProjectMediaWorkspace) async throws -> URL {
        guard workspaceRollbackProblem(workspace) == nil else { throw ProjectMediaStoreError.workspaceNotLive }
        guard let directory = workspaceChild(name, in: workspace) else { throw ProjectMediaStoreError.pathNotCanonical }
        guard rollbackNode(directory) == .missing else { throw ProjectMediaStoreError.destinationAlreadyExists }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    /// The `lstat` size of `url` when it is a regular file (never a symlink) directly inside a live, real
    /// workspace; nil otherwise. Read-only.
    func workspaceFileByteCount(_ url: URL, in workspace: ProjectMediaWorkspace) async -> Int64? {
        guard workspaceRollbackProblem(workspace) == nil,
              let child = workspaceChild(url.lastPathComponent, in: workspace),
              child.standardizedFileURL.path == url.standardizedFileURL.path,
              case .regularFile(let size) = rollbackNode(child) else { return nil }
        return size
    }

    func mediaNode(_ path: RelativeMediaPath) async -> ImportMediaNode {
        let url = root.appendingPathComponent(path.value)
        switch directoryChainProblem(url.deletingLastPathComponent()) {
        case nil: break
        case .missing?: return .missing
        case _?: return .other
        }
        switch rollbackNode(url) {
        case .missing: return .missing
        case .regularFile(let size): return .regularFile(byteCount: size)
        default: return .other
        }
    }

    private func removeAttemptDirectory(named name: String, in workspace: ProjectMediaWorkspace) -> ImportRollbackProblem? {
        guard let directory = workspaceChild(name, in: workspace) else { return .pathNotOwned }
        switch rollbackNode(directory) {
        case .missing: return nil
        case .symbolicLink: return .symbolicLink
        case .uninspectable: return .uninspectable
        case .outsideRoot: return .pathNotOwned
        case .regularFile, .other: return .notADirectory
        case .directory:
            try? fileManager.removeItem(at: directory)
            return rollbackNode(directory) == .missing ? nil : .removalFailed
        }
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
