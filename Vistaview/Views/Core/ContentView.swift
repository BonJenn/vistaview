// File: Views/Core/ContentView.swift
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import AppKit

/// Main application view with a split layout for presets and custom video preview & controls.
struct ContentView: View {
    @StateObject private var presetManager = PresetManager()
    @State private var videoURL: URL?
    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var playhead: Double = 0.0

    var body: some View {
        NavigationSplitView {
            // Sidebar: Preset list and actions
            VStack {
                HStack {
                    Button(action: loadVideo) {
                        Label("Load Video", systemImage: "film")
                    }
                    Button(action: addPreset) {
                        Label("New Preset", systemImage: "plus")
                    }
                }
                .padding([.top, .horizontal])

                List(presetManager.presets, id: \.id, selection: $presetManager.selectedPresetID) { preset in
                    Text(preset.name)
                        .tag(preset.id)
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("Presets")
        } detail: {
            VStack(spacing: 20) {
                // Video Preview with custom controls
                GroupBox(label: Label("Preview", systemImage: "play.rectangle")) {
                    if let url = videoURL, let preset = presetManager.selectedPreset {
                        ZStack {
                            // Video Layer
                            CustomVideoPlayerView(player: $player)
                                .onAppear {
                                    let item = AVPlayerItem(url: url)
                                    player.replaceCurrentItem(with: item)
                                    player.play()
                                    isPlaying = true
                                }
                                .frame(maxWidth: .infinity, minHeight: 250)
                                .blur(radius: preset.isBlurEnabled ? CGFloat(preset.blurAmount) * 20 : 0)
                                .cornerRadius(8)

                            // Controls Overlay
                            VStack {
                                Spacer()
                                HStack {
                                    Button(action: togglePlay) {
                                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                            .font(.title2)
                                            .padding(8)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                    }
                                    Slider(value: $playhead, in: 0...1, onEditingChanged: seek)
                                        .accentColor(.white)
                                        .padding(.horizontal)
                                }
                                .padding()
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(8)
                                .padding()
                            }
                        }
                    } else if videoURL == nil {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                            Text("No video loaded")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 250)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                            Text("No preset selected")
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

    private func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func seek(editingStarted: Bool) {
        guard let duration = player.currentItem?.duration.seconds, duration > 0 else { return }
        let newTime = CMTime(seconds: playhead * duration, preferredTimescale: 600)
        player.seek(to: newTime)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

