import Foundation
import SwiftUI

// MARK: - Project State

@MainActor
final class ProjectState: ObservableObject {
    @Published var manifest: ProjectManifest
    @Published var timeline: ProjectTimeline
    @Published var routing: ProjectRouting
    @Published var mixer: ProjectMixer
    @Published var effects: ProjectEffects
    @Published var mediaReferences: [ProjectMediaReference]
    
    @Published var hasUnsavedChanges: Bool = false
    @Published var isAutoSaveEnabled: Bool = true
    @Published var lastSavedAt: Date?
    @Published var saveInProgress: Bool = false
    
    // Project file system paths
    var projectURL: URL?
    var manifestURL: URL? { projectURL?.appendingPathComponent("manifest.json") }
    var timelineURL: URL? { projectURL?.appendingPathComponent("timeline.json") }
    var routingURL: URL? { projectURL?.appendingPathComponent("routing.json") }
    var mixerURL: URL? { projectURL?.appendingPathComponent("mixer.json") }
    var effectsURL: URL? { projectURL?.appendingPathComponent("effects.json") }
    var mediaDirectoryURL: URL? { projectURL?.appendingPathComponent("media") }
    var thumbnailsDirectoryURL: URL? { projectURL?.appendingPathComponent("thumbnails") }
    var cacheDirectoryURL: URL? { projectURL?.appendingPathComponent("cache") }
    var versionsDirectoryURL: URL? { projectURL?.appendingPathComponent(".versions") }
    
    init(template: ProjectTemplate = .blank) {
        // Initialize with template defaults
        self.manifest = ProjectManifest(title: "New Project")
        self.timeline = ProjectTimeline()
        self.routing = ProjectRouting()
        self.mixer = ProjectMixer()
        self.effects = ProjectEffects()
        self.mediaReferences = []
        
        applyTemplate(template)
    }
    
    init(manifest: ProjectManifest, timeline: ProjectTimeline, routing: ProjectRouting, 
         mixer: ProjectMixer, effects: ProjectEffects, mediaReferences: [ProjectMediaReference]) {
        self.manifest = manifest
        self.timeline = timeline
        self.routing = routing
        self.mixer = mixer
        self.effects = effects
        self.mediaReferences = mediaReferences
    }
    
    private func applyTemplate(_ template: ProjectTemplate) {
        manifest.title = template.displayName
        
        // Apply template-specific configurations
        switch template {
        case .blank:
            // Minimal setup - already initialized
            break
            
        case .news:
            setupNewsTemplate()
            
        case .talkShow:
            setupTalkShowTemplate()
            
        case .podcast:
            setupPodcastTemplate()
            
        case .gaming:
            setupGamingTemplate()
            
        case .concert:
            setupConcertTemplate()
            
        case .productDemo:
            setupProductDemoTemplate()
            
        case .webinar:
            setupWebinarTemplate()
            
        case .interview:
            setupInterviewTemplate()
        }
    }
    
    // MARK: - Template Setups
    
    private func setupNewsTemplate() {
        // Create default audio buses
        let masterBus = AudioBusConfig(name: "Master")
        let micBus = AudioBusConfig(name: "Microphone")
        let musicBus = AudioBusConfig(name: "Background Music")
        mixer.audioBuses = [masterBus, micBus, musicBus]
        
        // Create default input sources
        let cameraMain = InputSource(name: "Main Camera", type: .camera)
        let cameraWide = InputSource(name: "Wide Shot", type: .camera)
        routing.inputSources = [cameraMain, cameraWide]
        
        // Set up default preview/program
        routing.previewProgramMapping.previewSourceId = cameraWide.id
        routing.previewProgramMapping.programSourceId = cameraMain.id
    }
    
    private func setupTalkShowTemplate() {
        // Multi-camera setup
        let cam1 = InputSource(name: "Host Camera", type: .camera)
        let cam2 = InputSource(name: "Guest Camera", type: .camera)
        let cam3 = InputSource(name: "Wide Shot", type: .camera)
        routing.inputSources = [cam1, cam2, cam3]
        
        // Audio setup for multiple mics
        let masterBus = AudioBusConfig(name: "Master")
        let hostMicBus = AudioBusConfig(name: "Host Mic")
        let guestMicBus = AudioBusConfig(name: "Guest Mic")
        let musicBus = AudioBusConfig(name: "Music")
        mixer.audioBuses = [masterBus, hostMicBus, guestMicBus, musicBus]
        
        routing.previewProgramMapping.previewSourceId = cam3.id
        routing.previewProgramMapping.programSourceId = cam1.id
    }
    
