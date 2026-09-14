import SwiftUI

/// Compact horizontal snap picker: a clipped three-slot window over the five durations with the
/// selected value always centred. Drag snaps one step per gesture, side taps select and recentre,
/// and VoiceOver treats the whole control as one adjustable element. UI state only — Phase 3
/// records nothing, so changing the value never touches the camera service.
struct CameraDurationSelector: View {
    @Binding var selected: CameraDuration
    @GestureState private var dragTranslation: CGFloat = 0
    /// 40pt pitch keeps the row tight; the whole picker is the ≥44pt accessibility target and
    /// side taps map to non-overlapping full-slot regions.
    private let slotWidth: CGFloat = 40
    /// ~4.6 slots: neighbours fully visible, the outer values sit just inside the faded edges.
    private let visibleWidth: CGFloat = 184
    private let circleDiameter: CGFloat = 28
    private var selectedIndex: Int { CameraDuration.allCases.firstIndex(of: selected) ?? 0 }
    /// Leading edge of the strip so the selected slot is centred in the window.
    private var settledOffset: CGFloat { visibleWidth / 2 - slotWidth / 2 - slotWidth * CGFloat(selectedIndex) }
    /// Distance-based emphasis: selected 100%, neighbours 70%, outer values 50%. 50% is the
    /// lowest weight that keeps 15pt white text above the 4.5:1 contrast the accessibility audit
    /// enforces over the black fallback; anything dimmer fails the audit.
    private func emphasis(for duration: CameraDuration) -> Double {
        let distance = abs((CameraDuration.allCases.firstIndex(of: duration) ?? 0) - selectedIndex)
        switch distance {
        case 0: return 1
        case 1: return 0.7
        default: return 0.5
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CameraDuration.allCases, id: \.rawValue) { duration in
                let isSelected = duration == selected
                Text("\(duration.rawValue)s")
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.black : Color.white)
                    .frame(width: circleDiameter, height: circleDiameter)
                    .background(Circle().fill(Color.white.opacity(isSelected ? 1 : 0)))
                    .opacity(emphasis(for: duration))
                    .frame(width: slotWidth, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { select(duration) }
            }
        }
        .offset(x: settledOffset + dragTranslation)
        .frame(width: visibleWidth, height: 44, alignment: .leading)
        .clipped()
        // Understated edge fade: the peeking outer values soften toward the edges so the row
        // reads as continuing horizontally, without any instruction text or track.
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.035),
                        .init(color: .black, location: 0.965), .init(color: .clear, location: 1)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .updating($dragTranslation) { value, state, _ in state = value.translation.width }
                .onEnded { value in
                    // One discrete step per gesture: a quarter-slot pull is enough to commit.
                    let pull = -value.translation.width / slotWidth
                    if abs(pull) >= 0.25 { select(selected.advanced(by: pull > 0 ? 1 : -1)) }
                }
        )
        .animation(.snappy(duration: 0.22), value: selected)
        // Modest Dynamic Type only: numeric camera parameters must not wrap or break the row.
        .dynamicTypeSize(.small ... .xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Duration")
        .accessibilityValue(selected.accessibilityValueText)
        .accessibilityHint("Maximum clip length. Swipe up or down to adjust.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(selected.advanced(by: 1))
            case .decrement: select(selected.advanced(by: -1))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("durationPicker")
    }

    private func select(_ duration: CameraDuration) {
        guard duration != selected else { return }
        selected = duration
    }
}

/// Glyph-only flip: legible over arbitrary preview content through a soft shadow rather than a
/// dark disc, with an invisible 44pt hit region.
struct CameraFlipButton: View {
    let enabled: Bool
    let position: CameraPosition
    let flip: () -> Void
    var body: some View {
        Button(action: flip) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.45))
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel("Switch camera")
        .accessibilityValue(position == .front ? "Front camera" : "Rear camera")
        .accessibilityHint("Switches between front and rear camera")
        .accessibilityIdentifier("cameraSwitch")
    }
}

