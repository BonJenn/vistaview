import Foundation
import Metal
import MetalKit
import CoreVideo

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
    
    func encode(commandBuffer: MTLCommandBuffer, luma: MTLTexture, chroma: MTLTexture, output: MTLTexture) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(luma, index: 0)
        encoder.setTexture(chroma, index: 1)
        encoder.setTexture(output, index: 2)
        
        let w = output.width
        let h = output.height
        
        let tgCount = MTLSize(
            width: (w + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (h + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
    }
}