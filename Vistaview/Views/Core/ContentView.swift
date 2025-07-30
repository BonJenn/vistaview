import SwiftUI
import HaishinKit
import AVFoundation
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
    @StateObject private var previewProgramManager: PreviewProgramManager
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
    
    init() {
        let productionManager = UnifiedProductionManager()
        self._productionManager = StateObject(wrappedValue: productionManager)
        
        // Initialize preview/program manager with the production manager and effect manager
        self._previewProgramManager = StateObject(wrappedValue: PreviewProgramManager(
            cameraFeedManager: productionManager.cameraFeedManager,
            unifiedProductionManager: productionManager,
            effectManager: productionManager.effectManager
        ))
    }
    
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
                        previewProgramManager: previewProgramManager,
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
    @ObservedObject var previewProgramManager: PreviewProgramManager
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
                previewProgramManager: previewProgramManager,
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
                    previewProgramManager: previewProgramManager,
                    mediaFiles: $mediaFiles
                )
                
                // Timeline/Layers Control (bottom strip)
                TimelineControlsView(productionManager: productionManager)
                    .frame(height: 120)
                    .background(Color.black.opacity(0.05))
            }
            .frame(minWidth: 600)
            
            // Right Panel - Output & Streaming Controls
            OutputControlsPanel(
                productionManager: productionManager,
                rtmpURL: $rtmpURL,
                streamKey: $streamKey,
                selectedPlatform: $selectedPlatform
            )
            .frame(minWidth: 280, maxWidth: 350)
            .background(Color.gray.opacity(0.03))
        }
    }
}

// MARK: - Preview/Program Center View

