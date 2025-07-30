import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders
import SwiftUI

// MARK: - Effect Categories

enum EffectCategory: String, CaseIterable {
    case color = "Color"
    case artistic = "Artistic" 
    case distortion = "Distortion"
    case blur = "Blur & Sharpen"
    case stylize = "Stylize"
    case transition = "Transition"
    
    var icon: String {
        switch self {
        case .color: return "paintpalette"
        case .artistic: return "paintbrush"
        case .distortion: return "waveform.path"
        case .blur: return "camera.filters"
        case .stylize: return "sparkles"
        case .transition: return "arrow.left.arrow.right"
        }
    }
    
    var color: Color {
        switch self {
        case .color: return .orange
        case .artistic: return .purple
        case .distortion: return .blue
        case .blur: return .green
        case .stylize: return .pink
        case .transition: return .indigo
        }
    }
}

// MARK: - Effect Parameter

struct EffectParameter {
    var name: String
    var value: Float
    var range: ClosedRange<Float>
    var defaultValue: Float
    var step: Float
    
    init(name: String, defaultValue: Float, range: ClosedRange<Float>, step: Float = 0.01) {
        self.name = name
        self.defaultValue = defaultValue
        self.value = defaultValue
        self.range = range
        self.step = step
    }
}

// MARK: - Video Effect Protocol

protocol VideoEffect: ObservableObject, Identifiable {
    var id: UUID { get }
    var name: String { get }
    var category: EffectCategory { get }
    var icon: String { get }
    var isEnabled: Bool { get set }
    var parameters: [String: EffectParameter] { get set }
    
    func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture?
    func reset()
}

// MARK: - Base Effect Class

class BaseVideoEffect: VideoEffect, ObservableObject {
    let id = UUID()
    @Published var name: String
    @Published var category: EffectCategory
    @Published var icon: String
    @Published var isEnabled: Bool = true
    @Published var parameters: [String: EffectParameter] = [:]
    
    init(name: String, category: EffectCategory, icon: String) {
        self.name = name
        self.category = category
        self.icon = icon
    }
    
    func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        // Override in subclasses
        return texture
    }
    
    func reset() {
        for (key, parameter) in parameters {
            parameters[key]?.value = parameter.defaultValue
        }
        objectWillChange.send()
    }
}

// MARK: - Blur Effect

class BlurEffect: BaseVideoEffect {
    override init(name: String = "Gaussian Blur", category: EffectCategory = .blur, icon: String = "camera.filters") {
        super.init(name: name, category: category, icon: icon)
        
        parameters["radius"] = EffectParameter(
            name: "Blur Radius",
            defaultValue: 5.0,
            range: 0.0...50.0,
            step: 0.5
        )
        
        parameters["iterations"] = EffectParameter(
            name: "Quality",
            defaultValue: 3.0,
            range: 1.0...5.0,
            step: 1.0
        )
    }
    
    override func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        let radius = parameters["radius"]?.value ?? 5.0
        guard radius > 0 else { return texture }
        
        // Create blur filter using Metal Performance Shaders
        let blur = MPSImageGaussianBlur(device: device, sigma: radius)
        
        // Create output texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            return texture
        }
        
        blur.encode(commandBuffer: commandBuffer, sourceTexture: texture, destinationTexture: outputTexture)
        
        return outputTexture
    }
}

// MARK: - Sharpen Effect

class SharpenEffect: BaseVideoEffect {
    override init(name: String = "Unsharp Mask", category: EffectCategory = .blur, icon: String = "camera.macro") {
        super.init(name: name, category: category, icon: icon)
        
        parameters["intensity"] = EffectParameter(
            name: "Intensity",
            defaultValue: 0.5,
            range: 0.0...2.0
        )
        
        parameters["radius"] = EffectParameter(
            name: "Radius",
            defaultValue: 2.0,
            range: 0.1...10.0
        )
    }
    
    override func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        let intensity = parameters["intensity"]?.value ?? 0.5
        let radius = parameters["radius"]?.value ?? 2.0
        
        guard intensity > 0 else { return texture }
        
