//
//  CameraDebugView.swift
//  Vistaview
//
//  Created by AI Assistant
//

import SwiftUI
import AVFoundation

struct CameraDebugView: View {
    @StateObject private var cameraDeviceManager = CameraDeviceManager()
    @StateObject private var cameraFeedManager: CameraFeedManager
    @State private var testResults: [String] = []
    @State private var isRunningTests = false
    
    init() {
        let deviceManager = CameraDeviceManager()
        self._cameraFeedManager = StateObject(wrappedValue: CameraFeedManager(cameraDeviceManager: deviceManager))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Camera Debug Console")
                .font(.title)
                .padding()
            
            // Test Controls
            HStack(spacing: 20) {
                Button("Test Camera Access") {
                    runCameraAccessTest()
                }
                .disabled(isRunningTests)
                
                Button("Discover Cameras") {
                    Task {
                        await discoverCameras()
                    }
                }
                .disabled(isRunningTests)
                
                Button("Test Feed Creation") {
                    Task {
                        await testFeedCreation()
                    }
                }
                .disabled(isRunningTests)
                
                Button("Clear Log") {
                    testResults.removeAll()
                }
            }
            .padding()
            
            // Available Devices
            if !cameraDeviceManager.availableDevices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Available Devices:")
                        .font(.headline)
                    
                    ForEach(cameraDeviceManager.availableDevices, id: \.id) { device in
                        deviceRow(device)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Active Feeds
            if !cameraFeedManager.activeFeeds.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Active Feeds:")
                        .font(.headline)
                    
                    ForEach(cameraFeedManager.activeFeeds) { feed in
                        feedRow(feed)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Test Results Log
            VStack(alignment: .leading, spacing: 5) {
                Text("Debug Log:")
                    .font(.headline)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(testResults.enumerated()), id: \.offset) { index, result in
                            Text(result)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(colorForLogMessage(result))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 300)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray, lineWidth: 1)
                )
            }
            .padding()
            
            Spacer()
        }
        .padding()
        .onAppear {
            addLog("🧪 Camera Debug View loaded")
            addLog("📝 Click 'Test Camera Access' to check permissions")
        }
    }
    
    private func deviceRow(_ device: CameraDevice) -> some View {
        HStack {
            Image(systemName: device.icon)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text(device.displayName)
                    .font(.callout)
                Text(device.deviceType.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(device.statusColor)
                .frame(width: 8, height: 8)
            
            Button("Start Feed") {
                Task {
                    await startFeedTest(device)
                }
            }
            .font(.caption)
            .disabled(!device.isAvailable)
        }
        .padding(.vertical, 4)
    }
    
    private func feedRow(_ feed: CameraFeed) -> some View {
        HStack {
            // Preview thumbnail
            Group {
                if let nsImage = feed.previewNSImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 40)
                        .clipped()
                        .cornerRadius(4)
                } else if let cgImage = feed.previewImage {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 40)
                        .clipped()
                        .cornerRadius(4)
                } else {
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 60, height: 40)
                        .overlay(
                            Text("No Preview")
                                .font(.caption2)
                                .foregroundColor(.white)
                        )
                        .cornerRadius(4)
                }
            }
            
            VStack(alignment: .leading) {
                Text(feed.device.displayName)
                    .font(.callout)
                
                HStack {
                    Circle()
                        .fill(feed.connectionStatus.color)
                        .frame(width: 6, height: 6)
                    Text(feed.connectionStatus.displayText)
                        .font(.caption)
                        .foregroundColor(feed.connectionStatus.color)
                }
            }
            
            Spacer()
            
            Button("Stop") {
                cameraFeedManager.stopFeed(feed)
                addLog("🛑 Stopped feed: \(feed.device.displayName)")
            }
            .font(.caption)
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
    
    private func runCameraAccessTest() {
        isRunningTests = true
        addLog("🧪 Testing camera access...")
        
        Task {
            await CameraDebugHelper.testSimpleCameraCapture()
            await MainActor.run {
                isRunningTests = false
                addLog("✅ Camera access test completed")
            }
        }
    }
    
    private func discoverCameras() async {
        isRunningTests = true
        addLog("🔍 Discovering cameras...")
        
        let devices = await cameraFeedManager.getAvailableDevices()
        
        addLog("📱 Found \(devices.count) camera devices:")
        for device in devices {
            addLog("  - \(device.displayName) (\(device.deviceType.rawValue)) - Available: \(device.isAvailable)")
        }
        
        isRunningTests = false
    }
    
    private func testFeedCreation() async {
        guard let firstDevice = cameraDeviceManager.availableDevices.first else {
            addLog("❌ No devices available for feed test")
            return
        }
        
        isRunningTests = true
        addLog("🎬 Testing feed creation with: \(firstDevice.displayName)")
        
        if let feed = await cameraFeedManager.startFeed(for: firstDevice) {
            addLog("✅ Feed created successfully!")
            addLog("   - Status: \(feed.connectionStatus.displayText)")
            
            // Wait a bit and check for frames
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            if feed.previewImage != nil || feed.previewNSImage != nil {
                addLog("📸 Feed is receiving frames!")
            } else {
                addLog("⚠️ Feed created but no frames received yet")
            }
        } else {
            addLog("❌ Failed to create feed")
        }
        
        isRunningTests = false
    }
    
    private func startFeedTest(_ device: CameraDevice) async {
        addLog("🎬 Starting feed for: \(device.displayName)")
        
        if let feed = await cameraFeedManager.startFeed(for: device) {
            addLog("✅ Feed started: \(feed.connectionStatus.displayText)")
        } else {
            addLog("❌ Failed to start feed for: \(device.displayName)")
        }
    }
    
    private func addLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        testResults.append("[\(timestamp)] \(message)")
        
        // Keep only last 100 entries
        if testResults.count > 100 {
            testResults.removeFirst()
        }
    }
    
    private func colorForLogMessage(_ message: String) -> Color {
        if message.contains("❌") || message.contains("Failed") || message.contains("Error") {
            return .red
        } else if message.contains("⚠️") || message.contains("Warning") {
            return .orange
        } else if message.contains("✅") || message.contains("Success") {
            return .green
        } else if message.contains("🧪") || message.contains("Test") {
            return .blue
        } else {
            return .primary
        }
    }
}

#Preview {
    CameraDebugView()
        .frame(width: 800, height: 600)
}