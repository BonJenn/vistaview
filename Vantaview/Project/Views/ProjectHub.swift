import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ProjectHub: View {
    @StateObject private var recentProjectsManager = RecentProjectsManager()
    @StateObject private var projectManager = ProjectHubState()
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var projectCoordinator: ProjectCoordinator
    
    @State private var selectedTemplate: ProjectTemplate = .blank
    @State private var newProjectTitle: String = ""
    @State private var showingNewProjectSheet = false
    @State private var showingOpenPanel = false
    @State private var searchText = ""
    @State private var sortBy: SortOption = .dateModified
    @State private var viewMode: ViewMode = .grid
    
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case dateModified = "Date Modified"
        case dateCreated = "Date Created"
        
        var systemImage: String {
            switch self {
            case .name: return "textformat.abc"
            case .dateModified: return "clock.fill"
            case .dateCreated: return "calendar.badge.plus"
            }
        }
    }
    
    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
        
        var systemImage: String {
            switch self {
            case .grid: return "rectangle.grid.3x2"
            case .list: return "list.bullet"
            }
        }
    }
    
    var filteredRecentProjects: [RecentProject] {
        let filtered = recentProjectsManager.recentProjects.filter { project in
            searchText.isEmpty || project.title.localizedCaseInsensitiveContains(searchText)
        }
        
        switch sortBy {
        case .name:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dateModified:
            return filtered.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        case .dateCreated:
            return filtered.sorted { $0.lastOpenedAt > $1.lastOpenedAt } // Placeholder - would need creation date in model
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 20) {
                // User section
                if authManager.isAuthenticated {
                    UserSection()
                }
                
                // Quick actions
                QuickActionsSection(
                    showingNewProjectSheet: $showingNewProjectSheet,
                    showingOpenPanel: $showingOpenPanel
                )
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 200)
            .background(Color(NSColor.controlBackgroundColor))
            
        } detail: {
            // Main content
            VStack(spacing: 0) {
                // Header
                ProjectHubHeader(
                    searchText: $searchText,
                    sortBy: $sortBy,
                    viewMode: $viewMode
                )
                
                Divider()
                
                // Content
                ScrollView {
                    VStack(spacing: 32) {
                        // Recent projects
                        if !filteredRecentProjects.isEmpty {
                            ProjectSection(
                                title: "Recent Projects",
                                projects: filteredRecentProjects,
                                viewMode: viewMode,
                                onOpenProject: openProject,
                                onDuplicateProject: duplicateProject,
                                onDeleteProject: deleteProject
                            )
                        }
                        
                        // Templates section
                        TemplatesSection(
                            selectedTemplate: $selectedTemplate,
                            onCreateFromTemplate: { template in
                                selectedTemplate = template
                                newProjectTitle = template.displayName
                                showingNewProjectSheet = true
                            }
                        )
                        
                        // Cloud projects placeholder
                        if authManager.isAuthenticated {
                            CloudProjectsSection()
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectSheet(
                title: $newProjectTitle,
                selectedTemplate: $selectedTemplate,
                recentProjectsManager: recentProjectsManager,
                projectCoordinator: projectCoordinator,
                onProjectCreated: { projectState in
                    // Add to recent projects
                    Task {
                        if let projectURL = await projectState.projectURL {
                            let recentProject = RecentProject(
                                projectId: await projectState.manifest.projectId,
                                title: await projectState.manifest.title,
                                projectURL: projectURL
                            )
                            await MainActor.run {
                                recentProjectsManager.addRecentProject(recentProject)
                            }
                        }
                    }
                }
            )
        }
        .fileImporter(
            isPresented: $showingOpenPanel,
            allowedContentTypes: [UTType("com.vantaview.project")].compactMap { $0 },
            onCompletion: handleOpenResult
        )
        .task {
            await projectManager.loadProjects()
        }
    }
    
    private func openProject(_ project: RecentProject) {
        Task {
            do {
                try await projectCoordinator.openProject(at: project.projectURL)
                
                // Update recent projects
                recentProjectsManager.addRecentProject(
                    RecentProject(
                        projectId: project.projectId,
                        title: project.title,
                        projectURL: project.projectURL
                    )
                )
                
            } catch {
                // Show error
                print("Failed to open project: \(error)")
            }
        }
    }
    
    private func duplicateProject(_ project: RecentProject) {
        Task {
            do {
                // Show save panel for new location
                let savePanel = NSSavePanel()
                savePanel.title = "Duplicate Project"
                savePanel.prompt = "Duplicate"
                savePanel.allowedContentTypes = [UTType("com.vantaview.project")].compactMap { $0 }
                savePanel.nameFieldStringValue = "\(project.title) Copy"
                
                if savePanel.runModal() == .OK, let url = savePanel.url {
                    let directory = url.deletingLastPathComponent()
                    let title = url.deletingPathExtension().lastPathComponent
                    
                    try await projectCoordinator.duplicateCurrentProject(
                        newTitle: title,
                        at: directory
                    )
                }
                
            } catch {
                print("Failed to duplicate project: \(error)")
            }
        }
    }
    
    private func deleteProject(_ project: RecentProject) {
        Task {
            do {
                let projectManager = ProjectManager()
                try await projectManager.deleteProject(at: project.projectURL)
                
                // Remove from recent projects
                recentProjectsManager.removeRecentProject(project.projectId)
                
            } catch {
                print("Failed to delete project: \(error)")
            }
        }
    }
    
    private func handleOpenResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                do {
                    try await projectCoordinator.openProject(at: url)
                } catch {
                    print("Failed to open project: \(error)")
                }
            }
        case .failure(let error):
            print("File selection failed: \(error)")
        }
    }
}

// MARK: - User Section

struct UserSection: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                
                Text("Signed In")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            if let email = authManager.currentUser?.email {
                Text(email)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Quick Actions Section

struct QuickActionsSection: View {
    @Binding var showingNewProjectSheet: Bool
    @Binding var showingOpenPanel: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.semibold)
            
            Button(action: { showingNewProjectSheet = true }) {
                Label("New Project", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SidebarButtonStyle())
            
            Button(action: { showingOpenPanel = true }) {
                Label("Open Project...", systemImage: "folder.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SidebarButtonStyle())
            
            Divider()
                .padding(.vertical, 4)
            
            Button(action: {}) {
                Label("Import Media", systemImage: "square.and.arrow.down.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SidebarButtonStyle())
            
            Button(action: {}) {
                Label("Browse Templates", systemImage: "rectangle.3.group.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SidebarButtonStyle())
        }
    }
}

struct SidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .foregroundColor(configuration.isPressed ? .accentColor : .primary)
    }
}

// MARK: - Header

struct ProjectHubHeader: View {
    @Binding var searchText: String
    @Binding var sortBy: ProjectHub.SortOption
    @Binding var viewMode: ProjectHub.ViewMode
    
    var body: some View {
        HStack(spacing: 16) {
            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Vantaview Projects")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Create, manage, and organize your video projects")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Search and controls
            HStack(spacing: 12) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search projects...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .frame(width: 250)
                
                // Sort menu
                Menu {
                    Picker("Sort by", selection: $sortBy) {
                        ForEach(ProjectHub.SortOption.allCases, id: \.self) { option in
                            Label(option.rawValue, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .foregroundColor(.secondary)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                
                // View mode
                Picker("View mode", selection: $viewMode) {
                    ForEach(ProjectHub.ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
        .padding()
    }
}

// MARK: - Supporting Types

@MainActor
final class ProjectHubState: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    
    func loadProjects() async {
        isLoading = true
        defer { isLoading = false }
        
        // Load projects logic here
    }
}