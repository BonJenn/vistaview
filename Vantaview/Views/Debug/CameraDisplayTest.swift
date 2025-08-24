//
//  CameraDisplayTest.swift
//  Vantaview
//
//  Simple test to verify camera image display
//

import SwiftUI

struct CameraDisplayTest: View {
    @EnvironmentObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Camera Display Test")
                .font(.title)
            
            if let selectedFeed = productionManager.cameraFeedManager.selectedFeedForLiveProduction {
                VStack(spacing: 16) {
                    Text("Selected Feed: \(selectedFeed.device.displayName)")
                        .font(.headline)
                    
                    Text("Status: \(selectedFeed.connectionStatus.displayText)")
                        .foregroundColor(selectedFeed.connectionStatus.color)
                    
                    Text("Frame Count: \(selectedFeed.frameCount)")
                        .font(.monospaced(.body)())
                    
                    Text("Has CGImage: \(selectedFeed.previewImage != nil)")
                        .foregroundColor(selectedFeed.previewImage != nil ? .green : .red)
                    
                    Text("Has NSImage: \(selectedFeed.previewNSImage != nil)")
                        .foregroundColor(selectedFeed.previewNSImage != nil ? .green : .red)
                    
                    // Try to display the image directly
                    if let nsImage = selectedFeed.previewNSImage {
                        VStack {
                            Text("NSImage Display Test:")
                                .font(.caption)
                            
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 400, maxHeight: 300)
                                .border(Color.green, width: 2)
                        }
                    }
                    
                    if let cgImage = selectedFeed.previewImage {
                        VStack {
                            Text("CGImage Display Test:")
                                .font(.caption)
                            
                            Image(decorative: cgImage, scale: 1.0)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 400, maxHeight: 300)
                                .border(Color.blue, width: 2)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("No Camera Selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Available Feeds: \(productionManager.cameraFeedManager.activeFeeds.count)")
                    
                    ForEach(productionManager.cameraFeedManager.activeFeeds) { feed in
                        HStack {
                            Text(feed.device.displayName)
                            Spacer()
                            Text(feed.connectionStatus.displayText)
                                .foregroundColor(feed.connectionStatus.color)
                            Button("Select") {
                                Task {
                                    await productionManager.cameraFeedManager.selectFeedForLiveProduction(feed)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding()
        .frame(width: 600, height: 700)
    }
}

#Preview {
    CameraDisplayTest()
}