import SwiftUI

struct CameraFeedLiveLayerView: View {
    @ObservedObject var feed: CameraFeed

    var body: some View {
        ZStack {
            // Prefer the high-FPS display layer tied to sample buffers
            CameraFeedDisplayLayerView(feed: feed)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .foregroundColor(.white.opacity(0.9))
                        Text(feed.connectionStatus.displayText)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(6)
                    .padding(6)
                }
                .overlay {
                    if feed.currentSampleBuffer == nil && feed.previewImage == nil && feed.previewNSImage == nil {
                        VStack(spacing: 4) {
                            ProgressView().scaleEffect(0.6)
                            Text("Waiting for camera…")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
        }
        .clipped()
    }
}