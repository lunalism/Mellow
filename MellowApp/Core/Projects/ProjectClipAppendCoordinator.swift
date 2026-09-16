import Foundation
import OSLog

/// Editor Add Clips (ADR-037): turns already-transferred, workspace-owned sources into Project-owned
/// Clips for the CURRENT Project — storage guard → validate every source → materialise every file
/// under `Projects/<projectID>/Media/<clipID>.mov`. All-or-nothing: on any failure every file this
/// operation created is removed again and nothing else (never pre-existing Project media, never
/// Photos). It performs no persistence: the Editor commits the returned Clips as one history-capable
/// edit, so the batch is atomic in storage, in the store and in the Undo history.
@MainActor
final class ProjectClipAppendCoordinator {
    private let mediaStore: any ProjectMediaStoring
    private let validator: Phase5ReadyMediaValidator
    private let storage: any ProjectStorageGating

    init(mediaStore: any ProjectMediaStoring, validator: Phase5ReadyMediaValidator, storage: any ProjectStorageGating) {
        self.mediaStore = mediaStore
        self.validator = validator
        self.storage = storage
    }

    enum Outcome: Equatable, Sendable {
        /// Every source is Phase-5-ready and materialised; Clips are in picker order, not yet persisted.
        case ready([VlogClip])
        case requiresImportPreparation(Phase5ReadyVerdict.PreparationReason)
        case invalidMedia(Phase5ReadyVerdict.InvalidReason)
        case insufficientStorage
        case failed
    }

    /// Same pipeline as Project composition (ADR-020 / ADR-024), scoped to appending to `project`.
    func prepareClips(for project: VlogProject, sources: [SelectedVideoSource]) async -> Outcome {
        guard !sources.isEmpty else { return .failed }

        // 1. Final reserve guard: sources are already adopted on this volume, promotion is a rename.
        let adoptedBytes = sources.reduce(0) { $0 + $1.byteCount }
        let additional = ProjectCompositionPolicy.estimatedPeakAdditionalBytes(adoptedSourceBytes: adoptedBytes)
        if case .insufficient(let required, let usable) = await storage.check(additionalBytes: additional) {
            MellowLog.app.info("Add clips storage preflight refused: required=\(required, privacy: .public) usable=\(usable, privacy: .public)")
            return .insufficientStorage
        }

        // 2. Validate every source first; the first non-ready verdict rejects the whole selection.
        var durations: [MediaTime] = []
        for source in sources {
            switch await validator.validate(source.url) {
            case .ready(let duration): durations.append(duration)
            case .requiresImportPreparation(let reason): return .requiresImportPreparation(reason)
            case .invalid(let reason): return .invalidMedia(reason)
            }
        }

        // 3. Materialise into the current Project's own directory; undo everything on any failure.
        var clips: [VlogClip] = []
        for (index, source) in sources.enumerated() {
            let clipID = UUID()
            do {
                let path = try await mediaStore.materialize(source.url, projectID: project.id, clipID: clipID)
                guard await mediaStore.fileExists(path) else { throw ProjectMediaStoreError.sourceMissing }
                clips.append(try VlogClip(
                    id: clipID,
                    projectID: project.id,
                    sourceKind: .imported,
                    mediaRelativePath: path,
                    sourceDuration: durations[index],
                    trimStart: .zero,
                    trimDuration: durations[index],
                    framing: nil,
                    sortOrder: project.clips.count + index
                ))
            } catch {
                let details = error as NSError
                MellowLog.app.error("Add clips materialization failed: domain=\(details.domain, privacy: .public), code=\(details.code)")
                await discard(clips)
                return .failed
            }
        }
        return .ready(clips)
    }

    /// Removes the files of Clips this coordinator materialised but the Editor could not commit.
    func discard(_ clips: [VlogClip]) async {
        for clip in clips { await mediaStore.removeMedia(clip.mediaRelativePath) }
    }
}
