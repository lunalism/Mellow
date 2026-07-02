import SwiftUI
import ImageIO

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 필터 스와치 + 표시명 ····· 시각(우측 정렬)
            HStack(spacing: 10) {
                Circle()
                    .fill(Self.swatchColor(for: capture.filterID))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.mellowBorder, lineWidth: 0.5))  // 크림 위 은은한 테두리
                Text(FilterPreset.preset(for: capture.filterID).displayName)       // 원시 filterID 아님
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

            // 2. 헤어라인
            divider.padding(.vertical, 16)

            // 3. MAP SLOT — 예약된 빈 영역.
            // TODO: location map (slice B) — 위치/지도는 별도 슬라이스에서 여기에 들어간다.
            //       지금은 레이아웃 위치만 예약한다. CoreLocation/MapKit import 없음, 위치 권한 요청 없음.
            Color.clear.frame(height: 104)

            // 4. 헤어라인
            divider.padding(.vertical, 16)

            // 5. 메타 푸터(조용히, 작게): 비율 · 해상도
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

    /// ImageIO로 헤더의 픽셀 폭·높이만 조회. 저장 원본은 이미 .up 방향이라 그대로 표시 크기.
    private static func readPixelSize(url: URL) -> CGSize? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    // MARK: - 표시 매핑

    /// 필터별 표시 스와치(장식용). 8종 확장 시 여기에 추가. 미상은 앰버 폴백.
    private static func swatchColor(for filterID: String) -> Color {
        switch filterID {
        case "sunday":   return .mellowAmber        // 따뜻한 앰버
        case "honey":    return .mellowGolden       // 골든
        case "original": return .mellowLatte        // 중립 라떼
        default:         return .mellowAccent
        }
    }

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
