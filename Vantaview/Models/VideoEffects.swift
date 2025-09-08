import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders
import SwiftUI
import CoreImage
import AVFoundation
#if os(macOS)
import AppKit
#endif

// MARK: - Effect Categories

enum EffectCategory: String, CaseIterable {
    case color = "Color"
    case artistic = "Artistic" 
    case distortion = "Distortion"
    case blur = "Blur & Sharpen"
    case stylize = "Stylize"
    case transition = "Transition"
    case keying = "Keying"
    
    var icon: String {
        switch self {
        case .color: return "paintpalette"
        case .artistic: return "paintbrush"
        case .distortion: return "waveform.path"
        case .blur: return "camera.filters"
        case .stylize: return "sparkles"
        case .transition: return "arrow.left.arrow.right"
        case .keying: return "person.crop.rectangle"
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
        case .keying: return .teal
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
    
    override func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        let brightness = parameters["brightness"]?.value ?? 0.0
        let contrast = parameters["contrast"]?.value ?? 1.0
        let saturation = parameters["saturation"]?.value ?? 1.0
        let gamma = parameters["gamma"]?.value ?? 1.0
        
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
        
        // Apply color adjustments using Core Image with proper coordinate handling
        let ciImage = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        guard let inputImage = ciImage else { return texture }
        
        var processedImage = inputImage
        
        // Apply brightness, contrast, and saturation
        let colorFilter = CIFilter(name: "CIColorControls")!
        colorFilter.setValue(processedImage, forKey: "inputImage")
        colorFilter.setValue(brightness, forKey: "inputBrightness")
        colorFilter.setValue(contrast, forKey: "inputContrast")
        colorFilter.setValue(saturation, forKey: "inputSaturation")
        
        if let output = colorFilter.outputImage {
            processedImage = output
        }
        
        // Apply gamma
        if gamma != 1.0 {
            let gammaFilter = CIFilter(name: "CIGammaAdjust")!
            gammaFilter.setValue(processedImage, forKey: "inputImage")
            gammaFilter.setValue(gamma, forKey: "inputPower")
            if let output = gammaFilter.outputImage {
                processedImage = output
            }
        }
        
        // Render back to Metal texture with proper coordinate handling
        let context = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        
        // Render with correct bounds and coordinate system
        let renderBounds = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        context.render(processedImage, to: outputTexture, commandBuffer: commandBuffer, bounds: renderBounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        return outputTexture
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
    
    override func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        let sepiaIntensity = parameters["sepia"]?.value ?? 0.7
        let vignetteIntensity = parameters["vignette"]?.value ?? 0.3
        let warmth = parameters["warmth"]?.value ?? 0.1
        
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
        
        // Apply vintage effect using Core Image with proper coordinate handling
        let ciImage = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        guard let inputImage = ciImage else { return texture }
        
        var processedImage = inputImage
        
        // Apply sepia tone
        if sepiaIntensity > 0.0 {
            let sepiaFilter = CIFilter(name: "CISepiaTone")!
            sepiaFilter.setValue(processedImage, forKey: "inputImage")
            sepiaFilter.setValue(sepiaIntensity, forKey: "inputIntensity")
            if let sepiaOutput = sepiaFilter.outputImage {
                processedImage = sepiaOutput
            }
        }
        
        // Apply warmth (temperature adjustment)
        if warmth != 0.0 {
            let tempFilter = CIFilter(name: "CITemperatureAndTint")!
            tempFilter.setValue(processedImage, forKey: "inputImage")
            tempFilter.setValue(CIVector(x: CGFloat(6500 + warmth * 2000), y: 0), forKey: "inputNeutral")
            tempFilter.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
            if let tempOutput = tempFilter.outputImage {
                processedImage = tempOutput
            }
        }
        
        // Apply vignette
        if vignetteIntensity > 0.0 {
            let vignetteFilter = CIFilter(name: "CIVignette")!
            vignetteFilter.setValue(processedImage, forKey: "inputImage")
            vignetteFilter.setValue(vignetteIntensity, forKey: "inputIntensity")
            vignetteFilter.setValue(1.0, forKey: "inputRadius")
            if let vignetteOutput = vignetteFilter.outputImage {
                processedImage = vignetteOutput
            }
        }
        
        // Render back to Metal texture with proper coordinate handling
        let context = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        
        let renderBounds = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        context.render(processedImage, to: outputTexture, commandBuffer: commandBuffer, bounds: renderBounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        return outputTexture
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
    
    override func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        let intensity = parameters["intensity"]?.value ?? 1.0
        let contrast = parameters["contrast"]?.value ?? 1.1
        
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
        
        // Apply black and white effect using Core Image with proper coordinate handling
        let ciImage = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        guard let inputImage = ciImage else { return texture }
        
        var processedImage = inputImage
        
        // Convert to grayscale
        let monoFilter = CIFilter(name: "CIColorMonochrome")!
        monoFilter.setValue(processedImage, forKey: "inputImage")
        monoFilter.setValue(CIColor(red: 0.7, green: 0.7, blue: 0.7), forKey: "inputColor")
        monoFilter.setValue(intensity, forKey: "inputIntensity")
        
        if let monoOutput = monoFilter.outputImage {
            processedImage = monoOutput
            
            // Apply contrast
            if contrast != 1.0 {
                let contrastFilter = CIFilter(name: "CIColorControls")!
                contrastFilter.setValue(processedImage, forKey: "inputImage")
                contrastFilter.setValue(contrast, forKey: "inputContrast")
                if let contrastOutput = contrastFilter.outputImage {
                    processedImage = contrastOutput
                }
            }
        }
        
        // Render back to Metal texture with proper coordinate handling
        let context = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        
        let renderBounds = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        context.render(processedImage, to: outputTexture, commandBuffer: commandBuffer, bounds: renderBounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        return outputTexture
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
    
    override func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        let pixelSize = parameters["pixelSize"]?.value ?? 8.0
        
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
        
        // Apply pixelate effect using Core Image with proper coordinate handling
        let ciImage = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        guard let inputImage = ciImage else { return texture }
        
        let pixelateFilter = CIFilter(name: "CIPixellate")!
        pixelateFilter.setValue(inputImage, forKey: "inputImage")
        pixelateFilter.setValue(pixelSize, forKey: "inputScale")
        
        guard let processedImage = pixelateFilter.outputImage else { return texture }
        
        // Render back to Metal texture with proper coordinate handling
        let context = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        
        let renderBounds = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        context.render(processedImage, to: outputTexture, commandBuffer: commandBuffer, bounds: renderBounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        return outputTexture
    }
}

final class ChromaKeyEffect: BaseVideoEffect {
    private var pipelineState: MTLComputePipelineState?
    @Published var backgroundName: String?
    #if os(macOS)
    @Published var backgroundPreview: NSImage?
    #endif
    private var backgroundTexture: MTLTexture?
    private var fallbackBGTexture: MTLTexture?
    @Published var backgroundURL: URL?

    private var bgPlayer: AVPlayer?
    private var bgOutput: AVPlayerItemVideoOutput?
    private var bgEndObserver: NSObjectProtocol?
    private var ciContext: CIContext?
    private var textureCache: CVMetalTextureCache?
    @Published var bgIsPlaying: Bool = false

    @Published private var isInteractive: Bool = false
    private var interactiveDebounceWork: DispatchWorkItem?

    override init(name: String = "Chroma Key", category: EffectCategory = .keying, icon: String = "person.crop.rectangle") {
        super.init(name: name, category: category, icon: icon)
        
        parameters["keyR"] = EffectParameter(name: "Key Red", defaultValue: 0.0, range: 0.0...1.0, step: 0.01)
        parameters["keyG"] = EffectParameter(name: "Key Green", defaultValue: 1.0, range: 0.0...1.0, step: 0.01)
        parameters["keyB"] = EffectParameter(name: "Key Blue", defaultValue: 0.0, range: 0.0...1.0, step: 0.01)

        // Refined key controls
        parameters["strength"] = EffectParameter(name: "Similarity", defaultValue: 0.45, range: 0.0...1.0, step: 0.005)
        parameters["softness"] = EffectParameter(name: "Blend", defaultValue: 0.22, range: 0.0...1.0, step: 0.005)
        parameters["balance"] = EffectParameter(name: "Chroma Balance", defaultValue: 0.55, range: 0.0...1.0, step: 0.01)

        // Matte tools
        parameters["matteShift"] = EffectParameter(name: "Matte Shrink/Grow (px)", defaultValue: 0.0, range: -8.0...8.0, step: 1.0)
        parameters["edgeSoftness"] = EffectParameter(name: "Edge Feather", defaultValue: 0.28, range: 0.0...1.0, step: 0.01)
        parameters["blackClip"] = EffectParameter(name: "Black Clip", defaultValue: 0.04, range: 0.0...0.5, step: 0.005)
        parameters["whiteClip"] = EffectParameter(name: "White Clip", defaultValue: 0.97, range: 0.5...1.0, step: 0.005)

        // Spill suppression
        parameters["spillStrength"] = EffectParameter(name: "Spill Strength", defaultValue: 0.7, range: 0.0...1.0, step: 0.01)
        parameters["spillDesat"] = EffectParameter(name: "Spill Desaturation", defaultValue: 0.35, range: 0.0...1.0, step: 0.01)
        parameters["despillBias"] = EffectParameter(name: "Despill Bias", defaultValue: 0.2, range: 0.0...1.0, step: 0.01)

        // View matte
        parameters["viewMatte"] = EffectParameter(name: "View Matte", defaultValue: 0.0, range: 0.0...1.0, step: 1.0)

        // Background transform and playback
        parameters["bgScale"] = EffectParameter(name: "BG Scale", defaultValue: 1.0, range: 0.1...4.0, step: 0.01)
        parameters["bgOffsetX"] = EffectParameter(name: "BG Offset X", defaultValue: 0.0, range: -1.0...1.0, step: 0.01)
        parameters["bgOffsetY"] = EffectParameter(name: "BG Offset Y", defaultValue: 0.0, range: -1.0...1.0, step: 0.01)
        parameters["bgRotation"] = EffectParameter(name: "BG Rotation", defaultValue: 0.0, range: -180.0...180.0, step: 1.0)
        parameters["bgLoop"] = EffectParameter(name: "BG Loop", defaultValue: 1.0, range: 0.0...1.0, step: 1.0)

        // Light wrap
        parameters["lightWrap"] = EffectParameter(name: "Light Wrap", defaultValue: 0.15, range: 0.0...1.0, step: 0.01)

        parameters["bgFillMode"] = EffectParameter(name: "BG Fill Mode", defaultValue: 0.0, range: 0.0...1.0, step: 1.0)
    }
    
    private struct ChromaKeyUniforms {
        var keyR: Float, keyG: Float, keyB: Float
        var strength: Float, softness: Float, balance: Float
        var matteShift: Float, edgeSoftness: Float
        var blackClip: Float, whiteClip: Float
        var spillStrength: Float, spillDesat: Float, despillBias: Float
        var viewMatte: Float
        var width: Float, height: Float, padding: Float
        var bgScale: Float, bgOffsetX: Float, bgOffsetY: Float, bgRotationRad: Float, bgEnabled: Float
        var interactive: Float
        var lightWrap: Float
        var bgW: Float, bgH: Float
        var fillMode: Float
    }

    // Interactive tuning for smooth UI/scroll while editing
    func beginInteractive() {
        isInteractive = true
        objectWillChange.send()
    }
    func endInteractive(after delay: TimeInterval = 0.2) {
        interactiveDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.isInteractive = false
            self?.objectWillChange.send()
        }
        interactiveDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    
    private func makePipeline(device: MTLDevice) {
        if pipelineState != nil { return }
        guard let library = device.makeDefaultLibrary(), let function = library.makeFunction(name: "chromaKeyKernel") else { return }
        pipelineState = try? device.makeComputePipelineState(function: function)
    }

    private func ensureCIContext(device: MTLDevice) {
        if ciContext == nil {
            ciContext = CIContext(mtlDevice: device, options: [
                .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
                .outputColorSpace: CGColorSpaceCreateDeviceRGB()
            ])
        }
        if textureCache == nil {
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        }
    }

    private func makeFallbackBGTexture(device: MTLDevice) {
        guard fallbackBGTexture == nil else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        if let tex = device.makeTexture(descriptor: desc) {
            var px: UInt32 = 0x000000FF
            tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
            fallbackBGTexture = tex
        }
    }

    func clearBackground() {
        backgroundTexture = nil
        backgroundName = nil
        backgroundURL = nil
        #if os(macOS)
        backgroundPreview = nil
        #endif
        stopBackgroundVideo()
        objectWillChange.send()
    }

    func setBackgroundImage(_ image: CGImage, device: MTLDevice) {
        let loader = MTKTextureLoader(device: device)
        do {
            backgroundTexture = try loader.newTexture(cgImage: image, options: [
                MTKTextureLoader.Option.SRGB : false,
                MTKTextureLoader.Option.textureUsage : MTLTextureUsage.shaderRead.rawValue
            ])
            backgroundName = "Image"
            #if os(macOS)
            let rep = NSBitmapImageRep(cgImage: image)
            let ns = NSImage(size: NSSize(width: image.width, height: image.height))
            ns.addRepresentation(rep)
            backgroundPreview = ns
            #endif
            stopBackgroundVideo()
            objectWillChange.send()
        } catch { print("ChromaKeyEffect: BG image texture failed:", error) }
    }

    func setBackgroundVideo(url: URL, device: MTLDevice) {
        ensureCIContext(device: device)
        stopBackgroundVideo()

        let item = AVPlayerItem(url: url)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        output.suppressesPlayerRendering = true
        item.add(output)

        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none

        bgEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            if (self.parameters["bgLoop"]?.value ?? 1.0) >= 0.5 {
                player.seek(to: .zero)
                player.play()
                self.bgIsPlaying = true
            } else {
                self.bgIsPlaying = false
            }
        }

        bgPlayer = player
        bgOutput = output
        player.play()
        bgIsPlaying = true
        backgroundName = url.lastPathComponent

        // Create a small preview thumbnail
        let gen = AVAssetImageGenerator(asset: item.asset)
        gen.appliesPreferredTrackTransform = true
        if let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil) {
            #if os(macOS)
            let rep = NSBitmapImageRep(cgImage: cg)
            let ns = NSImage(size: NSSize(width: cg.width, height: cg.height))
            ns.addRepresentation(rep)
            backgroundPreview = ns
            #endif
        }

        objectWillChange.send()
    }

    func playBackgroundVideo() {
        bgPlayer?.play()
        bgIsPlaying = true
        objectWillChange.send()
    }

    func pauseBackgroundVideo() {
        bgPlayer?.pause()
        bgIsPlaying = false
        objectWillChange.send()
    }

    private func stopBackgroundVideo() {
        if let obs = bgEndObserver {
            NotificationCenter.default.removeObserver(obs)
            bgEndObserver = nil
        }
        bgPlayer?.pause()
        bgPlayer = nil
        bgOutput = nil
        bgIsPlaying = false
    }

    // Pull latest frame from video and upload to backgroundTexture
    private func refreshBackgroundVideoFrame(commandBuffer: MTLCommandBuffer, device: MTLDevice) {
        guard let output = bgOutput, let player = bgPlayer else { return }
        ensureCIContext(device: device)

        var atTime = player.currentTime()
        if !output.hasNewPixelBuffer(forItemTime: atTime) {
            let host = CACurrentMediaTime()
            let itemTime = output.itemTime(forHostTime: host)
            if output.hasNewPixelBuffer(forItemTime: itemTime) { atTime = itemTime } else { return }
        }
        var displayTime = CMTime.zero
        guard let pb = output.copyPixelBuffer(forItemTime: atTime, itemTimeForDisplay: &displayTime) else { return }

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)

        if backgroundTexture == nil || backgroundTexture?.width != w || backgroundTexture?.height != h {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            backgroundTexture = device.makeTexture(descriptor: desc)
        }
        guard let tex = backgroundTexture, let ctx = ciContext else { return }

        // FIX: Video frames were upside down — flip vertically before rendering
        let ciSrc = CIImage(cvPixelBuffer: pb)
        let flipped = ciSrc
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(h)))

        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.render(flipped, to: tex, commandBuffer: commandBuffer, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    func setBackground(from url: URL, device: MTLDevice) {
        backgroundURL = url
        let ext = url.pathExtension.lowercased()
        if ["mp4","mov","m4v","avi","mkv","webm","hevc","heic"].contains(ext) {
            setBackgroundVideo(url: url, device: device)
            return
        }
        #if os(macOS)
        if let img = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            setBackgroundImage(img, device: device)
            backgroundURL = url
        }
        #endif
    }
    
    override func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        makePipeline(device: device)
        makeFallbackBGTexture(device: device)
        refreshBackgroundVideoFrame(commandBuffer: commandBuffer, device: device)
        guard let pipelineState else { return texture }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else { return texture }

        var u = ChromaKeyUniforms(
            keyR: parameters["keyR"]?.value ?? 0.0,
            keyG: parameters["keyG"]?.value ?? 1.0,
            keyB: parameters["keyB"]?.value ?? 0.0,
            strength: parameters["strength"]?.value ?? 0.5,
            softness: parameters["softness"]?.value ?? 0.2,
            balance: parameters["balance"]?.value ?? 0.5,
            matteShift: parameters["matteShift"]?.value ?? 0.0,
            edgeSoftness: parameters["edgeSoftness"]?.value ?? 0.3,
            blackClip: parameters["blackClip"]?.value ?? 0.05,
            whiteClip: parameters["whiteClip"]?.value ?? 0.95,
            spillStrength: parameters["spillStrength"]?.value ?? 0.7,
            spillDesat: parameters["spillDesat"]?.value ?? 0.4,
            despillBias: parameters["despillBias"]?.value ?? 0.2,
            viewMatte: parameters["viewMatte"]?.value ?? 0.0,
            width: Float(texture.width),
            height: Float(texture.height),
            padding: 0,
            bgScale: parameters["bgScale"]?.value ?? 1.0,
            bgOffsetX: parameters["bgOffsetX"]?.value ?? 0.0,
            bgOffsetY: parameters["bgOffsetY"]?.value ?? 0.0,
            bgRotationRad: (parameters["bgRotation"]?.value ?? 0.0) * .pi / 180.0,
            bgEnabled: (backgroundTexture != nil) ? 1.0 : 0.0,
            interactive: isInteractive ? 1.0 : 0.0,
            lightWrap: parameters["lightWrap"]?.value ?? 0.0,
            bgW: Float(backgroundTexture?.width ?? 0),
            bgH: Float(backgroundTexture?.height ?? 0),
            fillMode: parameters["bgFillMode"]?.value ?? 0.0
        )

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return texture }
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setTexture(backgroundTexture ?? fallbackBGTexture, index: 2)
        var uniforms = u
        encoder.setBytes(&uniforms, length: MemoryLayout<ChromaKeyUniforms>.stride, index: 0)

        let w = pipelineState.threadExecutionWidth
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w
        encoder.dispatchThreads(MTLSize(width: texture.width, height: texture.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        encoder.endEncoding()

        return outputTexture
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
            EdgeDetectionEffect(),
            
            ChromaKeyEffect()
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
        case "Chroma Key": return ChromaKeyEffect()
        default: return nil
        }
    }
}