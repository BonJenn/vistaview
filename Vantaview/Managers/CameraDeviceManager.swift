//
//  CameraDeviceManager.swift
//  Vantaview
//
//  Created by AI Assistant
//

import Foundation
import AVFoundation
import SwiftUI

/// Represents a physical camera device that can be selected and used
struct CameraDevice: Identifiable, Hashable {
    let id = UUID()
    let deviceID: String
    let name: String
    let deviceType: CameraDeviceType
    let isAvailable: Bool
    let captureDevice: AVCaptureDevice?
    
    var displayName: String {
        switch deviceType {
        case .builtin:
            return "Built-in Camera"
        case .external:
            return name
        case .continuity:
            return "iPhone via Continuity"
        case .unknown:
            return name
        }
    }
    
    var icon: String {
        switch deviceType {
        case .builtin:
            return "camera.fill"
        case .external:
            return "camera.on.rectangle"
        case .continuity:
            return "iphone.badge.play"
        case .unknown:
            return "camera"
        }
    }
    
    var statusColor: Color {
        isAvailable ? .green : .orange
    }
    
    var statusText: String {
        isAvailable ? "Available" : "In Use"
    }
}

enum CameraDeviceType: String, CaseIterable {
    case builtin = "Built-in"
    case external = "External"
    case continuity = "Continuity"
    case unknown = "Unknown"
}

/// Manages discovery and connection of physical camera devices
@MainActor
final class CameraDeviceManager: ObservableObject {
    @Published var availableDevices: [CameraDevice] = []
    @Published var isDiscovering = false
    @Published var lastDiscoveryError: String?
    
    private var deviceObservers: [NSObjectProtocol] = []
    
    init() {
        setupDeviceObservers()
        Task {
            await discoverDevices()
        }
    }
    
