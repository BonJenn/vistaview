import SwiftUI
import HaishinKit
import AVFoundation
import AVKit
import Metal
import MetalKit
import CoreImage
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ProductionMode {
    case live, virtual
}

struct ContentView: View {
    @StateObject private var productionManager = UnifiedProductionManager()
    @State private var productionMode: ProductionMode = .live
    @State private var showingStudioSelector = false
    @State private var showingVirtualCameraDemo = false
    
    // Live Production States
    @State private var rtmpURL = "rtmp://live.twitch.tv/live/"
    @State private var streamKey = ""
    @State private var selectedTab = 0
    @State private var showingFilePicker = false
    @State private var mediaFiles: [MediaFile] = []
    @State private var selectedPlatform = "Twitch"
    
    // PERFORMANCE: Add UI update throttling
    @State private var lastUIUpdate = Date()
    private let uiUpdateThreshold: TimeInterval = 1.0/20.0 // 20fps UI updates
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            TopToolbarView(
                productionManager: productionManager,
                productionMode: $productionMode,
                showingStudioSelector: $showingStudioSelector,
                showingVirtualCameraDemo: $showingVirtualCameraDemo
            )
            
            Divider()
            
            // Main Content Area
            Group {
                switch productionMode {
                case .virtual:
                    VirtualProductionView()
                        .environmentObject(productionManager.studioManager)
                        .environmentObject(productionManager)
                case .live:
                    FinalCutProStyleView(
                        productionManager: productionManager,
                        rtmpURL: $rtmpURL,
                        streamKey: $streamKey,
                        selectedTab: $selectedTab,
                        showingFilePicker: $showingFilePicker,
                        mediaFiles: $mediaFiles,
                        selectedPlatform: $selectedPlatform
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingStudioSelector) {
            StudioSelectorSheet(productionManager: productionManager)
        }
        .sheet(isPresented: $showingVirtualCameraDemo) {
            VirtualCameraDemoView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .task {
            await requestPermissions()
            await productionManager.initialize()
            print("🔧 ContentView: Validating production manager initialization...")
            validateProductionManagerInitialization()
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.movie, .image, .audio],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    private func requestPermissions() async {
        let videoPermission = await AVCaptureDevice.requestAccess(for: .video)
        let audioPermission = await AVCaptureDevice.requestAccess(for: .audio)
        print("Video permission: \(videoPermission), Audio permission: \(audioPermission)")
    }
    
    private func validateProductionManagerInitialization() {
        print("🔧 Validating production manager components...")
        
        // Re-set production manager to ensure proper initialization
        print("🔧 Re-setting production manager to ensure proper initialization...")
        productionManager.externalDisplayManager.setProductionManager(productionManager)
        
        // Validate key components
        print("✅ CameraFeedManager: \(productionManager.cameraFeedManager != nil ? "OK" : "MISSING")")
        print("✅ EffectManager: \(productionManager.effectManager != nil ? "OK" : "MISSING")")
        print("✅ OutputMappingManager: \(productionManager.outputMappingManager != nil ? "OK" : "MISSING")")
        print("✅ ExternalDisplayManager: \(productionManager.externalDisplayManager != nil ? "OK" : "MISSING")")
        print("✅ PreviewProgramManager: \(productionManager.previewProgramManager != nil ? "OK" : "MISSING")")
        
        // Validate Metal device - metalDevice is not optional, so we can access it directly
        let metalDevice = productionManager.effectManager.metalDevice
        print("✅ Metal Device: \(metalDevice.name)")
        
        print("🔧 Production manager validation complete")
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let fileType: MediaFile.MediaFileType
                let fileExtension = url.pathExtension.lowercased()
                
                switch fileExtension {
                case "mp4", "mov", "avi", "mkv", "webm":
                    fileType = .video
                case "mp3", "wav", "aac", "m4a":
                    fileType = .audio
                case "jpg", "jpeg", "png", "gif", "tiff":
                    fileType = .image
                default:
                    fileType = .video // Default to video
                }
                
                let mediaFile = MediaFile(
                    name: url.lastPathComponent,
                    url: url,
                    fileType: fileType
                )
                mediaFiles.append(mediaFile)
            }
        case .failure(let error):
            print("File import error: \(error)")
        }
    }
}

// MARK: - Top Toolbar

struct TopToolbarView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var productionMode: ProductionMode
    @Binding var showingStudioSelector: Bool
    @Binding var showingVirtualCameraDemo: Bool
    
