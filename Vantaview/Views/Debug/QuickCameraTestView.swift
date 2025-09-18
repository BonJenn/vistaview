//
//  QuickCameraTestView.swift
//  Vantaview
//
//  Simple camera test to diagnose connection issues
//

import SwiftUI
import AVFoundation

struct QuickCameraTestView: View {
    @State private var isRunning = false
    @State private var testResult = "Press 'Run Quick Test' to start"
    @State private var productionManager: UnifiedProductionManager?
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Quick Camera Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("This test will:")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("1.")
                        .fontWeight(.bold)
                    Text("Detect available cameras")
                }
                HStack {
                    Text("2.")
                        .fontWeight(.bold)
                    Text("Connect to the first camera found")
                }
                HStack {
                    Text("3.")
                        .fontWeight(.bold)
                    Text("Check if frames are being received")
                }
                HStack {
                    Text("4.")
                        .fontWeight(.bold)
                    Text("Report success or failure")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            VStack(spacing: 16) {
                Text("Test Result:")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ScrollView {
                    Text(testResult)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .frame(maxHeight: 200)
                
                Button(action: {
                    Task {
                        await runQuickTest()
                    }
                }) {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isRunning ? "Running Test..." : "Run Quick Test")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isRunning ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isRunning)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: 600)
        .task {
            // Initialize production manager
            do {
                let manager = try await UnifiedProductionManager()
                await manager.initialize()
                productionManager = manager
            } catch {
                testResult = "Failed to initialize production manager: \(error)"
            }
        }
    }
    
    private func runQuickTest() async {
        isRunning = true
        await quickCameraTest()
        isRunning = false
    }
    
    private func quickCameraTest() async {
        print("🧪 QuickCameraTestView: Starting quick camera test")
        testResult = "Starting quick camera test..."
        
        do {
            // Check if production manager is available
            guard let productionManager = productionManager else {
                testResult = "Production manager not available"
                return
            }
            
            let deviceManager = productionManager.deviceManager
            
            print("🧪 QuickCameraTestView: Getting available cameras")
            let (cameras, _) = try await deviceManager.discoverDevices()
            
            guard let firstCamera = cameras.first else {
                testResult = "No cameras found during discovery"
                print("🧪 QuickCameraTestView: No cameras found")
                return
            }
            
            print("🧪 QuickCameraTestView: Found camera: \(firstCamera.displayName)")
            testResult = "Found camera: \(firstCamera.displayName). Creating feed..."
            
            let cameraFeed = CameraFeed(deviceInfo: firstCamera)
            
            print("🧪 QuickCameraTestView: Starting capture for: \(firstCamera.displayName)")
            testResult = "Starting capture for: \(firstCamera.displayName)..."
            
            await cameraFeed.startCapture(using: deviceManager)
            
            print("🧪 QuickCameraTestView: Capture started, checking for frames...")
            testResult = "Capture started. Checking for frames..."
            
            // Wait for frames to start coming in
            let maxWaitTime = 5.0 // seconds
            let checkInterval = 0.1 // seconds
            var waitTime = 0.0
            
            while waitTime < maxWaitTime {
                if cameraFeed.frameCount > 0 {
                    testResult = "✅ SUCCESS! Camera is working. Received \(cameraFeed.frameCount) frames from \(firstCamera.displayName)"
                    print("🧪 QuickCameraTestView: SUCCESS - received \(cameraFeed.frameCount) frames")
                    
                    // Stop the feed
                    await cameraFeed.stopCapture()
                    return
                }
                
                try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
                waitTime += checkInterval
            }
            
            // Timeout
            testResult = "❌ TIMEOUT: No frames received from \(firstCamera.displayName) after \(maxWaitTime) seconds. Status: \(cameraFeed.connectionStatus.displayText)"
            print("🧪 QuickCameraTestView: TIMEOUT - no frames received")
            
            await cameraFeed.stopCapture()
            
        } catch {
            testResult = "❌ ERROR: \(error.localizedDescription)"
            print("🧪 QuickCameraTestView: ERROR - \(error)")
        }
    }
}