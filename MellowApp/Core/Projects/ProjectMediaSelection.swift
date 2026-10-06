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
    /// Copy admission (ADR-050 050-C C0 / C0a) refused an incoming file; nothing more was copied. The
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
    /// The route that opened the session is gone: a session still waiting for the picker resolves `.cancelled`
    /// (its host view may never report dismissal); a transfer already started finishes normally.
    func cancelPendingSelection()
}

extension ProjectMediaSelecting {
    /// Default: boundaries that have no notion of a selection limit run the ordinary session.
    func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating, selectionLimit: Int?) async -> ProjectMediaSelectionOutcome {
        await selectVideos(into: workspace, store: store, admission: admission)
    }

    /// Default: boundaries whose sessions always resolve on their own.
    func cancelPendingSelection() {}
}

/// Thrown when copy admission refuses an incoming file: C0 in the transfer bridge, or C0a in `adopt`'s copy
/// fallback (ADR-050 050-C). `usableBytes` 0 also means the capacity could not be read; `requiredBytes` 0 means
/// the source size could not be read. Both are refusals.
struct ProjectMediaAdmissionRefused: Error, Equatable {
    let requiredBytes: Int64
    let usableBytes: Int64
    var boundary: ImportCopyBoundary = .c0TransferCopy
    /// Typed reason for logs. Through the C0 gate (`ProjectStorageVerdict`) an unknown capacity reports `.insufficient`
    /// with `usableBytes` 0; C0a reports every reason exactly.
    var reason: ImportCopyRefusalReason = .insufficient
}
