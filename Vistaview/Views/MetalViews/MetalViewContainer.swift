import SwiftUI
import MetalKit

struct MetalViewContainer: NSViewRepresentable {
    var isPreview: Bool
    var blurAmount: Float
    var isBlurEnabled: Bool

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        mtkView.framebufferOnly = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true

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
