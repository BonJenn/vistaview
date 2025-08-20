import Foundation
import MetalKit

class MainRenderer: NSObject, MTKViewDelegate {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var blurAmount: Float = 0.0
    var blurEnabled: Bool = false

    init(mtkView: MTKView, blurEnabled: Bool, blurAmount: Float) {
        super.init()
        self.device = mtkView.device
        self.commandQueue = device.makeCommandQueue()
        self.blurEnabled = blurEnabled
        self.blurAmount = blurAmount
    }

    func updateBlur(blurEnabled: Bool, blurAmount: Float) {
        self.blurEnabled = blurEnabled
        self.blurAmount = blurAmount
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        commandEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
