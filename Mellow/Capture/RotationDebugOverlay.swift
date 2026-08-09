import SwiftUI

/// 1-2 의 핵심 산출물. 기기를 돌려가며 네 값이 어떻게 움직이는지 보는 계기판이다.
/// 못생겨도 된다. Phase 1 이 끝날 때까지 UI 를 다듬지 않는다.
struct RotationDebugOverlay: View {

    let controller: CameraController

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("preview", degrees(controller.previewAngle),
                "obs \(controller.previewObservationCount)")
            row("capture", degrees(controller.captureAngle),
                "obs \(controller.captureObservationCount)")
            row("pollP", degrees(controller.polledPreviewAngle),
                controller.previewKVOMismatch ? "MISMATCH" : "match")
            row("applied", degrees(controller.appliedAngle),
                controller.appliedSupported ? "supported" : "UNSUPPORTED")
            row("device", controller.deviceOrientation.shortText, "")

            Divider().overlay(.white.opacity(0.3)).padding(.vertical, 2)

            row("session", controller.sessionState, "")
            row("coord", controller.coordinatorState, "")
            row("perm", "video \(controller.videoAuthorization.shortText)",
                "audio \(controller.audioAuthorization.shortText)")
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ label: String, _ value: String, _ trailing: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .frame(width: 62, alignment: .leading)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
            if !trailing.isEmpty {
                Text("(\(trailing))").foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func degrees(_ value: CGFloat) -> String {
        "\(Int(value.rounded()))°"
    }
}
