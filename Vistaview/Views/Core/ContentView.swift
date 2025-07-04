// File: Views/Core/ContentView.swift
import SwiftUI
import AVKit
import UniformTypeIdentifiers
import AppKit

/// Main application view with a split layout for presets and video preview.
struct ContentView: View {
    @StateObject private var presetManager = PresetManager()
    @State private var videoURL: URL?
    @State private var player: AVPlayer = AVPlayer()

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
                // Video Preview
                GroupBox(label: Label("Preview", systemImage: "play.rectangle")) {
                    if let url = videoURL, let preset = presetManager.selectedPreset {
                        VideoPlayer(player: player)
                            .onAppear {
                                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                                player.play()
                            }
                            .frame(maxWidth: .infinity, minHeight: 250)
                            .blur(radius: preset.isBlurEnabled ? CGFloat(preset.blurAmount) * 20 : 0)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                            Text(videoURL == nil ? "No video loaded" : "No preset selected")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 250)
                    }
                }

                // Effect Controls
                GroupBox(label: Label("Effect Controls", systemImage: "slider.horizontal.3")) {
                    EffectControlsView(presetManager: presetManager)
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
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType.movie, UTType.mpeg4Movie]
        } else {
            panel.allowedFileTypes = ["mov", "mp4", "m4v"]
        }
        panel.begin { response in
            if response == .OK, let url = panel.url {
                videoURL = url
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
