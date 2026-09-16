import SwiftUI

/// Bottom editing dock (ADR-034 §3 hierarchy: Preview → ordered strip → clip / project actions). A
/// persistent dark surface holding the leading Add Clips action (ADR-037, PhotosPicker append), the
/// leading-aligned ordered clip timeline (tap to select, long press + horizontal drag to reorder)
/// and, in its trailing column, the quiet Total metadata above the selected Clip's explicit Delete
/// action (ADR-034 §3 level 4: Clip-level Action / Project Summary).
struct EditorTimelineDock: View {
    let model: ProjectEditorModel
    /// Explicit delete of the selected Clip; the dock only presents it.
    var deleteSelected: () -> Void = {}
    /// Add Clips ("+"); the dock only presents it. Shown whenever the model has an acquisition boundary.
    var addClips: () -> Void = {}

    /// Compact dock (≈100 pt from the fixed cell geometry): add slot + clip row vertically centred,
    /// Total as quiet caption metadata in the top-trailing corner, in its own column so it never
    /// overlaps scrolled cells. No header row.
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if model.supportsAddingClips {
                AddClipsButton(isEnabled: model.canAddClips, isBusy: model.isAddingClips, action: addClips)
                    .frame(height: ProjectEditorModel.thumbnailPointSize.height)
            }
            ClipThumbnailStrip(model: model)
            VStack(alignment: .trailing, spacing: 0) {
                Text("Total \(ClipDurationText.string(model.totalDuration))")
                    .font(.caption2).monospacedDigit().foregroundStyle(EditorWorkspace.secondaryText)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .fixedSize()
                    .accessibilityIdentifier("projectTotalDuration")
                    .accessibilityLabel("Total duration \(ClipDurationText.string(model.totalDuration))")
                Spacer(minLength: 0)
                DeleteClipButton(isEnabled: model.canDeleteSelectedClip, action: deleteSelected)
            }
            .frame(height: ProjectEditorModel.thumbnailPointSize.height)
            .padding(.trailing, 10)
        }
        .padding(.leading, 10)
        .padding(.vertical, 11)
        .background(EditorWorkspace.dock, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editorDock")
    }
}

/// Explicit Delete for the selected Clip (ADR-034 §3): a compact trash control, 44 pt target,
/// bottom-trailing in the dock so it sits away from the drag surface and never on a thumbnail.
/// Disabled (dimmed, `사용할 수 없음`) when nothing is selected or a drag / save is in flight. No
/// confirmation — the session Undo (ADR-038, top-right) is the safety model (DESIGN §21).
private struct DeleteClipButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.body.weight(.medium))
                .foregroundStyle(isEnabled ? EditorWorkspace.primaryText : EditorWorkspace.hairline)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityIdentifier("deleteSelectedClip")
        .accessibilityLabel("클립 삭제")
        .accessibilityHint("선택한 클립을 삭제해요. 실행 취소할 수 있어요.")
    }
}

/// Production Add Clips action (ADR-034 §3 / ADR-037): the approved 40 pt circle at the timeline's
/// leading edge inside a 44 pt target, opening the system PhotosPicker to append to THIS Project.
/// Disabled (dimmed, `사용할 수 없음`) while a batch is in flight, a save is committing or a clip is
/// lifted, so a second picker can never be presented over a running Add.
private struct AddClipsButton: View {
    let isEnabled: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(EditorWorkspace.control)
                if isBusy {
                    ProgressView().controlSize(.small).tint(EditorWorkspace.secondaryText)
                } else {
                    Image(systemName: "plus").font(.body.weight(.medium))
                        .foregroundStyle(isEnabled ? EditorWorkspace.primaryText : EditorWorkspace.hairline)
                }
            }
            .frame(width: 40, height: 40)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityIdentifier("addClips")
        .accessibilityLabel("클립 추가")
        .accessibilityHint("사진 보관함에서 프로젝트에 클립을 추가합니다.")
    }
}

