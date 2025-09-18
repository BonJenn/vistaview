//
//  LEDWallCameraFeedModal.swift
//  Vantaview
//
//  Created by AI Assistant
//

import SwiftUI
import SceneKit

struct LEDWallCameraFeedModal: View {
    @ObservedObject var ledWall: StudioObject
    @ObservedObject var cameraFeedManager: CameraFeedManager
    @Binding var isPresented: Bool
    
    let onFeedConnected: (UUID?) -> Void
    
    private let spacing1: CGFloat = 4
    private let spacing2: CGFloat = 8
    private let spacing3: CGFloat = 16
    private let spacing4: CGFloat = 24
    
    var body: some View {
        VStack(spacing: 0) {
            modalHeader
            Divider()
            ScrollView {
                VStack(spacing: spacing4) {
                    ledWallInfoView
                    debugInfoView
                    cameraFeedList
                }
                .padding(.all, spacing4)
            }
            Divider()
            actionButtons
                .padding(.all, spacing4)
        }
        .frame(width: 600, height: 700)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            refreshCameraData()
        }
    }
    
    private var modalHeader: some View {
        HStack(spacing: spacing3) {
            Image(systemName: "tv.and.hifispeaker.fill")
                .font(.system(.title2, design: .default, weight: .semibold))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect Camera Feed")
                    .font(.system(.title2, design: .default, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Display live camera feed on \(ledWall.name)")
                    .font(.system(.caption, design: .default, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Refresh") {
                refreshCameraData()
            }
            .font(.system(.caption, design: .default, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.2))
            .foregroundColor(.blue)
            .cornerRadius(4)
            
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
    
    private var ledWallInfoView: some View {
        HStack(spacing: spacing3) {
            VStack(alignment: .leading, spacing: spacing2) {
                Text("LED Wall")
                    .font(.system(.callout, design: .default, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text(ledWall.name)
                    .font(.system(.title3, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("Position: (\(String(format: "%.1f", ledWall.position.x)), \(String(format: "%.1f", ledWall.position.y)), \(String(format: "%.1f", ledWall.position.z)))")
                    .font(.system(.caption, design: .monospaced, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: spacing2) {
                Text("Current Content")
                    .font(.system(.callout, design: .default, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: spacing2) {
                    Image(systemName: ledWall.ledWallContentType.icon)
                        .font(.system(.callout, design: .default, weight: .medium))
                        .foregroundColor(ledWall.isDisplayingCameraFeed ? .green : .secondary)
                    
                    Text(ledWall.ledWallContentType.displayName)
                        .font(.system(.callout, design: .default, weight: .medium))
                        .foregroundColor(ledWall.isDisplayingCameraFeed ? .green : .secondary)
                }
            }
        }
        .padding(.all, spacing3)
        .background(ledWall.isDisplayingCameraFeed ? Color.green.opacity(0.1) : Color.gray.opacity(0.15))
        .cornerRadius(8)
    }
    
    private var debugInfoView: some View {
        VStack(alignment: .leading, spacing: spacing2) {
            Text("Debug Info")
                .font(.system(.callout, design: .default, weight: .semibold))
                .foregroundColor(.orange)
            
            HStack {
                Text("Available Devices: \(cameraFeedManager.availableDevices.count)")
                    .font(.system(.caption, design: .default, weight: .regular))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Active Feeds: \(cameraFeedManager.activeFeeds.count)")
                    .font(.system(.caption, design: .default, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            if cameraFeedManager.isDiscovering {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Discovering cameras...")
                        .font(.system(.caption2, design: .default, weight: .regular))
                        .foregroundColor(.blue)
                }
            }
            
            if let error = cameraFeedManager.lastDiscoveryError {
                Text("Error: \(error)")
                    .font(.system(.caption2, design: .default, weight: .regular))
                    .foregroundColor(.red)
            }
        }
        .padding(.all, spacing2)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }
    
    private var cameraFeedList: some View {
        VStack(alignment: .leading, spacing: spacing3) {
            Text("Camera Management")
                .font(.system(.headline, design: .default, weight: .medium))
                .foregroundColor(.primary)
            
            if !cameraFeedManager.availableDevices.isEmpty {
                VStack(alignment: .leading, spacing: spacing2) {
                    Text("Available Camera Devices")
                        .font(.system(.callout, design: .default, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(cameraFeedManager.availableDevices, id: \.id) { device in
                        // Convert CameraDevice to LegacyCameraDevice for compatibility
                        let legacyDevice = LegacyCameraDevice(
                            id: device.id,
                            deviceID: device.deviceID,
                            displayName: device.displayName,
                            localizedName: device.displayName,
                            modelID: device.deviceID,
                            manufacturer: "Unknown",
                            isConnected: true
                        )
                        availableDeviceRow(legacyDevice)
                    }
                }
            } else {
                VStack(spacing: spacing2) {
                    Image(systemName: "camera.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("No Camera Devices Found")
                        .font(.system(.headline, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("Make sure cameras are connected and permissions are granted.")
                        .font(.system(.caption, design: .default, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, spacing4)
            }
            
            if !cameraFeedManager.activeFeeds.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: spacing2) {
                    Text("Active Camera Feeds")
                        .font(.system(.callout, design: .default, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(cameraFeedManager.activeFeeds) { feed in
                        activeFeedRow(feed)
                    }
                }
            }
        }
    }
    
    private func availableDeviceRow(_ device: LegacyCameraDevice) -> some View {
        let hasActiveFeed = cameraFeedManager.activeFeeds.contains { $0.device.deviceID == device.deviceID }
        
        return HStack(spacing: spacing3) {
            Image(systemName: "video.circle.fill") // Use generic camera icon
                .font(.system(.callout, design: .default, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.system(.callout, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("Camera") // Replace device.deviceType.rawValue
                    .font(.system(.caption2, design: .default))
                    .foregroundColor(.secondary)
                
                if let status = device.isConnected ? "Connected" : nil {
                    Text(status)
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundColor(.green) // Replace device.statusColor
                }
            }
            
            Spacer()
            
            if hasActiveFeed {
                Text("Feed Active")
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)
            } else {
                Button("Start Feed") {
                    startDeviceFeed(device)
                }
                .font(.system(.caption, design: .default, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(device.isConnected ? Color.blue : Color.gray) // Use isConnected instead of isAvailable
                .foregroundColor(.white)
                .cornerRadius(4)
                .disabled(!device.isConnected) // Use isConnected instead of isAvailable
            }
        }
        .padding(.horizontal, spacing4)
        .padding(.vertical, spacing2)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func activeFeedRow(_ feed: CameraFeed) -> some View {
        let isCurrentlyConnected = ledWall.connectedCameraFeedID == feed.id
        
        return Button {
            connectFeed(feed)
        } label: {
            HStack(spacing: spacing3) {
                CameraFeedThumbnailView(feed: feed)
                    .frame(width: 80, height: 45)
                
                VStack(alignment: .leading, spacing: spacing2) {
                    Text(feed.device.displayName)
                        .font(.system(.body, design: .default, weight: .medium))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: spacing2) {
                        Image(systemName: "video.fill")
                            .font(.system(.caption, design: .default, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("Camera") // Replace feed.device.deviceType.rawValue with generic text
                            .font(.system(.caption, design: .default, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: spacing2) {
                    HStack(spacing: spacing2) {
                        Circle()
                            .fill(feed.connectionStatus.color)
                            .frame(width: 8, height: 8)
                        
                        Text(feed.connectionStatus.displayText)
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundColor(feed.connectionStatus.color)
                    }
                    
                    if isCurrentlyConnected {
                        Text("Connected")
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    } else {
                        Text("Select")
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.all, spacing3)
            .background(isCurrentlyConnected ? Color.green.opacity(0.1) : Color.blue.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCurrentlyConnected ? Color.green : Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(feed.connectionStatus != .connected)
        .opacity(feed.connectionStatus == .connected ? 1.0 : 0.6)
    }
    
    private var actionButtons: some View {
        HStack(spacing: spacing3) {
            if ledWall.isDisplayingCameraFeed {
                Button(action: {
                    disconnectFeed()
                }) {
                    HStack(spacing: spacing2) {
                        Image(systemName: "multiply.circle")
                            .font(.system(.callout, design: .default, weight: .medium))
                        
                        Text("Disconnect")
                            .font(.system(.body, design: .default, weight: .medium))
                    }
                    .padding(.horizontal, spacing3)
                    .padding(.vertical, spacing2)
                    .background(Color.red.opacity(0.2))
                    .foregroundColor(.red)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Button("Cancel") {
                isPresented = false
            }
            .font(.system(.body, design: .default, weight: .medium))
            .foregroundColor(.secondary)
            
            Button("Debug Cameras") {
                debugCameras()
            }
            .font(.system(.body, design: .default, weight: .medium))
            .foregroundColor(.orange)
        }
    }
    
    private func refreshCameraData() {
        Task {
            await cameraFeedManager.forceRefreshDevices()
        }
    }
    
    private func debugCameras() {
        Task {
            await cameraFeedManager.debugCameraDetection()
        }
    }
    
    private func startDeviceFeed(_ device: LegacyCameraDevice) {
        Task {
            // Convert to CameraDeviceInfo for new API
            let deviceInfo = device.asCameraDeviceInfo
            if let feed = await cameraFeedManager.startFeed(for: deviceInfo) {
                onFeedConnected(feed.id)
            }
        }
    }
    
    private func connectFeed(_ feed: CameraFeed) {
        onFeedConnected(feed.id)
        isPresented = false
    }
    
    private func disconnectFeed() {
        onFeedConnected(nil)
        isPresented = false
    }
}

struct CameraFeedThumbnailView: View {
    @ObservedObject var feed: CameraFeed
    
    var body: some View {
        ZStack {
            if let cg = feed.previewImage {
                Image(decorative: cg, scale: 1.0)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
            } else if let ns = feed.previewNSImage {
                Image(nsImage: ns)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        VStack(spacing: 2) {
                            if feed.connectionStatus == .connected {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .green))
                                
                                Text("Loading...")
                                    .font(.system(.caption2, design: .default, weight: .medium))
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "video.fill") // Use generic camera icon
                                    .font(.system(.callout, design: .default, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Text("No Preview")
                                    .font(.system(.caption2, design: .default, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                    )
            }
        }
        .clipped()
        .cornerRadius(8) // Use fixed value instead of cornerRadius2
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green, lineWidth: 1)
        )
        .id("live-thumb-\(feed.id)-\(feed.frameCount)")
    }
}

#Preview {
        Text("LED Wall Camera Feed Modal")
            .frame(width: 800, height: 600)
    }