import SwiftUI

/// 시뮬레이터 더미 프리뷰 (Phase 1 Spec §10).
///
/// 시뮬레이터엔 카메라가 없어 라이브 프리뷰가 불가능하다. 크래시 대신
/// 따뜻한 페이퍼 톤 정지 화면으로 폴백하고 실기기 테스트를 유도한다.
struct DummyCameraView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.mellowCream, .mellowDreamWash, .mellowLatte],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 12) {
                Image(systemName: "camera.metering.unknown")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.mellowTextSecondary)

                Text("시뮬레이터 더미 모드")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.mellowTextPrimary)

                Text("실기기에서 라이브 프리뷰를 확인하세요")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mellowTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

#Preview {
    DummyCameraView()
}