    var body: some View {
        HStack {
            // Studio Selector
            HStack {
                Image(systemName: "building.2.crop.circle")
                    .foregroundColor(.blue)
                
                Button(productionManager.currentStudioName) {
                    showingStudioSelector = true
                }
                .font(.headline)
                .foregroundColor(.primary)
                
                if productionManager.hasUnsavedChanges {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
            
            Spacer()
            
            // Mode Switcher
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        productionMode = .virtual
                        productionManager.switchToVirtualMode()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "cube.transparent.fill")
                        Text("Virtual Studio")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(productionMode == .virtual ? Color.blue : Color.clear)
                    .foregroundColor(productionMode == .virtual ? .white : .primary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        productionMode = .live
                        productionManager.switchToLiveMode()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "video.circle.fill")
                        Text("Live Production")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(productionMode == .live ? Color.blue : Color.clear)
                    .foregroundColor(productionMode == .live ? .white : .primary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            Spacer()
            
            // Status Indicators
            HStack(spacing: 16) {
                if productionManager.isVirtualStudioActive {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Virtual Studio")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                if productionMode == .live {
                    HStack {
                        Circle()
                            .fill(productionManager.streamingViewModel.isPublishing ? Color.red : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(productionManager.streamingViewModel.isPublishing ? "LIVE" : "OFFLINE")
                            .font(.caption2)
                            .foregroundColor(productionManager.streamingViewModel.isPublishing ? .red : .secondary)
                    }
                }
                
                Button(action: {}) {
                    Image(systemName: "gear")
                }
                
                Button(action: { showingVirtualCameraDemo = true }) {
                    Image(systemName: "video.3d")
                }
                .help("Virtual Camera Demo")
            }
        }
        .padding()
        .background(TahoeDesign.Colors.surfaceLight)
    }
}

// MARK: - Final Cut Pro Style Layout

struct FinalCutProStyleView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var rtmpURL: String
    @Binding var streamKey: String
    @Binding var selectedTab: Int
    @Binding var showingFilePicker: Bool
    @Binding var mediaFiles: [MediaFile]
    @Binding var selectedPlatform: String
    
    var body: some View {
        HSplitView {
            // Left Panel - Sources
            SourcesPanel(
                productionManager: productionManager,
                selectedTab: $selectedTab,
                mediaFiles: $mediaFiles,
                showingFilePicker: $showingFilePicker
            )
            .frame(minWidth: 280, maxWidth: 400)
            .liquidGlassPanel(material: .regularMaterial, cornerRadius: 0, shadowIntensity: .light)
            
            // Center Panel - Preview/Program like Final Cut Pro
            VStack(spacing: 0) {
                // Main Preview/Program Area
                PreviewProgramCenterView(
                    productionManager: productionManager,
                    mediaFiles: $mediaFiles
                )
                
                // Timeline/Layers Control (bottom strip)
                TimelineControlsView(productionManager: productionManager)
                    .frame(height: 120)
                    .background(Color.black.opacity(0.05))
            }
            .frame(minWidth: 600)
            
            // Right Panel - Output & Streaming Controls
            VStack(spacing: 0) {
                // Effects List Panel (top section)
                EffectsListPanel(
                    effectManager: productionManager.effectManager,
                    previewProgramManager: productionManager.previewProgramManager
                )
                .frame(height: 180)
                
                Divider()
                
                // Output Mapping Controls (middle section - flexible height with max limit)
                OutputMappingControlsView(
                    outputMappingManager: productionManager.outputMappingManager,
                    externalDisplayManager: productionManager.externalDisplayManager
                )
                .frame(maxHeight: 300)
                
                Divider()
                
                // Output Controls (bottom section - takes remaining space)
                OutputControlsPanel(
                    productionManager: productionManager,
                    rtmpURL: $rtmpURL,
                    streamKey: $streamKey,
                    selectedPlatform: $selectedPlatform
                )
                .frame(minHeight: 200)
            }
            .frame(minWidth: 280, maxWidth: 350)
            .liquidGlassPanel(material: .regularMaterial, cornerRadius: 0, shadowIntensity: .light)
        }
    }
}

// MARK: - Preview/Program Center View (Optimized)

struct PreviewProgramCenterView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var mediaFiles: [MediaFile]
    
    // PERFORMANCE: Add UI update throttling for high-frequency updates
    @State private var lastUIUpdate = Date()
    private let uiUpdateThreshold: TimeInterval = 1.0/15.0 // 15fps for monitor updates
    
    var body: some View {
        VStack(spacing: 8) {
            // Main Preview/Program Display - Stacked Vertically
            VStack(spacing: 8) {
                // Preview Monitor (Top - Next Up)
                VStack(spacing: 4) {
                    HStack {
                        Text("PREVIEW")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                        Spacer()
                        
                        // Show media name if media is loaded
                        if case .media(let mediaFile, _) = productionManager.previewProgramManager.previewSource {
                            Text(mediaFile.name)
                                .font(.caption2)
                                .foregroundColor(.yellow)
                                .lineLimit(1)
                        }
                    }
                    
                    // SIMPLER: Direct monitor view without complex caching
                    SimplePreviewMonitorView(
                        productionManager: productionManager
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(Color.black)
                    .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.yellow, lineWidth: 2)
                    )
                    
                    // Media controls for preview (if media is loaded)
                    if case .media(let mediaFile, _) = productionManager.previewProgramManager.previewSource {
                        // Only show controls for video and audio, not images
                        if mediaFile.fileType == .video || mediaFile.fileType == .audio {
                            ComprehensiveMediaControls(
                                previewProgramManager: productionManager.previewProgramManager,
                                isPreview: true,
                                mediaFile: mediaFile
                            )
                        }
                    }
                }
                
                // Program Monitor (Bottom - Live Output)
                VStack(spacing: 4) {
                    HStack {
                        Text("PROGRAM")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                        Spacer()
                        
                        // Show media name if media is loaded
                        if case .media(let mediaFile, _) = productionManager.previewProgramManager.programSource {
                            Text(mediaFile.name)
                                .font(.caption2)
                                .foregroundColor(.red)
                                .lineLimit(1)
                        }
                    }
                    
                    // SIMPLER: Direct monitor view without complex caching
                    SimpleProgramMonitorView(
                        productionManager: productionManager
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(Color.black)
                    .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red, lineWidth: 2)
                    )
                    
                    // Media controls for program (if media is loaded)
                    if case .media(let mediaFile, _) = productionManager.previewProgramManager.programSource {
                        if mediaFile.fileType == .video || mediaFile.fileType == .audio {
                            ComprehensiveMediaControls(
                                previewProgramManager: productionManager.previewProgramManager,
                                isPreview: false,
                                mediaFile: mediaFile
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            
            // TAKE and AUTO buttons
            HStack(spacing: 12) {
                Spacer()
                
                Button("TAKE") {
                    // Move current preview source to program using the correct method name
                    print("✂️ TAKE BUTTON CLICKED!")
                    print("✂️ TAKE DEBUG: Current preview source: \(productionManager.previewProgramManager.previewSource)")
                    print("✂️ TAKE DEBUG: Current program source: \(productionManager.previewProgramManager.programSource)")
                    
                    // Check if preview source exists
                    if productionManager.previewProgramManager.previewSource == .none {
                        print("✂️ TAKE ERROR: No preview source to take!")
                    } else {
                        print("✂️ TAKE: About to call take() method...")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            productionManager.previewProgramManager.take()
                        }
                        print("✂️ TAKE: Called take() method")
                        DispatchQueue.main.async {
                            print("✂️ TAKE AFTER: Preview source: \(productionManager.previewProgramManager.previewSource)")
                            print("✂️ TAKE AFTER: Program source: \(productionManager.previewProgramManager.programSource)")
                            productionManager.previewProgramManager.objectWillChange.send()
                            productionManager.objectWillChange.send()
                        }
                    }
                }
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(productionManager.previewProgramManager.previewSource == .none ? Color.gray : Color.red)
                .foregroundColor(.white)
                .cornerRadius(6)
                .disabled(productionManager.previewProgramManager.previewSource == .none)
                
                Button("AUTO") {
                    print("🔄 AUTO: Auto-transitioned preview to program")
                    withAnimation(.easeInOut(duration: 1.0)) {
                        productionManager.previewProgramManager.transition(duration: 1.0)
                    }
                }
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(productionManager.previewProgramManager.previewSource == .none ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(6)
                .disabled(productionManager.previewProgramManager.previewSource == .none)
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .padding()
    }
}

// MARK: - Simplified Monitor Views (No Caching Issues)

struct SimplePreviewMonitorView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    private var effectCount: Int {
        productionManager.previewProgramManager.getPreviewEffectChain()?.effects.count ?? 0
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            switch productionManager.previewProgramManager.previewSource {
            case .camera(let cameraFeed):
                OptimizedPreviewCameraView(
                    cameraFeed: cameraFeed,
                    productionManager: productionManager,
                    effectCount: effectCount
                )
                
            case .media(let mediaFile, let player):
                if mediaFile.fileType == .image {
                    // Display image directly from previewImage
                    if let previewImageCG = productionManager.previewProgramManager.previewImage {
                        Image(decorative: previewImageCG, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .id("preview-image-\(mediaFile.id)")
                    } else {
                        MediaLoadingView(mediaFile: mediaFile, isPreview: true)
                    }
                } else if let actualPlayer = productionManager.previewProgramManager.previewPlayer {
                    // Handle video/audio with player
                    PersistentVideoPlayerView(
                        player: actualPlayer,
                        mediaFile: mediaFile,
                        isPreview: true
                    )
                    .id("preview-player-\(actualPlayer.description)")
                } else {
                    MediaLoadingView(mediaFile: mediaFile, isPreview: true)
                }
                
            case .virtual(let virtualCamera):
                VirtualCameraView(camera: virtualCamera, isPreview: true)
                
            case .none:
                NoSourceView(isPreview: true)
            }
            
            // Effect count indicator
            if effectCount > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("FX: \(effectCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
                            .padding(4)
                    }
                }
            }
        }
        .dropDestination(for: EffectDragItem.self) { items, location in
            guard let item = items.first else { return false }
            Task { @MainActor in
                productionManager.previewProgramManager.addEffectToPreview(item.effectType)
            }
            return true
        } isTargeted: { targeted in
            // Add visual feedback for drag targeting
        }
    }
}

struct SimpleProgramMonitorView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    private var effectCount: Int {
        productionManager.previewProgramManager.getProgramEffectChain()?.effects.count ?? 0
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            switch productionManager.previewProgramManager.programSource {
            case .camera(let cameraFeed):
                OptimizedProgramCameraView(
                    cameraFeed: cameraFeed,
                    productionManager: productionManager,
                    effectCount: effectCount
                )
                
            case .media(let mediaFile, let player):
                if mediaFile.fileType == .image {
                    // Display image directly from programImage
                    if let programImageCG = productionManager.previewProgramManager.programImage {
                        Image(decorative: programImageCG, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .id("program-image-\(mediaFile.id)")
                    } else {
                        MediaLoadingView(mediaFile: mediaFile, isPreview: false)
                    }
                } else if let actualPlayer = productionManager.previewProgramManager.programPlayer {
                    // Handle video/audio with player
                    PersistentVideoPlayerView(
                        player: actualPlayer,
                        mediaFile: mediaFile,
                        isPreview: false
                    )
                    .id("program-player-\(actualPlayer.description)")
                } else {
                    MediaLoadingView(mediaFile: mediaFile, isPreview: false)
                }
                
            case .virtual(let virtualCamera):
                VirtualCameraView(camera: virtualCamera, isPreview: false)
                
            case .none:
                NoSourceView(isPreview: false)
            }
            
            // Effect count indicator
            if effectCount > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("FX: \(effectCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
                            .padding(4)
                    }
                }
            }
        }
        .dropDestination(for: EffectDragItem.self) { items, location in
            guard let item = items.first else { return false }
            Task { @MainActor in
                productionManager.previewProgramManager.addEffectToProgram(item.effectType)
            }
            return true
        } isTargeted: { targeted in
            // Add visual feedback for drag targeting
        }
    }
}

