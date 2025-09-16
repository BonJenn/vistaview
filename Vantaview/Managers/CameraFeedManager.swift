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

actor CameraImageConverter {
    private let ciContext = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
    
    func makeImages(from pixelBuffer: CVPixelBuffer) -> (CGImage?, NSImage?) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return (nil, nil)
        }
        
        let nsImage = NSImage(size: NSSize(width: width, height: height))
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        nsImage.addRepresentation(bitmapRep)
        
        return (cgImage, nsImage)
    }
}

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
    
    private(set) var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "camera.feed.queue", qos: .userInitiated)
    
    @Published private(set) var frameCount = 0
    
    private var videoDelegate: VideoOutputDelegate?
    private var sessionObserver: NSObjectProtocol?
    private let converter = CameraImageConverter()
    
    private var lastProcessedPixelBuffer: CVPixelBuffer?
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
        let hasPermission = await CameraPermissionHelper.checkAndRequestCameraPermission()
        guard hasPermission else {
            connectionStatus = .error("Camera permission denied")
            return
        }
        
        guard let captureDevice = device.captureDevice else {
            connectionStatus = .error("No capture device available")
            return
        }
        
        connectionStatus = .connecting
        
        do {
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            let presets: [AVCaptureSession.Preset] = [.high, .medium, .low]
            var selectedPreset: AVCaptureSession.Preset = .medium
            for preset in presets where session.canSetSessionPreset(preset) {
                selectedPreset = preset
                break
            }
            session.sessionPreset = selectedPreset
            
            let videoInput = try AVCaptureDeviceInput(device: captureDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                throw CameraFeedError.cannotAddInput
            }
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            
            let delegate = VideoOutputDelegate(feed: self)
            self.videoDelegate = delegate
            output.setSampleBufferDelegate(delegate, queue: videoQueue)
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            } else {
                throw CameraFeedError.cannotAddOutput
            }
            
            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            
            session.commitConfiguration()
            
            self.captureSession = session
            self.videoOutput = output
            
            sessionObserver = NotificationCenter.default.addObserver(
                forName: .AVCaptureSessionDidStartRunning,
                object: session,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.connectionStatus = .connected
                    self?.isActive = true
                }
            }
            
            session.startRunning()
            
            try await Task.sleep(nanoseconds: 150_000_000)
            if session.isRunning {
                connectionStatus = .connected
                isActive = true
                frameCount = 0
                objectWillChange.send()
            } else {
                throw CameraFeedError.deviceNotAvailable
            }
        } catch {
            connectionStatus = .error(error.localizedDescription)
        }
    }
    
    func stopCapture() {
        if let observer = sessionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionObserver = nil
        
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
        
        lastProcessedPixelBuffer = nil
    }
    
    private func updateFrame(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        currentFrame = pixelBuffer
        
        if frameCount <= 3 && connectionStatus != .connected {
            connectionStatus = .connected
            isActive = true
        }
        
        // Push a CGImage/NSImage in parallel for any fallback UI
        if shouldProcessNewFrame(pixelBuffer) {
            let pb = pixelBuffer
            Task {
                try? Task.checkCancellation()
                let (cg, ns) = await converter.makeImages(from: pb)
                try? Task.checkCancellation()
                await MainActor.run {
                    self.previewImage = cg
                    self.previewNSImage = ns
                    self.objectWillChange.send()
                }
            }
        } else {
            objectWillChange.send()
        }
    }
    
    private func shouldProcessNewFrame(_ pixelBuffer: CVPixelBuffer) -> Bool {
        guard let lastPixelBuffer = lastProcessedPixelBuffer else {
            lastProcessedPixelBuffer = pixelBuffer
            return true
        }
        
        let currentWidth = CVPixelBufferGetWidth(pixelBuffer)
        let currentHeight = CVPixelBufferGetHeight(pixelBuffer)
        let lastWidth = CVPixelBufferGetWidth(lastPixelBuffer)
        let lastHeight = CVPixelBufferGetHeight(lastPixelBuffer)
        
        if currentWidth != lastWidth || currentHeight != lastHeight {
            lastProcessedPixelBuffer = pixelBuffer
            return true
        }
        
        if let sb = currentSampleBuffer {
            let ts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            if abs(ts - lastFrameTimestamp) > 0.0005 {
                lastFrameTimestamp = ts
                lastProcessedPixelBuffer = pixelBuffer
                return true
            }
        } else {
            lastProcessedPixelBuffer = pixelBuffer
            return true
        }
        
        return false
    }
    
    private class VideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private weak var feed: CameraFeed?
        
        init(feed: CameraFeed) {
            self.feed = feed
            super.init()
        }
        
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            Task { @MainActor in
                self.feed?.currentSampleBuffer = sampleBuffer
                if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    self.feed?.updateFrame(pb)
                }
            }
        }
        
        func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
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

