//
//  CameraConnectionDebugView.swift
//  Vistaview
//
//  Created by AI Assistant
//

import SwiftUI
import AVFoundation

struct CameraConnectionDebugView: View {
    @StateObject private var debugManager = CameraConnectionDebugManager()
    @State private var selectedDevice: CameraDevice?
    @State private var testFeed: CameraFeed?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Camera Connection Debug")
                .font(.title)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Permission Status
                    debugSection("Permission Status") {
                        HStack {
                            statusIndicator(debugManager.hasPermission)
                            Text(debugManager.permissionStatus)
                            Spacer()
                            Button("Request Permission") {
                                Task { await debugManager.checkPermissions() }
                            }
                            .disabled(debugManager.hasPermission)
                        }
                    }
                    
                    // Available Devices
                    debugSection("Available Devices (\(debugManager.availableDevices.count))") {
                        if debugManager.availableDevices.isEmpty {
                            Text("No devices found")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(debugManager.availableDevices) { device in
                                deviceRow(device)
                            }
                        }
                        
                        Button("Refresh Devices") {
                            Task { await debugManager.discoverDevices() }
                        }
                    }
                    
                    // Test Camera Feed
                    if let device = selectedDevice {
                        debugSection("Test Camera Feed") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Testing: \(device.displayName)")
                                    .font(.headline)
                                
                                HStack {
                                    Button("Start Feed") {
                                        Task { await startTestFeed(device) }
                                    }
                                    .disabled(testFeed != nil)
                                    
                                    Button("Stop Feed") {
                                        stopTestFeed()
                                    }
                                    .disabled(testFeed == nil)
                                }
                                
                                if let feed = testFeed {
                                    feedStatusView(feed)
                                }
                            }
                        }
                    }
                    
                    // Debug Log
                    debugSection("Debug Log") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(debugManager.debugLog, id: \.self) { logEntry in
                                    Text(logEntry)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .frame(height: 200)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                        
                        Button("Clear Log") {
                            debugManager.clearLog()
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 700)
        .onAppear {
            Task {
                await debugManager.checkPermissions()
                await debugManager.discoverDevices()
            }
        }
    }
    
    private func debugSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            content()
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    private func statusIndicator(_ isGood: Bool) -> some View {
        Circle()
            .fill(isGood ? Color.green : Color.red)
            .frame(width: 12, height: 12)
    }
    
    private func deviceRow(_ device: CameraDevice) -> some View {
        HStack {
            statusIndicator(device.isAvailable)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.subheadline)
                
                Text("\(device.deviceType.rawValue) - \(device.isAvailable ? "Available" : "In Use")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Test") {
                selectedDevice = device
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
    
    private func feedStatusView(_ feed: CameraFeed) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusIndicator(feed.connectionStatus == .connected)
                Text("Status: \(feed.connectionStatus.displayText)")
            }
            
            Text("Frame Count: \(feed.frameCount)")
            Text("Has Preview Image: \(feed.previewImage != nil ? "Yes" : "No")")
            Text("Has Current Frame: \(feed.currentFrame != nil ? "Yes" : "No")")
            
            if let image = feed.previewImage {
                Text("Image Size: \(image.width) x \(image.height)")
                
                // Show a small preview
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 150)
                    .border(Color.green, width: 2)
            }
        }
    }
    
    private func startTestFeed(_ device: CameraDevice) async {
        debugManager.log("Starting test feed for \(device.displayName)")
        
        let feed = CameraFeed(device: device)
        testFeed = feed
        
        await feed.startCapture()
        
        debugManager.log("Test feed started - Status: \(feed.connectionStatus.displayText)")
    }
    
    private func stopTestFeed() {
        if let feed = testFeed {
            debugManager.log("Stopping test feed for \(feed.device.displayName)")
            feed.stopCapture()
            testFeed = nil
        }
    }
}

@MainActor
class CameraConnectionDebugManager: ObservableObject {
    @Published var hasPermission = false
    @Published var permissionStatus = "Checking..."
    @Published var availableDevices: [CameraDevice] = []
    @Published var debugLog: [String] = []
    
    private let deviceManager = CameraDeviceManager()
    
    func checkPermissions() async {
        log("Checking camera permissions...")
        hasPermission = await CameraPermissionHelper.checkAndRequestCameraPermission()
        
        let status = CameraPermissionHelper.getCurrentPermissionStatus()
        switch status {
        case .authorized:
            permissionStatus = "✅ Authorized"
        case .denied:
            permissionStatus = "❌ Denied"
        case .restricted:
            permissionStatus = "⚠️ Restricted"
        case .notDetermined:
            permissionStatus = "❓ Not Determined"
        @unknown default:
            permissionStatus = "❓ Unknown"
        }
        
        log("Permission status: \(permissionStatus)")
    }
    
    func discoverDevices() async {
        log("Discovering camera devices...")
        await deviceManager.discoverDevices()
        availableDevices = deviceManager.availableDevices
        
        log("Found \(availableDevices.count) camera devices:")
        for device in availableDevices {
            log("  - \(device.displayName) (\(device.deviceType.rawValue)) - \(device.isAvailable ? "Available" : "In Use")")
        }
    }
    
    func log(_ message: String) {
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] \(message)"
        debugLog.append(logEntry)
        print("🐛 \(logEntry)")
        
        // Keep only last 100 entries
        if debugLog.count > 100 {
            debugLog.removeFirst(debugLog.count - 100)
        }
    }
    
    func clearLog() {
        debugLog.removeAll()
    }
}

extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

#Preview {
    CameraConnectionDebugView()
}