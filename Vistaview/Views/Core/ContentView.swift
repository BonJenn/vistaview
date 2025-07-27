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
    @State private var showingVirtualCameraDemo = false
    
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
                    
                    // Virtual Camera Demo Button
                    Button(action: { showingVirtualCameraDemo = true }) {
                        Image(systemName: "video.3d")
                    }
                    .help("Virtual Camera Demo")
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
                        .environmentObject(productionManager.studioManager)
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
    
    // MARK: - Actions
    
    private func switchToVirtualMode() {
        productionMode = .virtual
        productionManager.saveCurrentStudioState()
    }
    
    private func switchToLiveMode() {
        productionMode = .live
        productionManager.syncVirtualToLive()
    }
    
    private func updateRTMPURL(for platform: String) {
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
    
    private func requestPermissions() async {
        let videoPermission = await AVCaptureDevice.requestAccess(for: .video)
        let audioPermission = await AVCaptureDevice.requestAccess(for: .audio)
        
        print("Video permission: \(videoPermission)")
        print("Audio permission: \(audioPermission)")
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

// MARK: - Enhanced Live Production View

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
            LeftPanelView(
                productionManager: productionManager,
                selectedTab: $selectedTab,
                mediaFiles: $mediaFiles,
                showingFilePicker: $showingFilePicker
            )
            .frame(minWidth: 300, maxWidth: 400)
            .background(Color.black.opacity(0.05))
            
            // Center Panel - Main Preview & Layers
            CenterPanelView(
                productionManager: productionManager,
                selectedLayer: $selectedLayer
            )
            .frame(minWidth: 500)
            
            // Right Panel - Output Controls + Virtual Studio Info
            RightPanelView(
                productionManager: productionManager,
                rtmpURL: $rtmpURL,
                streamKey: $streamKey,
                selectedPlatform: $selectedPlatform
            )
            .frame(minWidth: 280, maxWidth: 350)
            .background(Color.gray.opacity(0.05))
        }
    }
}

// MARK: - Left Panel Component

struct LeftPanelView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var selectedTab: Int
    @Binding var mediaFiles: [MediaFile]
    @Binding var showingFilePicker: Bool
    
    var body: some View {
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
                    VirtualSourceView(productionManager: productionManager)
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
    }
}

// MARK: - Center Panel Component

struct CenterPanelView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var selectedLayer: Int
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Preview
            MainPreviewView(productionManager: productionManager)
            
            // Enhanced Layer Control
            EnhancedLayerControlView(
                selectedLayer: $selectedLayer,
                productionManager: productionManager
            )
        }
    }
}

// MARK: - Main Preview Component

struct MainPreviewView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        VStack {
            HStack {
                Text("Output Preview")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                
                // Virtual Studio Indicator
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
    }
}

// MARK: - Right Panel Component

struct RightPanelView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var rtmpURL: String
    @Binding var streamKey: String
    @Binding var selectedPlatform: String
    
    var body: some View {
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
                    // Virtual Studio Integration
                    if productionManager.isVirtualStudioActive {
                        VirtualStudioInfoView(productionManager: productionManager)
                    }
                    
                    // Streaming Section
                    StreamingControlsView(
                        productionManager: productionManager,
                        rtmpURL: $rtmpURL,
                        streamKey: $streamKey,
                        selectedPlatform: $selectedPlatform
                    )
                    
                    // Recording Section
                    RecordingControlsView()
                    
                    // Audio Controls
                    AudioControlsView()
                    
                    // Statistics
                    StatisticsView(productionManager: productionManager)
                }
                .padding()
            }
        }
    }
}

// MARK: - Supporting Components

struct VirtualStudioInfoView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
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
}

