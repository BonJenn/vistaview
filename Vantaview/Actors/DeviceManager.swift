//
//  DeviceManager.swift
//  Vantaview
//
//  Device management actor for handling camera and audio device discovery and management off the main thread
//

import Foundation
import AVFoundation
import CoreMedia

/// Sendable representation of a camera device
struct CameraDeviceInfo: Sendable, Identifiable {
    let id: String
    let deviceID: String
    let displayName: String
    let localizedName: String
    let modelID: String
    let manufacturer: String
    let isConnected: Bool
    let supportedFormats: [VideoFormatInfo]
    
    init(from device: AVCaptureDevice) {
        self.id = device.uniqueID
        self.deviceID = device.uniqueID
        self.displayName = device.localizedName
        self.localizedName = device.localizedName
        self.modelID = device.modelID
        self.manufacturer = device.manufacturer ?? "Unknown"
        self.isConnected = device.isConnected
        self.supportedFormats = device.formats.map { VideoFormatInfo(from: $0) }
    }
}

/// Sendable representation of video format information
struct VideoFormatInfo: Sendable, Identifiable {
    let id: String
    let mediaSubType: String
    let dimensions: CGSize
    let frameRateRanges: [FrameRateRange]
    let pixelFormat: String
    
    struct FrameRateRange: Sendable {
        let minFrameRate: Double
        let maxFrameRate: Double
        
        init(from range: AVFrameRateRange) {
            self.minFrameRate = range.minFrameRate
            self.maxFrameRate = range.maxFrameRate
        }
    }
    
    init(from format: AVCaptureDevice.Format) {
        let desc = format.formatDescription
        self.id = "\(CMFormatDescriptionGetMediaSubType(desc))_\(CMVideoFormatDescriptionGetDimensions(desc).width)x\(CMVideoFormatDescriptionGetDimensions(desc).height)"
        self.mediaSubType = String(CMFormatDescriptionGetMediaSubType(desc))
        let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
        self.dimensions = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        self.frameRateRanges = format.videoSupportedFrameRateRanges.map { FrameRateRange(from: $0) }
        self.pixelFormat = String(CMFormatDescriptionGetMediaSubType(desc))
    }
}

/// Sendable representation of an audio device
struct AudioDeviceInfo: Sendable, Identifiable {
    let id: String
    let deviceID: String
    let displayName: String
    let localizedName: String
    let manufacturer: String
    let isConnected: Bool
    let hasBuiltInMicrophone: Bool
    let transportType: String
    
    init(from device: AVCaptureDevice) {
        self.id = device.uniqueID
        self.deviceID = device.uniqueID
        self.displayName = device.localizedName
        self.localizedName = device.localizedName
        self.manufacturer = device.manufacturer ?? "Unknown"
        self.isConnected = device.isConnected
        // Fix: hasBuiltInMicrophone is iOS-only, check for audio media type instead
        self.hasBuiltInMicrophone = device.hasMediaType(.audio)
        // Fix: transportType is an enum, convert to string representation
        self.transportType = String(describing: device.transportType)
    }
}

/// Device change notification
struct DeviceChangeNotification: Sendable {
    enum ChangeType: Sendable {
        case added(CameraDeviceInfo)
        case removed(String) // deviceID
        case configurationChanged(CameraDeviceInfo)
    }
    
    let changeType: ChangeType
    let timestamp: Date
}

/// Device discovery statistics
struct DeviceDiscoveryStats: Sendable {
    let totalCameraDevices: Int
    let totalAudioDevices: Int
    let connectedCameraDevices: Int
    let connectedAudioDevices: Int
    let lastDiscoveryTime: Date?
    let discoveryDuration: TimeInterval
}

