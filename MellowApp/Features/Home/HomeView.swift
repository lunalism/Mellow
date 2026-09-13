import SwiftUI

struct HomeView: View {
    @Bindable var model: HomeModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isContinuingOnboarding = false

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

    var body: some View {
        @Bindable var router = model.router
        NavigationStack(path: $router.path) {
            Group {
                if environment.shouldShowPermissionOnboarding {
                    PermissionOnboardingView(isWorking: isContinuingOnboarding) {
                        guard !isContinuingOnboarding else { return }
                        isContinuingOnboarding = true
                        await environment.completePermissionOnboarding()
                        isContinuingOnboarding = false
                    }
                } else {
                    // V1 root: a new Portrait capture surface that persists no project on launch.
                    CameraDestination(context: .newCapture, showProjects: model.showRecent)
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
                }
            }
        }
        .tint(.primary)
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

struct PermissionOnboardingView: View {
    let isWorking: Bool
    let continueAction: () async -> Void

    @ScaledMetric(relativeTo: .title) private var titleSize = 32.0

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 0)
                    Text("Before you start")
                        .font(.system(size: titleSize, weight: .semibold, design: .default))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("permissionOnboardingTitle")
                    Text("Mellow needs your permission to record clips on this device.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 14) {
                        OnboardingPermissionRow(
                            title: "Camera",
                            subtitle: "Required for capturing moments",
                            required: true
                        )
                        OnboardingPermissionRow(
                            title: "Microphone",
                            subtitle: "Used for video sound",
                            required: false
                        )
                        OnboardingPermissionRow(
                            title: "Photos",
                            subtitle: "Used when adding existing videos",
                            required: false
                        )
                        OnboardingPermissionRow(
                            title: "Location",
                            subtitle: "Optional metadata",
                            required: false
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)

                    Button {
                        Task { await continueAction() }
                    } label: {
                        if isWorking {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        } else {
                            Text("Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
                    .disabled(isWorking)
                    .accessibilityIdentifier("permissionOnboardingContinue")

                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(MellowDesignSystem.brandBackground.ignoresSafeArea())
    }
}

private struct OnboardingPermissionRow: View {
    let title: String
    let subtitle: String
    let required: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                if required {
                    Text("Required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
