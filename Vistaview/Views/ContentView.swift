import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var effects: [Effect] = [
        Effect(name: "Blur", isEnabled: true, intensity: 0.5),
        Effect(name: "RGB Split", isEnabled: false, intensity: 0.3),
        Effect(name: "Glitch", isEnabled: false, intensity: 0.0)
    ]

    @State private var topHeight: CGFloat = 500.0
    @State private var bottomHeight: CGFloat = 200.0
    @State private var currentVideoName: String = "clip.mp4"
    @State private var showingFileImporter = false
    @State private var showingPresetNameAlert = false
    @State private var newPresetName = ""
    @State private var showingExportSuccess = false

    @StateObject private var presetManager = PresetManager(
        presetsDirectory: FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Presets")
    )

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                MetalViewContainer(
                    width: geometry.size.width,
                    height: topHeight,
                    blurEnabled: effects.first(where: { $0.name == "Blur" })?.isEnabled ?? false,
                    blurAmount: effects.first(where: { $0.name == "Blur" })?.intensity ?? 0.0
                )
            }
            .frame(height: topHeight)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                if let provider = providers.first {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let videoURL = url {
                            DispatchQueue.main.async {
                                currentVideoName = videoURL.lastPathComponent
                                NotificationCenter.default.post(name: .loadNewVideo, object: videoURL)
                            }
                        }
                    }
                    return true
                }
                return false
            }

            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 6)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newHeight = topHeight + value.translation.height
                            if newHeight > 200 && newHeight < 800 {
                                topHeight = newHeight
                                bottomHeight = max(100, 800 - newHeight)
                            }
                        }
                )
                .background(Color.gray)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button("Dreamy Preset") {
                        effects = [
                            Effect(name: "Blur", isEnabled: true, intensity: 0.7),
                            Effect(name: "RGB Split", isEnabled: false, intensity: 0.3),
                            Effect(name: "Glitch", isEnabled: false, intensity: 0.0)
                        ]
                    }

                    Button("Reset All") {
                        for i in effects.indices {
                            effects[i].isEnabled = false
                            effects[i].intensity = 0.5
                        }
                    }

                    Button("Load Video") {
                        showingFileImporter = true
                    }

                    Menu("Presets") {
                        ForEach(presetManager.presets, id: \.id) { preset in
                            Button(preset.name) {
                                effects = preset.effects
                            }
                        }
                    }

                    Button("Save Preset") {
                        showingPresetNameAlert = true
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Text("Now Playing: \(currentVideoName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Visual Effects")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach($effects) { $effect in
                            EffectControlsView(effect: $effect)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .frame(height: bottomHeight)
            .background(Color(.windowBackgroundColor))
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
        .alert("Enter Preset Name", isPresented: $showingPresetNameAlert, actions: {
            TextField("Preset Name", text: $newPresetName)
            Button("Save") {
                let newPreset = Preset(name: newPresetName, effects: effects)
                presetManager.addPreset(newPreset)
                newPresetName = ""
            }
            Button("Cancel", role: .cancel) {
                newPresetName = ""
            }
        })
    }
}

