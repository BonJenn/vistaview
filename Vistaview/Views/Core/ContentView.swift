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
    @State private var productionMode: ProductionMode = .live
    @State private var showingStudioSelector = false
    
    // Live Production States (keeping your existing ones)
    @State private var rtmpURL = "rtmp://live.twitch.tv/live/"
    @State private var streamKey = ""
    @State private var selectedTab = 0
    @State private var selectedLayer = 0
    @State private var showingFilePicker = false
    @State private var mediaFiles: [MediaFile] = []
    @State private var selectedPlatform = "Twitch"
    
    var body: some View {
        VStack(spacing: 0) {
            // Unified Top Navigation Bar
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
                    
                    // Unsaved changes indicator
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
                        switchToVirtualMode()
                    }) {
                        HStack {
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
                        switchToLiveMode()
                    }) {
                        HStack {
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
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                Spacer()
                
                // Status Indicators
                HStack(spacing: 16) {
                    // Virtual Studio Status
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
                    
                    // Live Streaming Status
                    if productionMode == .live {
                        HStack {
                            Circle()
                                .fill(productionManager.streamingViewModel.isPublishing ? Color.red : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(productionManager.streamingViewModel.isPublishing ? "LIVE" : "OFFLINE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(productionManager.streamingViewModel.isPublishing ? .red : .secondary)
                        }
                    }
                    
                    Button(action: {}) {
                        Image(systemName: "gear")
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            
            Divider()
            
            // Main Content Area
            Group {
                switch productionMode {
                case .virtual:
                    VirtualProductionView()
                case .live:
                    EnhancedLiveProductionView(
                        productionManager: productionManager,
                        rtmpURL: $rtmpURL,
                        streamKey: $streamKey,
                        selectedTab: $selectedTab,
                        selectedLayer: $selectedLayer,
                        showingFilePicker: $showingFilePicker,
                        mediaFiles: $mediaFiles,
                        selectedPlatform: $selectedPlatform
                    )
                }
            }
        }
        .sheet(isPresented: $showingStudioSelector) {
            StudioSelectorSheet(productionManager: productionManager)
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
    
    // MARK: - Actions
    
    private func switchToVirtualMode() {
        productionMode = .virtual
        productionManager.saveCurrentStudioState()
    }
    
    private func switchToLiveMode() {
        productionMode = .live
        productionManager.syncVirtualToLive()
    }
    
    private func requestPermissions() async {
        let _ = await AVCaptureDevice.requestAccess(for: .video)
        let _ = await AVCaptureDevice.requestAccess(for: .audio)
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let mediaFile = MediaFile(
                    name: url.lastPathComponent,
                    type: .video, // Determine type from extension
                    url: url
                )
                mediaFiles.append(mediaFile)
            }
        case .failure(let error):
            print("File import error: \(error)")
        }
    }
}

// MARK: - Enhanced Live Production View (Simplified)

struct EnhancedLiveProductionView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var rtmpURL: String
    @Binding var streamKey: String
    @Binding var selectedTab: Int
    @Binding var selectedLayer: Int
    @Binding var showingFilePicker: Bool
    @Binding var mediaFiles: [MediaFile]
    @Binding var selectedPlatform: String
    
    var body: some View {
        HSplitView {
            // Left Panel - Sources & Media (ENHANCED)
            VStack(spacing: 0) {
                // Source Tabs (Enhanced with Virtual)
                HStack(spacing: 0) {
                    ForEach(["Camera", "Virtual", "Media", "Effects"], id: \.self) { tab in
                        Button(action: {
                            selectedTab = ["Camera", "Virtual", "Media", "Effects"].firstIndex(of: tab) ?? 0
                        }) {
                            Text(tab)
                                .font(.caption)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(selectedTab == ["Camera", "Virtual", "Media", "Effects"].firstIndex(of: tab) ?
                                          Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(selectedTab == ["Camera", "Virtual", "Media", "Effects"].firstIndex(of: tab) ?
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
                        CameraSourceView(viewModel: productionManager.streamingViewModel)
                    case 1:
                        VirtualSourceView(productionManager: productionManager) // NEW TAB
                    case 2:
                        MediaBrowserView(mediaFiles: $mediaFiles, showingFilePicker: $showingFilePicker)
                    case 3:
                        EffectsView()
                    default:
                        CameraSourceView(viewModel: productionManager.streamingViewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 300, maxWidth: 400)
            .background(Color.black.opacity(0.05))
            
            // Center Panel - Main Preview & Layers (Your existing layout)
            VStack(spacing: 0) {
                // Main Preview
                VStack {
                    HStack {
                        Text("Output Preview")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        
                        // Virtual Studio Indicator (NEW)
                        if productionManager.isVirtualStudioActive {
                            HStack {
                                Image(systemName: "cube.transparent")
                                    .foregroundColor(.blue)
                                Text("Virtual Studio Active")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Text(productionManager.streamingViewModel.statusMessage)
                            .font(.caption)
                            .foregroundColor(productionManager.streamingViewModel.cameraSetup ? .green : .orange)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Main video output
                    CameraPreview(viewModel: productionManager.streamingViewModel)
                        .background(Color.black)
                        .overlay(
                            Group {
                                if !productionManager.streamingViewModel.cameraSetup {
                                    VStack {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        Text("Initializing Camera...")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                    }
                                    .padding()
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(10)
                                }
                            }
                        )
                        .aspectRatio(16/9, contentMode: .fit)
                }
                .background(Color.black.opacity(0.9))
                .cornerRadius(8)
                .padding()
                
                // Enhanced Layer Control
                EnhancedLayerControlView(
                    selectedLayer: $selectedLayer,
                    productionManager: productionManager
                )
            }
            .frame(minWidth: 500)
            
            // Right Panel - Your existing output controls + virtual studio info
            VStack(spacing: 0) {
                // Output Settings Header
                HStack {
                    Text("Output Controls")
                        .font(.headline)
                    Spacer()
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Virtual Studio Integration (NEW)
                        if productionManager.isVirtualStudioActive {
                            GroupBox("Virtual Studio") {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Virtual Cameras:")
                                        Spacer()
                                        Text("\(productionManager.availableVirtualCameras.count)")
                                            .foregroundColor(.blue)
                                    }
                                    
                                    HStack {
                                        Text("LED Walls:")
                                        Spacer()
                                        Text("\(productionManager.availableLEDWalls.count)")
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Button("Sync from Virtual Studio") {
                                        productionManager.syncVirtualToLive()
                                    }
                                    .buttonStyle(.bordered)
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        
                        // Your existing streaming controls (unchanged)
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
                                    .onChange(of: selectedPlatform) { platform in
                                        switch platform {
                                        case "Twitch":
                                            rtmpURL = "rtmp://live.twitch.tv/live/"
                                        case "YouTube":
                                            rtmpURL = "rtmp://a.rtmp.youtube.com/live2"
                                        case "Facebook":
                                            rtmpURL = "rtmps://live-api-s.facebook.com:443/rtmp/"
                                        default:
                                            rtmpURL = "rtmp://127.0.0.1:1935/stream"
                                        }
                                    }
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
                                .disabled(!productionManager.streamingViewModel.cameraSetup)
                            }
                        }
                        
                        // Audio Controls (keeping existing)
                        GroupBox("Audio") {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Master")
                                    Spacer()
                                    Slider(value: .constant(0.8), in: 0...1)
                                        .frame(width: 100)
                                    Text("80%")
                                        .font(.caption)
                                        .frame(width: 30)
                                }
                                
                                HStack {
                                    Text("Mic")
                                    Spacer()
                                    Slider(value: .constant(0.6), in: 0...1)
                                        .frame(width: 100)
                                    Text("60%")
                                        .font(.caption)
                                        .frame(width: 30)
                                }
                                
                                HStack {
                                    Text("System")
                                    Spacer()
                                    Slider(value: .constant(0.4), in: 0...1)
                                        .frame(width: 100)
                                    Text("40%")
                                        .font(.caption)
                                        .frame(width: 30)
                                }
                            }
                        }
                        
                        // Statistics (keeping existing)
                        GroupBox("Statistics") {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("FPS:")
                                    Spacer()
                                    Text("30")
                                        .foregroundColor(.green)
                                }
                                HStack {
                                    Text("Bitrate:")
                                    Spacer()
                                    Text("2.5 Mbps")
                                        .foregroundColor(.green)
                                }
                                HStack {
                                    Text("Dropped:")
                                    Spacer()
                                    Text("0 frames")
                                        .foregroundColor(.green)
                                }
                                HStack {
                                    Text("Duration:")
                                    Spacer()
                                    Text(productionManager.streamingViewModel.isPublishing ? "00:05:23" : "00:00:00")
                                }
                            }
                            .font(.caption)
                        }
                    }
                    .padding()
                }
            }
            .frame(minWidth: 280, maxWidth: 350)
            .background(Color.gray.opacity(0.05))
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

// MARK: - New Components (Simplified)

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
                // Virtual Camera Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(productionManager.availableVirtualCameras, id: \.id) { camera in
                        Button(action: {
                            productionManager.selectVirtualCamera(camera)
                        }) {
                            VStack {
                                Rectangle()
                                    .fill(Color.blue.opacity(0.3))
                                    .frame(height: 60)
                                    .overlay(
                                        VStack {
                                            Image(systemName: "video.3d")
                                            Text(camera.name)
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.blue)
                                    )
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(camera.isActive ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct EnhancedLayerControlView: View {
    @Binding var selectedLayer: Int
    let productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers")
                    .font(.headline)
                Spacer()
                Button(action: {}) {
                    Image(systemName: "plus.circle")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .background(Color.gray.opacity(0.1))
            
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    VStack {
                        Rectangle()
                            .fill(index == selectedLayer ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                            .frame(height: 40)
                            .overlay(
                                VStack {
                                    Text("Layer \(index + 1)")
                                        .font(.caption2)
                                        .foregroundColor(index == selectedLayer ? .blue : .secondary)
                                    
                                    // Show if virtual content
                                    if index == 0 && productionManager.isVirtualStudioActive {
                                        Image(systemName: "cube.transparent")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }
                            )
                            .cornerRadius(4)
                        
                        Slider(value: .constant(index == 0 ? 1.0 : 0.0), in: 0...1)
                            .frame(width: 60)
                    }
                    .onTapGesture {
                        selectedLayer = index
                    }
                }
                Spacer()
            }
            .padding()
            .background(Color.black.opacity(0.05))
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
            
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(productionManager.availableStudios) { studio in
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
                .padding(.horizontal)
            }
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 600, height: 650)
    }
}

// MARK: - Keep all your existing views (unchanged)

struct CameraSourceView: View {
    let viewModel: StreamingViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            // Camera thumbnails
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(0..<4) { index in
                    Button(action: {
                        // Switch camera
                    }) {
                        VStack {
                            Rectangle()
                                .fill(index == 0 ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                                .frame(height: 60)
                                .overlay(
                                    VStack {
                                        Image(systemName: "camera.fill")
                                        Text("Camera \(index + 1)")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(index == 0 ? .blue : .secondary)
                                )
                                .cornerRadius(6)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Divider()
            
            // Camera controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Camera Settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Position:")
                    Spacer()
                    Picker("Position", selection: .constant("Front")) {
                        Text("Front").tag("Front")
                        Text("Back").tag("Back")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 80)
                }
                
                HStack {
                    Text("Resolution:")
                    Spacer()
                    Picker("Resolution", selection: .constant("720p")) {
                        Text("480p").tag("480p")
                        Text("720p").tag("720p")
                        Text("1080p").tag("1080p")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 80)
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct MediaBrowserView: View {
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
                    Image(systemName: "plus.circle.fill")
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
                    
                    Text("Click + to add videos, images, or audio files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
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
                        MediaThumbnailView(file: file)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct EffectsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Effects & Filters")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(["Blur", "Sharpen", "Vintage", "B&W", "Sepia", "Contrast"], id: \.self) { effect in
                    Button(action: {
                        // Apply effect
                    }) {
                        VStack {
                            Rectangle()
                                .fill(Color.purple.opacity(0.2))
                                .frame(height: 50)
                                .overlay(
                                    VStack {
                                        Image(systemName: "camera.filters")
                                        Text(effect)
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.purple)
                                )
                                .cornerRadius(6)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct MediaThumbnailView: View {
    let file: MediaFile
    
    var body: some View {
        VStack {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 60)
                .overlay(
                    VStack {
                        Image(systemName: file.type.icon)
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

// Platform-specific preview wrapper (keeping existing)
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
    
    func updateNSView(_ nsView: MTHKView, context: Context) {
        // Updates handled through viewModel
    }
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
    
    func updateUIView(_ uiView: MTHKView, context: Context) {
        // Updates handled through viewModel
    }
}
#endif

// MARK: - Data Models (keeping existing)

struct MediaFile: Identifiable {
    let id = UUID()
    let name: String
    let type: MediaType
    let url: URL
}

enum MediaType {
    case video, image, audio
    
    var icon: String {
        switch self {
        case .video: return "video.fill"
        case .image: return "photo.fill"
        case .audio: return "music.note"
        }
    }
}
