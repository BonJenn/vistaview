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
                
                // Mode Switcher - Simplified to avoid type-checking timeout
                HStack(spacing: 0) {
                    Button(action: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            switchToVirtualMode()
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
                            switchToLiveMode()
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
                        .environmentObject(productionManager)
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
        print("ContentView: Switching to Virtual Studio mode")
        productionMode = .virtual
        productionManager.switchToVirtualMode()
        productionManager.saveCurrentStudioState()
    }
    
    private func switchToLiveMode() {
        print("ContentView: Switching to Live Production mode") 
        productionMode = .live
        productionManager.switchToLiveMode()
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
                    CameraSourceView(viewModel: productionManager.streamingViewModel, productionManager: productionManager)
                case 1:
                    VirtualSourceView(productionManager: productionManager)
                case 2:
                    MediaBrowserView(mediaFiles: $mediaFiles, showingFilePicker: $showingFilePicker)
                case 3:
                    EffectsView()
                default:
                    CameraSourceView(viewModel: productionManager.streamingViewModel, productionManager: productionManager)
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
    @State private var isInitializing = true
    @State private var showDebugFeed = false // Toggle for testing
    
    var body: some View {
        VStack {
            HStack {
                Text("Output Preview")
                    .font(.headline)
                Spacer()
                
                // Debug toggle for testing camera feeds
                Button("Debug Feed") {
                    showDebugFeed.toggle()
                }
                .font(.caption)
                .foregroundColor(.blue)
                
                // Enhanced status indicators with animations
                HStack(spacing: 16) {
                    // Camera status - NOW USING SHARED MANAGER
                    if let selectedFeed = productionManager.cameraFeedManager.selectedFeedForLiveProduction {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(selectedFeed.connectionStatus.color)
                                .frame(width: 8, height: 8)
                            
                            Text(selectedFeed.device.displayName)
                                .font(.caption)
                                .foregroundColor(selectedFeed.connectionStatus.color)
                        }
                    }
                    
                    // Virtual Studio Status with animation
                    if productionManager.isVirtualStudioActive {
                        HStack(spacing: 6) {
                            Image(systemName: "cube.transparent")
                                .foregroundColor(.blue)
                                .scaleEffect(1.1)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6).repeatForever(autoreverses: true), value: productionManager.isVirtualStudioActive)
                            
                            Text("Virtual Studio")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Live Status with pulsing animation
                    HStack(spacing: 6) {
                        Circle()
                            .fill(productionManager.streamingViewModel.isPublishing ? Color.red : Color.gray)
                            .frame(width: 8, height: 8)
                            .scaleEffect(productionManager.streamingViewModel.isPublishing ? 1.2 : 1.0)
                            .animation(
                                productionManager.streamingViewModel.isPublishing ? 
                                .spring(response: 0.6, dampingFraction: 0.4).repeatForever(autoreverses: true) : 
                                .easeOut, 
                                value: productionManager.streamingViewModel.isPublishing
                            )
                        
                        Text(productionManager.streamingViewModel.isPublishing ? "LIVE" : "OFFLINE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(productionManager.streamingViewModel.isPublishing ? .red : .secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Main video output with enhanced loading state
            ZStack {
                if showDebugFeed || productionManager.cameraFeedManager.selectedFeedForLiveProduction != nil {
                    // Show the camera feed directly
                    DirectCameraFeedPreview(cameraFeedManager: productionManager.cameraFeedManager)
                        .aspectRatio(16/9, contentMode: .fit)
                } else {
                    // Original HaishinKit preview
                    CameraPreview(viewModel: productionManager.streamingViewModel)
                        .background(Color.black)
                        .aspectRatio(16/9, contentMode: .fit)
                        .opacity(productionManager.streamingViewModel.cameraSetup ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.5), value: productionManager.streamingViewModel.cameraSetup)
                }
                
                if !productionManager.streamingViewModel.cameraSetup && !showDebugFeed && productionManager.cameraFeedManager.selectedFeedForLiveProduction == nil {
                    VStack(spacing: 16) {
                        // Skeleton loading animation
                        VStack(spacing: 8) {
                            ForEach(0..<3) { index in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 8)
                                    .frame(maxWidth: CGFloat.random(in: 120...200))
                                    .shimmer()
                                    .animation(.easeInOut(duration: 1.5).delay(Double(index) * 0.2).repeatForever(autoreverses: true), value: isInitializing)
                            }
                        }
                        .padding(.top, 20)
                        
                        Spacer()
                        
                        // UPDATED: Better messaging for camera selection
                        VStack(spacing: 12) {
                            Image(systemName: "camera")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text("No Camera Selected")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Choose a camera from the sidebar to start your preview")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                            
                            Text("Click 'Camera' tab → Select a device → Click 'START' → Click the feed")
                                .font(.caption2)
                                .foregroundColor(.blue.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 32)
                        .background(.black.opacity(0.8))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                        
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .background(Color.black.opacity(0.9))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding()
        .onAppear {
            print("Preview ready - using shared camera feed manager")
        }
    }
}

struct DirectCameraFeedPreview: View {
    @ObservedObject var cameraFeedManager: CameraFeedManager
    @State private var refreshTrigger = UUID() // Force refresh trigger
    
    var body: some View {
        Group {
            if let selectedFeed = cameraFeedManager.selectedFeedForLiveProduction {
                // Show the selected camera feed with live updates
                LiveCameraFeedView(feed: selectedFeed)
                    .id(refreshTrigger) // Force refresh when trigger changes
                    .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
                        // Update trigger to force refresh at ~30fps
                        if selectedFeed.previewImage != nil {
                            refreshTrigger = UUID()
                        }
                    }
                    .onAppear {
                        print("DirectCameraFeedPreview: Selected feed appeared - \(selectedFeed.device.displayName)")
                    }
            } else if !cameraFeedManager.activeFeeds.isEmpty {
                // Show available feeds to select from
                availableFeedsView
            } else {
                // Show camera selection instructions
                noCameraView
            }
        }
        .background(Color.black)
        .clipped()
        .onChange(of: cameraFeedManager.selectedFeedForLiveProduction?.id) { _, newValue in
            // Immediately update when selection changes
            print("DirectCameraFeedPreview: Selection changed to: \(newValue?.uuidString ?? "nil")")
            refreshTrigger = UUID()
        }
    }
    
    private var availableFeedsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.7))
            
            Text("Camera Feeds Available")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Select a camera feed from the sidebar to display it here")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            // Show available feeds as small previews
            HStack(spacing: 8) {
                ForEach(cameraFeedManager.activeFeeds.prefix(3)) { feed in
                    VStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 45)
                            .overlay(
                                VStack {
                                    Image(systemName: feed.device.icon)
                                        .font(.caption)
                                    Text(feed.device.displayName)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .foregroundColor(.white.opacity(0.8))
                            )
                            .cornerRadius(4)
                        
                        Circle()
                            .fill(feed.connectionStatus.color)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .padding()
    }
    
    private var noCameraView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera")
                .font(.largeTitle)
                .foregroundColor(.white.opacity(0.7))
            
            Text("No Camera Selected")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Choose a camera from the sidebar to start your preview")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            VStack(spacing: 4) {
                Text("1. Click 'Camera' tab in sidebar")
                Text("2. Click 'START' on a camera device")
                Text("3. Click the camera feed to select it")
            }
            .font(.caption2)
            .foregroundColor(.blue.opacity(0.8))
        }
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
                
                HStack {
                    Text("Objects:")
                    Spacer()
                    Text("\(productionManager.studioManager.studioObjects.count)")
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
        GroupBox {
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
        } label: {
            Text("Live Streaming")
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

// MARK: - Camera Source View

struct CameraSourceView: View {
    let viewModel: StreamingViewModel
    @ObservedObject var productionManager: UnifiedProductionManager
    
    init(viewModel: StreamingViewModel, productionManager: UnifiedProductionManager) {
        self.viewModel = viewModel
        self.productionManager = productionManager
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
            
            // Debug info with real-time updates
            if !productionManager.cameraFeedManager.activeFeeds.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Debug Info:")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        
                        Spacer()
                        
                        // Live update indicator
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .opacity(productionManager.cameraFeedManager.activeFeeds.contains { $0.previewImage != nil } ? 1.0 : 0.3)
                    }
                    
                    ForEach(productionManager.cameraFeedManager.activeFeeds) { feed in
                        HStack {
                            Text("• \(feed.device.displayName):")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("\(feed.connectionStatus.displayText)")
                                .font(.caption2)
                                .foregroundColor(feed.connectionStatus.color)
                            if feed.previewImage != nil {
                                Text("📷")
                                    .font(.caption2)
                            }
                            Text("(\(feed.frameCount))")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    if let selectedFeed = productionManager.cameraFeedManager.selectedFeedForLiveProduction {
                        Text("Selected: \(selectedFeed.device.displayName)")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.1))
                .cornerRadius(6)
                .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
                    // Force refresh every second to show live updates
                    productionManager.cameraFeedManager.objectWillChange.send()
                }
            }
            
            // Available camera devices
            if productionManager.cameraFeedManager.availableDevices.isEmpty {
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
                    ForEach(productionManager.cameraFeedManager.availableDevices, id: \.id) { device in
                        cameraDeviceButton(device)
                    }
                }
            }
            
            // Active camera feeds
            if !productionManager.cameraFeedManager.activeFeeds.isEmpty {
                Divider()
                
                HStack {
                    Text("Active Feeds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Add refresh indicator
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
                        activeFeedButton(feed)
                            .id("active-feed-\(feed.id)-\(feed.frameCount)") // Force refresh
                    }
                }
                .id("active-feeds-grid-\(productionManager.cameraFeedManager.activeFeeds.count)") // Force refresh when count changes
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            // Only discover available devices without starting them
            Task {
                await discoverCamerasOnly()
            }
        }
    }
    
    private func activeFeedButton(_ feed: CameraFeed) -> some View {
        let isSelectedForLive = productionManager.cameraFeedManager.selectedFeedForLiveProduction?.id == feed.id
        
        return Button(action: {
            // Select this feed for live production
            Task {
                print("User clicked feed: \(feed.device.displayName)")
                
                // Select the feed
                await productionManager.cameraFeedManager.selectFeedForLiveProduction(feed)
                print("Selected feed for live production: \(feed.device.displayName)")
                
                // CRITICAL: Force immediate UI updates
                await MainActor.run {
                    // Force both objects to trigger UI updates
                    feed.objectWillChange.send()
                    productionManager.cameraFeedManager.objectWillChange.send()
                    productionManager.objectWillChange.send()
                    
                    print("Forced UI updates - main preview should now show: \(feed.device.displayName)")
                }
                
                // Also trigger the state refresh
                await productionManager.refreshCameraFeedStateForMode()
            }
        }) {
            VStack(spacing: 4) {
                Group {
                    if let previewImage = feed.previewImage {
                        // Show the live camera feed
                        Image(decorative: previewImage, scale: 1.0)
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(height: 60)
                            .clipped()
                            .id("sidebar-preview-\(feed.id)-\(feed.frameCount)") // Force refresh
                            .overlay(
                                VStack {
                                    Spacer()
                                    HStack {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                        Text(isSelectedForLive ? "MAIN" : "LIVE")
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
                                    if feed.connectionStatus == .connecting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.7)
                                        Text("CONNECTING...")
                                            .font(.caption2)
                                    } else {
                                        Image(systemName: "camera.fill")
                                        Text("STARTING...")
                                            .font(.caption2)
                                    }
                                }
                                .foregroundColor(.white)
                            )
                            .id("sidebar-connecting-\(feed.id)-\(feed.frameCount)") // Force refresh
                    }
                }
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelectedForLive ? Color.green : Color.clear, lineWidth: 2)
                )
                
                VStack(spacing: 1) {
                    Text(feed.device.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    if isSelectedForLive {
                        Text("MAIN OUTPUT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    } else {
                        Text("Tap to use")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func cameraDeviceButton(_ device: CameraDevice) -> some View {
        let hasActiveFeed = productionManager.cameraFeedManager.activeFeeds.contains { $0.device.deviceID == device.deviceID }
        
        return Button(action: {
            if hasActiveFeed {
                // Stop the feed
                if let feed = productionManager.cameraFeedManager.activeFeeds.first(where: { $0.device.deviceID == device.deviceID }) {
                    productionManager.cameraFeedManager.stopFeed(feed)
                    
                    // Force UI update after stopping
                    productionManager.cameraFeedManager.objectWillChange.send()
                    productionManager.objectWillChange.send()
                }
            } else {
                // Start the feed - USER INITIATED
                Task {
                    print("User clicked START for: \(device.displayName)")
                    
                    if let feed = await productionManager.cameraFeedManager.startFeed(for: device) {
                        print("Started camera feed: \(feed.device.displayName)")
                        
                        // CRITICAL: Force immediate UI updates so feed appears in Active Feeds
                        await MainActor.run {
                            feed.objectWillChange.send()
                            productionManager.cameraFeedManager.objectWillChange.send()
                            productionManager.objectWillChange.send()
                            
                            print("Forced UI updates - feed should now appear in Active Feeds section")
                        }
                        
                        // Wait a moment for the feed to stabilize, then try to auto-select it if it's the only one
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        
                        await MainActor.run {
                            // Auto-select this feed if it's the only active feed
                            if productionManager.cameraFeedManager.activeFeeds.count == 1 && 
                               productionManager.cameraFeedManager.selectedFeedForLiveProduction == nil {
                                Task {
                                    await productionManager.cameraFeedManager.selectFeedForLiveProduction(feed)
                                    print("Auto-selected the first camera feed for main output")
                                }
                            }
                        }
                    } else {
                        print("Failed to start camera feed for: \(device.displayName)")
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
    
    private func refreshCameras() {
        Task {
            await productionManager.cameraFeedManager.forceRefreshDevices()
        }
    }
    
    private func discoverCamerasOnly() async {
        print("Live Production: Discovering cameras (no auto-start)")
        await productionManager.cameraFeedManager.getAvailableDevices()
        let devices = productionManager.cameraFeedManager.availableDevices
        print("Found \(devices.count) camera devices - waiting for user selection")
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

// Shimmer effect extension
extension View {
    func shimmer() -> some View {
        self.overlay(
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, Color.white.opacity(0.4), Color.clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .rotationEffect(.degrees(10))
                .offset(x: -200)
                .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: UUID())
        )
        .clipped()
    }
}

// MARK: - Live Camera Feed View Component

struct LiveCameraFeedView: View {
    @ObservedObject var feed: CameraFeed
    @State private var frameUpdateTrigger = 0
    
    var body: some View {
        Group {
            if let previewImage = feed.previewImage {
                // Show the live camera feed
                Image(decorative: previewImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Color.black)
                    .id("live-feed-\(feed.id)-\(frameUpdateTrigger)") // Force updates
                    .overlay(
                        VStack {
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                
                                Text("LIVE: \(feed.device.displayName)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                            .padding(.top, 8)
                            .padding(.horizontal, 8)
                            // Changed multiplier
                            Spacer()
                            
                            HStack {
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Resolution: \(Int(previewImage.width))×\(Int(previewImage.height))")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.9))
                                    
                                    Text("Frame: \(feed.frameCount)")
                                        .font(.caption2)
                                        .foregroundColor(.green.opacity(0.8))
                                }
                                .padding(6)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                            }
                            .padding(.bottom, 8)
                            .padding(.horizontal, 8)
                        }
                    )
                    .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
                        // Force UI updates at 30fps by changing the trigger
                        frameUpdateTrigger += 1
                    }
            } else {
                // Camera is connecting - show state info
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
                            
                            Text(feed.connectionStatus.displayText)
                                .font(.caption)
                                .foregroundColor(feed.connectionStatus.color)
                        }
                    )
            }
        }
    }
}