struct PersistentVideoPlayerView: View {
    let player: AVPlayer
    let mediaFile: MediaFile
    let isPreview: Bool
    
    var body: some View {
        FrameBasedVideoPlayerView(player: player, isPreview: isPreview)
            .id("persistent-video-\(mediaFile.id)-\(isPreview ? "preview" : "program")")
    }
}

// MARK: - Sources Panel

struct SourcesPanel: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var selectedTab: Int
    @Binding var mediaFiles: [MediaFile]
    @Binding var showingFilePicker: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(["Cameras", "Media", "Virtual", "Effects"].enumerated()), id: \.offset) { index, tab in
                    Button(action: {
                        selectedTab = index
                        print("📱 Selected tab: \(index) - \(tab)")
                    }) {
                        Text(tab)
                            .font(.caption)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(selectedTab == index ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(selectedTab == index ? .white : .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                Spacer()
            }
            .background(Color.gray.opacity(0.1))
            
            Group {
                switch selectedTab {
                case 0:
                    CamerasSourceView(
                        productionManager: productionManager
                    )
                case 1:
                    MediaSourceView(mediaFiles: $mediaFiles, showingFilePicker: $showingFilePicker)
                        .environmentObject(productionManager)
                case 2:
                    VirtualSourceView(productionManager: productionManager)
                case 3:
                    EffectsSourceView(effectManager: productionManager.effectManager)
                default:
                    CamerasSourceView(
                        productionManager: productionManager
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct MediaSourceView: View {
    @Binding var mediaFiles: [MediaFile]
    @Binding var showingFilePicker: Bool
    @EnvironmentObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Media Library")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { showingFilePicker = true }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.blue)
                }
            }
            if mediaFiles.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "folder.badge.plus")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Media Files")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("Add Files") {
                        showingFilePicker = true
                    }
                    .buttonStyle(LiquidGlassButton(accentColor: .accentColor, size: .medium))
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100), spacing: 12)
                    ], spacing: 12) {
                        ForEach(mediaFiles) { file in
                            MediaItemView(
                                mediaFile: file,
                                thumbnailManager: productionManager.mediaThumbnailManager,
                                onMediaSelected: { selectedFile in
                                    print("🎬 MediaSourceView: Media file selected: \(selectedFile.name)")
                                    print("🎬 MediaSourceView: Loading to preview...")
                                    
                                    let mediaSource = selectedFile.asContentSource()
                                    productionManager.previewProgramManager.loadToPreview(mediaSource)
                                    
                                    print("✅ MediaSourceView: Media loaded to preview successfully")
                                    
                                    // Force UI updates to ensure preview monitor updates immediately
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        productionManager.previewProgramManager.objectWillChange.send()
                                        productionManager.objectWillChange.send()
                                    }
                                },
                                onMediaDropped: { droppedFile, location in
                                    // Handle drop - could be dropped on preview or program pane
                                    print("Media dropped at location: \(location)")
                                }
                            ) 
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            Spacer()
        }
        .padding()
    }
}

