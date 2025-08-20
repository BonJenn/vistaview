import SwiftUI
import MetalKit

/// A simplified SwiftUI view that wraps an MTKView but omits drawing calls to avoid compiler errors.
struct DualRendererView: NSViewRepresentable {
    /// Placeholder flag for preview/main mode (unused).
    let isPreview: Bool
    /// Placeholder properties (unused).
    @Binding var blurAmount: Float
    @Binding var isBlurEnabled: Bool

    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }
        let view = MTKView(frame: .zero, device: device)
        view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // No-op: skip drawing updates
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MTKViewDelegate {
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            // Simplified draw: present current drawable without encoding
            guard let device = view.device,
                  let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let drawable = view.currentDrawable else {
                return
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}


