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
    @StateObject private var viewModel = StreamingViewModel()
    @State private var rtmpURL = "rtmp://live.twitch.tv/live/"
    @State private var streamKey = ""
    @State private var selectedTab = 0
    @State private var selectedLayer = 0
    @State private var showingFilePicker = false
    @State private var mediaFiles: [MediaFile] = []
    @State private var selectedPlatform = "Twitch"
    @State private var productionMode: ProductionMode = .live
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar
            HStack {
                // Mode Switcher
                HStack(spacing: 0) {
                    Button(action: { productionMode = .live }) {
                        HStack {
                            Image(systemName: "video.circle.fill")
                            Text("Live Production")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(productionMode == .live ? Color.blue : Color.clear)
                        .foregroundColor(productionMode == .live ? .white : .primary)
                        .cornerRadius(8, corners: [.topLeft, .bottomLeft])
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { productionMode = .virtual }) {
                        HStack {
                            Image(systemName: "cube.transparent.fill")
                            Text("Virtual Production")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(productionMode == .virtual ? Color.blue : Color.clear)
                        .foregroundColor(productionMode == .virtual ? .white : .primary)
                        .cornerRadius(8, corners: [.topRight, .bottomRight])
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                Spacer()
                
                // Global Controls
                HStack {
                    if productionMode == .live {
                        // Streaming status indicator
                        HStack {
                            Circle()
                                .fill(viewModel.isPublishing ? Color.red : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(viewModel.isPublishing ? "LIVE" : "OFFLINE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(viewModel.isPublishing ? .red : .secondary)
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
                case .live:
                    LiveProductionView(
                        viewModel: viewModel,
                        rtmpURL: $rtmpURL,
                        streamKey: $streamKey,
                        selectedTab: $selectedTab,
                        selectedLayer: $selectedLayer,
                        showingFilePicker: $showingFilePicker,
                        mediaFiles: $mediaFiles,
                        selectedPlatform: $selectedPlatform
                    )
                case .virtual:
                    VirtualProductionView()
                }
            }
        }
        .task {
            await requestPermissions()
            await viewModel.setupCamera()
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.movie, .image, .audio],
            allowsMultipleSelection: true
        ) { result in
            // Handle file import
        }
    }
    
    private func requestPermissions() async {
        let _ = await AVCaptureDevice.requestAccess(for: .video)
        let _ = await AVCaptureDevice.requestAccess(for: .audio)
    }
}

// MARK: - Live Production View (Original Interface)

struct LiveProductionView: View {
    let viewModel: StreamingViewModel
    @Binding var rtmpURL: String
    @Binding var streamKey: String
    @Binding var selectedTab: Int
    @Binding var selectedLayer: Int
    @Binding var showingFilePicker: Bool
    @Binding var mediaFiles: [MediaFile]
    @Binding var selectedPlatform: String
    
    var body: some View {
        HSplitView {
            // Left Panel - Sources & Media
            VStack(spacing: 0) {
                // Source Tabs
                HStack(spacing: 0) {
                    ForEach(["Camera", "Media", "Effects"], id: \.self) { tab in
                        Button(action: {
                            selectedTab = ["Camera", "Media", "Effects"].firstIndex(of: tab) ?? 0
                        }) {
                            Text(tab)
                                .font(.caption)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(selectedTab == ["Camera", "Media", "Effects"].firstIndex(of: tab) ?
                                          Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(selectedTab == ["Camera", "Media", "Effects"].firstIndex(of: tab) ?
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
                        CameraSourceView(viewModel: viewModel)
                    case 1:
                        MediaBrowserView(mediaFiles: $mediaFiles, showingFilePicker: $showingFilePicker)
                    case 2:
                        EffectsView()
                    default:
                        CameraSourceView(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 300, maxWidth: 400)
            .background(Color.black.opacity(0.05))
            
            // Center Panel - Main Preview & Layers
            VStack(spacing: 0) {
                // Main Preview
                VStack {
                    HStack {
                        Text("Output Preview")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundColor(viewModel.cameraSetup ? .green : .orange)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Main video output
                    CameraPreview(viewModel: viewModel)
                        .background(Color.black)
                        .overlay(
                            Group {
                                if !viewModel.cameraSetup {
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
                
                // Layer Control
                LayerControlView(selectedLayer: $selectedLayer)
            }
            .frame(minWidth: 500)
            
            // Right Panel - Output & Controls
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
                        // Streaming Section
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
                                    VStack(spacing: 4) {
                                        SecureField("Get from Twitch Creator Dashboard", text: $streamKey)
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
                                        .fill(viewModel.isPublishing ? Color.green : (viewModel.cameraSetup ? Color.orange : Color.red))
                                        .frame(width: 8, height: 8)
                                    Text(viewModel.isPublishing ? "LIVE" : (viewModel.cameraSetup ? "Ready" : "Not Ready"))
                                        .font(.caption)
                                        .foregroundColor(viewModel.isPublishing ? .green : .secondary)
                                }
                                
                                Button(action: {
                                    Task {
                                        await toggleStreaming()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: viewModel.isPublishing ? "stop.circle.fill" : "play.circle.fill")
                                        Text(viewModel.isPublishing ? "Stop Streaming" : "Start Streaming")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(viewModel.isPublishing ? Color.red : Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .disabled(!viewModel.cameraSetup)
                            }
                        }
                        
                        // Recording Section
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
                        
                        // Audio Controls
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
                        
                        // Statistics
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
                                    Text(viewModel.isPublishing ? "00:05:23" : "00:00:00")
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
        if viewModel.isPublishing {
            await viewModel.stop()
        } else {
            do {
                try await viewModel.start(rtmpURL: rtmpURL, streamKey: streamKey)
            } catch {
                print("Setup error:", error)
            }
        }
    }
}

// MARK: - Source Views (keeping your existing views)

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

struct LayerControlView: View {
    @Binding var selectedLayer: Int
    
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
                                Text("Layer \(index + 1)")
                                    .font(.caption2)
                                    .foregroundColor(index == selectedLayer ? .blue : .secondary)
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

// MARK: - Supporting Views

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

// MARK: - Helper Extension for Rounded Corners

extension View {
    func cornerRadius(_ radius: CGFloat, corners: CornerSet) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct CornerSet: OptionSet {
    let rawValue: Int
    
    static let topLeft = CornerSet(rawValue: 1 << 0)
    static let topRight = CornerSet(rawValue: 1 << 1)
    static let bottomLeft = CornerSet(rawValue: 1 << 2)
    static let bottomRight = CornerSet(rawValue: 1 << 3)
    
    static let all: CornerSet = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: CornerSet = .all

    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.size.width
        let height = rect.size.height
        
        // Start from top-left
        let topLeftRadius = corners.contains(.topLeft) ? radius : 0
        let topRightRadius = corners.contains(.topRight) ? radius : 0
        let bottomLeftRadius = corners.contains(.bottomLeft) ? radius : 0
        let bottomRightRadius = corners.contains(.bottomRight) ? radius : 0
        
        path.move(to: CGPoint(x: topLeftRadius, y: 0))
        
        // Top edge and top-right corner
        path.addLine(to: CGPoint(x: width - topRightRadius, y: 0))
        if topRightRadius > 0 {
            path.addArc(center: CGPoint(x: width - topRightRadius, y: topRightRadius),
                       radius: topRightRadius,
                       startAngle: Angle(degrees: -90),
                       endAngle: Angle(degrees: 0),
                       clockwise: false)
        }
        
        // Right edge and bottom-right corner
        path.addLine(to: CGPoint(x: width, y: height - bottomRightRadius))
        if bottomRightRadius > 0 {
            path.addArc(center: CGPoint(x: width - bottomRightRadius, y: height - bottomRightRadius),
                       radius: bottomRightRadius,
                       startAngle: Angle(degrees: 0),
                       endAngle: Angle(degrees: 90),
                       clockwise: false)
        }
        
        // Bottom edge and bottom-left corner
        path.addLine(to: CGPoint(x: bottomLeftRadius, y: height))
        if bottomLeftRadius > 0 {
            path.addArc(center: CGPoint(x: bottomLeftRadius, y: height - bottomLeftRadius),
                       radius: bottomLeftRadius,
                       startAngle: Angle(degrees: 90),
                       endAngle: Angle(degrees: 180),
                       clockwise: false)
        }
        
        // Left edge and top-left corner
        path.addLine(to: CGPoint(x: 0, y: topLeftRadius))
        if topLeftRadius > 0 {
            path.addArc(center: CGPoint(x: topLeftRadius, y: topLeftRadius),
                       radius: topLeftRadius,
                       startAngle: Angle(degrees: 180),
                       endAngle: Angle(degrees: 270),
                       clockwise: false)
        }
        
        path.closeSubpath()
        return path
    }
}
