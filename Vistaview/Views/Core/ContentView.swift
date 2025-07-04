import SwiftUI

struct ContentView: View {
    @StateObject private var presetManager = PresetManager()

    var body: some View {
        VStack {
            DualRendererView(
                isPreview: true,
                blurAmount: .constant(presetManager.selectedPreset?.blurAmount ?? 0.0),
                isBlurEnabled: .constant(presetManager.selectedPreset?.isBlurEnabled ?? false)
            )
            .frame(height: 200)

            DualRendererView(
                isPreview: false,
                blurAmount: .constant(presetManager.selectedPreset?.blurAmount ?? 0.0),
                isBlurEnabled: .constant(presetManager.selectedPreset?.isBlurEnabled ?? false)
            )
            .frame(height: 200)

            PresetSelectionView(presetManager: presetManager)
            EffectControlsView(presetManager: presetManager)
        }
        .padding()
    }
}
