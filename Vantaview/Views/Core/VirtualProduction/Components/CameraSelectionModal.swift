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
    @ObservedObject var cameraManager: CameraDeviceManager
    @ObservedObject var virtualCamera: VirtualCamera
    @Binding var isPresented: Bool
    
    let onCameraSelected: (CameraDevice) -> Void
    
    // Layout constants matching VirtualProductionView
    private let spacing1: CGFloat = 4
    private let spacing2: CGFloat = 8
    private let spacing3: CGFloat = 16
    private let spacing4: CGFloat = 24
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            modalHeader
            
            Divider()
            
            // Content
            VStack(spacing: spacing4) {
                // Camera info
                virtualCameraInfo
                
                // Device list
                deviceList
                
                // Actions
                actionButtons
            }
            .padding(.all, spacing4)
        }
        .frame(width: 480, height: 600)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            Task {
                await cameraManager.discoverDevices()
            }
        }
    }
    
    // MARK: - Header
    
    private var modalHeader: some View {
        HStack(spacing: spacing3) {
            Image(systemName: "video.circle.fill")
                .font(.system(.title2, design: .default, weight: .semibold))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Select Camera Source")
                    .font(.system(.title2, design: .default, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Choose which physical camera to use for \(virtualCamera.name)")
                    .font(.system(.caption, design: .default, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(.plain)
            .font(.system(.body, design: .default, weight: .medium))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, spacing4)
        .padding(.vertical, spacing3)
        .background(.black.opacity(0.05))
    }
    
    // MARK: - Virtual Camera Info
    
    private var virtualCameraInfo: some View {
        HStack(spacing: spacing3) {
            VStack(alignment: .leading, spacing: spacing1) {
                Text("Virtual Camera")
                    .font(.system(.callout, design: .default, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text(virtualCamera.name)
                    .font(.system(.title3, design: .default, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: spacing1) {
                Text("Position")
                    .font(.system(.callout, design: .default, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("(\(String(format: "%.1f", virtualCamera.position.x)), \(String(format: "%.1f", virtualCamera.position.y)), \(String(format: "%.1f", virtualCamera.position.z)))")
                    .font(.system(.caption, design: .monospaced, weight: .regular))
                    .foregroundColor(.primary)
            }
        }
        .padding(.all, spacing3)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
    }
    
    // MARK: - Device List
    
    private var deviceList: some View {
        VStack(alignment: .leading, spacing: spacing3) {
            HStack(spacing: spacing2) {
                Text("Available Cameras")
                    .font(.system(.headline, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if cameraManager.isDiscovering {
                    HStack(spacing: spacing1) {
                        ProgressView()
                            .scaleEffect(0.7)
                        
                        Text("Discovering...")
                            .font(.system(.caption, design: .default, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("Refresh") {
                        Task {
                            await cameraManager.discoverDevices()
                        }
                    }
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.blue)
                }
            }
            
            if cameraManager.availableDevices.isEmpty && !cameraManager.isDiscovering {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: spacing2) {
                        ForEach(cameraManager.availableDevices) { device in
                            deviceRow(device)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            
            if let error = cameraManager.lastDiscoveryError {
                errorView(error)
            }
        }
    }
    
    private func deviceRow(_ device: CameraDevice) -> some View {
        Button(action: {
            onCameraSelected(device)
        }) {
            HStack(spacing: spacing3) {
                // Device icon
                Image(systemName: device.icon)
                    .font(.system(.title3, design: .default, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                
                // Device info
                VStack(alignment: .leading, spacing: spacing1) {
                    Text(device.displayName)
                        .font(.system(.body, design: .default, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(device.deviceType.rawValue)
                        .font(.system(.caption, design: .default, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status indicator
                HStack(spacing: spacing1) {
                    Circle()
                        .fill(device.statusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(device.statusText)
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundColor(device.statusColor)
                }
            }
            .padding(.all, spacing2)
            .background(device.isAvailable ? Color.clear : Color.gray.opacity(0.1))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(device.isAvailable ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!device.isAvailable)
        .opacity(device.isAvailable ? 1.0 : 0.6)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: spacing3) {
            Image(systemName: "camera.slash")
                .font(.system(.largeTitle, design: .default, weight: .thin))
                .foregroundColor(.secondary)
            
            Text("No Cameras Found")
                .font(.system(.headline, design: .default, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Make sure your camera is connected and not in use by another application.")
                .font(.system(.caption, design: .default, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, spacing4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, spacing5)
    }
    
    private func errorView(_ error: String) -> some View {
        HStack(spacing: spacing2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(.callout, design: .default, weight: .medium))
                .foregroundColor(.orange)
            
            Text(error)
                .font(.system(.caption, design: .default, weight: .regular))
                .foregroundColor(.orange)
            
            Spacer()
        }
        .padding(.all, spacing2)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: spacing3) {
            // Use Virtual Only button
            Button(action: {
                onCameraSelected(CameraDevice(
                    deviceID: "virtual-only",
                    name: "Virtual Camera Only",
                    deviceType: .unknown,
                    isAvailable: true,
                    captureDevice: nil
                ))
            }) {
                HStack(spacing: spacing1) {
                    Image(systemName: "cube.transparent")
                        .font(.system(.callout, design: .default, weight: .medium))
                    
                    Text("Virtual Only")
                        .font(.system(.body, design: .default, weight: .medium))
                }
                .padding(.horizontal, spacing3)
                .padding(.vertical, spacing2)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Cancel button
            Button("Cancel") {
                isPresented = false
            }
            .font(.system(.body, design: .default, weight: .medium))
            .foregroundColor(.secondary)
            
            // Test Connection button (if we have a selection)
            if let selectedDevice = cameraManager.availableDevices.first(where: { $0.isAvailable }) {
                Button("Test Connection") {
                    testCameraConnection(selectedDevice)
                }
                .font(.system(.body, design: .default, weight: .medium))
                .foregroundColor(.blue)
            }
        }
    }
    
    // MARK: - Actions
    
    private func testCameraConnection(_ device: CameraDevice) {
        // TODO: Implement camera connection test
        print("🧪 Testing camera connection for device: \(device.displayName)")
    }
    
    private let spacing5: CGFloat = 32
}

// MARK: - Preview

#Preview {
    @StateObject var cameraManager = CameraDeviceManager()
    @StateObject var virtualCamera = VirtualCamera(name: "Camera 1", position: SCNVector3(0, 1.5, 5))
    @State var isPresented = true
    
    CameraSelectionModal(
        cameraManager: cameraManager,
        virtualCamera: virtualCamera,
        isPresented: $isPresented
    ) { device in
        print("Selected device: \(device.displayName)")
        isPresented = false
    }
    .onAppear {
        cameraManager.availableDevices = CameraDeviceManager.mockDevices
    }
}