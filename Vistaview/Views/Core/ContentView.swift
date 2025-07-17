import SwiftUI
import HaishinKit
import AVFoundation

struct ContentView: View {
    @StateObject private var viewModel = StreamingViewModel()
    @State private var rtmpURL = "rtmp://127.0.0.1:1935/stream"
    @State private var streamKey = "test"

    var body: some View {
        VStack(spacing: 16) {
            Text("Vistaview Streaming App")
                .font(.largeTitle)
                .padding()
            
            // Status Display
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(viewModel.cameraSetup ? .green : .orange)
                .padding(.horizontal)
            
            // Settings Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("RTMP URL:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("rtmp://…", text: $rtmpURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack {
                    Text("Stream Key:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("yourStreamName", text: $streamKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            .padding(.horizontal)

            // Camera Preview
            CameraPreview(viewModel: viewModel)
                .frame(minHeight: 360)
                .border(Color.gray)
                .overlay(
                    // Show loading indicator if camera isn't ready
                    Group {
                        if !viewModel.cameraSetup {
                            VStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                Text("Setting up camera...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                        }
                    }
                )

            // Start / Stop Button
            Button(action: {
                Task {
                    await toggleStreaming()
                }
            }) {
                Text(viewModel.isPublishing ? "Stop Streaming" : "Start Streaming")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .disabled(!viewModel.cameraSetup)  // Disable button until camera is ready
            .padding(.horizontal)
        }
        .padding()
        .task {
            await requestPermissions()
            await viewModel.setupCamera()
        }
    }

    private func toggleStreaming() async {
        if viewModel.isPublishing {
            await viewModel.stop()
        } else {
            do {
                try await viewModel.start(rtmpURL: rtmpURL, streamKey: streamKey)
            } catch {
                print("Setup error:", error)
            }
        }
    }

    private func requestPermissions() async {
        let _ = await AVCaptureDevice.requestAccess(for: .video)
        let _ = await AVCaptureDevice.requestAccess(for: .audio)
    }
}

// Camera Preview Component
#if os(macOS)
import AppKit
struct CameraPreview: NSViewRepresentable {
    let viewModel: StreamingViewModel
    
    func makeNSView(context: Context) -> MTHKView {
        let view = MTHKView(frame: CGRect.zero)
        Task { @MainActor in
            await viewModel.attachPreview(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: MTHKView, context: Context) {
        // Updates handled through viewModel
    }
}
#else
import UIKit
struct CameraPreview: UIViewRepresentable {
    let viewModel: StreamingViewModel
    
    func makeUIView(context: Context) -> MTHKView {
        let view = MTHKView(frame: CGRect.zero)
        Task { @MainActor in
            await viewModel.attachPreview(view)
        }
        return view
    }
    
    func updateUIView(_ uiView: MTHKView, context: Context) {
        // Updates handled through viewModel
    }
}
#endif
