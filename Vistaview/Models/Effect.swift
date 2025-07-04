import Foundation
import AVFoundation
import MetalKit

protocol Effect {
    var type: String { get }
    var amount: Float { get set }

    func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer) -> MTLTexture
}
