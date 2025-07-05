// File: Views/Core/ContentView.swift
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import AppKit

// MARK: - Streaming Platform & Credentials
enum StreamingPlatform: String, CaseIterable, Identifiable {
    case twitch, youtube
    var id: String { rawValue }
    var rtmpURL: String {
        switch self {
        case .twitch:  return "rtmp://live.twitch.tv/app"
        case .youtube: return "rtmp://a.rtmp.youtube.com/live2"
        }
    }
}

class StreamingCredentials {
    private enum Keys {
        static let platform = "streamingPlatform"
        static let streamKey = "streamKey"
    }
    static var platform: StreamingPlatform? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.platform) else { return nil }
            return StreamingPlatform(rawValue: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: Keys.platform)
        }
    }
    static var streamKey: String? {
        get { UserDefaults.standard.string(forKey: Keys.streamKey) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.streamKey) }
    }
    static var hasSavedCredentials: Bool {
        platform != nil && !(streamKey?.isEmpty ?? true)
    }
}

// MARK: - Main App View
struct ContentView: View {
    // State
    @StateObject private var presetManager = PresetManager()
    @StateObject private var streamer: Streamer
    @State private var videoURLs: [URL?] = [nil, nil]
    @State private var players: [AVPlayer] = [AVPlayer(), AVPlayer()]
    @State private var isPlaying: [Bool] = [false, false]
    @State private var playheads: [Double] = [0.0, 0.0]
    @State private var previewIndex = 0
    @State private var programIndex = 1
    @State private var crossfadePosition: Double = 1.0
    @State private var showSetup = false
    @State private var chosenPlatform: StreamingPlatform = .twitch
    @State private var enteredKey: String = ""

    // Custom initializer to configure streamer with saved creds if available
    init() {
        let (url, key) = StreamingCredentials.hasSavedCredentials
            ? (StreamingCredentials.platform!.rtmpURL, StreamingCredentials.streamKey!)
            : ("", "")
        _streamer = StateObject(wrappedValue: Streamer(streamURL: url, streamName: key))
    }

    var body: some View {
        NavigationSplitView {
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
        } detail: {
            mainDetailView
        }
        .frame(minWidth: 1000, minHeight: 600)
        .sheet(isPresented: $showSetup) { setupSheet }
    }

    // MARK: - Subviews
    private var deckControls: some View {
        VStack(alignment: .leading) {
            Text("Deck Controls").font(.headline)
            HStack {
                Button("Load Deck 1") { loadVideo(0) }
                Button("Load Deck 2") { loadVideo(1) }
            }
            .padding(.vertical)
            Picker("Preview", selection: $previewIndex) {
                Text("1").tag(0)
                Text("2").tag(1)
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
                    systemImage: streamer.isStreaming ? "dot.radiowaves.left.and.right.slash" : "dot.radiowaves.left.and.right"
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
            List(presetManager.presets, id: \.id, selection: $presetManager.selectedPresetID) {
                Text($0.name).tag($0.id)
            }
            .listStyle(SidebarListStyle())
        }
    }

    private var mainDetailView: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                deckView(isPreview: true)
                deckView(isPreview: false)
            }
            crossfadeSlider
            effectControls
            Spacer()
        }
        .padding()
    }

    private func deckView(isPreview: Bool) -> some View {
        let idx = isPreview ? previewIndex : programIndex
        return GroupBox(label: Label(isPreview ? "Preview" : "Program", systemImage: isPreview ? "eye" : "play.circle")) {
            if let _ = videoURLs[idx] {
                VideoPlayerContainerView(
                    player: $players[idx],
                    isPlaying: $isPlaying[idx],
                    playhead: $playheads[idx]
                )
                .onAppear { startPlayer(idx) }
                .opacity(isPreview ? crossfadePosition : (1 - crossfadePosition))
                .blur(radius: (!isPreview && (presetManager.selectedPreset?.isBlurEnabled ?? false))
                        ? CGFloat(presetManager.selectedPreset!.blurAmount) * 20 : 0)
            } else {
                Text("No source").foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var crossfadeSlider: some View {
        HStack {
            Text("Transition")
            Slider(value: $crossfadePosition, in: 0...1)
        }
        .padding(.horizontal)
    }

    private var effectControls: some View {
        GroupBox(label: Label("Effect Controls", systemImage: "slider.horizontal.3")) {
            EffectControlsView(presetManager: presetManager)
                .padding()
        }
    }

    private var setupSheet: some View {
        VStack(spacing: 16) {
            Text("First Time Streaming").font(.headline)
            Picker("Platform", selection: $chosenPlatform) {
                ForEach(StreamingPlatform.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(SegmentedPickerStyle())
            TextField("Stream Key", text: $enteredKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            HStack {
                Button("Cancel") { showSetup = false }
                Spacer()
                Button("Save & Go Live") {
                    StreamingCredentials.platform = chosenPlatform
                    StreamingCredentials.streamKey = enteredKey.trimmingCharacters(in: .whitespaces)
                    showSetup = false
                    toggleLive()
                }
                .disabled(enteredKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Actions
    private func loadVideo(_ deck: Int) {
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
                startPlayer(deck)
            }
        }
    }

    private func startPlayer(_ deck: Int) {
        guard let url = videoURLs[deck] else { return }
        let item = AVPlayerItem(url: url)
        players[deck].replaceCurrentItem(with: item)
        players[deck].play()
        isPlaying[deck] = true
        playheads[deck] = 0
    }

    private func autoTake() {
        crossfadePosition = 1
        withAnimation(.linear(duration: 1.0)) {
            crossfadePosition = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            programIndex = previewIndex
        }
    }

    private func toggleLive() {
        guard let programItem = players[programIndex].currentItem else { return }
        if streamer.isStreaming {
            streamer.stopStreaming()
        } else if StreamingCredentials.hasSavedCredentials {
            if let view = NSApp.mainWindow?.contentView {
                streamer.startStreaming(playerItem: programItem, on: view)
            }
        } else {
            showSetup = true
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