/// Camera-style capture affordance: thin outer ring, a small gap, then a solid inner disc.
/// While recording the ring becomes the progress surface (elapsed / selected maximum) in the
/// approved warm gradient; geometry is unchanged from the Phase 3 baseline.
struct CameraShutter: View {
    let enabled: Bool
    var isRecording = false
    /// Actual written media time / selected maximum, sampled from the capture pipeline.
    var progress: Double = 0
    var action: () -> Void = {}
    private let outerDiameter: CGFloat = 67
    private let ringWidth: CGFloat = 3.5
    private let innerDiameter: CGFloat = 55

    static let progressGradient = AngularGradient(
        colors: [
            Color(red: 1, green: 0.843, blue: 0.780),   // #FFD7C7
            Color(red: 1, green: 0.722, blue: 0.612),   // #FFB89C
            Color(red: 1, green: 0.541, blue: 0.396),   // #FF8A65
            Color(red: 1, green: 0.478, blue: 0.271),   // #FF7A45
            Color(red: 1, green: 0.369, blue: 0.227)    // #FF5E3A
        ],
        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
    )

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(isRecording ? 0.22 : (enabled ? 0.95 : 0.4)), lineWidth: ringWidth)
                    .frame(width: outerDiameter, height: outerDiameter)
                if isRecording {
                    Circle()
                        .trim(from: 0, to: max(0.002, min(1, progress)))
                        .stroke(Self.progressGradient, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: outerDiameter - ringWidth, height: outerDiameter - ringWidth)
                        .accessibilityHidden(true)
                }
                Circle()
                    .fill(Color.white.opacity(enabled || isRecording ? 1 : 0.28))
                    .frame(width: innerDiameter, height: innerDiameter)
                if !enabled && !isRecording {
                    Image(systemName: "slash.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.45))
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityIdentifier("cameraShutter")
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
        .accessibilityValue(isRecording ? "\(Int((progress * 100).rounded())) percent" : "")
        .accessibilityHint(isRecording ? "Stops the clip; clips shorter than one second are discarded" : "Records a clip up to the selected duration")
    }
}

/// Quiet muted-microphone state in the upper-leading chrome. Shown only when audio is not
/// available; tapping follows the authorization state and never blocks video recording.
struct CameraMicrophoneControl: View {
    let authorization: MicrophoneAuthorization
    let enabled: Bool
    let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            Image(systemName: "mic.slash")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.5))
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel("Microphone off")
        .accessibilityValue(value)
        .accessibilityHint(hint)
        .accessibilityIdentifier("microphoneMuted")
    }
    private var value: String {
        switch authorization {
        case .notDetermined: return "Not yet allowed"
        case .denied: return "Not allowed"
        case .restricted: return "Unavailable"
        case .authorized: return "On"
        }
    }
    private var hint: String {
        switch authorization {
        case .notDetermined: return "Allows the microphone so clips include sound"
        case .denied: return "Opens Settings to allow the microphone"
        case .restricted: return "Clips are recorded without sound"
        case .authorized: return ""
        }
    }
}

/// Portrait thumbnail-shaped slot. Empty today; a real 9:16 clip thumbnail can replace the
/// placeholder later without changing this geometry.
struct CameraContentSlot: View {
    let clipCount: Int
    @ScaledMetric(relativeTo: .caption) private var width = 38.0
    @ScaledMetric(relativeTo: .caption) private var height = 64.0
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .overlay {
                if clipCount > 0 {
                    Text("\(clipCount)")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(width: width, height: height)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            // No functional Clip Review destination exists until Phase 5.
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("projectContent")
            .accessibilityLabel(clipCount == 0 ? "Project content, empty" : "Project content, \(clipCount) clips")
            .accessibilityHint("Clip review is not available yet")
    }
}

/// Quiet secondary access to the dedicated Recent Projects browser from the Camera surface:
/// a small glyph with a 44pt hit region and no persistent background.
struct CameraProjectsButton: View {
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Projects")
        .accessibilityHint("Opens your saved vlogs")
        .accessibilityIdentifier("projects")
    }
}