    deinit {
        deviceObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    /// Discover all available camera devices
    func discoverDevices() async {
        print("🔍 CameraDeviceManager: Starting device discovery...")
        isDiscovering = true
        lastDiscoveryError = nil
        
        do {
            // Request camera permissions if not already granted
            let hasPermission = await CameraPermissionHelper.checkAndRequestCameraPermission()
            print("📋 Camera permission status: \(hasPermission)")
            
            guard hasPermission else {
                lastDiscoveryError = "Camera access denied. Please enable camera access in System Preferences > Privacy & Security > Camera"
                isDiscovering = false
                return
            }
            
            var devices: [CameraDevice] = []
            
            // First, try comprehensive device discovery with multiple methods
            print("🔍 Method 1: Using discovery session...")
            
            // Get all video devices using discovery session (macOS compatible device types only)
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [
                    .builtInWideAngleCamera,
                    .external,
                    .continuityCamera
                ],
                mediaType: .video,
                position: .unspecified
            )
            
            print("📱 Discovery session found \(discoverySession.devices.count) devices")
            for device in discoverySession.devices {
                print("  - \(device.localizedName) (\(device.deviceType.rawValue)) - \(device.uniqueID)")
            }
            
            // Method 2: Try the older AVCaptureDevice.devices method as fallback
            print("🔍 Method 2: Using AVCaptureDevice.devices...")
            let allDevices = AVCaptureDevice.devices()
            let videoDevices = allDevices.filter { $0.hasMediaType(.video) }
            print("📱 AVCaptureDevice.devices found \(videoDevices.count) video devices")
            for device in videoDevices {
                print("  - \(device.localizedName) (\(device.deviceType.rawValue)) - \(device.uniqueID)")
            }
            
            // Method 3: Try default devices
            print("🔍 Method 3: Checking default devices...")
            if let defaultDevice = AVCaptureDevice.default(for: .video) {
                print("  - Default device: \(defaultDevice.localizedName)")
            } else {
                print("  - No default device found")
            }
            
            // Combine all found devices (remove duplicates by uniqueID)
            var allFoundDevices: [AVCaptureDevice] = []
            var deviceIDs: Set<String> = []
            
            // Add from discovery session
            for device in discoverySession.devices {
                if !deviceIDs.contains(device.uniqueID) {
                    allFoundDevices.append(device)
                    deviceIDs.insert(device.uniqueID)
                }
            }
            
            // Add from devices() method
            for device in videoDevices {
                if !deviceIDs.contains(device.uniqueID) {
                    allFoundDevices.append(device)
                    deviceIDs.insert(device.uniqueID)
                }
            }
            
            // Add default device if not already included
            if let defaultDevice = AVCaptureDevice.default(for: .video),
               !deviceIDs.contains(defaultDevice.uniqueID) {
                allFoundDevices.append(defaultDevice)
                deviceIDs.insert(defaultDevice.uniqueID)
            }
            
            print("📱 Total unique devices found: \(allFoundDevices.count)")
            
            // Convert to CameraDevice objects
            for device in allFoundDevices {
                let deviceType = determineDeviceType(device)
                let isAvailable = !device.isInUseByAnotherApplication
                
                let cameraDevice = CameraDevice(
                    deviceID: device.uniqueID,
                    name: device.localizedName,
                    deviceType: deviceType,
                    isAvailable: isAvailable,
                    captureDevice: device
                )
                
                devices.append(cameraDevice)
                print("  ✅ \(cameraDevice.displayName) - \(cameraDevice.statusText) - Type: \(deviceType.rawValue)")
            }
            
            // If no devices found, show debug info
            if devices.isEmpty {
                print("❌ No camera devices detected!")
                print("📋 System info:")
                print("  - macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
                print("  - App permissions: Camera=\(hasPermission)")
                
                lastDiscoveryError = "No camera devices detected. Check camera connections and permissions."
            }
            
            // Sort devices by preference (built-in first, then external, then continuity)
            devices.sort { lhs, rhs in
                let order: [CameraDeviceType] = [.builtin, .external, .continuity, .unknown]
                let lhsIndex = order.firstIndex(of: lhs.deviceType) ?? order.count
                let rhsIndex = order.firstIndex(of: rhs.deviceType) ?? order.count
                return lhsIndex < rhsIndex
            }
            
            availableDevices = devices
            print("✅ Device discovery complete - found \(devices.count) cameras")
            
        } catch {
            lastDiscoveryError = "Device discovery failed: \(error.localizedDescription)"
            print("❌ Device discovery error: \(error)")
            availableDevices = []
        }
        
        isDiscovering = false
    }
    
    /// Get a specific device by ID
    func device(withID deviceID: String) -> CameraDevice? {
        return availableDevices.first { $0.deviceID == deviceID }
    }
    
    /// Check if a device is currently available for use
    func isDeviceAvailable(_ deviceID: String) -> Bool {
        return device(withID: deviceID)?.isAvailable ?? false
    }
    
    /// Get the AVCaptureDevice for a given device ID
    func captureDevice(for deviceID: String) -> AVCaptureDevice? {
        return device(withID: deviceID)?.captureDevice
    }
    
    /// Manual refresh for debugging
    func forceRefresh() async {
        print("🔄 Force refreshing camera devices...")
        await discoverDevices()
    }
    
    // MARK: - Private Methods
    
    private func determineDeviceType(_ device: AVCaptureDevice) -> CameraDeviceType {
        print("🔍 Determining type for device: \(device.localizedName) - \(device.deviceType.rawValue)")
        
        switch device.deviceType {
        case .builtInWideAngleCamera:
            return .builtin
        case .external:
            return .external
        case .continuityCamera:
            return .continuity
        default:
            print("⚠️ Unknown device type: \(device.deviceType.rawValue)")
            return .unknown
        }
    }
    
    private func setupDeviceObservers() {
        // Observe device connection/disconnection
        let connectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.discoverDevices()
            }
        }
        
        let disconnectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.discoverDevices()
            }
        }
        
        deviceObservers = [connectObserver, disconnectObserver]
    }
}

/// Extension to make it easier to work with mock data during development
extension CameraDeviceManager {
    static let mockDevices: [CameraDevice] = [
        CameraDevice(
            deviceID: "builtin-camera",
            name: "FaceTime HD Camera",
            deviceType: .builtin,
            isAvailable: true,
            captureDevice: nil
        ),
        CameraDevice(
            deviceID: "iphone-continuity",
            name: "iPhone 15 Pro",
            deviceType: .continuity,
            isAvailable: true,
            captureDevice: nil
        ),
        CameraDevice(
            deviceID: "external-webcam",
            name: "Logitech BRIO",
            deviceType: .external,
            isAvailable: false,
            captureDevice: nil
        )
    ]
}

