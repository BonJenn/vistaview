// File: Managers/PresetManager.swift
import Foundation
import Combine

class PresetManager: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var selectedPresetID: String?

    /// Currently selected preset, if any.
    var selectedPreset: Preset? {
        guard let id = selectedPresetID else { return nil }
        return presets.first { $0.id == id }
    }

    private let presetsDirectory: URL

    init(presetsDirectory: URL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Presets")) {
        self.presetsDirectory = presetsDirectory
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

    func savePreset(_ preset: Preset) {
        let fileURL = presetsDirectory.appendingPathComponent("\(preset.id).json")
        do {
            let data = try JSONEncoder().encode(preset)
            try data.write(to: fileURL)
        } catch {
            print("Error saving preset: \(error)")
        }
    }

    func addPreset(name: String) {
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
    }

    func deletePreset(_ preset: Preset) {
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
    }

    /// Updates an existing preset in memory and on disk.
    func updatePreset(_ preset: Preset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        savePreset(preset)
    }
}
