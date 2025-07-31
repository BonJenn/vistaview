//
//  QuickCameraTestView.swift
//  Vistaview
//
//  Simple camera test to diagnose connection issues
//

import SwiftUI
import AVFoundation

struct QuickCameraTestView: View {
    @State private var testResults: [String] = []
    @State private var isRunning = false
    @State private var currentTest = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Quick Camera Diagnostic")
                .font(.title)
            
            Text(currentTest)
                .font(.headline)
                .foregroundColor(.blue)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(testResults, id: \.self) { result in
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(result.hasPrefix("✅") ? .green : 
                                           result.hasPrefix("❌") ? .red : 
                                           result.hasPrefix("⚠️") ? .orange : .primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 300)
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
            
            Button("Run Camera Diagnostic") {
                runDiagnostic()
            }
            .disabled(isRunning)
        }
        .padding()
        .frame(width: 500, height: 500)
    }
    
    private func runDiagnostic() {
        guard !isRunning else { return }
        
        isRunning = true
        testResults.removeAll()
        
        Task { @MainActor in
            await performDiagnostic()
            isRunning = false
            currentTest = "Diagnostic Complete"
        }
    }
    
    private func performDiagnostic() async {
        log("🧪 Starting camera diagnostic...")
        
        // Test 1: Check permissions
        currentTest = "Checking Permissions..."
        log("📋 Test 1: Checking camera permissions")
        
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        log("   Current status: \(currentStatus.rawValue)")
        
        if currentStatus != .authorized {
            log("   Requesting permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                log("✅ Permission granted")
            } else {
                log("❌ Permission denied - cannot proceed")
                return
            }
        } else {
            log("✅ Permission already granted")
        }
        
        // Test 2: Device discovery
        currentTest = "Discovering Devices..."
        log("📱 Test 2: Discovering camera devices")
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        let devices = discoverySession.devices
        log("   Found \(devices.count) devices via discovery session")
        
        for (index, device) in devices.enumerated() {
            log("   \(index + 1). \(device.localizedName)")
            log("      - Type: \(device.deviceType.rawValue)")
            log("      - In use: \(device.isInUseByAnotherApplication)")
        }
        
        if devices.isEmpty {
            log("❌ No devices found")
            return
        } else {
            log("✅ Found camera devices")
        }
        
        // Test 3: Try to create capture session
        currentTest = "Testing Camera Connection..."
        log("🎬 Test 3: Testing capture session with first device")
        
        guard let firstDevice = devices.first else {
            log("❌ No device to test")
            return
        }
        
        log("   Testing with: \(firstDevice.localizedName)")
        
        do {
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            // Add input
            let input = try AVCaptureDeviceInput(device: firstDevice)
            if session.canAddInput(input) {
                session.addInput(input)
                log("✅ Added camera input successfully")
            } else {
                log("❌ Cannot add camera input")
                return
            }
            
            // Add output
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                log("✅ Added video output successfully")
            } else {
                log("❌ Cannot add video output")
                return
            }
            
            session.commitConfiguration()
            log("✅ Session configuration committed")
            
            // Test 4: Start session
            currentTest = "Starting Camera Session..."
            log("▶️ Test 4: Starting capture session")
            
            session.startRunning()
            
            // Wait and check
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
            if session.isRunning {
                log("✅ Session is running successfully!")
                
                // Test 5: Check for frames with delegate
                currentTest = "Testing Frame Reception..."
                log("📸 Test 5: Testing frame reception")
                
                let frameReceiver = TestFrameReceiver()
                let queue = DispatchQueue(label: "test.frame.queue")
                output.setSampleBufferDelegate(frameReceiver, queue: queue)
                
                // Wait for frames
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                
                let frameCount = frameReceiver.frameCount
                if frameCount > 0 {
                    log("✅ Received \(frameCount) frames in 5 seconds")
                    log("✅ Camera is working correctly!")
                } else {
                    log("❌ No frames received - camera may be in use or blocked")
                }
            } else {
                log("❌ Session failed to start")
            }
            
            session.stopRunning()
            log("🛑 Test session stopped")
            
        } catch {
            log("❌ Camera test failed: \(error)")
        }
        
        // Test 6: Compare with CameraFeedManager
        currentTest = "Testing CameraFeedManager..."
        log("🔧 Test 6: Testing with CameraFeedManager")
        
        let deviceManager = CameraDeviceManager()
        await deviceManager.discoverDevices()
        let cameraDevices = deviceManager.availableDevices
        
        log("   CameraDeviceManager found \(cameraDevices.count) devices")
        for device in cameraDevices {
            log("   - \(device.displayName) (\(device.deviceType.rawValue)) - Available: \(device.isAvailable)")
        }
        
        if let firstCameraDevice = cameraDevices.first(where: { $0.isAvailable }) {
            log("   Testing CameraFeed with: \(firstCameraDevice.displayName)")
            
            let cameraFeed = CameraFeed(device: firstCameraDevice)
            await cameraFeed.startCapture()
            
            log("   CameraFeed status: \(cameraFeed.connectionStatus.displayText)")
            
            // Wait and check for frames
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
            log("   Frame count: \(cameraFeed.frameCount)")
            log("   Has preview image: \(cameraFeed.previewImage != nil)")
            
            if cameraFeed.frameCount > 0 {
                log("✅ CameraFeed is working!")
            } else {
                log("❌ CameraFeed not receiving frames")
            }
            
            cameraFeed.stopCapture()
        }
        
        log("🏁 Diagnostic complete")
    }
    
    private func log(_ message: String) {
        testResults.append(message)
        print("🧪 \(message)")
    }
}

class TestFrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private(set) var frameCount = 0
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        if frameCount <= 5 {
            print("🧪 Test frame received: \(frameCount)")
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("🧪 Test frame dropped")
    }
}

#Preview {
    QuickCameraTestView()
}