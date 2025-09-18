import Foundation
import SwiftUI
import HaishinKit
import AVFoundation
import CoreVideo
import CoreMedia
import CoreImage
import Metal
import ImageIO
import CoreGraphics
import VideoToolbox
import MetalKit
#if os(macOS)
import AppKit
#endif

@MainActor
class StreamingViewModel: ObservableObject {
    // Background processing actors
    private let streamingEngine: StreamingEngine
    private let audioEngine: AudioEngine
    
    // Legacy components for backwards compatibility
    private let mixer = MediaMixer()
    private let connection = RTMPConnection()
    private let stream: RTMPStream
    private var previewView: MTHKView?

    @Published var isPublishing = false
    @Published var cameraSetup = false
    @Published var statusMessage = "Initializing..."
    @Published var mirrorProgramOutput: Bool = true

    @Published var programAudioRMS: Float = 0
    @Published var programAudioPeak: Float = 0
    @Published var avSyncOffsetMs: Double = 0

    // Audio configuration
    enum AudioSource: String, CaseIterable, Identifiable {
        case microphone, program, none
        case micAndProgram
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .microphone: return "Microphone"
            case .program: return "Program Audio"
            case .none: return "None"
            case .micAndProgram: return "Mic + Program"
            }
        }
    }
    @Published var selectedAudioSource: AudioSource = .microphone
    @Published var includePiPAudioInProgram: Bool = false

    // External managers for PiP and Program mirroring
    weak var programManager: PreviewProgramManager?
    weak var layerManager: LayerStackManager?
    weak var productionManager: UnifiedProductionManager?
    
    // Background processing tasks
    private var streamingTask: Task<Void, Never>?
    private var statusMonitoringTask: Task<Void, Never>?

    init(streamingEngine: StreamingEngine, audioEngine: AudioEngine) {
        self.streamingEngine = streamingEngine
        self.audioEngine = audioEngine
        self.stream = RTMPStream(connection: connection)
        
        setupAudioSession()
        setupStatusMonitoring()
        
        #if DEBUG
        print("StreamingViewModel: Initialized with Swift Concurrency actors")
        #endif
    }
    
    deinit {
        streamingTask?.cancel()
        statusMonitoringTask?.cancel()
    }
    
    private func setupStatusMonitoring() {
        statusMonitoringTask = Task { [weak self] in
            guard let self else { return }
            
            let statusStream = await self.streamingEngine.statusUpdates()
            for await status in statusStream {
                await self.updateUIFromStreamStatus(status)
            }
        }
    }
    
    private func updateUIFromStreamStatus(_ status: StreamingStatus) async {
        await MainActor.run {
            switch status.state {
            case .disconnected:
                self.isPublishing = false
                self.statusMessage = "Disconnected"
            case .connecting:
                self.statusMessage = "Connecting..."
            case .connected:
                self.statusMessage = "Connected"
            case .publishing:
                self.isPublishing = true
                self.statusMessage = "✅ Live (Program output)"
            case .reconnecting:
                self.statusMessage = "Reconnecting..."
            case .error(let message):
                self.isPublishing = false
                self.statusMessage = "❌ Error: \(message)"
            }
            
            // Update audio levels from status
            self.programAudioRMS = status.connectionQuality > 0 ? Float(status.connectionQuality) * 0.5 : 0
            self.programAudioPeak = Float(status.connectionQuality)
        }
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            statusMessage = "Audio session configured"
            print("✅ Audio session setup successful")
        } catch {
            statusMessage = "Audio session error: \(error.localizedDescription)"
            print("❌ Audio session setup error:", error)
        }
        #else
        statusMessage = "macOS - no audio session needed"
        print("✅ macOS detected - skipping audio session setup")
        #endif
    }
    
    func setupCameraWithDevice(_ videoDevice: AVCaptureDevice) async {
        if mirrorProgramOutput {
            print("🪞 Program mirroring active: skipping setupCameraWithDevice")
            statusMessage = "Program mirroring: camera disabled"
            cameraSetup = false
            return
        }
        statusMessage = "Setting up selected camera..."
        print("🎥 Setting up camera with specific device: \(videoDevice.localizedName)")
        
        do {
            print("✅ Using selected camera: \(videoDevice.localizedName)")
            statusMessage = "Connecting to: \(videoDevice.localizedName)"
            print("📹 Attaching selected camera to mixer...")
            try await mixer.attachVideo(videoDevice)
            cameraSetup = true
            statusMessage = "✅ Camera ready: \(videoDevice.localizedName)"
            print("✅ Camera setup successful with selected device!")
        } catch {
            statusMessage = "❌ Camera error: \(error.localizedDescription)"
            print("❌ Camera setup error with selected device:", error)
            cameraSetup = false
        }
    }
    
    func setupCamera() async {
        if mirrorProgramOutput {
            print("🪞 Program mirroring active: skipping setupCamera")
            statusMessage = "Program mirroring: camera disabled"
            cameraSetup = false
            return
        }
        statusMessage = "Setting up camera..."
        print("🎥 Starting automatic camera setup...")
        
        do {
            print("📝 Configuring mixer...")
            try await mixer.setFrameRate(30)
            try await mixer.setSessionPreset(AVCaptureSession.Preset.medium)
            
            print("🔍 Looking for camera devices...")
            #if os(macOS)
            let cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video)
            #else
            let cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            #endif
            
            guard let videoDevice = cameraDevice else {
                statusMessage = "❌ No camera device found"
                print("❌ No camera device found")
                return
            }
            
            print("✅ Found camera: \(videoDevice.localizedName)")
            statusMessage = "Found camera: \(videoDevice.localizedName)"
            print("📹 Attaching camera to mixer...")
            try await mixer.attachVideo(videoDevice)
            cameraSetup = true
            statusMessage = "✅ Camera ready"
            print("✅ Camera setup successful!")
        } catch {
            statusMessage = "❌ Camera error: \(error.localizedDescription)"
            print("❌ Camera setup error:", error)
        }
    }
    
    func attachPreview(_ view: MTHKView) async {
        print("🖼️ Attaching preview view...")
        previewView = view
        print("ℹ️ Preview attached (program output streaming)")
        statusMessage = "✅ Preview ready"
    }

    func bindToProgramManager(_ manager: PreviewProgramManager) {
        self.programManager = manager
        print("🔗 StreamingViewModel bound to PreviewProgramManager")
    }

    func bindToLayerManager(_ manager: LayerStackManager) {
        self.layerManager = manager
        print("🔗 StreamingViewModel bound to LayerStackManager")
    }

    func bindToProductionManager(_ manager: UnifiedProductionManager) {
        self.productionManager = manager
        print("🔗 StreamingViewModel bound to UnifiedProductionManager")
    }

    func start(rtmpURL: String, streamKey: String) async throws {
        print("🚀 Starting stream using Swift Concurrency actors...")
        statusMessage = "Starting stream..."
        cameraSetup = false

        do {
            // Create streaming configuration
            let config = StreamConfiguration(
                rtmpURL: rtmpURL,
                streamKey: streamKey,
                videoSettings: .default,
                audioSettings: .default,
                reconnectionSettings: .default
            )
            
            // Start streaming through actor
            try await streamingEngine.startStream(configuration: config)
            
            // Set up audio routing
            await configureAudioRouting()
            
            // Start frame and audio submission
            await startContentSubmission()
            
            print("✅ Streaming started successfully using actors")
        } catch {
            statusMessage = "❌ Stream error: \(error.localizedDescription)"
            print("❌ Streaming start error:", error)
            isPublishing = false
            throw error
        }
    }

    func stop() async {
        print("🛑 Stopping stream...")
        statusMessage = "Stopping stream..."

        // Stop content submission
        streamingTask?.cancel()
        streamingTask = nil
        
        // Stop streaming engine
        await streamingEngine.stopStream()
        
        // Stop audio processing
        try? await audioEngine.stopMicrophoneCapture()
        
        // Legacy cleanup
        do {
            try await stream.close()
            try await connection.close()
        } catch {
            print("❌ Legacy cleanup error:", error)
        }
        
        await MainActor.run {
            self.isPublishing = false
            self.statusMessage = "✅ Stream stopped"
            print("✅ Streaming stopped")
        }
    }

    func applyAudioSourceChange() {
        guard isPublishing else { return }
        Task { @MainActor in
            await configureAudioRouting()
        }
    }

    // MARK: - Audio Routing with Actors

    private func configureAudioRouting() async {
        print("🎚️ Configuring audio routing: \(selectedAudioSource.displayName)")
        
        do {
            switch selectedAudioSource {
            case .microphone:
                // Start microphone capture through audio engine
                _ = try await audioEngine.startMicrophoneCapture()
                
            case .program:
                // Configure program audio processing
                await setupProgramAudioProcessing()
                
            case .micAndProgram:
                // Start both microphone and program audio
                _ = try await audioEngine.startMicrophoneCapture()
                await setupProgramAudioProcessing()
                
            case .none:
                // Stop all audio processing
                try await audioEngine.stopMicrophoneCapture()
            }
        } catch {
            print("❌ Audio routing configuration failed: \(error)")
            await MainActor.run {
                self.statusMessage = "Audio config error: \(error.localizedDescription)"
            }
        }
    }
    
    private func setupProgramAudioProcessing() async {
        // Create audio stream for program audio processing
        let audioConfig = AudioMixConfiguration.AudioSourceConfig(
            volume: includePiPAudioInProgram ? 1.0 : 0.8,
            pan: 0.0,
            muted: false,
            soloEnabled: false
        )
        
        _ = await audioEngine.createAudioStream(for: "program", configuration: audioConfig)
        print("🔊 Program audio processing configured")
    }

    // MARK: - Content Submission

    private func startContentSubmission() async {
        streamingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            await withTaskGroup(of: Void.self) { group in
                // Video frame submission task
                group.addTask { [weak self] in
                    await self?.submitVideoFrames()
                }
                
                // Audio buffer submission task
                group.addTask { [weak self] in
                    await self?.submitAudioBuffers()
                }
            }
        }
    }
    
    private func submitVideoFrames() async {
        print("🎬 Starting video frame submission")
        
        // Submit frames at target FPS
        let targetFPS = 30.0
        let frameDuration = 1.0 / targetFPS
        
        while !Task.isCancelled {
            do {
                try Task.checkCancellation()
                
                // Get program frame from production manager
                if let programTexture = await MainActor.run(body: { self.productionManager?.programCurrentTexture }) {
                    let timestamp = CMClockGetTime(CMClockGetHostTimeClock())
                    let duration = CMTime(seconds: frameDuration, preferredTimescale: 600)
                    
                    try await streamingEngine.submitTexture(programTexture, timestamp: timestamp, duration: duration)
                }
                
                // Wait for next frame
                try await Task.sleep(nanoseconds: UInt64(frameDuration * 1_000_000_000))
                
            } catch is CancellationError {
                break
            } catch {
                print("❌ Video frame submission error: \(error)")
                // Continue trying
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            }
        }
        
        print("🎬 Video frame submission stopped")
    }
    
    private func submitAudioBuffers() async {
        print("🔊 Starting audio buffer submission")
        
        // Get audio stream from audio engine based on selected source
        let audioStream: AsyncStream<AudioProcessingResult>
        
        switch selectedAudioSource {
        case .microphone:
            do {
                audioStream = try await audioEngine.startMicrophoneCapture()
            } catch {
                print("❌ Failed to start microphone capture: \(error)")
                return
            }
        case .program, .micAndProgram:
            audioStream = await audioEngine.createAudioStream(for: "program")
        case .none:
            return
        }
        
        for await audioResult in audioStream {
            if Task.isCancelled { break }
            
            do {
                try Task.checkCancellation()
                
                if let sampleBuffer = audioResult.outputBuffer {
                    let streamBuffer = StreamAudioBuffer(sampleBuffer: sampleBuffer)
                    try await streamingEngine.submitAudioBuffer(streamBuffer)
                    
                    // Update UI with audio levels
                    await MainActor.run {
                        self.programAudioRMS = audioResult.rmsLevel
                        self.programAudioPeak = audioResult.peakLevel
                    }
                }
                
            } catch is CancellationError {
                break
            } catch {
                print("❌ Audio buffer submission error: \(error)")
                // Continue trying
            }
        }
        
        print("🔊 Audio buffer submission stopped")
    }

    // MARK: - Legacy Compatibility Methods

    func resetAndSetupWithDevice(_ videoDevice: AVCaptureDevice) async {
        print("🔄 Resetting StreamingViewModel to use device: \(videoDevice.localizedName)")
        if isPublishing {
            await stop()
        }
        await mixer.setFrameRate(30)
        await mixer.setSessionPreset(AVCaptureSession.Preset.medium)
        await setupCameraWithDevice(videoDevice)
    }
}

// MARK: - Error Types

enum StreamingError: Error, LocalizedError {
    case noCamera
    case noMicrophone
    case connectionFailed
    
    var errorDescription: String? {
        switch self {
        case .noCamera:
            return "No camera device found"
        case .noMicrophone:
            return "No microphone device found"
        case .connectionFailed:
            return "Failed to connect to streaming server"
        }
    }
}

// MARK: - Supporting Extensions

private extension LayerSource {
    var isVideo: Bool {
        if case .media(let file) = self {
            return file.fileType == .video
        }
        return false
    }
}