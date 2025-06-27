// EffectControlsView.swift
import SwiftUI

struct EffectControlsView: View {
    @Binding var effect: Effect

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $effect.isEnabled) {
                Text(effect.name)
                    .font(.headline)
            }
            .toggleStyle(SwitchToggleStyle())

            HStack {
                Text("Intensity")
                    .font(.subheadline)
                Slider(value: $effect.intensity, in: 0...1)
            }
            .disabled(!effect.isEnabled)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}
