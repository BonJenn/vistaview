import Foundation
import Metal
import MetalKit
import Combine
import SwiftUI

// MARK: - Effect Chain

class EffectChain: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var effects: [any VideoEffect] = []
    @Published var isEnabled: Bool = true
    @Published var opacity: Float = 1.0
    
    private var cancellables = Set<AnyCancellable>()
    
    init(name: String) {
        self.name = name
    }
    
    // MARK: - Codable Support
    enum CodingKeys: String, CodingKey {
        case id, name, effectTypes, isEnabled, opacity
    }
    
    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        
        self.init(name: name)
        
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.opacity = try container.decode(Float.self, forKey: .opacity)
        
        // Recreate effects from types
        let effectTypes = try container.decode([String].self, forKey: .effectTypes)
        let effectsLibrary = EffectsLibrary()
        for effectType in effectTypes {
            if let effect = effectsLibrary.createEffect(ofType: effectType) {
                self.addEffect(effect)
            }
        }
    }
    
    func addEffect(_ effect: any VideoEffect) {
        effects.append(effect)
        
        // Subscribe to effect changes to trigger chain updates
        (effect as! BaseVideoEffect).objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        objectWillChange.send()
    }
    
    func removeEffect(at index: Int) {
        guard index < effects.count else { return }
        effects.remove(at: index)
        objectWillChange.send()
    }
    
    func moveEffect(from: IndexSet, to: Int) {
        effects.move(fromOffsets: from, toOffset: to)
        objectWillChange.send()
    }
    
    func apply(to texture: MTLTexture, using commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        var currentTexture = texture
        
        for effect in effects where effect.isEnabled {
            if let processedTexture = effect.apply(to: currentTexture, using: commandBuffer, device: device) {
                currentTexture = processedTexture
            }
        }
        
        return currentTexture
    }
    
    func duplicate() -> EffectChain {
        let newChain = EffectChain(name: "\(name) Copy")
        newChain.isEnabled = isEnabled
        newChain.opacity = opacity
        
        // Duplicate all effects
        for effect in effects {
            if let duplicatedEffect = duplicateEffect(effect) {
                newChain.addEffect(duplicatedEffect)
            }
        }
        
        return newChain
    }
    
    private func duplicateEffect(_ effect: any VideoEffect) -> (any VideoEffect)? {
        // Create new instance of the same effect type
        let effectType = String(describing: type(of: effect))
        
        switch effectType {
        case "BlurEffect":
            let newEffect = BlurEffect()
            copyParameters(from: effect, to: newEffect)
            return newEffect
        case "SharpenEffect":
            let newEffect = SharpenEffect()
            copyParameters(from: effect, to: newEffect)
            return newEffect
        case "ColorAdjustmentEffect":
            let newEffect = ColorAdjustmentEffect()
            copyParameters(from: effect, to: newEffect)
            return newEffect
        case "VintageEffect":
            let newEffect = VintageEffect()
            copyParameters(from: effect, to: newEffect)
            return newEffect
        case "BlackWhiteEffect":
            let newEffect = BlackWhiteEffect()
            copyParameters(from: effect, to: newEffect)
            return newEffect
        case "ChromaticAberrationEffect":
            let newEffect = ChromaticAberrationEffect()
            copyParameters(from: effect, to: newEffect)
            return newEffect
        case "GlitchEffect":
            let newEffect = GlitchEffect()
            copyParameters(from: effect, to: newEffect)
            return newEffect
        case "EdgeDetectionEffect":
            let newEffect = EdgeDetectionEffect()
            copyParameters(from: effect, to: newEffect)
            return newEffect
        case "PixelateEffect":
            let newEffect = PixelateEffect()
            copyParameters(from: effect, to: newEffect)
            return newEffect
        default:
            return nil
        }
    }
    
    private func copyParameters(from source: any VideoEffect, to destination: any VideoEffect) {
        var dest = destination as! BaseVideoEffect
        for (key, parameter) in source.parameters {
            dest.parameters[key]?.value = parameter.value
        }
        dest.isEnabled = source.isEnabled
    }
}

// MARK: - Codable Conformance for EffectChain

