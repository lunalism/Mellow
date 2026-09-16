import Foundation

/// Durable record of a Clip's logical deletion (ADR-021 / ARCHITECTURE §60). Written when the user
/// deletes a Clip; the Clip's identity, media and metadata stay intact and physical cleanup is a
/// separate, later, explicit operation. The anchors let Undo restore the Clip relative to the
/// surviving neighbours instead of a blind array index, so unrelated reorders are preserved.
struct ClipDeletionRecord: Equatable, Sendable {
    /// When the user deleted the Clip.
    let deletedAt: Date
    /// Logical index in the active timeline at the moment of deletion (the last-resort anchor).
    let originalIndex: Int
    /// The active Clip that preceded it at deletion time, if any.
    let previousClipID: UUID?
    /// The active Clip that followed it at deletion time, if any.
    let nextClipID: UUID?

    init(deletedAt: Date, originalIndex: Int, previousClipID: UUID?, nextClipID: UUID?) throws {
        guard originalIndex >= 0 else { throw DomainValidationError.invalidDeletionRecord }
        self.deletedAt = deletedAt
        self.originalIndex = originalIndex
        self.previousClipID = previousClipID
        self.nextClipID = nextClipID
    }
}
