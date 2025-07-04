// File: Views/Core/CustomVideoPlayerView.swift
import SwiftUI
import AVFoundation
import AppKit

/// A SwiftUI wrapper around an AVPlayerLayer for custom video playback controls.
struct CustomVideoPlayerView: NSViewRepresentable {
    @Binding var player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        // Create the AVPlayerLayer
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = container.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        container.layer = playerLayer
        container.wantsLayer = true

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let playerLayer = nsView.layer as? AVPlayerLayer else { return }
        playerLayer.player = player
    }
}

/// A SwiftUI view that composes the custom video layer with on-screen controls.
struct VideoPlayerContainerView: View {
    @Binding var player: AVPlayer
    @Binding var isPlaying: Bool
    @Binding var playhead: Double // 0.0–1.0 normalized

    var body: some View {
        ZStack {
            CustomVideoPlayerView(player: $player)
                .cornerRadius(8)

            // Overlay controls
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
            }
        }
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

