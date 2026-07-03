import Foundation
import CoreLocation

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
///
/// slice B-1: **옵셔널 촬영 위치**(`latitude`/`longitude`). 셔터 시 코스 정확도로 캐시된
/// 좌표를 붙인다(없으면 nil). **마이그레이션 안전**이 최우선 — 좌표 키가 없는 기존
/// captures.json 레코드도 반드시 그대로 디코드돼야 한다(갤러리가 사라지면 안 됨).
/// 그래서 좌표는 `decodeIfPresent`로 읽고(없으면 nil), `encodeIfPresent`로 쓴다(있을 때만).
///
/// slice B-2: **옵셔널 장소명**(`placeName`). 좌표를 역지오코딩한 짧은 이름(동네·시)을
/// 한 번 얻어 여기에 **박제**한다(이후 재지오코딩 없이 오프라인에서도 표시). 좌표와 동일한
/// 옵셔널-마이그레이션 패턴 — 키가 없는 기존 레코드는 `decodeIfPresent`로 nil 디코드.
struct Capture: Identifiable, Codable {
    let id: UUID
    let type: CaptureType
    let originalFilename: String
    let filterID: String
    let ratio: AspectRatio
    let createdAt: Date
    let latitude: Double?
    let longitude: Double?
    let placeName: String?

    /// 좌표가 **둘 다** 있을 때만 좌표를 돌려준다 — 인포 시트의 지도 섹션 표시 조건.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: UUID, type: CaptureType, originalFilename: String, filterID: String,
         ratio: AspectRatio, createdAt: Date,
         latitude: Double? = nil, longitude: Double? = nil, placeName: String? = nil) {
        self.id = id
        self.type = type
        self.originalFilename = originalFilename
        self.filterID = filterID
        self.ratio = ratio
        self.createdAt = createdAt
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, originalFilename, filterID, ratio, createdAt, latitude, longitude, placeName
    }

    /// 명시적 디코드 — 좌표는 **decodeIfPresent**. 기존 레코드엔 두 키가 아예 없으므로
    /// 없으면 nil로 안전 디코드된다(throw 아님) → 예전 사진이 전부 그대로 로드된다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(CaptureType.self, forKey: .type)
        originalFilename = try c.decode(String.self, forKey: .originalFilename)
        filterID = try c.decode(String.self, forKey: .filterID)
        ratio = try c.decode(AspectRatio.self, forKey: .ratio)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        placeName = try c.decodeIfPresent(String.self, forKey: .placeName)
    }

    /// 명시적 인코드 — 좌표는 **encodeIfPresent**. 좌표 없는 사진의 JSON은 예전과
    /// 완전히 동일(불필요한 null 키 없음) → 전/후 호환.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(originalFilename, forKey: .originalFilename)
        try c.encode(filterID, forKey: .filterID)
        try c.encode(ratio, forKey: .ratio)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(latitude, forKey: .latitude)
        try c.encodeIfPresent(longitude, forKey: .longitude)
        try c.encodeIfPresent(placeName, forKey: .placeName)
    }
}
