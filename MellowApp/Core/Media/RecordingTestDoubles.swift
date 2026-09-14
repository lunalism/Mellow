#if DEBUG
import Foundation

/// Deterministic stand-ins for the Phase 4 boundaries. Shared by unit tests and the opted-in
/// simulator UI tests; never compiled into release.
@MainActor
final class FakePhotosLibrarySaver: PhotosLibrarySaving {
    var authorization: PhotosAddAuthorization
    var grantOnRequest = true
    var saveFails = false
    private(set) var savedURLs: [URL] = []
    private(set) var requestCount = 0
    /// Mirrors Photos' shouldMoveFile: on success the staging file disappears.
    var removesFileOnSave = true

    init(authorization: PhotosAddAuthorization = .authorized) { self.authorization = authorization }

    func requestAccess() async -> PhotosAddAuthorization {
        requestCount += 1
        if authorization == .notDetermined { authorization = grantOnRequest ? .authorized : .denied }
        return authorization
    }

    func save(videoAt url: URL) async throws {
        guard authorization == .authorized else { throw PhotosSaveError.notAuthorized(authorization) }
        if saveFails { throw PhotosSaveError.saveFailed("fake save failure") }
        savedURLs.append(url)
        if removesFileOnSave { try? FileManager.default.removeItem(at: url) }
    }
}

@MainActor
final class FakeMicrophoneAuthorization: MicrophoneAuthorizationProviding {
    var authorization: MicrophoneAuthorization
    var grantOnRequest = true
    private(set) var requestCount = 0
    init(authorization: MicrophoneAuthorization = .authorized) { self.authorization = authorization }
    func requestAccess() async -> MicrophoneAuthorization {
        requestCount += 1
        if authorization == .notDetermined { authorization = grantOnRequest ? .authorized : .denied }
        return authorization
    }
}

@MainActor
final class FakeRecordingMediaInspector: RecordingMediaInspecting {
    /// Fixed answer for unit tests; when nil, `durationProvider` supplies a playable video clip.
    var nextInfo: RecordingMediaInfo?
    var durationProvider: (@MainActor () -> TimeInterval)?
    private(set) var inspected: [URL] = []
    func inspect(_ url: URL) async -> RecordingMediaInfo {
        inspected.append(url)
        if let nextInfo { return nextInfo }
        return RecordingMediaInfo(isPlayable: true, hasVideoTrack: true, duration: durationProvider?() ?? 0)
    }
}

@MainActor
final class FakeCompletionHaptic: CompletionHapticPlaying {
    private(set) var completions = 0
    func playCompletion() { completions += 1 }
}

@MainActor
final class ImmediateBackgroundTaskRunner: BackgroundTaskRunning {
    private(set) var runs = 0
    func run(_ work: @MainActor () async -> Void) async { runs += 1; await work() }
}
#endif
