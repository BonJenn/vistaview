import SwiftUI

struct CameraFeedLiveLayerView: View {
    @ObservedObject var feed: CameraFeed

    var body: some View {
        ZStack {
            if let cg = feed.previewImage {
                Image(decorative: cg, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let ns = feed.previewNSImage {
                Image(nsImage: ns)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black.overlay(
                    VStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Waiting for camera…")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                )
            }
        }
        .clipped()
    }
}