//
//  CameraDeviceManager.swift
//  Vantaview
//
//  Manager for camera device discovery and configuration
//

import Foundation
import AVFoundation
import Combine
import SwiftUI

// Rename to avoid collision with new actors
struct LegacyCameraDevice: Identifiable, Hashable {
    let id: String
    let deviceID: String
    let displayName: String
    let localizedName: String
    let modelID: String
    let manufacturer: String
    let isConnected: Bool
    
    // For backwards compatibility, convert to new type when needed
    var asCameraDeviceInfo: CameraDeviceInfo {
        // This would require an actual AVCaptureDevice to create proper CameraDeviceInfo
        // For now, return a basic info structure
        return CameraDeviceInfo(
            id: id,
            deviceID: deviceID,
            displayName: displayName,
            localizedName: localizedName,
            modelID: modelID,
            manufacturer: manufacturer,
            isConnected: isConnected,
            supportedFormats: []
        )
    }
}

// Add convenience initializer to avoid compilation errors
extension CameraDeviceInfo {
    init(id: String, deviceID: String, displayName: String, localizedName: String, modelID: String, manufacturer: String, isConnected: Bool, supportedFormats: [VideoFormatInfo]) {
        self.id = id
        self.deviceID = deviceID
        self.displayName = displayName
        self.localizedName = localizedName
        self.modelID = modelID
        self.manufacturer = manufacturer
        self.isConnected = isConnected
        self.supportedFormats = supportedFormats
    }
}

@MainActor
final class CameraDeviceManager: ObservableObject {
    @Published var isDiscovering = false
    @Published var lastDiscoveryError: String?
    @Published var availableDevices: [LegacyCameraDevice] = []
    
    // Use DeviceManager actor for actual device management
    private let deviceManager: DeviceManager
    
    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
        
        Task {
            await refreshDevices()
        }
    }
    
    func discoverDevices() async {
        await refreshDevices()
    }
    
    func forceRefresh() async {
        await refreshDevices(forceRefresh: true)
    }
    
    private func refreshDevices(forceRefresh: Bool = false) async {
        isDiscovering = true
        lastDiscoveryError = nil
        
        do {
            let (cameras, _) = try await deviceManager.discoverDevices(forceRefresh: forceRefresh)
            
            // Convert to legacy format
            let legacyDevices = cameras.map { camera in
                LegacyCameraDevice(
                    id: camera.id,
                    deviceID: camera.deviceID,
                    displayName: camera.displayName,
                    localizedName: camera.localizedName,
                    modelID: camera.modelID,
                    manufacturer: camera.manufacturer,
                    isConnected: camera.isConnected
                )
            }
            
            availableDevices = legacyDevices
            
        } catch {
            lastDiscoveryError = error.localizedDescription
        }
        
        isDiscovering = false
    }
    
    func device(withID deviceID: String) -> LegacyCameraDevice? {
        return availableDevices.first { $0.deviceID == deviceID }
    }
    
    func debugCameraDetection() async {
        let stats = await deviceManager.getDiscoveryStats()
        print("Camera Detection Debug:")
        print("- Total cameras: \(stats.totalCameraDevices)")
        print("- Connected cameras: \(stats.connectedCameraDevices)")
        print("- Last discovery: \(stats.lastDiscoveryTime?.description ?? "Never")")
        print("- Discovery duration: \(stats.discoveryDuration)s")
    }
    
    // MARK: - Mock data for development
    
    static let mockDevices: [LegacyCameraDevice] = [
        LegacyCameraDevice(
            id: "mock-builtin-camera-1",
            deviceID: "builtin-camera-wide",
            displayName: "Built-in Wide Camera",
            localizedName: "Built-in Wide Camera",
            modelID: "com.apple.camera.builtin",
            manufacturer: "Apple Inc.",
            isConnected: true
        ),
        LegacyCameraDevice(
            id: "mock-external-camera-1",
            deviceID: "external-usb-camera",
            displayName: "USB Camera",
            localizedName: "External USB Camera",
            modelID: "com.generic.usb.camera",
            manufacturer: "Generic",
            isConnected: true
        )
    ]
}