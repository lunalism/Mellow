import Foundation
import Photos

/// 완성본을 사진 앱에 저장한다. (Tasks 1-18)
///
/// 이번 범위는 **개별 클립 저장**이다. 병합 결과 익스포트(1-17)는 다음 작업이다.
/// 권한은 `addOnly` 만 요청한다 — 읽기 권한은 필요 없고, 요청하면 사용자에게
/// 더 넓은 접근을 물어보게 된다.
enum PhotoLibrarySaver {

    enum Failure: LocalizedError {
        case fileMissing(String)
        case notAuthorized(PHAuthorizationStatus)

        var errorDescription: String? {
            switch self {
            case .fileMissing(let name): return "파일이 없다: \(name)"
            case .notAuthorized(let status): return "사진 권한 없음 (\(status.shortText))"
            }
        }
    }

    static func currentStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    @discardableResult
    static func save(_ url: URL) async throws -> PHAuthorizationStatus {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure.fileMissing(url.lastPathComponent)
        }

        var status = currentStatus()
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else {
            throw Failure.notAuthorized(status)
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            // 원본을 남긴다. 스파이크 단계에서는 파일을 다시 분석해야 한다.
            options.shouldMoveFile = false
            request.addResource(with: .video, fileURL: url, options: options)
        }
        return status
    }
}

extension PHAuthorizationStatus {
    var shortText: String {
        switch self {
        case .notDetermined: return "미결정"
        case .restricted: return "제한됨"
        case .denied: return "거부됨"
        case .authorized: return "허용됨"
        case .limited: return "일부 허용"
        @unknown default: return "알 수 없음(\(rawValue))"
        }
    }
}
