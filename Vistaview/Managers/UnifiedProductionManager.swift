import Foundation
import SwiftUI
import Combine

@MainActor
class UnifiedProductionManager: ObservableObject {
    // Core Managers (using your existing ones)
    let streamingViewModel = StreamingViewModel()
    let studioManager = VirtualStudioManager()
    
    // Simple Studio Management
    @Published var currentStudioName = "Default Studio"
    @Published var availableStudios: [SimpleStudio] = []
    @Published var hasUnsavedChanges = false
    
    // Integration State
    @Published var isVirtualStudioActive = false
    @Published var availableVirtualCameras: [VirtualCamera] = []
    @Published var availableLEDWalls: [StudioObject] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupAvailableStudios()
        setupIntegration()
    }
    
    // MARK: - Initialization
    
    func initialize() async {
        await streamingViewModel.setupCamera()
        loadDefaultStudio()
    }
    
    private func setupAvailableStudios() {
        availableStudios = [
            SimpleStudio(
                name: "News Studio",
                description: "Professional news broadcast setup",
                icon: "newspaper"
            ),
            SimpleStudio(
                name: "Talk Show",
                description: "Casual interview environment",
                icon: "person.2.wave.2"
            ),
            SimpleStudio(
                name: "Podcast Studio",
                description: "Intimate conversation setup",
                icon: "mic.fill"
            ),
            SimpleStudio(
                name: "Concert",
                description: "Epic live music stage with LED backdrop",
                icon: "music.mic"
            ),
            SimpleStudio(
                name: "Product Demo",
                description: "Clean product showcase space",
                icon: "cube.box"
            ),
            SimpleStudio(
                name: "Gaming Setup",
                description: "High-energy gaming environment",
                icon: "gamecontroller"
            ),
            SimpleStudio(
                name: "Custom Studio",
                description: "Build your own custom setup",
                icon: "paintbrush"
            )
        ]
        
        currentStudioName = availableStudios[0].name
    }
    
    private func setupIntegration() {
        // Monitor virtual camera changes
        studioManager.$virtualCameras
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cameras in
                self?.availableVirtualCameras = cameras
                self?.updateVirtualStudioStatus()
            }
            .store(in: &cancellables)
        
        // Monitor studio object changes
        studioManager.$studioObjects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] objects in
                self?.availableLEDWalls = objects.filter { $0.type == .ledWall }
                self?.updateVirtualStudioStatus()
                self?.hasUnsavedChanges = true
            }
            .store(in: &cancellables)
    }
    
    private func updateVirtualStudioStatus() {
        isVirtualStudioActive = !availableVirtualCameras.isEmpty || !availableLEDWalls.isEmpty
    }
    
    // MARK: - Studio Management
    
    func loadStudio(_ studio: SimpleStudio) {
        currentStudioName = studio.name
        
        // Load studio template
        loadStudioTemplate(studio.name)
        
        // Sync to live production
        syncVirtualToLive()
        
        hasUnsavedChanges = false
    }
    
    private func loadDefaultStudio() {
        guard let defaultStudio = availableStudios.first else { return }
        loadStudio(defaultStudio)
    }
    
    private func loadStudioTemplate(_ templateName: String) {
        // Clear existing studio (simplified)
        clearCurrentStudio()
        
        switch templateName {
        case "News Studio":
            createNewsStudioTemplate()
        case "Talk Show":
            createTalkShowTemplate()
        case "Podcast Studio":
            createPodcastStudioTemplate()
        case "Concert":
            createConcertTemplate()
        case "Product Demo":
            createProductDemoTemplate()
        case "Gaming Setup":
            createGamingTemplate()
        default:
            // Custom - start empty
            break
        }
    }
    
    // MARK: - Studio Templates (simplified)
    
    private func createNewsStudioTemplate() {
        // Add main LED wall
        if let ledWallAsset = LEDWallAsset.predefinedWalls.first {
            studioManager.addLEDWall(from: ledWallAsset)
        }
        
        // Add main camera
        if let cameraAsset = CameraAsset.predefinedCameras.first {
            studioManager.addCamera(from: cameraAsset)
        }
        
        // Add desk set piece
        if let deskAsset = SetPieceAsset.predefinedPieces.first(where: { $0.name == "Desk" }) {
            studioManager.addSetPiece(from: deskAsset)
        }
    }
    
    private func createTalkShowTemplate() {
        // Add wide LED wall
        if let ledWallAsset = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Wide") }) {
            studioManager.addLEDWall(from: ledWallAsset)
        }
        
        // Add multiple cameras
        let cameraAssets = Array(CameraAsset.predefinedCameras.prefix(2))
        for asset in cameraAssets {
            studioManager.addCamera(from: asset)
        }
    }
    
    private func createPodcastStudioTemplate() {
        // Add compact LED backdrop for branding
        if let ledWallAsset = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Standard") }) {
            studioManager.addLEDWall(from: ledWallAsset)
        }
        
        // Add podcast table/desk setup
        if let desk = SetPieceAsset.predefinedPieces.first(where: { $0.name == "Desk" }) {
            studioManager.addSetPiece(from: desk)
        }
        
        // Add chairs for host and guests
        if let chair = SetPieceAsset.predefinedPieces.first(where: { $0.name == "Chair" }) {
            studioManager.addSetPiece(from: chair) // Host chair
            studioManager.addSetPiece(from: chair) // Guest chair
        }
        
        // Add decorative plant for cozy atmosphere
        if let plant = SetPieceAsset.predefinedPieces.first(where: { $0.name == "Plant" }) {
            studioManager.addSetPiece(from: plant)
        }
        
        // Add focused cameras for podcast recording
        let podcastCameras = [
            CameraAsset.predefinedCameras.first(where: { $0.name == "Camera 1" }), // Wide shot of both hosts
            CameraAsset.predefinedCameras.first(where: { $0.name == "Camera 2" })  // Close-up switching camera
        ]
        
        for cameraAsset in podcastCameras {
            if let asset = cameraAsset {
                studioManager.addCamera(from: asset)
            }
        }
    }
    
    private func createConcertTemplate() {
        // Add massive LED backdrop wall
        if let backdropWall = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Massive") }) {
            studioManager.addLEDWall(from: backdropWall)
        }
        
        // Add side LED walls for immersive environment
        if let sideWall = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Tall") }) {
            studioManager.addLEDWall(from: sideWall)
        }
        
        // Add main stage/platform
        if let stage = SetPieceAsset.predefinedPieces.first(where: { $0.name == "Backdrop" }) {
            studioManager.addSetPiece(from: stage)
        }
        
        // Add truss for stage lighting
        if let truss = SetPieceAsset.predefinedPieces.first(where: { $0.name == "Truss" }) {
            studioManager.addSetPiece(from: truss)
        }
        
        // Add multiple cameras for concert coverage
        let concertCameras = [
            CameraAsset.predefinedCameras.first(where: { $0.name == "Camera 1" }), // Main wide shot
            CameraAsset.predefinedCameras.first(where: { $0.name == "Camera 2" }), // Close-up
            CameraAsset.predefinedCameras.first(where: { $0.name == "Camera 3" })  // Side angle
        ]
        
        for cameraAsset in concertCameras {
            if let asset = cameraAsset {
                studioManager.addCamera(from: asset)
            }
        }
    }
    
    private func createProductDemoTemplate() {
        // Add standard LED wall
        if let ledWallAsset = LEDWallAsset.predefinedWalls.first(where: { $0.name.contains("Standard") }) {
            studioManager.addLEDWall(from: ledWallAsset)
        }
        
        // Add camera
        if let cameraAsset = CameraAsset.predefinedCameras.first {
            studioManager.addCamera(from: cameraAsset)
        }
    }
    
    private func createGamingTemplate() {
        // Add large LED wall
        if let ledWallAsset = LEDWallAsset.predefinedWalls.last {
            studioManager.addLEDWall(from: ledWallAsset)
        }
        
        // Add camera
        if let cameraAsset = CameraAsset.predefinedCameras.first {
            studioManager.addCamera(from: cameraAsset)
        }
    }
    
    // MARK: - Virtual-Live Integration
    
    func syncVirtualToLive() {
        // Update available sources in streaming
        // For now, just trigger UI updates
        objectWillChange.send()
        hasUnsavedChanges = false
    }
    
    func saveCurrentStudioState() {
        // Save current virtual studio state
        hasUnsavedChanges = false
    }
    
    // MARK: - Virtual Camera Integration
    
    func selectVirtualCamera(_ camera: VirtualCamera) {
        // Deactivate all cameras first
        for cam in availableVirtualCameras {
            cam.isActive = false
        }
        
        // Activate selected camera
        camera.isActive = true
        
        objectWillChange.send()
    }
    
    // MARK: - Utility Methods
    
    func clearCurrentStudio() {
        // Remove all objects from studio
        for object in studioManager.studioObjects {
            object.node.removeFromParentNode()
        }
        studioManager.studioObjects.removeAll()
        
        // Keep only the default overview camera
        let defaultCamera = studioManager.virtualCameras.first
        for camera in studioManager.virtualCameras {
            if camera != defaultCamera {
                camera.node.removeFromParentNode()
            }
        }
        if let defaultCam = defaultCamera {
            studioManager.virtualCameras = [defaultCam]
        }
        
        hasUnsavedChanges = true
    }
    
    func exportCurrentStudio() {
        studioManager.exportScene()
    }
    
    func importStudio() {
        studioManager.importScene()
        hasUnsavedChanges = true
    }
}

// MARK: - Simple Data Models

struct SimpleStudio: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
}

// MARK: - Make VirtualCamera Equatable

extension VirtualCamera: Equatable {
    static func == (lhs: VirtualCamera, rhs: VirtualCamera) -> Bool {
        return lhs.id == rhs.id
    }
}
