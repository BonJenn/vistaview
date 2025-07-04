// File: Views/Core/ContentView.swift
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import AppKit

/// Main application view with multi-deck camera switching and smooth crossfades.
struct ContentView: View {
    // MARK: - State
    @StateObject private var presetManager = PresetManager()
    @State private var videoURLs: [URL?] = [nil, nil]
    @State private var players: [AVPlayer] = [AVPlayer(), AVPlayer()]
    @State private var isPlaying: [Bool] = [false, false]
    @State private var playheads: [Double] = [0.0, 0.0]
    @State private var previewIndex: Int = 0
    @State private var programIndex: Int = 1
    @State private var crossfadePosition: Double = 1.0

    // MARK: - Body
    var body: some View {
        NavigationSplitView {
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

                Button("Take") { autoTake() }
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
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    // Preview Window
                    GroupBox(label: Label("Preview (Deck \(previewIndex+1))", systemImage: "eye")) {
                        if videoURLs[previewIndex] != nil {
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

                    // Program Window (blended)
                    GroupBox(label: Label("Program (Blend)", systemImage: "play.circle")) {
                        ZStack {
                            if videoURLs[programIndex] != nil {
                                VideoPlayerContainerView(
                                    player: $players[programIndex],
                                    isPlaying: $isPlaying[programIndex],
                                    playhead: $playheads[programIndex]
                                )
                                .onAppear { startPlayer(at: programIndex) }
                                .frame(maxWidth: .infinity, minHeight: 200)
                                .opacity(1 - crossfadePosition)
                            }
                            if videoURLs[previewIndex] != nil {
                                VideoPlayerContainerView(
                                    player: $players[previewIndex],
                                    isPlaying: $isPlaying[previewIndex],
                                    playhead: $playheads[previewIndex]
                                )
                                .frame(maxWidth: .infinity, minHeight: 200)
                                .opacity(crossfadePosition)
                            }
                        }
                        .blur(radius: (presetManager.selectedPreset?.isBlurEnabled ?? false)
                              ? CGFloat(presetManager.selectedPreset?.blurAmount ?? 0) * 20 : 0)
                    }
                }

                // Crossfade slider
                HStack {
                    Text("Transition")
                    Slider(value: $crossfadePosition, in: 0...1)
                }
                .padding(.horizontal)

                Divider()

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
    /// Opens a picker, assigns the chosen URL to the given deck, switches preview to it, and starts playback.
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
                previewIndex = deck
                startPlayer(at: deck)
            }
        }
    }

    /// Configures and plays the deck at the specified index.
    private func startPlayer(at deck: Int) {
        guard let url = videoURLs[deck] else { return }
        let item = AVPlayerItem(url: url)
        players[deck].replaceCurrentItem(with: item)
        players[deck].play()
        isPlaying[deck] = true
        playheads[deck] = 0.0
    }

    /// Performs a smooth dissolve from preview to program over 1 second.
    private func autoTake() {
        crossfadePosition = 1.0
        withAnimation(.linear(duration: 1.0)) {
            crossfadePosition = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            programIndex = previewIndex
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
