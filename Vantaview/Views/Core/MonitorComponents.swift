//
//  MonitorComponents.swift
//  Vantaview
//
//  Missing monitor and control components for ContentView
//

import SwiftUI
import AVFoundation
import MetalKit

// MARK: - Simple Monitor Views

struct SimplePreviewMonitorView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @State private var debugTimer: Timer?
    @State private var isTargeted = false
    
    private var effectCount: Int {
        productionManager.previewProgramManager.getPreviewEffectChain()?.effects.count ?? 0
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)
            
            // Use Metal texture if available, otherwise fallback to CGImage
            if productionManager.previewProgramManager.previewMetalTexture != nil {
                MetalVideoView(textureSupplier: {
                    let texture = productionManager.previewProgramManager.previewMetalTexture
                    if texture != nil {
                        print("📺 SimplePreviewMonitorView: Metal texture available - \(texture!.width)x\(texture!.height)")
                    } else {
                        print("❌ SimplePreviewMonitorView: Metal texture is nil")
                    }
                    return texture
                })
                .onAppear {
                    print("🎬 SimplePreviewMonitorView: MetalVideoView appeared")
                }
            } else if let previewImage = productionManager.previewProgramManager.previewImage {
                Image(previewImage, scale: 1.0, label: Text("Preview"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .onAppear {
                        print("🖼️ SimplePreviewMonitorView: CGImage fallback - \(previewImage.width)x\(previewImage.height)")
                    }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "tv")
                        .font(.system(size: 24))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No Preview")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.5))
                }
                .onAppear {
                    print("❌ SimplePreviewMonitorView: No content available")
                    print("   - Metal texture: \(productionManager.previewProgramManager.previewMetalTexture != nil)")
                    print("   - CGImage: \(productionManager.previewProgramManager.previewImage != nil)")
                    print("   - Preview source: \(productionManager.previewProgramManager.previewSource)")
                    
                    // Start debug timer to monitor state changes
                    debugTimer?.invalidate()
                    debugTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        if case .media(let file, _) = productionManager.previewProgramManager.previewSource {
                            print("🔍 DEBUG: Preview source is media '\(file.name)' but no texture visible")
                            print("   - Metal texture exists: \(productionManager.previewProgramManager.previewMetalTexture != nil)")
                            print("   - Is playing: \(productionManager.previewProgramManager.isPreviewPlaying)")
                        }
                    }
                }
                .onDisappear {
                    debugTimer?.invalidate()
                    debugTimer = nil
                }
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
        .clipped()
        .dropDestination(for: EffectDragItem.self) { items, location in
            handleEffectDrop(items, isPreview: true)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .contextMenu {
            if effectCount > 0 {
                Button("Clear Effects") {
                    productionManager.previewProgramManager.clearPreviewEffects()
                }
                
                Button("View Effects") {
                    if let chain = productionManager.previewProgramManager.getPreviewEffectChain() {
                        productionManager.effectManager.selectedChain = chain
                    }
                }
            }
        }
        .onChange(of: productionManager.previewProgramManager.previewSource) { _, newSource in
            print("🔄 SimplePreviewMonitorView: Preview source changed to \(newSource)")
            
            // Force a small delay and then check texture availability
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("🔍 POST-CHANGE DEBUG:")
                print("   - Metal texture: \(productionManager.previewProgramManager.previewMetalTexture != nil)")
                
                // Force UI refresh
                productionManager.previewProgramManager.objectWillChange.send()
            }
        }
    }
    
    private func handleEffectDrop(_ items: [EffectDragItem], isPreview: Bool) {
        guard let item = items.first else { return }
        
        if isPreview {
            productionManager.previewProgramManager.addEffectToPreview(item.effectType)
        } else {
            productionManager.previewProgramManager.addEffectToProgram(item.effectType)
        }
        
        // Visual feedback
        let feedbackGenerator = NSHapticFeedbackManager.defaultPerformer
        feedbackGenerator.perform(.generic, performanceTime: .now)
    }
}

