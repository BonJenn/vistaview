import SwiftUI
import os
import UniformTypeIdentifiers

@MainActor
final class ProjectCoordinator: ObservableObject {
    @Published var currentProjectState: ProjectState?
    @Published var showingProjectHub = false
    @Published var isLoadingProject = false
    @Published var projectError: Error?
    
    private let projectManager = ProjectManager()
    private let logger = Logger(subsystem: "app.vantaview.project", category: "ProjectCoordinator")
    
    // Auto-save management
    private var autoSaveTask: Task<Void, Never>?
    
    var hasOpenProject: Bool {
        currentProjectState != nil
    }
    
    // MARK: - Project Operations
    
    func createNewProject(
        title: String,
        template: ProjectTemplate,
        mediaPolicy: ProjectManifest.MediaPolicy,
        at directoryURL: URL
    ) async throws {
        isLoadingProject = true
        projectError = nil
        
        defer { isLoadingProject = false }
        
        do {
            let projectState = try await projectManager.createProject(
                title: title,
                template: template,
                mediaPolicy: mediaPolicy,
                at: directoryURL
            )
            
            await openProject(projectState)
            logger.info("Created and opened new project: \(title)")
            
        } catch {
            projectError = error
            logger.error("Failed to create project: \(error.localizedDescription)")
            throw error
        }
    }
    
    func openProject(at url: URL) async throws {
        isLoadingProject = true
        projectError = nil
        
        defer { isLoadingProject = false }
        
        do {
            let projectState = try await projectManager.openProject(at: url)
            await openProject(projectState)
            let projectTitle = projectState.manifest.title
            logger.info("Opened project: \(projectTitle)")
            
        } catch {
            projectError = error
            logger.error("Failed to open project: \(error.localizedDescription)")
            throw error
        }
    }
    
    func openProject(_ projectState: ProjectState) async {
        // Stop auto-save for previous project
        autoSaveTask?.cancel()
        
        // Set new project
        currentProjectState = projectState
        showingProjectHub = false
        
        // Start auto-save for new project
        enableAutoSave(for: projectState)
    }
    
    func saveCurrentProject() async throws {
        guard let projectState = currentProjectState else {
            throw ProjectError.noProjectURL
        }
        
        try await projectManager.saveProject(projectState)
        logger.info("Saved current project")
    }
    
    func closeCurrentProject() async {
        // Stop auto-save
        autoSaveTask?.cancel()
        
        // Save if there are unsaved changes
        if let projectState = currentProjectState,
           await projectState.hasUnsavedChanges {
            do {
                try await saveCurrentProject()
            } catch {
                logger.error("Failed to save project on close: \(error.localizedDescription)")
                // Could show alert here
            }
        }
        
        currentProjectState = nil
        showingProjectHub = true  // This will cause the app to show Project Hub
        
        logger.info("Closed current project - returning to Project Hub")
    }
    
    func duplicateCurrentProject(newTitle: String, at directoryURL: URL) async throws {
        guard let currentProject = currentProjectState else {
            throw ProjectError.noProjectURL
        }
        
        isLoadingProject = true
        defer { isLoadingProject = false }
        
        do {
            let duplicatedProject = try await projectManager.duplicateProject(
                currentProject,
                newTitle: newTitle,
                at: directoryURL
            )
            
            await openProject(duplicatedProject)
            logger.info("Duplicated project as: \(newTitle)")
            
        } catch {
            projectError = error
            throw error
        }
    }
    
    // MARK: - Auto Save
    
    private func enableAutoSave(for projectState: ProjectState) {
        autoSaveTask = Task { [weak self] in
            await self?.projectManager.enableAutoSave(for: projectState)
        }
    }
    
    // MARK: - App Launch
    
    func handleAppLaunch() {
        // Always start with Project Hub showing when no project is open
        if currentProjectState == nil {
            showingProjectHub = true
        }
    }
    
    // MARK: - File Opening
    
    func handleFileOpen(url: URL) async {
        do {
            try await openProject(at: url)
        } catch {
            projectError = error
            logger.error("Failed to open file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Media Import
    
    func importMedia(urls: [URL], progressHandler: @escaping (Double) -> Void) async throws -> [ProjectMediaReference] {
        guard let projectState = currentProjectState else {
            throw ProjectError.noProjectURL
        }
        
        let mediaManager = MediaManager()
        let mediaPolicy = await projectState.manifest.mediaPolicy
        
        return try await mediaManager.importMedia(
            from: urls,
            to: projectState,
            mediaPolicy: mediaPolicy,
            progressHandler: progressHandler
        )
    }
}

// MARK: - Error Handling

extension ProjectCoordinator {
    func clearError() {
        projectError = nil
    }
    
    var errorMessage: String? {
        projectError?.localizedDescription
    }
}