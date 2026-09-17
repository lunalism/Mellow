import Foundation

/// Derived, never persisted, Editor-facing availability of one ACTIVE Clip's Project-owned media
/// (ADR-040). Phase 5 scope is structural only: the committed media file is missing / unresolvable.
/// An existing file that is corrupt, unreadable or decode-failing is NOT unavailable here — that is
/// the later playback / decode phase, and thumbnail-generation failure on an existing file keeps its
/// own neutral presentation.
enum ClipAvailability: Equatable, Sendable {
    case available
    case unavailable(ClipUnavailableReason)

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

enum ClipUnavailableReason: Equatable, Sendable {
    /// No file exists at the Clip's committed media path.
    case mediaMissing
    /// The committed path cannot be resolved inside the Mellow-owned root.
    case unresolvablePath
}

/// The smallest boundary the Editor needs: one answer per Clip, computed from metadata plus the
/// current filesystem reality. Implementations never decode media, never generate thumbnails, never
/// consult Photos and never scan directories.
protocol ClipAvailabilityChecking: Sendable {
    func availability(for clip: VlogClip) async -> ClipAvailability
}

/// Production checker: wraps the read-only committed-media resolver (`ProjectMediaStore`). Only the
/// resolver's documented contract (`mediaMissing`, `pathEscapesRoot`) classifies a Clip as
/// unavailable; any other error fails toward preservation — the Clip is reported available and the
/// existing thumbnail-failure path shows whatever the media really is.
struct CommittedMediaAvailabilityChecker: ClipAvailabilityChecking {
    let resolver: any ProjectMediaURLResolving

    func availability(for clip: VlogClip) async -> ClipAvailability {
        do {
            _ = try await resolver.committedMediaURL(for: clip.mediaRelativePath)
            return .available
        } catch ProjectMediaStoreError.mediaMissing {
            return .unavailable(.mediaMissing)
        } catch ProjectMediaStoreError.pathEscapesRoot {
            return .unavailable(.unresolvablePath)
        } catch {
            MellowLog.app.error("Clip availability check failed, preserving as available clip=\(String(clip.id.uuidString.prefix(8)), privacy: .public): \(String(describing: error), privacy: .public)")
            return .available
        }
    }
}

#if DEBUG
/// Deterministic checker for unit tests and the seeded UI-test Editor routes (whose Clips have no
/// files at all): every Clip is available unless its identity is listed. Records every request so
/// tests can prove when availability is (re-)evaluated. Never compiled into Release.
actor FakeClipAvailabilityChecker: ClipAvailabilityChecking {
    private var unavailableClipIDs: Set<UUID>
    private(set) var requests: [UUID] = []

    init(unavailableClipIDs: Set<UUID> = []) {
        self.unavailableClipIDs = unavailableClipIDs
    }

    func setUnavailable(_ ids: Set<UUID>) { unavailableClipIDs = ids }

    func availability(for clip: VlogClip) async -> ClipAvailability {
        requests.append(clip.id)
        return unavailableClipIDs.contains(clip.id) ? .unavailable(.mediaMissing) : .available
    }
}
#endif