    private func setupPodcastTemplate() {
        // Audio-focused setup
        let cam1 = InputSource(name: "Host Camera", type: .camera)
        let cam2 = InputSource(name: "Guest Camera", type: .camera)
        routing.inputSources = [cam1, cam2]
        
        let masterBus = AudioBusConfig(name: "Master")
        let host1Bus = AudioBusConfig(name: "Host 1")
        let host2Bus = AudioBusConfig(name: "Host 2")
        let introMusicBus = AudioBusConfig(name: "Intro Music")
        mixer.audioBuses = [masterBus, host1Bus, host2Bus, introMusicBus]
        
        routing.previewProgramMapping.previewSourceId = cam2.id
        routing.previewProgramMapping.programSourceId = cam1.id
    }
    
    private func setupGamingTemplate() {
        // Gaming-focused setup with screen capture
        let faceCam = InputSource(name: "Face Cam", type: .camera)
        let screenCapture = InputSource(name: "Game Capture", type: .screenCapture)
        routing.inputSources = [faceCam, screenCapture]
        
        // Set up PiP for face cam
        var pipConfig = PiPConfig(name: "Face Cam PiP", sourceId: faceCam.id)
        pipConfig.position = CGRect(x: 0.75, y: 0.75, width: 0.2, height: 0.2)
        effects.pipConfigs.append(pipConfig)
        
        let masterBus = AudioBusConfig(name: "Master")
        let micBus = AudioBusConfig(name: "Microphone")
        let gameBus = AudioBusConfig(name: "Game Audio")
        let alertsBus = AudioBusConfig(name: "Alerts")
        mixer.audioBuses = [masterBus, micBus, gameBus, alertsBus]
        
        routing.previewProgramMapping.previewSourceId = faceCam.id
        routing.previewProgramMapping.programSourceId = screenCapture.id
    }
    
    private func setupConcertTemplate() {
        // Multi-camera performance setup
        let cam1 = InputSource(name: "Main Stage", type: .camera)
        let cam2 = InputSource(name: "Close-up", type: .camera)
        let cam3 = InputSource(name: "Audience", type: .camera)
        let cam4 = InputSource(name: "Side Angle", type: .camera)
        routing.inputSources = [cam1, cam2, cam3, cam4]
        
        let masterBus = AudioBusConfig(name: "Master")
        let performersBus = AudioBusConfig(name: "Performers")
        let audienceBus = AudioBusConfig(name: "Audience")
        mixer.audioBuses = [masterBus, performersBus, audienceBus]
        
        routing.previewProgramMapping.previewSourceId = cam2.id
        routing.previewProgramMapping.programSourceId = cam1.id
        routing.previewProgramMapping.transitionDuration = 0.5
    }
    
    private func setupProductDemoTemplate() {
        // Product demonstration setup
        let mainCam = InputSource(name: "Main Camera", type: .camera)
        let overheadCam = InputSource(name: "Overhead Shot", type: .camera)
        let screenShare = InputSource(name: "Screen Share", type: .screenCapture)
        routing.inputSources = [mainCam, overheadCam, screenShare]
        
        let masterBus = AudioBusConfig(name: "Master")
        let presenterMicBus = AudioBusConfig(name: "Presenter Mic")
        mixer.audioBuses = [masterBus, presenterMicBus]
        
        routing.previewProgramMapping.previewSourceId = overheadCam.id
        routing.previewProgramMapping.programSourceId = mainCam.id
    }
    
    private func setupWebinarTemplate() {
        // Webinar/presentation setup
        let presenterCam = InputSource(name: "Presenter Camera", type: .camera)
        let screenShare = InputSource(name: "Screen Share", type: .screenCapture)
        routing.inputSources = [presenterCam, screenShare]
        
        // Set up PiP for presenter
        var pipConfig = PiPConfig(name: "Presenter PiP", sourceId: presenterCam.id)
        pipConfig.position = CGRect(x: 0.75, y: 0.75, width: 0.2, height: 0.2)
        effects.pipConfigs.append(pipConfig)
        
        let masterBus = AudioBusConfig(name: "Master")
        let presenterMicBus = AudioBusConfig(name: "Presenter Mic")
        let systemAudioBus = AudioBusConfig(name: "System Audio")
        mixer.audioBuses = [masterBus, presenterMicBus, systemAudioBus]
        
        routing.previewProgramMapping.previewSourceId = presenterCam.id
        routing.previewProgramMapping.programSourceId = screenShare.id
    }
    
