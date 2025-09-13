import SwiftUI
import AVFoundation
import AVKit

final class AVPlayerLayerHostView: NSView {
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVQueuePlayer? {
        get { playerLayer.player as? AVQueuePlayer }
        set { playerLayer.player = newValue }
    }

    override func makeBackingLayer() -> CALayer {
        AVPlayerLayer()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        canDrawConcurrently = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        canDrawConcurrently = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        playerLayer.needsDisplayOnBoundsChange = true
        needsDisplay = true
    }
}

struct LayerAVPlayerView: NSViewRepresentable {
    let url: URL
    var isMuted: Bool = true
    var autoplay: Bool = true
    var loop: Bool = true
    let layerId: UUID
    @EnvironmentObject var layerManager: LayerStackManager

    func makeNSView(context: Context) -> AVPlayerLayerHostView {
        let v = AVPlayerLayerHostView()
        configure(on: v, context: context)
        return v
    }

    func updateNSView(_ nsView: AVPlayerLayerHostView, context: Context) {
        let needsSetup = (nsView.player == nil) || (nsView.player?.items().isEmpty == true)
        if needsSetup {
            configure(on: nsView, context: context)
        } else {
            nsView.player?.isMuted = isMuted
            if autoplay {
                nsView.player?.play()
            }
        }
    }

    private func configure(on view: AVPlayerLayerHostView, context: Context) {
        var didStartAccess = false
        if url.startAccessingSecurityScopedResource() {
            didStartAccess = true
        }

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        let tap = PlayerAudioTap(playerItem: item)
        layerManager.registerPiPAudioTap(for: layerId, tap: tap)

        let player = AVQueuePlayer(items: [item])
        var looper: AVPlayerLooper?
        if loop {
            looper = AVPlayerLooper(player: player, templateItem: item)
        }
        player.isMuted = isMuted
        view.player = player

        if autoplay {
            player.play()
        }

        // Optional: keep ticking to avoid sleep while offscreen
        let timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { _ in }

        context.coordinator.player = player
        context.coordinator.looper = looper
        context.coordinator.audioTap = tap
        context.coordinator.timeObserver = timeObserver
        context.coordinator.securityScoped = didStartAccess
        context.coordinator.url = url
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var audioTap: PlayerAudioTap?
        var timeObserver: Any?
        var securityScoped: Bool = false
        var url: URL?

        deinit {
            if let p = player, let obs = timeObserver {
                p.removeTimeObserver(obs)
            }
            if securityScoped, let u = url {
                u.stopAccessingSecurityScopedResource()
            }
            audioTap = nil
            looper = nil
            player = nil
        }
    }
}