/// Reorder interaction constants (DESIGN §19 / §20). Kept in one place so the design record and the
/// implementation cannot drift.
enum ClipReorderInteraction {
    /// Deliberate long-press activation: shorter than the system context-menu press so reorder feels
    /// immediate, long enough that an ordinary tap or a scroll flick never lifts a clip.
    static let longPressDuration: TimeInterval = 0.4
    /// Lift presentation while (and only while) a clip is dragged; the committed cell geometry is
    /// restored exactly on drop.
    static let liftedScale: CGFloat = 1.05
    /// Motion (STEP 9.1): direct manipulation for the dragged clip (its translation is never
    /// animated) with restrained, interruptible springs around it — each new reflow retargets the
    /// previous one, nothing queues. No overshoot to speak of, no bounce.
    /// Neighbours gliding into the vacated slot as the lifted clip crosses a threshold.
    static let reflowSpring: Animation = .spring(response: 0.28, dampingFraction: 0.86)
    /// The lifted clip settling into its final slot on drop / cancel (position, scale, shadow).
    static let settleSpring: Animation = .spring(response: 0.24, dampingFraction: 0.9)
    /// Normal cell → lifted state on activation (scale + shadow only, never position).
    static let liftSpring: Animation = .spring(response: 0.2, dampingFraction: 0.9)
    /// Width of the viewport edge band that auto-scrolls the timeline during a drag.
    static let autoScrollEdgeInset: CGFloat = 32
    /// Points scrolled per auto-scroll tick (≈60 Hz → ≈180 pt/s): controlled, never a screen jump.
    static let autoScrollStep: CGFloat = 3
    static let autoScrollInterval: Duration = .milliseconds(16)
}

