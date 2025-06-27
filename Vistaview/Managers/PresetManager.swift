import Foundation

public struct Preset: Codable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var effects: [Effect]

    public init(id: UUID = UUID(), name: String, effects: [Effect]) {
        self.id = id
        self.name = name
        self.effects = effects
    }
}

public class PresetManager: ObservableObject {
    @Published public private(set) var presets: [Preset] = []
    private let presetsDirectory: URL

    public init(presetsDirectory: URL) {
        self.presetsDirectory = presetsDirectory
        loadPresets()
    }

    public func addPreset(_ preset: Preset) {
        presets.append(preset)
        savePresetToDisk(preset)
    }

    private func loadPresets() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: presetsDirectory, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }

            for file in jsonFiles {
                let data = try Data(contentsOf: file)
                let preset = try JSONDecoder().decode(Preset.self, from: data)
                presets.append(preset)
            }
        } catch {
            print("Failed to load presets: \(error)")
        }
    }

    private func savePresetToDisk(_ preset: Preset) {
        let fileURL = presetsDirectory.appendingPathComponent("\(preset.name).json")

        do {
            let data = try JSONEncoder().encode(preset)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save preset: \(error)")
        }
    }
}
