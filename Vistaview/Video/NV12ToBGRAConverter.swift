import Foundation
import Metal
import MetalKit
import CoreVideo

struct ConvertParams {
    var yuv2rgb: simd_float3x3
    var yOffset: Float
    var uvOffset: Float
    var yScale: Float
    var uvScale: Float
    var toneMapEnabled: Float
    var swapUV: Float
}

final class NV12ToBGRAConverter {
    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    private let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
    
    init?(device: MTLDevice) {
        self.device = device
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "nv12ToBGRA") else {
            return nil
        }
        do {
            self.pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            return nil
        }
    }
    
    func makeOutputTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderWrite, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }
    
    func makeOutputTexture(width: Int, height: Int, heap: MTLHeap?) -> MTLTexture? {
        guard let heap else { return makeOutputTexture(width: width, height: height) }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderWrite, .shaderRead]
        desc.storageMode = heap.storageMode
        return heap.makeTexture(descriptor: desc)
    }
    
    func encode(commandBuffer: MTLCommandBuffer, luma: MTLTexture, chroma: MTLTexture, output: MTLTexture, params: ConvertParams) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "NV12ToBGRAEncoder"
        encoder.pushDebugGroup("NV12→BGRA")
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(luma, index: 0)
        encoder.setTexture(chroma, index: 1)
        encoder.setTexture(output, index: 2)
        
        var p = params
        encoder.setBytes(&p, length: MemoryLayout<ConvertParams>.stride, index: 0)
        
        let w = output.width
        let h = output.height
        
        let tgCount = MTLSize(
            width: (w + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (h + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: threadgroupSize)
        encoder.popDebugGroup()
        encoder.endEncoding()
    }

    func encode(commandBuffer: MTLCommandBuffer, luma: MTLTexture, chroma: MTLTexture, output: MTLTexture) {
        // Column-major Rec.709 defaults (Full range)
        let m = simd_float3x3(
            simd_float3(1.0,  1.0,    1.0),          // Y column
            simd_float3(0.0, -0.1873, 1.8556),       // U column
            simd_float3(1.5748, -0.4681, 0.0)        // V column
        )
        let defaultParams = ConvertParams(
            yuv2rgb: m,
            yOffset: 0.0,
            uvOffset: 0.5,
            yScale: 1.0,
            uvScale: 1.0,
            toneMapEnabled: 0.0,
            swapUV: 0.0
        )
        encode(commandBuffer: commandBuffer, luma: luma, chroma: chroma, output: output, params: defaultParams)
    }
}