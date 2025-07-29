//
//  UnifiedProductionManager.swift
//  Vistaview
//

import Foundation
import SwiftUI
import SceneKit

@MainActor
final class UnifiedProductionManager: ObservableObject {
    // Core Dependencies
    let streamingViewModel: StreamingViewModel
    let studioManager: VirtualStudioManager
    let cameraFeedManager: CameraFeedManager
    
    // Published States
    @Published var currentStudioName: String = "Default Studio"
    @Published var hasUnsavedChanges: Bool = false
    @Published var isVirtualStudioActive: Bool = false
    
    // Studio Management
    @Published var availableStudios: [StudioConfiguration] = []
    @Published var currentStudio: StudioConfiguration?
    @Published var currentTemplate: StudioTemplate = .custom
    
    init(studioManager: VirtualStudioManager? = nil,
         cameraFeedManager: CameraFeedManager? = nil) {
        self.studioManager = studioManager ?? VirtualStudioManager()
        
        // Create shared camera device manager and feed manager
        let deviceManager = CameraDeviceManager()
        self.cameraFeedManager = cameraFeedManager ?? CameraFeedManager(cameraDeviceManager: deviceManager)
        
        self.streamingViewModel = StreamingViewModel()
        
        // Set up bidirectional integration
        setupIntegration()
        
        // Initialize with default studio
        loadDefaultStudio()
    }
    
    private func setupIntegration() {
        // Connect camera feed manager to streaming view model
        cameraFeedManager.setStreamingViewModel(streamingViewModel)
        
        print("🔗 Unified Production Manager: Integration setup complete")
    }
    
    // MARK: - Mode Switching with State Management
    
    func switchToVirtualMode() {
        print("🎬 Switching to Virtual Production mode...")
        isVirtualStudioActive = true
        
        // Ensure camera feeds are properly managed when switching
        Task {
            await refreshCameraFeedStateForMode()
        }
    }
    
    func switchToLiveMode() {
        print("📺 Switching to Live Production mode...")
        
        // Sync virtual studio changes to live production
        syncVirtualToLive()
        
        // Ensure camera feeds are properly managed when switching
        Task {
            await refreshCameraFeedStateForMode()
        }
    }
    
    /// CRITICAL: Refresh camera feed state when switching modes
    func refreshCameraFeedStateForMode() async {
        print("🔄 Refreshing camera feed state for mode switch...")
        
        // Force UI updates for all active feeds
        for feed in cameraFeedManager.activeFeeds {
            print("   - Refreshing feed: \(feed.device.displayName)")
            print("     - Status: \(feed.connectionStatus.displayText)")
            print("     - Has preview: \(feed.previewImage != nil)")
            print("     - Frame count: \(feed.frameCount)")
            
            // Force objectWillChange to trigger UI updates
            feed.objectWillChange.send()
        }
        
        // If there's a selected feed, ensure it's properly connected
        if let selectedFeed = cameraFeedManager.selectedFeedForLiveProduction {
            print("   - Selected feed: \(selectedFeed.device.displayName)")
            print("     - Forcing UI refresh for selected feed")
            selectedFeed.objectWillChange.send()
        }
        
        // Force camera feed manager UI update
        cameraFeedManager.objectWillChange.send()
        
        print("✅ Camera feed state refresh complete")
    }
    
    // MARK: - Computed Properties
    
    var availableVirtualCameras: [VirtualCamera] {
        return studioManager.virtualCameras
    }
    
    var availableLEDWalls: [StudioObject] {
        return studioManager.studioObjects.filter { $0.type == .ledWall }
    }
    
    // MARK: - Initialization
    
    func initialize() async {
        // Initialize both managers
        isVirtualStudioActive = true
        hasUnsavedChanges = false
    }
    
    // MARK: - Studio Management
    
