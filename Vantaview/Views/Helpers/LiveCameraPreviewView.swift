//
//  LiveCameraPreviewView.swift
//  Vantaview
//
//  Created by AI Assistant
//

import SwiftUI
import AppKit

/// A specialized view for displaying live camera feeds that forces SwiftUI updates
struct LiveCameraPreviewView: View {
    @ObservedObject var cameraFeed: CameraFeed
    let maxHeight: CGFloat
    
    var previewProgramManager: PreviewProgramManager? = nil
    @State private var refreshTrigger = false
    
    var body: some View {
        Group {
            if let nsImage = cameraFeed.previewNSImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
                        refreshTrigger.toggle()
                    }
                    .id("\(cameraFeed.frameCount)-\(refreshTrigger)")
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        VStack(spacing: 2) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.4)
                            Text("CONNECTING...")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                    )
            }
        }
    }
}

/// NSImageView wrapper for SwiftUI that better handles live updates
struct LiveNSImageView: NSViewRepresentable {
    let nsImage: NSImage
    
    func makeNSView(context: Context) -> AppKit.NSImageView {
        let imageView = AppKit.NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter
        return imageView
    }
    
    func updateNSView(_ nsView: AppKit.NSImageView, context: Context) {
        nsView.image = nsImage
    }
}

#Preview {
    // Mock preview
    Rectangle()
        .fill(Color.gray)
        .aspectRatio(16/9, contentMode: .fit)
        .frame(maxHeight: 200)
}