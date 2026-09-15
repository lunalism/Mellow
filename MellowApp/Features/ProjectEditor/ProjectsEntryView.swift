import SwiftUI

/// Phase 5 Projects screen (ADR-034 semantics, ADR-035 destination, ADR-036 two-action content;
/// final visual baseline per DESIGN.md): a dedicated pushed `프로젝트` screen holding one centered
/// group — small visual, state headline, supporting copy, compact primary `새 프로젝트 시작`, quiet
/// secondary `기존 프로젝트 불러오기` (enabled only while a saved Project exists, opening it directly
/// in the Editor). V1 keeps at most one editable saved Project, so there is no list, card or metadata.
///
/// STEP 5 transitional note: this screen is reached only through DEBUG/UI-test routing
/// (`.projectsEntry`). Production Camera `Projects` still opens the existing Recent Projects browser
/// until the new-project path has a real composition destination, so `새 프로젝트 시작` never becomes
/// a user-visible dead end.
struct ProjectsEntryView: View {
    @Bindable var model: ProjectsEntryModel
    /// Optional representative image for the saved-Project state. Nothing supplies one yet (the
    /// Thumbnail slice will: canonical representative Project thumbnail → first usable clip thumbnail
    /// → placeholder); until then the screen deterministically shows the neutral placeholder.
    var representativeImage: UIImage? = nil

    private var content: ProjectsEntryContent {
        .resolve(hasSavedProject: model.hasSavedProject, representativeImage: representativeImage)
    }

    var body: some View {
        // Geometry-aware centering (same pattern as Permission Onboarding): the group takes the
        // available height below the navigation bar as a minimum and is centered inside it; if
        // Dynamic Type makes it taller, the minimum stops binding and the ScrollView simply scrolls.
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    ProjectsEntryVisualView(visual: content.visual)
                        .padding(.bottom, 24)
                    Text(content.headline)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("projectsEntryHeadline")
                        .padding(.bottom, 8)
                    // Supporting copy keeps `.label` (Mellow's secondary-text convention) so it
                    // clears the contrast audit at subheadline size; hierarchy comes from size.
                    Text(content.supporting)
                        .font(.subheadline)
                        .foregroundStyle(MellowDesignSystem.secondaryText)
                        .accessibilityIdentifier("projectsEntrySupporting")
                        .padding(.bottom, 28)
                    ProjectsPrimaryButton("새 프로젝트 시작", action: model.requestNewProject)
                        .accessibilityHint(model.hasSavedProject
                            ? "마지막으로 저장한 프로젝트를 교체하기 전에 확인을 요청합니다"
                            : "새 프로젝트를 시작합니다")
                        .accessibilityIdentifier("startNewProject")
                        .padding(.bottom, 6)
                    ProjectsSecondaryButton("기존 프로젝트 불러오기", action: model.continueEditing)
                        .disabled(!model.hasSavedProject)
                        .accessibilityHint(model.hasSavedProject ? "저장된 프로젝트를 편집기에서 엽니다" : "")
                        .accessibilityIdentifier("loadExistingProject")
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("프로젝트")
        .navigationBarTitleDisplayMode(.inline)
        // `.contain` keeps the content individually queryable under the screen identifier while
        // leaving the native navigation bar (Back) outside the group.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectsEntry")
        .alert("새 프로젝트를 시작할까요?", isPresented: $model.isReplacementConfirmationPresented) {
            Button("취소", role: .cancel, action: model.cancelReplacement)
            Button("새 프로젝트 만들기", role: .destructive, action: model.confirmReplacement)
        } message: {
            Text("새 프로젝트를 만들면 마지막으로 저장한 프로젝트가 교체됩니다.")
        }
        .onAppear(perform: model.load)
    }
}

/// Presentation state of the Projects screen: which top visual and which copy the two states show.
/// Pure and deterministic — no media policy lives here. The visual never claims an image exists
/// when none was supplied, and the no-Project state ignores any supplied image.
struct ProjectsEntryContent: Equatable {
    enum Visual: Equatable {
        case placeholder
        case image(UIImage)
    }

    let visual: Visual
    let headline: String
    let supporting: String

    static func resolve(hasSavedProject: Bool, representativeImage: UIImage?) -> ProjectsEntryContent {
        guard hasSavedProject else {
            return ProjectsEntryContent(
                visual: .placeholder,
                headline: "아직 프로젝트가 없어요",
                supporting: "촬영한 순간들을 골라\n첫 번째 Vlog를 만들어보세요."
            )
        }
        return ProjectsEntryContent(
            visual: representativeImage.map(Visual.image) ?? .placeholder,
            headline: "이어서 만들래요?",
            supporting: "마지막으로 저장한 프로젝트가 있어요."
        )
    }
}

/// Small centered rounded-square visual anchor (80pt): a neutral placeholder with a film symbol, or
/// the supplied representative image aspect-filled and clipped. Display-only and not tappable. It is
/// wrapped in a `.contain` group so tests can find the slot by identifier while VoiceOver skips it —
/// the headline and supporting copy carry the meaning.
private struct ProjectsEntryVisualView: View {
    let visual: ProjectsEntryContent.Visual
    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        ZStack { artwork.accessibilityHidden(true) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(visual == .placeholder ? "projectsEntryVisual-placeholder" : "projectsEntryVisual-image")
    }

    @ViewBuilder private var artwork: some View {
        Group {
            switch visual {
            case .placeholder:
                shape
                    .fill(Color(.tertiarySystemFill))
                    .overlay {
                        Image(systemName: "film")
                            .font(.title2)
                            .foregroundStyle(MellowDesignSystem.secondaryText)
                    }
            case .image(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(shape)
    }
}

/// Compact primary action: `plus` + label, rounded rectangle (radius 16), ~52pt, ~260pt wide, on the
/// Mellow Signature Gradient (identical in Light and Dark — the brand anchor across appearances)
/// with the design system's near-black signature foreground for accessible contrast on every stop.
private struct ProjectsPrimaryButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.subheadline.weight(.semibold)).accessibilityHidden(true)
                Text(title).font(.headline)
            }
            .foregroundStyle(MellowDesignSystem.signatureForeground)
            .padding(.horizontal, 24)
            .frame(width: 260)
            .frame(minHeight: 52)
            .background(MellowDesignSystem.signatureGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(ProjectsPressableStyle())
        .accessibilityLabel(title)
    }
}

/// Quiet borderless text action with a 44pt target. Disabled keeps the same place and reads as
/// unavailable (reduced emphasis; the button trait reports "사용할 수 없음") without dropping below
/// the contrast audit — a custom style so the system styles' extra disabled dimming does not apply.
private struct ProjectsSecondaryButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.primary : Color.primary.opacity(0.65))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(ProjectsPressableStyle())
    }
}

/// Neutral pressed feedback only; never dims disabled labels (contrast stays under our control).
private struct ProjectsPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
