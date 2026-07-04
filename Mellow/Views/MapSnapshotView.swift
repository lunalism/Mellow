import SwiftUI
import UIKit
import MapKit

/// 인포 시트의 **정적 지도** (Phase 1 · slice B-1).
///
/// `MKMapSnapshotter`로 좌표에 핀을 찍은 정적 스냅샷을 렌더한다 — 인앱 라이브 지도 아님,
/// 지오코딩(장소명) 아님(그건 B-2). 지도 타일은 **원색 그대로**(틴트 금지 — 타일이 탁해짐),
/// 대신 따뜻한 크림 라운드 프레임으로 §9 시트 톤에 녹인다. 탭 → Apple Maps 앱으로 연다.
///
/// 스냅샷은 `.utility` 백그라운드에서 생성하고, 좌표+크기 키로 캐시해 재오픈 시 즉시 표시한다.
struct MapSnapshotView: View {
    let coordinate: CLLocationCoordinate2D
    /// Apple Maps에서 열릴 때 핀에 붙는 이름(B-1: 촬영 날짜). 탭 동작은 B-1 그대로 유지.
    let mapItemName: String
    /// 역지오코딩된 짧은 장소명 (slice B-2). nil이면 라벨 미표시(지도+핀만 = B-1 상태).
    let placeName: String?

    @State private var snapshot: UIImage?

    private static let cache = NSCache<NSString, UIImage>()
    private let cornerRadius: CGFloat = 14
    private let height: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let snapshot {
                    Image(uiImage: snapshot).resizable().scaledToFill()
                } else {
                    // 로딩/실패(오프라인 타일 등) 시 은은한 웜 플레이스홀더.
                    Color.mellowLightTan
                    Image(systemName: "map")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.mellowTextSecondary.opacity(0.5))
                }
            }
            .frame(width: geo.size.width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.mellowBorder, lineWidth: 1)      // 크림 라운드 프레임(§9)
            )
            // 장소명 필 (slice B-2) — 좌하단, placeName 있을 때만. §9 웜톤: 크림 필 · 앰버 핀 · 잉크 텍스트.
            .overlay(alignment: .bottomLeading) { placePill }
            .task(id: cacheKey(width: geo.size.width)) {
                await loadSnapshot(width: geo.size.width)
            }
        }
        .frame(height: height)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture { openInMaps() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("지도에서 열기")
    }

    /// 장소명 필 — placeName이 있을 때만. 크림 캡슐 + 앰버 맵핀 아이콘 + 들린 잉크 텍스트.
    @ViewBuilder
    private var placePill: some View {
        if let placeName {
            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.mellowAccent)          // 앰버/코랄 액센트
                Text(placeName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.mellowTextPrimary)     // 들린 블랙 #4A443A
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.mellowPaper.opacity(0.96)))   // 크림 필
            .overlay(Capsule().stroke(Color.mellowBorder, lineWidth: 0.5))
            .shadow(color: Color.mellowShadow.opacity(0.18), radius: 4, y: 1)
            .padding(10)
        }
    }

    private func cacheKey(width: CGFloat) -> String {
        "\(coordinate.latitude),\(coordinate.longitude)@\(Int(width))x\(Int(height))"
    }

    @MainActor private func loadSnapshot(width: CGFloat) async {
        guard width > 0 else { return }
        let key = cacheKey(width: width) as NSString
        if let cached = Self.cache.object(forKey: key) { snapshot = cached; return }
        let image = await Self.render(coordinate: coordinate, size: CGSize(width: width, height: height))
        guard let image else { return }        // 실패 → 플레이스홀더 유지
        Self.cache.setObject(image, forKey: key)
        snapshot = image
    }

    /// 백그라운드(.utility)에서 스냅샷 생성 후 핀 합성.
    private static func render(coordinate: CLLocationCoordinate2D, size: CGSize) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: 700, longitudinalMeters: 700)
        options.size = size
        options.mapType = .standard
        let snapshotter = MKMapSnapshotter(options: options)
        #if DEBUG
        ThermalDiagnostics.shared.beginMapSnapshot()
        #endif
        return await withCheckedContinuation { continuation in
            snapshotter.start(with: DispatchQueue.global(qos: .utility)) { snapshot, _ in
                #if DEBUG
                ThermalDiagnostics.shared.endMapSnapshot()
                #endif
                guard let snapshot else { continuation.resume(returning: nil); return }
                continuation.resume(returning: compositePin(on: snapshot, coordinate: coordinate, size: size))
            }
        }
    }

    /// 스냅샷 이미지 위, 좌표 지점에 앰버 핀을 그린다.
    private static func compositePin(on snapshot: MKMapSnapshotter.Snapshot,
                                     coordinate: CLLocationCoordinate2D, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            snapshot.image.draw(at: .zero)
            let point = snapshot.point(for: coordinate)
            let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)
            if let pin = UIImage(systemName: "mappin.circle.fill", withConfiguration: config)?
                .withTintColor(UIColor(Color.mellowAccent), renderingMode: .alwaysOriginal) {
                pin.draw(in: CGRect(x: point.x - pin.size.width / 2,
                                    y: point.y - pin.size.height / 2,
                                    width: pin.size.width, height: pin.size.height))
            }
        }
    }

    /// 탭 → Apple Maps 앱에서 좌표를 연다(합리적 span). 인앱 지도·지오코딩 없음.
    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = mapItemName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan:
                MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        ])
    }
}
