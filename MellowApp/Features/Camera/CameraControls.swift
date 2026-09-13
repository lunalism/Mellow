import SwiftUI

struct CameraDurationSelector: View {
    @Binding var selected: CameraDuration
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: dynamicTypeSize.isAccessibilitySize ? 3 : 5)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(CameraDuration.allCases, id: \.rawValue) { duration in
                Button { selected = duration } label: {
                    Text("\(duration.rawValue)s")
                        .font(.headline)
                        .fontWeight(duration == selected ? .semibold : .regular)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if duration == selected {
                                Capsule().fill(.white).frame(width: 20, height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(duration.rawValue) seconds")
                .accessibilityHint("Select camera maximum duration")
                .accessibilityValue(duration == selected ? "Selected" : "Not selected")
                .accessibilityAddTraits(duration == selected ? .isSelected : [])
                .accessibilityIdentifier("duration\(duration.rawValue)")
            }
        }
        .frame(maxWidth: 300)
        .padding(4)
    }
}

struct CameraFlipButton: View {
    let enabled: Bool
    let position: CameraPosition
    let flip: () -> Void
    @ScaledMetric(relativeTo: .title2) private var diameter = 52.0
    var body: some View {
        Button(action: flip) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2).frame(width: diameter, height: diameter)
                .background(Color.white.opacity(0.12)).clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(.white).disabled(!enabled)
        .accessibilityLabel("Switch camera")
        .accessibilityValue(position == .front ? "Front camera" : "Rear camera")
        .accessibilityHint("Switches between front and rear camera")
        .accessibilityIdentifier("cameraSwitch")
    }
}

struct CameraShutter: View {
    let enabled: Bool
    let size: CGFloat
    var body: some View {
        Button {} label: {
            Circle().fill(enabled ? Color.white : Color.white.opacity(0.25))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.white.opacity(enabled ? 1 : 0.4), lineWidth: 4))
                .overlay {
                    if !enabled { Image(systemName: "slash.circle").font(.title2).foregroundStyle(.black.opacity(0.5)) }
                }
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityIdentifier("cameraShutter").accessibilityLabel("Shutter")
        .accessibilityHint("Recording is not available yet")
    }
}

struct CameraContentSlot: View {
    let clipCount: Int
    @ScaledMetric(relativeTo: .caption) private var thumbnailWidth = 84.0
    @ScaledMetric(relativeTo: .caption) private var thumbnailHeight = 48.0
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.12))
                .frame(width: thumbnailWidth, height: thumbnailHeight)
                .overlay {
                    // The root Camera owns no project yet, so the empty slot stays a neutral
                    // affordance rather than a labelled control.
                    if clipCount > 0 {
                        Text(clipCount == 1 ? "1 clip" : "\(clipCount) clips")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
            if clipCount > 0 {
                Text("Project content").font(.caption).foregroundStyle(Color.white.opacity(0.82))
            }
        }
        // No functional Clip Review destination exists until Phase 5.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("projectContent")
        .accessibilityLabel(clipCount == 0 ? "Project content, empty" : "Project content, \(clipCount) clips")
        .accessibilityHint("Clip review is not available yet")
    }
}

/// Quiet secondary access to the dedicated Recent Projects browser from the Camera surface.
struct CameraProjectsButton: View {
    let open: () -> Void
    @ScaledMetric(relativeTo: .title2) private var diameter = 44.0
    var body: some View {
        Button(action: open) {
            Image(systemName: "rectangle.stack")
                .font(.title3)
                .frame(width: max(44, diameter), height: max(44, diameter))
                .background(Color.black.opacity(0.32))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel("Projects")
        .accessibilityHint("Opens your saved vlogs")
        .accessibilityIdentifier("projects")
    }
}
