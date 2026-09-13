import SwiftUI

struct HomeView: View {
    @Bindable var model: HomeModel
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

    var body: some View {
        @Bindable var router = model.router
        NavigationStack(path: $router.path) {
            OrientationSelectionView(select: model.createProject) {
                if model.loadFailed {
                    Text("Recent couldn’t be loaded.")
                    Button("Try Again", action: model.loadRecent).frame(minHeight: 44)
                } else if !model.projects.isEmpty {
                    Button("Continue an existing project?", action: model.showRecent)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("continueProject")
                }
            }
            .onAppear(perform: model.loadRecent)
            .navigationDestination(for: AppRouter.Route.self) { route in
                switch route {
                case .recent:
                    recentProjects
                case .camera(let id):
                    if let project = model.openedProject, project.id == id {
                        CameraPlaceholderView(project: project)
                    }
                }
            }
        }
        .tint(.primary)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.loadRecent() }
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
        .alert(item: $model.failure) { failure in
            Alert(title: Text("Something went wrong"), message: Text(failure.message), dismissButton: .default(Text("OK")))
        }
    }
}