extension EffectChain: Codable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(opacity, forKey: .opacity)
        
        // Encode effect types for reconstruction
        let effectTypes = effects.map { String(describing: type(of: $0)) }
        try container.encode(effectTypes, forKey: .effectTypes)
    }
}

// MARK: - Transferable Conformance for EffectChain

extension EffectChain: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: EffectChain.self, contentType: .data)
    }
}

// MARK: - Effect Manager

@MainActor
class EffectManager: ObservableObject {
    @Published var effectsLibrary = EffectsLibrary()
    @Published var effectChains: [String: EffectChain] = [:] // keyed by source ID
    @Published var selectedChain: EffectChain?
    @Published var presetChains: [EffectChain] = []
    
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    // Special source IDs for preview/program outputs
    static let previewSourceID = "preview_output"
    static let programSourceID = "program_output"
    
    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Could not create Metal device and command queue")
        }
        
        self.metalDevice = device
        self.commandQueue = queue
        
        loadPresetChains()
        setupPreviewProgramChains()
    }
    
    // MARK: - Preview/Program Setup
    
    private func setupPreviewProgramChains() {
        // Create default empty chains for preview and program
        let previewChain = EffectChain(name: "Preview Effects")
        let programChain = EffectChain(name: "Program Effects")
        
        effectChains[Self.previewSourceID] = previewChain
        effectChains[Self.programSourceID] = programChain
        
        print("✨ Created default effect chains for Preview and Program outputs")
    }
    
    // MARK: - Preview/Program Convenience Methods
    
    func getPreviewEffectChain() -> EffectChain? {
        return effectChains[Self.previewSourceID]
    }
    
    func getProgramEffectChain() -> EffectChain? {
        return effectChains[Self.programSourceID]
    }
    
    func addEffectToPreview(_ effectType: String) {
        addEffectToChain(effectType, to: Self.previewSourceID)
        print("✨ Added \(effectType) effect to Preview output")
    }
    
    func addEffectToProgram(_ effectType: String) {
        addEffectToChain(effectType, to: Self.programSourceID)
        print("✨ Added \(effectType) effect to Program output")
    }
    
    func addEffectToPreview(_ effect: any VideoEffect) {
        addEffectToChain(effect, to: Self.previewSourceID)
        print("✨ Added \(effect.name) effect to Preview output")
    }
    
    func addEffectToProgram(_ effect: any VideoEffect) {
        addEffectToChain(effect, to: Self.programSourceID)
        print("✨ Added \(effect.name) effect to Program output")
    }
    
    func clearPreviewEffects() {
        effectChains[Self.previewSourceID]?.effects.removeAll()
        effectChains[Self.previewSourceID]?.objectWillChange.send()
        print("🧹 Cleared all Preview effects")
    }
    
    func clearProgramEffects() {
        effectChains[Self.programSourceID]?.effects.removeAll()
        effectChains[Self.programSourceID]?.objectWillChange.send()
        print("🧹 Cleared all Program effects")
    }
    
    func applyPreviewEffects(to texture: MTLTexture) -> MTLTexture? {
        return applyEffects(to: texture, for: Self.previewSourceID)
    }
    
    func applyProgramEffects(to texture: MTLTexture) -> MTLTexture? {
        return applyEffects(to: texture, for: Self.programSourceID)
    }
    
    // MARK: - Effect Chain Management
    
    func createEffectChain(for sourceID: String, name: String) -> EffectChain {
        let chain = EffectChain(name: name)
        effectChains[sourceID] = chain
        return chain
    }
    
    func getEffectChain(for sourceID: String) -> EffectChain? {
        return effectChains[sourceID]
    }
    
    func removeEffectChain(for sourceID: String) {
        effectChains.removeValue(forKey: sourceID)
        if selectedChain?.id == effectChains[sourceID]?.id {
            selectedChain = nil
        }
    }
    
    func duplicateChain(_ chain: EffectChain) -> EffectChain {
        let newChain = chain.duplicate()
        presetChains.append(newChain)
        return newChain
    }
    
    // MARK: - Effect Application
    
    func applyEffects(to texture: MTLTexture, for sourceID: String) -> MTLTexture? {
        guard let chain = effectChains[sourceID],
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return texture
        }
        
        let processedTexture = chain.apply(to: texture, using: commandBuffer, device: metalDevice)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return processedTexture
    }
    
    // MARK: - Drag & Drop Support
    
    func addEffectToChain(_ effectType: String, to sourceID: String) {
        guard let effect = effectsLibrary.createEffect(ofType: effectType) else { return }
        
        let chain = effectChains[sourceID] ?? createEffectChain(for: sourceID, name: "Effects")
        chain.addEffect(effect)
        
        print("✨ Added \(effectType) effect to source \(sourceID)")
    }
    
    func addEffectToChain(_ effect: any VideoEffect, to sourceID: String) {
        let chain = effectChains[sourceID] ?? createEffectChain(for: sourceID, name: "Effects")
        chain.addEffect(effect)
        
        print("✨ Added \(effect.name) effect to source \(sourceID)")
    }
    
    // MARK: - Presets
    
    private func loadPresetChains() {
        // Create some preset effect chains
        
        // Vintage Film Look
        let vintageChain = EffectChain(name: "Vintage Film")
        vintageChain.addEffect(VintageEffect())
        let colorAdj = ColorAdjustmentEffect()
        colorAdj.parameters["contrast"]?.value = 1.2
        colorAdj.parameters["saturation"]?.value = 0.8
        vintageChain.addEffect(colorAdj)
        presetChains.append(vintageChain)
        
        // Dramatic B&W
        let bwChain = EffectChain(name: "Dramatic B&W")
        let bwEffect = BlackWhiteEffect()
        bwEffect.parameters["contrast"]?.value = 1.5
        bwChain.addEffect(bwEffect)
        presetChains.append(bwChain)
        
        // Cinematic
        let cinematicChain = EffectChain(name: "Cinematic")
        let cinColor = ColorAdjustmentEffect()
        cinColor.parameters["contrast"]?.value = 1.3
        cinColor.parameters["saturation"]?.value = 1.1
        cinColor.parameters["brightness"]?.value = -0.1
        cinematicChain.addEffect(cinColor)
        cinematicChain.addEffect(ChromaticAberrationEffect())
        presetChains.append(cinematicChain)
        
        // Glitch Art
        let glitchChain = EffectChain(name: "Glitch Art")
        glitchChain.addEffect(GlitchEffect())
        glitchChain.addEffect(ChromaticAberrationEffect())
        presetChains.append(glitchChain)
    }
    
    func applyPreset(_ preset: EffectChain, to sourceID: String) {
        let newChain = preset.duplicate()
        newChain.name = "Applied: \(preset.name)"
        effectChains[sourceID] = newChain
        selectedChain = newChain
        
        print("🎨 Applied preset '\(preset.name)' to source \(sourceID)")
    }
    
    // MARK: - Real-time Preview
    
    func generatePreviewTexture(for effect: any VideoEffect, size: CGSize = CGSize(width: 128, height: 72)) -> MTLTexture? {
        // Create a simple test pattern texture for effect preview
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let testTexture = metalDevice.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }
        
        // Generate test pattern (gradient or sample image)
        generateTestPattern(in: testTexture, commandBuffer: commandBuffer)
        
        // Apply effect
        let previewTexture = effect.apply(to: testTexture, using: commandBuffer, device: metalDevice)
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return previewTexture
    }
    
    private func generateTestPattern(in texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        // Generate a simple gradient pattern for preview
        // This would be implemented with a Metal compute shader
    }
}

// MARK: - Drag & Drop Types

struct EffectDragItem: Codable {
    let effectType: String
    let sourceChainID: String?
    let sourceIndex: Int?
    
    init(effectType: String) {
        self.effectType = effectType
        self.sourceChainID = nil
        self.sourceIndex = nil
    }
    
    init(effectType: String, from chainID: String, at index: Int) {
        self.effectType = effectType
        self.sourceChainID = chainID
        self.sourceIndex = index
    }
}

extension EffectDragItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: EffectDragItem.self, contentType: .data)
    }
}