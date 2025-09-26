//
//  UnifiedProductionManager.swift
//  Vantaview
//

import Foundation
import SwiftUI
import SceneKit
import Metal
import AVFoundation
import os

@MainActor
final class UnifiedProductionManager: ObservableObject {
    private static let log = OSLog(subsystem: "com.vantaview", category: "UnifiedProductionManager")
    
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
    
    private var recordingSink: RecordingSink?
    private var programRecordingTask: Task<Void, Never>?
    private var textureConverter: TextureToSampleBufferConverter?
    
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
    
    // Audio processing tasks
    private var programAudioTask: Task<Void, Never>?
    
    // Expose current textures for UI (updated via background processing)
    @Published var previewCurrentTexture: MTLTexture?
    @Published var programCurrentTexture: MTLTexture?
    
    @Published var isProgramActive: Bool = false
    
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
        
        os_log(.info, log: Self.log, "🎥 UnifiedProductionManager initialized with recording support")
    }
    
    private func setupIntegration() {
        cameraFeedManager.setStreamingViewModel(streamingViewModel)
        externalDisplayManager.setProductionManager(self)
    }
    
    func connectRecordingSink(_ sink: RecordingSink) async {
        os_log(.info, log: Self.log, "🎬 Connecting recording sink...")
        os_log(.info, log: Self.log, "🎬 Current program state - isProgramActive: %{public}@, selectedProgramCameraID: %{public}@", 
               isProgramActive ? "YES" : "NO", 
               selectedProgramCameraID ?? "NONE")
        
        await stopProgramRecording()  // Stop any existing recording pipeline
        
        self.recordingSink = sink
        
        // Initialize texture converter
        do {
            self.textureConverter = try TextureToSampleBufferConverter(device: effectManager.metalDevice)
            os_log(.info, log: Self.log, "🎬 Texture converter initialized successfully")
        } catch {
            os_log(.error, log: Self.log, "🎬 Failed to initialize texture converter: %{public}@", error.localizedDescription)
            return // Don't continue if converter fails
        }
        
        // Start program recording pipeline if program is active
        if isProgramActive {
            os_log(.info, log: Self.log, "🎬 Program is active, starting recording pipeline")
            await startProgramRecording()
        } else {
            os_log(.info, log: Self.log, "🎬 Program is not active, recording pipeline will start when program becomes active")
        }
        
        os_log(.info, log: Self.log, "🎬 Recording sink connected successfully")
    }
    
    func disconnectRecordingSink() async {
        os_log(.info, log: Self.log, "🎬 Disconnecting recording sink...")
        await stopProgramRecording()
        self.recordingSink = nil
        os_log(.info, log: Self.log, "🎬 Recording sink disconnected")
    }
    
    private func startProgramRecording() async {
        guard let sink = recordingSink else {
            os_log(.default, log: Self.log, "🎬 Cannot start recording - missing sink")
            return
        }
        
        guard let converter = textureConverter else {
            os_log(.error, log: Self.log, "🎬 Cannot start recording - missing texture converter")
            return
        }
        
        await stopProgramRecording()  // Stop any existing task
        
        os_log(.info, log: Self.log, "🎬 Creating recording streams...")
        
        programRecordingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            os_log(.info, log: Self.log, "🎬 Started program recording pipeline task")
            
            // Create a processing stream for recording
            let recordingStream = await self.frameProcessor.createFrameStream(
                for: "program_recording",
                effectChain: self.effectManager.getProgramEffectChain()
            )
            
            // Audio recording stream for program
            let audioRecordingStream = await self.audioEngine.createAudioStream(for: "program_recording")
            
            os_log(.info, log: Self.log, "🎬 Recording streams created, starting processing...")
            
            // Process video frames
            Task {
                var videoFrameCount: Int64 = 0
                var startTime: CMTime?
                
                os_log(.info, log: Self.log, "🎬 Starting video frame processing loop")
                
                for await result in recordingStream {
                    if Task.isCancelled { 
                        os_log(.info, log: Self.log, "🎬 Video processing task cancelled")
                        break 
                    }
                    
                    guard let texture = result.outputTexture else { 
                        os_log(.debug, log: Self.log, "🎬 Recording: Received nil texture (frame %lld)", videoFrameCount)
                        continue 
                    }
                    
                    if videoFrameCount == 0 {
                        os_log(.info, log: Self.log, "🎬 Recording: First video frame received - %dx%d", texture.width, texture.height)
                    }
                    
                    do {
                        // Use a more consistent timestamp approach
                        let frameTimestamp: CMTime
                        if startTime == nil {
                            startTime = CMClockGetTime(CMClockGetHostTimeClock())
                            os_log(.info, log: Self.log, "🎬 Recording: Started video timestamp tracking")
                        }
                        // Generate sequential timestamps at 30fps
                        let frameTime = CMTime(value: videoFrameCount, timescale: 30)
                        frameTimestamp = CMTimeAdd(startTime!, frameTime)
                        
                        // Convert texture to sample buffer with proper timing
                        let sampleBuffer = try await converter.convertTexture(
                            texture,
                            timestamp: frameTimestamp,
                            duration: CMTime(value: 1, timescale: 30)
                        )
                        
                        // Send to recording sink
                        sink.appendVideo(sampleBuffer)
                        
                        videoFrameCount += 1
                        if videoFrameCount % 30 == 0 {  // Log every 30 frames (1 second at 30fps)
                            let elapsed = frameTimestamp.seconds - (startTime?.seconds ?? 0)
                            os_log(.info, log: Self.log, "🎬 Recording: %lld video frames processed (%.1fs elapsed)", videoFrameCount, elapsed)
                        }
                        
                    } catch {
                        os_log(.error, log: Self.log, "🎬 Video recording conversion error: %{public}@", error.localizedDescription)
                    }
                }
                os_log(.info, log: Self.log, "🎬 Video recording processing ended after %lld frames", videoFrameCount)
            }
            
            // Process audio buffers
            Task {
                var audioFrameCount: Int64 = 0
                os_log(.info, log: Self.log, "🎬 Starting audio frame processing loop")
                
                for await result in audioRecordingStream {
                    if Task.isCancelled { 
                        os_log(.info, log: Self.log, "🎬 Audio processing task cancelled")
                        break 
                    }
                    
                    guard let audioBuffer = result.outputBuffer else { 
                        os_log(.debug, log: Self.log, "🎬 Recording: Received nil audio buffer (frame %lld)", audioFrameCount)
                        continue 
                    }
                    
                    if audioFrameCount == 0 {
                        os_log(.info, log: Self.log, "🎬 Recording: First audio frame received")
                    }
                    
                    // Send audio to recording sink
                    sink.appendAudio(audioBuffer)
                    
                    audioFrameCount += 1
                    if audioFrameCount % 100 == 0 {  // Log every 100 audio frames
                        os_log(.info, log: Self.log, "🎬 Recording: %lld audio frames processed", audioFrameCount)
                    }
                }
                os_log(.info, log: Self.log, "🎬 Audio recording processing ended after %lld frames", audioFrameCount)
            }
            
            os_log(.info, log: Self.log, "🎬 Program recording pipeline ended")
        }
        
        os_log(.info, log: Self.log, "🎬 Program recording pipeline task created")
    }
    
    private func stopProgramRecording() async {
        programRecordingTask?.cancel()
        programRecordingTask = nil
        
        // Stop the recording processing stream
        await frameProcessor.stopFrameStream(for: "program_recording")
        await audioEngine.stopAudioStream(for: "program_recording")
    }
    
    // MARK: - Program switching and binding - now async
    
    func switchProgram(to cameraID: String) async {
        os_log(.info, log: Self.log, "🎥 SWITCH PROGRAM REQUEST: %{public}@", cameraID)
        
        // Only switch if it's actually a different camera
        if selectedProgramCameraID == cameraID {
            os_log(.info, log: Self.log, "🎥 Program already using this camera, no switch needed")
            return
        }
        
        selectedProgramCameraID = cameraID
        await ensureProgramRunning()
    }
    
    private func ensureProgramRunning() async {
        guard let cameraID = selectedProgramCameraID else {
            os_log(.info, log: Self.log, "🎥 No program camera selected, setting inactive")
            await setProgramActive(false)
            return
        }
        
        os_log(.info, log: Self.log, "🎥 ENSURE PROGRAM RUNNING for camera: %{public}@", cameraID)
        
        // CRITICAL FIX: Don't cancel if we're just switching cameras during recording
        // Only cancel if we're actually stopping the program entirely
        if recordingSink != nil {
            os_log(.info, log: Self.log, "🎬 Recording active - gracefully switching camera without cancelling")
        } else {
            // Cancel any existing processing task only if not recording
            programProcessingTask?.cancel()
        }
        
        await setProgramActive(true)
        
        // Start video processing task
        programProcessingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            do {
                try Task.checkCancellation()
                
                os_log(.info, log: Self.log, "🎥 CREATING camera capture session for program")
                
                // Create camera capture session through device manager
                let captureSession = try await self.deviceManager.createCameraCaptureSession(for: cameraID)
                
                // Create frame processing stream
                let processingStream = await self.frameProcessor.createFrameStream(
                    for: "program",
                    effectChain: self.effectManager.getProgramEffectChain()
                )
                
                os_log(.info, log: Self.log, "🎥 PROGRAM PROCESSING STREAMS CREATED SUCCESSFULLY")
                
                // Process frames from camera
                let sampleBufferStream = await captureSession.sampleBuffers()
                
                // Submit frames to processor
                Task {
                    var frameCount: Int64 = 0
                    os_log(.info, log: Self.log, "🎥 STARTING program video processing loop")
                    for await sampleBuffer in sampleBufferStream {
                        if Task.isCancelled {
                            os_log(.info, log: Self.log, "🎥 Program video processing CANCELLED after %lld frames", frameCount)
                            break
                        }
                        
                        // Extract pixel buffer and submit for processing
                        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            try? await self.frameProcessor.submitFrame(pixelBuffer, for: "program", timestamp: timestamp)
                            
                            // ALSO: Submit to recording processing stream if recording
                            if self.recordingSink != nil {
                                try? await self.frameProcessor.submitFrame(pixelBuffer, for: "program_recording", timestamp: timestamp)
                                if frameCount % 30 == 0 {
                                    os_log(.info, log: Self.log, "🎬 MAIN PROGRAM: Submitted frame %lld to recording stream (recordingSink connected)", frameCount)
                                }
                            }
                            
                            frameCount += 1
                            if frameCount % 30 == 0 {  // Log every 30 frames
                                os_log(.info, log: Self.log, "🎥 Processed %lld program video frames (recordingSink: %{public}@)", frameCount, self.recordingSink != nil ? "connected" : "nil")
                            }
                        }
                    }
                    os_log(.info, log: Self.log, "🎥 PROGRAM VIDEO processing ended after %lld frames", frameCount)
                }
                
                // Update UI with processed frames
                var uiFrameCount: Int64 = 0
                os_log(.info, log: Self.log, "🎥 STARTING program UI update loop")
                for await result in processingStream {
                    if Task.isCancelled {
                        os_log(.info, log: Self.log, "🎥 Program UI update processing CANCELLED after %lld frames", uiFrameCount)
                        break
                    }
                    
                    await MainActor.run {
                        self.programCurrentTexture = result.outputTexture
                        self.objectWillChange.send()
                    }
                    
                    uiFrameCount += 1
                    if uiFrameCount % 30 == 0 {  // Log every 30 UI updates
                        let hasTexture = result.outputTexture != nil
                        os_log(.debug, log: Self.log, "🎥 UI updated %lld times, has texture: %{public}@", uiFrameCount, hasTexture ? "YES" : "NO")
                    }
                }
                
                os_log(.info, log: Self.log, "🎥 PROGRAM UI processing ended after %lld frames", uiFrameCount)
                
            } catch is CancellationError {
                os_log(.info, log: Self.log, "🎥 PROGRAM PROCESSING WAS CANCELLED")
                // Don't set program inactive during cancellation since we might be switching cameras
            } catch {
                os_log(.error, log: Self.log, "🎥 PROGRAM PROCESSING FAILED: %{public}@", error.localizedDescription)
                await MainActor.run {
                    self.log("Program capture failed: \(error.localizedDescription)")
                }
                // Use Task to handle async call
                Task { await self.setProgramActive(false) }
            }
        }
        
        // Start separate audio processing task for program audio
        await startProgramAudioProcessing()
    }
    
    // MARK: - Program Audio Processing
    
    private func startProgramAudioProcessing() async {
        // Stop any existing audio task
        programAudioTask?.cancel()
        
        programAudioTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            do {
                os_log(.info, log: Self.log, "🎤 Starting program audio processing")
                
                // Start microphone capture for program audio
                let micStream = try await self.audioEngine.startMicrophoneCapture()
                
                // Create program audio stream
                let programAudioStream = await self.audioEngine.createAudioStream(for: "program")
                
                var audioFrameCount: Int64 = 0
                os_log(.info, log: Self.log, "🎤 STARTING program audio processing loop")
                
                for await result in micStream {
                    if Task.isCancelled {
                        os_log(.info, log: Self.log, "🎤 Program audio processing CANCELLED after %lld frames", audioFrameCount)
                        break
                    }
                    
                    guard let audioBuffer = result.outputBuffer else { continue }
                    
                    do {
                        // Submit to main program audio processing
                        try await self.audioEngine.submitAudioBuffer(audioBuffer, for: "program")
                        
                        // ALSO: Submit to recording audio processing if recording
                        if self.recordingSink != nil {
                            try await self.audioEngine.submitAudioBuffer(audioBuffer, for: "program_recording")
                        }
                        
                        audioFrameCount += 1
                        if audioFrameCount % 100 == 0 {  // Log every 100 audio frames
                            os_log(.debug, log: Self.log, "🎤 Processed %lld program audio frames", audioFrameCount)
                        }
                    } catch {
                        os_log(.error, log: Self.log, "🎤 Failed to process program audio: %{public}@", error.localizedDescription)
                    }
                }
                
                os_log(.info, log: Self.log, "🎤 PROGRAM AUDIO processing ended after %lld frames", audioFrameCount)
                
            } catch is CancellationError {
                os_log(.info, log: Self.log, "🎤 PROGRAM AUDIO PROCESSING WAS CANCELLED")
            } catch {
                os_log(.error, log: Self.log, "🎤 PROGRAM AUDIO PROCESSING FAILED: %{public}@", error.localizedDescription)
            }
        }
    }
    
    private func stopProgramAudioProcessing() async {
        programAudioTask?.cancel()
        programAudioTask = nil
        
        // Stop microphone capture
        try? await audioEngine.stopMicrophoneCapture()
        
        // Stop program audio stream
        await audioEngine.stopAudioStream(for: "program")
    }
    
    private func setProgramActive(_ active: Bool) async {
        await MainActor.run {
            if self.isProgramActive != active {
                self.isProgramActive = active
                os_log(.info, log: Self.log, "🎥 PROGRAM ACTIVE STATE CHANGED: %{public}@", active ? "ACTIVE" : "INACTIVE")
                os_log(.info, log: Self.log, "🎬 Recording sink connected: %{public}@", self.recordingSink != nil ? "YES" : "NO")
                
                // Notify recording service of availability change
                AppServices.shared.recordingService.updateAvailability(isProgramActive: active)
                
                if active {
                    // Start recording pipeline if sink is connected
                    if self.recordingSink != nil {
                        os_log(.info, log: Self.log, "🎬 Program became active - starting recording pipeline")
                        Task { await self.startProgramRecording() }
                    }
                } else {
                    // Stop recording pipeline
                    os_log(.info, log: Self.log, "🎬 Program became inactive - stopping recording pipeline")
                    Task { 
                        await self.stopProgramRecording()
                        await self.stopProgramAudioProcessing()
                    }
                }
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
        os_log(.info, log: Self.log, "%{public}@", msg)
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
            
            // NOTE: Audio engine initialization is now handled separately
            // when program becomes active to avoid conflicts
            
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
                    Task { await self.setProgramActive(false) }
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
    
    // MARK: - Cleanup
    
    func cleanup() async {
        await stopProgramRecording()
        await stopProgramAudioProcessing()
        await disconnectRecordingSink()
        
        programProcessingTask?.cancel()
        previewProcessingTask?.cancel()
        programAudioTask?.cancel()
        
        programProcessingTask = nil
        previewProcessingTask = nil
        programAudioTask = nil
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