import SwiftUI
import ImageIO
import CoreLocation

/// 사진 상세 뷰의 ⓘ 인포 바텀시트 (Phase 1 · Stage: detail-view info sheet).
///
/// **우리가 이미 가진 메타데이터만** 보여준다 — 필터(표시명), 촬영 날짜·시각, 비율, 해상도.
/// 차가운 EXIF 덤프가 아니라 §9의 따뜻한 필름 다이어리 톤: 페이퍼 크림 표면 · 들린 잉크 텍스트 ·
/// 웜톤 헤어라인. 순수 흰색/검정 없음.
///
/// - 필터 표시명은 `FilterPreset.preset(for:)`로 매핑(원시 filterID 문자열은 노출하지 않음).
/// - 비율은 `capture.ratio`에서 **동적**으로(저장된 실제 비율). 하드코딩 9:16 아님.
/// - 해상도는 저장에 없으므로 **원본 JPEG 헤더**에서 읽는다(ImageIO, 픽셀 크기만 — 전체 디코드 없음).
/// - 위치/지도는 **별도 슬라이스**. 여기선 레이아웃 슬롯만 예약(아래 MAP SLOT 참고).
struct PhotoInfoSheet: View {
    let capture: Capture

    /// 원본 JPEG 헤더에서 읽은 픽셀 크기(비동기 로드). nil이면 로딩 중 "—".
    @State private var pixelSize: CGSize?

    /// 역지오코딩된 장소명 (slice B-2). 디스크에 박제됐으면 그 값으로 시작, 없으면 시트 오픈 시
    /// best-effort 지오코딩. nil이면 지도에 라벨을 표시하지 않는다.
    @State private var placeName: String?

    init(capture: Capture) {
        self.capture = capture
        _placeName = State(initialValue: capture.placeName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 필터 스와치 + 표시명 ····· 시각(우측 정렬)
            HStack(spacing: 10) {
                Circle()
                    .fill(MellowFilterRoster.swatchColor(forSlug: capture.filterID))  // 로스터 = 스와치 단일 진실
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.mellowBorder, lineWidth: 0.5))  // 크림 위 은은한 테두리
                Text(MellowFilterRoster.displayName(forSlug: capture.filterID))    // 로스터 slug→표시명(원시 filterID 아님)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.mellowTextPrimary)
                Spacer(minLength: 12)
                Text(Self.timeText(capture.createdAt))                             // "오후 8:26"
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mellowTextSecondary)
            }

            // 날짜 라인(상단 chrome은 짧은 날짜라, 여기서 전체 날짜를 조용히 보강).
            Text(Self.dateText(capture.createdAt))                                 // "2026. 7. 2"
                .font(.system(size: 13))
                .foregroundStyle(Color.mellowTextSecondary)
                .padding(.top, 4)

            // 지도 섹션 (slice B-1) — **좌표가 있을 때만**. 없으면(기존 사진 / 위치 거부)
            // 섹션을 통째로 접는다: 빈 밴드 없음, 중복 헤어라인 없음.
            // 좌표가 있으면 두 헤어라인이 지도를 위아래로 감싼다.
            if let coordinate = capture.coordinate {
                divider.padding(.vertical, 16)
                MapSnapshotView(coordinate: coordinate,
                                mapItemName: Self.dateText(capture.createdAt),   // Apple Maps 핀 이름(B-1)
                                placeName: placeName)                            // 역지오코딩 라벨(B-2)
            }

            // 메타 푸터 앞 헤어라인(지도 유무와 무관하게 항상 하나).
            divider.padding(.vertical, 16)

            // 메타 푸터(조용히, 작게): 비율 · 해상도
            HStack(alignment: .top, spacing: 28) {
                metaColumn(label: "비율", value: Self.ratioLabel(capture.ratio))    // capture.ratio에서 동적
                metaColumn(label: "해상도", value: resolutionText)                 // 원본 헤더에서 유도
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: capture.id) { await loadPixelSize() }
        .task(id: capture.id) { await loadPlaceName() }
    }

    // MARK: - 조각

    private var divider: some View {
        Rectangle().fill(Color.mellowBorder).frame(height: 1)   // 웜톤 헤어라인(라이트탄)
    }

    private func metaColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.mellowTextSecondary.opacity(0.85))
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.mellowTextPrimary)
        }
    }

    private var resolutionText: String {
        guard let s = pixelSize else { return "—" }
        return "\(Int(s.width)) × \(Int(s.height))"
    }

    // MARK: - 해상도(원본 헤더에서)

    /// 원본 JPEG의 픽셀 크기를 헤더에서만 읽는다(전체 디코드 없음). 백그라운드에서 실행.
    private func loadPixelSize() async {
        let url = CaptureStore.shared.url(for: capture)
        let size = await Task.detached(priority: .utility) { Self.readPixelSize(url: url) }.value
        if let size { pixelSize = size }
    }

    // MARK: - 장소명 (slice B-2, best-effort 역지오코딩 + 박제)

    /// 시트 오픈 시 장소명 확보. 우선순위: 이미 있는 값(디스크 박제) → 이번 세션에 저장된 값 →
    /// 없으면 best-effort 역지오코딩 1회. 좌표가 없으면 라벨 자체가 없으므로 아무것도 안 한다.
    /// 실패(오프라인·레이트리밋·결과 없음)면 저장하지 않아 다음 오픈 때 재시도된다(에러 표시 없음).
    private func loadPlaceName() async {
        guard let coordinate = capture.coordinate else { return }   // 좌표 없음 → 라벨 없음
        if placeName != nil { return }                              // 이미 박제됨(디스크 로드) → 끝
        // 이번 세션에 이미 지오코딩·저장됐는지(스토어가 단일 진실).
        if let stored = CaptureStore.shared.placeName(for: capture.id) {
            placeName = stored
            return
        }
        // best-effort 1회. 실패/중복 인플라이트면 nil → 저장 안 함(재시도 여지).
        guard let name = await ReverseGeocoder.shared.placeName(id: capture.id, coordinate: coordinate) else {
            return
        }
        CaptureStore.shared.setPlaceName(name, for: capture.id)     // 박제 → 다시는 지오코딩 안 함
        placeName = name
    }

    /// ImageIO로 헤더의 픽셀 폭·높이만 조회. 저장 원본은 이미 .up 방향이라 그대로 표시 크기.
    /// 순수 함수(액터 상태 없음)라 `nonisolated` — 백그라운드 detached 태스크에서 안전하게 호출.
    nonisolated private static func readPixelSize(url: URL) -> CGSize? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    // MARK: - 표시 매핑

    private static func ratioLabel(_ ratio: AspectRatio) -> String {
        switch ratio {
        case .ratio9x16: return "9:16"
        case .ratio4x3:  return "4:3"
        case .ratio1x1:  return "1:1"
        case .ratio2x1:  return "2:1"
        }
    }

    // MARK: - 날짜/시각(ko_KR)
    // 상세 뷰 nav 타이틀의 결합 포맷(yMMMdjm)과 달리, 시트는 날짜·시각을 **분리**해 보여주므로
    // 시각 전용(jm)·날짜 전용(yMd) 포맷터를 둔다(같은 ko_KR 접근, 다른 세분화).

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("jm")     // "오후 8:26"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("yMd")    // "2026. 7. 2"
        return f
    }()

    private static func timeText(_ date: Date) -> String { timeFormatter.string(from: date) }
    private static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }
}
