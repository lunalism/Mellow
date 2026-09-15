import SwiftUI

/// Bottom editing dock (ADR-034 §3 hierarchy: Preview → ordered strip → clip / project actions). A
/// persistent dark surface holding the structural Add-Clip slot, the leading-aligned ordered clip
/// timeline and the quiet Total metadata. Reorder (long press + horizontal drag) is the next slice;
/// the timeline is laid out so that slice only adds a gesture, never a new structure.
struct EditorTimelineDock: View {
    let clips: [VlogClip]
    let selectedClipID: UUID?
    let totalDuration: MediaTime
    let thumbnail: (UUID) -> ClipThumbnailPresentation
    let select: (UUID) -> Void
    /// DEBUG-only staging of the future Add Clip reference visual. Production never sets this: the
    /// timeline starts at the dock's leading inset with no dead control and no empty slot; a real
    /// Add Clip button is later prepended to the same HStack without changing the layout.
    var showsStagedAddSlot = false

    /// Compact dock (≈100 pt from the fixed cell geometry): add slot + clip row vertically centred,
    /// Total as quiet caption metadata in the top-trailing corner, in its own column so it never
    /// overlaps scrolled cells. No header row.
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showsStagedAddSlot {
                StagedAddClipSlot()
                    .frame(height: ProjectEditorModel.thumbnailPointSize.height)
            }
            ClipThumbnailStrip(clips: clips, selectedClipID: selectedClipID, thumbnail: thumbnail, select: select)
            Text("Total \(ClipDurationText.string(totalDuration))")
                .font(.caption2).monospacedDigit().foregroundStyle(EditorWorkspace.secondaryText)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .fixedSize()
                .padding(.trailing, 10)
                .accessibilityIdentifier("projectTotalDuration")
                .accessibilityLabel("Total duration \(ClipDurationText.string(totalDuration))")
        }
        .padding(.leading, 10)
        .padding(.vertical, 11)
        .background(EditorWorkspace.dock, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editorDock")
    }
}

/// DEBUG-only reference visual for the future Phase 5 `Add Clips` action (ADR-034 §3): 40 pt circle,
/// non-interactive, hidden from accessibility. Never compiled into Release.
private struct StagedAddClipSlot: View {
    var body: some View {
        #if DEBUG
        ZStack {
            Circle().fill(EditorWorkspace.control)
            Image(systemName: "plus").font(.body.weight(.medium)).foregroundStyle(EditorWorkspace.primaryText)
        }
        .frame(width: 40, height: 40)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityHidden(true)
        #else
        EmptyView()
        #endif
    }
}

/// Leading-aligned ordered filmstrip: one compact real-thumbnail cell per clip in logical order,
/// left → right, tap to select; scrolls horizontally once cells exceed the available width. Short
/// projects are never centred — the timeline origin is stable for the coming drag-reorder slice.
struct ClipThumbnailStrip: View {
    let clips: [VlogClip]
    let selectedClipID: UUID?
    let thumbnail: (UUID) -> ClipThumbnailPresentation
    let select: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // Identity is the stable clip id; `position` is display-only (label / test hooks).
            LazyHStack(alignment: .center, spacing: 4) {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    ClipTimelineCell(
                        clip: clip,
                        position: index + 1,
                        total: clips.count,
                        thumbnail: thumbnail(clip.id),
                        isSelected: clip.id == selectedClipID,
                        select: { select(clip.id) }
                    )
                }
            }
            .padding(.trailing, 8)
        }
        .frame(height: ProjectEditorModel.thumbnailPointSize.height)
        .accessibilityIdentifier("clipThumbnailStrip")
    }
}

private struct ClipTimelineCell: View {
    let clip: VlogClip
    let position: Int
    let total: Int
    let thumbnail: ClipThumbnailPresentation
    let isSelected: Bool
    let select: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
    private var size: CGSize { ProjectEditorModel.thumbnailPointSize }

    var body: some View {
        // The image-only button carries the tap; the duration tag is a decorative overlay drawn
        // (not a text node) because the cell label already speaks the duration — it must never be
        // read twice, and a text node cut off at the dock's scroll edge cannot be audited.
        Button(action: select) { thumbnailBox.contentShape(shape) }
            .buttonStyle(.plain)
            .overlay { DurationTag(text: ClipDurationText.string(clip.effectiveDuration)).allowsHitTesting(false) }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityAction(.default) { select() }
            .accessibilityIdentifier("editorClip-\(position)")
            .accessibilityLabel(accessibilityLabel)
            // Selection is exposed both as the standard trait (VoiceOver) and as an accessibility value
            // ("Selected") so it is conveyed non-visually and is deterministically assertable.
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Compact 9:16 timeline segment: the frame aspect-fills and is clipped; media is untouched.
    private var thumbnailBox: some View {
        ZStack {
            EditorWorkspace.control
            switch thumbnail {
            case .ready(let image):
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
            case .loading:
                ProgressView().controlSize(.mini).tint(EditorWorkspace.secondaryText)
            case .unavailable:
                // Neutral fallback in the same slot and geometry; nothing here reads as an error.
                Image(systemName: "film").font(.body).foregroundStyle(EditorWorkspace.secondaryText)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        // Selected = Mellow signature outline (an active timeline segment) plus the accessibility
        // state; stable geometry, no badge, no scale. Unselected = a quiet hairline.
        .overlay {
            shape.strokeBorder(
                isSelected ? MellowDesignSystem.signatureOrange500 : EditorWorkspace.hairline,
                lineWidth: isSelected ? 2 : 1
            )
        }
    }

    private var accessibilityLabel: String {
        var label = "Clip \(position) of \(total), \(ClipDurationText.string(clip.effectiveDuration))"
        switch thumbnail {
        case .ready: break
        case .loading: label += ", loading"
        case .unavailable: label += ", thumbnail unavailable"
        }
        return label
    }
}

/// Quiet bottom-trailing duration tag over a timeline cell. Rendered in a `Canvas` so it is pure
/// presentation (no accessibility node); the text still resolves through the environment font.
private struct DurationTag: View {
    let text: String

    var body: some View {
        Canvas { context, size in
            let resolved = context.resolve(Text(text).font(.caption2).monospacedDigit().foregroundStyle(.white))
            let textSize = resolved.measure(in: size)
            let tag = CGRect(
                x: size.width - textSize.width - 8 - 3, y: size.height - textSize.height - 4 - 3,
                width: textSize.width + 8, height: textSize.height + 4
            )
            context.fill(Path(roundedRect: tag, cornerRadius: 4), with: .color(Color(white: 0.06)))
            context.draw(resolved, at: CGPoint(x: tag.midX, y: tag.midY), anchor: .center)
        }
        // Decorative overlay inside a fixed-size control: capped so it never outgrows the cell; the
        // accessible duration lives in the cell label and scales with VoiceOver / Dynamic Type there.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityHidden(true)
    }
}

/// Editor-only dark media workspace palette (DESIGN §19). Deliberately independent of the app's
/// Light / Dark appearance: Projects is a normal app surface, the Editor is a focused workspace.
enum EditorWorkspace {
    static let canvas = Color.black
    static let dock = Color(white: 0.11)
    static let control = Color(white: 0.2)
    static let hairline = Color(white: 0.32)
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.72)
}