/// Leading-aligned ordered filmstrip: one compact real-thumbnail cell per clip in logical order,
/// left → right; scrolls horizontally once cells exceed the available width. Short projects are
/// never centred.
///
/// Interaction (STEP 9): tap selects; a long press lifts the clip (one haptic, selection follows the
/// clip) and the following horizontal drag moves it — neighbours reflow as the lifted clip's centre
/// crosses their slots, the timeline auto-scrolls near its edges, and the drop commits the order
/// through `ProjectEditorModel` (autosave). Cancellation restores the committed order. VoiceOver /
/// Switch Control reorder through the per-cell "앞으로 이동" / "뒤로 이동" actions instead.
struct ClipThumbnailStrip: View {
    let model: ProjectEditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Layout slot of every cell in timeline-content coordinates (the HStack's own space). Cells are
    /// non-lazy so the whole timeline is measured; a project has tens of 44 pt cells at most.
    @State private var slotFrames: [UUID: CGRect] = [:]
    @State private var scrollOffsetX: CGFloat = 0
    @State private var scrollContentWidth: CGFloat = 0
    @State private var scrollViewportWidth: CGFloat = 0
    @State private var scrollPosition = ScrollPosition()
    /// Bookkeeping of the drag in flight; nil when no clip is lifted.
    @State private var drag: DragSession?
    @State private var autoScrollTask: Task<Void, Never>?

    private static let viewportSpace = "clipTimelineViewport"
    private static let contentSpace = "clipTimelineContent"
    private var cellSize: CGSize { ProjectEditorModel.thumbnailPointSize }

    /// State of one drag: which clip, where the finger is (viewport x), where the finger grabbed
    /// the cell (content-x offset from its leading edge), the settled slot positions snapshotted at
    /// activation (stable while cells animate between them), the resulting lifted position and the
    /// lift amount (0 = resting cell geometry, 1 = fully lifted; animated on activation and settle).
    /// The session outlives the model's drag for the settle animation; the real cell stays hidden
    /// until the lifted copy has come to rest exactly on it.
    private struct DragSession {
        let clipID: UUID
        var settledSlots: [CGRect]
        var grabOffset: CGFloat?
        var fingerViewportX: CGFloat
        var liftedMinX: CGFloat
        var lift: CGFloat = 0
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // Identity is the stable clip id; `position` is display-only (label / test hooks).
            HStack(alignment: .center, spacing: 4) {
                ForEach(Array(model.orderedClips.enumerated()), id: \.element.id) { index, clip in
                    cell(for: clip, position: index + 1)
                }
            }
            .padding(.trailing, 8)
            .coordinateSpace(name: Self.contentSpace)
            // The lifted clip is drawn here, above its neighbours, exactly under the finger; its
            // own HStack slot stays in the flow (invisible) so the gesture keeps its view.
            .overlay(alignment: .topLeading) { liftedCell }
        }
        .scrollPosition($scrollPosition)
        .scrollDisabled(model.draggingClipID != nil)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(offset: geometry.contentOffset.x, content: geometry.contentSize.width, viewport: geometry.containerSize.width)
        } action: { _, metrics in
            scrollOffsetX = metrics.offset
            scrollContentWidth = metrics.content
            scrollViewportWidth = metrics.viewport
        }
        .coordinateSpace(name: Self.viewportSpace)
        .frame(height: cellSize.height)
        // Horizontal clipping stays exact (scrolled-off cells never draw over the dock's leading
        // area); vertically the lifted cell's scale and shadow may use the dock's own padding.
        .scrollClipDisabled()
        .clipShape(VerticalOverflowRect(overflow: 11))
        .accessibilityIdentifier("clipThumbnailStrip")
        .onDisappear { if model.draggingClipID != nil { abandonDrag() } }
        #if DEBUG
        // Visual-evidence hook only: `-uiTestFreezeReorderDrag=<position>,<viewportX>` lifts the clip
        // at `position` and holds it at `viewportX` (no touch involved) so the mid-drag presentation
        // can be screenshotted deterministically. Never compiled into Release.
        .task { await freezeDragIfRequested() }
        #endif
    }

    #if DEBUG
    private func freezeDragIfRequested() async {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-uiTestFreezeReorderDrag=") }) else { return }
        let parts = argument.replacingOccurrences(of: "-uiTestFreezeReorderDrag=", with: "").split(separator: ",")
        guard parts.count == 2, let position = Int(parts[0]), let viewportX = Double(parts[1]) else { return }
        // Let the timeline measure its slots first.
        try? await Task.sleep(for: .milliseconds(400))
        guard model.orderedClips.indices.contains(position - 1) else { return }
        let clipID = model.orderedClips[position - 1].id
        activate(clipID)
        fingerMoved(toViewportX: (slotFrames[clipID]?.midX ?? 0) - scrollOffsetX)
        fingerMoved(toViewportX: viewportX)
    }
    #endif

    private struct ScrollMetrics: Equatable {
        var offset: CGFloat
        var content: CGFloat
        var viewport: CGFloat
    }

    // MARK: Cells

    private func cell(for clip: VlogClip, position: Int) -> some View {
        let isLifted = drag?.clipID == clip.id
        return ClipTimelineCell(
            clip: clip,
            position: position,
            total: model.orderedClips.count,
            thumbnail: model.thumbnail(for: clip.id),
            isSelected: clip.id == model.selectedClipID,
            select: { model.select(clip.id) },
            canMoveEarlier: model.canMoveEarlier(clip.id),
            canMoveLater: model.canMoveLater(clip.id),
            moveEarlier: { announce(model.moveClipEarlier(id: clip.id)) },
            moveLater: { announce(model.moveClipLater(id: clip.id)) }
        )
        .opacity(isLifted ? 0 : 1)
        .background {
            // Measures the layout slot (never the lifted copy): a sibling, so no transform leaks in.
            Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.contentSpace)) } action: { frame in
                slotFrames[clip.id] = frame
            }
        }
        // A UIKit recogniser coexists with the cell's tap and with a swipe that starts on a cell
        // (UIKit arbitration: it only wins once the press has been held still); after that the
        // scroll view is disabled and the drag alone owns the touch.
        .gesture(reorderGesture(for: clip))
    }

    @ViewBuilder
    private var liftedCell: some View {
        if let drag, let clip = model.orderedClips.first(where: { $0.id == drag.clipID }) {
            ClipTimelineCell(
                clip: clip,
                position: (model.dragTargetIndex ?? 0) + 1,
                total: model.orderedClips.count,
                thumbnail: model.thumbnail(for: clip.id),
                isSelected: true,
                select: {}, canMoveEarlier: false, canMoveLater: false, moveEarlier: {}, moveLater: {}
            )
            .scaleEffect(1 + (ClipReorderInteraction.liftedScale - 1) * drag.lift)
            .shadow(color: .black.opacity(0.45 * drag.lift), radius: 8 * drag.lift, y: 4 * drag.lift)
            // Position is written outside any animation while dragging (1:1 with the finger) and
            // inside the settle spring only on drop / cancel.
            .offset(x: drag.liftedMinX)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.identity)
        }
    }

    // MARK: Gesture

    /// Long press (activation, haptic, lift) that keeps tracking the finger (live insertion preview)
    /// until the touch lifts (drop commits) or the system cancels it (rollback). A plain tap never
    /// reaches this: the press must hold still for `longPressDuration` first, so selecting and
    /// scrolling are untouched. The native long-press recogniser is used because SwiftUI's
    /// `LongPressGesture` blocks the enclosing ScrollView's pan even when simultaneous.
    private func reorderGesture(for clip: VlogClip) -> some UIGestureRecognizerRepresentable {
        ClipReorderPressGesture(
            viewportSpace: Self.viewportSpace,
            began: { x in
                if model.draggingClipID != clip.id { activate(clip.id) }
                fingerMoved(toViewportX: x)
            },
            changed: { x in if model.draggingClipID == clip.id { fingerMoved(toViewportX: x) } },
            ended: { if model.draggingClipID == clip.id { finishDrag() } },
            cancelled: { if model.draggingClipID == clip.id { abandonDrag() } }
        )
    }

    private func activate(_ clipID: UUID) {
        guard model.beginReorder(clipID: clipID), let slot = slotFrames[clipID] else { return }
        // Snapshot the settled slot positions: they are the insertion thresholds for the whole drag.
        let settled = model.orderedClips.compactMap { slotFrames[$0.id] }.sorted { $0.minX < $1.minX }
        drag = DragSession(clipID: clipID, settledSlots: settled, grabOffset: nil, fingerViewportX: slot.midX - scrollOffsetX, liftedMinX: slot.minX)
        // Lift on the next turn so the copy is inserted at rest first and then animates up
        // (scale + shadow only). Under Reduce Motion the lifted state is simply shown.
        if reduceMotion {
            drag?.lift = 1
        } else {
            Task { @MainActor in
                withAnimation(ClipReorderInteraction.liftSpring) { if drag?.clipID == clipID { drag?.lift = 1 } }
            }
        }
    }

    private func fingerMoved(toViewportX x: CGFloat) {
        guard var session = drag else { return }
        session.fingerViewportX = x
        if session.grabOffset == nil {
            // Where inside the cell the finger landed; keeps the cell from jumping under the finger.
            session.grabOffset = (x + scrollOffsetX) - (slotFrames[session.clipID]?.minX ?? (x + scrollOffsetX))
        }
        drag = session
        repositionLiftedCell()
        updateAutoScroll()
    }

    /// Lifted position from the finger and the current scroll offset (kept inside the timeline's own
    /// extent, like an iOS home-screen icon), then the insertion preview.
    private func repositionLiftedCell() {
        guard var session = drag, let grabOffset = session.grabOffset else { return }
        let lastMinX = session.settledSlots.last.map { $0.maxX - cellSize.width } ?? 0
        let followedMinX = session.fingerViewportX + scrollOffsetX - grabOffset
        session.liftedMinX = min(max(followedMinX, 0), max(0, lastMinX))
        drag = session
        // The insertion target follows the finger itself, not the clamped visual, so dragging past
        // either end still reaches the first / last position.
        let centerX = followedMinX + cellSize.width / 2
        guard let current = model.dragTargetIndex else { return }
        // Insertion index = number of *other* settled slots whose midpoint the lifted centre has
        // passed. Slots are positions, not clips, so this is stable while neighbours animate.
        let target = session.settledSlots.enumerated().filter { $0.offset != current && $0.element.midX < centerX }.count
        guard target != current else { return }
        // Logical order updates immediately; only the neighbours' slide is animated, and a new
        // crossing retargets the spring in flight.
        withAnimation(reduceMotion ? nil : ClipReorderInteraction.reflowSpring) { model.previewReorder(toIndex: target) }
    }

    private func finishDrag() {
        stopAutoScroll()
        settle { model.commitReorder() }
    }

    private func abandonDrag() {
        stopAutoScroll()
        settle { model.cancelReorder() }
    }

    /// Ends the drag in the model (`resolve`: commit or cancel — synchronous, so the resulting
    /// committed order is known here) and lets the lifted copy settle onto the clip's final slot
    /// with a short, highly damped spring before the real cell takes over. A rollback (persistence
    /// failure) reflows the neighbours with the same spring. Under Reduce Motion the copy is
    /// dropped in place at once.
    private func settle(_ resolve: @escaping () -> Void) {
        guard let session = drag else { return resolve() }
        let finish = {
            resolve()
            let index = model.orderedClips.firstIndex { $0.id == session.clipID } ?? 0
            drag?.liftedMinX = session.settledSlots.indices.contains(index) ? session.settledSlots[index].minX : session.liftedMinX
            drag?.lift = 0
        }
        if reduceMotion {
            finish()
            drag = nil
            return
        }
        withAnimation(ClipReorderInteraction.settleSpring, finish) {
            // Only this session's copy is removed; a clip re-lifted meanwhile keeps its new session.
            if drag?.clipID == session.clipID, model.draggingClipID == nil { drag = nil }
        }
    }

    // MARK: Auto-scroll

    /// While the finger sits in the edge band, the timeline scrolls a few points per tick in that
    /// direction until it reaches its bounds or the finger leaves the band. Manual scrolling is not
    /// involved (the drag owns the touch), so nothing fights.
    private func updateAutoScroll() {
        guard let session = drag, scrollViewportWidth > 0 else { return stopAutoScroll() }
        let inset = ClipReorderInteraction.autoScrollEdgeInset
        let direction: CGFloat
        if session.fingerViewportX < inset { direction = -1 } else if session.fingerViewportX > scrollViewportWidth - inset { direction = 1 } else { return stopAutoScroll() }
        guard autoScrollTask == nil else { return }
        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled, drag != nil {
                let maxOffset = max(0, scrollContentWidth - scrollViewportWidth)
                let next = min(max(scrollOffsetX + direction * ClipReorderInteraction.autoScrollStep, 0), maxOffset)
                if next == scrollOffsetX { break }
                scrollPosition.scrollTo(x: next)
                scrollOffsetX = next
                repositionLiftedCell()
                try? await Task.sleep(for: ClipReorderInteraction.autoScrollInterval)
            }
            autoScrollTask = nil
        }
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    // MARK: Accessibility

    /// Brief VoiceOver confirmation of the new position after a Move action; nothing on refusal.
    private func announce(_ newPosition: Int?) {
        guard let newPosition else { return }
        AccessibilityNotification.Announcement("\(newPosition)번째 위치로 이동").post()
    }
}

