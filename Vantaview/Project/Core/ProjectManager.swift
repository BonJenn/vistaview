import Foundation
import os
import UniformTypeIdentifiers

actor ProjectManager {
    private let logger = Logger(subsystem: "app.vantaview.project", category: "ProjectManager")
    private let fileManager = FileManager.default
    
    // File operations queue for sequential writes
    private var saveOperations: [String: Task<Void, Error>] = [:]
    
    // Version management
    private let maxVersionHistory = 50
    private var versionCounter = 0
    
    // File lock management
    private var projectLocks: [URL: NSFileLock] = [:]
    
    // MARK: - Project Creation
    
    func createProject(
        title: String,
        template: ProjectTemplate,
        mediaPolicy: ProjectManifest.MediaPolicy,
        at directoryURL: URL
    ) async throws -> ProjectState {
        logger.info("Creating new project: \(title)")
        
        let sanitizedTitle = sanitizeFileName(title)
        let projectURL = directoryURL.appendingPathComponent("\(sanitizedTitle).vvproj")
        
        // Check if project already exists
        guard !fileManager.fileExists(atPath: projectURL.path) else {
            throw ProjectError.projectAlreadyExists(projectURL)
        }
        
        // Create project package directory
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        
        // Create subdirectories
        let subdirectories = [
            projectURL.appendingPathComponent("media"),
            projectURL.appendingPathComponent("thumbnails"),
            projectURL.appendingPathComponent("cache"),
            projectURL.appendingPathComponent(".versions")
        ]
        
        for directory in subdirectories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        // Initialize project state
        let projectState = await ProjectState(template: template)
        await projectState.setProjectURL(projectURL)
        
        // Update manifest with correct media policy
        await MainActor.run {
            projectState.manifest.title = title
            projectState.manifest.mediaPolicy = mediaPolicy
        }
        
        // Perform initial save
        try await saveProject(projectState)
        
        // Generate initial thumbnail
        Task.detached(priority: .utility) {
            await self.generateProjectThumbnail(for: projectState)
        }
        
        logger.info("Project created successfully at: \(projectURL.path)")
        return projectState
    }
    
    // MARK: - Project Loading
    
    func openProject(at projectURL: URL) async throws -> ProjectState {
        logger.info("Opening project at: \(projectURL.path)")
        
        // Validate project structure
        try await validateProjectStructure(at: projectURL)
        
        // Acquire file lock
        try await acquireProjectLock(projectURL)
        
        do {
            // Load manifest first for version checking
            let manifestURL = projectURL.appendingPathComponent("manifest.json")
            let manifest = try await loadManifest(from: manifestURL)
            
            // Check schema version and migrate if needed
            let migratedManifest = try await migrateManifestIfNeeded(manifest, at: projectURL)
            
            // Load all project components concurrently
            async let timelineTask = loadTimeline(from: projectURL.appendingPathComponent("timeline.json"))
            async let routingTask = loadRouting(from: projectURL.appendingPathComponent("routing.json"))
            async let mixerTask = loadMixer(from: projectURL.appendingPathComponent("mixer.json"))
            async let effectsTask = loadEffects(from: projectURL.appendingPathComponent("effects.json"))
            async let mediaTask = loadMediaReferences(from: projectURL)
            
            let timeline = try await timelineTask
            let routing = try await routingTask
            let mixer = try await mixerTask
            let effects = try await effectsTask
            let mediaReferences = try await mediaTask
            
            // Create project state
            let projectState = await ProjectState(
                manifest: migratedManifest,
                timeline: timeline,
                routing: routing,
                mixer: mixer,
                effects: effects,
                mediaReferences: mediaReferences
            )
            
            await projectState.setProjectURL(projectURL)
            await MainActor.run {
                projectState.markSaved()
            }
            
            // Verify media links in background
            Task.detached(priority: .utility) {
                await self.verifyMediaLinks(for: projectState)
            }
            
            logger.info("Project opened successfully")
            return projectState
            
        } catch {
            await releaseProjectLock(projectURL)
            throw error
        }
    }
    
    // MARK: - Project Saving
    
    func saveProject(_ projectState: ProjectState) async throws {
        guard let projectURL = await projectState.projectURL else {
            throw ProjectError.noProjectURL
        }
        
        let projectTitle = await projectState.manifest.title
        logger.info("Saving project: \(projectTitle)")
        
        // Cancel any existing save operation for this project
        let projectPath = projectURL.path
        saveOperations[projectPath]?.cancel()
        
        // Create new save operation
        let saveTask = Task<Void, Error> {
            try Task.checkCancellation()
            
            // Create version snapshot before saving
            try await createVersionSnapshot(for: projectState)
            
            // Prepare data for saving
            let manifest = await projectState.manifest
            let timeline = await projectState.timeline
            let routing = await projectState.routing
            let mixer = await projectState.mixer
            let effects = await projectState.effects
            
            try Task.checkCancellation()
            
            // Save all components atomically
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.saveManifest(manifest, to: projectURL.appendingPathComponent("manifest.json")) }
                group.addTask { try await self.saveTimeline(timeline, to: projectURL.appendingPathComponent("timeline.json")) }
                group.addTask { try await self.saveRouting(routing, to: projectURL.appendingPathComponent("routing.json")) }
                group.addTask { try await self.saveMixer(mixer, to: projectURL.appendingPathComponent("mixer.json")) }
                group.addTask { try await self.saveEffects(effects, to: projectURL.appendingPathComponent("effects.json")) }
                
                try await group.waitForAll()
            }
            
            try Task.checkCancellation()
            
            // Update project state
            await MainActor.run {
                projectState.markSaved()
            }
        }
        
        saveOperations[projectPath] = saveTask
        
        do {
            try await saveTask.value
            saveOperations.removeValue(forKey: projectPath)
            logger.info("Project saved successfully")
        } catch {
            saveOperations.removeValue(forKey: projectPath)
            throw error
        }
    }
    
    // MARK: - Auto Save
    
    func enableAutoSave(for projectState: ProjectState, interval: TimeInterval = 5.0) {
        Task {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                
                let hasChanges = await projectState.hasUnsavedChanges
                let autoSaveEnabled = await projectState.isAutoSaveEnabled
                
                if hasChanges && autoSaveEnabled {
                    do {
                        try await saveProject(projectState)
                        logger.debug("Auto-save completed")
                    } catch {
                        logger.error("Auto-save failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // MARK: - Project Duplication
    
    func duplicateProject(
        _ sourceProjectState: ProjectState,
        newTitle: String,
        at directoryURL: URL
    ) async throws -> ProjectState {
        guard let sourceURL = await sourceProjectState.projectURL else {
            throw ProjectError.noProjectURL
        }
        
        logger.info("Duplicating project: \(newTitle)")
        
        let sanitizedTitle = sanitizeFileName(newTitle)
        let newProjectURL = directoryURL.appendingPathComponent("\(sanitizedTitle).vvproj")
        
        // Ensure destination doesn't exist
        guard !fileManager.fileExists(atPath: newProjectURL.path) else {
            throw ProjectError.projectAlreadyExists(newProjectURL)
        }
        
        // Copy project package
        try fileManager.copyItem(at: sourceURL, to: newProjectURL)
        
        // Load the duplicated project
        let duplicatedState = try await openProject(at: newProjectURL)
        
        // Update manifest with new title and IDs
        await MainActor.run {
            duplicatedState.manifest.title = newTitle
            duplicatedState.manifest.projectId = UUID()
            duplicatedState.manifest.createdAt = Date()
            duplicatedState.manifest.updatedAt = Date()
            duplicatedState.markUnsaved()
        }
        
        // Save the updated manifest
        try await saveProject(duplicatedState)
        
        // Generate new thumbnail
        Task.detached(priority: .utility) {
            await self.generateProjectThumbnail(for: duplicatedState)
        }
        
        logger.info("Project duplicated successfully")
        return duplicatedState
    }
    
    // MARK: - Project Deletion
    
    func deleteProject(at projectURL: URL) async throws {
        logger.info("Deleting project at: \(projectURL.path)")
        
        // Release any locks
        await releaseProjectLock(projectURL)
        
        // Move to trash instead of permanent deletion
        if fileManager.fileExists(atPath: projectURL.path) {
            var trashedURL: NSURL?
            try fileManager.trashItem(at: projectURL, resultingItemURL: &trashedURL)
            logger.info("Project moved to trash")
        }
    }
    
    // MARK: - Version History
    
    private func createVersionSnapshot(for projectState: ProjectState) async throws {
        guard let projectURL = await projectState.projectURL else { return }
        
        let versionsDir = projectURL.appendingPathComponent(".versions")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let versionDir = versionsDir.appendingPathComponent("v\(versionCounter)_\(timestamp)")
        
        try fileManager.createDirectory(at: versionDir, withIntermediateDirectories: true)
        
        // Copy current state files to version directory
        let filesToVersion = [
            "manifest.json", "timeline.json", "routing.json", "mixer.json", "effects.json"
        ]
        
        for fileName in filesToVersion {
            let sourceURL = projectURL.appendingPathComponent(fileName)
            let destURL = versionDir.appendingPathComponent(fileName)
            
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.copyItem(at: sourceURL, to: destURL)
            }
        }
        
        versionCounter += 1
        
        // Clean up old versions
        try await cleanupOldVersions(versionsDir: versionsDir)
    }
    
    private func cleanupOldVersions(versionsDir: URL) async throws {
        let versions = try fileManager.contentsOfDirectory(at: versionsDir, includingPropertiesForKeys: [.creationDateKey])
        
        if versions.count > maxVersionHistory {
            let sortedVersions = versions.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 < date2
            }
            
            let versionsToDelete = sortedVersions.prefix(versions.count - maxVersionHistory)
            for version in versionsToDelete {
                try fileManager.removeItem(at: version)
            }
        }
    }
    
    // MARK: - File Operations
    
    private func saveManifest(_ manifest: ProjectManifest, to url: URL) async throws {
        let data = try JSONEncoder().encode(manifest)
        try await atomicWrite(data: data, to: url)
    }
    
    private func loadManifest(from url: URL) async throws -> ProjectManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProjectManifest.self, from: data)
    }
    
    private func saveTimeline(_ timeline: ProjectTimeline, to url: URL) async throws {
        let data = try JSONEncoder().encode(timeline)
        try await atomicWrite(data: data, to: url)
    }
    
    private func loadTimeline(from url: URL) async throws -> ProjectTimeline {
        guard fileManager.fileExists(atPath: url.path) else {
            return ProjectTimeline()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProjectTimeline.self, from: data)
    }
    
    private func saveRouting(_ routing: ProjectRouting, to url: URL) async throws {
        let data = try JSONEncoder().encode(routing)
        try await atomicWrite(data: data, to: url)
    }
    
    private func loadRouting(from url: URL) async throws -> ProjectRouting {
        guard fileManager.fileExists(atPath: url.path) else {
            return ProjectRouting()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProjectRouting.self, from: data)
    }
    
    private func saveMixer(_ mixer: ProjectMixer, to url: URL) async throws {
        let data = try JSONEncoder().encode(mixer)
        try await atomicWrite(data: data, to: url)
    }
    
    private func loadMixer(from url: URL) async throws -> ProjectMixer {
        guard fileManager.fileExists(atPath: url.path) else {
            return ProjectMixer()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProjectMixer.self, from: data)
    }
    
    private func saveEffects(_ effects: ProjectEffects, to url: URL) async throws {
        let data = try JSONEncoder().encode(effects)
        try await atomicWrite(data: data, to: url)
    }
    
    private func loadEffects(from url: URL) async throws -> ProjectEffects {
        guard fileManager.fileExists(atPath: url.path) else {
            return ProjectEffects()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProjectEffects.self, from: data)
    }
    
    // MARK: - Media Management
    
    private func loadMediaReferences(from projectURL: URL) async throws -> [ProjectMediaReference] {
        // For now, scan the media directory and create references
        // In the future, this could be stored in a separate media.json file
        let mediaDir = projectURL.appendingPathComponent("media")
        
        guard fileManager.fileExists(atPath: mediaDir.path) else {
            return []
        }
        
        let mediaFiles = try fileManager.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        
        return mediaFiles.compactMap { url in
            let fileName = url.lastPathComponent
            let mediaType: ProjectMediaReference.MediaType
            
            switch url.pathExtension.lowercased() {
            case "mp4", "mov", "avi", "mkv", "webm":
                mediaType = .video
            case "mp3", "wav", "aac", "m4a":
                mediaType = .audio
            case "jpg", "jpeg", "png", "gif", "tiff":
                mediaType = .image
            default:
                return nil
            }
            
            var reference = ProjectMediaReference(
                originalPath: url.path,
                fileName: fileName,
                mediaType: mediaType,
                isLinked: false
            )
            
            // Set relative path
            reference.relativePath = "media/\(fileName)"
            
            // Get file size and modification date
            if let resources = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
                reference.fileSize = Int64(resources.fileSize ?? 0)
                reference.lastModified = resources.contentModificationDate ?? Date()
            }
            
            return reference
        }
    }
    
    // MARK: - Atomic File Operations
    
    private func atomicWrite(data: Data, to url: URL) async throws {
        let tempURL = url.appendingPathExtension("tmp")
        
        // Write to temporary file first
        try data.write(to: tempURL)
        
        // Atomically replace the original file
        _ = try fileManager.replaceItem(at: url, withItemAt: tempURL, backupItemName: nil, options: [], resultingItemURL: nil)
    }
    
    // MARK: - File Locking
    
    private func acquireProjectLock(_ projectURL: URL) async throws {
        // Implementation would use file locking mechanism
        // For now, we'll use a simple in-memory tracking
        projectLocks[projectURL] = NSFileLock()
    }
    
    private func releaseProjectLock(_ projectURL: URL) async {
        projectLocks.removeValue(forKey: projectURL)
    }
    
    // MARK: - Validation & Migration
    
    private func validateProjectStructure(at projectURL: URL) async throws {
        let requiredFiles = ["manifest.json"]
        let requiredDirectories = ["media", "thumbnails", "cache"]
        
        // Check required files
        for fileName in requiredFiles {
            let fileURL = projectURL.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw ProjectError.invalidProjectStructure("Missing required file: \(fileName)")
            }
        }
        
        // Check and create required directories if missing
        for dirName in requiredDirectories {
            let dirURL = projectURL.appendingPathComponent(dirName)
            if !fileManager.fileExists(atPath: dirURL.path) {
                try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
        }
    }
    
    private func migrateManifestIfNeeded(_ manifest: ProjectManifest, at projectURL: URL) async throws -> ProjectManifest {
        // Check if migration is needed based on schema version
        if manifest.schemaVersion < 1 {
            logger.info("Migrating project schema from version \(manifest.schemaVersion) to 1")
            // Perform migration steps here
            var migratedManifest = manifest
            migratedManifest.updatedAt = Date()
            return migratedManifest
        }
        
        return manifest
    }
    
    // MARK: - Thumbnail Generation
    
    private func generateProjectThumbnail(for projectState: ProjectState) async {
        guard let projectURL = await projectState.projectURL else { return }
        
        let thumbnailURL = projectURL.appendingPathComponent("thumbnails/project.png")
        
        // This would integrate with the existing rendering system
        // For now, create a placeholder
        let placeholderData = createPlaceholderThumbnail()
        
        do {
            try placeholderData.write(to: thumbnailURL)
        } catch {
            logger.error("Failed to save project thumbnail: \(error.localizedDescription)")
        }
    }
    
    private func createPlaceholderThumbnail() -> Data {
        // Create a simple 640x360 placeholder image
        // In practice, this would render the current program output
        return Data()
    }
    
    // MARK: - Media Verification
    
    private func verifyMediaLinks(for projectState: ProjectState) async {
        // Check if linked media files still exist
        // This would run in the background and update the UI if files are missing
    }
    
    // MARK: - Utilities
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
}

// MARK: - Supporting Types

enum ProjectError: LocalizedError {
    case projectAlreadyExists(URL)
    case noProjectURL
    case invalidProjectStructure(String)
    case unsupportedSchemaVersion(Int)
    case saveFailed(String)
    case loadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .projectAlreadyExists(let url):
            return "A project already exists at \(url.lastPathComponent)"
        case .noProjectURL:
            return "No project URL specified"
        case .invalidProjectStructure(let message):
            return "Invalid project structure: \(message)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported project schema version: \(version)"
        case .saveFailed(let message):
            return "Failed to save project: \(message)"
        case .loadFailed(let message):
            return "Failed to load project: \(message)"
        }
    }
}

// Placeholder for NSFileLock
class NSFileLock {
    // Implementation would use platform-specific file locking
}

// Extension to ProjectState for URL management
extension ProjectState {
    func setProjectURL(_ url: URL) {
        projectURL = url
    }
}