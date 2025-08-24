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
    
    // Layout constants
    private let spacing1: CGFloat = 4   // Tight spacing
    private let spacing2: CGFloat = 8
    private let spacing3: CGFloat = 16
    private let spacing4: CGFloat = 24
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            modalHeader
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: spacing4) {
                    // LED Wall info
                    ledWallInfoView
                    
                    // Debug info
                    debugInfoView
                    
                    // Available camera feeds
                    cameraFeedList
                }
                .padding(.all, spacing4)
            }
            
            // Actions
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
    
    // MARK: - Header
    
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
    
    // MARK: - LED Wall Info
    
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
    
    // MARK: - Debug Info
    
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
    
    // MARK: - Camera Feed List
    
    private var cameraFeedList: some View {
        VStack(alignment: .leading, spacing: spacing3) {
            Text("Camera Management")
                .font(.system(.headline, design: .default, weight: .medium))
                .foregroundColor(.primary)
            
            // Available Devices Section
            if !cameraFeedManager.availableDevices.isEmpty {
                VStack(alignment: .leading, spacing: spacing2) {
                    Text("Available Camera Devices")
                        .font(.system(.callout, design: .default, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(cameraFeedManager.availableDevices, id: \.id) { device in
                        availableDeviceRow(device)
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
            
            // Active Feeds Section
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
    
    // MARK: - Device Rows
    
    private func availableDeviceRow(_ device: CameraDevice) -> some View {
        let hasActiveFeed = cameraFeedManager.activeFeeds.contains { $0.device.deviceID == device.deviceID }
        
        return HStack(spacing: spacing3) {
            Image(systemName: device.icon)
                .font(.system(.callout, design: .default, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.system(.callout, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack(spacing: spacing1) {
                    Text(device.deviceType.rawValue)
                        .font(.system(.caption2, design: .default, weight: .regular))
                        .foregroundColor(.secondary)
                    
                    Circle()
                        .fill(device.statusColor)
                        .frame(width: 6, height: 6)
                    
                    Text(device.statusText)
                        .font(.system(.caption2, design: .default, weight: .regular))
                        .foregroundColor(device.statusColor)
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
                .background(device.isAvailable ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(4)
                .disabled(!device.isAvailable)
            }
        }
        .padding(.all, spacing2)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }
    
    private func activeFeedRow(_ feed: CameraFeed) -> some View {
        let isCurrentlyConnected = ledWall.connectedCameraFeedID == feed.id
        
        return Button {
            connectFeed(feed)
        } label: {
            HStack(spacing: spacing3) {
                // Feed preview thumbnail
                Group {
                    if let nsImage = feed.previewNSImage {
                        // Use LiveNSImageView wrapper for better live updates
                        LiveNSImageView(nsImage: nsImage)
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: 80, height: 45)
                            .clipped()
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.green, lineWidth: 1)
                            )
                            .id("live-thumbnail-\(feed.id)-\(feed.frameCount)") // Force updates with frame count
                    } else if let previewImage = feed.previewImage {
                        // Fallback to CGImage with forced updates
                        Image(decorative: previewImage, scale: 1.0)
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: 80, height: 45)
                            .clipped()
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.green, lineWidth: 1)
                            )
                            .id("live-cgimage-thumbnail-\(feed.id)-\(feed.frameCount)") // Force updates
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 80, height: 45)
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
                                        Image(systemName: "camera.fill")
                                            .font(.system(.callout, design: .default, weight: .medium))
                                            .foregroundColor(.white)
                                        
                                        Text("No Preview")
                                            .font(.system(.caption2, design: .default, weight: .medium))
                                            .foregroundColor(.white)
                                    }
                                }
                            )
                            .cornerRadius(6)
                    }
                }
                
                // Feed info
                VStack(alignment: .leading, spacing: spacing2) {
                    Text(feed.device.displayName)
                        .font(.system(.body, design: .default, weight: .medium))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: spacing2) {
                        Image(systemName: feed.device.icon)
                            .font(.system(.caption, design: .default, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text(feed.device.deviceType.rawValue)
                            .font(.system(.caption, design: .default, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Connection status
                VStack(alignment: .trailing, spacing: spacing2) {
                    HStack(spacing: spacing2) {
                        Circle()
                            .fill(feed.connectionStatus.color)
                            .frame(width: 8, height: 8)
                        
                        Text(feed.connectionStatus.displayText)
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundColor(feed.connectionStatus.color)
                    }
                    
                    // Already connected indicator
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
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: spacing3) {
            // Disconnect button (if connected)
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
            
            // Cancel button
            Button("Cancel") {
                isPresented = false
            }
            .font(.system(.body, design: .default, weight: .medium))
            .foregroundColor(.secondary)
            
            // Debug button
            Button("Debug Cameras") {
                debugCameras()
            }
            .font(.system(.body, design: .default, weight: .medium))
            .foregroundColor(.orange)
        }
    }
    
    // MARK: - Actions
    
    private func refreshCameraData() {
        Task {
            print("🔄 Refreshing camera data...")
            await cameraFeedManager.forceRefreshDevices()
            
            print("📱 Available devices after refresh: \(cameraFeedManager.availableDevices.count)")
            for device in cameraFeedManager.availableDevices {
                print("  - \(device.displayName) (\(device.deviceType.rawValue)) - Available: \(device.isAvailable)")
            }
            
            print("📺 Active feeds: \(cameraFeedManager.activeFeeds.count)")
            for feed in cameraFeedManager.activeFeeds {
                print("  - \(feed.device.displayName) - Status: \(feed.connectionStatus.displayText)")
            }
        }
    }
    
    private func debugCameras() {
        Task {
            print("🧪 Running camera debug...")
            await cameraFeedManager.debugCameraDetection()
        }
    }
    
    private func startDeviceFeed(_ device: CameraDevice) {
        Task {
            print("🎬 Starting feed for device: \(device.displayName)")
            let feed = await cameraFeedManager.startFeed(for: device)
            if let feed = feed {
                print("✅ Feed started successfully: \(feed.device.displayName)")
            } else {
                print("❌ Failed to start feed for: \(device.displayName)")
            }
        }
    }
    
    private func connectFeed(_ feed: CameraFeed) {
        print("🔗 LEDWallCameraFeedModal: Connecting feed \(feed.id) to LED wall \(ledWall.name)")
        print("   - Feed status: \(feed.connectionStatus.displayText)")
        print("   - Feed has preview: \(feed.previewImage != nil)")
        print("   - Feed device: \(feed.device.displayName)")
        
        onFeedConnected(feed.id)
        isPresented = false
    }
    
    private func disconnectFeed() {
        onFeedConnected(nil)
        isPresented = false
    }
}

// MARK: - Preview

#Preview {
    @StateObject var cameraDeviceManager = CameraDeviceManager()
    @StateObject var cameraFeedManager = CameraFeedManager(cameraDeviceManager: cameraDeviceManager)
    @StateObject var ledWall = StudioObject(
        name: "Main LED Wall",
        type: .ledWall,
        position: SCNVector3(0, 2, 0)
    )
    @State var isPresented = true
    
    return LEDWallCameraFeedModal(
        ledWall: ledWall,
        cameraFeedManager: cameraFeedManager,
        isPresented: $isPresented
    ) { feedID in
        print("Selected feed ID: \(feedID?.uuidString ?? "nil")")
    }
    .onAppear {
        // Add some mock devices for preview
        cameraDeviceManager.availableDevices = CameraDeviceManager.mockDevices
    }
}