struct CamerasSourceView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Camera Sources")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Refresh") {
                    Task {
                        await productionManager.cameraFeedManager.forceRefreshDevices()
                    }
                }
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .statusIndicator(color: TahoeDesign.Colors.virtual, isActive: true)
                .foregroundColor(.blue)
                .cornerRadius(4)
            }
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(productionManager.cameraFeedManager.availableDevices, id: \.id) { device in
                    CameraDeviceButton(device: device, productionManager: productionManager)
                }
            }
            if !productionManager.cameraFeedManager.activeFeeds.isEmpty {
                Divider()
                HStack {
                    Text("Live Camera Feeds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(productionManager.cameraFeedManager.activeFeeds.count)")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .statusIndicator(color: TahoeDesign.Colors.live, isActive: true)
                        .cornerRadius(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                let columns = [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(productionManager.cameraFeedManager.activeFeeds) { feed in
                        LiveCameraFeedButton(
                            feed: feed,
                            productionManager: productionManager
                        )
                    }
                }
            }
            Spacer()
        }
        .padding()
        .onAppear {
            Task {
                await productionManager.cameraFeedManager.getAvailableDevices()
            }
        }
    }
}

struct CameraDeviceButton: View {
    let device: CameraDevice
    @ObservedObject var productionManager: UnifiedProductionManager
    
    private var hasActiveFeed: Bool {
        productionManager.cameraFeedManager.activeFeeds.contains { $0.device.deviceID == device.deviceID }
    }
    
