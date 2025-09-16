//
//  UnifiedProductionManager.swift
//  Vantaview
//

import Foundation
import SwiftUI
import SceneKit
import Metal
import AVFoundation

@MainActor
final class UnifiedProductionManager: ObservableObject {
    // Core Dependencies
    let streamingViewModel: StreamingViewModel
    let studioManager: VirtualStudioManager
    let cameraFeedManager: CameraFeedManager
    let effectManager: EffectManager
    let outputMappingManager: OutputMappingManager
    let externalDisplayManager: ExternalDisplayManager
    
    // Preview/Program Manager - lazy initialized to avoid circular dependencies
    private var _previewProgramManager: PreviewProgramManager?
    var previewProgramManager: PreviewProgramManager {
        if _previewProgramManager == nil {
            _previewProgramManager = PreviewProgramManager(
                cameraFeedManager: cameraFeedManager,
                unifiedProductionManager: self,
                effectManager: effectManager
            )
        }
        return _previewProgramManager!
    }
    
    // Published States
    @Published var currentStudioName: String = "Default Studio"
    @Published var hasUnsavedChanges: Bool = false
    @Published var isVirtualStudioActive: Bool = false
    
    // Studio Management
    @Published var availableStudios: [StudioConfiguration] = []
    @Published var currentStudio: StudioConfiguration?
    @Published var currentTemplate: StudioTemplate = .custom
    
    // Add media thumbnail manager
    let mediaThumbnailManager = MediaThumbnailManager()
    
    // MARK: - Live Camera Flow (Program/Preview)
    @Published var selectedProgramCameraID: String?
    @Published var selectedPreviewCameraID: String? {
        didSet { ensurePreviewRunning() }
    }
    
    private var programRenderer: VideoRenderable?
    private var programCapture: CameraCaptureSession?
    private var programFramesTask: Task<Void, Never>?
    
    // Preview pipeline
    private var previewRenderer: VideoRenderable?
    private var previewCapture: CameraCaptureSession?
    private var previewFramesTask: Task<Void, Never>?
    
    // Expose textures for views
    var previewCurrentTexture: MTLTexture? {
        previewRenderer?.currentTexture
    }
    
    init(studioManager: VirtualStudioManager? = nil,
         cameraFeedManager: CameraFeedManager? = nil) {
        self.studioManager = studioManager ?? VirtualStudioManager()
        
        // Create shared camera device manager and feed manager
        let deviceManager = CameraDeviceManager()
        self.cameraFeedManager = cameraFeedManager ?? CameraFeedManager(cameraDeviceManager: deviceManager)
        
        self.streamingViewModel = StreamingViewModel()
        self.effectManager = EffectManager()
        
        // Initialize output mapping manager with the same Metal device as effects
        self.outputMappingManager = OutputMappingManager(metalDevice: effectManager.metalDevice)
        
        // Initialize external display manager
        self.externalDisplayManager = ExternalDisplayManager()
        
        // Set up bidirectional integration
        setupIntegration()
        
        // Initialize with default studio
        loadDefaultStudio()
    }
    
    private func setupIntegration() {
        cameraFeedManager.setStreamingViewModel(streamingViewModel)
        externalDisplayManager.setProductionManager(self)
    }
    
    // MARK: - Program switching and binding
    
    func switchProgram(to cameraID: String) {
        selectedProgramCameraID = cameraID
        ensureProgramRunning()
    }
    
    func bindProgramOutput(to renderer: VideoRenderable) {
        programRenderer = renderer
        ensureProgramRunning()
    }
    
    func rebindProgram(to cameraID: String?, renderer: VideoRenderable) {
        programRenderer = renderer
        selectedProgramCameraID = cameraID
        ensureProgramRunning()
    }
    
