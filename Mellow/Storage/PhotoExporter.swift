import Photos

/// 사진 앱으로 **단일 사진 익스포트** (Phase 1 · Stage 4d).
///
/// 흐름: add-only 권한 확보 → 풀해상도 필터 렌더(백그라운드) → PHAsset 생성. 공유 시트 없음,
/// 워터마크 없음 — 화면에 보이는 그 필터본을 **풀해상도**로 그대로 저장한다(WYSIWYG).
///
/// - **add-only 권한만** 요청한다(`.addOnly`) — 전체 라이브러리 읽기 접근이 아님(더 가벼운 프롬프트).
/// - 거부/실패는 **완전 무해**: 조용한 결과값만 돌려주고 크래시 없음. UI가 차분한 토스트로 안내.
/// - **한 번에 한 장.** 풀해상도 버퍼는 렌더 함수 반환 즉시 해제(캐시 안 함) → 발열/메모리 억제.
@MainActor
enum PhotoExporter {
    enum ExportResult { case saved, denied, failed }

    static func export(_ capture: Capture) async -> ExportResult {
        guard await ensureAddOnlyAuthorization() else { return .denied }

        // 풀해상도 필터 렌더는 무겁다 → 백그라운드(.userInitiated). 프리뷰가 아니라 원본 전체에 필터.
        let url = CaptureStore.shared.url(for: capture)
        let filterID = capture.filterID
        let data = await Task.detached(priority: .userInitiated) {
            await CaptureThumbnailRenderer.shared.fullResolutionFilteredJPEG(originalURL: url, filterID: filterID)
        }.value
        guard let data else { return .failed }

        return await addToLibrary(data)
    }

    /// add-only 권한 확보. 미결정이면 시스템 프롬프트, authorized/limited면 진행 가능,
    /// 그 외(거부/제한)는 조용히 실패.
    private static func ensureAddOnlyAuthorization() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let requested = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return requested == .authorized || requested == .limited
        default:
            return false
        }
    }

    /// 사진 앱에 add-only로 리소스 추가. 성공/실패만 돌려준다(에러 문자열 노출 안 함).
    private static func addToLibrary(_ data: Data) async -> ExportResult {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, _ in
                continuation.resume(returning: success ? .saved : .failed)
            }
        }
    }
}
