import Foundation
import Observation
import PhotosUI
import SwiftUI

/// The system Photos picker as the Select-Clips boundary. Runs out of process, so Mellow requests no
/// Photos library read permission (ADR-033 keeps only Add-only for the Camera save path). Selected
/// items are transferred as files into the operation workspace before anything else happens.
///
/// The hosting view binds `isPresented` / `items` to `.photosPicker(...)` and forwards dismissal via
/// `pickerDismissed()`; `selectVideos` suspends until one outcome is produced.
///
/// Selection isolation: every `selectVideos` call opens its own session with an EMPTY selection; a
/// binding write is never acted on while the picker is still open or outside a session, and a
/// transfer starts only once the picker has been dismissed WITH a non-empty selection. Dismissal
/// without a confirmed selection is `.cancelled`, whatever earlier sessions selected.
@Observable
@MainActor
final class PhotosVideoSelector: ProjectMediaSelecting {
    var isPresented = false
    var items: [PhotosPickerItem] = [] {
        didSet { evaluate() }
    }
    /// Selection bound of the CURRENT session for the hosting `.photosPicker` (nil = unlimited, the
    /// Add / Select-Clips default). Set before presentation, cleared when the session resolves, so
    /// one host serves both the multi-select Add and the single-video Replace (ADR-040).
    private(set) var maxSelectionCount: Int?

    /// Grace period after dismissal for the picker to deliver a confirmed selection into the binding.
    static let confirmationGrace: Duration = .milliseconds(800)

    private struct Session {
        let continuation: CheckedContinuation<ProjectMediaSelectionOutcome, Never>
        let workspace: ProjectMediaWorkspace
        let store: any ProjectMediaStoring
        var dismissed = false
        var transferStarted = false
    }
    private var session: Session?

    func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating) async -> ProjectMediaSelectionOutcome {
        await selectVideos(into: workspace, store: store, admission: admission, selectionLimit: nil)
    }

    func selectVideos(into workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring, admission: any ProjectStorageGating, selectionLimit: Int?) async -> ProjectMediaSelectionOutcome {
        if let stale = session {
            // A session that never resolved must not leak into this one.
            session = nil
            stale.continuation.resume(returning: .cancelled)
        }
        // The importing closure is static; the current operation's gate is published for it.
        ReceivedVideoFile.admission.set(admission)
        items = []
        maxSelectionCount = selectionLimit
        return await withCheckedContinuation { continuation in
            session = Session(continuation: continuation, workspace: workspace, store: store)
            isPresented = true
        }
    }

    /// Called when the picker sheet goes away. The confirmed selection, when any, is delivered into
    /// the binding around dismissal, so the decision is made once the grace period has elapsed.
    func pickerDismissed() {
        guard session != nil, session?.dismissed == false else { return }
        session?.dismissed = true
        evaluate()
        Task {
            try? await Task.sleep(for: Self.confirmationGrace)
            guard let session, !session.transferStarted else { return }
            if items.isEmpty { resolve(.cancelled) }
        }
    }

    /// Transfers only when a session exists, the picker has been dismissed and a non-empty confirmed
    /// selection is present — never on a bare binding write.
    private func evaluate() {
        guard let current = session, current.dismissed, !current.transferStarted, !items.isEmpty else { return }
        session?.transferStarted = true
        let confirmed = items
        Task { await transfer(confirmed, workspace: current.workspace, store: current.store) }
    }

    private func transfer(_ confirmed: [PhotosPickerItem], workspace: ProjectMediaWorkspace, store: any ProjectMediaStoring) async {
        var sources: [SelectedVideoSource] = []
        for item in confirmed {
            do {
                guard let received = try await item.loadTransferable(type: ReceivedVideoFile.self) else {
                    resolve(.failed); return
                }
                let url = try await store.adopt(received.url, into: workspace)
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                sources.append(SelectedVideoSource(url: url, byteCount: bytes))
            } catch let refusal as ProjectMediaAdmissionRefused {
                MellowLog.app.info("Select Clips pre-copy admission refused: required=\(refusal.requiredBytes, privacy: .public) usable=\(refusal.usableBytes, privacy: .public)")
                resolve(.insufficientStorage); return
            } catch {
                MellowLog.app.error("Select Clips transfer failed: \((error as NSError).domain, privacy: .public)/\((error as NSError).code)")
                resolve(.failed); return
            }
        }
        resolve(.selected(sources))
    }

    private func resolve(_ outcome: ProjectMediaSelectionOutcome) {
        guard let current = session else { return }
        session = nil
        ReceivedVideoFile.admission.set(nil)
        items = []
        maxSelectionCount = nil
        isPresented = false
        current.continuation.resume(returning: outcome)
    }
}

/// Lock-protected slot for the gate the static importing closure must consult; set per operation by
/// the selector and cleared when it resolves.
final class TransferAdmissionSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var gate: (any ProjectStorageGating)?
    func set(_ gate: (any ProjectStorageGating)?) { lock.lock(); self.gate = gate; lock.unlock() }
    func current() -> (any ProjectStorageGating)? { lock.lock(); defer { lock.unlock() }; return gate }
}

/// Copies the picker-provided file into Mellow's temporary directory the moment it is received; the
/// selector then adopts it into the workspace. Photos' own file is never modified.
///
/// `received.file` is a plain file URL that is only guaranteed to exist for the duration of the
/// importing closure, so both the pre-copy storage admission (ADR-024: incoming size + Safety Reserve
/// against the *current* usable capacity) and the copy happen inside it. A refused file is never
/// copied; the provider's own temporary representation is system-controlled and not counted.
struct ReceivedVideoFile: Transferable {
    let url: URL
    static let admission = TransferAdmissionSlot()

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try await admit(received.file)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectMediaTransfer", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            do {
                try FileManager.default.copyItem(at: received.file, to: destination)
            } catch {
                // Runtime write failure (e.g. disk full after admission): leave no partial temp behind.
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            return ReceivedVideoFile(url: destination)
        }
    }

    /// Pre-copy admission for one incoming file. Without a published gate the transfer is refused
    /// rather than silently un-gated.
    static func admit(_ incoming: URL) async throws {
        let size = Int64((try? incoming.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard let gate = admission.current() else {
            throw ProjectMediaAdmissionRefused(requiredBytes: size, usableBytes: 0)
        }
        if case .insufficient(let required, let usable) = await gate.check(additionalBytes: size) {
            throw ProjectMediaAdmissionRefused(requiredBytes: required, usableBytes: usable)
        }
    }
}
