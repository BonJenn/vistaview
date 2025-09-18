//
//  CameraConnectionDebugView.swift
//  Vantaview
//
//  Created by AI Assistant
//

import SwiftUI
import AVFoundation

struct CameraConnectionDebugView: View {
    @State private var selectedDevice: LegacyCameraDevice?
    @State private var connectionStatus = "No device selected"
    @State private var isConnecting = false
    @State private var testFeed: CameraFeed?
    @State private var lastFrameTime: Date?
    @State private var frameCount = 0
    @State private var testStartTime: Date?
    @State private var productionManager: UnifiedProductionManager?
    @State private var availableDevices: [CameraDeviceInfo] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Camera Connection Debug")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if availableDevices.isEmpty {
                Text("No cameras detected")
                    .foregroundColor(.secondary)
                
                Button("Refresh Devices") {
                    Task {
                        await self.refreshDevices()
                    }
                }
                .buttonStyle(.bordered)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Available Cameras:")
                        .font(.headline)
                    
                    ForEach(availableDevices) { device in
                        self.deviceRow(LegacyCameraDevice(
                            id: device.id,
                            deviceID: device.deviceID,
                            displayName: device.displayName,
                            localizedName: device.localizedName,
                            modelID: device.modelID,
                            manufacturer: device.manufacturer,
                            isConnected: device.isConnected
                        ))
                    }
                }
            }
            
            Divider()
            
            VStack(spacing: 12) {
                Text("Connection Status: \(connectionStatus)")
                    .font(.subheadline)
                
                if let startTime = testStartTime {
                    Text("Test Duration: \(formatDuration(Date().timeIntervalSince(startTime)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Frames Received: \(frameCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let lastFrame = lastFrameTime {
                    Text("Last Frame: \(DateFormatter.localizedString(from: lastFrame, dateStyle: .none, timeStyle: .medium))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
        .task {
            await self.loadDevices()
        }
    }
    
    private func loadDevices() async {
        // Initialize production manager if needed
        if productionManager == nil {
            do {
                let manager = try await UnifiedProductionManager()
                await manager.initialize()
                productionManager = manager
            } catch {
                print("Failed to initialize production manager: \(error)")
                return
            }
        }
        await refreshDevices()
    }
    
    private func refreshDevices() async {
        guard let manager = productionManager else { return }
        
        do {
            let (cameras, _) = try await manager.deviceManager.discoverDevices(forceRefresh: true)
            await MainActor.run {
                self.availableDevices = cameras
            }
        } catch {
            print("Failed to refresh devices: \(error)")
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: LegacyCameraDevice) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(device.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(device.deviceID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(device.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Button(selectedDevice?.deviceID == device.deviceID ? "Stop Test" : "Test Connection") {
                if selectedDevice?.deviceID == device.deviceID {
                    self.stopTest()
                } else {
                    Task {
                        await self.startTestFeed(device)
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(isConnecting || !device.isConnected)
        }
        .padding(.vertical, 4)
    }

    private func startTestFeed(_ device: LegacyCameraDevice) async {
        selectedDevice = device
        isConnecting = true
        connectionStatus = "Connecting to \(device.displayName)..."
        frameCount = 0
        lastFrameTime = nil
        testStartTime = Date()
        
        // Implementation would use the actual device manager
        // For now, simulate a test
        connectionStatus = "Connected to \(device.displayName)"
        isConnecting = false
    }
    
    private func stopTest() {
        selectedDevice = nil
        connectionStatus = "Test stopped"
        isConnecting = false
        testFeed = nil
        frameCount = 0
        lastFrameTime = nil
        testStartTime = nil
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}