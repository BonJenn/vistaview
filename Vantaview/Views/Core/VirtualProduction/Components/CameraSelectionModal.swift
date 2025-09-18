//
//  CameraSelectionModal.swift
//  Vantaview
//
//  Created by AI Assistant
//

import SwiftUI
import AVFoundation
import SceneKit

struct CameraSelectionModal: View {
    @Binding var isPresented: Bool
    let onCameraSelected: (LegacyCameraDevice) -> Void
    
    @EnvironmentObject private var productionManager: UnifiedProductionManager
    @State private var selectedDevice: String = ""
    @State private var isTestingConnection = false
    @State private var testResult: String = ""
    @State private var isRefreshing = false
    
    // Use device manager from production manager
    private var deviceManager: DeviceManager {
        productionManager.deviceManager
    }
    
    @State private var availableCameras: [CameraDeviceInfo] = []
    
    // Layout constants matching VirtualProductionView
    private let spacing1: CGFloat = 4
    private let spacing2: CGFloat = 8
    private let spacing3: CGFloat = 16
    private let spacing4: CGFloat = 24
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if availableCameras.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "video.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No cameras detected")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Make sure your camera is connected and try refreshing")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Refresh") {
                            refreshDevices()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    List {
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
                    .listStyle(PlainListStyle())
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Select Camera")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        refreshDevices()
                    }
                    .disabled(isRefreshing)
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Refresh") {
                        refreshDevices()
                    }
                    .disabled(isRefreshing)
                }
                #endif
            }
        }
        .frame(width: 500, height: 400)
        .task {
            await loadCameras()
        }
    }
    
    private func loadCameras() async {
        do {
            let (cameras, _) = try await deviceManager.discoverDevices()
            await MainActor.run {
                self.availableCameras = cameras
            }
        } catch {
            print("Failed to load cameras: \(error)")
        }
    }
    
    private func refreshDevices() {
        isRefreshing = true
        Task {
            do {
                let (cameras, _) = try await deviceManager.discoverDevices(forceRefresh: true)
                await MainActor.run {
                    self.availableCameras = cameras
                    self.isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    self.isRefreshing = false
                }
                print("Failed to refresh devices: \(error)")
            }
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: LegacyCameraDevice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("ID: \(device.deviceID)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Manufacturer: \(device.manufacturer)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Circle()
                    .fill(device.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                
                Text(device.isConnected ? "Connected" : "Disconnected")
                    .font(.caption2)
                    .foregroundColor(device.isConnected ? .green : .red)
            }
            
            Button("Select") {
                onCameraSelected(device)
                isPresented = false
            }
            .buttonStyle(.bordered)
            .disabled(!device.isConnected)
        }
        .padding(.vertical, 8)
        .background(selectedDevice == device.deviceID ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onTapGesture {
            selectedDevice = device.deviceID
        }
    }
}