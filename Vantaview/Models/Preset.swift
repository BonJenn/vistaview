import Foundation

struct PresetEffect: Codable, Hashable {
    var type: String
    var amount: Float
    
    /// Whether this effect requires premium subscription
    var isPremium: Bool {
        // Define which effects are premium (Pro tier)
        let premiumEffects = ["colorGrading", "lut", "chromaKey", "motionBlur", "particleSystem"]
        return premiumEffects.contains(type)
    }
    
    /// Required license tier for this effect
    var requiredTier: PlanTier {
        return isPremium ? .pro : .live
    }
}

struct Preset: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var effects: [PresetEffect]
    var blurAmount: Float
    var isBlurEnabled: Bool
    
    /// Whether this preset contains any premium effects
    var containsPremiumEffects: Bool {
        return effects.contains { $0.isPremium }
    }
    
    /// Minimum tier required to use this preset
    var requiredTier: PlanTier {
        if containsPremiumEffects {
            return .pro
        } else if !effects.isEmpty {
            return .live
        } else {
            return .stream
        }
    }
    
    /// Filter effects based on available license tier
    func filteredEffects(for licenseManager: LicenseManager) async -> [PresetEffect] {
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                let filtered = effects.filter { effect in
                    if effect.isPremium {
                        return licenseManager.isEnabled(.fxPremium)
                    } else {
                        return licenseManager.isEnabled(.effectsBasic)
                    }
                }
                continuation.resume(returning: filtered)
            }
        }
    }
    
    /// Create a version of this preset with only accessible effects
    func filtered(for licenseManager: LicenseManager) async -> Preset {
        let filteredEffects = await filteredEffects(for: licenseManager)
        return Preset(
            id: id,
            name: name,
            effects: filteredEffects,
            blurAmount: blurAmount,
            isBlurEnabled: isBlurEnabled
        )
    }
}

// MARK: - Effect Types

extension PresetEffect {
    /// Common effect types
    enum EffectType {
        // Basic effects (Live tier)
        static let blur = "blur"
        static let brightness = "brightness"
        static let contrast = "contrast"
        static let saturation = "saturation"
        static let hue = "hue"
        
        // Premium effects (Pro tier)
        static let colorGrading = "colorGrading"
        static let lut = "lut"
        static let chromaKey = "chromaKey"
        static let motionBlur = "motionBlur"
        static let particleSystem = "particleSystem"
    }
    
    /// Display name for the effect
    var displayName: String {
        switch type {
        case EffectType.blur: return "Blur"
        case EffectType.brightness: return "Brightness"
        case EffectType.contrast: return "Contrast"
        case EffectType.saturation: return "Saturation"
        case EffectType.hue: return "Hue"
        case EffectType.colorGrading: return "Color Grading"
        case EffectType.lut: return "LUT"
        case EffectType.chromaKey: return "Chroma Key"
        case EffectType.motionBlur: return "Motion Blur"
        case EffectType.particleSystem: return "Particle System"
        default: return type.capitalized
        }
    }
}