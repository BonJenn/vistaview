//
//  CameraSelectionView.swift
//  Vantaview
//
//  Created by AI Assistant
//

import SwiftUI
import AVFoundation

struct CameraSelectionView: View {
    @ObservedObject var cameraFeedManager: CameraFeedManager
    @ObservedObject var streamingViewModel: StreamingViewModel
    @ObservedObject var productionManager: UnifiedProductionManager
    
    @State private var showingDeviceSelector = false
    
    private let spacing2: CGFloat = 8
    private let spacing3: CGFloat = 16
    private let spacing4: CGFloat = 24
    
    var body: some View {
        VStack(spacing: spacing3) {
            HStack(spacing: spacing2) {
                Image(systemName: "camera.fill")
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text("Camera Source")
                    .font(.system(.headline, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if cameraFeedManager.isDiscovering {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Discovering...")
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundColor(.orange)
                    }
                } else {
                    Text("\(cameraFeedManager.availableDevices.count) devices")
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Button("Debug") {
                    Task { await cameraFeedManager.debugCameraDetection() }
                }
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundColor(.orange)
                
                Button(action: {
                    Task {
                        _ = await cameraFeedManager.getAvailableDevices()
                        showingDeviceSelector = true
                    }
                }) {
                    HStack(spacing: spacing2) {
                        Image(systemName: "plus.circle.fill").font(.system(.callout, design: .default, weight: .medium))
                        Text("Select Camera").font(.system(.callout, design: .default, weight: .medium))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            if let selectedFeed = cameraFeedManager.selectedFeedForLiveProduction {
                activeCameraFeedView(selectedFeed)
            } else {
                emptyCameraStateView
            }
        }
        .padding(.all, spacing3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingDeviceSelector) {
            CameraDeviceSelectorSheet(
                devices: cameraFeedManager.availableDevices,
                cameraFeedManager: cameraFeedManager,
                productionManager: productionManager,
                isPresented: $showingDeviceSelector
            )
        }
    }
    
    private func activeCameraFeedView(_ feed: CameraFeed) -> some View {
        VStack(spacing: spacing3) {
            HStack(spacing: spacing3) {
                HStack(spacing: spacing2) {
                    Image(systemName: feed.device.icon)
                        .font(.system(.callout, design: .default, weight: .medium))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feed.device.displayName)
                            .font(.system(.body, design: .default, weight: .medium))
                            .foregroundColor(.primary)
                        Text(feed.device.deviceType.rawValue)
                            .font(.system(.caption, design: .default, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: spacing2) {
                    Circle().fill(feed.connectionStatus.color).frame(width: 8, height: 8)
                    Text(feed.connectionStatus.displayText)
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundColor(feed.connectionStatus.color)
                }
                Button("Disconnect") {
                    cameraFeedManager.stopFeed(feed)
                }
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundColor(.red)
            }
            cameraPreviewView(feed)
            cameraControlsView(feed)
        }
    }
    
    private func cameraPreviewView(_ feed: CameraFeed) -> some View {
        VStack { LiveCameraPreviewView(cameraFeed: feed, maxHeight: 200) }
    }
    
    private func cameraControlsView(_ feed: CameraFeed) -> some View {
        HStack(spacing: spacing4) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Resolution")
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                Picker("Resolution", selection: .constant("720p")) {
                    Text("480p").tag("480p")
                    Text("720p").tag("720p")
                    Text("1080p").tag("1080p")
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Frame Rate")
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                Text("30 fps")
                    .font(.system(.caption, design: .monospaced, weight: .regular))
                    .foregroundColor(.primary)
            }
        }
    }
    
    private var emptyCameraStateView: some View {
        VStack(spacing: spacing4) {
            Rectangle()
                .fill(Color.black)
                .aspectRatio(16/9, contentMode: .fit)
                .frame(maxHeight: 200)
                .overlay(
                    VStack(spacing: spacing3) {
                        Image(systemName: "camera.badge.plus")
                            .font(.system(.largeTitle, design: .default, weight: .thin))
                            .foregroundColor(.secondary)
                        Text("No Camera Selected")
                            .font(.system(.headline, design: .default, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Select a camera to see live preview")
                            .font(.system(.caption, design: .default, weight: .regular))
                            .foregroundColor(.secondary)
                        Button("Select Camera") {
                            Task {
                                _ = await cameraFeedManager.getAvailableDevices()
                                showingDeviceSelector = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                )
                .cornerRadius(8)
        }
    }
}

// MARK: - Camera Device Selector Sheet

struct CameraDeviceSelectorSheet: View {
    let devices: [CameraDevice]
    @ObservedObject var cameraFeedManager: CameraFeedManager
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var isPresented: Bool
    
    private let spacing2: CGFloat = 8
    private let spacing3: CGFloat = 16
    private let spacing4: CGFloat = 24
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: spacing3) {
                Image(systemName: "camera.circle.fill")
                    .font(.system(.title2, design: .default, weight: .semibold))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select Camera")
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Choose which camera to use for live production")
                        .font(.system(.caption, design: .default, weight: .regular))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.all, spacing4)
            .background(.black.opacity(0.05))
            
            Divider()
            
            if devices.isEmpty {
                emptyDeviceListView
            } else {
                ScrollView {
                    LazyVStack(spacing: spacing2) {
                        ForEach(devices) { device in
                            deviceSelectionRow(device)
                        }
                    }
                    .padding(.all, spacing3)
                }
            }
        }
        .frame(width: 500, height: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 12)
    }
    
    private func deviceSelectionRow(_ device: CameraDevice) -> some View {
        Button(action: { selectDevice(device) }) {
            HStack(spacing: spacing3) {
                Image(systemName: device.icon)
                    .font(.system(.title3, design: .default, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: spacing2) {
                    Text(device.displayName)
                        .font(.system(.body, design: .default, weight: .medium))
                        .foregroundColor(.primary)
                    Text(device.deviceType.rawValue)
                        .font(.system(.caption, design: .default, weight: .regular))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: spacing2) {
                    Circle().fill(device.statusColor).frame(width: 8, height: 8)
                    Text(device.statusText)
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundColor(device.statusColor)
                }
                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.all, spacing3)
            .background(device.isAvailable ? Color.clear : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(device.isAvailable ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!device.isAvailable)
        .opacity(device.isAvailable ? 1.0 : 0.6)
    }
    
    private var emptyDeviceListView: some View {
        VStack(spacing: spacing4) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func selectDevice(_ device: CameraDevice) {
        Task {
            if let feed = await cameraFeedManager.startFeed(for: device) {
                await cameraFeedManager.selectFeedForLiveProduction(feed)
                await MainActor.run {
                    productionManager.switchProgram(to: device.deviceID)
                    isPresented = false
                }
            }
        }
    }
}