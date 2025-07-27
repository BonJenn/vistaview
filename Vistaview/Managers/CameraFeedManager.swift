//
//  CameraFeedManager.swift
//  Vistaview
//
//  Created by AI Assistant
//

import Foundation
import AVFoundation
import SwiftUI
import SceneKit
import CoreVideo

/// Represents a camera feed that can be shared between Live Production and Virtual Studio
@MainActor
final class CameraFeed: ObservableObject, Identifiable {
    let id = UUID()
    let device: CameraDevice
    
    @Published var isActive = false
    @Published var currentFrame: CVPixelBuffer?
    @Published var currentSampleBuffer: CMSampleBuffer?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var previewImage: CGImage?
    
    // Make captureSession accessible for debugging
    private(set) var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "camera.feed.queue")
    private var frameCount = 0
    
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
        
        var displayText: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Live"
            case .error(let message): return "Error: \(message)"
            }
        }
        
        var color: Color {
            switch self {
            case .disconnected: return .secondary
            case .connecting: return .orange
            case .connected: return .green
            case .error: return .red
            }
        }
        
        static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    
    init(device: CameraDevice) {
        self.device = device
    }
    
    func startCapture() async {
        guard let captureDevice = device.captureDevice else {
            connectionStatus = .error("No capture device available")
            print("❌ No capture device for: \(device.displayName)")
            return
        }
        
        connectionStatus = .connecting
        print("📹 Starting camera capture for: \(device.displayName)")
        
        do {
            // Create capture session with explicit configuration
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            // Use medium quality for better compatibility and performance
            if session.canSetSessionPreset(.medium) {
                session.sessionPreset = .medium
            } else if session.canSetSessionPreset(.low) {
                session.sessionPreset = .low
            }
            
            // Add video input
            let videoInput = try AVCaptureDeviceInput(device: captureDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                print("✅ Added video input for: \(device.displayName)")
                
                // Log input format details
                print("   - Active format: \(captureDevice.activeFormat)")
                print("   - Frame rate: \(captureDevice.activeVideoMinFrameDuration)")
            } else {
                throw CameraFeedError.cannotAddInput
            }
            
            // Configure video output with very specific settings
            let output = AVCaptureVideoDataOutput()
            
            // Use BGRA format which is most compatible with macOS
            let pixelFormat = kCVPixelFormatType_32BGRA
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            
            // Set up frame delivery
            output.alwaysDiscardsLateVideoFrames = true // Drop frames if processing is slow
            output.setSampleBufferDelegate(VideoOutputDelegate(feed: self), queue: videoQueue)
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                print("✅ Added video output for: \(device.displayName)")
                print("   - Pixel format: BGRA32")
                print("   - Metal compatibility: enabled")
            } else {
                throw CameraFeedError.cannotAddOutput
            }
            
            // Configure video connection
            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                print("   - Video orientation: \(connection.videoOrientation.rawValue)")
            }
            
            session.commitConfiguration()
            
            self.captureSession = session
            self.videoOutput = output
            
            // Start session
            print("🎬 Starting capture session for: \(device.displayName)")
            session.startRunning()
            
            // Wait a moment and verify session is running
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            if session.isRunning {
                isActive = true
                connectionStatus = .connected
                frameCount = 0
                
                print("✅ Camera feed started successfully: \(device.displayName)")
                print("   - Session preset: \(session.sessionPreset.rawValue)")
                print("   - Session is running: \(session.isRunning)")
                print("   - Inputs: \(session.inputs.count), Outputs: \(session.outputs.count)")
                
                // Start frame monitoring
                Task {
                    await monitorFrameRate()
                }
            } else {
                throw CameraFeedError.deviceNotAvailable
            }
            
        } catch {
            connectionStatus = .error(error.localizedDescription)
            print("❌ Camera feed error for \(device.displayName): \(error)")
        }
    }
    
    private func monitorFrameRate() async {
        while isActive && captureSession?.isRunning == true {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            
            print("📊 Camera feed \(device.displayName): \(frameCount) frames in last 5 seconds")
            print("   - Has preview image: \(previewImage != nil)")
            print("   - Session running: \(captureSession?.isRunning ?? false)")
            
            frameCount = 0
        }
    }
    
    func stopCapture() {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        isActive = false
        connectionStatus = .disconnected
        currentFrame = nil
        previewImage = nil
        frameCount = 0
        
        print("🛑 Camera feed stopped: \(device.displayName)")
    }
    
    private func updateFrame(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        currentFrame = pixelBuffer
        
        // Store the pixel buffer for direct use
        // Also create CGImage for preview/compatibility
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Lock the pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            print("❌ Failed to get pixel buffer base address")
            return
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // Create bitmap context from pixel buffer
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            print("❌ Failed to create CGContext from pixel buffer")
            return
        }
        
        // Create CGImage from context
        guard let cgImage = context.makeImage() else {
            print("❌ Failed to create CGImage from context")
            return
        }
        
        previewImage = cgImage
        
        // Debug: Log frame updates occasionally
        if frameCount % 150 == 1 { // Every ~5 seconds at 30fps
            print("🎥 Camera feed '\(device.displayName)' frame \(frameCount): \(cgImage.width)x\(cgImage.height)")
            print("   - Bytes per row: \(bytesPerRow)")
            print("   - Color space: \(cgImage.colorSpace?.name as? String ?? "unknown")")
            print("   - Alpha info: \(cgImage.alphaInfo.rawValue)")
            print("   - CVPixelBuffer format: \(CVPixelBufferGetPixelFormatType(pixelBuffer))")
        }
    }
    
    private class VideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private weak var feed: CameraFeed?
        
        init(feed: CameraFeed) {
            self.feed = feed
        }
        
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { 
                print("❌ No pixel buffer in sample buffer")
                return 
            }
            
            Task { @MainActor in
                self.feed?.currentSampleBuffer = sampleBuffer
                self.feed?.updateFrame(pixelBuffer)
            }
        }
        
        func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            print("⚠️ Dropped video frame from \(self.feed?.device.displayName ?? "unknown camera")")
        }
    }
}

