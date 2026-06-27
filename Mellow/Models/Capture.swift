import Foundation

/// 캡처 종류 (Phase 1 Spec §8). 영상은 Phase 4.
enum CaptureType: String, Codable {
    case photo
}

/// 캡처 기록 (Phase 1 Spec §8) — **비파괴**의 핵심.
///
/// 원본(무필터)과 `filterID`를 분리 저장한다. 표시·익스포트 시 filterID로 룩을
/// 재렌더하므로, 나중에 필터를 바꿔도 원본 화질 손실이 없다.
///
/// 스펙의 `originalURL: URL` 대신 **상대 파일명**을 저장한다 — 앱 컨테이너 절대 경로는
/// 재설치 시 바뀌어 깨지므로(영속성). URL은 `CaptureStore.url(for:)`로 복원한다.
struct Capture: Identifiable, Codable {
    let id: UUID
    let type: CaptureType
    let originalFilename: String
    let filterID: String
    let ratio: AspectRatio
    let createdAt: Date
}
