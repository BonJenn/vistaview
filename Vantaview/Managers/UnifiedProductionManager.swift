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
    
    private var simpleRecordingSink: SimpleRecordingSink?
    private var microphoneAudioStream: AsyncStream<AudioProcessingResult>?
    private var programFrameTap: ProgramFrameTap?
    private let programRecordingBridge = ProgramRecordingBridge()
    
    // Direct recording connections
    private var recordingCameraCaptureSession: CameraCaptureSession?
    private var recordingFrameStreamTask: Task<Void, Never>?
    private var recordingAudioStreamTask: Task<Void, Never>?
    
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
        await setupIntegration()
        
        // Initialize with default studio
        loadDefaultStudio()
        
        os_log(.info, log: Self.log, "🎥 UnifiedProductionManager initialized with recording support")
    }
    
    private func setupIntegration() async {
        await cameraFeedManager.setStreamingViewModel(streamingViewModel)
        await externalDisplayManager.setProductionManager(self)
    }
    
    // MARK: - Direct Recording Pipeline
    
    func connectRecordingSink(_ sink: RecordingSink) async {
        os_log(.info, log: Self.log, "🎬 Connecting recording sink...")
        print("🎬 UnifiedProductionManager: ====== CONNECTING RECORDING SINK ======")
        print("🎬 UnifiedProductionManager: Current program state:")
        print("🎬   - isProgramActive: \(isProgramActive)")
        print("🎬   - selectedProgramCameraID: \(selectedProgramCameraID ?? "NONE")")
        print("🎬   - Program source: \(previewProgramManager.programSourceDisplayName)")
        print("🎬   - Has program player: \(previewProgramManager.programPlayer != nil)")
        print("🎬   - Has program texture: \(previewProgramManager.programMetalTexture != nil)")
        
        guard let programFrameTap = sink as? ProgramFrameTap else {
            print("🎬 UnifiedProductionManager: ERROR - Failed to cast sink to ProgramFrameTap")
            return
        }
        
        self.programFrameTap = programFrameTap
        let recorder = programFrameTap.recorder
        self.simpleRecordingSink = SimpleRecordingSink(recorder: recorder, device: effectManager.metalDevice)
        print("🎬 UnifiedProductionManager: Created SimpleRecordingSink (GPU based)")
        
        // For media sources, mark the segment begin and defer actual export until stop.
        switch previewProgramManager.programSource {
        case .media(_, let player):
            await recorder.setSourceMode(.filePlayback)
            if let item = player?.currentItem {
                beginMediaSegmentCapture(for: item)
            }
            print("🎬 UnifiedProductionManager: Media program - deferring export to stop()")
        default:
            await startDirectRecordingPipeline(recorder: recorder)
        }
        
        os_log(.info, log: Self.log, "🎬 Recording sink connected")
        print("🎬 UnifiedProductionManager: ====== RECORDING SINK CONNECTION COMPLETED ======")
    }
    
    func disconnectRecordingSink() async {
        os_log(.info, log: Self.log, "🎬 Disconnecting recording sink...")
        
        await stopDirectRecordingPipeline()
        
        simpleRecordingSink?.setActive(false)
        simpleRecordingSink = nil
        programFrameTap = nil
        
        try? await audioEngine.stopMicrophoneCapture()
        microphoneAudioStream = nil
        
        await programRecordingBridge.stop()
        
        os_log(.info, log: Self.log, "🎬 Recording sink disconnected")
    }
    
    private func startDirectRecordingPipeline(recorder: ProgramRecorder) async {
        print("🎬 UnifiedProductionManager: ====== STARTING DIRECT RECORDING PIPELINE ======")
        
        var shouldStartMic = false
        
        switch previewProgramManager.programSource {
        case .camera(let cameraFeed):
            print("🎬 UnifiedProductionManager: Recording from CAMERA: \(cameraFeed.device.displayName)")
            await recorder.setSourceMode(.live)
            await startCameraRecording(cameraID: cameraFeed.device.deviceID, recorder: recorder)
            shouldStartMic = true
        case .media(let mediaFile, let player):
            print("🎬 UnifiedProductionManager: Recording from MEDIA: \(mediaFile.name)")
            await recorder.setSourceMode(.filePlayback)
            if let player = player {
                await startMediaRecording(player: player, recorder: recorder)
            } else {
                print("🎬 UnifiedProductionManager: ERROR - Media source has no player")
            }
            shouldStartMic = false
        case .virtual(let virtualCamera):
            print("🎬 UnifiedProductionManager: Recording from VIRTUAL CAMERA: \(virtualCamera.name)")
            await recorder.setSourceMode(.live)
            shouldStartMic = true
        case .none:
            print("🎬 UnifiedProductionManager: ERROR - No program source active")
            return
        }
        
        if shouldStartMic {
            await startMicrophoneRecording(recorder: recorder)
        }
        
        print("🎬 UnifiedProductionManager: ====== DIRECT RECORDING PIPELINE STARTED ======")
    }
    
    private func stopDirectRecordingPipeline() async {
        print("🎬 UnifiedProductionManager: ====== STOPPING DIRECT RECORDING PIPELINE ======")
        
        recordingFrameStreamTask?.cancel()
        recordingFrameStreamTask = nil
        
        recordingAudioStreamTask?.cancel()
        recordingAudioStreamTask = nil
        
        recordingCameraCaptureSession = nil
        microphoneAudioStream = nil
        
        // Wait a moment for tasks to clean up
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        print("🎬 UnifiedProductionManager: ====== DIRECT RECORDING PIPELINE STOPPED ======")
    }
    
    private func startCameraRecording(cameraID: String, recorder: ProgramRecorder) async {
        do {
            print("🎬 UnifiedProductionManager: Creating camera capture session for recording")
            let captureSession = try await deviceManager.createCameraCaptureSession(for: cameraID)
            recordingCameraCaptureSession = captureSession
            
            print("🎬 UnifiedProductionManager: Starting camera frame capture for recording")
            let sampleBufferStream = await captureSession.sampleBuffers()
            
            recordingFrameStreamTask = Task.detached(priority: .userInitiated) {
                print("🎬 UnifiedProductionManager: Camera recording task started")
                var frameCount: Int64 = 0
                
                for await sampleBuffer in sampleBufferStream {
                    if Task.isCancelled { break }
                    
                    frameCount += 1
                    if frameCount == 1 {
                        print("🎬 UnifiedProductionManager: First camera frame captured for recording")
                    }
                    
                    // Send directly to recorder
                    await recorder.appendVideoSampleBuffer(sampleBuffer)
                    
                    if frameCount % 30 == 0 {
                        print("🎬 UnifiedProductionManager: Captured \(frameCount) camera frames for recording")
                    }
                }
                print("🎬 UnifiedProductionManager: Camera recording task ended")
            }
        } catch {
            print("🎬 UnifiedProductionManager: ERROR creating camera capture session: \(error)")
        }
    }
    
    private func startMediaRecording(player: AVPlayer, recorder: ProgramRecorder) async {
        print("🎬 UnifiedProductionManager: Starting media recording from AVPlayer (host-time anchored)")

        guard let playerItem = player.currentItem else {
            print("🎬 UnifiedProductionManager: ERROR - No player item for media recording")
            return
        }

        // Determine source fps and frame duration from the asset track
        var sourceFPS: Double = 30.0
        var frameDuration = CMTime(value: 1, timescale: 30)
        if let track = playerItem.asset.tracks(withMediaType: .video).first {
            if track.nominalFrameRate > 0 {
                sourceFPS = Double(track.nominalFrameRate)
            }
            if track.minFrameDuration.isValid && track.minFrameDuration.value > 0 {
                frameDuration = track.minFrameDuration
                sourceFPS = max(1.0, 1.0 / CMTimeGetSeconds(frameDuration))
            }
        }
        await recorder.updateVideoConfig(expectedFPS: sourceFPS, allowFrameReordering: true)
        print("🎬 UnifiedProductionManager: Media source fps: \(sourceFPS), frameDuration: \(frameDuration.seconds)s")

        // Ensure we have AVPlayerItemVideoOutput
        var videoOutput: AVPlayerItemVideoOutput?
        for output in playerItem.outputs {
            if let out = output as? AVPlayerItemVideoOutput {
                videoOutput = out
                break
            }
        }
        if videoOutput == nil {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            let out = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
            out.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.1)
            playerItem.add(out)
            videoOutput = out
        }
        guard let vOut = videoOutput else {
            print("🎬 UnifiedProductionManager: ERROR - Could not get video output for media recording")
            return
        }

        // Anchor the timebase to the exact host time when record is pressed.
        // Using player.currentTime() here is incorrect and can be offset (leading to wrong segment recorded).
        let hostStart = CACurrentMediaTime()
        let startItemTime = vOut.itemTime(forHostTime: hostStart)
        print("🎬 UnifiedProductionManager: Record anchors - hostStart=\(hostStart), startItemTime=\(startItemTime.seconds)s (ts=\(startItemTime.timescale))")

        let videoTask = Task.detached(priority: .userInitiated) {
            print("🎬 UnifiedProductionManager: Media video recording task started (host-time anchored)")
            let pollInterval = max(0.002, (1.0 / max(1.0, sourceFPS)) / 2.0)
            let intervalNs = UInt64(pollInterval * 1_000_000_000.0)
            var appended: Int64 = 0

            while !Task.isCancelled {
                let hostNow = CACurrentMediaTime()
                var itemTime = vOut.itemTime(forHostTime: hostNow)

                if vOut.hasNewPixelBuffer(forItemTime: itemTime) {
                    var displayTime = CMTime.invalid
                    if let pb = vOut.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime) {
                        let ts = displayTime.isValid ? displayTime : itemTime
                        let norm = CMTimeSubtract(ts, startItemTime)
                        if norm.value >= 0 {
                            await recorder.appendVideoPixelBuffer(pb, presentationTime: norm)
                            appended &+= 1
                            if appended == 1 || appended % 60 == 0 {
                                print("🎬 UnifiedProductionManager: Appended media frame #\(appended) at norm \(norm.seconds)s")
                            }
                        } else {
                            // If negative due to pipeline latency, skip until we cross zero.
                            if appended < 5 {
                                print("🎬 UnifiedProductionManager: Skipping negative norm \(norm.seconds)s (ts \(ts.seconds)s < start \(startItemTime.seconds)s)")
                            }
                        }
                    }
                } else {
                    try? await Task.sleep(nanoseconds: intervalNs)
                }
            }
            print("🎬 UnifiedProductionManager: Media video recording task ended (appended=\(appended))")
        }

        self.recordingFrameStreamTask?.cancel()
        self.recordingFrameStreamTask = videoTask

        // No microphone for file playback
        recordingAudioStreamTask?.cancel()
        recordingAudioStreamTask = nil
    }
    
    private func startMicrophoneRecording(recorder: ProgramRecorder) async {
        do {
            print("🎬 UnifiedProductionManager: Starting microphone capture for recording")
            microphoneAudioStream = try await audioEngine.startMicrophoneCapture()
            
            guard let micStream = microphoneAudioStream else {
                print("🎬 UnifiedProductionManager: ERROR - Failed to get microphone stream")
                return
            }
            
            recordingAudioStreamTask = Task.detached(priority: .userInitiated) {
                print("🎬 UnifiedProductionManager: Microphone recording task started")
                var audioCount: Int64 = 0
                
                for await result in micStream {
                    if Task.isCancelled { break }
                    
                    if let audioBuffer = result.outputBuffer {
                        audioCount += 1
                        if audioCount == 1 {
                            print("🎬 UnifiedProductionManager: First audio sample captured for recording")
                        }
                        
                        await recorder.appendAudioSampleBuffer(audioBuffer)
                        
                        if audioCount % 100 == 0 {
                            print("🎬 UnifiedProductionManager: Captured \(audioCount) audio samples for recording")
                        }
                    }
                }
                print("🎬 UnifiedProductionManager: Microphone recording task ended")
            }
        } catch {
            print("🎬 UnifiedProductionManager: ERROR starting microphone capture: \(error)")
        }
    }
    
    // MARK: - Program switching and binding - now async
    
    func switchProgram(to cameraID: String) async {
        os_log(.info, log: Self.log, "🎥 SWITCH PROGRAM REQUEST: %{public}@", cameraID)
        if selectedProgramCameraID == cameraID { return }
        selectedProgramCameraID = cameraID
        await ensureProgramRunning()
    }
    
    private func ensureProgramRunning() async {
        guard let cameraID = selectedProgramCameraID else {
            await setProgramActive(false)
            return
        }
        
        programProcessingTask?.cancel()
        
        await setProgramActive(true)
        
        programProcessingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            do {
                try Task.checkCancellation()
                
                let captureSession = try await self.deviceManager.createCameraCaptureSession(for: cameraID)
                
                let processingStream = await self.frameProcessor.createFrameStream(
                    for: "program",
                    effectChain: self.effectManager.getProgramEffectChain()
                )
                
                let sampleBufferStream = await captureSession.sampleBuffers()
                
                // UI rendering task
                Task.detached(priority: .userInitiated) { [weak self, frameProcessor = self.frameProcessor] in
                    guard let self else { return }
                    
                    for await sampleBuffer in sampleBufferStream {
                        if Task.isCancelled { break }
                        
                        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            try? await frameProcessor.submitFrame(pixelBuffer, for: "program", timestamp: pts)
                        }
                    }
                }
                
                // UI update task
                Task { [weak self] in
                    guard let self = self else { return }
                    
                    for await result in processingStream {
                        if Task.isCancelled { break }
                        
                        await MainActor.run { [weak self] in
                            guard let self = self else { return }
                            if let texture = result.outputTexture {
                                self.programCurrentTexture = texture
                            } else {
                                self.programCurrentTexture = nil
                            }
                            self.objectWillChange.send()
                        }
                    }
                }
                
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.programCurrentTexture = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.programCurrentTexture = nil
                    self.log("Program capture failed: \(error.localizedDescription)")
                }
            }
        }
        
        await startProgramAudioProcessing()
    }
    
    // MARK: - Program Audio Processing
    
    private func startProgramAudioProcessing() async {
        programAudioTask?.cancel()
        
        programAudioTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let micStream = try await self.audioEngine.startMicrophoneCapture()
                let _ = await self.audioEngine.createAudioStream(for: "program")
                for await result in micStream {
                    if Task.isCancelled { break }
                    guard let audioBuffer = result.outputBuffer else { continue }
                    try? await self.audioEngine.submitAudioBuffer(audioBuffer, for: "program")
                }
            } catch { }
        }
    }
    
    private func setProgramActive(_ active: Bool) async {
        if self.isProgramActive != active {
            self.isProgramActive = active
            os_log(.info, log: Self.log, "🎥 PROGRAM ACTIVE STATE CHANGED: %{public}@", active ? "ACTIVE" : "INACTIVE")
            
            AppServices.shared.recordingService.updateAvailability(isProgramActive: active)
        }
    }
    
    // MARK: - Preview switching/binding - now async
    
    private func ensurePreviewRunning() async {
        guard let cameraID = selectedPreviewCameraID else { return }
        previewProcessingTask?.cancel()
        previewProcessingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let captureSession = try await self.deviceManager.createCameraCaptureSession(for: cameraID)
                let processingStream = await self.frameProcessor.createFrameStream(
                    for: "preview",
                    effectChain: self.effectManager.getPreviewEffectChain()
                )
                let sampleBufferStream = await captureSession.sampleBuffers()
                for await sampleBuffer in sampleBufferStream {
                    if Task.isCancelled { break }
                    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        try await self.frameProcessor.submitFrame(pixelBuffer, for: "preview", timestamp: timestamp)
                    }
                }
                for await result in processingStream {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        self.previewCurrentTexture = result.outputTexture
                        self.objectWillChange.send()
                    }
                }
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
        Task { await refreshCameraFeedStateForMode() }
    }
    
    func switchToLiveMode() {
        syncVirtualToLive()
        Task { await refreshCameraFeedStateForMode() }
    }
    
    func refreshCameraFeedStateForMode() async {
        do {
            let _ = try await deviceManager.discoverDevices(forceRefresh: true)
            await MainActor.run {
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
        
        do {
            let deviceChangeStream = await deviceManager.deviceChangeNotifications()
            Task {
                for await change in deviceChangeStream {
                    await self.handleDeviceChange(change)
                }
            }
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
        await disconnectRecordingSink()
        
        programProcessingTask?.cancel()
        previewProcessingTask?.cancel()
        programAudioTask?.cancel()
        
        if let task = programProcessingTask { _ = await task.result }
        if let task = previewProcessingTask { _ = await task.result }
        if let task = programAudioTask { _ = await task.result }
        
        programProcessingTask = nil
        previewProcessingTask = nil
        programAudioTask = nil
        
        await MainActor.run {
            self.programCurrentTexture = nil
            self.previewCurrentTexture = nil
            self.objectWillChange.send()
        }
        
        simpleRecordingSink = nil
        microphoneAudioStream = nil
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

    // MARK: - Media segment capture (file playback → exact in/out using AVAssetReader)
    private var mediaSegmentStartItemTime: CMTime?
    private var mediaSegmentAsset: AVAsset?
    private var mediaSegmentPlayerItem: AVPlayerItem?

    private func beginMediaSegmentCapture(for playerItem: AVPlayerItem) {
        mediaSegmentPlayerItem = playerItem
        mediaSegmentAsset = playerItem.asset
        mediaSegmentStartItemTime = playerItem.currentTime()
        print("🎬 UnifiedProductionManager: Media segment capture BEGIN at itemTime=\(mediaSegmentStartItemTime?.seconds ?? -1)")
    }

    func exportCurrentMediaSegmentIfNeeded(to recorder: ProgramRecorder) async {
        guard let item = mediaSegmentPlayerItem,
              let asset = mediaSegmentAsset,
              let start = mediaSegmentStartItemTime else {
            print("🎬 UnifiedProductionManager: No media segment to export")
            return
        }

        let end = item.currentTime()
        if CMTimeCompare(end, start) <= 0 {
            print("🎬 UnifiedProductionManager: Media segment export skipped (end <= start)")
            mediaSegmentPlayerItem = nil
            mediaSegmentAsset = nil
            mediaSegmentStartItemTime = nil
            return
        }

        let duration = CMTimeSubtract(end, start)
        print("🎬 UnifiedProductionManager: Exporting media segment start=\(start.seconds)s end=\(end.seconds)s dur=\(duration.seconds)s")

        let assetCopy = asset
        let startCopy = start
        let durationCopy = duration

        let task = Task.detached(priority: .userInitiated) {
            do {
                let reader = try AVAssetReader(asset: assetCopy)
                reader.timeRange = CMTimeRange(start: startCopy, duration: durationCopy)

                guard let vTrack = assetCopy.tracks(withMediaType: .video).first else {
                    print("🎬 UnifiedProductionManager: Segment export ERROR - no video track")
                    return
                }

                var sourceFPS: Double = 30.0
                if vTrack.nominalFrameRate > 0 {
                    sourceFPS = Double(vTrack.nominalFrameRate)
                } else if vTrack.minFrameDuration.isValid && vTrack.minFrameDuration.value > 0 {
                    sourceFPS = max(1.0, 1.0 / CMTimeGetSeconds(vTrack.minFrameDuration))
                }
                await recorder.setSourceMode(.filePlayback)
                await recorder.updateVideoConfig(expectedFPS: sourceFPS, allowFrameReordering: true)

                let vSettings: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]
                let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: vSettings)
                vOut.alwaysCopiesSampleData = false
                guard reader.canAdd(vOut) else {
                    print("🎬 UnifiedProductionManager: Segment export ERROR - cannot add video output")
                    return
                }
                reader.add(vOut)

                var aOut: AVAssetReaderTrackOutput?
                if let aTrack = assetCopy.tracks(withMediaType: .audio).first {
                    let aSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 48_000,
                        AVNumberOfChannelsKey: 2,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMBitDepthKey: 16
                    ]
                    let out = AVAssetReaderTrackOutput(track: aTrack, outputSettings: aSettings)
                    out.alwaysCopiesSampleData = false
                    if reader.canAdd(out) {
                        reader.add(out)
                        aOut = out
                    }
                }

                guard reader.startReading() else {
                    print("🎬 UnifiedProductionManager: Segment export ERROR - reader failed: \(reader.error?.localizedDescription ?? "unknown")")
                    return
                }

                var vCount: Int64 = 0
                while let sb = vOut.copyNextSampleBuffer() {
                    try? Task.checkCancellation()
                    vCount &+= 1
                    await recorder.appendVideoSampleBuffer(sb)
                    if vCount == 1 || vCount % 120 == 0 {
                        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
                        print("🎬 UnifiedProductionManager: Segment video sb#\(vCount) PTS=\(pts.seconds)")
                    }
                }

                var aCount: Int64 = 0
                if let aOut {
                    while let sb = aOut.copyNextSampleBuffer() {
                        try? Task.checkCancellation()
                        aCount &+= 1
                        await recorder.appendAudioSampleBuffer(sb)
                        if aCount == 1 || aCount % 300 == 0 {
                            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
                            print("🎬 UnifiedProductionManager: Segment audio sb#\(aCount) PTS=\(pts.seconds)")
                        }
                    }
                }

                print("🎬 UnifiedProductionManager: Segment export finished status=\(reader.status.rawValue) err=\(reader.error?.localizedDescription ?? "nil") v=\(vCount) a=\(aCount)")
            } catch {
                print("🎬 UnifiedProductionManager: Segment export ERROR - \(error.localizedDescription)")
            }
        }

        await task.value

        mediaSegmentPlayerItem = nil
        mediaSegmentAsset = nil
        mediaSegmentStartItemTime = nil
    }
}

// MARK: - Supporting Types

struct StudioConfiguration: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let icon: String
}