    var body: some View {
        Button(action: {
            if hasActiveFeed {
                if let feed = productionManager.cameraFeedManager.activeFeeds.first(where: { $0.device.deviceID == device.deviceID }) {
                    productionManager.cameraFeedManager.stopFeed(feed)
                }
            } else {
                Task {
                    if let newFeed = await productionManager.cameraFeedManager.startFeed(for: device) {
                        print("Started camera feed: \(newFeed.device.displayName)")
                        await MainActor.run {
                            newFeed.objectWillChange.send()
                            productionManager.cameraFeedManager.objectWillChange.send()
                            productionManager.objectWillChange.send()
                        }
                    }
                }
            }
        }) {
            VStack {
                Rectangle()
                    .fill(hasActiveFeed ? Color.green.opacity(0.3) : (device.isAvailable ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2)))
                    .frame(height: 60)
                    .overlay(
                        VStack(spacing: 2) {
                            Image(systemName: device.icon)
                                .font(.title2)
                            Text(hasActiveFeed ? "STOP" : (device.isAvailable ? "START" : "BUSY"))
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(hasActiveFeed ? .green : (device.isAvailable ? .blue : .gray))
                    )
                    .cornerRadius(6)
                Text(device.displayName)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!device.isAvailable && !hasActiveFeed)
    }
}

struct LiveCameraFeedButton: View {
    @ObservedObject var feed: CameraFeed
    @ObservedObject var productionManager: UnifiedProductionManager
    
    private var isInPreview: Bool {
        if case .camera(let previewFeed) = productionManager.previewProgramManager.previewSource {
            return previewFeed.id == feed.id
        }
        return false
    }
    
    private var isInProgram: Bool {
        if case .camera(let programFeed) = productionManager.previewProgramManager.programSource {
            return programFeed.id == feed.id
        }
        return false
    }
    
