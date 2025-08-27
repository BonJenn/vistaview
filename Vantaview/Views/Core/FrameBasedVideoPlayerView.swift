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
    private var statusObserver: NSKeyValueObservation?
    private let observerId = UUID()
    private let isPreview: Bool
    private var hasVideoOutput = false // Track if we've successfully added output
    private var lastNoBufferLogTime: TimeInterval = 0 // Track last log time
    private var callbackCount = 0 // Track display link callbacks
    private let frameProcessor: ((CGImage) -> CGImage?)?
    private let processingQueue = DispatchQueue(label: "vantaview.video.fx.processing", qos: .userInteractive)

    init(player: AVPlayer, isPreview: Bool = false, frameProcessor: ((CGImage) -> CGImage?)? = nil) {
        self.player = player
        self.isPreview = isPreview
        self.frameProcessor = frameProcessor
        print("🎬 VideoFrameObserver: Created with ID: \(observerId) for \(isPreview ? "PREVIEW" : "PROGRAM")")
        setupObservers()
        setupDisplayLink()
    }

    private func setupObservers() {
        print("🎬 VideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")): Setting up observers")
        
        // Observe player item changes
        playerItemObserver = player.publisher(for: \.currentItem).sink { [weak self] newItem in
            guard let self = self else { return }
            print("🎬 VideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Player item changed to: \(newItem?.description ?? "nil")")
            self.setupVideoOutput(for: newItem)
        }
        
        // Also set up immediate observation if current item exists
        if let currentItem = player.currentItem {
            setupVideoOutput(for: currentItem)
        }
    }

    private func setupVideoOutput(for item: AVPlayerItem?) {
        print("🎬 VideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")): Setting up video output")
        
        // Clean up previous status observer
        statusObserver?.invalidate()
        statusObserver = nil
        hasVideoOutput = false
        
        // Remove output from any previous item
        if let existingOutput = self.videoOutput {
            // FIXED: Remove from all items, not just current one
            if let previousItem = player.currentItem {
                if previousItem.outputs.contains(existingOutput) {
                    previousItem.remove(existingOutput)
                    print("🎬 VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): Removed existing video output from previous item")
                }
            }
            self.videoOutput = nil
        }

        guard let currentItem = item else {
            videoOutput = nil
            print("🎬 VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): No current item, clearing video output")
            return
        }
        
        print("🎬 VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): Setting up video output for new item")
        
        // FIXED: Create video output immediately, don't wait for ready status
        self.createVideoOutput(for: currentItem)
        
        // Set up status observer for debugging
        statusObserver = currentItem.observe(\.status, options: [.new, .initial]) { [weak self] item, change in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                print("🎬 VideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Status changed to \(item.status.description)")
                
                switch item.status {
                case .readyToPlay:
                    print("✅ VideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Player item is ready")
                    // Video output should already be created
                    
                case .failed:
                    print("❌ VideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Failed - \(item.error?.localizedDescription ?? "Unknown")")
                    
                case .unknown:
                    print("🤔 VideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Status still unknown")
                    
                @unknown default:
                    print("🆕 VideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Unknown status: \(item.status.rawValue)")
                }
            }
        }
    }
    
    private func createVideoOutput(for item: AVPlayerItem) {
        guard !hasVideoOutput else {
            print("🎬 VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): Video output already exists, skipping")
            return
        }
        
        print("🎬 VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): Creating video output")
        
        // Use different pixel buffer attributes for preview vs program to avoid conflicts
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            // Add unique identifier to avoid conflicts
            "VideoFrameObserver" as String: "\(observerId)-\(isPreview ? "preview" : "program")"
        ] as [String : Any]
        
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        
        // Check if item already has too many outputs
        if item.outputs.count > 2 {
            print("⚠️ VideoFrameObserver: Player item has \(item.outputs.count) outputs, clearing some first")
            // Keep only the first output to avoid conflicts
            let outputsToRemove = Array(item.outputs.dropFirst())
            for existingOutput in outputsToRemove {
                item.remove(existingOutput)
            }
        }
        
        item.add(output)
        self.videoOutput = output
        self.hasVideoOutput = true
        print("✅ Video output created and attached for \(isPreview ? "PREVIEW" : "PROGRAM")")
    }
    
    private func setupDisplayLink() {
        print("🎬 VideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")): Setting up display link")
        
        // Create a CVDisplayLink
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        
        guard let displayLink = displayLink else {
            print("❌ Failed to create CVDisplayLink for \(isPreview ? "PREVIEW" : "PROGRAM").")
            return
        }
        
        // Set the callback function
        let callback: CVDisplayLinkOutputCallback = { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
            if let context = displayLinkContext {
                let observer = Unmanaged<VideoFrameObserver>.fromOpaque(context).takeUnretainedValue()
                // Add periodic logging to verify callback is running
                observer.callbackCount += 1
                if observer.callbackCount % 60 == 0 { // Log every 60 calls (about once per second at 60fps)
                    print("🔄 Display link callback #\(observer.callbackCount) for \(observer.isPreview ? "PREVIEW" : "PROGRAM")")
                }
                observer.frameAvailable()
            }
            return kCVReturnSuccess
        }
        
        // Pass a reference to self (the observer) to the callback
        let selfAsContext = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, selfAsContext)
        
        // Start the display link
        let result = CVDisplayLinkStart(displayLink)
        if result == kCVReturnSuccess {
            print("✅ Display link started successfully for VideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM"))")
        } else {
            print("❌ Failed to start display link for VideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")): \(result)")
        }
    }
    
    // This is now called by the CVDisplayLink callback
    func frameAvailable() {
        guard let videoOutput = videoOutput else {
            print("❌ VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): No video output")
            return
        }
        
        guard let currentItem = player.currentItem else {
            print("❌ VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): No current item")
            return
        }
        
        // COMPREHENSIVE DEBUGGING
        let time = currentItem.currentTime()
        let timeSeconds = CMTimeGetSeconds(time)
        let playerRate = player.rate
        let itemStatus = currentItem.status
        
        // Print debug info every second when playing
        if Int(timeSeconds) != Int(timeSeconds) || playerRate > 0 {
            print("🎬 VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): Frame check - Time: \(timeSeconds), Rate: \(playerRate), Status: \(itemStatus.description)")
        }
        
        let hasNewBuffer = videoOutput.hasNewPixelBuffer(forItemTime: time)
        
        if hasNewBuffer {
            print("✅ VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): HAS NEW PIXEL BUFFER at \(timeSeconds)")
            
            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                print("✅ VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): GOT PIXEL BUFFER")
                
                // Check pixel buffer properties
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                print("✅ VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): Pixel buffer size: \(width)x\(height)")
                
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let context = CIContext()
                
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    print("✅ VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): CREATED CGIMAGE")
                    let targetSize = ciImage.extent.size
                    if let processor = self.frameProcessor {
                        processingQueue.async { [weak self] in
                            guard let self = self else { return }
                            let processed = processor(cgImage) ?? cgImage
                            DispatchQueue.main.async {
                                self.currentFrame = NSImage(cgImage: processed, size: targetSize)
                            }
                        }
                    } else {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.currentFrame = NSImage(cgImage: cgImage, size: targetSize)
                        }
                    }
                } else {
                    print("❌ VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): FAILED TO CREATE CGIMAGE from CIImage")
                }
            } else {
                print("❌ VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): FAILED TO COPY PIXEL BUFFER")
            }
        } else {
            // Check if the issue is that we never have new buffers
            let currentTime = CACurrentMediaTime()
            if currentTime - lastNoBufferLogTime > 2.0 { // Log every 2 seconds
                print("🤔 VideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): NO NEW PIXEL BUFFER - Player rate: \(playerRate), Item status: \(itemStatus.description), Time: \(timeSeconds)")
                lastNoBufferLogTime = currentTime
            }
        }
    }
    
    deinit {
        print("🗑️ VideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")) is being deinitialized.")
        statusObserver?.invalidate()
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
            print("🗑️ Display link stopped for VideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM"))")
        }
        playerItemObserver?.cancel()
        print("🗑️ VideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")) deinitialized.")
    }
}