/// Extension for debugging camera issues
extension CameraDeviceManager {
    /// Comprehensive debug function to troubleshoot camera detection
    func debugCameraDetection() {
        Task { @MainActor in
            print("\n🔍 =================================")
            print("🔍 CAMERA DEBUG SESSION STARTED")
            print("🔍 =================================")
            
            // Check permissions first
            print("\n📋 1. Checking Permissions...")
            let permission = AVCaptureDevice.authorizationStatus(for: .video)
            print("   Current permission status: \(permission.rawValue)")
            switch permission {
            case .authorized:
                print("   ✅ Camera access is AUTHORIZED")
            case .denied:
                print("   ❌ Camera access is DENIED")
            case .notDetermined:
                print("   ⚠️ Camera access is NOT DETERMINED")
            case .restricted:
                print("   🚫 Camera access is RESTRICTED")
            @unknown default:
                print("   ❓ Unknown permission status")
            }
            
            // Request permission if needed
            if permission != .authorized {
                print("\n📋 2. Requesting Camera Permission...")
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                print("   Permission granted: \(granted)")
                if !granted {
                    print("   ❌ Camera permission denied - this is likely the issue!")
                    return
                }
            }
            
            // Try discovery session
            print("\n📱 3. Testing Discovery Session...")
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                mediaType: .video,
                position: .unspecified
            )
            print("   Found \(discoverySession.devices.count) devices via discovery session")
            
            for (index, device) in discoverySession.devices.enumerated() {
                print("   Device \(index + 1):")
                print("     Name: \(device.localizedName)")
                print("     Type: \(device.deviceType.rawValue)")
                print("     ID: \(device.uniqueID)")
                print("     In use: \(device.isInUseByAnotherApplication)")
                print("     Connected: \(device.isConnected)")
                print("     Has video: \(device.hasMediaType(.video))")
            }
            
            // Try legacy method
            print("\n📱 4. Testing Legacy Device Query...")
            let legacyDevices = AVCaptureDevice.devices()
            let videoDevices = legacyDevices.filter { $0.hasMediaType(.video) }
            print("   Found \(videoDevices.count) video devices via legacy method")
            
            for (index, device) in videoDevices.enumerated() {
                print("   Legacy Device \(index + 1):")
                print("     Name: \(device.localizedName)")
                print("     Type: \(device.deviceType.rawValue)")
                print("     ID: \(device.uniqueID)")
            }
            
            // Try default device
            print("\n📱 5. Testing Default Device...")
            if let defaultDevice = AVCaptureDevice.default(for: .video) {
                print("   ✅ Default device found:")
                print("     Name: \(defaultDevice.localizedName)")
                print("     Type: \(defaultDevice.deviceType.rawValue)")
                print("     ID: \(defaultDevice.uniqueID)")
                print("     In use: \(defaultDevice.isInUseByAnotherApplication)")
            } else {
                print("   ❌ No default device found")
            }
            
            // Try other common device queries
            print("\n📱 6. Testing Specific Device Queries...")
            
            // Built-in wide angle
            if let builtIn = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) {
                print("   ✅ Built-in wide angle camera found: \(builtIn.localizedName)")
            } else {
                print("   ❌ No built-in wide angle camera")
            }
            
            // External cameras
            if let external = AVCaptureDevice.default(.external, for: .video, position: .unspecified) {
                print("   ✅ External camera found: \(external.localizedName)")
            } else {
                print("   ❌ No external camera")
            }
            
            // Continuity camera
            if let continuity = AVCaptureDevice.default(.continuityCamera, for: .video, position: .unspecified) {
                print("   ✅ Continuity camera found: \(continuity.localizedName)")
            } else {
                print("   ❌ No continuity camera")
            }
            
            print("\n🔍 =================================")
            print("🔍 CAMERA DEBUG SESSION COMPLETED")
            print("🔍 =================================\n")
            
            // Trigger normal discovery after debug
            await discoverDevices()
        }
    }
}