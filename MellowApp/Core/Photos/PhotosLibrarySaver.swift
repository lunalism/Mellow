import Photos

enum PhotosAddAuthorization: String, Sendable, CaseIterable {
    case notDetermined, authorized, denied, restricted
}

enum PhotosSaveError: Error, Equatable, Sendable {
    case notAuthorized(PhotosAddAuthorization)
    case saveFailed(String)
}

/// Narrow add-only boundary for the direct-capture save path. No library reads.
@MainActor
protocol PhotosLibrarySaving: AnyObject {
    var authorization: PhotosAddAuthorization { get }
    func requestAccess() async -> PhotosAddAuthorization
    /// Moves the staging file into the user's library. On success the file is gone from
    /// staging; on failure it is left in place for recovery.
    func save(videoAt url: URL) async throws
}

@MainActor
final class PHPhotosLibrarySaver: PhotosLibrarySaving {
    var authorization: PhotosAddAuthorization {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }

    func requestAccess() async -> PhotosAddAuthorization {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .addOnly))
    }

    func save(videoAt url: URL) async throws {
        let status = authorization
        guard status == .authorized else { throw PhotosSaveError.notAuthorized(status) }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: options)
            }
        } catch {
            throw PhotosSaveError.saveFailed(error.localizedDescription)
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotosAddAuthorization {
        switch status {
        case .authorized, .limited: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .restricted
        }
    }
}
