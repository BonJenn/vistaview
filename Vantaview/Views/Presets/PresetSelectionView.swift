import SwiftUI

struct PresetSelectionView: View {
    @ObservedObject var presetManager: PresetManager

    var body: some View {
        HStack {
            Picker("Preset", selection: $presetManager.selectedPresetID) {
                ForEach(presetManager.presets, id: \.id) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .pickerStyle(MenuPickerStyle())

            Button(action: {
                presetManager.addPreset(name: "New Preset")
            }) {
                Image(systemName: "plus.circle")
            }
        }
        .padding()
    }
}

