import SwiftUI

struct MultiviewTile: View {
    let tile: MultiviewViewModel.Tile
    let image: NSImage?
    let isProgram: Bool
    let isPreview: Bool
    
    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.8))
            if let nsImage = image {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .clipped()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "video")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(tile.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(8)
            }
            
            VStack {
                HStack {
                    Text(tile.name)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(6)
                    Spacer()
                }
                Spacer()
            }
            
            if isProgram || isPreview {
                RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.sm, style: .continuous)
                    .stroke(isProgram ? TahoeDesign.Colors.program : TahoeDesign.Colors.preview, lineWidth: isProgram ? 3 : 2)
                    .shadow(color: (isProgram ? TahoeDesign.Colors.program : TahoeDesign.Colors.preview).opacity(0.6), radius: 6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.sm, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
        .aspectRatio(16.0/9.0, contentMode: .fit)
    }
}

struct MultiviewTileLive: View {
    let tile: MultiviewViewModel.Tile
    @ObservedObject var feed: CameraFeed
    let isProgram: Bool
    let isPreview: Bool
    
    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.8))
            if let nsImage = feed.previewNSImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .clipped()
            } else {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(tile.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(8)
            }
            
            VStack {
                HStack {
                    Text(tile.name)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(6)
                    Spacer()
                }
                Spacer()
            }
            
            if isProgram || isPreview {
                RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.sm, style: .continuous)
                    .stroke(isProgram ? TahoeDesign.Colors.program : TahoeDesign.Colors.preview, lineWidth: isProgram ? 3 : 2)
                    .shadow(color: (isProgram ? TahoeDesign.Colors.program : TahoeDesign.Colors.preview).opacity(0.6), radius: 6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.sm, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
        .aspectRatio(16.0/9.0, contentMode: .fit)
    }
}