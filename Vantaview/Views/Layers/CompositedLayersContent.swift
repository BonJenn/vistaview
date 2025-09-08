import SwiftUI
import AppKit

struct CompositedLayersContent: View {
    @EnvironmentObject var layerManager: LayerStackManager
    @ObservedObject var productionManager: UnifiedProductionManager

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(layerManager.layers.sorted(by: { $0.zIndex < $1.zIndex })) { model in
                    if model.isEnabled {
                        layerView(for: model, canvasSize: size)
                            .frame(
                                width: size.width * model.sizeNorm.width,
                                height: size.height * model.sizeNorm.height
                            )
                            .position(
                                x: size.width * model.centerNorm.x,
                                y: size.height * model.centerNorm.y
                            )
                            .rotationEffect(.degrees(Double(model.rotationDegrees)))
                            .opacity(Double(model.opacity))
                            .clipped()
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func layerView(for model: CompositedLayer, canvasSize: CGSize) -> some View {
        switch model.source {
        case .camera(let feedId):
            if let feed = productionManager.cameraFeedManager.activeFeeds.first(where: { $0.id == feedId }) {
                CameraFeedCALayerView(feed: feed)
                     .background(Color.black)
            } else {
                Color.black.overlay(
                    Text("Camera offline").font(.caption).foregroundColor(.white)
                )
            }

        case .media(let file):
            switch file.fileType {
            case .image:
                if let img = NSImage(contentsOf: file.url) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .background(Color.black)
                } else {
                    Color.black.overlay(
                        Text("Image not found").font(.caption).foregroundColor(.white)
                    )
                }
            case .video:
                LayerAVPlayerView(url: file.url, isMuted: true, autoplay: true, loop: true, layerId: model.id)
                    .environmentObject(layerManager)
                    .background(Color.black)
            case .audio:
                Color.clear
            }
        }
    }
}// touch
