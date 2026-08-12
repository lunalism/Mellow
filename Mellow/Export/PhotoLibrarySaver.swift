import Foundation
import Photos

// 익스포트된 파일을 사진 앱에 넣는다 (1-18).
//
// ClipExporter 와 분리한다. 두 단계는 실패 원인이 완전히 다르다 —
// 익스포트는 코덱·프리셋·디스크 문제로 실패하고, 여기는 권한과 사진 라이브러리
// 상태로 실패한다. 1-19 에서 각 구간의 소요 시간도 따로 재야 한다.
//
// Mac 검증 대응물이 없다. Photos 프레임워크는 실기기에서만 확인된다.

// MARK: - 사용한 API
//
//   PHPhotoLibrary.authorizationStatus(for:)         — iOS 14+
//   PHPhotoLibrary.requestAuthorization(for:)        — iOS 14+, async
//   PHPhotoLibrary.shared().performChanges { }       — async throws
//   PHAssetCreationRequest.forAsset()
//   addResource(with:fileURL:options:)
//
// 인자 없는 authorizationStatus() / requestAuthorization(_:) 은 deprecated 이며
// 접근 수준을 구분하지 못한다. 이 파일은 전부 접근 수준을 받는 쪽을 쓴다.
//
// performChanges 는 헤더에 NS_SWIFT_ASYNC_THROWS_ON_FALSE 가 붙어 있어
// Swift 에서 async throws 로 들어온다. 완료 핸들러 형태를 직접 쓸 일이 없다.
//
// PHAssetResourceCreationOptions.contentType (UTType) 은 iOS 26+ 라 쓰지 않는다.
// 구 uniformTypeIdentifier 는 deprecated 다. 둘 다 지정하지 않아도 되는데,
// 헤더에 "지정하지 않으면 PHAssetResourceType 이나 파일 확장자에서 추론한다"고
// 되어 있고 우리는 .video + .mov 라서 추론이 정확하다.

// MARK: - 권한

extension PermissionState {

    /// 사진 앱 권한 상태를 앱에서 쓰는 형태로 좁힌다.
    ///
    /// `.limited` 는 읽기 접근이 일부로 제한된 상태다. 우리는 add-only 라
    /// 읽지 않고 넣기만 하므로 그 제한이 우리 동작을 막지 않는다. 허용으로 본다.
    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .undetermined
        case .authorized: self = .authorized
        case .limited: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }
}

// MARK: - 결과 모델

struct PhotoLibrarySaveOutcome {
    /// performChanges 에만 걸린 wall time.
    ///
    /// 권한 대기는 여기 들어가지 않는다. 미결정 상태에서 처음 저장하면 시스템
    /// 팝업이 뜨고 사용자가 누를 때까지 기다리는데, 실측에서 그 대기가 22.7초로
    /// 잡혀 저장 시간을 통째로 덮어썼다. 사람의 반응 속도는 우리 성능이 아니다.
    let elapsed: TimeInterval
    /// 만들어진 에셋의 식별자. 1-20 에서 이 값으로 결과물을 되짚는다.
    let localIdentifier: String?
    /// 파일을 복사했는지 옮겼는지. shouldMoveFile 판단 근거를 남기려고 함께 돌려준다.
    let movedFile: Bool
}

enum PhotoLibrarySaveError: Error, CustomStringConvertible {
    case permissionDenied(PermissionState)
    case fileMissing(URL)
    case changeFailed(String)

    var description: String {
        switch self {
        case .permissionDenied(let state):
            switch state {
            case .denied:
                return "사진 앱 접근이 거부되어 있습니다. 설정에서 허용해 주세요."
            case .restricted:
                return "사진 앱 접근이 기기 정책으로 제한되어 있습니다."
            case .undetermined:
                return "사진 앱 접근 권한이 아직 결정되지 않았습니다."
            case .authorized:
                return "사진 앱 접근은 허용되어 있습니다."
            }
        case .fileMissing(let url):
            return "저장할 파일이 없습니다: \(url.lastPathComponent)"
        case .changeFailed(let message):
            return "사진 앱에 저장하지 못했습니다: \(message)"
        }
    }
}

// MARK: - 저장

enum PhotoLibrarySaver {

    /// 요청하는 접근 수준.
    ///
    /// v0.1 은 사진 앱에서 읽어오는 기능이 없다(0-5 확정). `.readWrite` 를 물으면
    /// 쓰지도 않을 읽기 권한까지 사용자에게 요구하게 된다.
    /// `Info.plist` 도 `NSPhotoLibraryAddUsageDescription` 만 갖고 있다.
    static let accessLevel: PHAccessLevel = .addOnly

