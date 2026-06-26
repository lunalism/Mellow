import SwiftUI

/// 권한 프라이밍 & 거부 안내 (Phase 1 Spec §5.1, §10).
///
/// - notDetermined: 따뜻한 톤의 프라이밍 + "카메라 켜기" → 시스템 프롬프트.
/// - denied: 안내 + "설정에서 권한 켜기". 앱은 죽지 않는다.
///
/// 온보딩/회원가입 화면이 아니라 **첫 실행 권한 프라이밍**만. (CLAUDE.md 제약)
struct PermissionPrimingView: View {
    /// true면 거부 상태 안내, false면 최초 프라이밍.
    let isDenied: Bool
    /// 프라이밍에서 "켜기" 탭 → 권한 요청.
    let onRequest: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.mellowPaper.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.mellowAccent)
                    .shadow(color: Color.mellowShadow.opacity(0.12), radius: 8, y: 4)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.mellowTextPrimary)

                    Text(message)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mellowTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 36)
                }

                Button(action: primaryAction) {
                    Text(buttonTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.mellowIvory)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.mellowAccent)
                        )
                        .shadow(color: Color.mellowShadow.opacity(0.18), radius: 10, y: 5)
                }
                .padding(.top, 4)
            }
            .padding()
        }
    }

    private var title: String {
        isDenied ? "카메라 권한이 필요해요" : "순간을 담을 준비"
    }

    private var message: String {
        isDenied
            ? "설정에서 카메라 접근을 허용하면\n필름 감성 프리뷰를 바로 볼 수 있어요."
            : "라이브 필름 프리뷰로\n지금 이 순간을 따뜻하게 담아요."
    }

    private var buttonTitle: String {
        isDenied ? "설정 열기" : "카메라 켜기"
    }

    private func primaryAction() {
        if isDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } else {
            onRequest()
        }
    }
}

#Preview("프라이밍") {
    PermissionPrimingView(isDenied: false, onRequest: {})
}

#Preview("거부") {
    PermissionPrimingView(isDenied: true, onRequest: {})
}
