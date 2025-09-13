import SwiftUI
import AppKit

struct MediaItemView: View {
    let mediaFile: MediaFile
    @ObservedObject var thumbnailManager: MediaThumbnailManager
    let onMediaSelected: (MediaFile) -> Void
    let onMediaDropped: (MediaFile, CGPoint) -> Void
    @EnvironmentObject var layerManager: LayerStackManager
    
    @State private var thumbnail: NSImage?
    @State private var isDragging = false
    @State private var isHovered = false
    
    var body: some View {
        ZStack {
            VStack(spacing: TahoeDesign.Spacing.xs) {
                // Thumbnail or icon with enhanced glass styling
                ZStack {
                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(TahoeDesign.Colors.surfaceMedium)
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
                    
                    // Type badge overlay with glass styling
                    VStack {
                        HStack {
                            Spacer()
                            Text(mediaFile.fileType.displayName)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, TahoeDesign.Spacing.xs)
                                .padding(.vertical, 2)
                                .statusIndicator(color: mediaFile.fileType.badgeColor, isActive: true)
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
                                    .padding(.horizontal, TahoeDesign.Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.xs, style: .continuous))
                            }
                        }
                        .padding(2)
                    }
                }
                .frame(width: 80, height: 45)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.sm, style: .continuous))
                
                // File name with improved typography
                Text(mediaFile.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 30)
            }
            .padding(TahoeDesign.Spacing.sm)
        }
        .frame(width: 100, height: 100)
        .liquidGlassPanel(
            material: isHovered || isDragging ? .regularMaterial : .ultraThinMaterial,
            cornerRadius: TahoeDesign.CornerRadius.md,
            shadowIntensity: isHovered || isDragging ? .medium : .light
        )
        .scaleEffect(isDragging ? 0.95 : (isHovered ? 1.02 : 1.0))
        .animation(TahoeAnimations.quickEasing, value: isDragging)
        .animation(TahoeAnimations.quickEasing, value: isHovered)
        .onHover { hovering in
            withAnimation(TahoeAnimations.quickEasing) {
                isHovered = hovering
            }
        }
        .onAppear {
            Task {
                thumbnail = await thumbnailManager.getThumbnail(for: mediaFile)
            }
        }
        .onTapGesture {
            print("🎬 MediaItemView: CLICKED on media file: \(mediaFile.name)")
            print("🎬 MediaItemView: About to call onMediaSelected callback")
            
            // Add haptic feedback
            let feedbackGenerator = NSHapticFeedbackManager.defaultPerformer
            feedbackGenerator.perform(.generic, performanceTime: .now)
            
            onMediaSelected(mediaFile)
            print("✅ MediaItemView: onMediaSelected callback completed")
        }
        .draggable(mediaFile) {
            // Enhanced drag preview with glass styling
            VStack(spacing: TahoeDesign.Spacing.xs) {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 34)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.xs, style: .continuous))
                } else {
                    Rectangle()
                        .fill(TahoeDesign.Colors.surfaceMedium)
                        .frame(width: 60, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: TahoeDesign.CornerRadius.xs, style: .continuous))
                        .overlay(
                            Image(systemName: mediaFile.fileType.icon)
                                .font(.body)
                                .foregroundColor(.secondary)
                        )
                }
                
                Text(mediaFile.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(TahoeDesign.Spacing.sm)
            .liquidGlassPanel(
                material: .thickMaterial,
                cornerRadius: TahoeDesign.CornerRadius.md,
                shadowIntensity: .heavy
            )
        }
        .contextMenu {
            Button("Load to Preview") {
                let feedbackGenerator = NSHapticFeedbackManager.defaultPerformer
                feedbackGenerator.perform(.generic, performanceTime: .now)
                onMediaSelected(mediaFile)
            }
            Divider()
            Button("Add as Picture-in-Picture") {
                let feedbackGenerator = NSHapticFeedbackManager.defaultPerformer
                feedbackGenerator.perform(.generic, performanceTime: .now)
                let defaultCenter = CGPoint(x: 0.82, y: 0.82)
                layerManager.addMediaLayer(file: mediaFile, centerNorm: defaultCenter)
            }
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