/// Actor responsible for managing camera and audio device discovery and configuration
actor DeviceManager {
    
    // MARK: - Device Storage
    
    private var cameraDevices: [String: CameraDeviceInfo] = [:]
    private var audioDevices: [String: AudioDeviceInfo] = [:]
    private var deviceObservers: [NSObjectProtocol] = []
    
    // MARK: - Change Notifications
    
    private var changeNotifications: AsyncStream<DeviceChangeNotification>.Continuation?
    private var deviceChangeStream: AsyncStream<DeviceChangeNotification>?
    
    // MARK: - Discovery State
    
    private var isDiscovering = false
    private var lastDiscoveryTime: Date?
    private var discoveryStats = DeviceDiscoveryStats(
        totalCameraDevices: 0,
        totalAudioDevices: 0,
        connectedCameraDevices: 0,
        connectedAudioDevices: 0,
        lastDiscoveryTime: nil,
        discoveryDuration: 0
    )
    
    // MARK: - Permissions
    
    private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    private var microphonePermissionStatus: AVAuthorizationStatus = .notDetermined
    
    init() async {
        await setupDeviceObservers()
        await requestPermissions()
        await performInitialDiscovery()
    }
    
    deinit {
        // Clean up observers
        for observer in deviceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Device Discovery
    
    /// Perform device discovery
    func discoverDevices(forceRefresh: Bool = false) async throws -> (cameras: [CameraDeviceInfo], audio: [AudioDeviceInfo]) {
        try Task.checkCancellation()
        
        guard !isDiscovering || forceRefresh else {
            return (cameras: Array(cameraDevices.values), audio: Array(audioDevices.values))
        }
        
        let startTime = Date()
        isDiscovering = true
        defer { isDiscovering = false }
        
        // Check permissions first
        await updatePermissionStatus()
        
        // Discover camera devices
        if cameraPermissionStatus == .authorized {
            try await discoverCameraDevices()
        }
        
        // Discover audio devices
        if microphonePermissionStatus == .authorized {
            try await discoverAudioDevices()
        }
        
        // Update statistics
        let discoveryDuration = Date().timeIntervalSince(startTime)
        lastDiscoveryTime = startTime
        discoveryStats = DeviceDiscoveryStats(
            totalCameraDevices: cameraDevices.count,
            totalAudioDevices: audioDevices.count,
            connectedCameraDevices: cameraDevices.values.filter { $0.isConnected }.count,
            connectedAudioDevices: audioDevices.values.filter { $0.isConnected }.count,
            lastDiscoveryTime: startTime,
            discoveryDuration: discoveryDuration
        )
        
        return (cameras: Array(cameraDevices.values), audio: Array(audioDevices.values))
    }
    
    /// Get currently known camera devices
    func getCameraDevices() async -> [CameraDeviceInfo] {
        return Array(cameraDevices.values)
    }
    
    /// Get currently known audio devices
    func getAudioDevices() async -> [AudioDeviceInfo] {
        return Array(audioDevices.values)
    }
    
    /// Get a specific camera device by ID
    func getCameraDevice(by id: String) async -> CameraDeviceInfo? {
        return cameraDevices[id]
    }
    
    /// Get a specific audio device by ID
    func getAudioDevice(by id: String) async -> AudioDeviceInfo? {
        return audioDevices[id]
    }
    
    /// Create a device change notification stream
    func deviceChangeNotifications() async -> AsyncStream<DeviceChangeNotification> {
        if let existingStream = deviceChangeStream {
            return existingStream
        }
        
        let (stream, continuation) = AsyncStream<DeviceChangeNotification>.makeStream()
        changeNotifications = continuation
        deviceChangeStream = stream
        
        return stream
    }
    
    // MARK: - Device Configuration
    
    /// Configure a camera device with specific settings
    func configureCameraDevice(_ deviceID: String, format: VideoFormatInfo? = nil, frameRate: Double? = nil) async throws -> AVCaptureDevice? {
        try Task.checkCancellation()
        
        guard let device = AVCaptureDevice(uniqueID: deviceID) else {
            throw DeviceManagerError.deviceNotFound(deviceID)
        }
        
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        // Configure format if specified
        if let format = format {
            if let deviceFormat = device.formats.first(where: { 
                let desc = $0.formatDescription
                let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
                return dimensions.width == Int32(format.dimensions.width) && 
                       dimensions.height == Int32(format.dimensions.height)
            }) {
                device.activeFormat = deviceFormat
            }
        }
        
        // Configure frame rate if specified
        if let frameRate = frameRate {
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
        }
        
        return device
    }
    
    // MARK: - Permissions
    
    /// Request camera and microphone permissions
    func requestPermissions() async -> (camera: Bool, microphone: Bool) {
        async let cameraPermission = AVCaptureDevice.requestAccess(for: .video)
        async let microphonePermission = AVCaptureDevice.requestAccess(for: .audio)
        
        let (camera, microphone) = await (cameraPermission, microphonePermission)
        
        await updatePermissionStatus()
        
        return (camera: camera, microphone: microphone)
    }
    
    /// Get current permission status
    func getPermissionStatus() async -> (camera: AVAuthorizationStatus, microphone: AVAuthorizationStatus) {
        return (camera: cameraPermissionStatus, microphone: microphonePermissionStatus)
    }
    
    // MARK: - Statistics
    
    /// Get device discovery statistics
    func getDiscoveryStats() async -> DeviceDiscoveryStats {
        return discoveryStats
    }
    
    // MARK: - Device Session Management
    
    /// Create a camera capture session for a specific device
    func createCameraCaptureSession(for deviceID: String, configuration: CameraCaptureConfiguration? = nil) async throws -> CameraCaptureSession {
        try Task.checkCancellation()
        
        guard cameraDevices[deviceID] != nil else {
            throw DeviceManagerError.deviceNotFound(deviceID)
        }
        
        let session = CameraCaptureSession()
        try await session.start(cameraID: deviceID)
        
        return session
    }
    
    // MARK: - Private Implementation
    
    private func setupDeviceObservers() async {
        // Camera device change notifications
        let cameraConnectedObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            Task { [weak self] in
                await self?.handleDeviceConnected(notification)
            }
        }
        
        let cameraDisconnectedObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            Task { [weak self] in
                await self?.handleDeviceDisconnected(notification)
            }
        }
        
        deviceObservers.append(cameraConnectedObserver)
        deviceObservers.append(cameraDisconnectedObserver)
    }
    
    private func performInitialDiscovery() async {
        do {
            _ = try await discoverDevices()
        } catch {
            print("DeviceManager: Initial discovery failed: \(error)")
        }
    }
    
    private func updatePermissionStatus() async {
        cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        microphonePermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    private func discoverCameraDevices() async throws {
        try Task.checkCancellation()
        
        // Fix: Use only macOS-compatible device types
        let deviceTypes: [AVCaptureDevice.DeviceType]
        #if os(macOS)
        deviceTypes = [
            .builtInWideAngleCamera,
            .external
        ]
        #else
        deviceTypes = [
            .builtInWideAngleCamera,
            .builtInTelephotoCamera,
            .builtInUltraWideCamera,
            .builtInDualCamera,
            .builtInTrueDepthCamera,
            .external
        ]
        #endif
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        
        var discoveredDevices: [String: CameraDeviceInfo] = [:]
        
        for device in discoverySession.devices {
            let deviceInfo = CameraDeviceInfo(from: device)
            discoveredDevices[device.uniqueID] = deviceInfo
            
            // Check if this is a new device
            if cameraDevices[device.uniqueID] == nil {
                // Notify about new device
                let notification = DeviceChangeNotification(
                    changeType: .added(deviceInfo),
                    timestamp: Date()
                )
                changeNotifications?.yield(notification)
            }
        }
        
        // Check for removed devices
        for (deviceID, _) in cameraDevices {
            if discoveredDevices[deviceID] == nil {
                let notification = DeviceChangeNotification(
                    changeType: .removed(deviceID),
                    timestamp: Date()
                )
                changeNotifications?.yield(notification)
            }
        }
        
        cameraDevices = discoveredDevices
    }
    
    private func discoverAudioDevices() async throws {
        try Task.checkCancellation()
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        
        var discoveredDevices: [String: AudioDeviceInfo] = [:]
        
        for device in discoverySession.devices {
            let deviceInfo = AudioDeviceInfo(from: device)
            discoveredDevices[device.uniqueID] = deviceInfo
        }
        
        audioDevices = discoveredDevices
    }
    
    private func handleDeviceConnected(_ notification: Notification) async {
        guard let device = notification.object as? AVCaptureDevice else { return }
        
        if device.hasMediaType(.video) {
            let deviceInfo = CameraDeviceInfo(from: device)
            let previousInfo = cameraDevices[device.uniqueID]
            cameraDevices[device.uniqueID] = deviceInfo
            
            let changeType: DeviceChangeNotification.ChangeType = previousInfo == nil ? 
                .added(deviceInfo) : 
                .configurationChanged(deviceInfo)
            
            let notification = DeviceChangeNotification(
                changeType: changeType,
                timestamp: Date()
            )
            changeNotifications?.yield(notification)
        } else if device.hasMediaType(.audio) {
            let deviceInfo = AudioDeviceInfo(from: device)
            audioDevices[device.uniqueID] = deviceInfo
        }
    }
    
    private func handleDeviceDisconnected(_ notification: Notification) async {
        guard let device = notification.object as? AVCaptureDevice else { return }
        
        if device.hasMediaType(.video) {
            cameraDevices.removeValue(forKey: device.uniqueID)
            
            let notification = DeviceChangeNotification(
                changeType: .removed(device.uniqueID),
                timestamp: Date()
            )
            changeNotifications?.yield(notification)
        } else if device.hasMediaType(.audio) {
            audioDevices.removeValue(forKey: device.uniqueID)
        }
    }
}

// MARK: - Supporting Types

/// Configuration for camera capture sessions
struct CameraCaptureConfiguration: Sendable {
    let sessionPreset: AVCaptureSession.Preset
    let videoFormat: VideoFormatInfo?
    let frameRate: Double?
    let orientation: AVCaptureVideoOrientation
    
    static let `default` = CameraCaptureConfiguration(
        sessionPreset: .high,
        videoFormat: nil,
        frameRate: 30.0,
        orientation: .portrait
    )
}

/// Device manager errors
enum DeviceManagerError: Error, LocalizedError, Sendable {
    case deviceNotFound(String)
    case permissionDenied(String)
    case configurationFailed(String)
    case discoveryFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let deviceID):
            return "Device not found: \(deviceID)"
        case .permissionDenied(let type):
            return "Permission denied for \(type)"
        case .configurationFailed(let reason):
            return "Device configuration failed: \(reason)"
        case .discoveryFailed(let reason):
            return "Device discovery failed: \(reason)"
        }
    }
}

// MARK: - Sendable Conformance

extension AVCaptureSession.Preset: @unchecked Sendable {}
extension AVCaptureVideoOrientation: @unchecked Sendable {}
extension AVAuthorizationStatus: @unchecked Sendable {}