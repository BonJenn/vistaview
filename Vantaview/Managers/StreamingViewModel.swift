import Foundation
import SwiftUI
import HaishinKit
import AVFoundation
import CoreVideo
import CoreMedia
import CoreImage
import Metal

@MainActor
class StreamingViewModel: ObservableObject {
    private let mixer = MediaMixer()
    private let connection = RTMPConnection()
    private let stream: RTMPStream
    private var previewView: MTHKView?
    // private var programStream: RTMPStream?

    @Published var isPublishing = false
    @Published var cameraSetup = false
    @Published var statusMessage = "Initializing..."
    @Published var mirrorProgramOutput: Bool = true

    enum AudioSource: String, CaseIterable, Identifiable {
        case microphone, program, none
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .microphone: return "Microphone"
            case .program: return "Program Audio"
            case .none: return "None"
            }
        }
    }
    @Published var selectedAudioSource: AudioSource = .microphone

    // Program mirroring
    weak var programManager: PreviewProgramManager?
    private var frameTimer: Timer?
    private let programTargetFPS: Double = 30
    private let programCIContext = CIContext(options: [.cacheIntermediates: false])
    private var programPixelBufferPool: CVPixelBufferPool?
    private var programVideoFormat: CMVideoFormatDescription?
    private var lastPTS: CMTime = .zero
    private var frameDuration: CMTime { CMTime(value: 1, timescale: CMTimeScale(programTargetFPS)) }

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

        print("ℹ️ Skipping HK preview attach (publisher is Program-only)")
        statusMessage = "✅ Preview ready"
    }

    func bindToProgramManager(_ manager: PreviewProgramManager) {
        self.programManager = manager
        print("🔗 StreamingViewModel bound to PreviewProgramManager")
    }

    func start(rtmpURL: String, streamKey: String) async throws {
        print("🚀 Starting stream...")
        statusMessage = "Starting stream..."

        // Program-only publishing: do not involve mixer or camera at all.
        cameraSetup = false

        do {
            print("🌐 Connecting to: \(rtmpURL)")
            statusMessage = "Connecting to server..."
            try await connection.connect(rtmpURL)
            
            print("📡 Publishing Program stream with key: \(streamKey)")
            statusMessage = "Publishing stream..."
            try await stream.publish(streamKey)
            
            isPublishing = true
            statusMessage = "✅ Live (Program output)"
            print("✅ Streaming started successfully (Program-only)")

            startProgramFramePump()
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

        stopProgramFramePump()
        
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

    func applyAudioSourceChange() {
        guard isPublishing else { return }
        // TODO: Implement dynamic audio source switching once program audio tap is integrated.
        print("ℹ️ Audio source change requested: \(selectedAudioSource.displayName) (will apply with AVAudioMix tap integration)")
    }

    // MARK: - Program frame pump
    private func startProgramFramePump() {
        guard frameTimer == nil else { return }
        print("🖼️ Starting Program frame pump at \(programTargetFPS) FPS")
        lastPTS = .zero
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / programTargetFPS, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.pushCurrentProgramFrame()
            }
        }
        RunLoop.main.add(frameTimer!, forMode: .common)
    }

    private func stopProgramFramePump() {
        frameTimer?.invalidate()
        frameTimer = nil
        print("🖼️ Stopped Program frame pump")
    }

    private func pushCurrentProgramFrame() async {
        guard isPublishing else { return }
        guard let pb = makeProgramPixelBuffer() else { return }

        if programVideoFormat == nil {
            var fdesc: CMVideoFormatDescription?
            if CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescriptionOut: &fdesc) == noErr {
                programVideoFormat = fdesc
            }
        }

        lastPTS = CMTimeAdd(lastPTS, frameDuration)

        var timing = CMSampleTimingInfo(duration: frameDuration, presentationTimeStamp: lastPTS, decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        guard let fdesc = programVideoFormat,
              CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescription: fdesc, sampleTiming: &timing, sampleBufferOut: &sb) == noErr,
              let sampleBuffer = sb else {
            return
        }

        // Directly feed Program frame to the publishing RTMP stream
        await stream.appendVideo(sampleBuffer)
    }

    private func makeProgramPixelBuffer() -> CVPixelBuffer? {
        guard let pm = programManager else { return nil }

        if let tex = pm.programCurrentTexture, let pb = pixelBuffer(from: tex) {
            return pb
        }

        if let cg = pm.programImage, let pb = pixelBuffer(from: cg) {
            return pb
        }

        if case .camera(let feed) = pm.programSource, let pb = feed.currentFrame {
            return pb
        }

        return nil
    }

    private func pixelBuffer(from texture: MTLTexture) -> CVPixelBuffer? {
        let width = texture.width
        let height = texture.height

        if programPixelBufferPool == nil {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
            programPixelBufferPool = pool
        }

        var pb: CVPixelBuffer?
        if let pool = programPixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        }
        guard let pixelBuffer = pb else { return nil }

        guard let ciImage = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) else {
            return nil
        }
        let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -ciImage.extent.height))

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        programCIContext.render(flipped, to: pixelBuffer)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    private func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let width = image.width
        let height = image.height

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb else { return nil }

        let ciImage = CIImage(cgImage: image)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        programCIContext.render(ciImage, to: pixelBuffer)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
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