import SwiftUI

struct OrientationSelectionView<ExistingProjects: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var titleSize = 28.0
    @ScaledMetric(relativeTo: .title3) private var optionSize = 20.0
    @ScaledMetric(relativeTo: .body) private var bodySize = 17.0
    let select: (ProjectOrientation) -> Void
    @ViewBuilder let existingProjects: () -> ExistingProjects

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 28) {
                    Text("Choose your vlog format")
                        .font(.system(size: titleSize, weight: .semibold, design: .default))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("formatTitle")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 16) {
                        ForEach(ProjectOrientation.allCases, id: \.self) { orientation in
                            Button { select(orientation) } label: {
                                VStack(spacing: 20) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(lineWidth: 2)
                                            .frame(width: orientation == .portrait9x16 ? 54 : 96, height: orientation == .portrait9x16 ? 96 : 54)
                                    }
                                    .frame(height: 100)
                                    .accessibilityHidden(true)
                                    VStack(spacing: 6) {
                                        Text(orientation == .portrait9x16 ? "Portrait" : "Landscape").font(.system(size: optionSize, weight: .semibold, design: .default))
                                        Text(orientation == .portrait9x16 ? "9:16" : "16:9").font(.system(size: bodySize, weight: .regular, design: .default))
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(orientation.displayTitle)
                            .accessibilityHint("Creates and saves a new vlog")
                            .accessibilityIdentifier(orientation.rawValue)
                        }
                    }
                    existingProjects()
                        .font(.system(size: bodySize, weight: .regular, design: .default))
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .clipped()
        }
        .background(MellowDesignSystem.brandBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}