        // Create texture descriptors
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let blurredTexture = device.makeTexture(descriptor: descriptor),
              let outputTexture = device.makeTexture(descriptor: descriptor) else {
            return texture
        }
        
        // Step 1: Create blurred version
        let blur = MPSImageGaussianBlur(device: device, sigma: radius)
        blur.encode(commandBuffer: commandBuffer, sourceTexture: texture, destinationTexture: blurredTexture)
        
        // Step 2: Use MPSImageSubtract to get the high-frequency details (original - blurred)
        let subtract = MPSImageSubtract(device: device)
        subtract.encode(commandBuffer: commandBuffer, primaryTexture: texture, secondaryTexture: blurredTexture, destinationTexture: outputTexture)
        
        // Step 3: Use MPSImageAdd to add the sharpened details back (original + intensity * details)
        // For simplicity, we'll use a convolution kernel for sharpening instead
        let sharpenKernel = createSharpenKernel(device: device, intensity: intensity)
        sharpenKernel?.encode(commandBuffer: commandBuffer, sourceTexture: texture, destinationTexture: outputTexture)
        
        return outputTexture
    }
    
    private func createSharpenKernel(device: MTLDevice, intensity: Float) -> MPSImageConvolution? {
        // Create a 3x3 sharpening kernel
        let kernelWeights: [Float] = [
            0, -intensity, 0,
            -intensity, 1 + 4 * intensity, -intensity,
            0, -intensity, 0
        ]
        
        return MPSImageConvolution(device: device, kernelWidth: 3, kernelHeight: 3, weights: kernelWeights)
    }
}

// MARK: - Color Adjustment Effect

class ColorAdjustmentEffect: BaseVideoEffect {
    override init(name: String = "Color Adjustment", category: EffectCategory = .color, icon: String = "slider.horizontal.3") {
        super.init(name: name, category: category, icon: icon)
        
        parameters["brightness"] = EffectParameter(
            name: "Brightness",
            defaultValue: 0.0,
            range: -1.0...1.0
        )
        
        parameters["contrast"] = EffectParameter(
            name: "Contrast",
            defaultValue: 1.0,
            range: 0.0...2.0
        )
        
        parameters["saturation"] = EffectParameter(
            name: "Saturation",
            defaultValue: 1.0,
            range: 0.0...2.0
        )
        
        parameters["gamma"] = EffectParameter(
            name: "Gamma",
            defaultValue: 1.0,
            range: 0.1...3.0
        )
    }
}

// MARK: - Vintage Effect

class VintageEffect: BaseVideoEffect {
    override init(name: String = "Vintage Film", category: EffectCategory = .artistic, icon: String = "camera.viewfinder") {
        super.init(name: name, category: category, icon: icon)
        
        parameters["sepia"] = EffectParameter(
            name: "Sepia Tone",
            defaultValue: 0.7,
            range: 0.0...1.0
        )
        
        parameters["vignette"] = EffectParameter(
            name: "Vignette",
            defaultValue: 0.3,
            range: 0.0...1.0
        )
        
        parameters["noise"] = EffectParameter(
            name: "Film Grain",
            defaultValue: 0.2,
            range: 0.0...1.0
        )
        
        parameters["warmth"] = EffectParameter(
            name: "Warmth",
            defaultValue: 0.1,
            range: -0.5...0.5
        )
    }
}

// MARK: - Black & White Effect

class BlackWhiteEffect: BaseVideoEffect {
    override init(name: String = "Black & White", category: EffectCategory = .color, icon: String = "circle.lefthalf.filled") {
        super.init(name: name, category: category, icon: icon)
        
        parameters["intensity"] = EffectParameter(
            name: "Intensity",
            defaultValue: 1.0,
            range: 0.0...1.0
        )
        
        parameters["contrast"] = EffectParameter(
            name: "Contrast",
            defaultValue: 1.1,
            range: 0.5...2.0
        )
        
        parameters["redWeight"] = EffectParameter(
            name: "Red Channel",
            defaultValue: 0.299,
            range: 0.0...1.0
        )
        
        parameters["greenWeight"] = EffectParameter(
            name: "Green Channel",
            defaultValue: 0.587,
            range: 0.0...1.0
        )
        
        parameters["blueWeight"] = EffectParameter(
            name: "Blue Channel",
            defaultValue: 0.114,
            range: 0.0...1.0
        )
    }
}