struct StreamingControlsView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @Binding var rtmpURL: String
    @Binding var streamKey: String
    @Binding var selectedPlatform: String
    
    var body: some View {
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
                    .onChange(of: selectedPlatform) { _, platform in
                        updateRTMPURL(for: platform)
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
                    VStack(spacing: 4) {
                        SecureField("Get from platform", text: $streamKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        if selectedPlatform == "Twitch" && streamKey.isEmpty {
                            Button("Open Twitch Dashboard") {
                                if let url = URL(string: "https://dashboard.twitch.tv/settings/stream") {
                                    #if os(macOS)
                                    NSWorkspace.shared.open(url)
                                    #else
                                    UIApplication.shared.open(url)
                                    #endif
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                }
                
                // Connection Status
                HStack {
                    Circle()
                        .fill(productionManager.streamingViewModel.isPublishing ? Color.green : (productionManager.streamingViewModel.cameraSetup ? Color.orange : Color.red))
                        .frame(width: 8, height: 8)
                    Text(productionManager.streamingViewModel.isPublishing ? "LIVE" : (productionManager.streamingViewModel.cameraSetup ? "Ready" : "Not Ready"))
                        .font(.caption)
                        .foregroundColor(productionManager.streamingViewModel.isPublishing ? .green : .secondary)
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
    }
    
    private func updateRTMPURL(for platform: String) {
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

struct RecordingControlsView: View {
    var body: some View {
        GroupBox("Recording") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Format:")
                        .frame(width: 70, alignment: .leading)
                    Picker("Format", selection: .constant("MP4")) {
                        Text("MP4").tag("MP4")
                        Text("MOV").tag("MOV")
                        Text("AVI").tag("AVI")
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                HStack {
                    Text("Quality:")
                        .frame(width: 70, alignment: .leading)
                    Picker("Quality", selection: .constant("High")) {
                        Text("Low").tag("Low")
                        Text("Medium").tag("Medium")
                        Text("High").tag("High")
                        Text("Ultra").tag("Ultra")
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Button(action: {
                    // TODO: Recording functionality
                }) {
                    HStack {
                        Image(systemName: "record.circle")
                        Text("Start Recording")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
    }
}

struct AudioControlsView: View {
    var body: some View {
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
    }
}

struct StatisticsView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
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
}

// MARK: - New Components

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
                            productionManager.switchToVirtualCamera(camera)
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
        .frame(width: 600, height: 650)
    }
}

// MARK: - Keep all your existing views

struct CameraSourceView: View {
    let viewModel: StreamingViewModel
    
    // Add camera feed manager integration
    @StateObject private var cameraDeviceManager = CameraDeviceManager()
    @StateObject private var cameraFeedManager: CameraFeedManager
    
    init(viewModel: StreamingViewModel) {
        self.viewModel = viewModel
        let deviceManager = CameraDeviceManager()
        let feedManager = CameraFeedManager(cameraDeviceManager: deviceManager)
        self._cameraDeviceManager = StateObject(wrappedValue: deviceManager)
        self._cameraFeedManager = StateObject(wrappedValue: feedManager)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Camera Sources")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Refresh") {
                    refreshCameras()
                }
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(4)
            }
            
            // Available camera devices
            if cameraFeedManager.availableDevices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "camera.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Cameras Found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Detect Cameras") {
                        refreshCameras()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(cameraFeedManager.availableDevices, id: \.id) { device in
                        cameraDeviceButton(device)
                    }
                }
            }
            
            // Active camera feeds
            if !cameraFeedManager.activeFeeds.isEmpty {
                Divider()
                
                Text("Active Feeds")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(cameraFeedManager.activeFeeds) { feed in
                        activeFeedButton(feed)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            Task {
                await discoverAndStartCameras()
            }
        }
    }
    
    private func cameraDeviceButton(_ device: CameraDevice) -> some View {
        let hasActiveFeed = cameraFeedManager.activeFeeds.contains { $0.device.deviceID == device.deviceID }
        
        return Button(action: {
            if hasActiveFeed {
                // Stop the feed
                if let feed = cameraFeedManager.activeFeeds.first(where: { $0.device.deviceID == device.deviceID }) {
                    cameraFeedManager.stopFeed(feed)
                }
            } else {
                // Start the feed
                Task {
                    await cameraFeedManager.startFeed(for: device)
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
                            Text(hasActiveFeed ? "ACTIVE" : (device.isAvailable ? "START" : "BUSY"))
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
    
    private func activeFeedButton(_ feed: CameraFeed) -> some View {
        Button(action: {
            // Select this feed for live production
            Task {
                await cameraFeedManager.selectFeedForLiveProduction(feed)
                print("📺 Selected feed for live production: \(feed.device.displayName)")
            }
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
                                            .fill(feed.connectionStatus.color)
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
                                    Image(systemName: "camera.fill")
                                    Text("STARTING...")
                                        .font(.caption2)
                                }
                                .foregroundColor(.white)
                            )
                    }
                }
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(cameraFeedManager.selectedFeedForLiveProduction?.id == feed.id ? Color.green : Color.clear, lineWidth: 2)
                )
                
                Text(feed.device.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func refreshCameras() {
        Task {
            await cameraFeedManager.forceRefreshDevices()
        }
    }
    
    private func discoverAndStartCameras() async {
        // Auto-discover cameras and start feeds
        let devices = await cameraFeedManager.getAvailableDevices()
        print("📹 Live Production: Found \(devices.count) camera devices")
        
        // Auto-start the first available camera
        if let firstCamera = devices.first(where: { $0.isAvailable }) {
            print("🎥 Auto-starting first camera: \(firstCamera.displayName)")
            if let feed = await cameraFeedManager.startFeed(for: firstCamera) {
                await cameraFeedManager.selectFeedForLiveProduction(feed)
                print("✅ Auto-selected first camera for live production")
            }
        }
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

// MARK: - Data Models

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