    func loadDefaultStudio() {
        currentStudioName = "Default Studio"
        
        // Load default studio configuration
        let defaultStudio = StudioConfiguration(id: UUID(), name: "Default Studio", description: "Default studio setup", icon: "tv.circle")
        currentStudio = defaultStudio
        availableStudios.append(defaultStudio)
        
        hasUnsavedChanges = false
    }
    
    func loadStudio(_ studio: StudioConfiguration) {
        currentStudioName = studio.name
        
        // Load based on studio type
        switch studio.name {
        case "News Studio":
            loadTemplate(.news)
        case "Talk Show":
            loadTemplate(.talkShow)
        case "Podcast":
            loadTemplate(.podcast)
        case "Concert":
            loadTemplate(.concert)
        case "Product Demo":
            loadTemplate(.productDemo)
        case "Gaming":
            loadTemplate(.gaming)
        default:
            loadTemplate(.custom)
        }
        
        hasUnsavedChanges = false
    }
    
    func switchToVirtualCamera(_ camera: VirtualCamera) {
        studioManager.selectCamera(camera)
        hasUnsavedChanges = true
    }
    
    // MARK: - Templates
    
    enum StudioTemplate: String, CaseIterable, Identifiable {
        case news, talkShow, podcast, concert, productDemo, gaming, custom
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .news:        return "News Studio"
            case .talkShow:    return "Talk Show"
            case .podcast:     return "Podcast Studio"
            case .concert:     return "Concert"
            case .productDemo: return "Product Demo"
            case .gaming:      return "Gaming Setup"
            case .custom:      return "Custom"
            }
        }
    }
    
    func loadTemplate(_ template: StudioTemplate) {
        // Optionally: clear scene first
        // studioManager.clearAll()
        
        switch template {
        case .news:        buildNewsStudio()
        case .talkShow:    buildTalkShowStudio()
        case .podcast:     buildPodcastStudio()
        case .concert:     buildConcertStudio()
        case .productDemo: buildProductDemoStudio()
        case .gaming:      buildGamingStudio()
        case .custom:      break
        }
        currentTemplate = template
    }
    
    // MARK: - Builders
    
    private func buildNewsStudio() {
        if let wall = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Wide") }) {
            studioManager.addLEDWall(from: wall, at: SCNVector3(0, 2, -5))
        }
        if let desk = SetPieceAsset.predefinedPieces.first(where: { $0.name.contains("Desk") }) {
            studioManager.addSetPiece(from: desk, at: SCNVector3(0, 0, -3))
        }
        if let cam1 = CameraAsset.predefinedCameras.first {
            studioManager.addCamera(from: cam1, at: SCNVector3(0, 2, 5))
        }
        if let cam2 = CameraAsset.predefinedCameras.dropFirst().first {
            studioManager.addCamera(from: cam2, at: SCNVector3(3, 2, 2))
        }
    }
    
    private func buildTalkShowStudio() {
        if let wall = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Wide") }) {
            studioManager.addLEDWall(from: wall, at: SCNVector3(0, 2, -6))
        }
        if let sofa = SetPieceAsset.predefinedPieces.first(where: { $0.name.contains("Sofa") }) {
            studioManager.addSetPiece(from: sofa, at: SCNVector3(-1.5, 0, -3))
        }
        if let chair = SetPieceAsset.predefinedPieces.first(where: { $0.name.contains("Chair") }) {
            studioManager.addSetPiece(from: chair, at: SCNVector3(1.2, 0, -3))
        }
        if let camMain = CameraAsset.predefinedCameras.first {
            studioManager.addCamera(from: camMain, at: SCNVector3(0, 2, 5))
        }
        if let camSide = CameraAsset.predefinedCameras.dropFirst().first {
            studioManager.addCamera(from: camSide, at: SCNVector3(4, 2, 1))
        }
    }
    
    private func buildPodcastStudio() {
        if let wall = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Standard") }) {
            studioManager.addLEDWall(from: wall, at: SCNVector3(0, 1.5, -3))
        }
        if let table = SetPieceAsset.predefinedPieces.first(where: { $0.name.contains("Table") }) {
            studioManager.addSetPiece(from: table, at: SCNVector3(0, 0, -2))
        }
        if let chair = SetPieceAsset.predefinedPieces.first(where: { $0.name.contains("Chair") }) {
            studioManager.addSetPiece(from: chair, at: SCNVector3(-0.8, 0, -2.2))
            studioManager.addSetPiece(from: chair, at: SCNVector3(0.8, 0, -2.2))
        }
        if let camWide = CameraAsset.predefinedCameras.first {
            studioManager.addCamera(from: camWide, at: SCNVector3(0, 1.8, 3.5))
        }
        if let camClose = CameraAsset.predefinedCameras.dropFirst().first {
            studioManager.addCamera(from: camClose, at: SCNVector3(2.5, 1.8, 1))
        }
    }
    
    private func buildConcertStudio() {
        if let back = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Massive") || $0.name.contains("Wide") }) {
            studioManager.addLEDWall(from: back, at: SCNVector3(0, 4, -10))
        }
        if let side = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Tall") }) {
            studioManager.addLEDWall(from: side, at: SCNVector3(-6, 3, -9))
            studioManager.addLEDWall(from: side, at: SCNVector3( 6, 3, -9))
        }
        if let stage = SetPieceAsset.predefinedPieces.first(where: { $0.name.contains("Stage") || $0.name.contains("Platform") }) {
            studioManager.addSetPiece(from: stage, at: SCNVector3(0, 0, -6))
        }
        if let camWide = CameraAsset.predefinedCameras.first {
            studioManager.addCamera(from: camWide, at: SCNVector3(0, 3, 12))
        }
        if let camClose = CameraAsset.predefinedCameras.dropFirst().first {
            studioManager.addCamera(from: camClose, at: SCNVector3(2, 2.5, 4))
        }
        if let camSide = CameraAsset.predefinedCameras.dropFirst(2).first {
            studioManager.addCamera(from: camSide, at: SCNVector3(-6, 2.5, 2))
        }
    }
    
    private func buildProductDemoStudio() {
        if let wall = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Standard") }) {
            studioManager.addLEDWall(from: wall, at: SCNVector3(0, 2, -4))
        }
        if let podium = SetPieceAsset.predefinedPieces.first(where: { $0.name.contains("Podium") }) {
            studioManager.addSetPiece(from: podium, at: SCNVector3(0, 0, -2.2))
        }
        if let cam = CameraAsset.predefinedCameras.first {
            studioManager.addCamera(from: cam, at: SCNVector3(0, 1.8, 3))
        }
    }
    
    private func buildGamingStudio() {
        if let wall = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Wide") }) {
            studioManager.addLEDWall(from: wall, at: SCNVector3(0, 2.2, -5))
        }
        if let desk = SetPieceAsset.predefinedPieces.first(where: { $0.name.contains("Desk") }) {
            studioManager.addSetPiece(from: desk, at: SCNVector3(0, 0, -2.5))
        }
        if let chair = SetPieceAsset.predefinedPieces.first(where: { $0.name.contains("Chair") }) {
            studioManager.addSetPiece(from: chair, at: SCNVector3(0, 0, -2.8))
        }
        if let camFront = CameraAsset.predefinedCameras.first {
            studioManager.addCamera(from: camFront, at: SCNVector3(0, 1.6, 3))
        }
        if let camSide = CameraAsset.predefinedCameras.dropFirst().first {
            studioManager.addCamera(from: camSide, at: SCNVector3(3, 1.6, 0))
        }
    }
    
    // MARK: - Virtual Live (stub)
    func saveCurrentStudioState() { /* persist if needed */ }
    func syncVirtualToLive() { /* push to streamingViewModel */ }
    func setVirtualCameraActive(_ cam: VirtualCamera) {
        studioManager.selectCamera(cam)
        // streamingViewModel.switchToVirtual(cam)
    }
}

// MARK: - Supporting Types

struct StudioConfiguration: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let icon: String
}