import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
    let blurEnabled: Bool
    let blurAmount: Float

    func makeCoordinator() -> Renderer {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        return Renderer(mtkView: mtkView, blurEnabled: blurEnabled, blurAmount: blurAmount)
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.delegate = context.coordinator
        mtkView.framebufferOnly = false
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.blurEnabled = blurEnabled
        context.coordinator.blurAmount = blurAmount
    }
}
