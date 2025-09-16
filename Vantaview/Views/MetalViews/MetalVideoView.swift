import SwiftUI
import MetalKit
import QuartzCore
import Metal

struct MetalVideoView: NSViewRepresentable {
    let textureSupplier: () -> MTLTexture?
    var preferredFPS: Int = 60
    var device: MTLDevice? = nil
    
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        if let device {
            view.device = device
        } else {
            view.device = MTLCreateSystemDefaultDevice()
        }
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = preferredFPS
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        if let layer = view.layer as? CAMetalLayer {
            layer.displaySyncEnabled = true
            layer.presentsWithTransaction = false
            if #available(macOS 13.0, *) {
                layer.maximumDrawableCount = 3
            }
        }
        if let renderer = MetalTextureRenderer(mtkView: view, textureSupplier: textureSupplier) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }
        return view
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        if let renderer = context.coordinator.renderer {
            renderer.setTextureSupplier(textureSupplier)
        }
        if let device, nsView.device?.registryID != device.registryID {
            nsView.device = device
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var renderer: MetalTextureRenderer? }
}