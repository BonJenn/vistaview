import SwiftUI
import HaishinKit
import AVFoundation

struct ContentView: View {
    @StateObject private var streamer = Streamer()
    @State private var isStreaming = false
    @State private var streamURL = "rtmp://127.0.0.1:1935/stream"
    @State private var streamKey = "test"

    var body: some View {
        VStack(spacing: 20) {
            // Live camera preview
            HaishinPreviewView(stream: streamer.stream)
                .frame(width: 640, height: 360)
                .cornerRadius(8)
                .shadow(radius: 4)

            // RTMP connection fields
            HStack {
                TextField("RTMP URL", text: $streamURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minWidth: 300)
                TextField("Stream Key", text: $streamKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minWidth: 150)
            }.padding(.horizontal)

            // Go Live / Stop button
            Button(isStreaming ? "Stop Streaming" : "Go Live") {
                if isStreaming {
                    streamer.stopStreaming()
                } else {
                    streamer.startStreaming(streamURL: streamURL, streamKey: streamKey)
                }
                isStreaming.toggle()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(isStreaming ? Color.red : Color.green)
            .foregroundColor(.white)
            .cornerRadius(6)
        }
        .padding()
    }
}

/// NSViewRepresentable wrapper for HaishinKit preview
struct HaishinPreviewView: NSViewRepresentable {
    let stream: RTMPStream
    
    func makeNSView(context: Context) -> NSView {
        // Create a container view
        let container = NSView()
        container.wantsLayer = true
        
        // Try to create MTHKView if it exists
        if let hkViewClass = NSClassFromString("HaishinKit.MTHKView") as? NSView.Type {
            let hkView = hkViewClass.init(frame: .zero)
            
            // Try to attach stream using performSelector
            if hkView.responds(to: Selector("attachStream:")) {
                hkView.perform(Selector("attachStream:"), with: stream)
            }
            
            container.addSubview(hkView)
            hkView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hkView.topAnchor.constraint(equalTo: container.topAnchor),
                hkView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hkView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hkView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else {
            // Fallback: Try to get a preview layer from the stream
            print("MTHKView not found, using fallback preview")
            
            // This is a placeholder - you'll need to implement based on what HaishinKit provides
            let label = NSTextField(labelWithString: "Camera Preview")
            label.alignment = .center
            container.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
        }
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Updates handled by the view itself
    }
}
