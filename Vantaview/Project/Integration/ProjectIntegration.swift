import Foundation
import SwiftUI

// MARK: - MediaFile Extensions

extension MediaFile {
    /// Convert to ProjectMediaReference
    func asProjectMediaReference() -> ProjectMediaReference {
        let mediaType: ProjectMediaReference.MediaType
        switch fileType {
        case .video:
            mediaType = .video
        case .audio:
            mediaType = .audio
        case .image:
            mediaType = .image
        }
        
        var reference = ProjectMediaReference(
            originalPath: url.path,
            fileName: name,
            mediaType: mediaType,
            isLinked: true // Existing MediaFiles are typically linked
        )
        
        reference.absolutePath = url.path
        reference.duration = duration
        
        return reference
    }
    
    /// Create MediaFile from ProjectMediaReference
    static func from(_ reference: ProjectMediaReference, projectURL: URL) async -> MediaFile? {
        let mediaManager = MediaManager()
        
        guard let resolvedURL = await mediaManager.resolveMediaReference(reference, projectURL: projectURL) else {
            return nil
        }
        
        let fileType: MediaFile.MediaFileType
        switch reference.mediaType {
        case .video:
            fileType = .video
        case .audio:
            fileType = .audio
        case .image:
            fileType = .image
        }
        
        return MediaFile(
            name: reference.fileName,
            url: resolvedURL,
            fileType: fileType,
            duration: reference.duration
        )
    }
}

extension ProjectMediaReference {
    /// Convert to legacy ContentSource format if needed
    func asContentSource() -> MediaSource {
        // This would need to be implemented based on your existing ContentSource type
        // For now, returning a placeholder media source
        return MediaSource.media(url: URL(fileURLWithPath: resolvedPath ?? originalPath), duration: duration ?? 0)
    }
}

// MARK: - Project State Integration

extension ProjectState {
    /// Convert current project media to MediaFile array for legacy systems
    func getMediaFiles() async -> [MediaFile] {
        guard let projectURL = projectURL else { return [] }
        
        let mediaManager = MediaManager()
        var mediaFiles: [MediaFile] = []
        
        for reference in mediaReferences {
            if let resolvedURL = await mediaManager.resolveMediaReference(reference, projectURL: projectURL) {
                let fileType: MediaFile.MediaFileType
                switch reference.mediaType {
                case .video:
                    fileType = .video
                case .audio:
                    fileType = .audio
                case .image:
                    fileType = .image
                }
                
                let mediaFile = MediaFile(
                    name: reference.fileName,
                    url: resolvedURL,
                    fileType: fileType,
                    duration: reference.duration
                )
                mediaFiles.append(mediaFile)
            }
        }
        
        return mediaFiles
    }
    
    /// Add MediaFiles to project state
    func importMediaFiles(_ mediaFiles: [MediaFile]) {
        for mediaFile in mediaFiles {
            let reference = mediaFile.asProjectMediaReference()
            addMediaReference(reference)
        }
    }
}

// MARK: - MediaSource Placeholder

enum MediaSource {
    case media(url: URL, duration: TimeInterval)
    case camera(deviceId: String)
    case virtualCamera(id: UUID)
}

// MARK: - Production Manager Integration

extension ProjectCoordinator {
    /// Apply project configuration to UnifiedProductionManager
    func applyProjectConfiguration(to productionManager: UnifiedProductionManager) async {
        guard let projectState = currentProjectState else { return }
        
        // Apply routing configuration
        let routing = projectState.routing
        
        // Configure input sources
        for inputSource in routing.inputSources {
            switch inputSource.type {
            case .camera:
                if let deviceId = inputSource.deviceId {
                    await productionManager.switchProgram(to: deviceId)
                }
            case .mediaFile:
                // Handle media file routing
                break
            case .virtualCamera:
                // Handle virtual camera routing
                break
            case .screenCapture:
                // Handle screen capture routing
                break
            }
        }
        
        // Apply preview/program mapping
        if let previewSourceId = routing.previewProgramMapping.previewSourceId,
           let previewSource = routing.inputSources.first(where: { $0.id == previewSourceId }),
           let deviceId = previewSource.deviceId {
            productionManager.selectedPreviewCameraID = deviceId
        }
        
        if let programSourceId = routing.previewProgramMapping.programSourceId,
           let programSource = routing.inputSources.first(where: { $0.id == programSourceId }),
           let deviceId = programSource.deviceId {
            productionManager.selectedProgramCameraID = deviceId
        }
        
        // Apply mixer configuration
        let mixer = projectState.mixer
        // Configure audio buses based on mixer.audioBuses
        
        // Apply effects configuration
        let effects = projectState.effects
        // Configure PiP, chroma key, filters based on effects configuration
        
        // Mark production manager as configured from project
        productionManager.hasUnsavedChanges = projectState.hasUnsavedChanges
    }
    
    /// Save current production state to project
    func saveProductionStateToProject(from productionManager: UnifiedProductionManager) async {
        guard let projectState = currentProjectState else { return }
        
        // Update routing based on current production state
        var routing = projectState.routing
        
        // Update preview/program mapping
        if let programCameraID = productionManager.selectedProgramCameraID {
            if let existingSource = routing.inputSources.first(where: { $0.deviceId == programCameraID }) {
                routing.previewProgramMapping.programSourceId = existingSource.id
            }
        }
        
        if let previewCameraID = productionManager.selectedPreviewCameraID {
            if let existingSource = routing.inputSources.first(where: { $0.deviceId == previewCameraID }) {
                routing.previewProgramMapping.previewSourceId = existingSource.id
            }
        }
        
        // Update project state
        await MainActor.run {
            projectState.routing = routing
            projectState.markUnsaved()
        }
    }
}

// MARK: - Template Configuration Integration

extension ProjectTemplate {
    /// Apply template to UnifiedProductionManager
    @MainActor
    func configureProductionManager(_ productionManager: UnifiedProductionManager) async {
        switch self {
        case .news:
            // Configure for news production
            productionManager.currentTemplate = .news
            
        case .talkShow:
            // Configure for talk show production
            productionManager.currentTemplate = .talkShow
            
        case .podcast:
            // Configure for podcast production
            productionManager.currentTemplate = .podcast
            
        case .gaming:
            // Configure for gaming production
            productionManager.currentTemplate = .gaming
            
        case .concert:
            // Configure for concert production
            productionManager.currentTemplate = .concert
            
        case .productDemo:
            // Configure for product demo
            productionManager.currentTemplate = .productDemo
            
        case .webinar, .interview:
            // Configure for webinar/interview
            productionManager.currentTemplate = .custom
            
        case .blank:
            // Minimal configuration
            productionManager.currentTemplate = .custom
        }
    }
}