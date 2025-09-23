import SwiftUI
import Foundation

@MainActor
class TemplateConfiguration {
    static func applyTemplate(
        _ template: ProjectTemplate,
        to productionManager: UnifiedProductionManager,
        with projectState: ProjectState
    ) async {
        // Apply Studio Mode default per template (Gaming: OFF, others: ON)
        productionManager.previewProgramManager.setStudioModeEnabled(template.studioModeDefault)

        // Apply template-specific studio configuration
        switch template {
        case .news:
            await configureNewsTemplate(productionManager, projectState)
        case .talkShow:
            await configureTalkShowTemplate(productionManager, projectState)
        case .podcast:
            await configurePodcastTemplate(productionManager, projectState)
        case .gaming:
            await configureGamingTemplate(productionManager, projectState)
        case .concert:
            await configureConcertTemplate(productionManager, projectState)
        case .productDemo:
            await configureProductDemoTemplate(productionManager, projectState)
        case .webinar:
            await configureWebinarTemplate(productionManager, projectState)
        case .interview:
            await configureInterviewTemplate(productionManager, projectState)
        case .blank:
            break
        }
        
        // Set project title as studio name
        productionManager.currentStudioName = projectState.manifest.title
        
        // Clear unsaved changes flag since we just applied the template
        productionManager.hasUnsavedChanges = false
    }
    
    private static func configureNewsTemplate(
        _ productionManager: UnifiedProductionManager,
        _ projectState: ProjectState
    ) async {
        productionManager.currentStudioName = "News Studio - \(projectState.manifest.title)"
        productionManager.loadTemplate(.news)
        productionManager.switchToVirtualMode()
    }
    
    private static func configureTalkShowTemplate(
        _ productionManager: UnifiedProductionManager,
        _ projectState: ProjectState
    ) async {
        productionManager.currentStudioName = "Talk Show - \(projectState.manifest.title)"
        productionManager.loadTemplate(.talkShow)
        productionManager.switchToVirtualMode()
    }
    
    private static func configurePodcastTemplate(
        _ productionManager: UnifiedProductionManager,
        _ projectState: ProjectState
    ) async {
        productionManager.currentStudioName = "Podcast Studio - \(projectState.manifest.title)"
        productionManager.loadTemplate(.podcast)
        productionManager.switchToLiveMode()
    }
    
    private static func configureGamingTemplate(
        _ productionManager: UnifiedProductionManager,
        _ projectState: ProjectState
    ) async {
        productionManager.currentStudioName = "Gaming Setup - \(projectState.manifest.title)"
        productionManager.loadTemplate(.gaming)
        productionManager.switchToLiveMode()
    }
    
    private static func configureConcertTemplate(
        _ productionManager: UnifiedProductionManager,
        _ projectState: ProjectState
    ) async {
        productionManager.currentStudioName = "Concert Stage - \(projectState.manifest.title)"
        productionManager.loadTemplate(.concert)
        productionManager.switchToVirtualMode()
    }
    
    private static func configureProductDemoTemplate(
        _ productionManager: UnifiedProductionManager,
        _ projectState: ProjectState
    ) async {
        productionManager.currentStudioName = "Product Demo - \(projectState.manifest.title)"
        productionManager.loadTemplate(.productDemo)
        productionManager.switchToVirtualMode()
    }
    
    private static func configureWebinarTemplate(
        _ productionManager: UnifiedProductionManager,
        _ projectState: ProjectState
    ) async {
        productionManager.currentStudioName = "Webinar Studio - \(projectState.manifest.title)"
        productionManager.loadTemplate(.custom)
        productionManager.switchToLiveMode()
    }
    
    private static func configureInterviewTemplate(
        _ productionManager: UnifiedProductionManager,
        _ projectState: ProjectState
    ) async {
        productionManager.currentStudioName = "Interview Setup - \(projectState.manifest.title)"
        productionManager.loadTemplate(.custom)
        productionManager.switchToLiveMode()
    }
}