import SwiftUI
import AppKit
import AVFoundation

final class CameraFeedLayerHostView: NSView {
    private let imageLayer = CALayer()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.isOpaque = true
        layer?.addSublayer(imageLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }
    
    func setImage(_ cgImage: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = cgImage
        CATransaction.commit()
    }
}

/// High-FPS preview using AVSampleBufferDisplayLayer fed by CameraFeed.currentSampleBuffer
final class CameraFeedDisplayLayerHostView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var timebase: CMTimebase?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = bounds
        displayLayer.isOpaque = true
        
        // Configure real-time timebase so frames present at camera FPS
        var tb: CMTimebase?
        CMTimebaseCreateWithMasterClock(allocator: kCFAllocatorDefault, masterClock: CMClockGetHostTimeClock(), timebaseOut: &tb)
        if let tb {
            CMTimebaseSetRate(tb, rate: 1.0)
            displayLayer.controlTimebase = tb
            timebase = tb
        }
        
        layer?.addSublayer(displayLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
    
    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        // Ensure realtime presentation: if back-pressured, flush
        if displayLayer.isReadyForMoreMediaData {
            displayLayer.enqueue(sampleBuffer)
        } else {
            displayLayer.flush()
            displayLayer.enqueue(sampleBuffer)
        }
    }
    
    func reset() {
        displayLayer.flushAndRemoveImage()
        if let tb = timebase {
            CMTimebaseSetRate(tb, rate: 0.0)
            CMTimebaseSetRate(tb, rate: 1.0)
        }
    }
}

/// Deprecated CGImage-based view (kept for fallback/compat)
struct CameraFeedCALayerView: NSViewRepresentable {
    let feed: CameraFeed
    
    @MainActor
    func makeNSView(context: Context) -> CameraFeedLayerHostView {
        let v = CameraFeedLayerHostView()
        context.coordinator.attachCG(to: v, feed: feed)
        return v
    }
    
    func updateNSView(_ nsView: CameraFeedLayerHostView, context: Context) {
    }
    
    @MainActor
    static func dismantleNSView(_ nsView: CameraFeedLayerHostView, coordinator: Coordinator) {
        coordinator.detach()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    @MainActor
    final class Coordinator {
        private weak var cgView: CameraFeedLayerHostView?
        private weak var sbView: CameraFeedDisplayLayerHostView?
        private var cgTask: Task<Void, Never>?
        private var sbTask: Task<Void, Never>?
        
        func attachCG(to view: CameraFeedLayerHostView, feed: CameraFeed) {
            self.cgView = view
            cgTask = Task { @MainActor in
                for await cg in feed.$previewImage.values {
                    try? Task.checkCancellation()
                    self.cgView?.setImage(cg)
                }
            }
        }
        
        func attachSB(to view: CameraFeedDisplayLayerHostView, feed: CameraFeed) {
            self.sbView = view
            sbTask = Task { @MainActor in
                for await sb in feed.$currentSampleBuffer.values {
                    try? Task.checkCancellation()
                    if let sb { self.sbView?.enqueue(sb) }
                }
            }
        }
        
        func detach() {
            cgTask?.cancel()
            cgTask = nil
            sbTask?.cancel()
            sbTask = nil
            cgView?.setImage(nil)
            sbView?.reset()
            cgView = nil
            sbView = nil
        }
    }
}

/// Preferred high-FPS display view (uses AVSampleBufferDisplayLayer)
struct CameraFeedDisplayLayerView: NSViewRepresentable {
    let feed: CameraFeed
    
    @MainActor
    func makeNSView(context: Context) -> CameraFeedDisplayLayerHostView {
        let v = CameraFeedDisplayLayerHostView()
        context.coordinator.attachSB(to: v, feed: feed)
        return v
    }
    
    func updateNSView(_ nsView: CameraFeedDisplayLayerHostView, context: Context) {
    }
    
    @MainActor
    static func dismantleNSView(_ nsView: CameraFeedDisplayLayerHostView, coordinator: CameraFeedCALayerView.Coordinator) {
        coordinator.detach()
    }
    
    func makeCoordinator() -> CameraFeedCALayerView.Coordinator {
        CameraFeedCALayerView.Coordinator()
    }
}
