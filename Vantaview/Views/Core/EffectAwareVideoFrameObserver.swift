import SwiftUI
import AVKit
import Combine
import CoreVideo
import Metal

@MainActor
class EffectAwareVideoFrameObserver: ObservableObject {
    @Published var processedFrame: NSImage?
    
    private var player: AVPlayer
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CVDisplayLink?
    private var playerItemObserver: AnyCancellable?
    private var statusObserver: NSKeyValueObservation?
    private let observerId = UUID()
    private let isPreview: Bool
    private var hasVideoOutput = false
    private var lastNoBufferLogTime: TimeInterval = 0
    
    // Make callbackCount nonisolated so it can be accessed from display link callback
    private nonisolated(unsafe) var callbackCount = 0
    
    // Effect processing
    private weak var productionManager: UnifiedProductionManager?
    private var lastProcessedEffectCount: Int = 0
    private var rawFrame: NSImage?

    init(player: AVPlayer, productionManager: UnifiedProductionManager, isPreview: Bool = false) {
        self.player = player
        self.productionManager = productionManager
        self.isPreview = isPreview
        print("🎬 EffectAwareVideoFrameObserver: Created with ID: \(observerId) for \(isPreview ? "PREVIEW" : "PROGRAM")")
        setupObservers()
        setupDisplayLink()
    }
    
    func effectCountChanged(_ newCount: Int) {
        print("🎨 EffectAwareVideoFrameObserver (\(isPreview ? "PREVIEW" : "PROGRAM")): Effect count changed to \(newCount)")
        // Reprocess current raw frame with new effects
        if let raw = rawFrame {
            processFrame(raw, forceReprocess: true)
        }
    }

    private func setupObservers() {
        print("🎬 EffectAwareVideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")): Setting up observers")
        
        // Observe player item changes
        playerItemObserver = player.publisher(for: \.currentItem).sink { [weak self] newItem in
            Task { @MainActor in
                guard let self = self else { return }
                print("🎬 EffectAwareVideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Player item changed to: \(newItem?.description ?? "nil")")
                self.setupVideoOutput(for: newItem)
            }
        }
        
