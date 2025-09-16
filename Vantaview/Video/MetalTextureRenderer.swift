import Foundation
import Metal
import MetalKit
import QuartzCore

final class MetalTextureRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let inFlight = DispatchSemaphore(value: 3)

    private struct ScaleUniforms {
        var scale: SIMD2<Float>
    }

    private var textureSupplier: () -> MTLTexture?

    init?(mtkView: MTKView, textureSupplier: @escaping () -> MTLTexture?) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let v = library.makeFunction(name: "textured_vertex_scaled"),
              let f = library.makeFunction(name: "textured_fragment") else {
            return nil
        }
        self.device = device
        self.commandQueue = queue
        self.textureSupplier = textureSupplier

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = v
        desc.fragmentFunction = f
        desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            return nil
        }

        let sampDesc = MTLSamplerDescriptor()
        sampDesc.minFilter = .linear
        sampDesc.magFilter = .linear
        sampDesc.sAddressMode = .clampToEdge
        sampDesc.tAddressMode = .clampToEdge
        self.sampler = device.makeSamplerState(descriptor: sampDesc)!

        super.init()
    }

    func setTextureSupplier(_ supplier: @escaping () -> MTLTexture?) {
        self.textureSupplier = supplier
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }

        inFlight.wait()
        cb.addCompletedHandler { [weak self] _ in self?.inFlight.signal() }

        enc.setRenderPipelineState(pipeline)

        if let tex = textureSupplier() {
            enc.setFragmentTexture(tex, index: 0)

            let vw = max(1.0, view.drawableSize.width)
            let vh = max(1.0, view.drawableSize.height)
            let tw = max(1, tex.width)
            let th = max(1, tex.height)
            let viewAspect = vw / vh
            let texAspect = Double(tw) / Double(th)
            var sx: Float = 1.0
            var sy: Float = 1.0
            if viewAspect > texAspect {
                sx = Float(texAspect / viewAspect)
                sy = 1.0
            } else {
                sx = 1.0
                sy = Float(viewAspect / texAspect)
            }
            var uniforms = ScaleUniforms(scale: SIMD2<Float>(sx, sy))
            enc.setVertexBytes(&uniforms, length: MemoryLayout<ScaleUniforms>.size, index: 0)
        } else {
            var uniforms = ScaleUniforms(scale: SIMD2<Float>(1, 1))
            enc.setVertexBytes(&uniforms, length: MemoryLayout<ScaleUniforms>.size, index: 0)
        }

        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}