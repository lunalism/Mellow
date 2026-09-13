import SwiftUI

struct CameraPlaceholderView: View {
    let project: VlogProject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Camera Placeholder").font(.title2).fontWeight(.semibold)
                    .accessibilityIdentifier("cameraPlaceholder")
                Text(project.displayName()).font(.headline)
                Text(project.orientation.displayTitle)
                    .accessibilityIdentifier("projectOrientation")
                Text("Your vlog is saved.").foregroundStyle(MellowDesignSystem.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(MellowDesignSystem.brandBackground.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("Vlog")
        .navigationBarTitleDisplayMode(.inline)
    }
}
