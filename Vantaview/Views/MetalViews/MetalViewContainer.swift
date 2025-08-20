import SwiftUI
import MetalKit
import QuartzCore

struct MetalViewContainer: NSViewRepresentable {
    var isPreview: Bool
    var blurAmount: Float
    var isBlurEnabled: Bool

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        mtkView.framebufferOnly = true
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 60

        if let layer = mtkView.layer as? CAMetalLayer {
            layer.displaySyncEnabled = true
            layer.presentsWithTransaction = false
            if #available(macOS 13.0, *) {
                layer.maximumDrawableCount = 3
            }
        }

        if isPreview {
            let previewRenderer = PreviewRenderer(mtkView: mtkView, blurEnabled: isBlurEnabled, blurAmount: blurAmount)
            mtkView.delegate = previewRenderer
            context.coordinator.renderer = previewRenderer
        } else {
            let mainRenderer = MainRenderer(mtkView: mtkView, blurEnabled: isBlurEnabled, blurAmount: blurAmount)
            mtkView.delegate = mainRenderer
            context.coordinator.renderer = mainRenderer
        }

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // You can update the renderer properties here if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var renderer: Any?
    }
}