    static func currentPermission() -> PermissionState {
        PermissionState(PHPhotoLibrary.authorizationStatus(for: accessLevel))
    }

    /// 미결정이면 시스템에 요청하고, 그 외에는 현재 상태를 그대로 돌려준다.
    /// 이미 거부된 권한은 다시 물어도 팝업이 뜨지 않는다 (CameraPermissions 와 같은 규칙).
    static func requestPermission() async -> PermissionState {
        let state = currentPermission()
        guard state == .undetermined else { return state }

        let status = await PHPhotoLibrary.requestAuthorization(for: accessLevel)
        return PermissionState(status)
    }

    /// 임시 익스포트 파일을 사진 앱에 넣는다.
    ///
    /// **이 함수는 파일의 소유권을 가져간다.** 성공하든 실패하든 돌아올 때는
    /// 임시 파일이 남아 있지 않다. 남기면 고아 파일이 되고, 세션 하나가
    /// 수백 MB라 쌓이면 바로 저장 공간 문제가 된다. 재시도가 필요하면 다시
    /// 익스포트하는 편이 낫다 — passthrough 는 파일 복사 수준이라 보관보다 싸다.
    ///
    /// - Parameter moveFile: 복사하지 않고 옮긴다. 아래 주석 참고.
    /// - Important: 권한은 호출 전에 `requestPermission()` 으로 해결해 둔다.
    ///   여기서는 이미 정해진 상태를 확인만 한다 — 팝업 대기가 저장 시간에
    ///   섞이면 안 되고, 거부된 상태라면 익스포트까지 간 것 자체가 낭비다.
    static func save(temporaryVideoAt url: URL,
                     moveFile: Bool = true) async throws -> PhotoLibrarySaveOutcome {

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PhotoLibrarySaveError.fileMissing(url)
        }

        let permission = currentPermission()
        guard permission.isAuthorized else {
            discardTemporaryFile(at: url)
            throw PhotoLibrarySaveError.permissionDenied(permission)
        }

        let started = CFAbsoluteTimeGetCurrent()
        let identifier = IdentifierBox()

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()

                // shouldMoveFile 을 켠다.
                //
                // 켜면 파일 데이터를 복제하지 않고 라이브러리로 옮기며, 에셋 생성이
                // 성공하면 원본이 사라진다. 끄면(기본값) 복사본이 만들어진다.
                //
                // 켜는 이유는 두 가지다.
                //   (1) 최대 디스크 사용량이 절반이 된다. 클립 30개 세션의 익스포트
                //       결과가 579MB 인데(1-17 실측), 복사면 저장이 끝날 때까지
                //       원본과 사본이 동시에 존재해 1.1GB 를 요구한다.
                //   (2) 바이트 복사가 없어 더 빠르다.
                //
                // 켜도 되는 이유는, 이 파일이 우리가 방금 만든 단발 임시 파일이고
                // 아무도 열고 있지 않기 때문이다. 헤더에 "열려 있거나 하드링크된
                // 파일을 옮으려 하면 실패한다"고 되어 있는데, 익스포트 세션은 이미
                // 파일을 닫았고 미리보기 AVPlayer 가 물고 있는 것은 원본 클립들이지
                // 이 결과 파일이 아니다.
                //
                // 실기기에서 복사와 이동을 둘 다 재서 확인한다 (moveFile 인자).
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = moveFile

                request.addResource(with: .video, fileURL: url, options: options)
                identifier.value = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            discardTemporaryFile(at: url)
            throw PhotoLibrarySaveError.changeFailed(error.localizedDescription)
        }

        // moveFile 이 켜져 있으면 사진 앱이 이미 가져갔다. 꺼져 있으면 사본이
        // 만들어졌으므로 원본은 우리가 지운다. 켜져 있어도 확인차 한 번 더 부른다 —
        // 이미 없으면 아무 일도 하지 않는다.
        discardTemporaryFile(at: url)

        return PhotoLibrarySaveOutcome(elapsed: CFAbsoluteTimeGetCurrent() - started,
                                       localIdentifier: identifier.value,
                                       movedFile: moveFile)
    }

    /// 임시 파일을 지운다. 이미 없으면 아무 일도 하지 않는다.
    static func discardTemporaryFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// performChanges 블록은 escaping 이라 지역 변수를 직접 못 담는다.
private final class IdentifierBox: @unchecked Sendable {
    var value: String?
}
