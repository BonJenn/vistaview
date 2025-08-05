import SwiftUI
import AVKit
import Combine
import CoreVideo

class VideoFrameObserver: ObservableObject {
    @Published var currentFrame: NSImage?
    
    private var player: AVPlayer
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CVDisplayLink?
    private var playerItemObserver: AnyCancellable?
    private let observerId = UUID()

    init(player: AVPlayer) {
        self.player = player
        print("🎬 VideoFrameObserver: Created with ID: \(observerId)")
        setupObservers()
        setupDisplayLink()
    }

    private func setupObservers() {
        print("🎬 VideoFrameObserver \(observerId): Setting up observers")
        playerItemObserver = player.publisher(for: \.currentItem).sink { [weak self] newItem in
            print("🎬 VideoFrameObserver: Player item changed to: \(newItem?.description ?? "nil")")
            self?.setupVideoOutput(for: newItem)
        }
    }

    private func setupVideoOutput(for item: AVPlayerItem?) {
        print("🎬 VideoFrameObserver \(observerId): Setting up video output")
        
        // Remove output from any previous item
        if let currentItem = player.currentItem, let existingOutput = self.videoOutput {
            if currentItem.outputs.contains(existingOutput) {
                currentItem.remove(existingOutput)
                print("🎬 VideoFrameObserver: Removed existing video output")
            }
        }

        guard let currentItem = item else {
            videoOutput = nil
            print("🎬 VideoFrameObserver: No current item, clearing video output")
            return
        }
        
        print("🎬 VideoFrameObserver: Setting up video output for new item")
        
        // Add a status observer to the new item
        playerItemObserver = currentItem.publisher(for: \.status).sink { [weak self] status in
            print("🎬 VideoFrameObserver: Player item status changed to: \(status.description)")
            switch status {
            case .readyToPlay:
                print("✅ Player item is ready to play.")
                DispatchQueue.main.async {
                    self?.player.play() // Auto-play when ready
                }
            case .failed:
                print("❌ Player item failed. Error: \(currentItem.error?.localizedDescription ?? "Unknown error")")
            case .unknown:
                print("🤔 Player item status is unknown.")
            @unknown default:
                break
            }
        }
        
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ] as [String : Any]
        
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        
        if !currentItem.outputs.contains(output) {
            currentItem.add(output)
            self.videoOutput = output
            print("✅ Video output attached to new player item.")
        } else if let existing = currentItem.outputs.first(where: { $0 is AVPlayerItemVideoOutput }) as? AVPlayerItemVideoOutput {
            self.videoOutput = existing
            print("✅ Found existing video output on player item.")
        }
    }
    
    private func setupDisplayLink() {
        print("🎬 VideoFrameObserver \(observerId): Setting up display link")
        
        // Create a CVDisplayLink
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        
        guard let displayLink = displayLink else {
            print("❌ Failed to create CVDisplayLink.")
            return
        }
        
        // Set the callback function
        let callback: CVDisplayLinkOutputCallback = { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
            // Safely get a reference to our VideoFrameObserver
            if let context = displayLinkContext {
                let observer = Unmanaged<VideoFrameObserver>.fromOpaque(context).takeUnretainedValue()
                observer.frameAvailable()
            }
            return kCVReturnSuccess
        }
        
        // Pass a reference to self (the observer) to the callback
        let selfAsContext = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, selfAsContext)
        
        // Start the display link
        CVDisplayLinkStart(displayLink)
        print("✅ Display link started for VideoFrameObserver \(observerId)")
    }
    
    // This is now called by the CVDisplayLink callback
    func frameAvailable() {
        guard let videoOutput = videoOutput,
              let currentItem = player.currentItem,
              currentItem.status == .readyToPlay else {
            return
        }
        
        let time = currentItem.currentTime()
        if videoOutput.hasNewPixelBuffer(forItemTime: time) {
            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let context = CIContext()
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    DispatchQueue.main.async {
                        self.currentFrame = NSImage(cgImage: cgImage, size: ciImage.extent.size)
                    }
                }
            }
        }
    }
    
    deinit {
        print("🗑️ VideoFrameObserver \(observerId) is being deinitialized.")
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
            print("🗑️ Display link stopped for VideoFrameObserver \(observerId)")
        }
        playerItemObserver?.cancel()
        print("🗑️ VideoFrameObserver \(observerId) deinitialized.")
    }
}

struct FrameBasedVideoPlayerView: View {
    let player: AVPlayer
    @StateObject private var frameObserver: VideoFrameObserver
    @State private var isPlayerActive = false
    
    init(player: AVPlayer) {
        self.player = player
        _frameObserver = StateObject(wrappedValue: VideoFrameObserver(player: player))
    }
    
    var body: some View {
        Group {
            if let frame = frameObserver.currentFrame {
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.6)
                            Text("Loading Media...")
                                .font(.caption)
                                .foregroundColor(.white)
                            if let currentItem = player.currentItem {
                                Text("Status: \(currentItem.status.description)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                    )
            }
        }
        .onAppear {
            print("🎬 FrameBasedVideoPlayerView: View appeared, starting playback")
            isPlayerActive = true
            player.play()
        }
        .onDisappear {
            print("🎬 FrameBasedVideoPlayerView: View disappeared, pausing playback")
            isPlayerActive = false
            player.pause()
        }
        .background(Color.black) // Ensure we have a stable background
        .clipped() // Ensure content doesn't overflow
    }
}

extension AVPlayerItem.Status {
    var description: String {
        switch self {
        case .readyToPlay:
            return "Ready to Play"
        case .failed:
            return "Failed"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown Default"
        }
    }
}