struct SimpleProgramMonitorView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @State private var debugTimer: Timer?
    @State private var isTargeted = false
    
    private var effectCount: Int {
        productionManager.previewProgramManager.getProgramEffectChain()?.effects.count ?? 0
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)
            
            // Base program content (Metal texture or CGImage)
            Group {
                if productionManager.previewProgramManager.programMetalTexture != nil {
                    MetalVideoView(textureSupplier: {
                        let texture = productionManager.previewProgramManager.programMetalTexture
                        if texture != nil {
                            print("📺 SimpleProgramMonitorView: Metal texture available - \(texture!.width)x\(texture!.height)")
                        } else {
                            print("❌ SimpleProgramMonitorView: Metal texture is nil")
                        }
                        return texture
                    })
                    .onAppear {
                        print("📺 SimpleProgramMonitorView: MetalVideoView appeared")
                    }
                } else if let programImage = productionManager.previewProgramManager.programImage {
                    Image(programImage, scale: 1.0, label: Text("Program"))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .onAppear {
                            print("🖼️ SimpleProgramMonitorView: CGImage fallback - \(programImage.width)x\(programImage.height)")
                        }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 24))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No Program")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                    .onAppear {
                        print("❌ SimpleProgramMonitorView: No content available")
                        print("   - Metal texture: \(productionManager.previewProgramManager.programMetalTexture != nil)")
                        print("   - CGImage: \(productionManager.previewProgramManager.programImage != nil)")
                        print("   - Program source: \(productionManager.previewProgramManager.programSource)")
                        
                        // Start debug timer to monitor state changes
                        debugTimer?.invalidate()
                        debugTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                            if case .media(let file, _) = productionManager.previewProgramManager.programSource {
                                print("🔍 DEBUG: Program source is media '\(file.name)' but no texture visible")
                                print("   - Metal texture exists: \(productionManager.previewProgramManager.programMetalTexture != nil)")
                                print("   - Is playing: \(productionManager.previewProgramManager.isProgramPlaying)")
                            }
                        }
                    }
                    .onDisappear {
                        debugTimer?.invalidate()
                        debugTimer = nil
                    }
                }
            }
            
            // IMPORTANT: PiP layers composited on top
            CompositedLayersContent(productionManager: productionManager)
                .allowsHitTesting(false) // Prevent interaction in monitor view
            
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
        .clipped()
        .dropDestination(for: EffectDragItem.self) { items, location in
            handleEffectDrop(items, isPreview: false)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .contextMenu {
            if effectCount > 0 {
                Button("Clear Effects") {
                    productionManager.previewProgramManager.clearProgramEffects()
                }
                
                Button("View Effects") {
                    if let chain = productionManager.previewProgramManager.getProgramEffectChain() {
                        productionManager.effectManager.selectedChain = chain
                    }
                }
            }
        }
        .onChange(of: productionManager.previewProgramManager.programSource) { _, newSource in
            print("🔄 SimpleProgramMonitorView: Program source changed to \(newSource)")
            
            // Force a small delay and then check texture availability
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("🔍 PROGRAM POST-CHANGE DEBUG:")
                print("   - Metal texture: \(productionManager.previewProgramManager.programMetalTexture != nil)")
                
                // Force UI refresh
                productionManager.previewProgramManager.objectWillChange.send()
            }
        }
    }
    
    private func handleEffectDrop(_ items: [EffectDragItem], isPreview: Bool) {
        guard let item = items.first else { return }
        
        if isPreview {
            productionManager.previewProgramManager.addEffectToPreview(item.effectType)
        } else {
            productionManager.previewProgramManager.addEffectToProgram(item.effectType)
        }
        
        // Visual feedback
        let feedbackGenerator = NSHapticFeedbackManager.defaultPerformer
        feedbackGenerator.perform(.generic, performanceTime: .now)
    }
}

// MARK: - Comprehensive Media Controls

struct ComprehensiveMediaControls: View {
    @ObservedObject var previewProgramManager: PreviewProgramManager
    let isPreview: Bool
    let mediaFile: MediaFile
    
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
    
    private var isLoopEnabled: Bool {
        isPreview ? previewProgramManager.previewLoopEnabled : previewProgramManager.programLoopEnabled
    }
    
    private var playbackRate: Float {
        isPreview ? previewProgramManager.previewRate : previewProgramManager.programRate
    }
    
    private var isMuted: Bool {
        isPreview ? previewProgramManager.previewMuted : previewProgramManager.programMuted
    }
    
