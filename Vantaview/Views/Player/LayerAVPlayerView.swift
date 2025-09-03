import SwiftUI
import AVFoundation
import AVKit

struct LayerAVPlayerView: NSViewRepresentable {
    let url: URL
    var isMuted: Bool = true
    var autoplay: Bool = true
    var loop: Bool = true
    let layerId: UUID
    @EnvironmentObject var layerManager: LayerStackManager

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        configurePlayer(for: view)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player == nil || (nsView.player as? AVQueuePlayer)?.items().isEmpty == true {
            configurePlayer(for: nsView)
        }
        nsView.player?.isMuted = isMuted
        if autoplay {
            nsView.player?.play()
        }
    }

    private func configurePlayer(for view: AVPlayerView) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        let tap = PlayerAudioTap(playerItem: item)
        layerManager.registerPiPAudioTap(for: layerId, tap: tap)

        let player = AVQueuePlayer(items: [item])
        view.player = player

        if loop {
            _ = AVPlayerLooper(player: player, templateItem: item)
        }
        player.isMuted = isMuted
        if autoplay {
            player.play()
        }
    }
}