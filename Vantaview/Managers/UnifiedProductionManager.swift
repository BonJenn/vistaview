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
    // Core Dependencies - now using actors for heavy lifting
    let streamingViewModel: StreamingViewModel
    let studioManager: VirtualStudioManager
    let cameraFeedManager: CameraFeedManager
    let effectManager: EffectManager
    let outputMappingManager: OutputMappingManager
    let externalDisplayManager: ExternalDisplayManager
    
    // Background processing actors
    let frameProcessor: FrameProcessor
    let audioEngine: AudioEngine
    let deviceManager: DeviceManager
    let streamingEngine: StreamingEngine
    
    // Preview/Program Manager - lazy initialized to avoid circular dependencies
    private var _previewProgramManager: PreviewProgramManager?
    var previewProgramManager: PreviewProgramManager {
        if _previewProgramManager == nil {
            _previewProgramManager = PreviewProgramManager(
                cameraFeedManager: cameraFeedManager,
                unifiedProductionManager: self,
                effectManager: effectManager,
                frameProcessor: frameProcessor,
                audioEngine: audioEngine
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
    
    // MARK: - Live Camera Flow (Program/Preview) - now async
    @Published var selectedProgramCameraID: String?
    @Published var selectedPreviewCameraID: String? {
        didSet { 
            Task { await ensurePreviewRunning() }
        }
    }
    
    // Background processing tasks
    private var programProcessingTask: Task<Void, Never>?
    private var previewProcessingTask: Task<Void, Never>?
    
    // Expose current textures for UI (updated via background processing)
    @Published var previewCurrentTexture: MTLTexture?
    @Published var programCurrentTexture: MTLTexture?
    
    init(studioManager: VirtualStudioManager? = nil,
         cameraFeedManager: CameraFeedManager? = nil) async throws {
        self.studioManager = studioManager ?? VirtualStudioManager()
        
        // Create shared device manager and feed manager
        self.deviceManager = try await DeviceManager()
        self.cameraFeedManager = cameraFeedManager ?? CameraFeedManager(deviceManager: deviceManager)
        
        // Create processing actors
        let metalDevice = MTLCreateSystemDefaultDevice()!
        self.effectManager = EffectManager()
        self.frameProcessor = try await FrameProcessor(device: metalDevice, effectManager: effectManager)
        self.audioEngine = try await AudioEngine()
        self.streamingEngine = await StreamingEngine()
        
        self.streamingViewModel = StreamingViewModel(streamingEngine: streamingEngine, audioEngine: audioEngine)
        
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
    
    // MARK: - Program switching and binding - now async
    
    func switchProgram(to cameraID: String) async {
        selectedProgramCameraID = cameraID
        await ensureProgramRunning()
    }
    
    private func ensureProgramRunning() async {
        guard let cameraID = selectedProgramCameraID else { return }
        
        // Cancel any existing processing
        programProcessingTask?.cancel()
        
        // Start new processing task
        programProcessingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            do {
                try Task.checkCancellation()
                
                // Create camera capture session through device manager
                let captureSession = try await self.deviceManager.createCameraCaptureSession(for: cameraID)
                
                // Create frame processing stream
                let processingStream = await self.frameProcessor.createFrameStream(
                    for: "program",
                    effectChain: self.effectManager.getProgramEffectChain()
                )
                
                // Process frames from camera
                let sampleBufferStream = await captureSession.sampleBuffers()
                
                for await sampleBuffer in sampleBufferStream {
                    if Task.isCancelled { break }
                    
                    // Extract pixel buffer and submit for processing
                    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        try await self.frameProcessor.submitFrame(pixelBuffer, for: "program", timestamp: timestamp)
                    }
                }
                
                // Update UI with processed frames
                for await result in processingStream {
                    if Task.isCancelled { break }
                    
                    await MainActor.run {
                        self.programCurrentTexture = result.outputTexture
                        self.objectWillChange.send()
                    }
                }
                
            } catch is CancellationError {
                await MainActor.run { self.log("Program capture cancelled") }
            } catch {
                await MainActor.run { self.log("Program capture failed: \(error.localizedDescription)") }
            }
        }
    }
    
    // MARK: - Preview switching/binding - now async
    
    private func ensurePreviewRunning() async {
        guard let cameraID = selectedPreviewCameraID else { return }
        
        // Cancel existing processing
        previewProcessingTask?.cancel()
        
        // Start new processing task
        previewProcessingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            do {
                try Task.checkCancellation()
                
                // Create camera capture session through device manager
                let captureSession = try await self.deviceManager.createCameraCaptureSession(for: cameraID)
                
                // Create frame processing stream with preview effects
                let processingStream = await self.frameProcessor.createFrameStream(
                    for: "preview",
                    effectChain: self.effectManager.getPreviewEffectChain()
                )
                
                // Process frames from camera
                let sampleBufferStream = await captureSession.sampleBuffers()
                
                for await sampleBuffer in sampleBufferStream {
                    if Task.isCancelled { break }
                    
                    // Extract pixel buffer and submit for processing
                    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        try await self.frameProcessor.submitFrame(pixelBuffer, for: "preview", timestamp: timestamp)
                    }
                }
                
                // Update UI with processed frames
                for await result in processingStream {
                    if Task.isCancelled { break }
                    
                    await MainActor.run {
                        self.previewCurrentTexture = result.outputTexture
                        self.objectWillChange.send()
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
    
    // MARK: - Mode Switching with State Management - now async
    
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
        // Use device manager to refresh camera states
        do {
            let (cameras, _) = try await deviceManager.discoverDevices(forceRefresh: true)
            await MainActor.run {
                // Update UI with refreshed camera information
                self.objectWillChange.send()
            }
        } catch {
            log("Failed to refresh camera devices: \(error)")
        }
    }
    
    // MARK: - Computed Properties
    
    var availableVirtualCameras: [VirtualCamera] {
        return studioManager.virtualCameras
    }
    
    var availableLEDWalls: [StudioObject] {
        return studioManager.studioObjects.filter { $0.type == .ledWall }
    }
    
    // MARK: - Initialization - now async
    
    func initialize() async {
        isVirtualStudioActive = true
        hasUnsavedChanges = false
        
        // Initialize background processing
        do {
            // Set up device monitoring
            let deviceChangeStream = await deviceManager.deviceChangeNotifications()
            Task {
                for await change in deviceChangeStream {
                    await self.handleDeviceChange(change)
                }
            }
            
            // Initialize audio engine
            _ = try await audioEngine.startMicrophoneCapture()
            
        } catch {
            log("Failed to initialize background systems: \(error)")
        }
    }
    
    // MARK: - Device Change Handling
    
    private func handleDeviceChange(_ change: DeviceChangeNotification) async {
        await MainActor.run {
            switch change.changeType {
            case .added(let device):
                self.log("Camera device added: \(device.displayName)")
            case .removed(let deviceID):
                self.log("Camera device removed: \(deviceID)")
                // Update UI if the removed device was selected
                if self.selectedProgramCameraID == deviceID {
                    self.selectedProgramCameraID = nil
                    self.programCurrentTexture = nil
                }
                if self.selectedPreviewCameraID == deviceID {
                    self.selectedPreviewCameraID = nil
                    self.previewCurrentTexture = nil
                }
            case .configurationChanged(let device):
                self.log("Camera device configuration changed: \(device.displayName)")
            }
            
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Studio Management (unchanged)
    
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
    
    // MARK: - Templates (unchanged)
    
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
    
    // MARK: - Template Building Methods (unchanged for brevity)
    
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