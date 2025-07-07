// File: Views/Core/ContentView.swift
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import AppKit

/// Main view: manages video decks, presets, and live streaming.
struct ContentView: View {
    // MARK: - Deck State
    @State private var videoURLs: [URL?] = [nil, nil]
    @State private var players: [AVPlayer] = [AVPlayer(), AVPlayer()]
    @State private var isPlaying: [Bool] = [false, false]
    @State private var playheads: [Double] = [0.0, 0.0]
    @State private var previewIndex = 0
    @State private var programIndex = 1
    @State private var crossfadePosition: Double = 1.0

    // MARK: - Presets
    @StateObject private var presetManager = PresetManager()

    // MARK: - Streaming State
    @AppStorage("rtmpURL") private var rtmpURL: String = "rtmp://127.0.0.1:1935/live"
    @AppStorage("streamKey") private var streamKey: String = ""
    @StateObject private var streamer = Streamer()
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            mainDetailView
        }
        .frame(minWidth: 1000, minHeight: 600)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading) {
            deckControls
            Divider()
            liveButton
            Divider()
            presetsList
            Spacer()
        }
        .padding()
        .navigationTitle("Vistaview")
    }

    private var deckControls: some View {
        VStack(alignment: .leading) {
            Text("Deck Controls").font(.headline)
            HStack {
                Button("Load Deck 1") { loadVideo(deck: 0) }
                Button("Load Deck 2") { loadVideo(deck: 1) }
            }
            .padding(.vertical)
            Picker("Preview Deck", selection: $previewIndex) {
                Text("Deck 1").tag(0)
                Text("Deck 2").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            Button("Take", action: autoTake)
                .padding(.vertical)
        }
    }

    private var liveButton: some View {
        HStack {
            Button(action: toggleLive) {
                Label(
                    streamer.isStreaming ? "Stop Live" : "Go Live",
                    systemImage: streamer.isStreaming ? "stop.circle" : "dot.radiowaves.left.and.right"
                )
            }
            .foregroundColor(streamer.isStreaming ? .red : .primary)
            if streamer.isStreaming {
                Circle().fill(Color.red).frame(width: 10, height: 10)
            }
        }
        .padding(.vertical)
    }

    private var presetsList: some View {
        VStack(alignment: .leading) {
            Text("Presets").font(.headline)
            List(presetManager.presets, id: \.id, selection: $presetManager.selectedPresetID) { preset in
                Text(preset.name).tag(preset.id)
            }
            .listStyle(SidebarListStyle())
        }
    }

    // MARK: - Main Detail View
    private var mainDetailView: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                deckView(isPreview: true)
                deckView(isPreview: false)
            }
            HStack {
                Text("Transition")
                Slider(value: $crossfadePosition, in: 0...1)
            }
            .padding(.horizontal)
            GroupBox(label: Label("Effect Controls", systemImage: "slider.horizontal.3")) {
                EffectControlsView(presetManager: presetManager)
                    .padding()
            }
            Spacer()
        }
        .padding()
    }

    private func deckView(isPreview: Bool) -> some View {
        let idx = isPreview ? previewIndex : programIndex
        return GroupBox(label: Label(isPreview ? "Preview" : "Program",
                                      systemImage: isPreview ? "eye" : "play.circle")) {
            if let url = videoURLs[idx] {
                VideoPlayerContainerView(
                    player: $players[idx],
                    isPlaying: $isPlaying[idx],
                    playhead: $playheads[idx]
                )
                .onAppear { startPlayer(deck: idx) }
                .opacity(isPreview ? crossfadePosition : (1 - crossfadePosition))
            } else {
                Text("No source").foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Actions
    private func loadVideo(deck: Int) {
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
                startPlayer(deck: deck)
            }
        }
    }

    private func startPlayer(deck: Int) {
        guard let url = videoURLs[deck] else { return }
        let item = AVPlayerItem(url: url)
        players[deck].replaceCurrentItem(with: item)
        players[deck].play()
        isPlaying[deck] = true
        playheads[deck] = 0
    }

    private func autoTake() {
        withAnimation(.linear(duration: 1.0)) { crossfadePosition = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            programIndex = previewIndex
            crossfadePosition = 1
        }
    }

    private func toggleLive() {
        guard let item = players[programIndex].currentItem else { return }
        if streamer.isStreaming {
            streamer.stopStreaming()
        } else {
            // Trim whitespace
            let cleanURL = rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanKey = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)
            streamer.configure(streamURL: cleanURL, streamName: cleanKey)
            if let view = NSApp.mainWindow?.contentView {
                streamer.startStreaming(playerItem: item, on: view)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}

