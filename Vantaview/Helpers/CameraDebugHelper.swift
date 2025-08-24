//
//  CameraDebugHelper.swift
//  Vantaview
//
//  Created by AI Assistant
//

import Foundation
import AVFoundation
import SwiftUI

/// Helper class for debugging camera issues
@MainActor
class CameraDebugHelper {
    
    static func testCameraAccess() {
        print("🧪 Testing camera access...")
        
        // Check camera permission
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("📹 Camera authorization status: \(cameraAuthStatus.rawValue)")
        
        switch cameraAuthStatus {
        case .authorized:
            print("✅ Camera access authorized")
            listAvailableCameras()
        case .denied:
            print("❌ Camera access denied")
        case .restricted:
            print("⚠️ Camera access restricted")
        case .notDetermined:
            print("❓ Camera access not determined - requesting permission...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        print("✅ Camera permission granted!")
                        listAvailableCameras()
                    } else {
                        print("❌ Camera permission denied")
                    }
                }
            }
        @unknown default:
            print("❓ Unknown camera authorization status")
        }
    }
    
    static func listAvailableCameras() {
        print("🔍 Listing available cameras...")
        
        // Get all video devices - using macOS compatible device types
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .external,
                .continuityCamera
            ],
            mediaType: .video,
            position: .unspecified
        )
        
        let devices = discoverySession.devices
        print("📱 Found \(devices.count) camera devices:")
        
        for (index, device) in devices.enumerated() {
            print("   \(index + 1). \(device.localizedName)")
            print("      - Unique ID: \(device.uniqueID)")
            print("      - Model ID: \(device.modelID)")
            print("      - Device Type: \(device.deviceType.rawValue)")
            print("      - Connected: \(device.isConnected)")
            print("      - In use: \(device.isInUseByAnotherApplication)")
            print("      - Active format: \(device.activeFormat)")
            
            // Test if we can create input
            do {
                let input = try AVCaptureDeviceInput(device: device)
                print("      - ✅ Can create input")
            } catch {
                print("      - ❌ Cannot create input: \(error)")
            }
        }
        
        // Also try the legacy method
        print("\n🔍 Legacy device enumeration:")
        let allDevices = AVCaptureDevice.devices()
        let videoDevices = allDevices.filter { $0.hasMediaType(.video) }
        print("📱 Found \(videoDevices.count) video devices via legacy method:")
        
        for (index, device) in videoDevices.enumerated() {
            print("   \(index + 1). \(device.localizedName) (\(device.deviceType.rawValue))")
        }
    }
    
    static func testSimpleCameraCapture() async {
        print("🎬 Testing simple camera capture...")
        
        guard let device = AVCaptureDevice.default(for: .video) else {
            print("❌ No default camera device found")
            return
        }
        
        print("📹 Using camera: \(device.localizedName)")
        
        do {
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            // Add input
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                print("✅ Added camera input")
            } else {
                print("❌ Cannot add camera input")
                return
            }
            
            // Add output
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                print("✅ Added video output")
            } else {
                print("❌ Cannot add video output")
                return
            }
            
            session.commitConfiguration()
            
            print("🎬 Starting capture session...")
            session.startRunning()
            
            // Wait and check
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            if session.isRunning {
                print("✅ Capture session is running successfully!")
            } else {
                print("❌ Capture session failed to start")
            }
            
            session.stopRunning()
            print("🛑 Test session stopped")
            
        } catch {
            print("❌ Camera capture test failed: \(error)")
        }
    }
}