import Foundation
import AVFoundation
import MetalKit

protocol Effect {
    var type: String { get }
    var amount: Float { get set }

    func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer) -> MTLTexture
}

// MARK: - Licensing Support (additive only)

extension Effect {
    /// Whether this effect requires a Pro subscription
    var isPremium: Bool {
        // Define which effects are premium based on string type
        let premiumEffectTypes = [
            "colorGrading",
            "lut", 
            "chromaKey",
            "motionBlur",
            "particleSystem"
        ]
        return premiumEffectTypes.contains(self.type)
    }
    
    /// Required license tier for this effect
    var requiredTier: PlanTier {
        return isPremium ? .pro : .live
    }
}