struct PreviewProgramCenterView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @ObservedObject var previewProgramManager: PreviewProgramManager
    @Binding var mediaFiles: [MediaFile]
    
    var body: some View {
        VStack(spacing: 8) {
            // Main Preview/Program Display
            HStack(spacing: 8) {
                // Preview Monitor (Left - Next Up)
                VStack(spacing: 4) {
                    HStack {
                        Text("PREVIEW")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                        Spacer()
                        Text(previewProgramManager.previewSourceDisplayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    PreviewMonitorView(
                        productionManager: productionManager,
                        previewProgramManager: previewProgramManager
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(Color.black)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.yellow, lineWidth: 2)
                    )
                }
                
                // Program Monitor (Right - Live Output)
                VStack(spacing: 4) {
                    HStack {
                        Text("PROGRAM")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                        Spacer()
                        Circle()
                            .fill(productionManager.streamingViewModel.isPublishing ? Color.red : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(productionManager.streamingViewModel.isPublishing ? "LIVE" : "OFFLINE")
                            .font(.caption2)
                            .foregroundColor(productionManager.streamingViewModel.isPublishing ? .red : .secondary)
                    }
                    
                    ProgramMonitorView(
                        productionManager: productionManager,
                        previewProgramManager: previewProgramManager
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
                    previewProgramManager.take()
                }
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(6)
                .disabled(previewProgramManager.previewSource == .none)
                
                Button("AUTO") {
                    previewProgramManager.transition(duration: 2.0)
                }
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(previewProgramManager.isTransitioning ? Color.orange : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(6)
                .disabled(previewProgramManager.previewSource == .none)
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .padding()
    }
}

// MARK: - Simple Effects View

struct EffectsSourceView: View {
    @ObservedObject var effectManager: EffectManager
    
    init(effectManager: EffectManager) {
        self.effectManager = effectManager
    }
    
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
                            .foregroundColor(effect.category.color)
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

// MARK: - Monitor Views

struct PreviewMonitorView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @ObservedObject var previewProgramManager: PreviewProgramManager
    @State private var frameUpdateTrigger = 0
    @State private var isTargeted = false
    
    private var effectCount: Int {
        previewProgramManager.getPreviewEffectChain()?.effects.count ?? 0
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            switch previewProgramManager.previewSource {
            case .camera(let feed):
                if let previewImage = feed.previewImage {
                    Image(decorative: previewImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .id("preview-camera-\(feed.id)-\(frameUpdateTrigger)")
                        .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
                            frameUpdateTrigger += 1
                        }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
                
            case .none:
                VStack(spacing: 16) {
                    Image(systemName: "eye")
                        .font(.system(size: 48))
                        .foregroundColor(.yellow.opacity(0.7))
                    
                    Text("Preview")
                        .font(.headline)
                        .foregroundColor(.yellow)
                    
                    Text("Select sources from the sidebar\nto preview before going live")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                
            default:
                Text("Preview")
                    .foregroundColor(.white)
            }
            
            // Drop target overlay
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
            
            // Effect count indicator
            if effectCount > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(effectCount)")
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
        }
        .dropDestination(for: EffectDragItem.self) { items, location in
            let handler = PreviewEffectDropHandler(previewProgramManager: previewProgramManager)
            return handler.handleDrop(items: items)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .contextMenu {
            if effectCount > 0 {
                Button("Clear Effects") {
                    previewProgramManager.clearPreviewEffects()
                }
                
                Button("View Effects") {
                    let chain = previewProgramManager.getPreviewEffectChain()
                    productionManager.effectManager.selectedChain = chain
                }
            }
        }
    }
}

// MARK: - Preview Effect Drop Handler

struct PreviewEffectDropHandler {
    let previewProgramManager: PreviewProgramManager
    
    func handleDrop(items: [EffectDragItem]) -> Bool {
        guard let item = items.first else { return false }
        
        Task { @MainActor in
            previewProgramManager.addEffectToPreview(item.effectType)
            
            // Visual feedback
            let feedbackGenerator = NSHapticFeedbackManager.defaultPerformer
            feedbackGenerator.perform(.generic, performanceTime: .now)
        }
        
        return true
    }
}

struct ProgramMonitorView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @ObservedObject var previewProgramManager: PreviewProgramManager
    @State private var frameUpdateTrigger = 0
    @State private var isTargeted = false
    
    private var effectCount: Int {
        previewProgramManager.getProgramEffectChain()?.effects.count ?? 0
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            switch previewProgramManager.programSource {
            case .camera(let feed):
                if let previewImage = feed.previewImage {
                    Image(decorative: previewImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .id("program-camera-\(feed.id)-\(frameUpdateTrigger)")
                        .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
                            frameUpdateTrigger += 1
                        }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
                
            case .none:
                if let selectedFeed = productionManager.cameraFeedManager.selectedFeedForLiveProduction {
                    LiveCameraFeedView(feed: selectedFeed)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "tv")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("Program Output")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("This is what your audience sees")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                
            default:
                Text("Program")
                    .foregroundColor(.white)
            }
            
            // Drop target overlay
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
            
            // Effect count indicator
            if effectCount > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(effectCount)")
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
        }
        .dropDestination(for: EffectDragItem.self) { items, location in
            let handler = ProgramEffectDropHandler(previewProgramManager: previewProgramManager)
            return handler.handleDrop(items: items)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .contextMenu {
            if effectCount > 0 {
                Button("Clear Effects") {
                    previewProgramManager.clearProgramEffects()
                }
                
                Button("View Effects") {
                    let chain = previewProgramManager.getProgramEffectChain()
                    productionManager.effectManager.selectedChain = chain
                }
            }
        }
    }
}

// MARK: - Program Effect Drop Handler

struct ProgramEffectDropHandler {
    let previewProgramManager: PreviewProgramManager
    
    func handleDrop(items: [EffectDragItem]) -> Bool {
        guard let item = items.first else { return false }
        
        Task { @MainActor in
            previewProgramManager.addEffectToProgram(item.effectType)
            
            // Visual feedback
            let feedbackGenerator = NSHapticFeedbackManager.defaultPerformer
            feedbackGenerator.perform(.generic, performanceTime: .now)
        }
        
        return true
    }
}

// MARK: - Other Views (keeping simple versions for now)

struct SourcesPanel: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @ObservedObject var previewProgramManager: PreviewProgramManager
    @Binding var selectedTab: Int
    @Binding var mediaFiles: [MediaFile]
    @Binding var showingFilePicker: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Source Tabs
            HStack(spacing: 0) {
                ForEach(["Cameras", "Media", "Virtual", "Effects"], id: \.self) { tab in
                    Button(action: {
                        selectedTab = ["Cameras", "Media", "Virtual", "Effects"].firstIndex(of: tab) ?? 0
                    }) {
                        Text(tab)
                            .font(.caption)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(selectedTab == ["Cameras", "Media", "Virtual", "Effects"].firstIndex(of: tab) ?
                                      Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(selectedTab == ["Cameras", "Media", "Virtual", "Effects"].firstIndex(of: tab) ?
                                           .white : .primary)
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
                        productionManager: productionManager,
                        previewProgramManager: previewProgramManager
                    )
                case 1:
                    MediaSourceView(mediaFiles: $mediaFiles, showingFilePicker: $showingFilePicker)
                case 2:
                    VirtualSourceView(productionManager: productionManager)
                case 3:
                    EffectsSourceView(effectManager: productionManager.effectManager)
                default:
                    CamerasSourceView(
                        productionManager: productionManager,
                        previewProgramManager: previewProgramManager
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct CamerasSourceView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @ObservedObject var previewProgramManager: PreviewProgramManager
    
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
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(productionManager.cameraFeedManager.activeFeeds) { feed in
                        LiveCameraFeedButton(
                            feed: feed,
                            productionManager: productionManager,
                            previewProgramManager: previewProgramManager
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
            VStack(spacing: 4) {
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
    @ObservedObject var previewProgramManager: PreviewProgramManager
    
    private var isInPreview: Bool {
        if case .camera(let previewFeed) = previewProgramManager.previewSource {
            return previewFeed.id == feed.id
        }
        return false
    }
    
    var body: some View {
        Button(action: {
            loadFeedToPreview(feed)
        }) {
            VStack(spacing: 4) {
                Group {
                    if let previewImage = feed.previewImage {
                        Image(decorative: previewImage, scale: 1.0)
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(height: 60)
                            .clipped()
                            .overlay(
                                VStack {
                                    Spacer()
                                    HStack {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                        Text("LIVE")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                        Spacer()
                                    }
                                    .padding(4)
                                    .background(Color.black.opacity(0.7))
                                }
                            )
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: 60)
                            .overlay(
                                VStack(spacing: 2) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.7)
                                    Text("CONNECTING...")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                }
                            )
                    }
                }
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isInPreview ? Color.yellow : Color.clear, lineWidth: 2)
                )
                
                VStack(spacing: 1) {
                    Text(feed.device.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Text(isInPreview ? "IN PREVIEW" : "Tap for Preview")
                        .font(.caption2)
                        .fontWeight(isInPreview ? .bold : .regular)
                        .foregroundColor(isInPreview ? .yellow : .secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button("Load to Preview") {
                loadFeedToPreview(feed)
            }
            
            Button("Load to Program") {
                loadFeedToProgram(feed)
            }
            
            Button("Stop Feed") {
                productionManager.cameraFeedManager.stopFeed(feed)
            }
        }
    }
    
    private func loadFeedToPreview(_ feed: CameraFeed) {
        print("Loading \(feed.device.displayName) to Preview")
        let contentSource = ContentSource.camera(feed)
        previewProgramManager.loadToPreview(contentSource)
    }
    
    private func loadFeedToProgram(_ feed: CameraFeed) {
        print("Loading \(feed.device.displayName) to Program")
        let contentSource = ContentSource.camera(feed)
        previewProgramManager.loadToProgram(contentSource)
    }
}

// MARK: - Missing Components

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

struct TimelineControlsView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Timeline & Layers")
                    .font(.headline)
                Spacer()
                Button(action: {}) {
                    Image(systemName: "plus.circle")
                }
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

struct LiveCameraFeedView: View {
    @ObservedObject var feed: CameraFeed
    @State private var frameUpdateTrigger = 0
    
    var body: some View {
        Group {
            if let previewImage = feed.previewImage {
                Image(decorative: previewImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Color.black)
                    .id("live-feed-\(feed.id)-\(frameUpdateTrigger)")
                    .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
                        frameUpdateTrigger += 1
                    }
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            
                            Text("Connecting to \(feed.device.displayName)...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    )
            }
        }
    }
}

// Platform-specific preview wrapper
#if os(macOS)
struct CameraPreview: NSViewRepresentable {
    let viewModel: StreamingViewModel
    
    func makeNSView(context: Context) -> MTHKView {
        let view = MTHKView(frame: CGRect.zero)
        Task { @MainActor in
            await viewModel.attachPreview(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: MTHKView, context: Context) {}
}
#else
struct CameraPreview: UIViewRepresentable {
    let viewModel: StreamingViewModel
    
    func makeUIView(context: Context) -> MTHKView {
        let view = MTHKView(frame: CGRect.zero)
        Task { @MainActor in
            await viewModel.attachPreview(view)
        }
        return view
    }
    
    func updateUIView(_ uiView: MTHKView, context: Context) {}
}
#endif