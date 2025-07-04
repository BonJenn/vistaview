import SwiftUI
import AppKit

/// Main application view with a split layout for presets and video preview.
struct ContentView: View {
    @StateObject private var presetManager = PresetManager()
    @State private var videoURL: URL?

    var body: some View {
        NavigationSplitView {
            // Sidebar: Preset list and actions
            List(selection: $presetManager.selectedPresetID) {
                ForEach(presetManager.presets, id: \.id) { preset in
                    Text(preset.name)
                        .tag(preset.id)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Presets")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button(action: loadVideo) {
                        Label("Load Video", systemImage: "film")
                    }
                    Button(action: addPreset) {
                        Label("New Preset", systemImage: "plus")
                    }
                }
            }
        } detail: {
            // Main area: Video preview + effect controls
            VStack(spacing: 20) {
                // Video Preview Group
                GroupBox(label: Label("Preview", systemImage: "play.rectangle")) {
                    ZStack {
                        // Placeholder background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Text(videoURL == nil ? "No video loaded" : "Video playing…")
                                    .foregroundColor(.secondary)
                            )
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                }

                // Effect Controls Group
                GroupBox(label: Label("Effect Controls", systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 16) {
                        EffectControlsView(presetManager: presetManager)
                    }
                    .padding()
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    // MARK: - Actions
    private func loadVideo() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["mov", "mp4", "m4v"]
        panel.begin { response in
            if response == .OK {
                videoURL = panel.url
            }
        }
    }

    private func addPreset() {
        let name = "Preset \(presetManager.presets.count + 1)"
        presetManager.addPreset(name: name)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

