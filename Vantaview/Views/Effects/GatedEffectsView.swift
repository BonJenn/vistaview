//
//  GatedEffectsView.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import SwiftUI

struct GatedEffectsView: View {
    @ObservedObject var presetManager: PresetManager
    @ObservedObject var licenseManager: LicenseManager
    @State private var showingAddPreset = false
    @State private var newPresetName = ""
    @State private var isBasicEffectsEnabled = false
    @State private var maxPresets = 0
    @State private var canCreateMore = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with license info
            headerSection
            
            // Presets section
            presetsSection
            
            // Effects library
            effectsLibrarySection
        }
        .padding()
        .sheet(isPresented: $showingAddPreset) {
            addPresetSheet
        }
        .onAppear {
            updateLicenseState()
        }
        .onChange(of: licenseManager.currentTier) { _, _ in
            updateLicenseState()
        }
        .onChange(of: licenseManager.status) { _, _ in
            updateLicenseState()
        }
    }
    
    private func updateLicenseState() {
        Task { @MainActor in
            isBasicEffectsEnabled = licenseManager.isEnabled(.effectsBasic)
            maxPresets = presetManager.maxPresetsAllowed
            canCreateMore = presetManager.canCreateMorePresets
        }
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Effects & Presets")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let tier = licenseManager.currentTier {
                    Text("\(tier.displayName) Plan")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No active subscription")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            if isBasicEffectsEnabled {
                Button("New Preset") {
                    showingAddPreset = true
                }
                .disabled(!canCreateMore)
            }
        }
    }
    
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Presets")
                    .font(.headline)
                
                Spacer()
                
                if isBasicEffectsEnabled {
                    Text("\(presetManager.presets.count)/\(maxPresets)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if isBasicEffectsEnabled {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(presetManager.presets, id: \.id) { preset in
                            PresetCard(
                                preset: preset,
                                isSelected: presetManager.selectedPresetID == preset.id,
                                onSelect: {
                                    presetManager.selectedPresetID = preset.id
                                },
                                onDelete: {
                                    _ = presetManager.deletePreset(preset)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                // Show locked state for Stream tier
                VStack {
                    Image(systemName: "lock.fill")
                        .font(.title)
                        .foregroundColor(.secondary)
                    
                    Text("Custom presets require Live plan or higher")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Button("Upgrade to Live") {
                        // Show paywall
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .gated(.effectsBasic, licenseManager: licenseManager)
            }
        }
    }
    
    private var effectsLibrarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Effects Library")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120), spacing: 12)
            ], spacing: 12) {
                // Use available effect types from PresetManager
                ForEach(presetManager.getAvailableEffectTypes(), id: \.self) { effectType in
                    EffectTypeCard(
                        effectType: effectType,
                        licenseManager: licenseManager
                    )
                }
                
                // Show locked premium effects
                if !licenseManager.isEnabled(.fxPremium) {
                    ForEach(getPremiumEffectTypes(), id: \.self) { effectType in
                        LockedEffectTypeCard(
                            effectType: effectType,
                            licenseManager: licenseManager
                        )
                    }
                }
            }
        }
    }
    
    private func getPremiumEffectTypes() -> [String] {
        return [
            PresetEffect.EffectType.colorGrading,
            PresetEffect.EffectType.lut,
            PresetEffect.EffectType.chromaKey,
            PresetEffect.EffectType.motionBlur,
            PresetEffect.EffectType.particleSystem
        ]
    }
    
    private var addPresetSheet: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("New Preset")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Cancel") {
                    showingAddPreset = false
                    newPresetName = ""
                }
                .buttonStyle(.plain)
            }
            
            // Form
            VStack(alignment: .leading, spacing: 8) {
                Text("Preset Name")
                    .font(.headline)
                
                TextField("Enter preset name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Actions
            HStack {
                Spacer()
                
                Button("Create") {
                    if presetManager.addPreset(name: newPresetName) {
                        showingAddPreset = false
                        newPresetName = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPresetName.isEmpty)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}

struct PresetCard: View {
    let preset: Preset
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preset.name)
                .font(.headline)
                .lineLimit(1)
            
            Text("\(preset.effects.count) effects")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack {
                Button("Apply") {
                    onSelect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 140, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
    }
}

struct EffectTypeCard: View {
    let effectType: String
    let licenseManager: LicenseManager
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: effectIcon)
                .font(.title2)
                .foregroundColor(.primary)
            
            Text(effectDisplayName)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            if isPremium {
                Text("PRO")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .cornerRadius(4)
            }
        }
        .frame(width: 80, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        )
    }
    
    private var isPremium: Bool {
        let effect = PresetEffect(type: effectType, amount: 0.0)
        return effect.isPremium
    }
    
    private var effectDisplayName: String {
        let effect = PresetEffect(type: effectType, amount: 0.0)
        return effect.displayName
    }
    
    private var effectIcon: String {
        switch effectType {
        case "blur": return "camera.filters"
        case "brightness": return "sun.max"
        case "contrast": return "circle.lefthalf.filled"
        case "saturation": return "paintpalette"
        case "hue": return "paintbrush"
        case "colorGrading": return "slider.horizontal.3"
        case "lut": return "square.grid.3x3"
        case "chromaKey": return "wand.and.stars"
        case "motionBlur": return "wind"
        case "particleSystem": return "sparkles"
        default: return "fx"
        }
    }
}

struct LockedEffectTypeCard: View {
    let effectType: String
    let licenseManager: LicenseManager
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: effectIcon)
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text(effectDisplayName)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Text("PRO")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange)
                .cornerRadius(4)
        }
        .frame(width: 80, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    Image(systemName: "lock.fill")
                        .foregroundColor(.white)
                )
        )
        .gated(.fxPremium, licenseManager: licenseManager)
    }
    
    private var effectDisplayName: String {
        let effect = PresetEffect(type: effectType, amount: 0.0)
        return effect.displayName
    }
    
    private var effectIcon: String {
        switch effectType {
        case "colorGrading": return "slider.horizontal.3"
        case "lut": return "square.grid.3x3"
        case "chromaKey": return "wand.and.stars"
        case "motionBlur": return "wind"
        case "particleSystem": return "sparkles"
        default: return "fx"
        }
    }
}