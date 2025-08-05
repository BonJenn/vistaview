import SwiftUI
import AppKit

struct MediaItemView: View {
    let mediaFile: MediaFile
    @ObservedObject var thumbnailManager: MediaThumbnailManager
    let onMediaSelected: (MediaFile) -> Void
    let onMediaDropped: (MediaFile, CGPoint) -> Void
    
    @State private var thumbnail: NSImage?
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            // Background with hover effect
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(isDragging ? 0.3 : 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.blue.opacity(isDragging ? 0.5 : 0.2), lineWidth: isDragging ? 2 : 1)
                )
            
            VStack(spacing: 4) {
                // Thumbnail or icon
                ZStack {
                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                VStack(spacing: 2) {
                                    Image(systemName: mediaFile.fileType.icon)
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    Text("Loading...")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                    
                    // Type badge overlay
                    VStack {
                        HStack {
                            Spacer()
                            Text(mediaFile.fileType.displayName)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(mediaFile.fileType.badgeColor.opacity(0.8))
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                    .padding(2)
                    
                    // Duration overlay for videos
                    if mediaFile.fileType == .video, let duration = mediaFile.duration {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(formatDuration(duration))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(2)
                    }
                }
                .frame(width: 80, height: 45)
                .clipped()
                .cornerRadius(4)
                
                // File name
                Text(mediaFile.name)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 30)
            }
            .padding(6)
        }
        .frame(width: 100, height: 100)
        .onAppear {
            Task {
                thumbnail = await thumbnailManager.getThumbnail(for: mediaFile)
            }
        }
        .onTapGesture {
            print("🎬 MediaItemView: CLICKED on media file: \(mediaFile.name)")
            print("🎬 MediaItemView: About to call onMediaSelected callback")
            onMediaSelected(mediaFile)
            print("✅ MediaItemView: onMediaSelected callback completed")
        }
        .draggable(mediaFile) {
            // Drag preview
            VStack(spacing: 4) {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 34)
                        .clipped()
                        .cornerRadius(4)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 34)
                        .cornerRadius(4)
                        .overlay(
                            Image(systemName: mediaFile.fileType.icon)
                                .font(.body)
                                .foregroundColor(.secondary)
                        )
                }
                
                Text(mediaFile.name)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(8)
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension MediaFile: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: MediaFile.self, contentType: .data)
    }
}