@MainActor
final class CameraFeedManager: ObservableObject {
    @Published var activeFeeds: [CameraFeed] = []
    @Published var selectedFeedForLiveProduction: CameraFeed?
    @Published var isDiscovering = false
    @Published var lastDiscoveryError: String?
    
    let cameraDeviceManager: CameraDeviceManager
    
    weak var streamingViewModel: StreamingViewModel?
    
    private var lastManagerUIUpdate = CACurrentMediaTime()
    private let managerUIUpdateInterval: CFTimeInterval = 1.0/30.0
    
    init(cameraDeviceManager: CameraDeviceManager) {
        self.cameraDeviceManager = cameraDeviceManager
        
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
    
    func setStreamingViewModel(_ viewModel: StreamingViewModel) {
        self.streamingViewModel = viewModel
    }
    
    func startFeed(for device: CameraDevice) async -> CameraFeed? {
        if let existingFeed = activeFeeds.first(where: { $0.device.deviceID == device.deviceID }) {
            if existingFeed.frameCount > 0 && existingFeed.connectionStatus != .connected {
                existingFeed.connectionStatus = .connected
                existingFeed.isActive = true
                existingFeed.objectWillChange.send()
            }
            return existingFeed
        }
        
        let feed = CameraFeed(device: device)
        activeFeeds.append(feed)
        triggerManagerUIUpdate()
        
        await feed.startCapture()
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        if feed.frameCount > 0 && feed.connectionStatus != .connected {
            feed.connectionStatus = .connected
            feed.isActive = true
            feed.objectWillChange.send()
            triggerManagerUIUpdate()
        }
        
        return feed
    }
    
    private func triggerManagerUIUpdate() {
        let currentTime = CACurrentMediaTime()
        if currentTime - lastManagerUIUpdate >= managerUIUpdateInterval {
            lastManagerUIUpdate = currentTime
            objectWillChange.send()
        }
    }
    
    func stopFeed(_ feed: CameraFeed) {
        feed.stopCapture()
        activeFeeds.removeAll { $0.id == feed.id }
        
        if selectedFeedForLiveProduction?.id == feed.id {
            selectedFeedForLiveProduction = nil
        }
        
        triggerManagerUIUpdate()
    }
    
    func selectFeedForLiveProduction(_ feed: CameraFeed) async {
        selectedFeedForLiveProduction = feed
        feed.objectWillChange.send()
        self.triggerManagerUIUpdate()
    }
    
    var liveProductionFrame: CVPixelBuffer? {
        return selectedFeedForLiveProduction?.currentFrame
    }
    
    var liveProductionPreviewImage: CGImage? {
        return selectedFeedForLiveProduction?.previewImage
    }
    
    var liveProductionNSImage: NSImage? {
        return selectedFeedForLiveProduction?.previewNSImage
    }
    
    func getAvailableDevices() async -> [CameraDevice] {
        await cameraDeviceManager.discoverDevices()
        return cameraDeviceManager.availableDevices
    }
    
    func forceRefreshDevices() async {
        await cameraDeviceManager.forceRefresh()
    }
    
    var availableDevices: [CameraDevice] {
        return cameraDeviceManager.availableDevices
    }
    
    func stopAllFeeds() {
        for feed in activeFeeds {
            feed.stopCapture()
        }
        activeFeeds.removeAll()
        selectedFeedForLiveProduction = nil
        triggerManagerUIUpdate()
    }
    
    func debugCameraDetection() async {
        await cameraDeviceManager.debugCameraDetection()
    }
}