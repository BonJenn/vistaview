import SwiftUI
import AVFoundation

// MARK: – Camera Controller

final class CameraController: ObservableObject {
    let session = AVCaptureSession()

    init() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // video input
        guard let videoDevice = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
              ),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice)
        else {
            print("❌ Unable to open video device")
            session.commitConfiguration()
            return
        }
        session.addInput(videoInput)

        // audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice)
        else {
            print("❌ Unable to open audio device")
            session.commitConfiguration()
            return
        }
        session.addInput(audioInput)

        session.commitConfiguration()
    }
}

// MARK: – Preview Layer

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.wantsLayer = true
        view.layer?.addSublayer(previewLayer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: – Main UI

struct ContentView: View {
    @StateObject private var cam = CameraController()
    @State private var rtmpURL   = "rtmp://live.twitch.tv/app"
    @State private var streamKey = "<YOUR_STREAM_KEY>"
    @State private var isLive     = false

    private let streamer = FFmpegStreamer()

    var body: some View {
        VStack(spacing: 20) {
            CameraPreview(session: cam.session)
                .onAppear { cam.session.startRunning() }
                .frame(width: 640, height: 360)
                .cornerRadius(8)
                .shadow(radius: 4)

            HStack {
                TextField("RTMP URL", text: $rtmpURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Stream Key", text: $streamKey)
                    .textFieldStyle(.roundedBorder)
                Button(isLive ? "Stop" : "Go Live") {
                    if isLive {
                        streamer.stop()
                    } else {
                        streamer.start(rtmpURL: rtmpURL, streamKey: streamKey)
                    }
                    isLive.toggle()
                }
                .padding(.horizontal)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}