// MARK: - Chromatic Aberration Effect

class ChromaticAberrationEffect: BaseVideoEffect {
    override init(name: String = "Chromatic Aberration", category: EffectCategory = .distortion, icon: String = "rays") {
        super.init(name: name, category: category, icon: icon)
        
        parameters["strength"] = EffectParameter(
            name: "Strength",
            defaultValue: 2.0,
            range: 0.0...10.0
        )
        
        parameters["centerX"] = EffectParameter(
            name: "Center X",
            defaultValue: 0.5,
            range: 0.0...1.0
        )
        
        parameters["centerY"] = EffectParameter(
            name: "Center Y",
            defaultValue: 0.5,
            range: 0.0...1.0
        )
    }
}

// MARK: - Glitch Effect

class GlitchEffect: BaseVideoEffect {
    override init(name: String = "Digital Glitch", category: EffectCategory = .stylize, icon: String = "waveform.path.ecg") {
        super.init(name: name, category: category, icon: icon)
        
        parameters["intensity"] = EffectParameter(
            name: "Intensity",
            defaultValue: 0.3,
            range: 0.0...1.0
        )
        
        parameters["speed"] = EffectParameter(
            name: "Speed",
            defaultValue: 5.0,
            range: 0.1...20.0
        )
        
        parameters["blockSize"] = EffectParameter(
            name: "Block Size",
            defaultValue: 0.1,
            range: 0.01...0.5
        )
        
        parameters["colorShift"] = EffectParameter(
            name: "Color Shift",
            defaultValue: 0.2,
            range: 0.0...1.0
        )
    }
}

// MARK: - Edge Detection Effect

class EdgeDetectionEffect: BaseVideoEffect {
    override init(name: String = "Edge Detection", category: EffectCategory = .stylize, icon: String = "square.dashed") {
        super.init(name: name, category: category, icon: icon)
        
        parameters["threshold"] = EffectParameter(
            name: "Threshold",
            defaultValue: 0.1,
            range: 0.0...1.0
        )
        
        parameters["thickness"] = EffectParameter(
            name: "Line Thickness",
            defaultValue: 1.0,
            range: 0.5...5.0
        )
    }
}

// MARK: - Pixelate Effect

class PixelateEffect: BaseVideoEffect {
    override init(name: String = "Pixelate", category: EffectCategory = .distortion, icon: String = "squareshape.split.3x3") {
        super.init(name: name, category: category, icon: icon)
        
        parameters["pixelSize"] = EffectParameter(
            name: "Pixel Size",
            defaultValue: 8.0,
            range: 2.0...50.0,
            step: 1.0
        )
    }
}

// MARK: - Effects Library

class EffectsLibrary: ObservableObject {
    @Published var availableEffects: [any VideoEffect] = []
    
    init() {
        loadEffects()
    }
    
    private func loadEffects() {
        availableEffects = [
            // Blur & Sharpen
            BlurEffect(),
            SharpenEffect(),
            
            // Color
            ColorAdjustmentEffect(),
            BlackWhiteEffect(),
            
            // Artistic
            VintageEffect(),
            
            // Distortion
            ChromaticAberrationEffect(),
            PixelateEffect(),
            
            // Stylize
            GlitchEffect(),
            EdgeDetectionEffect()
        ]
    }
    
    func effects(for category: EffectCategory) -> [any VideoEffect] {
        return availableEffects.filter { $0.category == category }
    }
    
    func createEffect(ofType type: String) -> (any VideoEffect)? {
        switch type {
        case "Gaussian Blur": return BlurEffect()
        case "Unsharp Mask": return SharpenEffect()
        case "Color Adjustment": return ColorAdjustmentEffect()
        case "Vintage Film": return VintageEffect()
        case "Black & White": return BlackWhiteEffect()
        case "Chromatic Aberration": return ChromaticAberrationEffect()
        case "Digital Glitch": return GlitchEffect()
        case "Edge Detection": return EdgeDetectionEffect()
        case "Pixelate": return PixelateEffect()
        default: return nil
        }
    }
}