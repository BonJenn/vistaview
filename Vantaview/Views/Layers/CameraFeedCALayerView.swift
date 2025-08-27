import SwiftUI
import Combine
import AppKit

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

struct CameraFeedCALayerView: NSViewRepresentable {
    let feed: CameraFeed
    
    @MainActor
    func makeNSView(context: Context) -> CameraFeedLayerHostView {
        let v = CameraFeedLayerHostView()
        context.coordinator.attach(to: v, feed: feed)
        return v
    }
    
    func updateNSView(_ nsView: CameraFeedLayerHostView, context: Context) {
        // No-op; Coordinator drives updates via Combine
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
        private var cancellable: AnyCancellable?
        private weak var view: CameraFeedLayerHostView?
        
        func attach(to view: CameraFeedLayerHostView, feed: CameraFeed) {
            self.view = view
            cancellable = feed.$previewImage
                .compactMap { $0 }
                .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] cg in
                    self?.view?.setImage(cg)
                }
        }
        
        func detach() {
            cancellable?.cancel()
            cancellable = nil
            view?.setImage(nil)
            view = nil
        }
    }
}