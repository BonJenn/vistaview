//
//  CameraSelectionView.swift
//  Vantaview
//
//  Created by AI Assistant
//

import SwiftUI

struct CameraSelectionView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Camera Selection")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Divider()
            
            // Active Camera Feeds Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "video.circle.fill")
                        .foregroundColor(.green)
                    Text("Active Camera Feeds")
                        .font(.headline)
                    Spacer()
                    Text("\(productionManager.cameraFeedManager.activeFeeds.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(12)
                }
                
                if productionManager.cameraFeedManager.activeFeeds.isEmpty {
                    Text("No active camera feeds")
                        .foregroundColor(.secondary)
                        .font(.body)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
                    ], spacing: 16) {
                        ForEach(productionManager.cameraFeedManager.activeFeeds) { feed in
                            CameraFeedItem(feed: feed)
                        }
                    }
                }
            }
            
            Divider()
            
            // Available Devices Section  
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "camera.circle")
                        .foregroundColor(.blue)
                    Text("Available Cameras")
                        .font(.headline)
                    Spacer()
                    Button("Refresh") {
                        Task {
                            await productionManager.cameraFeedManager.forceRefreshDevices()
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(12)
                }
                
                // Show placeholder for now since we need async device loading
                Text("Camera devices will be loaded asynchronously")
                    .foregroundColor(.secondary)
                    .font(.body)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CameraFeedItem: View {
    @ObservedObject var feed: CameraFeed
    
    var body: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.green.opacity(0.2))
                .frame(height: 60)
                .overlay(
                    Group {
                        if let previewImage = feed.previewImage {
                            Image(nsImage: NSImage(cgImage: previewImage, size: NSSize(width: previewImage.width, height: previewImage.height)))
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .clipped()
                        } else {
                            Image(systemName: "video.fill")
                                .font(.largeTitle)
                                .foregroundColor(.green)
                        }
                    }
                )
                .liquidGlassMonitor(borderColor: TahoeDesign.Colors.live, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: feed.isActive)
            
            VStack(spacing: 2) {
                Text(feed.device.displayName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                HStack(spacing: 4) {
                    Circle()
                        .fill(feed.connectionStatus.color)
                        .frame(width: 6, height: 6)
                    Text("\(feed.frameCount) frames")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .cornerRadius(8)
    }
}

#Preview {
    Text("Camera Selection View")
        .padding()
}