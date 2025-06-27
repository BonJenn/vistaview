import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var effects: [Effect] = [
        Effect(name: "Blur", isEnabled: false, intensity: 0.5),
        Effect(name: "RGB Split", isEnabled: false, intensity: 0.3),
        Effect(name: "Glitch", isEnabled: false, intensity: 0.0)
    ]

    @State private var showingFileImporter = false
    @State private var currentVideoName: String = "clip.mp4"

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                VStack {
                    Text("Preview")
                    MetalViewContainer(
                        blurEnabled: effects[0].isEnabled,
                        blurAmount: effects[0].intensity
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .border(Color.gray)
                }

                VStack {
                    Text("Main Output")
                    MetalViewContainer(
                        blurEnabled: effects[0].isEnabled,
                        blurAmount: effects[0].intensity
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .border(Color.red)
                }
            }
            .padding()

            HStack {
                Button("Load Video") {
                    showingFileImporter = true
                }

                Button("Reset Effects") {
                    effects = effects.map {
                        var copy = $0
                        copy.isEnabled = false
                        copy.intensity = 0.5
                        return copy
                    }
                }
            }

            Text("Now Playing: \(currentVideoName)")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                ForEach($effects) { $effect in
                    EffectControlsView(effect: $effect)
                        .padding(.horizontal)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let selectedURL = urls.first {
                    currentVideoName = selectedURL.lastPathComponent
                    NotificationCenter.default.post(name: .loadNewVideo, object: selectedURL)
                }
            case .failure(let error):
                print("File import error: \(error)")
            }
        }
    }
}
