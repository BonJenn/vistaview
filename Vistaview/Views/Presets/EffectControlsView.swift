import SwiftUI

struct EffectControlsView: View {
    @ObservedObject var presetManager: PresetManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let preset = presetManager.selectedPreset {
                    GroupBox("Blur") {
                        Toggle("Enabled", isOn: Binding(
                            get: { preset.isBlurEnabled },
                            set: { newVal in
                                var p = preset
                                p.isBlurEnabled = newVal
                                presetManager.updatePreset(p)
                            }
                        ))
                        HStack {
                            Text("Amount")
                            Slider(
                                value: Binding(
                                    get: { preset.blurAmount },
                                    set: { newVal in
                                        var p = preset
                                        p.blurAmount = newVal
                                        presetManager.updatePreset(p)
                                    }
                                ),
                                in: 0...1
                            )
                        }
                    }

                    if !preset.effects.isEmpty {
                        GroupBox("Effects") {
                            ForEach(preset.effects.indices, id: \.self) { idx in
                                HStack {
                                    Text(preset.effects[idx].type)
                                    Slider(
                                        value: Binding(
                                            get: { preset.effects[idx].amount },
                                            set: { newVal in
                                                var p = preset
                                                p.effects[idx].amount = newVal
                                                presetManager.updatePreset(p)
                                            }
                                        ),
                                        in: 0...1
                                    )
                                }
                            }
                        }
                    }
                } else {
                    Text("No preset selected")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