/// `UILongPressGestureRecognizer` bridged into the SwiftUI gesture system: began after the press has
/// been held still for the activation threshold, changed while the finger moves, ended on lift,
/// cancelled on interruption. Locations are reported in the timeline viewport coordinate space.
private struct ClipReorderPressGesture: UIGestureRecognizerRepresentable {
    let viewportSpace: String
    let began: (CGFloat) -> Void
    let changed: (CGFloat) -> Void
    let ended: () -> Void
    let cancelled: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = ClipReorderInteraction.longPressDuration
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let x = context.converter.location(in: .named(viewportSpace)).x
        switch recognizer.state {
        case .began: began(x)
        case .changed: changed(x)
        case .ended: ended()
        case .cancelled, .failed: cancelled()
        default: break
        }
    }
}

/// The strip's bounds extended vertically only, so a lifted cell's scale / shadow are not clipped
/// while horizontal scrolling stays exactly clipped.
private struct VerticalOverflowRect: Shape {
    let overflow: CGFloat
    func path(in rect: CGRect) -> Path { Path(rect.insetBy(dx: 0, dy: -overflow)) }
}

private struct ClipTimelineCell: View {
    let clip: VlogClip
    let position: Int
    let total: Int
    let thumbnail: ClipThumbnailPresentation
    let isSelected: Bool
    let select: () -> Void
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let moveEarlier: () -> Void
    let moveLater: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
    private var size: CGSize { ProjectEditorModel.thumbnailPointSize }

    var body: some View {
        // The image-only tap target carries selection; the duration tag is a decorative overlay drawn
        // (not a text node) because the cell label already speaks the duration — it must never be
        // read twice, and a text node cut off at the dock's scroll edge cannot be audited. A tap
        // gesture rather than a Button: a Button child would out-prioritise the reorder recogniser
        // on the same cell, which then never activates.
        thumbnailBox
            .contentShape(shape)
            .onTapGesture(perform: select)
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
            // Non-drag reorder (ADR-034): only the actions that are valid at this position exist.
            .accessibilityActions {
                if canMoveEarlier { Button("앞으로 이동", action: moveEarlier) }
                if canMoveLater { Button("뒤로 이동", action: moveLater) }
            }
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
