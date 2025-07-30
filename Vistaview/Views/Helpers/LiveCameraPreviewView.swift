//
//  LiveCameraPreviewView.swift
//  Vistaview
//
//  Created by AI Assistant
//

import SwiftUI
import AppKit

/// A specialized view for displaying live camera feeds that forces SwiftUI updates
struct LiveCameraPreviewView: View {
    @ObservedObject var cameraFeed: CameraFeed
    let maxHeight: CGFloat
    
    // Optional PreviewProgramManager for clicking to send to preview
    var previewProgramManager: PreviewProgramManager? = nil
    
    // Force updates using a timer
    @State private var refreshTrigger = false
    
    var body: some View {
        Group {
            if let nsImage = cameraFeed.previewNSImage {
                LiveNSImageView(nsImage: nsImage)
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxHeight: maxHeight)
                    .background(Color.black)
                    .cornerRadius(8)
                    .overlay(
                        // Add click indicator if preview program manager is available
                        Group {
                            if previewProgramManager != nil {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue, lineWidth: 2)
                                    .overlay(
                                        VStack {
                                            Spacer()
                                            HStack {
                                                Spacer()
                                                Text("CLICK TO SEND TO PREVIEW")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.blue.opacity(0.8))
                                                    .cornerRadius(4)
                                            }
                                            .padding(.trailing, 8)
                                            .padding(.bottom, 8)
                                        }
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green, lineWidth: 2)
                            }
                        }
                    )
                    .onTapGesture {
                        // Send camera feed to preview when clicked
                        if let previewProgramManager = previewProgramManager {
                            print("🎬 Sending camera feed \(cameraFeed.device.displayName) to PREVIEW")
                            let cameraSource = cameraFeed.asContentSource()
                            previewProgramManager.loadToPreview(cameraSource)
                        }
                    }
                    .help(previewProgramManager != nil ? "Click to send this camera feed to Preview pane" : "Live camera feed")
                    .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
                        // Force refresh at ~30fps
                        refreshTrigger.toggle()
                    }
                    .id("\(cameraFeed.frameCount)-\(refreshTrigger)")
            } else {
                Rectangle()
                    .fill(Color.black)
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxHeight: maxHeight)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .green))
                            
                            Text("Frames: \(cameraFeed.frameCount)")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Text("Waiting for video...")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    )
                    .cornerRadius(8)
            }
        }
    }
}

/// NSImageView wrapper for SwiftUI that better handles live updates
struct LiveNSImageView: NSViewRepresentable {
    let nsImage: NSImage
    
    func makeNSView(context: Context) -> AppKit.NSImageView {
        let imageView = AppKit.NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        return imageView
    }
    
    func updateNSView(_ nsView: AppKit.NSImageView, context: Context) {
        // Always update the image, even if it appears to be the "same" NSImage
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