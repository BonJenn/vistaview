import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var productionManager = UnifiedProductionManager()
    @State private var mediaFiles: [MediaFile] = []
    
    @State private var isDropTarget = false
    
    var body: some View {
        HSplitView {
            // Left Pane: VJ Controls
            VStack {
                VJPreviewProgramPane(
                    previewSource: productionManager.previewProgramManager.previewSource,
                    programSource: productionManager.previewProgramManager.programSource,
                    onTake: {
                        productionManager.previewProgramManager.take()
                    },
                    productionManager: productionManager
                )
                
                MediaSourceView()
            }
            .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity)
            
            // Right Pane
            VStack {
                Text("Settings & Controls")
                    .font(.headline)
                Spacer()
            }
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
        }
        .environmentObject(productionManager)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            handleDrop(providers: providers)
        }
        .overlay(
            isDropTarget ? Color.blue.opacity(0.3) : Color.clear
        )
    }
    
    @ViewBuilder
    private func MediaSourceView() -> some View {
        VStack(alignment: .leading) {
            Text("Media Sources")
                .font(.headline)
                .padding([.top, .leading])
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 12)], spacing: 12) {
                    ForEach(mediaFiles) { file in
                        MediaItemView(
                            mediaFile: file,
                            thumbnailManager: productionManager.mediaThumbnailManager,
                            onMediaSelected: { selectedFile in
                                let mediaSource = selectedFile.asContentSource()
                                productionManager.previewProgramManager.loadToPreview(mediaSource)
                            },
                            onMediaDropped: { _, _ in }
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    print("Failed to get URL from drop item.")
                    return
                }
                
                DispatchQueue.main.async {
                    addMediaFile(from: url)
                }
            }
        }
        return true
    }
    
    private func addMediaFile(from url: URL) {
        let fileType = determineFileType(from: url)
        
        Task {
            // We don't need to start/stop access here because we're just getting metadata.
            // The MediaFile init will store the bookmark for later use.
            let asset = AVURLAsset(url: url)
            var durationInSeconds: TimeInterval?
            
            do {
                let duration = try await asset.load(.duration)
                durationInSeconds = CMTimeGetSeconds(duration)
            } catch {
                print("Could not load duration for \(url.lastPathComponent): \(error.localizedDescription)")
            }

            let newMediaFile = MediaFile(
                name: url.lastPathComponent,
                url: url,
                fileType: fileType,
                duration: durationInSeconds
            )
            
            DispatchQueue.main.async {
                if !mediaFiles.contains(where: { $0.id == newMediaFile.id }) {
                    mediaFiles.append(newMediaFile)
                }
            }
        }
    }
    
    private func determineFileType(from url: URL) -> MediaFile.MediaFileType {
        let pathExtension = url.pathExtension.lowercased()
        let videoTypes = ["mov", "mp4", "m4v"]
        let audioTypes = ["mp3", "m4a", "wav", "aac"]
        let imageTypes = ["jpg", "jpeg", "png", "heic", "gif"]
        
        if videoTypes.contains(pathExtension) {
            return .video
        } else if audioTypes.contains(pathExtension) {
            return .audio
        } else if imageTypes.contains(pathExtension) {
            return .image
        }
        return .video
    }
}