    var body: some View {
        Button(action: {
            let cameraSource = feed.asContentSource()
            productionManager.previewProgramManager.loadToPreview(cameraSource)
            DispatchQueue.main.async {
                feed.objectWillChange.send()
                productionManager.previewProgramManager.objectWillChange.send()
                productionManager.objectWillChange.send()
            }
        }) {
            VStack(spacing: 4) {
                if let nsImage = feed.previewNSImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 45)
                        .background(Color.black)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    isInProgram ? Color.red : (isInPreview ? Color.yellow : Color.gray.opacity(0.3)), 
                                    lineWidth: (isInProgram || isInPreview) ? 2 : 1
                                )
                        )
                        .id("camera-preview-\(feed.id)-\(feed.frameCount)") // Force updates when frame changes
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .frame(maxWidth: .infinity, maxHeight: 45)
                        .overlay(
                            VStack(spacing: 2) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.5)
                                Text("Loading...")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                if feed.frameCount > 0 {
                                    Text("Frame: \(feed.frameCount)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Text(feed.connectionStatus.displayText)
                                    .font(.caption2)
                                    .foregroundColor(feed.connectionStatus.color)
                            }
                        )
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    isInProgram ? Color.red : (isInPreview ? Color.yellow : Color.gray.opacity(0.3)), 
                                    lineWidth: (isInProgram || isInPreview) ? 2 : 1
                                )
                        )
                }
                
                VStack(spacing: 1) {
                    Text(feed.device.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    Text(isInProgram ? "ON AIR" : (isInPreview ? "IN PREVIEW" : "Tap for Preview"))
                        .font(.caption2)
                        .fontWeight((isInProgram || isInPreview) ? .bold : .regular)
                        .foregroundColor(isInProgram ? .red : (isInPreview ? .yellow : .secondary))
                    
                    HStack(spacing: 4) {
                        Text("●")
                            .font(.caption2)
                            .foregroundColor(feed.connectionStatus.color)
                        Text("\(feed.frameCount)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct VirtualSourceView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Virtual Sources")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(productionManager.availableVirtualCameras.count) cameras")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            if productionManager.availableVirtualCameras.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cube.transparent")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Virtual Cameras")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add cameras in Virtual Studio mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(productionManager.availableVirtualCameras, id: \.id) { camera in
                        VirtualCameraButton(camera: camera, productionManager: productionManager)
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}

struct VirtualCameraButton: View {
    let camera: VirtualCamera
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        Button(action: {
            productionManager.switchToVirtualCamera(camera)
        }) {
            VStack {
                Rectangle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(height: 80)
                    .overlay(
                        Image(systemName: "video.3d")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                    )
                    .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
                Text(camera.name)
                    .font(.headline)
                Text("Focal: \(Int(camera.focalLength))mm")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EffectsSourceView: View {
    @ObservedObject var effectManager: EffectManager
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Effects & Filters")
                .font(.caption)
                .foregroundColor(.secondary)
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(effectManager.effectsLibrary.availableEffects, id: \.id) { effect in
                        EffectDragButton(effect: effect)
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}

struct EffectDragButton: View {
    let effect: any VideoEffect
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(effect.category.color.opacity(0.2))
                .frame(height: 50)
                .overlay(
                    VStack(spacing: 2) {
                        Image(systemName: effect.icon)
                            .font(.title2)
                        Text(effect.name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundColor(effect.category.color)
                    }
                    .padding(4)
                )
                .cornerRadius(6)
                .scaleEffect(dragOffset != .zero ? 0.95 : 1.0)
                .shadow(color: effect.category.color.opacity(0.3), radius: dragOffset != .zero ? 8 : 2)
        }
        .draggable(EffectDragItem(effectType: effect.name)) {
            VStack(spacing: 2) {
                Image(systemName: effect.icon)
                    .font(.title2)
                Text(effect.name)
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .padding(8)
            .background(effect.category.color.opacity(0.8))
            .foregroundColor(.white)
            .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
            .shadow(radius: 4)
        }
    }
}

struct TimelineControlsView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Timeline & Layers")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    VStack {
                        Rectangle()
                            .fill(index == 0 ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                            .frame(height: 40)
                            .overlay(
                                Text("Layer \(index + 1)")
                                    .font(.caption2)
                                    .foregroundColor(index == 0 ? .blue : .secondary)
                            )
                            .cornerRadius(4)
                        Slider(value: .constant(index == 0 ? 1.0 : 0.0), in: 0...1)
                            .frame(width: 60)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

struct OutputControlsPanel: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var rtmpURL: String
    @Binding var streamKey: String
    @Binding var selectedPlatform: String
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Output Controls")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            ScrollView {
                VStack(spacing: 16) {
                    GroupBox("Live Streaming") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Platform:")
                                    .frame(width: 70, alignment: .leading)
                                Picker("Platform", selection: $selectedPlatform) {
                                    Text("YouTube").tag("YouTube")
                                    Text("Twitch").tag("Twitch")
                                    Text("Facebook").tag("Facebook")
                                    Text("Custom").tag("Custom")
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                            HStack {
                                Text("Server:")
                                    .frame(width: 70, alignment: .leading)
                                TextField("rtmp://server", text: $rtmpURL)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            HStack {
                                Text("Key:")
                                    .frame(width: 70, alignment: .leading)
                                SecureField("Stream key", text: $streamKey)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            Button(action: {
                                Task {
                                    await toggleStreaming()
                                }
                            }) {
                                HStack {
                                    Image(systemName: productionManager.streamingViewModel.isPublishing ? "stop.circle.fill" : "play.circle.fill")
                                    Text(productionManager.streamingViewModel.isPublishing ? "Stop Streaming" : "Start Streaming")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(productionManager.streamingViewModel.isPublishing ? Color.red : Color.green)
                                .foregroundColor(.white)
                                .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private func toggleStreaming() async {
        if productionManager.streamingViewModel.isPublishing {
            await productionManager.streamingViewModel.stop()
        } else {
            do {
                try await productionManager.streamingViewModel.start(rtmpURL: rtmpURL, streamKey: streamKey)
            } catch {
                print("Setup error:", error)
            }
        }
    }
}

struct StudioSelectorSheet: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select Studio")
                .font(.title2)
                .fontWeight(.semibold)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(productionManager.availableStudios, id: \.id) { studio in
                    Button(action: {
                        productionManager.loadStudio(studio)
                        dismiss()
                    }) {
                        VStack {
                            Rectangle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(height: 80)
                                .overlay(
                                    Image(systemName: studio.icon)
                                        .font(.largeTitle)
                                        .foregroundColor(.blue)
                                )
                                .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
                            Text(studio.name)
                                .font(.headline)
                            Text(studio.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 600, height: 400)
    }
}

struct ComprehensiveMediaControls: View {
    @ObservedObject var previewProgramManager: PreviewProgramManager
    let isPreview: Bool
    let mediaFile: MediaFile
    
    @State private var isDragging = false
    @State private var dragStartTime: TimeInterval = 0
    @State private var wasPlayingBeforeDrag = false
    
    private var player: AVPlayer? {
        isPreview ? previewProgramManager.previewPlayer : previewProgramManager.programPlayer
    }
    
    private var isPlaying: Bool {
        isPreview ? previewProgramManager.isPreviewPlaying : previewProgramManager.isProgramPlaying
    }
    
    private var currentTime: TimeInterval {
        isPreview ? previewProgramManager.previewCurrentTime : previewProgramManager.programCurrentTime
    }
    
    private var duration: TimeInterval {
        isPreview ? previewProgramManager.previewDuration : previewProgramManager.programDuration
    }
    
    private var progress: Double {
        guard duration > 0 else { return 0.0 }
        return min(1.0, max(0.0, currentTime / duration))
    }
    
    // FIXED: Check if player is ready before allowing scrubbing
    private var isPlayerReady: Bool {
        guard let currentPlayer = player,
              let currentItem = currentPlayer.currentItem else { return false }
        return currentItem.status == .readyToPlay && currentItem.duration.isValid
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Scrub Bar with Timeline
            VStack(spacing: 4) {
                HStack {
                    Text(formatTime(currentTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    
                    Spacer()
                    
                    // Progress percentage
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(isPreview ? .yellow : .red)
                    
                    Spacer()
                    
                    Text(formatTime(duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                
                // Custom scrub slider with more precise control
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                            .cornerRadius(2)
                        
                        // Progress track
                        Rectangle()
                            .fill(isPreview ? Color.yellow : Color.red)
                            .frame(width: geometry.size.width * progress, height: 4)
                            .cornerRadius(2)
                        
                        // Scrub handle - disabled if player not ready
                        Circle()
                            .fill(isPlayerReady ? (isPreview ? Color.yellow : Color.red) : Color.gray)
                            .frame(width: 12, height: 12)
                            .offset(x: geometry.size.width * progress - 6)
                            .scaleEffect(isDragging ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.1), value: isDragging)
                        
                        // Show loading indicator if player not ready
                        if !isPlayerReady {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                    .scaleEffect(0.5)
                                Text("Loading...")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                // Add manual retry button for stuck loading
                                Button("Retry") {
                                    if let currentPlayer = player, let currentItem = currentPlayer.currentItem {
                                        print("🔄 Manual retry: Recreating player item")
                                        let asset = currentItem.asset
                                        let newItem = AVPlayerItem(asset: asset)
                                        currentPlayer.replaceCurrentItem(with: newItem)
                                    }
                                }
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // FIXED: Only allow scrubbing if player is ready
                                guard isPlayerReady else {
                                    print("🚫 Scrubbing disabled - player not ready")
                                    return
                                }
                                
                                if !isDragging {
                                    isDragging = true
                                    wasPlayingBeforeDrag = isPlaying
                                    dragStartTime = currentTime
                                    // Pause during scrubbing for smoother experience
                                    if isPlaying {
                                        if isPreview {
                                            previewProgramManager.pausePreview()
                                        } else {
                                            previewProgramManager.pauseProgram()
                                        }
                                    }
                                }
                                
                                let newProgress = max(0, min(1, value.location.x / geometry.size.width))
                                let newTime = newProgress * duration
                                
                                if isPreview {
                                    previewProgramManager.seekPreview(to: newTime)
                                } else {
                                    previewProgramManager.seekProgram(to: newTime)
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                                // Resume playback if it was playing before scrubbing
                                if wasPlayingBeforeDrag {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        if isPreview {
                                            previewProgramManager.playPreview()
                                        } else {
                                            previewProgramManager.playProgram()
                                        }
                                    }
                                }
                            }
                    )
                    .disabled(!isPlayerReady) // Disable gesture if player not ready
                }
                .frame(height: 20)
            }
            
            // Transport Controls
            HStack(spacing: 16) {
                // Skip backward button
                Button(action: {
                    guard isPlayerReady else { return }
                    let newTime = max(0, currentTime - 10)
                    if isPreview {
                        previewProgramManager.seekPreview(to: newTime)
                    } else {
                        previewProgramManager.seekProgram(to: newTime)
                    }
                }) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isPlayerReady ? .primary : .gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Skip backward 10 seconds")
                .keyboardShortcut("j", modifiers: [])
                .disabled(!isPlayerReady)
                
                // Play/Pause button (larger)
                Button(action: {
                    guard isPlayerReady else { 
                        print("🚫 Play/Pause disabled - player not ready")
                        return 
                    }
                    togglePlayPause()
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(isPlayerReady ? (isPreview ? .yellow : .red) : .gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help(isPlaying ? "Pause (Space)" : "Play (Space)")
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!isPlayerReady)
                
                // Skip forward button
                Button(action: {
                    guard isPlayerReady else { return }
                    let newTime = min(duration, currentTime + 10)
                    if isPreview {
                        previewProgramManager.seekPreview(to: newTime)
                    } else {
                        previewProgramManager.seekProgram(to: newTime)
                    }
                }) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isPlayerReady ? .primary : .gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Skip forward 10 seconds")
                .keyboardShortcut("l", modifiers: [])
                .disabled(!isPlayerReady)
                
                Spacer()
                
                // Frame-by-frame controls
                Button(action: {
                    guard isPlayerReady else { return }
                    // Step backward one frame (approximate)
                    let frameTime = 1.0/30.0 // Assume 30fps
                    let newTime = max(0, currentTime - frameTime)
                    if isPreview {
                        previewProgramManager.seekPreview(to: newTime)
                    } else {
                        previewProgramManager.seekProgram(to: newTime)
                    }
                }) {
                    Image(systemName: "backward.frame")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isPlayerReady ? .secondary : .gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Previous frame")
                .keyboardShortcut(",", modifiers: [])
                .disabled(!isPlayerReady)
                
                Button(action: {
                    guard isPlayerReady else { return }
                    // Step forward one frame (approximate)
                    let frameTime = 1.0/30.0 // Assume 30fps
                    let newTime = min(duration, currentTime + frameTime)
                    if isPreview {
                        previewProgramManager.seekPreview(to: newTime)
                    } else {
                        previewProgramManager.seekProgram(to: newTime)
                    }
                }) {
                    Image(systemName: "forward.frame")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isPlayerReady ? .secondary : .gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Next frame")
                .keyboardShortcut(".", modifiers: [])
                .disabled(!isPlayerReady)
                
                // Stop button
                Button(action: {
                    guard isPlayerReady else { return }
                    if isPreview {
                        previewProgramManager.stopPreview()
                    } else {
                        previewProgramManager.stopProgram()
                    }
                }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isPlayerReady ? .primary : .gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Stop and rewind to beginning")
                .disabled(!isPlayerReady)
                
                // Loop button (for future implementation)
                Button(action: {
                    // TODO: Implement loop functionality
                    print("🔄 Loop functionality coming soon!")
                }) {
                    Image(systemName: "repeat")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Loop (coming soon)")
                .disabled(true)
            }
            
            // Additional info row
            HStack {
                Text(mediaFile.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Show player status for debugging
                if let currentPlayer = player, let currentItem = currentPlayer.currentItem {
                    Text("Status: \(currentItem.status.description)")
                        .font(.caption2)
                        .foregroundColor(currentItem.status == .readyToPlay ? .green : (currentItem.status == .failed ? .red : .orange))
                }
                
                Text(formatFileSize(mediaFile.url))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.1))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isPreview ? Color.yellow.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func togglePlayPause() {
        if isPreview {
            if isPlaying {
                previewProgramManager.pausePreview()
            } else {
                previewProgramManager.playPreview()
            }
        } else {
            if isPlaying {
                previewProgramManager.pauseProgram()
            } else {
                previewProgramManager.playProgram()
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func formatFileSize(_ url: URL) -> String {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resourceValues.fileSize {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useMB, .useGB]
                formatter.countStyle = .file
                return formatter.string(fromByteCount: Int64(fileSize))
            }
        } catch {
            // Ignore errors
        }
        return ""
    }
}

// MARK: - Helper Views for Cleaner Code

struct MediaLoadingView: View {
    let mediaFile: MediaFile
    let isPreview: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: mediaFile.fileType.icon)
                .font(.largeTitle)
                .foregroundColor(isPreview ? .yellow : .red)
            Text(mediaFile.name)
                .font(.title2)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("Loading Media...")
                .font(.caption)
                .foregroundColor(.gray)
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: isPreview ? .yellow : .red))
                .scaleEffect(0.8)
        }
        .padding()
    }
}

struct VirtualCameraView: View {
    let camera: VirtualCamera
    let isPreview: Bool
    
    var body: some View {
        VStack {
            Image(systemName: "video.3d")
                .font(.largeTitle)
                .foregroundColor(isPreview ? .yellow : .red)
            Text(camera.name)
                .font(.title2)
                .foregroundColor(.white)
            Text("Virtual Camera")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct NoSourceView: View {
    let isPreview: Bool
    
    var body: some View {
        VStack {
            Image(systemName: isPreview ? "eye.slash" : "tv.slash")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text(isPreview ? "No Preview Source" : "No Program Source")
                .font(.title2)
                .foregroundColor(.gray)
            Text(isPreview ? "Click a camera or media to load preview" : "Use TAKE button to send preview to program")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }
}

// PERFORMANCE: Optimized camera view with reduced update frequency
struct OptimizedPreviewCameraView: View {
    @ObservedObject var cameraFeed: CameraFeed
    @ObservedObject var productionManager: UnifiedProductionManager
    let effectCount: Int
    
    // PERFORMANCE: Cache processed images to avoid repeated processing
    @State private var cachedProcessedImage: NSImage?
    @State private var lastProcessedFrameCount: Int = 0
    
    var body: some View {
        Group {
            // PERFORMANCE: Only process new images when frame count changes
            if let processedImage = getCachedOrProcessedImage() {
                Image(nsImage: processedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .id("preview-camera-\(cameraFeed.id)-\(lastProcessedFrameCount)-fx-\(effectCount)")
            } else {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Loading Camera...")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text(cameraFeed.device.displayName)
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("Status: \(cameraFeed.connectionStatus.displayText)")
                        .font(.caption2)
                        .foregroundColor(cameraFeed.connectionStatus.color)
                    Text("Frame: \(cameraFeed.frameCount)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    // PERFORMANCE: Cached image processing to avoid repeated work
    private func getCachedOrProcessedImage() -> NSImage? {
        // Only process if frame count changed
        if cameraFeed.frameCount != lastProcessedFrameCount {
            lastProcessedFrameCount = cameraFeed.frameCount
            
            guard let cgImage = cameraFeed.previewImage else { 
                cachedProcessedImage = nil
                return nil 
            }
            
            if let processedCGImage = productionManager.previewProgramManager.processImageWithEffects(cgImage, for: .preview) {
                let nsImage = NSImage(size: NSSize(width: processedCGImage.width, height: processedCGImage.height))
                let bitmapRep = NSBitmapImageRep(cgImage: processedCGImage)
                nsImage.addRepresentation(bitmapRep)
                cachedProcessedImage = nsImage
                return nsImage
            }
            
            cachedProcessedImage = cameraFeed.previewNSImage
            return cameraFeed.previewNSImage
        }
        
        // Return cached image if frame hasn't changed
        return cachedProcessedImage ?? cameraFeed.previewNSImage
    }
}

struct OptimizedProgramCameraView: View {
    @ObservedObject var cameraFeed: CameraFeed
    @ObservedObject var productionManager: UnifiedProductionManager
    let effectCount: Int
    
    // PERFORMANCE: Cache processed images
    @State private var cachedProcessedImage: NSImage?
    @State private var lastProcessedFrameCount: Int = 0
    
    var body: some View {
        Group {
            if let processedImage = getCachedOrProcessedImage() {
                Image(nsImage: processedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .id("program-camera-\(cameraFeed.id)-\(lastProcessedFrameCount)-fx-\(effectCount)")
            } else {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Loading Camera...")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text(cameraFeed.device.displayName)
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("Status: \(cameraFeed.connectionStatus.displayText)")
                        .font(.caption2)
                        .foregroundColor(cameraFeed.connectionStatus.color)
                    Text("Frame: \(cameraFeed.frameCount)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private func getCachedOrProcessedImage() -> NSImage? {
        if cameraFeed.frameCount != lastProcessedFrameCount {
            lastProcessedFrameCount = cameraFeed.frameCount
            
            guard let cgImage = cameraFeed.previewImage else { 
                cachedProcessedImage = nil
                return nil 
            }
            
            if let processedCGImage = productionManager.previewProgramManager.processImageWithEffects(cgImage, for: .program) {
                let nsImage = NSImage(size: NSSize(width: processedCGImage.width, height: processedCGImage.height))
                let bitmapRep = NSBitmapImageRep(cgImage: processedCGImage)
                nsImage.addRepresentation(bitmapRep)
                cachedProcessedImage = nsImage
                return nsImage
            }
            
            cachedProcessedImage = cameraFeed.previewNSImage
            return cameraFeed.previewNSImage
        }
        
        return cachedProcessedImage ?? cameraFeed.previewNSImage
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
