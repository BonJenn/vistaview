//
//  LEDWallStatusPanel.swift
//  Vistaview
//
//  Created by AI Assistant
//

import SwiftUI
import SceneKit

struct LEDWallStatusPanel: View {
    @EnvironmentObject var studioManager: VirtualStudioManager
    @ObservedObject var cameraFeedManager: CameraFeedManager
    
    private let spacing2: CGFloat = 8
    private let spacing3: CGFloat = 16
    
    var ledWalls: [StudioObject] {
        return studioManager.studioObjects.filter { $0.type == .ledWall }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "tv.and.hifispeaker.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text("LED Wall Feeds")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Count badge
                Text("\(ledWalls.count)")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.black.opacity(0.8))
            
            if ledWalls.isEmpty {
                // Empty state
                VStack(spacing: spacing2) {
                    Image(systemName: "tv.slash")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("No LED Walls")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Add LED walls to connect camera feeds")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, spacing3)
            } else {
                // LED Wall list
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(ledWalls, id: \.id) { ledWall in
                            ledWallRow(ledWall)
                        }
                    }
                    .padding(.vertical, spacing2)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(.regularMaterial)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func ledWallRow(_ ledWall: StudioObject) -> some View {
        HStack(spacing: spacing2) {
            // LED Wall icon and status
            Image(systemName: ledWall.isDisplayingCameraFeed ? "tv.fill" : "tv")
                .font(.caption)
                .foregroundColor(ledWall.isDisplayingCameraFeed ? .green : .secondary)
                .frame(width: 16)
            
            // LED Wall name
            VStack(alignment: .leading, spacing: 1) {
                Text(ledWall.name)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if ledWall.isDisplayingCameraFeed,
                   let feedID = ledWall.connectedCameraFeedID,
                   let feed = cameraFeedManager.activeFeeds.first(where: { $0.id == feedID }) {
                    // Show connected camera info
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 4, height: 4)
                        
                        Text(feed.device.displayName)
                            .font(.caption2)
                            .foregroundColor(.green)
                            .lineLimit(1)
                    }
                } else {
                    Text("No feed connected")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Connection status indicator
            if ledWall.isDisplayingCameraFeed {
                // Live indicator with animation
                HStack(spacing: 2) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: UUID())
                    
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            } else {
                Button(action: {
                    // Show camera feed modal for this LED wall
                    NotificationCenter.default.post(
                        name: .showLEDWallCameraFeedModal,
                        object: ledWall
                    )
                }) {
                    Text("Connect")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(ledWall.isDisplayingCameraFeed ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            // Force refresh every second to show live updates
            if ledWall.isDisplayingCameraFeed {
                // This will trigger a UI update
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @StateObject var studioManager = VirtualStudioManager()
    @StateObject var cameraDeviceManager = CameraDeviceManager()
    @StateObject var cameraFeedManager = CameraFeedManager(cameraDeviceManager: cameraDeviceManager)
    
    return LEDWallStatusPanel(cameraFeedManager: cameraFeedManager)
        .environmentObject(studioManager)
        .frame(width: 300)
        .padding()
        .onAppear {
            // Add some mock LED walls for preview
            if let ledWallAsset = LEDWallAsset.predefinedWalls.first {
                studioManager.addLEDWall(from: ledWallAsset, at: SCNVector3(0, 2, 0))
                studioManager.addLEDWall(from: ledWallAsset, at: SCNVector3(3, 2, 0))
            }
        }
}