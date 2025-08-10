import Foundation
import Metal

final class EffectRunner {
    private let device: MTLDevice
    private var chain: EffectChain?
    
    init(device: MTLDevice, chain: EffectChain? = nil) {
        self.device = device
        self.chain = chain
    }
    
    func setChain(_ chain: EffectChain?) {
        self.chain = chain
    }
    
    func encodeEffects(input: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let chain = chain else { return input }
        return chain.apply(to: input, using: commandBuffer, device: device) ?? input
    }
}