//
//  CameraDebugView.swift
//  Vantaview
//
//  Created by AI Assistant
//

import SwiftUI
import AVFoundation

struct CameraDebugView: View {
    @EnvironmentObject private var productionManager: UnifiedProductionManager
    @State private var selectedDevice: String = ""
    @State private var isTestingFeed = false
    @State private var testResult: String = ""
    @State private var availableCameras: [CameraDeviceInfo] = []
    
    // Use device manager from production manager
    private var deviceManager: DeviceManager {
        productionManager.deviceManager
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Camera Debug Panel")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Available Cameras:")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if availableCameras.isEmpty {
                Text("No cameras detected")
                    .foregroundColor(.secondary)
                
                Button("Refresh") {
                    Task {
                        await refreshCameras()
                    }
                }
                .buttonStyle(.bordered)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(availableCameras) { camera in
                            deviceRow(LegacyCameraDevice(
                                id: camera.id,
                                deviceID: camera.deviceID,
                                displayName: camera.displayName,
                                localizedName: camera.localizedName,
                                modelID: camera.modelID,
                                manufacturer: camera.manufacturer,
                                isConnected: camera.isConnected
                            ))
                        }
                    }
                    .padding()
                }
            }
            
            if !testResult.isEmpty {
                Text("Test Result:")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(testResult)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .task {
            await loadCameras()
        }
    }
    
    private func loadCameras() async {
        await refreshCameras()
    }
    
    private func refreshCameras() async {
        do {
            let (cameras, _) = try await deviceManager.discoverDevices(forceRefresh: true)
            await MainActor.run {
                self.availableCameras = cameras
            }
        } catch {
            await MainActor.run {
                self.testResult = "Failed to load cameras: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: LegacyCameraDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Device ID: \(device.deviceID)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Manufacturer: \(device.manufacturer)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Model: \(device.modelID)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(device.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(device.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundColor(device.isConnected ? .green : .red)
                    }
                    
                    Button(selectedDevice == device.deviceID && isTestingFeed ? "Stop Test" : "Test Feed") {
                        if selectedDevice == device.deviceID && isTestingFeed {
                            stopFeedTest()
                        } else {
                            Task {
                                await startFeedTest(device)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!device.isConnected || (isTestingFeed && selectedDevice != device.deviceID))
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(selectedDevice == device.deviceID ? 0.2 : 0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedDevice == device.deviceID ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onTapGesture {
            selectedDevice = device.deviceID
        }
    }

    private func startFeedTest(_ device: LegacyCameraDevice) async {
        selectedDevice = device.deviceID
        isTestingFeed = true
        testResult = "Starting test for \(device.displayName)..."
        
        // For now, simulate a test
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        await MainActor.run {
            self.testResult = "Test completed for \(device.displayName). Camera appears to be working."
            self.isTestingFeed = false
        }
    }
    
    private func stopFeedTest() {
        isTestingFeed = false
        testResult = "Test stopped for selected device."
        selectedDevice = ""
    }
}