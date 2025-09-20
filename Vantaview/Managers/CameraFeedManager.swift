//
//  CameraFeedManager.swift
//  Vantaview
//
//  Created by AI Assistant - Memory Optimized Version
//

import Foundation
import AVFoundation
import SwiftUI
import SceneKit
import CoreVideo

// MARK: - Memory-Optimized Camera Image Converter Actor

actor CameraImageConverter {
    private let ciContext = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
    private var imageCache: [String: (cgImage: CGImage, nsImage: NSImage, timestamp: CFTimeInterval)] = [:]
    private let maxCacheSize = 5
    
    func makeImages(from pixelBuffer: CVPixelBuffer) async -> (CGImage?, NSImage?) {
        return await withCheckedContinuation { continuation in
            autoreleasepool {
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                _ = "\(width)x\(height)_\(CVPixelBufferGetTypeID())"
                
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                    continuation.resume(returning: (nil, nil))
                    return
                }
                
                let nsImage = NSImage(size: NSSize(width: width, height: height))
                let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                nsImage.addRepresentation(bitmapRep)
                
                continuation.resume(returning: (cgImage, nsImage))
            }
        }
    }
}

@MainActor
final class CameraFeed: ObservableObject, Identifiable {
    let id = UUID()
    let deviceInfo: CameraDeviceInfo
    
    @Published var isActive = false
    @Published var currentFrame: CVPixelBuffer?
    @Published var currentSampleBuffer: CMSampleBuffer?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var previewImage: CGImage?
    @Published var previewNSImage: NSImage?
    
    private var captureSession: CameraCaptureSession?
    private var processingTask: Task<Void, Never>?
    
    @Published private(set) var frameCount = 0
    
    private let converter = CameraImageConverter()
    private var lastProcessedPixelBuffer: CVPixelBuffer?
    private var lastFrameTimestamp: CFTimeInterval = 0
    
    private var lastImageUpdateTime: CFTimeInterval = 0
    private let imageUpdateInterval: CFTimeInterval = 1.0/30.0
    private var frameProcessingCount = 0
    
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
    
    var device: LegacyCameraDevice {
        return LegacyCameraDevice(
            id: deviceInfo.id,
            deviceID: deviceInfo.deviceID,
            displayName: deviceInfo.displayName,
            localizedName: deviceInfo.localizedName,
            modelID: deviceInfo.modelID,
            manufacturer: deviceInfo.manufacturer,
            isConnected: deviceInfo.isConnected
        )
    }
    
    init(deviceInfo: CameraDeviceInfo) {
        self.deviceInfo = deviceInfo
    }
    
    deinit {
        processingTask?.cancel()
        processingTask = nil
        print("🧹 CameraFeed deinit: \(deviceInfo.displayName)")
    }
    
