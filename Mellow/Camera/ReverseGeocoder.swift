import CoreLocation

/// 좌표 → 짧은 장소명 역지오코딩 (Phase 1 · slice B-2).
///
/// ⚠️ 이 앱의 **첫 아웃바운드 네트워크 호출** — `CLGeocoder`는 좌표를 Apple 서버로 보낸다.
/// 그래서 **strictly best-effort**: 성공하면 호출부가 결과를 캡처에 **박제**(persist)해 다시는
/// 지오코딩하지 않고, 실패(오프라인·레이트리밋·결과 없음)면 **아무것도 저장하지 않고 nil**을
/// 돌려줘 다음 시트 오픈 때 재시도한다. 에러 문자열/스피너를 절대 UI에 노출하지 않는다.
///
/// 같은 캡처에 대한 **중복 인플라이트**를 막는다(시트를 빠르게 여닫아도 요청은 1건).
@MainActor
final class ReverseGeocoder {
    static let shared = ReverseGeocoder()

    /// 진행 중인 캡처 id — 중복 요청 방지.
    private var inFlight: Set<UUID> = []

    private init() {}

    /// 좌표를 짧은 장소명으로. 이미 같은 캡처가 진행 중이거나 실패/결과 없음이면 nil.
    /// nil이면 호출부는 **저장하지 않는다**(재시도 여지 유지).
    func placeName(id: UUID, coordinate: CLLocationCoordinate2D) async -> String? {
        guard !inFlight.contains(id) else { return nil }
        inFlight.insert(id)
        defer { inFlight.remove(id) }

        // 요청마다 새 CLGeocoder — 단일 인스턴스 동시 요청 제약을 피한다.
        // preferredLocale을 넘기지 않아 **기기 로케일 그대로**(한국어 기기 → "도쿄", 영어 기기 → "Tokyo").
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        #if DEBUG
        ThermalDiagnostics.shared.beginGeocode()
        #endif
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        #if DEBUG
        ThermalDiagnostics.shared.endGeocode()
        #endif
        guard let placemark = placemarks?.first else { return nil }
        return Self.shortName(from: placemark)
    }

    /// **국가 불문 폴백 체인** — 두 필드가 다 있다고 가정하지 않는다.
    /// subLocality(동네)+locality(시) → "동네, 시" / 하나만 → 그것 / 없음 → nil(라벨 접힘).
    /// 빈 문자열/공백은 없음으로 취급 → 어정쩡한 콤마("성수동, ")나 빈 라벨이 생기지 않는다.
    static func shortName(from placemark: CLPlacemark) -> String? {
        let sub = nonEmpty(placemark.subLocality)
        let city = nonEmpty(placemark.locality)
        switch (sub, city) {
        case let (s?, c?): return "\(s), \(c)"
        case let (s?, nil): return s
        case let (nil, c?): return c
        case (nil, nil):    return nil
        }
    }

    /// 트림 후 비어 있으면 nil.
    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
