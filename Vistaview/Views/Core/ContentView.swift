import SwiftUI
import HaishinKit
import AVFoundation
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
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.movie, .image, .audio],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Helper Functions
    
    private func requestPermissions() async {
        let videoPermission = await AVCaptureDevice.requestAccess(for: .video)
        let audioPermission = await AVCaptureDevice.requestAccess(for: .audio)
        print("Video permission: \(videoPermission), Audio permission: \(audioPermission)")
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
            .cornerRadius(8)
            
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
        .background(Color.gray.opacity(0.05))
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
            .background(Color.gray.opacity(0.03))
            
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
                .frame(height: 200)
                
                Divider()
                
                // Output Mapping Controls (middle section)
                OutputMappingControlsView(
                    outputMappingManager: productionManager.outputMappingManager,
                    externalDisplayManager: productionManager.externalDisplayManager
                )
                .frame(height: 220)
                
                Divider()
                
                // Output Controls (bottom section)
                OutputControlsPanel(
                    productionManager: productionManager,
                    rtmpURL: $rtmpURL,
                    streamKey: $streamKey,
                    selectedPlatform: $selectedPlatform
                )
            }
            .frame(minWidth: 280, maxWidth: 350)
            .background(Color.gray.opacity(0.03))
        }
    }
}

// MARK: - Preview/Program Center View