    func ensureProgramRunning() {
        guard let cameraID = selectedProgramCameraID else { return }
        
        // Cancel any existing stream consumption
        programFramesTask?.cancel()
        programFramesTask = nil
        
        // Start/Restart capture off the main actor to avoid blocking UI
        let capture = programCapture ?? CameraCaptureSession()
        programCapture = capture
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                try await capture.start(cameraID: cameraID)
                
                await MainActor.run {
                    self.log("Program capture started for cameraID=\(cameraID)")
                }
                
                let stream = await capture.sampleBuffers()
                let renderer = await MainActor.run { self.programRenderer }
                
                await MainActor.run {
                    // Consume frames on a child task bound to manager lifetime
                    self.programFramesTask?.cancel()
                    self.programFramesTask = Task(priority: .userInitiated) {
                        var gotFirst = false
                        let firstDeadline = ContinuousClock.now.advanced(by: .milliseconds(500))
                        
                        for await sb in stream {
                            if Task.isCancelled { break }
                            if let pb = CMSampleBufferGetImageBuffer(sb) {
                                renderer?.push(pb)
                            }
                            if !gotFirst {
                                gotFirst = true
                                self.log("Program first frame received")
                            }
                            
                            if !gotFirst && ContinuousClock.now > firstDeadline {
                                self.log("Warning: No program frames within 500 ms after switch")
                            }
                        }
                    }
                }
            } catch is CancellationError {
                await MainActor.run { self.log("Program capture cancelled") }
            } catch {
                await MainActor.run { self.log("Program capture failed: \(error.localizedDescription)") }
            }
        }
    }
    
    // MARK: - Preview switching/binding for live camera
    
    func ensurePreviewRunning() {
        guard let cameraID = selectedPreviewCameraID else { return }
        
        // Cancel existing
        previewFramesTask?.cancel()
        previewFramesTask = nil
        
        // Create capture
        let capture = previewCapture ?? CameraCaptureSession()
        previewCapture = capture
        
        // Ensure we have a renderer to push into
        if previewRenderer == nil {
            if let device = MTLCreateSystemDefaultDevice() {
                previewRenderer = ProgramRenderer(device: device)
            }
        }
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                try await capture.start(cameraID: cameraID)
                
                await MainActor.run {
                    self.log("Preview capture started for cameraID=\(cameraID)")
                }
                
                let stream = await capture.sampleBuffers()
                let renderer = await MainActor.run { self.previewRenderer }
                
                await MainActor.run {
                    self.previewFramesTask?.cancel()
                    self.previewFramesTask = Task(priority: .userInitiated) {
                        var gotFirst = false
                        let firstDeadline = ContinuousClock.now.advanced(by: .milliseconds(500))
                        
                        for await sb in stream {
                            if Task.isCancelled { break }
                            if let pb = CMSampleBufferGetImageBuffer(sb) {
                                renderer?.push(pb)
                            }
                            if !gotFirst {
                                gotFirst = true
                                self.log("Preview first frame received")
                            }
                            
                            if !gotFirst && ContinuousClock.now > firstDeadline {
                                self.log("Warning: No preview frames within 500 ms after switch")
                            }
                        }
                    }
                }
            } catch is CancellationError {
                await MainActor.run { self.log("Preview capture cancelled") }
            } catch {
                await MainActor.run { self.log("Preview capture failed: \(error.localizedDescription)") }
            }
        }
    }
    
    func routeProgramToPreview() {
        selectedPreviewCameraID = selectedProgramCameraID
    }
    
    func log(_ msg: String) {
        print("🎥 [UnifiedProductionManager] \(msg)")
    }
    
    // MARK: - Mode Switching with State Management
    
    func switchToVirtualMode() {
        isVirtualStudioActive = true
        Task {
            await refreshCameraFeedStateForMode()
        }
    }
    
    func switchToLiveMode() {
        syncVirtualToLive()
        Task {
            await refreshCameraFeedStateForMode()
        }
    }
    
    func refreshCameraFeedStateForMode() async {
        for feed in cameraFeedManager.activeFeeds {
            feed.objectWillChange.send()
        }
        cameraFeedManager.objectWillChange.send()
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
        isVirtualStudioActive = true
        hasUnsavedChanges = false
    }
    
    // MARK: - Studio Management
    
    func loadDefaultStudio() {
        currentStudioName = "Default Studio"
        let defaultStudio = StudioConfiguration(id: UUID(), name: "Default Studio", description: "Default studio setup", icon: "tv.circle")
        currentStudio = defaultStudio
        availableStudios.append(defaultStudio)
        hasUnsavedChanges = false
    }
    
    func loadStudio(_ studio: StudioConfiguration) {
        currentStudioName = studio.name
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
    func saveCurrentStudioState() { }
    func syncVirtualToLive() { }
    func setVirtualCameraActive(_ cam: VirtualCamera) {
        studioManager.selectCamera(cam)
    }
}

// MARK: - Supporting Types

struct StudioConfiguration: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let icon: String
}