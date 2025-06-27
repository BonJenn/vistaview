import SwiftUI
import MetalKit

struct MetalViewContainer: NSViewRepresentable {
    var blurEnabled: Bool
    var blurAmount: Float

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColorMake(0, 0, 0, 1)
        mtkView.framebufferOnly = false

        if let device = mtkView.device {
            let renderer = Renderer(mtkView: mtkView, blurEnabled: blurEnabled, blurAmount: blurAmount)
            mtkView.delegate = renderer
            context.coordinator.renderer = renderer
        }

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.blurEnabled = blurEnabled
        context.coordinator.renderer?.blurAmount = blurAmount
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    class Coordinator {
        var renderer: Renderer?
    }
}