struct PreviewProgramCenterView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var mediaFiles: [MediaFile]
    
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
                    }
                    
                    PreviewMonitorView(
                        productionManager: productionManager
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(Color.black)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.yellow, lineWidth: 2)
                    )
                }
                
                // Program Monitor (Bottom - Live Output)
                VStack(spacing: 4) {
                    HStack {
                        Text("PROGRAM")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    
                    ProgramMonitorView(
                        productionManager: productionManager
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(Color.black)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red, lineWidth: 2)
                    )
                }
            }
            .frame(maxHeight: .infinity)
            
            // TAKE and AUTO buttons
            HStack(spacing: 12) {
                Spacer()
                
                Button("TAKE") {
                    // Move current preview source to program using the correct method name
                    print(" TAKE BUTTON CLICKED!")
                    print(" TAKE DEBUG: Current preview source: \(productionManager.previewProgramManager.previewSource)")
                    print(" TAKE DEBUG: Current program source: \(productionManager.previewProgramManager.programSource)")
                    
                    // Check if preview source exists
                    if productionManager.previewProgramManager.previewSource == .none {
                        print(" TAKE ERROR: No preview source to take!")
                    } else {
                        print(" TAKE: About to call take() method...")
                        
                        // FIXED: Use withAnimation for smoother transitions
                        withAnimation(.easeInOut(duration: 0.3)) {
                            productionManager.previewProgramManager.take()
                        }
                        
                        print(" TAKE: Called take() method")
                        
                        // Force immediate UI update
                        DispatchQueue.main.async {
                            print(" TAKE AFTER: Preview source: \(productionManager.previewProgramManager.previewSource)")
                            print(" TAKE AFTER: Program source: \(productionManager.previewProgramManager.programSource)")
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
                    // Auto transition preview to program (could add transition effects here)
                    print(" AUTO: Auto-transitioned preview to program")
                    
                    // FIXED: Use withAnimation for smooth auto transition
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

// MARK: - Monitor Views

struct PreviewMonitorView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @State private var frameUpdateTrigger = 0
    @State private var isTargeted = false
    
    private var effectCount: Int {
        productionManager.previewProgramManager.getPreviewEffectChain()?.effects.count ?? 0
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            // Display the current preview source if available
            if case .camera(let cameraFeed) = productionManager.previewProgramManager.previewSource {
                PreviewCameraView(
                    cameraFeed: cameraFeed,
                    productionManager: productionManager,
                    effectCount: effectCount
                )
                
            } else if case .media(let mediaFile, let player) = productionManager.previewProgramManager.previewSource {
                VStack {
                    Image(systemName: mediaFile.fileType.icon)
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text(mediaFile.name)
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Media Playback")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else if case .virtual(let virtualCamera) = productionManager.previewProgramManager.previewSource {
                VStack {
                    Image(systemName: "video.3d")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text(virtualCamera.name)
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Virtual Camera")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                VStack {
                    Image(systemName: "eye.slash")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No Preview Source")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Text("Click a camera to load preview")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
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
                            .cornerRadius(8)
                            .padding(4)
                    }
                }
            }
            
            // Drop target overlay for effects
            if isTargeted {
                Rectangle()
                    .fill(Color.blue.opacity(0.3))
                    .overlay(
                        VStack {
                            Image(systemName: "wand.and.stars")
                                .font(.title)
                                .foregroundColor(.white)
                            Text("Drop Effect Here")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    )
            }
        }
        .dropDestination(for: EffectDragItem.self) { items, location in
            guard let item = items.first else { return false }
            
            Task { @MainActor in
                productionManager.previewProgramManager.addEffectToPreview(item.effectType)
            }
            
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}

// FIXED: New view that directly observes the camera feed for live updates
struct PreviewCameraView: View {
    @ObservedObject var cameraFeed: CameraFeed  // Direct observation of camera feed
    @ObservedObject var productionManager: UnifiedProductionManager
    let effectCount: Int
    
    var body: some View {
        Group {
            if let processedImage = getProcessedPreviewImage(from: cameraFeed) {
                Image(nsImage: processedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .id("preview-camera-\(cameraFeed.id)-\(cameraFeed.frameCount)-fx-\(effectCount)")
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
    
    // FIXED: Process camera feed image through effects
    private func getProcessedPreviewImage(from cameraFeed: CameraFeed) -> NSImage? {
        guard let cgImage = cameraFeed.previewImage else { return nil }
        
        // Apply effects processing
        if let processedCGImage = productionManager.previewProgramManager.processImageWithEffects(cgImage, for: .preview) {
            // Convert processed CGImage back to NSImage
            let nsImage = NSImage(size: NSSize(width: processedCGImage.width, height: processedCGImage.height))
            let bitmapRep = NSBitmapImageRep(cgImage: processedCGImage)
            nsImage.addRepresentation(bitmapRep)
            return nsImage
        }
        
        // Fallback to original image if effects processing fails
        return cameraFeed.previewNSImage
    }
}

struct ProgramMonitorView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @State private var frameUpdateTrigger = 0
    @State private var isTargeted = false
    
    private var effectCount: Int {
        productionManager.previewProgramManager.getProgramEffectChain()?.effects.count ?? 0
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            // Display the current program source if available
            if case .camera(let cameraFeed) = productionManager.previewProgramManager.programSource {
                ProgramCameraView(
                    cameraFeed: cameraFeed,
                    productionManager: productionManager,
                    effectCount: effectCount
                )
                
            } else if case .media(let mediaFile, let player) = productionManager.previewProgramManager.programSource {
                VStack {
                    Image(systemName: mediaFile.fileType.icon)
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(mediaFile.name)
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Media Playback")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else if case .virtual(let virtualCamera) = productionManager.previewProgramManager.programSource {
                VStack {
                    Image(systemName: "video.3d")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(virtualCamera.name)
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Virtual Camera")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                VStack {
                    Image(systemName: "tv.slash")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No Program Source")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Text("Use TAKE button to send preview to program")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
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
                            .cornerRadius(8)
                            .padding(4)
                    }
                }
            }
            
            // Drop target overlay for effects
            if isTargeted {
                Rectangle()
                    .fill(Color.red.opacity(0.3))
                    .overlay(
                        VStack {
                            Image(systemName: "wand.and.stars")
                                .font(.title)
                                .foregroundColor(.white)
                            Text("Drop Effect Here")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    )
            }
        }
        .dropDestination(for: EffectDragItem.self) { items, location in
            guard let item = items.first else { return false }
            
            Task { @MainActor in
                productionManager.previewProgramManager.addEffectToProgram(item.effectType)
            }
            
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}

// FIXED: New view that directly observes the camera feed for live updates
struct ProgramCameraView: View {
    @ObservedObject var cameraFeed: CameraFeed  // Direct observation of camera feed
    @ObservedObject var productionManager: UnifiedProductionManager
    let effectCount: Int
    
    var body: some View {
        Group {
            if let processedImage = getProcessedProgramImage(from: cameraFeed) {
                Image(nsImage: processedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .id("program-camera-\(cameraFeed.id)-\(cameraFeed.frameCount)-fx-\(effectCount)")
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
    
    // FIXED: Process camera feed image through effects
    private func getProcessedProgramImage(from cameraFeed: CameraFeed) -> NSImage? {
        guard let cgImage = cameraFeed.previewImage else { return nil }
        
        // Apply effects processing
        if let processedCGImage = productionManager.previewProgramManager.processImageWithEffects(cgImage, for: .program) {
            // Convert processed CGImage back to NSImage
            let nsImage = NSImage(size: NSSize(width: processedCGImage.width, height: processedCGImage.height))
            let bitmapRep = NSBitmapImageRep(cgImage: processedCGImage)
            nsImage.addRepresentation(bitmapRep)
            return nsImage
        }
        
        // Fallback to original image if effects processing fails
        return cameraFeed.previewNSImage
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
            // Source Tabs
            HStack(spacing: 0) {
                ForEach(Array(["Cameras", "Media", "Virtual", "Effects"].enumerated()), id: \.offset) { index, tab in
                    Button(action: {
                        selectedTab = index
                        print(" Selected tab: \(index) - \(tab)")
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
            
            // Source Content
            Group {
                switch selectedTab {
                case 0:
                    CamerasSourceView(
                        productionManager: productionManager
                    )
                case 1:
                    MediaSourceView(mediaFiles: $mediaFiles, showingFilePicker: $showingFilePicker)
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
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(4)
            }
            
            // Available Devices
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(productionManager.cameraFeedManager.availableDevices, id: \.id) { device in
                    CameraDeviceButton(device: device, productionManager: productionManager)
                }
            }
            
            // Live Camera Feeds (Active Feeds)
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
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Fixed grid layout
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
                        .id("live-feed-\(feed.id)-\(feed.frameCount)")
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
            print(" Camera feed clicked: \(feed.device.displayName)")
            print(" Feed status: \(feed.connectionStatus.displayText)")
            print(" Feed has image: \(feed.previewImage != nil)")
            print(" Feed frame count: \(feed.frameCount)")
            print(" Feed isActive: \(feed.isActive)")
            
            let cameraSource = feed.asContentSource()
            productionManager.previewProgramManager.loadToPreview(cameraSource)
            
            // FIXED: Force immediate UI updates
            DispatchQueue.main.async {
                feed.objectWillChange.send()
                productionManager.previewProgramManager.objectWillChange.send()
                productionManager.objectWillChange.send()
                print(" Forced UI updates after loading to preview")
            }
        }) {
            VStack(spacing: 4) {
                // Camera preview thumbnail
                Group {
                    if let nsImage = feed.previewNSImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .id("thumbnail-\(feed.id)-\(feed.frameCount)")  // FIXED: Add frameCount for reactivity
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .overlay(
                                VStack(spacing: 2) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.5)
                                    Text("Loading...")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                    Text("\(feed.frameCount)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text(feed.connectionStatus.displayText)
                                        .font(.caption2)
                                        .foregroundColor(feed.connectionStatus.color)
                                }
                            )
                    }
                }
                .frame(width: 80, height: 45)
                .background(Color.black)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isInProgram ? Color.red : (isInPreview ? Color.yellow : Color.gray.opacity(0.3)), 
                            lineWidth: (isInProgram || isInPreview) ? 2 : 1
                        )
                )
                
                // Label
                VStack(spacing: 1) {
                    Text(feed.device.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Text(
                        isInProgram ? "ON AIR" : (isInPreview ? "IN PREVIEW" : "Tap for Preview")
                    )
                        .font(.caption2)
                        .fontWeight((isInProgram || isInPreview) ? .bold : .regular)
                        .foregroundColor(
                            isInProgram ? .red : (isInPreview ? .yellow : .secondary)
                        )
                    
                    // Status and frame indicator
                    HStack(spacing: 4) {
                        Text("●")
                            .font(.caption2)
                            .foregroundColor(feed.connectionStatus.color)
                        Text("\(feed.frameCount)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 80)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 80)
        .id("camera-button-\(feed.id)-\(feed.frameCount)")  // FIXED: React to frame count changes
    }
}

struct MediaSourceView: View {
    @Binding var mediaFiles: [MediaFile]
    @Binding var showingFilePicker: Bool
    
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
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                }
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(mediaFiles) { file in
                        VStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 60)
                                .overlay(
                                    VStack {
                                        Image(systemName: file.fileType.icon)
                                        Text(file.name)
                                            .font(.caption2)
                                            .lineLimit(2)
                                    }
                                    .foregroundColor(.secondary)
                                )
                                .cornerRadius(6)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
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
                    .cornerRadius(8)
                
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
            .cornerRadius(8)
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
                                .cornerRadius(8)
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
                                .cornerRadius(8)
                            
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

#Preview {
    ContentView()
}