        // Also set up immediate observation if current item exists
        if let currentItem = player.currentItem {
            setupVideoOutput(for: currentItem)
        }
    }

    private func setupVideoOutput(for item: AVPlayerItem?) {
        print("🎬 EffectAwareVideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")): Setting up video output")
        
        // Clean up previous status observer
        statusObserver?.invalidate()
        statusObserver = nil
        hasVideoOutput = false
        
        // Remove output from any previous item
        if let existingOutput = self.videoOutput {
            // Remove from all items, not just current one
            if let previousItem = player.currentItem {
                if previousItem.outputs.contains(existingOutput) {
                    previousItem.remove(existingOutput)
                    print("🎬 EffectAwareVideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): Removed existing video output from previous item")
                }
            }
            self.videoOutput = nil
        }

        guard let currentItem = item else {
            videoOutput = nil
            print("🎬 EffectAwareVideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): No current item, clearing video output")
            return
        }
        
        print("🎬 EffectAwareVideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): Setting up video output for new item")
        
        // Create video output immediately
        self.createVideoOutput(for: currentItem)
        
        // Set up status observer for debugging
        statusObserver = currentItem.observe(\.status, options: [.new, .initial]) { [weak self] item, change in
            Task { @MainActor in
                guard let self = self else { return }
                
                print("🎬 EffectAwareVideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Status changed to \(item.status.description)")
                
                switch item.status {
                case .readyToPlay:
                    print("✅ EffectAwareVideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Player item is ready")
                    
                case .failed:
                    print("❌ EffectAwareVideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Failed - \(item.error?.localizedDescription ?? "Unknown")")
                    
                case .unknown:
                    print("🤔 EffectAwareVideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Status still unknown")
                    
                @unknown default:
                    print("🆕 EffectAwareVideoFrameObserver \(self.isPreview ? "PREVIEW" : "PROGRAM"): Unknown status: \(item.status.rawValue)")
                }
            }
        }
    }
    
    private func createVideoOutput(for item: AVPlayerItem) {
        guard !hasVideoOutput else {
            print("🎬 EffectAwareVideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): Video output already exists, skipping")
            return
        }
        
        print("🎬 EffectAwareVideoFrameObserver \(isPreview ? "PREVIEW" : "PROGRAM"): Creating video output")
        
        // Use different pixel buffer attributes for preview vs program to avoid conflicts
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            "EffectAwareVideoFrameObserver" as String: "\(observerId)-\(isPreview ? "preview" : "program")"
        ] as [String : Any]
        
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        
        // Check if item already has too many outputs
        if item.outputs.count > 2 {
            print("⚠️ EffectAwareVideoFrameObserver: Player item has \(item.outputs.count) outputs, clearing some first")
            let outputsToRemove = Array(item.outputs.dropFirst())
            for existingOutput in outputsToRemove {
                item.remove(existingOutput)
            }
        }
        
        item.add(output)
        self.videoOutput = output
        self.hasVideoOutput = true
        print("✅ Effect-aware video output created and attached for \(isPreview ? "PREVIEW" : "PROGRAM")")
    }
    
    private nonisolated func setupDisplayLink() {
        print("🎬 EffectAwareVideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")): Setting up display link")
        
        // Create a CVDisplayLink
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        
        guard let displayLink = displayLink else {
            print("❌ Failed to create CVDisplayLink for effect-aware observer \(isPreview ? "PREVIEW" : "PROGRAM").")
            return
        }
        
        // Set the callback function
        let callback: CVDisplayLinkOutputCallback = { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
            if let context = displayLinkContext {
                let observer = Unmanaged<EffectAwareVideoFrameObserver>.fromOpaque(context).takeUnretainedValue()
                // Add periodic logging to verify callback is running
                observer.callbackCount += 1
                if observer.callbackCount % 60 == 0 { // Log every 60 calls (about once per second at 60fps)
                    print("🔄 Effect-aware display link callback #\(observer.callbackCount) for \(observer.isPreview ? "PREVIEW" : "PROGRAM")")
                }
                observer.frameAvailable()
            }
            return kCVReturnSuccess
        }
        
        // Pass a reference to self to the callback
        let selfAsContext = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, selfAsContext)
        
        // Start the display link
        let result = CVDisplayLinkStart(displayLink)
        if result == kCVReturnSuccess {
            print("✅ Effect-aware display link started successfully for observer \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM"))")
        } else {
            print("❌ Failed to start effect-aware display link for observer \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")): \(result)")
        }
        
        // Store the display link
        Task { @MainActor in
            self.displayLink = displayLink
        }
    }
    
    nonisolated func frameAvailable() {
        // We need to safely access main actor properties from the display link callback
        Task { @MainActor in
            guard let videoOutput = self.videoOutput else { return }
            guard let currentItem = self.player.currentItem else { return }
            
            let time = currentItem.currentTime()
            let hasNewBuffer = videoOutput.hasNewPixelBuffer(forItemTime: time)
            
            if hasNewBuffer {
                if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    let context = CIContext()
                    
                    if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                        // Store raw frame and process with effects
                        let rawNSImage = NSImage(cgImage: cgImage, size: ciImage.extent.size)
                        self.rawFrame = rawNSImage
                        self.processFrame(rawNSImage)
                    }
                }
            }
        }
    }
    
    private func processFrame(_ frame: NSImage, forceReprocess: Bool = false) {
        guard let productionManager = productionManager else {
            // No effects processing available, show raw frame
            processedFrame = frame
            return
        }
        
        // Get current effect count safely
        let currentEffectCount = isPreview ? 
            (productionManager.previewProgramManager.getPreviewEffectChain()?.effects.count ?? 0) :
            (productionManager.previewProgramManager.getProgramEffectChain()?.effects.count ?? 0)
        
        // Only reprocess if effects have changed or forced
        guard forceReprocess || currentEffectCount != lastProcessedEffectCount else {
            return
        }
        
        lastProcessedEffectCount = currentEffectCount
        
        // Convert NSImage to CGImage for processing
        guard let cgImage = frame.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            processedFrame = frame
            return
        }
        
        // Apply effects if any exist
        if currentEffectCount > 0 {
            let outputType: PreviewProgramManager.OutputType = isPreview ? .preview : .program
            if let processed = productionManager.previewProgramManager.processImageWithEffects(cgImage, for: outputType) {
                let processedNSImage = NSImage(size: NSSize(width: processed.width, height: processed.height))
                let bitmapRep = NSBitmapImageRep(cgImage: processed)
                processedNSImage.addRepresentation(bitmapRep)
                processedFrame = processedNSImage
                
                print("🎨 EffectAwareVideoFrameObserver (\(isPreview ? "PREVIEW" : "PROGRAM")): Applied \(currentEffectCount) effects to frame")
            } else {
                // Effect processing failed, use raw frame
                processedFrame = frame
            }
        } else {
            // No effects, use raw frame
            processedFrame = frame
        }
    }
    
    deinit {
        print("🗑️ EffectAwareVideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")) is being deinitialized.")
        statusObserver?.invalidate()
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
            print("🗑️ Effect-aware display link stopped for observer \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM"))")
        }
        playerItemObserver?.cancel()
        print("🗑️ EffectAwareVideoFrameObserver \(observerId) (\(isPreview ? "PREVIEW" : "PROGRAM")) deinitialized.")
    }
}