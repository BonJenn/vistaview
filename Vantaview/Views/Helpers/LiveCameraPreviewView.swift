//
//  LiveCameraPreviewView.swift
//  Vantaview
//
//  Created by AI Assistant
//

import SwiftUI
import AppKit

@MainActor
struct LiveCameraPreviewView: View {
    @ObservedObject var cameraFeed: CameraFeed
    let maxHeight: CGFloat
    
    var body: some View {
        ZStack {
            CameraFeedDisplayLayerView(feed: cameraFeed)
                .background(Color.black)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .foregroundColor(.white.opacity(0.9))
                        Text(cameraFeed.connectionStatus.displayText)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(6)
                    .padding(6)
                }
                .overlay {
                    if cameraFeed.currentSampleBuffer == nil && cameraFeed.previewImage == nil && cameraFeed.previewNSImage == nil {
                        VStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.6)
                            Text(cameraFeed.connectionStatus == .connecting ? "CONNECTING..." : "INITIALIZING...")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxHeight: maxHeight)
        .clipped()
    }
    
    private var aspect: CGFloat {
        if let cg = cameraFeed.previewImage {
            return cg.height > 0 ? CGFloat(cg.width) / CGFloat(cg.height) : 16.0/9.0
        }
        if let ns = cameraFeed.previewNSImage, ns.size.height > 0 {
            return ns.size.width / ns.size.height
        }
        return 16.0/9.0
    }
}

#Preview {
    Rectangle()
        .fill(Color.gray)
        .aspectRatio(16/9, contentMode: .fit)
        .frame(maxHeight: 200)
}