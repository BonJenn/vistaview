// File: Managers/PresetManager.swift
import Foundation
import Combine

@MainActor
class PresetManager: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var selectedPresetID: String?

    /// Currently selected preset, if any.
    var selectedPreset: Preset? {
        guard let id = selectedPresetID else { return nil }
        return presets.first { $0.id == id }
    }

    private let presetsDirectory: URL
    private let licenseManager: LicenseManager

    init(presetsDirectory: URL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Presets"),
         licenseManager: LicenseManager) {
        self.presetsDirectory = presetsDirectory
        self.licenseManager = licenseManager
        
        do {
            try FileManager.default.createDirectory(at: presetsDirectory,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        } catch {
            print("Error creating presets directory: \(error)")
        }
        loadPresets()

        // Guarantee at least one preset exists
        if presets.isEmpty {
            let defaultPreset = Preset(
                id: UUID().uuidString,
                name: "Default Preset",
                effects: [],
                blurAmount: 0.0,
                isBlurEnabled: false
            )
            presets = [defaultPreset]
            selectedPresetID = defaultPreset.id
            savePreset(defaultPreset)
        }
    }

    private func loadPresets() {
        presets.removeAll()
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: presetsDirectory,
                includingPropertiesForKeys: nil,
                options: []
            )
            for url in fileURLs where url.pathExtension.lowercased() == "json" {
                if let data = try? Data(contentsOf: url),
                   let preset = try? JSONDecoder().decode(Preset.self, from: data) {
                    presets.append(preset)
                }
            }
        } catch {
            print("Error reading presets directory: \(error)")
        }
        selectedPresetID = presets.first?.id
    }

    nonisolated func savePreset(_ preset: Preset) {
        let fileURL = presetsDirectory.appendingPathComponent("\(preset.id).json")
        do {
            let data = try JSONEncoder().encode(preset)
            try data.write(to: fileURL)
        } catch {
            print("Error saving preset: \(error)")
        }
    }

    func addPreset(name: String) -> Bool {
        // Gate preset creation behind basic effects feature
        guard licenseManager.isEnabled(.effectsBasic) else {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 PresetManager: Preset creation denied - requires Live tier or higher")
            }
            return false
        }
        
        let newPreset = Preset(
            id: UUID().uuidString,
            name: name,
            effects: [],
            blurAmount: 0.0,
            isBlurEnabled: false
        )
        presets.append(newPreset)
        selectedPresetID = newPreset.id
        savePreset(newPreset)
        return true
    }

    func deletePreset(_ preset: Preset) -> Bool {
        // Gate preset deletion behind basic effects feature
        guard licenseManager.isEnabled(.effectsBasic) else {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 PresetManager: Preset deletion denied - requires Live tier or higher")
            }
            return false
        }
        
        presets.removeAll { $0.id == preset.id }
        if selectedPresetID == preset.id {
            selectedPresetID = presets.first?.id
        }
        let fileURL = presetsDirectory.appendingPathComponent("\(preset.id).json")
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            print("Error deleting preset file: \(error)")
        }
        return true
    }

    /// Updates an existing preset in memory and on disk
    func updatePreset(_ preset: Preset) -> Bool {
        // For UI updates, we'll allow the update and filter later if needed
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return false }
        
        presets[index] = preset
        savePreset(preset)
        return true
    }
    
    /// Updates an existing preset with license checking
    func updatePresetWithLicenseCheck(_ preset: Preset) async -> Bool {
        // Gate preset updates behind basic effects feature
        guard licenseManager.isEnabled(.effectsBasic) else {
            if LicenseConstants.debugLoggingEnabled {
                print("🔐 PresetManager: Preset update denied - requires Live tier or higher")
            }
            return false
        }
        
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return false }
        
        // Filter out premium effects if user doesn't have Pro tier
        let filteredPreset = await preset.filtered(for: licenseManager)
        
        presets[index] = filteredPreset
        savePreset(filteredPreset)
        return true
    }
    
    /// Get available effect types based on current license tier
    func getAvailableEffectTypes() -> [String] {
        var availableTypes: [String] = []
        
        // Basic effects (Live tier and above)
        if licenseManager.isEnabled(.effectsBasic) {
            availableTypes.append(contentsOf: [
                PresetEffect.EffectType.blur,
                PresetEffect.EffectType.brightness,
                PresetEffect.EffectType.contrast,
                PresetEffect.EffectType.saturation,
                PresetEffect.EffectType.hue
            ])
        }
        
        // Premium effects (Pro tier only)
        if licenseManager.isEnabled(.fxPremium) {
            availableTypes.append(contentsOf: [
                PresetEffect.EffectType.colorGrading,
                PresetEffect.EffectType.lut,
                PresetEffect.EffectType.chromaKey,
                PresetEffect.EffectType.motionBlur,
                PresetEffect.EffectType.particleSystem
            ])
        }
        
        return availableTypes
    }
    
    /// Check if a specific effect type can be used
    func canUseEffectType(_ effectType: String) -> Bool {
        let effect = PresetEffect(type: effectType, amount: 0.0)
        return effect.isPremium ? licenseManager.isEnabled(.fxPremium) : licenseManager.isEnabled(.effectsBasic)
    }
    
    /// Get maximum number of presets allowed
    var maxPresetsAllowed: Int {
        guard let tier = licenseManager.currentTier else { return 0 }
        
        switch tier {
        case .stream:
            return 0 // No custom presets in Stream tier
        case .live:
            return 10
        case .stage:
            return 25
        case .pro:
            return 100 // Unlimited (practical limit)
        }
    }
    
    /// Check if user can create more presets
    var canCreateMorePresets: Bool {
        return licenseManager.isEnabled(.effectsBasic) && presets.count < maxPresetsAllowed
    }
}