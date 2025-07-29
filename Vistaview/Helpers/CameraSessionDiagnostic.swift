//
//  CameraSessionDiagnostic.swift
//  Vistaview
//
//  Created by AI Assistant
//

import Foundation
import AVFoundation

@MainActor
class CameraSessionDiagnostic {
    
    static func runFullDiagnostic() async {
        print("🏥 === CAMERA SESSION DIAGNOSTIC ===")
        
        // Check permissions
        await checkPermissions()
        
        // Check available devices
        checkAvailableDevices()
        
        // Test basic session creation
        await testBasicSession()
        
        print("🏥 === DIAGNOSTIC COMPLETE ===")
    }
    
    static func checkPermissions() async {
        print("📋 Checking camera permissions...")
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            print("✅ Camera permission: AUTHORIZED")
        case .denied:
            print("❌ Camera permission: DENIED")
        case .restricted:
            print("⚠️ Camera permission: RESTRICTED")
        case .notDetermined:
            print("❓ Camera permission: NOT DETERMINED")
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            print("   Requested permission: \(granted ? "GRANTED" : "DENIED")")
        @unknown default:
            print("❓ Camera permission: UNKNOWN")
        }
    }
    
    static func checkAvailableDevices() {
        print("📱 Checking available camera devices...")
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        
        let devices = discoverySession.devices
        print("   Found \(devices.count) devices:")
        
        for (index, device) in devices.enumerated() {
            print("   \(index + 1). \(device.localizedName)")
            print("      - Unique ID: \(device.uniqueID)")
            print("      - Model ID: \(device.modelID)")
            print("      - Connected: \(device.isConnected)")
            
            #if os(iOS)
            print("      - In use by another client: \(device.isInUseByAnotherClient)")
            print("      - Suspended: \(device.isSuspended)")
            #endif
            
            // Test input creation
            do {
                let _ = try AVCaptureDeviceInput(device: device)
                print("      - ✅ Can create input")
            } catch {
                print("      - ❌ Cannot create input: \(error)")
            }
        }
    }
    
    static func testBasicSession() async {
        print("🧪 Testing basic capture session...")
        
        guard let device = AVCaptureDevice.default(for: .video) else {
            print("❌ No default camera device found")
            return
        }
        
        print("   Using device: \(device.localizedName)")
        
        do {
            let session = AVCaptureSession()
            print("   ✅ Created capture session")
            
            // Test input
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                print("   ✅ Added input to session")
            } else {
                print("   ❌ Cannot add input to session")
                return
            }
            
            // Test output
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                print("   ✅ Added output to session")
            } else {
                print("   ❌ Cannot add output to session")
                return
            }
            
            // Test session presets
            let presets: [AVCaptureSession.Preset] = [.high, .medium, .low, .cif352x288]
            for preset in presets {
                if session.canSetSessionPreset(preset) {
                    print("   ✅ Supports preset: \(preset.rawValue)")
                } else {
                    print("   ❌ Does not support preset: \(preset.rawValue)")
                }
            }
            
            // Start session
            print("   🎬 Starting session...")
            session.startRunning()
            
            // Wait and check
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            if session.isRunning {
                print("   ✅ Session is running successfully!")
                print("      - Inputs: \(session.inputs.count)")
                print("      - Outputs: \(session.outputs.count)")
                
                if let connection = output.connection(with: .video) {
                    print("      - Connection active: \(connection.isActive)")
                    print("      - Connection enabled: \(connection.isEnabled)")
                }
            } else {
                print("   ❌ Session failed to start")
            }
            
            session.stopRunning()
            print("   🛑 Test session stopped")
            
        } catch {
            print("   ❌ Session test failed: \(error)")
        }
    }
}