enum CameraFeedError: Error, LocalizedError {
    case cannotAddInput
    case cannotAddOutput
    case deviceNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .cannotAddInput: return "Cannot add camera input to session"
        case .cannotAddOutput: return "Cannot add video output to session"
        case .deviceNotAvailable: return "Camera device not available"
        }
    }
}

/// Manages camera feeds for both Live Production and Virtual Studio
@MainActor
final class CameraFeedManager: ObservableObject {
    @Published var activeFeeds: [CameraFeed] = []
    @Published var selectedFeedForLiveProduction: CameraFeed?
    @Published var isDiscovering = false
    @Published var lastDiscoveryError: String?
    
    let cameraDeviceManager: CameraDeviceManager
    
    // Reference to StreamingViewModel for integration
    weak var streamingViewModel: StreamingViewModel?
    
    init(cameraDeviceManager: CameraDeviceManager) {
        self.cameraDeviceManager = cameraDeviceManager
        
        // Bind to camera device manager's published properties
        Task { @MainActor in
            for await _ in cameraDeviceManager.$isDiscovering.values {
                self.isDiscovering = cameraDeviceManager.isDiscovering
            }
        }
        
        Task { @MainActor in
            for await _ in cameraDeviceManager.$lastDiscoveryError.values {
                self.lastDiscoveryError = cameraDeviceManager.lastDiscoveryError
            }
        }
    }
    
    /// Set the streaming view model for integration
    func setStreamingViewModel(_ viewModel: StreamingViewModel) {
        self.streamingViewModel = viewModel
    }
    
    /// Create and start a camera feed for a specific device
    func startFeed(for device: CameraDevice) async -> CameraFeed? {
        // Check if feed already exists
        if let existingFeed = activeFeeds.first(where: { $0.device.deviceID == device.deviceID }) {
            return existingFeed
        }
        
        let feed = CameraFeed(device: device)
        activeFeeds.append(feed)
        
        await feed.startCapture()
        return feed
    }
    
    /// Stop and remove a camera feed
    func stopFeed(_ feed: CameraFeed) {
        feed.stopCapture()
        activeFeeds.removeAll { $0.id == feed.id }
        
        if selectedFeedForLiveProduction?.id == feed.id {
            selectedFeedForLiveProduction = nil
            
            // Note: StreamingViewModel doesn't have a disconnectCamera method
            // The camera will be disconnected when the stream is stopped
        }
    }
    
    /// Select a feed for live production use and connect to StreamingViewModel
    func selectFeedForLiveProduction(_ feed: CameraFeed) async {
        selectedFeedForLiveProduction = feed
        print("📺 Selected camera feed for live production: \(feed.device.displayName)")
        
        // Note: StreamingViewModel uses its own camera setup method
        // The integration would need to be handled at a higher level
        // since StreamingViewModel.setupCamera() doesn't take parameters
    }
    
    /// Get the current frame from the selected live production feed
    var liveProductionFrame: CVPixelBuffer? {
        return selectedFeedForLiveProduction?.currentFrame
    }
    
    /// Get the preview image from the selected live production feed
    var liveProductionPreviewImage: CGImage? {
        return selectedFeedForLiveProduction?.previewImage
    }
    
    /// Get all available camera devices
    func getAvailableDevices() async -> [CameraDevice] {
        await cameraDeviceManager.discoverDevices()
        return cameraDeviceManager.availableDevices
    }
    
    /// Force refresh camera devices for debugging
    func forceRefreshDevices() async {
        await cameraDeviceManager.forceRefresh()
    }
    
    /// Get current available devices without triggering discovery
    var availableDevices: [CameraDevice] {
        return cameraDeviceManager.availableDevices
    }
    
    /// Stop all active feeds
    func stopAllFeeds() {
        for feed in activeFeeds {
            feed.stopCapture()
        }
        activeFeeds.removeAll()
        selectedFeedForLiveProduction = nil
        
        // Note: StreamingViewModel doesn't have a disconnectCamera method
        // The camera will be disconnected when the stream is stopped
    }
    
    /// Debug camera detection issues
    func debugCameraDetection() async {
        await cameraDeviceManager.debugCameraDetection()
    }
}