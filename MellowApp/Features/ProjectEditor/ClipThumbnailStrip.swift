import SwiftUI

/// Horizontal ordered clip strip (ADR-034): one placeholder item per clip, tap to select. No drag
/// reorder and no fake drag affordances in this slice.
struct ClipThumbnailStrip: View {
    let clips: [VlogClip]
    let selectedClipID: UUID?
    let select: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    ClipThumbnailItem(
                        clip: clip,
                        position: index + 1,
                        total: clips.count,
                        isSelected: clip.id == selectedClipID,
                        select: { select(clip.id) }
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .frame(height: 104)
        .accessibilityIdentifier("clipThumbnailStrip")
    }
}

private struct ClipThumbnailItem: View {
    let clip: VlogClip
    let position: Int
    let total: Int
    let isSelected: Bool
    let select: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                shape
                    .fill(Color(.systemGray5))
                    .frame(width: 54, height: 72)
                    // High-contrast placeholder: the clip's position number, not a faint icon.
                    .overlay { Text("\(position)").font(.headline).foregroundStyle(.primary) }
                    // Selection is conveyed by a thick border AND a checkmark badge — never colour
                    // alone (ADR-034 / accessibility).
                    .overlay {
                        shape.strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 3)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.primary)
                                .padding(2)
                        }
                    }
                Text(ClipDurationText.string(clip.effectiveDuration))
                    .font(.caption2).monospacedDigit().foregroundStyle(.primary)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("editorClip-\(position)")
        .accessibilityLabel("Clip \(position) of \(total), \(ClipDurationText.string(clip.effectiveDuration))")
        // Selection is exposed both as the standard trait (VoiceOver) and as an accessibility value
        // ("Selected") so it is conveyed non-visually and is deterministically assertable.
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