    func startCapture(using deviceManager: DeviceManager) async {
        connectionStatus = .connecting
        
        do {
            try Task.checkCancellation()
            captureSession = try await deviceManager.createCameraCaptureSession(for: deviceInfo.deviceID)
            
            connectionStatus = .connected
            isActive = true
            frameCount = 0
            frameProcessingCount = 0
            
            processingTask = Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                await self.processFramesOptimized()
            }
            
            await MainActor.run {
                self.objectWillChange.send()
            }
            
        } catch is CancellationError {
            connectionStatus = .disconnected
        } catch {
            connectionStatus = .error(error.localizedDescription)
        }
    }
    
    func stopCapture() async {
        processingTask?.cancel()
        processingTask = nil
        
        if let session = captureSession {
            await session.stop()
        }
        captureSession = nil
        
        isActive = false
        connectionStatus = .disconnected
        currentFrame = nil
        previewImage = nil
        previewNSImage = nil
        frameCount = 0
        frameProcessingCount = 0
        
        lastProcessedPixelBuffer = nil
        
        await MainActor.run {
            self.objectWillChange.send()
        }
    }
    
    private func processFramesOptimized() async {
        guard let session = captureSession else { return }
        let sampleBufferStream = await session.sampleBuffers()
        
        for await sampleBuffer in sampleBufferStream {
            if Task.isCancelled { break }
            
            await MainActor.run {
                autoreleasepool {
                    self.currentSampleBuffer = sampleBuffer
                    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        self.updateFrameOptimized(pixelBuffer)
                    }
                }
            }
        }
    }
    
    private func updateFrameOptimized(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        frameProcessingCount += 1
        currentFrame = pixelBuffer
        
        if frameCount <= 3 && connectionStatus != .connected {
            connectionStatus = .connected
            isActive = true
        }
        
        let currentTime = CACurrentMediaTime()
        let shouldProcessImage = shouldProcessNewFrame(pixelBuffer) &&
                                (currentTime - lastImageUpdateTime >= imageUpdateInterval)
        
        if shouldProcessImage {
            lastImageUpdateTime = currentTime
            
            Task(priority: .utility) { [weak self] in
                guard let self else { return }
                try? Task.checkCancellation()
                let (cg, ns) = await self.converter.makeImages(from: pixelBuffer)
                try? Task.checkCancellation()
                
                await MainActor.run {
                    autoreleasepool {
                        self.previewImage = cg
                        self.previewNSImage = ns
                        self.objectWillChange.send()
                    }
                }
            }
        } else {
            if frameProcessingCount % 10 == 0 {
                objectWillChange.send()
            }
        }
        
        if frameProcessingCount % 300 == 0 {
            autoreleasepool {
                if frameProcessingCount > 600 {
                    lastProcessedPixelBuffer = nil
                }
            }
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
            if abs(ts - lastFrameTimestamp) > 0.033 {
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
}

// MARK: - Backwards Compatibility

struct CameraDevice {
    let deviceID: String
    let displayName: String
    let id: String
    
    init(from info: CameraDeviceInfo) {
        self.deviceID = info.deviceID
        self.displayName = info.displayName
        self.id = info.id
    }
}

@MainActor
final class CameraFeedManager: ObservableObject {
    @Published var activeFeeds: [CameraFeed] = []
    @Published var selectedFeedForLiveProduction: CameraFeed?
    @Published var isDiscovering = false
    @Published var lastDiscoveryError: String?
    
    private let deviceManager: DeviceManager
    weak var streamingViewModel: StreamingViewModel?
    
    private var lastManagerUIUpdate = CACurrentMediaTime()
    private let managerUIUpdateInterval: CFTimeInterval = 1.0/15.0
    private var deviceChangeTask: Task<Void, Never>?
    
    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
        startDeviceChangeMonitoring()
        startInitialDeviceDiscovery()
    }
    
    deinit {
        deviceChangeTask?.cancel()
        deviceChangeTask = nil
        print("🧹 CameraFeedManager deinit")
    }
    
    private func startDeviceChangeMonitoring() {
        deviceChangeTask = Task { [weak self] in
            guard let self else { return }
            
            do {
                let changeStream = await self.deviceManager.deviceChangeNotifications()
                for await change in changeStream {
                    autoreleasepool {
                        Task { [weak self] in
                            guard let self else { return }
                            await self.handleDeviceChange(change)
                        }
                    }
                }
            } catch {
                print("Device change monitoring error: \(error)")
            }
        }
    }
    
    private func startInitialDeviceDiscovery() {
        Task { [weak self] in
            guard let self else { return }
            await self.performInitialDeviceDiscovery()
        }
    }
    
    private func performInitialDeviceDiscovery() async {
        await refreshDevices()
    }
    
    func setStreamingViewModel(_ viewModel: StreamingViewModel) {
        self.streamingViewModel = viewModel
    }
    
    func startFeed(for deviceInfo: CameraDeviceInfo) async -> CameraFeed? {
        if let existingFeed = activeFeeds.first(where: { $0.deviceInfo.deviceID == deviceInfo.deviceID }) {
            if existingFeed.frameCount > 0 && existingFeed.connectionStatus != .connected {
                existingFeed.connectionStatus = .connected
                existingFeed.isActive = true
                existingFeed.objectWillChange.send()
            }
            return existingFeed
        }
        
        let feed = CameraFeed(deviceInfo: deviceInfo)
        
        await MainActor.run {
            self.activeFeeds.append(feed)
            self.triggerManagerUIUpdate()
        }
        
        await feed.startCapture(using: deviceManager)
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            if feed.frameCount > 0 && feed.connectionStatus != .connected {
                feed.connectionStatus = .connected
                feed.isActive = true
                feed.objectWillChange.send()
                self.triggerManagerUIUpdate()
            }
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
    
    func stopFeed(_ feed: CameraFeed) async {
        await feed.stopCapture()
        
        await MainActor.run {
            self.activeFeeds.removeAll { $0.id == feed.id }
            
            if self.selectedFeedForLiveProduction?.id == feed.id {
                self.selectedFeedForLiveProduction = nil
            }
            
            self.triggerManagerUIUpdate()
        }
    }
    
    func selectFeedForLiveProduction(_ feed: CameraFeed) async {
        await MainActor.run {
            self.selectedFeedForLiveProduction = feed
            feed.objectWillChange.send()
            self.triggerManagerUIUpdate()
        }
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
        do {
            let (cameras, _) = try await deviceManager.discoverDevices()
            return cameras.map { CameraDevice(from: $0) }
        } catch {
            await MainActor.run {
                self.lastDiscoveryError = error.localizedDescription
            }
            return []
        }
    }
    
    func forceRefreshDevices() async {
        await refreshDevices(forceRefresh: true)
    }
    
    private func refreshDevices(forceRefresh: Bool = false) async {
        await MainActor.run {
            self.isDiscovering = true
            self.lastDiscoveryError = nil
        }
        
        do {
            _ = try await deviceManager.discoverDevices(forceRefresh: forceRefresh)
        } catch {
            await MainActor.run {
                self.lastDiscoveryError = error.localizedDescription
            }
        }
        
        await MainActor.run {
            self.isDiscovering = false
            self.objectWillChange.send()
        }
    }
    
    var availableDevices: [CameraDevice] {
        return []
    }
    
    func stopAllFeeds() async {
        let feedsToStop = activeFeeds
        
        await withTaskGroup(of: Void.self) { group in
            for feed in feedsToStop {
                group.addTask {
                    await feed.stopCapture()
                }
            }
        }
        
        await MainActor.run {
            self.activeFeeds.removeAll()
            self.selectedFeedForLiveProduction = nil
            self.triggerManagerUIUpdate()
        }
        
        autoreleasepool {
            print("🧹 CameraFeedManager: All feeds stopped and cleaned up")
        }
    }
    
    func debugCameraDetection() async {
        let stats = await deviceManager.getDiscoveryStats()
        print("Camera Detection Debug:")
        print("- Total cameras: \(stats.totalCameraDevices)")
        print("- Connected cameras: \(stats.connectedCameraDevices)")
        print("- Last discovery: \(stats.lastDiscoveryTime?.description ?? "Never")")
        print("- Discovery duration: \(stats.discoveryDuration)s")
    }
    
    private func handleDeviceChange(_ change: DeviceChangeNotification) async {
        switch change.changeType {
        case .added(let deviceInfo):
            print("CameraFeedManager: Device added: \(deviceInfo.displayName)")
        case .removed(let deviceID):
            print("CameraFeedManager: Device removed: \(deviceID)")
            if let feed = self.activeFeeds.first(where: { $0.deviceInfo.deviceID == deviceID }) {
                Task {
                    await self.cleanupRemovedDevice(feed)
                }
            }
        case .configurationChanged(let deviceInfo):
            print("CameraFeedManager: Device configuration changed: \(deviceInfo.displayName)")
        }
        
        self.objectWillChange.send()
    }
    
    private func cleanupRemovedDevice(_ feed: CameraFeed) async {
        await feed.stopCapture()
        
        await MainActor.run {
            self.activeFeeds.removeAll { $0.id == feed.id }
            if self.selectedFeedForLiveProduction?.id == feed.id {
                self.selectedFeedForLiveProduction = nil
            }
            self.triggerManagerUIUpdate()
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