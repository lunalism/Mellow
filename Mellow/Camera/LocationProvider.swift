import CoreLocation

/// 촬영 위치 캐시 (Phase 1 · slice B-1). 카메라 화면이 활성인 동안만 **코스 정확도**로
/// 위치를 갱신하고, 셔터에서 **동기로** 마지막 좌표를 읽어 캡처에 붙인다.
///
/// 설계 원칙:
/// - **셔터를 느리게 하지 않는다.** 셔터 시 새 GPS fix를 기다리지 않고 `lastCoordinate`를
///   그대로 읽는다(없으면 nil → 좌표 없이 저장). fix 대기 = 셔터 스톨이므로 금지.
/// - **코스 정확도(`kCLLocationAccuracyHundredMeters`)** — 동네 수준이면 충분, 배터리·발열 친화.
/// - **거부는 완전 무해.** 권한 없으면 아무것도 안 하고, 앱은 예전과 똑같이 동작(좌표만 없음).
/// - **발열:** 카메라 이탈(백그라운드) 시 `stop()`으로 업데이트를 끈다.
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    /// 셔터에서 동기로 읽는 마지막 캐시 좌표. 아직 fix가 없으면 nil.
    private(set) var lastCoordinate: CLLocationCoordinate2D?

    /// 카메라 화면이 업데이트를 원하는 상태인지 — 권한 변경 콜백이 백그라운드에서
    /// 멋대로 업데이트를 켜지 않도록 게이트.
    private var wantsUpdates = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters   // 코스 = 동네 수준
    }

    /// 카메라 권한이 이미 허용된 화면에서 호출. 위치가 **미결정일 때만** When-In-Use 요청.
    /// 이미 허용/거부됐으면 아무것도 하지 않는다(사용자를 다시 괴롭히지 않음).
    func requestIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// 카메라 화면 활성 → 업데이트 시작(권한 있을 때만 실제 시작).
    func start() {
        wantsUpdates = true
        startIfPossible()
    }

    /// 카메라 화면 이탈(백그라운드) → 업데이트 중단. 캐시 좌표는 유지.
    func stop() {
        wantsUpdates = false
        manager.stopUpdatingLocation()
    }

    private func startIfPossible() {
        guard wantsUpdates else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break   // 미결정/거부 → 시작 안 함(무해)
        }
    }

    // MARK: - CLLocationManagerDelegate
    // CLLocationManager는 매니저를 만든 스레드(=여기선 메인)의 런루프에서 델리게이트를 부른다.
    // 그래서 nonisolated로 선언하고 메인 격리로 진입(assumeIsolated)한다 — Swift 6에서도 안전.

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        MainActor.assumeIsolated { self.lastCoordinate = coord }
    }

    /// 사용자가 방금 허용했다면(카메라 화면에 있는 동안) 곧바로 업데이트 시작.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { self.startIfPossible() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 무시 — 기존 캐시 좌표를 유지한다. 위치를 못 얻으면 좌표 없이 저장될 뿐, 앱은 정상.
    }
}
