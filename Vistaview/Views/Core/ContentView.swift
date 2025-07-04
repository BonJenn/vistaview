// File: Views/Core/ContentView.swift
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import AppKit

/// Main application view with multi-deck camera switching and custom video preview & controls.
struct ContentView: View {
    @StateObject private var presetManager = PresetManager()
    @State private var videoURLs: [URL?] = [nil, nil]
    @State private var players: [AVPlayer] = [AVPlayer(), AVPlayer()]
    @State private var isPlaying: [Bool] = [false, false]
    @State private var playheads: [Double] = [0.0, 0.0]
    @State private var previewIndex: Int = 0
    @State private var programIndex: Int = 1

    var body: some View {
        NavigationSplitView {
            // Sidebar: load decks and presets
            VStack(alignment: .leading) {
                Text("Deck Controls")
                    .font(.headline)
                    .padding(.top)
                HStack {
                    Button("Load Deck 1") { loadVideo(for: 0) }
                    Button("Load Deck 2") { loadVideo(for: 1) }
                }
                .padding(.vertical)

                Picker("Preview Deck", selection: $previewIndex) {
                    Text("Deck 1").tag(0)
                    Text("Deck 2").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.bottom)

                Button("Take") {
                    programIndex = previewIndex
                }
                .padding(.bottom)

                Divider()

                Text("Presets")
                    .font(.headline)
                List(presetManager.presets, id: \.id, selection: $presetManager.selectedPresetID) { preset in
                    Text(preset.name).tag(preset.id)
                }
                .listStyle(.sidebar)

                Spacer()
            }
            .padding()
            .navigationTitle("Vistaview")
            .frame(minWidth: 200)
        } detail: {
            // Detail: show preview/program side by side
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    // Preview Window
                    GroupBox(label: Label("Preview (Deck \(previewIndex+1))", systemImage: "eye")) {
                        if let url = videoURLs[previewIndex] {
                            VideoPlayerContainerView(
                                player: $players[previewIndex],
                                isPlaying: $isPlaying[previewIndex],
                                playhead: $playheads[previewIndex]
                            )
                            .onAppear { startPlayer(at: previewIndex) }
                            .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            Text("No source")
                                .frame(maxWidth: .infinity, minHeight: 200)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Program Window
                    GroupBox(label: Label("Program (Deck \(programIndex+1))", systemImage: "play.circle")) {
                        if let url = videoURLs[programIndex], let preset = presetManager.selectedPreset {
                            VideoPlayerContainerView(
                                player: $players[programIndex],
                                isPlaying: $isPlaying[programIndex],
                                playhead: $playheads[programIndex]
                            )
                            .onAppear { startPlayer(at: programIndex) }
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .blur(radius: preset.isBlurEnabled ? CGFloat(preset.blurAmount) * 20 : 0)
                        } else {
                            Text("No source")
                                .frame(maxWidth: .infinity, minHeight: 200)
                                .foregroundColor(.secondary)
                        }
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
        .frame(minWidth: 1000, minHeight: 600)
    }

    // MARK: - Deck Actions
    private func loadVideo(for deck: Int) {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType.movie, UTType.mpeg4Movie]
        } else {
            panel.allowedFileTypes = ["mov", "mp4", "m4v"]
        }
        panel.begin { response in
            if response == .OK, let url = panel.url {
                videoURLs[deck] = url
            }
        }
    }

    private func startPlayer(at deck: Int) {
        guard let url = videoURLs[deck] else { return }
        let item = AVPlayerItem(url: url)
        players[deck].replaceCurrentItem(with: item)
        players[deck].play()
        isPlaying[deck] = true
        playheads[deck] = 0.0
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

