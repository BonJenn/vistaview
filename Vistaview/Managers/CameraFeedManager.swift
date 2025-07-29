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
    @Published var previewNSImage: NSImage? // Add NSImage for better SceneKit compatibility
    
    // Make captureSession accessible for debugging
    private(set) var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "camera.feed.queue", qos: .userInitiated)
    private(set) var frameCount = 0 // Make frameCount accessible
    
    // IMPORTANT: Keep strong reference to delegate to prevent deallocation
    private var videoDelegate: VideoOutputDelegate?
    
    // Add CIContext for better image conversion performance
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    
    // Add session monitoring
    private var sessionObserver: NSObjectProtocol?
    
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
        print("   - Device unique ID: \(captureDevice.uniqueID)")
        print("   - Device model ID: \(captureDevice.modelID)")
        print("   - Device is connected: \(captureDevice.isConnected)")
        
        do {
            // Create capture session with explicit configuration
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            // Try different session presets in order of preference
            let presets: [AVCaptureSession.Preset] = [.medium, .low, .cif352x288]
            var selectedPreset: AVCaptureSession.Preset = .low
            
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
                
                // Log detailed input format information
                print("   - Active format: \(captureDevice.activeFormat)")
                print("   - Frame rate: \(captureDevice.activeVideoMinFrameDuration)")
                
                let formatDescription = captureDevice.activeFormat.formatDescription
                let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                print("   - Resolution: \(dimensions.width)x\(dimensions.height)")
            } else {
                throw CameraFeedError.cannotAddInput
            }
            
            // Configure video output with minimal settings first
            let output = AVCaptureVideoDataOutput()
            
            // Use the most basic video settings that should work
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            // Configure frame delivery
            output.alwaysDiscardsLateVideoFrames = true
            
            // Create and retain delegate
            let delegate = VideoOutputDelegate(feed: self)
            self.videoDelegate = delegate // IMPORTANT: Keep strong reference
            
            output.setSampleBufferDelegate(delegate, queue: videoQueue)
            print("   - Created and assigned video output delegate")
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                print("✅ Added video output for: \(device.displayName)")
                print("   - Video settings: \(output.videoSettings)")
                print("   - Discards late frames: \(output.alwaysDiscardsLateVideoFrames)")
            } else {
                throw CameraFeedError.cannotAddOutput
            }
            
            // Configure video connection
            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                
                print("   - Video connection configured")
                print("   - Video orientation: \(connection.videoOrientation.rawValue)")
                print("   - Connection is active: \(connection.isActive)")
                print("   - Connection is enabled: \(connection.isEnabled)")
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
            
            print("🔍 Session verification for: \(device.displayName)")
            print("   - Session is running: \(session.isRunning)")
            print("   - Session inputs: \(session.inputs.count)")
            print("   - Session outputs: \(session.outputs.count)")
            
            if let input = session.inputs.first as? AVCaptureDeviceInput {
                print("   - Input device: \(input.device.localizedName)")
                print("   - Input ports: \(input.ports.count)")
            }
            
            if let output = session.outputs.first as? AVCaptureVideoDataOutput {
                print("   - Output delegate set: \(output.sampleBufferDelegate != nil)")
                print("   - Output connection active: \(output.connection(with: .video)?.isActive ?? false)")
            }
            
            if session.isRunning {
                isActive = true
                connectionStatus = .connected
                frameCount = 0
                
                print("✅ Camera feed started successfully: \(device.displayName)")
                
                // Start frame monitoring with more aggressive checking
                Task {
                    await monitorFrameRate()
                }
                
                // Start delegate verification
                Task {
                    await verifyDelegateReceivingFrames()
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
            print("   - Has NSImage: \(previewNSImage != nil)")
            print("   - Session running: \(captureSession?.isRunning ?? false)")
            
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
        videoDelegate = nil // Release delegate
        isActive = false
        connectionStatus = .disconnected
        currentFrame = nil
        previewImage = nil
        previewNSImage = nil
        frameCount = 0
        
        print("🛑 Camera feed stopped: \(device.displayName)")
    }
    
    private func updateFrame(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        currentFrame = pixelBuffer
        
        // Convert pixel buffer to both CGImage and NSImage for maximum compatibility
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Debug: Log frame processing for first few frames
        if frameCount <= 5 {
            print("🔄 Processing frame \(frameCount) for \(device.displayName)")
            print("   - Pixel buffer size: \(width)x\(height)")
            print("   - Pixel format: \(CVPixelBufferGetPixelFormatType(pixelBuffer))")
        }
        
        // Create CIImage from pixel buffer (most efficient)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Convert to CGImage using CIContext (optimized)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            print("❌ Failed to create CGImage from CIImage for \(device.displayName)")
            return
        }
        
        // FIXED: Force new NSImage creation to ensure SwiftUI detects changes
        let newNSImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        
        // Update both images - force new object references to trigger SwiftUI updates
        previewImage = cgImage
        previewNSImage = newNSImage
        
        // CRITICAL: Force SwiftUI to detect the change by triggering objectWillChange manually
        objectWillChange.send()
        
        // Debug: Log successful conversion for first few frames
        if frameCount <= 5 {
            print("✅ Successfully converted frame \(frameCount) to images for \(device.displayName)")
            print("   - CGImage: \(cgImage.width)x\(cgImage.height)")
            print("   - NSImage: \(newNSImage.size)")
            print("   - Triggered objectWillChange for SwiftUI update")
        }
        
        // Debug: Log frame updates occasionally
        if frameCount % 150 == 1 { // Every ~5 seconds at 30fps
            print("🎥 Camera feed '\(device.displayName)' frame \(frameCount): \(cgImage.width)x\(cgImage.height)")
            print("   - CVPixelBuffer format: \(CVPixelBufferGetPixelFormatType(pixelBuffer))")
            print("   - Color space: \(cgImage.colorSpace?.name as? String ?? "unknown")")
            print("   - Alpha info: \(cgImage.alphaInfo.rawValue)")
            print("   - Created NSImage: \(newNSImage.size)")
        }
    }
    
    private class VideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private weak var feed: CameraFeed?
        private var debugFrameCount = 0 // Local counter for debugging
        
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
            
            // Debug: Log first frame immediately
            if debugFrameCount == 1 {
                print("🎉 FIRST FRAME RECEIVED for \(self.feed?.device.displayName ?? "unknown")!")
            }
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { 
                print("❌ No pixel buffer in sample buffer for frame \(debugFrameCount)")
                return 
            }
            
            // Debug: Log first few frames
            if debugFrameCount <= 5 {
                print("🎥 VideoOutputDelegate received frame \(debugFrameCount) for \(self.feed?.device.displayName ?? "unknown")")
                print("   - Pixel buffer size: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
                print("   - Pixel format: \(CVPixelBufferGetPixelFormatType(pixelBuffer))")
            }
            
            // Update on main thread for UI consistency
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
            print("   - Session running: \(captureSession?.isRunning ?? false)")
            print("   - Delegate exists: \(videoDelegate != nil)")
            print("   - Output exists: \(videoOutput != nil)")
            
            if let output = videoOutput {
                print("   - Output has delegate: \(output.sampleBufferDelegate != nil)")
                if let connection = output.connection(with: .video) {
                    print("   - Connection active: \(connection.isActive)")
                    print("   - Connection enabled: \(connection.isEnabled)")
                }
            }
            
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
        
        // Trigger UI update immediately when feed is added
        objectWillChange.send()
        print("📱 Added feed to activeFeeds array - count now: \(activeFeeds.count)")
        
        await feed.startCapture()
        
        // Verify the feed started successfully
        if feed.connectionStatus == .connected {
            print("✅ Camera feed started successfully: \(device.displayName)")
            
            // Trigger another UI update when connection is confirmed
            feed.objectWillChange.send()
            objectWillChange.send()
            
            return feed
        } else {
            print("❌ Camera feed failed to start: \(device.displayName) - \(feed.connectionStatus.displayText)")
            
            // Remove failed feed but keep it in the list briefly to show error state
            // Don't remove immediately - let user see the error
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
        print("   - Current status: \(feed.connectionStatus.displayText)")
        print("   - Has preview: \(feed.previewImage != nil)")
        print("   - Frame count: \(feed.frameCount)")
        
        selectedFeedForLiveProduction = feed
        
        // CRITICAL: Force UI updates immediately
        await MainActor.run {
            // Trigger updates for the selected feed
            feed.objectWillChange.send()
            
            // Trigger update for the manager
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