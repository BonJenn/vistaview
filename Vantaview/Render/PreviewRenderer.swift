import Foundation
import MetalKit

class PreviewRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var blurEnabled: Bool
    private var blurAmount: Float

    private var heartbeatBuffer: MTLBuffer?

    init?(mtkView: MTKView, blurEnabled: Bool, blurAmount: Float) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            print("❌ Failed to create Metal device or command queue")
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.blurEnabled = blurEnabled
        self.blurAmount = blurAmount

        super.init()
        mtkView.device = device
        heartbeatBuffer = device.makeBuffer(length: 4, options: .storageModeShared)
        setupPipeline(mtkView: mtkView)
    }

    func updateBlur(blurEnabled: Bool, blurAmount: Float) {
        self.blurEnabled = blurEnabled
        self.blurAmount = blurAmount
    }

    private func setupPipeline(mtkView: MTKView) {
        let library = device.makeDefaultLibrary()
        guard let vertexFunc = library?.makeFunction(name: "vertexShader"),
              let fragmentFunc = library?.makeFunction(name: "fragmentShader") else {
            print("❌ Failed to load shaders")
            return
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunc
        pipelineDescriptor.fragmentFunction = fragmentFunc
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("❌ Failed to create pipeline state: \(error.localizedDescription)")
        }
    }

    func draw(in view: MTKView) {
        let capturing = MTLCaptureManager.shared().isCapturing

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            if capturing, let hb = heartbeatBuffer, let cb = commandQueue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
                cb.label = "PreviewRenderer_NoCB"
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

        guard let pipelineState = pipelineState else {
            if capturing, let hb = heartbeatBuffer, let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.fill(buffer: hb, range: 0..<4, value: 0)
                blit.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
            return
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            if capturing, let hb = heartbeatBuffer, let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.fill(buffer: hb, range: 0..<4, value: 0)
                blit.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
            return
        }

        encoder.setRenderPipelineState(pipelineState)

        // Insert your vertex/index buffer setup here if needed

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Optional: handle resizing
    }
}