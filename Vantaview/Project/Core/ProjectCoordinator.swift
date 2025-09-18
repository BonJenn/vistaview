import SwiftUI
import os

@MainActor
final class ProjectCoordinator: ObservableObject {
    @Published var currentProjectState: ProjectState?
    @Published var showingProjectHub = false
    @Published var isLoadingProject = false
    @Published var projectError: Error?
    
    private let logger = Logger(subsystem: "app.vantaview.project", category: "ProjectCoordinator")
    
    var hasOpenProject: Bool {
        currentProjectState != nil
    }
    
    // MARK: - Simple Operations
    
    func handleAppLaunch() {
        // For now, just don't show project hub to avoid crashes
        showingProjectHub = false
    }
    
    func openProject(_ projectState: ProjectState) async {
        currentProjectState = projectState
        showingProjectHub = false
    }
    
    func closeCurrentProject() async {
        currentProjectState = nil
        showingProjectHub = false
    }
    
    // Placeholder methods to satisfy the interface
    func saveCurrentProject() async throws {
        // Placeholder
    }
    
    func importMedia(urls: [URL], progressHandler: @escaping (Double) -> Void) async throws -> [ProjectMediaReference] {
        return []
    }
    
    func openProject(at url: URL) async throws {
        // Placeholder
    }
    
    func createNewProject(title: String, template: ProjectTemplate, mediaPolicy: ProjectManifest.MediaPolicy, at directoryURL: URL) async throws {
        // Placeholder
    }
    
    func duplicateCurrentProject(newTitle: String, at directoryURL: URL) async throws {
        // Placeholder
    }
}