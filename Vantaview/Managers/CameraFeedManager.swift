//
//  CameraFeedManager.swift
//  Vantaview
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
    
    // PERFORMANCE: Add background image processing queue
    private let imageProcessingQueue = DispatchQueue(label: "camera.imageprocessing.queue", qos: .utility)
    
    @Published private(set) var frameCount = 0
    
    // IMPORTANT: Keep strong reference to delegate to prevent deallocation
    private var videoDelegate: VideoOutputDelegate?
    
    // CIContext for image conversion - reuse instance for efficiency
    private let ciContext = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
    
    // Add session monitoring
    private var sessionObserver: NSObjectProtocol?
    
    // PERFORMANCE: UI update throttling - only update UI at 15fps instead of 30fps
    private var lastUIUpdateTime: CFTimeInterval = 0
    private let uiUpdateInterval: CFTimeInterval = 1.0/15.0 // 15fps for UI updates
    
    // PERFORMANCE: Image caching to avoid reprocessing identical frames
    private var lastProcessedPixelBuffer: CVPixelBuffer?
    private var cachedCGImage: CGImage?
    private var cachedNSImage: NSImage?
    private var imageConversionCount = 0
    
    // PERFORMANCE: Frame change detection
    private var lastFrameTimestamp: CFTimeInterval = 0
    
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
            
            // PERFORMANCE: Use medium quality for better CPU efficiency while maintaining good visual quality
            let presets: [AVCaptureSession.Preset] = [.medium, .high, .low]
            var selectedPreset: AVCaptureSession.Preset = .medium // Start with balanced quality/performance
            
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
            
            // PERFORMANCE: Use optimized pixel format
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            // PERFORMANCE: Allow frame dropping to prevent memory buildup
            output.alwaysDiscardsLateVideoFrames = true
            
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
                // UPDATE STATUS TO CONNECTED WHEN SESSION STARTS
                Task { @MainActor in
                    self.connectionStatus = .connected
                    self.isActive = true
                    print("✅ Connection status updated to CONNECTED for: \(self.device.displayName)")
                }
            }
            
            // Start session
            print("🎬 Starting capture session for: \(device.displayName)")
            session.startRunning()
            
            // Wait a moment for session to start
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            if session.isRunning {
                // Set connected status immediately if session is running
                connectionStatus = .connected
                isActive = true
                frameCount = 0
                lastUIUpdateTime = CACurrentMediaTime()
                
                print("✅ Camera feed started successfully: \(device.displayName)")
                print("✅ Connection status set to CONNECTED")
                
                // Force UI update
                objectWillChange.send()
                
                // PERFORMANCE: Less frequent frame monitoring
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
        
        // PERFORMANCE: Clear cached images
        lastProcessedPixelBuffer = nil
        cachedCGImage = nil
        cachedNSImage = nil
        
        print("🛑 Camera feed stopped: \(device.displayName)")
    }
    
    // PERFORMANCE: Optimized frame processing with throttling and caching
    private func updateFrame(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        currentFrame = pixelBuffer
        
        // FORCE CONNECTION STATUS UPDATE ON FIRST FEW FRAMES
        if frameCount <= 3 && connectionStatus != .connected {
            print("🔄 FORCING connection status to CONNECTED on frame \(frameCount)")
            connectionStatus = .connected
            isActive = true
        }
        
        let currentTime = CACurrentMediaTime()
        
        // PERFORMANCE: Only process images and update UI at 15fps instead of 30fps
        let shouldUpdateUI = (currentTime - lastUIUpdateTime) >= uiUpdateInterval
        
        if shouldUpdateUI {
            lastUIUpdateTime = currentTime
            
            // PERFORMANCE: Check if frame actually changed before processing
            if shouldProcessNewFrame(pixelBuffer) {
                // PERFORMANCE: Process images on background thread
                imageProcessingQueue.async { [weak self] in
                    self?.updateImagesAsync(pixelBuffer) { [weak self] cgImage, nsImage in
                        // Update UI on main thread
                        DispatchQueue.main.async {
                            self?.previewImage = cgImage
                            self?.previewNSImage = nsImage
                            self?.objectWillChange.send()
                        }
                    }
                }
            } else {
                // PERFORMANCE: Still trigger UI update but without image processing
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
        }
        
        // PERFORMANCE: Reduce debug logging frequency
        if frameCount <= 10 {
            print("🎥 Camera feed '\(device.displayName)' frame \(frameCount) - INITIAL FRAMES")
            print("   - Status: \(connectionStatus.displayText)")
            print("   - Has previewImage: \(previewImage != nil)")
            print("   - Has previewNSImage: \(previewNSImage != nil)")
            print("   - isActive: \(isActive)")
        } else if frameCount % 300 == 1 { // Log every 10 seconds at 30fps instead of every 5 seconds
            print("🎥 Camera feed '\(device.displayName)' frame \(frameCount)")
        }
    }
    
    // PERFORMANCE: Check if we need to process a new frame (detect changes)
    private func shouldProcessNewFrame(_ pixelBuffer: CVPixelBuffer) -> Bool {
        // If no cached frame, always process
        guard let lastPixelBuffer = lastProcessedPixelBuffer else {
            lastProcessedPixelBuffer = pixelBuffer
            return true
        }
        
        // Simple frame change detection using CVPixelBuffer properties
        let currentWidth = CVPixelBufferGetWidth(pixelBuffer)
        let currentHeight = CVPixelBufferGetHeight(pixelBuffer)
        let lastWidth = CVPixelBufferGetWidth(lastPixelBuffer)
        let lastHeight = CVPixelBufferGetHeight(lastPixelBuffer)
        
        // If dimensions changed, definitely process
        if currentWidth != lastWidth || currentHeight != lastHeight {
            lastProcessedPixelBuffer = pixelBuffer
            return true
        }
        
        // PERFORMANCE: Use frame timestamp for better change detection
        let currentTimestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(currentSampleBuffer!))
        if abs(currentTimestamp - lastFrameTimestamp) > 0.001 { // More than 1ms difference
            lastFrameTimestamp = currentTimestamp
            lastProcessedPixelBuffer = pixelBuffer
            return true
        }
        
        return false
    }
    
    // PERFORMANCE: Async image processing to keep main thread free
    private func updateImagesAsync(_ pixelBuffer: CVPixelBuffer, completion: @escaping (CGImage?, NSImage?) -> Void) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Convert CVPixelBuffer to CGImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            if frameCount <= 5 {
                print("❌ Failed to create CGImage from pixel buffer - frame \(frameCount)")
            }
            completion(nil, nil)
            return
        }
        
        // PERFORMANCE: Create NSImage more efficiently
        let nsImage = NSImage(size: NSSize(width: width, height: height))
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        nsImage.addRepresentation(bitmapRep)
        
        // Verify NSImage was created properly (only for initial frames)
        if frameCount <= 5 {
            print("✅ Created images for frame \(frameCount) - Size: \(width)x\(height)")
            print("   - CGImage valid: \(cgImage.width)x\(cgImage.height)")
            print("   - NSImage valid: \(nsImage.isValid), Size: \(nsImage.size)")
            print("   - NSImage representations: \(nsImage.representations.count)")
        }
        
        imageConversionCount += 1
        completion(cgImage, nsImage)
    }
    
    private class VideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private weak var feed: CameraFeed?
        private var debugFrameCount = 0
        private var lastFrameTime = CACurrentMediaTime()
        
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
            let currentTime = CACurrentMediaTime()
            
            if debugFrameCount == 1 {
                print("🎉 FIRST FRAME RECEIVED for \(self.feed?.device.displayName ?? "unknown")!")
                print("   - Buffer format: \(CMSampleBufferGetFormatDescription(sampleBuffer) != nil ? "Valid" : "Invalid")")
                print("   - Has pixel buffer: \(CMSampleBufferGetImageBuffer(sampleBuffer) != nil)")
                
                // ENSURE CONNECTION STATUS IS SET TO CONNECTED ON FIRST FRAME
                Task { @MainActor in
                    if let feed = self.feed, feed.connectionStatus != .connected {
                        feed.connectionStatus = .connected
                        feed.isActive = true
                        feed.objectWillChange.send()
                        print("🔄 Updated connection status to CONNECTED on first frame")
                    }
                }
            }
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { 
                if debugFrameCount <= 5 {
                    print("❌ No pixel buffer in sample buffer - frame \(debugFrameCount)")
                }
                return 
            }
            
            // PERFORMANCE: Reduce FPS logging frequency
            if debugFrameCount <= 10 {
                let fps = debugFrameCount > 1 ? 1.0 / (currentTime - lastFrameTime) : 0
                print("🎥 VideoOutputDelegate frame \(debugFrameCount) for \(self.feed?.device.displayName ?? "unknown") - FPS: \(String(format: "%.1f", fps))")
            }
            lastFrameTime = currentTime
            
            // PERFORMANCE: Process frames asynchronously to avoid blocking capture thread
            Task { @MainActor in
                self.feed?.currentSampleBuffer = sampleBuffer
                self.feed?.updateFrame(pixelBuffer)
            }
        }
        
        func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            // PERFORMANCE: Reduce dropped frame logging
            if debugFrameCount <= 20 || debugFrameCount % 100 == 0 {
                print("⚠️ Dropped video frame \(debugFrameCount) from \(self.feed?.device.displayName ?? "unknown camera")")
            }
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
    
    // PERFORMANCE: Throttle UI updates for feed manager
    private var lastManagerUIUpdate = CACurrentMediaTime()
    private let managerUIUpdateInterval: CFTimeInterval = 1.0/10.0 // 10fps for manager updates
    
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
            
            // FORCE STATUS CHECK FOR EXISTING FEED
            if existingFeed.frameCount > 0 && existingFeed.connectionStatus != .connected {
                print("🔄 Existing feed has frames but wrong status - fixing...")
                existingFeed.connectionStatus = .connected
                existingFeed.isActive = true
                existingFeed.objectWillChange.send()
            }
            
            return existingFeed
        }
        
        print("🎬 Creating new camera feed for: \(device.displayName)")
        let feed = CameraFeed(device: device)
        
        // Add to active feeds BEFORE starting capture
        activeFeeds.append(feed)
        
        // PERFORMANCE: Throttled UI updates
        triggerManagerUIUpdate()
        print("📱 Added feed to activeFeeds array - count now: \(activeFeeds.count)")
        
        await feed.startCapture()
        
        // FORCE STATUS UPDATE AFTER CAPTURE START
        try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
        
        if feed.frameCount > 0 && feed.connectionStatus != .connected {
            print("🔄 Feed has frames but status is wrong - forcing update...")
            feed.connectionStatus = .connected
            feed.isActive = true
            feed.objectWillChange.send()
            triggerManagerUIUpdate()
        }
        
        // Verify the feed started successfully
        if feed.connectionStatus == .connected || feed.frameCount > 0 {
            print("✅ Camera feed started successfully: \(device.displayName)")
            print("   - Final status: \(feed.connectionStatus.displayText)")
            print("   - Frame count: \(feed.frameCount)")
            print("   - Has preview: \(feed.previewImage != nil)")
            
            // PERFORMANCE: Throttled UI updates
            feed.objectWillChange.send()
            triggerManagerUIUpdate()
            
            return feed
        } else {
            print("❌ Camera feed failed to start: \(device.displayName) - \(feed.connectionStatus.displayText)")
            return feed // Return the feed even if failed so UI can show error state
        }
    }
    
    // PERFORMANCE: Throttled UI updates for manager
    private func triggerManagerUIUpdate() {
        let currentTime = CACurrentMediaTime()
        if currentTime - lastManagerUIUpdate >= managerUIUpdateInterval {
            lastManagerUIUpdate = currentTime
            objectWillChange.send()
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
        
        triggerManagerUIUpdate()
    }
    
    /// Select a feed for live production use and connect to StreamingViewModel
    func selectFeedForLiveProduction(_ feed: CameraFeed) async {
        print("📺 CameraFeedManager: Selecting feed for live production - \(feed.device.displayName)")
        
        selectedFeedForLiveProduction = feed
        
        // PERFORMANCE: Throttled UI updates
        await MainActor.run {
            feed.objectWillChange.send()
            self.triggerManagerUIUpdate()
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
        triggerManagerUIUpdate()
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