struct FrameBasedVideoPlayerView: View {
    let player: AVPlayer
    let isPreview: Bool
    let frameProcessor: ((CGImage) -> CGImage?)?
    @StateObject private var frameObserver: VideoFrameObserver
    
    init(player: AVPlayer, isPreview: Bool = false, frameProcessor: ((CGImage) -> CGImage?)? = nil) {
        self.player = player
        self.isPreview = isPreview
        self.frameProcessor = frameProcessor
        _frameObserver = StateObject(wrappedValue: VideoFrameObserver(player: player, isPreview: isPreview, frameProcessor: frameProcessor))
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
                            Text("Loading \(isPreview ? "Preview" : "Program") Media...")
                                .font(.caption)
                                .foregroundColor(.white)
                            if let currentItem = player.currentItem {
                                Text("Status: \(currentItem.status.description)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                
                                // Show current time for debugging
                                Text("Time: \(formatTime(CMTimeGetSeconds(currentItem.currentTime())))")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                
                                // Show more debug info for stuck status
                                if currentItem.status == .unknown {
                                    Text("Outputs: \(currentItem.outputs.count)")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    
                                    Text("Asset: \(currentItem.asset.description)")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .lineLimit(1)
                                }
                            }
                        }
                    )
            }
        }
        .onAppear {
            print("🎬 FrameBasedVideoPlayerView (\(isPreview ? "PREVIEW" : "PROGRAM")): View appeared")
            // Let PreviewProgramManager control playback timing
        }
        .background(Color.black)
        .clipped()
        .id("frame-video-player-\(isPreview ? "preview" : "program")-\(player.description)")
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
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