    var body: some View {
        VStack(spacing: TahoeDesign.Spacing.xs) {
            // Progress scrubber
            VStack(spacing: 2) {
                if duration > 0 {
                    Slider(
                        value: Binding(
                            get: { currentTime },
                            set: { newTime in
                                if isPreview {
                                    previewProgramManager.seekPreview(to: newTime)
                                } else {
                                    previewProgramManager.seekProgram(to: newTime)
                                }
                            }
                        ),
                        in: 0...duration
                    )
                    .accentColor(isPreview ? TahoeDesign.Colors.preview : TahoeDesign.Colors.program)
                } else {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle(tint: isPreview ? TahoeDesign.Colors.preview : TahoeDesign.Colors.program))
                        .frame(height: 4)
                }
            }
            
            // Control buttons and time display
            HStack(spacing: TahoeDesign.Spacing.sm) {
                // Time display
                Text(formatTime(currentTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                
                Spacer()
                
                // Previous frame (if video)
                if mediaFile.fileType == .video {
                    Button(action: {
                        if isPreview {
                            previewProgramManager.stepPreviewBackward()
                        } else {
                            previewProgramManager.stepProgramBackward()
                        }
                    }) {
                        Image(systemName: "backward.frame")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.secondary)
                }
                
                // Play/Pause button
                Button(action: {
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
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption)
                        .foregroundColor(isPreview ? TahoeDesign.Colors.preview : TahoeDesign.Colors.program)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Next frame (if video)
                if mediaFile.fileType == .video {
                    Button(action: {
                        if isPreview {
                            previewProgramManager.stepPreviewForward()
                        } else {
                            previewProgramManager.stepProgramForward()
                        }
                    }) {
                        Image(systemName: "forward.frame")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Duration
                Text(formatTime(duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            // Advanced controls row
            HStack(spacing: TahoeDesign.Spacing.sm) {
                // Loop toggle
                Button(action: {
                    if isPreview {
                        previewProgramManager.previewLoopEnabled.toggle()
                    } else {
                        previewProgramManager.programLoopEnabled.toggle()
                    }
                }) {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundColor(isLoopEnabled ? (isPreview ? TahoeDesign.Colors.preview : TahoeDesign.Colors.program) : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Loop playback")
                
                // Speed control
                Menu {
                    ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button(action: {
                            if isPreview {
                                previewProgramManager.previewRate = Float(rate)
                                if isPlaying {
                                    previewProgramManager.previewPlayer?.rate = Float(rate)
                                }
                            } else {
                                previewProgramManager.programRate = Float(rate)
                                if isPlaying {
                                    previewProgramManager.programPlayer?.rate = Float(rate)
                                }
                            }
                        }) {
                            HStack {
                                Text("\(rate, specifier: "%.2g")x")
                                if abs(playbackRate - Float(rate)) < 0.01 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "gauge")
                            .font(.caption)
                        Text("\(playbackRate, specifier: "%.2g")x")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .help("Playback speed")
                
                Spacer()
                
                // Mute toggle
                Button(action: {
                    if isPreview {
                        previewProgramManager.previewMuted.toggle()
                        previewProgramManager.previewPlayer?.volume = previewProgramManager.previewMuted ? 0.0 : previewProgramManager.previewVolume
                    } else {
                        previewProgramManager.programMuted.toggle()
                        previewProgramManager.programPlayer?.volume = previewProgramManager.programMuted ? 0.0 : previewProgramManager.programVolume
                    }
                }) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .font(.caption)
                        .foregroundColor(isMuted ? .orange : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Mute audio")
            }
            
            // Volume control (for audio/video with audio)
            if mediaFile.fileType == .audio || mediaFile.fileType == .video {
                HStack(spacing: TahoeDesign.Spacing.xs) {
                    Image(systemName: isMuted ? "speaker.slash" : "speaker")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Slider(
                        value: Binding(
                            get: { 
                                Double(isPreview ? previewProgramManager.previewVolume : previewProgramManager.programVolume)
                            },
                            set: { newVolume in
                                let volume = Float(newVolume)
                                if isPreview {
                                    previewProgramManager.previewVolume = volume
                                    if !previewProgramManager.previewMuted {
                                        previewProgramManager.previewPlayer?.volume = volume
                                    }
                                } else {
                                    previewProgramManager.programVolume = volume
                                    if !previewProgramManager.programMuted {
                                        previewProgramManager.programPlayer?.volume = volume
                                    }
                                }
                            }
                        ),
                        in: 0...1
                    )
                    .accentColor(.secondary)
                    .disabled(isMuted)
                    
                    Text("\(Int((isPreview ? previewProgramManager.previewVolume : previewProgramManager.programVolume) * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 30)
                        .monospacedDigit()
                }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else { return "00:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Camera Device Button

struct CameraDeviceButton: View {
    let device: CameraDevice
    @ObservedObject var productionManager: UnifiedProductionManager
    
    @State private var isConnecting = false
    
    private var isDeviceConnected: Bool {
        productionManager.cameraFeedManager.activeFeeds.contains { feed in
            feed.device.deviceID == device.deviceID && feed.connectionStatus == .connected
        }
    }
    
    var body: some View {
        Button(action: {
            connectToCamera()
        }) {
            VStack(spacing: TahoeDesign.Spacing.xs) {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 60)
                        .overlay(
                            VStack(spacing: 2) {
                                if isConnecting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: device.icon)
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                    
                                    if isDeviceConnected {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                    }
                                }
                            }
                        )
                        .liquidGlassMonitor(
                            borderColor: isDeviceConnected ? TahoeDesign.Colors.live : .gray,
                            cornerRadius: TahoeDesign.CornerRadius.sm,
                            glowIntensity: 0.3,
                            isActive: isDeviceConnected
                        )
                    
                    // Connection status overlay
                    if isDeviceConnected {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("LIVE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.green)
                                    .cornerRadius(2)
                                    .padding(4)
                            }
                        }
                    }
                }
                
                VStack(spacing: 1) {
                    Text(device.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Text(device.statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isDeviceConnected ? Color.green : Color.gray)
                            .frame(width: 4, height: 4)
                        Text(isDeviceConnected ? "Connected" : "Available")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isConnecting)
    }
    
    private func connectToCamera() {
        guard !isConnecting && !isDeviceConnected else { return }
        
        isConnecting = true
        
        Task {
            await productionManager.cameraFeedManager.startFeed(for: device)
            
            await MainActor.run {
                isConnecting = false
            }
        }
    }
}

// MARK: - Live Camera Feed Button

struct LiveCameraFeedButton: View {
    let feed: CameraFeed
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        Button(action: {
            loadFeedToPreview()
        }) {
            VStack(spacing: TahoeDesign.Spacing.xs) {
                ZStack {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 60)
                    
                    // Live preview thumbnail
                    if let previewImage = feed.previewImage {
                        Image(previewImage, scale: 1.0, label: Text("Camera Preview"))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 60)
                            .clipped()
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: feed.device.icon)
                                .font(.title2)
                                .foregroundColor(.blue)
                            if feed.connectionStatus != .connected {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                    .scaleEffect(0.6)
                            }
                        }
                    }
                    
                    // Live indicator
                    VStack {
                        HStack {
                            if feed.connectionStatus == .connected {
                                HStack(spacing: 2) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 4, height: 4)
                                    Text("LIVE")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(2)
                                .padding(4)
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                    
                    // Frame count indicator (instead of FPS)
                    if feed.connectionStatus == .connected {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                if feed.frameCount > 0 {
                                    Text("\(feed.frameCount)")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.black.opacity(0.7))
                                        .cornerRadius(2)
                                        .padding(4)
                                }
                            }
                        }
                    }
                }
                .liquidGlassMonitor(
                    borderColor: feed.connectionStatus == .connected ? TahoeDesign.Colors.live : TahoeDesign.Colors.virtual,
                    cornerRadius: TahoeDesign.CornerRadius.sm,
                    glowIntensity: 0.4,
                    isActive: feed.connectionStatus == .connected
                )
                
                VStack(spacing: 1) {
                    Text(feed.device.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(feed.connectionStatus == .connected ? Color.green : Color.orange)
                            .frame(width: 4, height: 4)
                        Text(feed.connectionStatus.displayText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button("Load to Preview") {
                loadFeedToPreview()
            }
            
            Button("Load to Program") {
                loadFeedToProgram()
            }
            
            Divider()
            
            Button("Disconnect", role: .destructive) {
                Task {
                    await productionManager.cameraFeedManager.stopFeed(feed)
                }
            }
        }
    }
    
    private func loadFeedToPreview() {
        let cameraSource = feed.asContentSource()
        productionManager.previewProgramManager.loadToPreview(cameraSource)
        
        // Force UI update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            productionManager.previewProgramManager.objectWillChange.send()
            productionManager.objectWillChange.send()
        }
    }
    
    private func loadFeedToProgram() {
        let cameraSource = feed.asContentSource()
        productionManager.previewProgramManager.loadToProgram(cameraSource)
        
        // Force UI update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            productionManager.previewProgramManager.objectWillChange.send()
            productionManager.objectWillChange.send()
        }
    }
}

// MARK: - Preview Provider

#Preview {
    VStack {
        Rectangle()
            .fill(Color.gray)
            .frame(height: 200)
            .overlay(
                Text("Monitor Preview")
                    .foregroundColor(.white)
            )
    }
    .padding()
}