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
    @Published var previewNSImage: NSImage?
    
    // Make captureSession accessible for debugging
    private(set) var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "camera.feed.queue", qos: .userInitiated)
    private(set) var frameCount = 0
    
    // IMPORTANT: Keep strong reference to delegate to prevent deallocation
    private var videoDelegate: VideoOutputDelegate?
    
    // CIContext for image conversion
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    
    // Add session monitoring
    private var sessionObserver: NSObjectProtocol?
    
    // REVERTED: Back to original frame rate for better quality
    private var lastFrameTime: CFTimeInterval = 0
    private var targetFrameInterval: CFTimeInterval = 1.0/30.0 // Back to 30fps for better quality
    private var lastProcessedImage: CGImage?
    private var lastProcessedNSImage: NSImage?
    private var imageConversionCount = 0
    
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
        // First check camera permissions
        let hasPermission = await CameraPermissionHelper.checkAndRequestCameraPermission()
        guard hasPermission else {
            connectionStatus = .error("Camera permission denied")
            print("❌ Camera permission denied for: \(device.displayName)")
            return
        }
        
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
            
            // FULL QUALITY: Use the highest quality presets available
            let presets: [AVCaptureSession.Preset] = [.high, .medium, .low]
            var selectedPreset: AVCaptureSession.Preset = .high // Start with highest quality
            
            for preset in presets {
                if session.canSetSessionPreset(preset) {
                    selectedPreset = preset
                    break
                }
            }
            
            session.sessionPreset = selectedPreset
            print("   - Selected session preset: \(selectedPreset.rawValue)")
            
            // Add video input
            let videoInput = try AVCaptureDeviceInput(device: captureDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                print("✅ Added video input for: \(device.displayName)")
                
                let formatDescription = captureDevice.activeFormat.formatDescription
                let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                print("   - Resolution: \(dimensions.width)x\(dimensions.height)")
            } else {
                throw CameraFeedError.cannotAddInput
            }
            
            // Configure video output with optimal settings
            let output = AVCaptureVideoDataOutput()
            
            // FULL QUALITY: Use highest quality video settings
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            // FULL QUALITY: Don't discard frames - process everything
            output.alwaysDiscardsLateVideoFrames = false
            
            // Create and retain delegate
            let delegate = VideoOutputDelegate(feed: self)
            self.videoDelegate = delegate
            
            output.setSampleBufferDelegate(delegate, queue: videoQueue)
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                print("✅ Added video output for: \(device.displayName)")
            } else {
                throw CameraFeedError.cannotAddOutput
            }
            
            // Configure video connection
            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                print("   - Video connection configured")
            }
            
            session.commitConfiguration()
            
            self.captureSession = session
            self.videoOutput = output
            
            // Add session state monitoring
            sessionObserver = NotificationCenter.default.addObserver(
                forName: .AVCaptureSessionDidStartRunning,
                object: session,
                queue: .main
            ) { _ in
                print("📹 Session started running notification for: \(self.device.displayName)")
            }
            
            // Start session
            print("🎬 Starting capture session for: \(device.displayName)")
            session.startRunning()
            
            // Wait and verify session is running
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            if session.isRunning {
                isActive = true
                connectionStatus = .connected
                frameCount = 0
                lastFrameTime = CACurrentMediaTime()
                
                print("✅ Camera feed started successfully: \(device.displayName)")
                
                // Start frame monitoring with less frequent checking
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
            try? await Task.sleep(nanoseconds: 5_000_000_000) // Check every 5 seconds
            
            print("📊 Camera feed \(device.displayName): \(frameCount) frames in last 5 seconds")
            frameCount = 0
        }
    }
    
    func stopCapture() {
        // Remove session observer
        if let observer = sessionObserver {
            NotificationCenter.default.removeObserver(observer)
            sessionObserver = nil
        }
        
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        videoDelegate = nil
        isActive = false
        connectionStatus = .disconnected
        currentFrame = nil
        previewImage = nil
        previewNSImage = nil
        frameCount = 0
        
        print("🛑 Camera feed stopped: \(device.displayName)")
    }
    
    // FULL QUALITY: Process EVERY frame with no throttling or caching
    private func updateFrame(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        currentFrame = pixelBuffer
        
        // Convert EVERY frame immediately - no caching or throttling
        updateImages(pixelBuffer)
        
        // Trigger UI updates for EVERY frame
        objectWillChange.send()
        
        // Minimal debug logging
        if frameCount % 150 == 1 {
            print("🎥 Camera feed '\(device.displayName)' frame \(frameCount)")
        }
    }
    
    // FULL QUALITY: Convert every frame immediately
    private func updateImages(_ pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Convert CVPixelBuffer to CGImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }
        
        // Create NSImage
        let nsImage = NSImage(size: NSSize(width: width, height: height))
        nsImage.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        
        // Update EVERY frame - no caching
        previewImage = cgImage
        previewNSImage = nsImage
    }
    
    private class VideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private weak var feed: CameraFeed?
        private var debugFrameCount = 0
        
        init(feed: CameraFeed) {
            self.feed = feed
            super.init()
            print("📹 VideoOutputDelegate created for \(feed.device.displayName)")
        }
        
        deinit {
            print("🗑️ VideoOutputDelegate deallocated for \(feed?.device.displayName ?? "unknown")")
        }
        
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            debugFrameCount += 1
            
            if debugFrameCount == 1 {
                print("🎉 FIRST FRAME RECEIVED for \(self.feed?.device.displayName ?? "unknown")!")
            }
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { 
                return 
            }
            
            // Minimal debug logging
            if debugFrameCount <= 3 {
                print("🎥 VideoOutputDelegate received frame \(debugFrameCount) for \(self.feed?.device.displayName ?? "unknown")")
            }
            
            // Process EVERY frame immediately
            Task { @MainActor in
                self.feed?.currentSampleBuffer = sampleBuffer
                self.feed?.updateFrame(pixelBuffer)
            }
        }
        
        func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            print("⚠️ Dropped video frame \(debugFrameCount) from \(self.feed?.device.displayName ?? "unknown camera")")
        }
    }
    
    private func verifyDelegateReceivingFrames() async {
        // Wait a few seconds then check if delegate is receiving frames
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        if frameCount == 0 && connectionStatus == .connected {
            print("⚠️ WARNING: Camera session running but no frames received for \(device.displayName)")
            
            // Try restarting the session
            print("🔄 Attempting to restart session for \(device.displayName)")
            captureSession?.stopRunning()
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            captureSession?.startRunning()
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
            print("📹 Feed already exists for \(device.displayName), returning existing feed")
            return existingFeed
        }
        
        print("🎬 Creating new camera feed for: \(device.displayName)")
        let feed = CameraFeed(device: device)
        
        // Add to active feeds BEFORE starting capture
        activeFeeds.append(feed)
        
        // PERFORMANCE: Less frequent UI updates
        objectWillChange.send()
        print("📱 Added feed to activeFeeds array - count now: \(activeFeeds.count)")
        
        await feed.startCapture()
        
        // Verify the feed started successfully
        if feed.connectionStatus == .connected {
            print("✅ Camera feed started successfully: \(device.displayName)")
            
            // PERFORMANCE: Reduce UI update frequency
            feed.objectWillChange.send()
            objectWillChange.send()
            
            return feed
        } else {
            print("❌ Camera feed failed to start: \(device.displayName) - \(feed.connectionStatus.displayText)")
            return feed // Return the feed even if failed so UI can show error state
        }
    }
    
    /// Stop and remove a camera feed
    func stopFeed(_ feed: CameraFeed) {
        print("🛑 Stopping camera feed: \(feed.device.displayName)")
        feed.stopCapture()
        activeFeeds.removeAll { $0.id == feed.id }
        
        if selectedFeedForLiveProduction?.id == feed.id {
            selectedFeedForLiveProduction = nil
        }
    }
    
    /// Select a feed for live production use and connect to StreamingViewModel
    func selectFeedForLiveProduction(_ feed: CameraFeed) async {
        print("📺 CameraFeedManager: Selecting feed for live production - \(feed.device.displayName)")
        
        selectedFeedForLiveProduction = feed
        
        // PERFORMANCE: Reduce UI update frequency
        await MainActor.run {
            feed.objectWillChange.send()
            self.objectWillChange.send()
            print("✅ Feed selection complete with UI updates triggered")
        }
        
        // Verify feed is active before selection
        if feed.connectionStatus != .connected {
            print("⚠️ Warning: Selected feed is not connected - status: \(feed.connectionStatus.displayText)")
        } else {
            print("✅ Selected feed is connected and ready")
        }
    }
    
    /// Get the current frame from the selected live production feed
    var liveProductionFrame: CVPixelBuffer? {
        return selectedFeedForLiveProduction?.currentFrame
    }
    
    /// Get the preview image from the selected live production feed
    var liveProductionPreviewImage: CGImage? {
        return selectedFeedForLiveProduction?.previewImage
    }
    
    /// Get the NSImage from the selected live production feed (macOS optimized)
    var liveProductionNSImage: NSImage? {
        return selectedFeedForLiveProduction?.previewNSImage
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
        print("🛑 Stopping all camera feeds (\(activeFeeds.count) active)")
        for feed in activeFeeds {
            feed.stopCapture()
        }
        activeFeeds.removeAll()
        selectedFeedForLiveProduction = nil
    }
    
    /// Debug camera detection issues
    func debugCameraDetection() async {
        await cameraDeviceManager.debugCameraDetection()
        
        // Additional feed-specific debugging
        print("🔍 Camera Feed Manager Debug:")
        print("   - Active feeds: \(activeFeeds.count)")
        for feed in activeFeeds {
            print("     - \(feed.device.displayName): \(feed.connectionStatus.displayText)")
            print("       - Has frames: \(feed.currentFrame != nil)")
            print("       - Has CGImage: \(feed.previewImage != nil)")
            print("       - Has NSImage: \(feed.previewNSImage != nil)")
        }
    }
}