    private func setupInterviewTemplate() {
        // Two-person interview setup
        let interviewer = InputSource(name: "Interviewer", type: .camera)
        let interviewee = InputSource(name: "Interviewee", type: .camera)
        let wide = InputSource(name: "Wide Shot", type: .camera)
        routing.inputSources = [interviewer, interviewee, wide]
        
        let masterBus = AudioBusConfig(name: "Master")
        let interviewerMicBus = AudioBusConfig(name: "Interviewer Mic")
        let intervieweeMicBus = AudioBusConfig(name: "Interviewee Mic")
        mixer.audioBuses = [masterBus, interviewerMicBus, intervieweeMicBus]
        
        routing.previewProgramMapping.previewSourceId = wide.id
        routing.previewProgramMapping.programSourceId = interviewer.id
    }
    
    // MARK: - State Management
    
    func markUnsaved() {
        hasUnsavedChanges = true
        manifest.markUpdated()
    }
    
    func markSaved() {
        hasUnsavedChanges = false
        lastSavedAt = Date()
    }
    
    func addMediaReference(_ reference: ProjectMediaReference) {
        mediaReferences.append(reference)
        markUnsaved()
    }
    
    func removeMediaReference(_ id: UUID) {
        mediaReferences.removeAll { $0.id == id }
        markUnsaved()
    }
    
    func updateMediaReference(_ id: UUID, _ updateBlock: (inout ProjectMediaReference) -> Void) {
        if let index = mediaReferences.firstIndex(where: { $0.id == id }) {
            updateBlock(&mediaReferences[index])
            markUnsaved()
        }
    }
}

// MARK: - Recent Projects

struct RecentProject: Codable, Identifiable, Sendable {
    let id: UUID
    let projectId: UUID
    let title: String
    let lastOpenedAt: Date
    let projectURL: URL
    let thumbnailPath: String?
    let resolution: CGSize?
    let frameRate: Double?
    let duration: TimeInterval?
    
    init(projectId: UUID, title: String, projectURL: URL) {
        self.id = UUID()
        self.projectId = projectId
        self.title = title
        self.lastOpenedAt = Date()
        self.projectURL = projectURL
        self.thumbnailPath = nil
        self.resolution = nil
        self.frameRate = nil
        self.duration = nil
    }
}

@MainActor
final class RecentProjectsManager: ObservableObject {
    @Published var recentProjects: [RecentProject] = []
    
    private let userDefaults = UserDefaults.standard
    private let recentProjectsKey = "com.vantaview.recentProjects"
    private let maxRecentProjects = 20
    
    init() {
        loadRecentProjects()
    }
    
    func addRecentProject(_ project: RecentProject) {
        // Remove existing entry if it exists
        recentProjects.removeAll { $0.projectId == project.projectId }
        
        // Add to beginning
        recentProjects.insert(project, at: 0)
        
        // Limit size
        if recentProjects.count > maxRecentProjects {
            recentProjects = Array(recentProjects.prefix(maxRecentProjects))
        }
        
        saveRecentProjects()
    }
    
    func removeRecentProject(_ projectId: UUID) {
        recentProjects.removeAll { $0.projectId == projectId }
        saveRecentProjects()
    }
    
    func clearRecentProjects() {
        recentProjects.removeAll()
        saveRecentProjects()
    }
    
    private func loadRecentProjects() {
        guard let data = userDefaults.data(forKey: recentProjectsKey) else { return }
        
        do {
            let decoded = try JSONDecoder().decode([RecentProject].self, from: data)
            recentProjects = decoded
        } catch {
            print("Failed to load recent projects: \(error)")
        }
    }
    
    private func saveRecentProjects() {
        do {
            let encoded = try JSONEncoder().encode(recentProjects)
            userDefaults.set(encoded, forKey: recentProjectsKey)
        } catch {
            print("Failed to save recent projects: \(error)")
        }
    }
}