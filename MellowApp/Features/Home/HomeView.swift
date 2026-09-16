import SwiftUI

struct HomeView: View {
    @Bindable var model: HomeModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var recentProjects: some View {
        ScrollView {
            if model.loadFailed {
                Text("Recent couldn’t be loaded.")
                Button("Try Again", action: model.loadRecent).frame(minHeight: 44)
            } else if model.projects.isEmpty {
                Text("No projects yet.").padding().accessibilityIdentifier("emptyRecent")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 24) {
                ForEach(model.projects) { project in
                    RecentProjectRow(project: project) {
                        model.openProject(id: project.id)
                    } delete: {
                        model.pendingDeletion = project
                    }
                }
            }
            .padding()
        }
        .background(MellowDesignSystem.brandBackground.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("Recent Projects")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Camera `Projects` → canonical `프로젝트` screen. The transitional Recent browser is reachable
    /// only through the DEBUG `-uiTestLegacyRecentProjects` argument (historical regressions).
    private var showProjects: () -> Void {
        #if DEBUG
        if environment.usesLegacyRecentProjects { return model.showRecent }
        #endif
        return model.showProjects
    }

    var body: some View {
        @Bindable var router = model.router
        NavigationStack(path: $router.path) {
            Group {
                if environment.shouldShowPermissionOnboarding, let onboarding = environment.permissionOnboarding {
                    PermissionOnboardingView(model: onboarding)
                } else {
                    // V1 root: a new Portrait capture surface that persists no project on launch. Its
                    // `Projects` control enters the canonical `프로젝트` screen (ADR-035/036).
                    CameraDestination(context: .newCapture, showProjects: showProjects)
                }
            }
            .navigationDestination(for: AppRouter.Route.self) { route in
                switch route {
                case .recent:
                    recentProjects
                case .camera(let id):
                    if let project = model.openedProject, project.id == id {
                        CameraDestination(context: .project(project)).id(project.id)
                    }
                case .projectsEntry:
                    // ADR-035 dedicated `프로젝트` screen with the production composition stack.
                    // DEBUG harnesses substitute their own model (deterministic fake selection, or the
                    // real-media physical-review route); production is unaffected by either.
                    #if DEBUG
                    if let entry = environment.uiTestProjectsEntry {
                        ProjectsEntryView(model: entry, photosSelector: environment.uiTestRealMediaSelector)
                    } else {
                        ProjectsEntryView(model: environment.projectsEntry, photosSelector: environment.photosVideoSelector)
                    }
                    #else
                    ProjectsEntryView(model: environment.projectsEntry, photosSelector: environment.photosVideoSelector)
                    #endif
                case .projectEditor(let id):
                    ProjectEditorDestination(projectID: id).id(id)
                }
            }
        }
        .tint(.primary)
        #if DEBUG
        // Phase 5 STEP 5: the DEBUG Projects Entry harness surfaces the delivered intent so UI tests
        // can observe it deterministically without any Project being created or replaced.
        .overlay(alignment: .top) {
            if let intent = environment.uiTestProjectsEntryIntent {
                Text(intent)
                    .font(.caption)
                    .padding(6)
                    .background(Color(.systemBackground))
                    .accessibilityIdentifier("projectsEntryIntent")
            }
        }
        // Phase 5 STEP 12A: cumulative cleanup counters (`-uiTestCleanupDiagnostics`) so UI tests can
        // observe that a deferred pass completed; cleanup has no production surface by design.
        .overlay(alignment: .bottom) {
            if let summary = environment.uiTestCleanupSummary {
                VStack(spacing: 2) {
                    Text(summary)
                        .accessibilityIdentifier("cleanupDiagnostics")
                    if let recovery = environment.uiTestRecoverySummary {
                        Text(recovery)
                            .accessibilityIdentifier("recoveryDiagnostics")
                    }
                }
                .font(.caption2)
                .padding(4)
                .background(Color(.systemBackground))
                .allowsHitTesting(false)
            }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.loadRecent() }
        }
        .onAppear {
            model.loadRecent()
            if !environment.shouldShowPermissionOnboarding {
                environment.prewarmCameraIfNeeded()
            }
        }
        .onChange(of: environment.shouldShowPermissionOnboarding) { _, shouldShow in
            if !shouldShow {
                environment.prewarmCameraIfNeeded()
            }
        }
        .alert("Delete vlog?", isPresented: Binding(
            get: { model.pendingDeletion != nil },
            set: { if !$0 { model.pendingDeletion = nil } }
        ), presenting: model.pendingDeletion) { _ in
            Button("Delete", role: .destructive, action: model.confirmDeletion)
            Button("Cancel", role: .cancel) { model.pendingDeletion = nil }
        } message: { project in
            Text("Delete \(project.displayName())? This can’t be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.failure != nil },
            set: { if !$0 { model.failure = nil } }
        ), presenting: model.failure) { failure in
            Button("OK", role: .cancel) { model.failure = nil }
        } message: { failure in
            Text(failure.message)
        }
    }
}

/// One progressive-reveal onboarding screen (ADR-033): Camera, then Microphone, then Photos, each
/// granted individually; Start Mellow appears once all three are decided. The Mellow screen never
/// navigates — only the iOS system sheet appears per row action.
struct PermissionOnboardingView: View {
    @Bindable var model: PermissionOnboardingModel
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize = 56

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 8)
                    Image("MellowSplashLogo")
                        .resizable().scaledToFit()
                        .frame(width: logoSize, height: logoSize)
                        .accessibilityHidden(true)
                    VStack(spacing: 6) {
                        Text("Before you start")
                            .font(.title2.weight(.semibold))
                            .accessibilityIdentifier("permissionOnboardingTitle")
                        Text("A few permissions help Mellow capture and save moments.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 10) {
                        row(.camera)
                        if model.showsMicrophoneRow { row(.microphone).transition(reveal) }
                        if model.showsPhotosRow { row(.photos).transition(reveal) }
                    }
                    .animation(revealAnimation, value: model.showsMicrophoneRow)
                    .animation(revealAnimation, value: model.showsPhotosRow)

                    if model.showsStart {
                        Button { model.start() } label: {
                            Text("Start Mellow")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.primary)
                        .accessibilityIdentifier("startMellow")
                        .transition(reveal)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 24)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .animation(revealAnimation, value: model.showsStart)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var revealAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22)
    }
    /// Calm reveal: fade with a small rise. Reduce Motion drops the offset to opacity-only.
    private var reveal: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 7))
    }

    @ViewBuilder private func row(_ kind: OnboardingPermissionRow.Kind) -> some View {
        OnboardingPermissionRow(kind: kind, model: model) { action in
            switch action {
            case .requestCamera: Task { await model.requestCamera() }
            case .requestMicrophone: Task { await model.requestMicrophone() }
            case .requestPhotos: Task { await model.requestPhotos() }
            case .openSettings:
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }
}

/// A compact permission row: icon, title + one-line purpose + Required/Optional, and a small
/// trailing action that reflects the authorization state.
private struct OnboardingPermissionRow: View {
    enum Kind { case camera, microphone, photos }
    enum Action { case requestCamera, requestMicrophone, requestPhotos, openSettings }

    let kind: Kind
    @Bindable var model: PermissionOnboardingModel
    let perform: (Action) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            // The text column (title / purpose / requirement) alone defines the card's height. The
            // trailing status sits in a top-trailing overlay, top-aligned with the title so it reads
            // as part of the title row, but OUT of the layout flow — so swapping the tall Allow button
            // for the short Allowed label (or Settings / Muted / Unavailable) can never change the
            // card's geometry. `titleTrailingInset` keeps the title clear of the status.
            VStack(alignment: .leading, spacing: 1) {
                if dynamicTypeSize.isAccessibilitySize {
                    // At accessibility sizes the status flows in the title row and is free to wrap;
                    // the row grows naturally and the control stays near the top, on screen.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title).font(.body.weight(.semibold))
                        Spacer(minLength: 8)
                        trailing
                    }
                } else {
                    // At standard sizes the title reserves trailing space and the status is placed by
                    // the overlay below, out of the layout flow.
                    Text(title).font(.body.weight(.semibold))
                        .padding(.trailing, titleTrailingInset)
                }
                Text(purpose).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(requirement).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                // Standard sizes only: the status floats on the title row so exchanging the tall Allow
                // button for the short Allowed label can never change the card height.
                if !dynamicTypeSize.isAccessibilitySize {
                    trailing
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permissionRow-\(identifier)")
    }

    /// Space reserved on the title so it never runs beneath the trailing status overlay. Released at
    /// accessibility sizes where the status wraps under its own layout rules.
    private var titleTrailingInset: CGFloat { dynamicTypeSize.isAccessibilitySize ? 0 : 96 }

    @ViewBuilder private var trailing: some View {
        let inFlight = model.requesting == requestingRow
        switch status {
        case .authorized:
            // Green stays a semantic confirmation accent on the checkmark only; the word uses
            // `.primary` so it carries no extra colour weight and always meets text contrast.
            Label {
                Text("Allowed").foregroundStyle(.primary)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("permissionState-\(identifier)")
        case .notDetermined:
            Button("Allow") { perform(allowAction) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(inFlight)
                .accessibilityIdentifier("permissionAllow-\(identifier)")
        case .denied:
            Button(kind == .microphone ? "Muted" : "Settings") { perform(.openSettings) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("permissionSettings-\(identifier)")
        case .restricted:
            Text(kind == .microphone ? "Muted" : "Unavailable")
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
                .accessibilityIdentifier("permissionState-\(identifier)")
        }
    }

    private enum Status { case notDetermined, authorized, denied, restricted }
    private var status: Status {
        switch kind {
        case .camera:
            switch model.camera {
            case .notDetermined: return .notDetermined
            case .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            }
        case .microphone:
            switch model.microphone {
            case .notDetermined: return .notDetermined
            case .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            }
        case .photos:
            switch model.photos {
            case .notDetermined: return .notDetermined
            case .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            }
        }
    }
    private var requestingRow: PermissionOnboardingModel.Row {
        switch kind { case .camera: return .camera; case .microphone: return .microphone; case .photos: return .photos }
    }
    private var allowAction: Action {
        switch kind { case .camera: return .requestCamera; case .microphone: return .requestMicrophone; case .photos: return .requestPhotos }
    }
    private var icon: String {
        switch kind {
        case .camera: return "camera"
        case .microphone: return status == .authorized ? "mic" : "mic.slash"
        case .photos: return "photo.on.rectangle"
        }
    }
    private var title: String {
        switch kind { case .camera: return "Camera"; case .microphone: return "Microphone"; case .photos: return "Photos" }
    }
    private var purpose: String {
        switch kind {
        case .camera: return "Capture your moments"
        case .microphone: return "Add sound to your clips"
        case .photos: return "Save your clips"
        }
    }
    private var requirement: String {
        switch kind { case .camera: return "Required"; case .microphone: return "Optional"; case .photos: return "Required" }
    }
    private var identifier: String {
        switch kind { case .camera: return "camera"; case .microphone: return "microphone"; case .photos: return "photos" }
    }
}
