import Foundation
import MetalKit

class MainRenderer: NSObject, MTKViewDelegate {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var blurAmount: Float = 0.0
    var blurEnabled: Bool = false

    private var heartbeatBuffer: MTLBuffer?

    init(mtkView: MTKView, blurEnabled: Bool, blurAmount: Float) {
        super.init()
        self.device = mtkView.device
        self.commandQueue = device.makeCommandQueue()
        self.blurEnabled = blurEnabled
        self.blurAmount = blurAmount
        self.heartbeatBuffer = device.makeBuffer(length: 4, options: .storageModeShared)
    }

    func updateBlur(blurEnabled: Bool, blurAmount: Float) {
        self.blurEnabled = blurEnabled
        self.blurAmount = blurAmount
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }

    func draw(in view: MTKView) {
        let capturing = MTLCaptureManager.shared().isCapturing

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            if capturing, let hb = heartbeatBuffer, let cb = commandQueue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
                cb.label = "MainRenderer_NoCB"
                blit.fill(buffer: hb, range: 0..<4, value: 0)
                blit.endEncoding()
                cb.commit()
            }
            return
        }

        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else {
            if capturing, let hb = heartbeatBuffer, let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.fill(buffer: hb, range: 0..<4, value: 0)
                blit.endEncoding()
                commandBuffer.commit()
            }
            return
        }

        guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            if capturing, let hb = heartbeatBuffer, let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.fill(buffer: hb, range: 0..<4, value: 0)
                blit.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
            return
        }

        commandEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}