import Foundation

/// A video the user explicitly selected, already transferred under app control (inside the
/// operation workspace). Never a Photos asset reference; Photos originals are never touched.
struct SelectedVideoSource: Hashable, Sendable {
    let url: URL
    let byteCount: Int64
}

enum ProjectMediaSelectionOutcome: Sendable {
    /// Normal, silent result — the user dismissed the picker.
    case cancelled
    case selected([SelectedVideoSource])
    /// Pre-copy storage admission refused an incoming file (ADR-024); nothing more was copied. The
    /// workspace (with any earlier adopted files) is left for the caller to discard.
    case insufficientStorage
    /// Transfer / read failure of the selected item(s); the workspace is left for the caller to discard.
    case failed
}

/// Select-Clips boundary (ADR-033 / ADR-034 §2): the minimal system selection call for Project
/// bootstrap. Production uses the system Photos picker (no library read permission); tests inject
/// deterministic local fixtures.
@MainActor
protocol ProjectMediaSelecting: AnyObject {
    /// Presents selection and resolves once files are inside `workspace`, or with cancel / failure.
    /// `admission` is consulted with each incoming file's actual byte size immediately before the
    /// first Mellow-owned full-size copy of that file (sequentially, re-querying capacity each time).
    func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating) async -> ProjectMediaSelectionOutcome
    /// Same session, with an upper bound on how many items the picker offers to confirm
    /// (`selectionLimit` nil = the boundary's default). Replace (ADR-040) uses exactly 1; the model
    /// still verifies the returned cardinality, so a boundary that ignores the limit cannot widen a
    /// Replace into a batch.
    func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating, selectionLimit: Int?) async -> ProjectMediaSelectionOutcome
}

extension ProjectMediaSelecting {
    /// Default: boundaries that have no notion of a selection limit run the ordinary session.
    func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating, selectionLimit: Int?) async -> ProjectMediaSelectionOutcome {
        await selectVideos(into: workspace, store: store, admission: admission)
    }
}

/// Thrown by the transfer bridge when pre-copy admission refuses an incoming file.
struct ProjectMediaAdmissionRefused: Error, Equatable {
    let requiredBytes: Int64
    let usableBytes: Int64
}
