import Foundation
import SwiftUI
import HaishinKit
import AVFoundation

@MainActor
class StreamingViewModel: ObservableObject {
    private let mixer = MediaMixer()
    private let connection = RTMPConnection()
    private let stream: RTMPStream
    private var previewView: MTHKView?
    
    @Published var isPublishing = false
    @Published var cameraSetup = false
    @Published var statusMessage = "Initializing..."
    
    init() {
        stream = RTMPStream(connection: connection)
        setupAudioSession()
        
        // Enable detailed logging
        #if DEBUG
        print("StreamingViewModel: Initialized")
        #endif
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
        statusMessage = "Setting up selected camera..."
        print("🎥 Setting up camera with specific device: \(videoDevice.localizedName)")
        
        do {
            print("✅ Using selected camera: \(videoDevice.localizedName)")
            statusMessage = "Connecting to: \(videoDevice.localizedName)"
            
            // Attach camera to mixer - this should work with the device directly
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
        statusMessage = "Setting up camera..."
        print("🎥 Starting automatic camera setup...")
        
        do {
            // Configure mixer first
            print("📝 Configuring mixer...")
            try await mixer.setFrameRate(30)
            try await mixer.setSessionPreset(AVCaptureSession.Preset.medium)
            
            // Add stream as output
            print("🔗 Adding stream to mixer...")
            try await mixer.addOutput(stream)
            
            // Find and attach camera
            print("🔍 Looking for camera devices...")
            
            #if os(macOS)
            // On macOS, try different camera types
            let cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video)
            #else
            // On iOS, try front camera first, then back
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
            
            // Attach camera to mixer
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
        
        do {
            try await stream.addOutput(view)
            statusMessage = "✅ Preview attached"
            print("✅ Preview attached successfully")
        } catch {
            statusMessage = "❌ Preview error: \(error.localizedDescription)"
            print("❌ Preview attachment error:", error)
        }
    }
    
    func start(rtmpURL: String, streamKey: String) async throws {
        print("🚀 Starting stream...")
        statusMessage = "Starting stream..."
        
        guard cameraSetup else {
            let error = StreamingError.noCamera
            statusMessage = "❌ Camera not ready"
            print("❌ Camera not set up yet")
            throw error
        }
        
        // Attach microphone
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                print("🎤 Attaching microphone...")
                try await mixer.attachAudio(audioDevice)
                print("✅ Microphone attached")
            } catch {
                print("⚠️ Audio attachment error:", error)
                statusMessage = "⚠️ Audio error (continuing): \(error.localizedDescription)"
            }
        } else {
            print("⚠️ No microphone found")
            statusMessage = "⚠️ No microphone found"
        }
        
        // Connect and publish
        do {
            print("🌐 Connecting to: \(rtmpURL)")
            statusMessage = "Connecting to server..."
            try await connection.connect(rtmpURL)
            
            print("📡 Publishing stream with key: \(streamKey)")
            statusMessage = "Publishing stream..."
            try await stream.publish(streamKey)
            
            isPublishing = true
            statusMessage = "✅ Streaming live!"
            print("✅ Streaming started successfully")
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
        
        do {
            try await stream.close()
            try await connection.close()
            isPublishing = false
            statusMessage = "✅ Stream stopped"
            print("✅ Streaming stopped")
        } catch {
            statusMessage = "❌ Stop error: \(error.localizedDescription)"
            print("❌ Stop streaming error:", error)
            isPublishing = false
        }
    }
    
    // Add a new method to reset the mixer and use a specific device
    func resetAndSetupWithDevice(_ videoDevice: AVCaptureDevice) async {
        print("🔄 Resetting StreamingViewModel to use device: \(videoDevice.localizedName)")
        
        // Stop any existing streaming
        if isPublishing {
            await stop()
        }
        
        // Reset the mixer
        await mixer.setFrameRate(30)
        await mixer.setSessionPreset(AVCaptureSession.Preset.medium)
        
        // Re-add stream as output
        do {
            try await mixer.addOutput(stream)
            print("✅ Re-added stream to mixer")
        } catch {
            print("❌ Error re-adding stream to mixer: \(error)")
        }
        
        // Now setup with the specific device
        await setupCameraWithDevice(videoDevice)
    }
}

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
