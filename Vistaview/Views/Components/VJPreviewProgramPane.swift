//
//  VJPreviewProgramPane.swift
//  Vistaview
//
//  VJ-style Preview/Program control pane with stacked layout
//

import SwiftUI
import AVFoundation
import Combine
import Foundation

struct VJPreviewProgramPane: View {
    @StateObject private var previewProgramManager: PreviewProgramManager
    @ObservedObject var productionManager: UnifiedProductionManager
    @ObservedObject var effectManager: EffectManager
    @Binding var mediaFiles: [MediaFile]
    
    init(productionManager: UnifiedProductionManager, effectManager: EffectManager, mediaFiles: Binding<[MediaFile]>) {
        self.productionManager = productionManager
        self.effectManager = effectManager
        self._mediaFiles = mediaFiles
        
        // Initialize the preview/program manager with effect manager
        self._previewProgramManager = StateObject(wrappedValue: PreviewProgramManager(
            cameraFeedManager: productionManager.cameraFeedManager,
            unifiedProductionManager: productionManager,
            effectManager: effectManager
        ))
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Header with controls
            HStack {
                Text("Preview/Program")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Take button
                Button("TAKE") {
                    previewProgramManager.take()
                }
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(4)
                
                // Auto transition button
                Button("AUTO") {
                    previewProgramManager.transition(duration: 2.0)
                }
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(previewProgramManager.isTransitioning ? Color.orange : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(4)
                .disabled(previewProgramManager.previewSource == .none)
            }
            
            // Preview monitor (top)
            VStack(spacing: 4) {
                HStack {
                    Text("PREVIEW")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)
                    
                    Spacer()
                    
                    Text(previewProgramManager.previewSourceDisplayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                VJPreviewMonitor(
                    source: previewProgramManager.previewSource,
                    image: previewProgramManager.previewImage,
                    cameraFeedManager: productionManager.cameraFeedManager,
                    effectManager: effectManager,
                    previewProgramManager: previewProgramManager,
                    isPreview: true
                )
                .frame(height: 80)
                .background(Color.black)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.yellow, lineWidth: 2)
                )
            }
            
            // Program monitor (bottom)
            VStack(spacing: 4) {
                HStack {
                    Text("PROGRAM")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Spacer()
                    
                    Text(previewProgramManager.programSourceDisplayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                VJPreviewMonitor(
                    source: previewProgramManager.programSource,
                    image: previewProgramManager.programImage,
                    cameraFeedManager: productionManager.cameraFeedManager,
                    effectManager: effectManager,
                    previewProgramManager: previewProgramManager,
                    isPreview: false
                )
                .frame(height: 80)
                .background(Color.black)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red, lineWidth: 2)
                )
            }
            
            // Crossfader
            VStack(spacing: 4) {
                HStack {
                    Text("CROSSFADE")
                        .font(.caption2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Text("\(Int(previewProgramManager.crossfaderValue * 100))%")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                
                Slider(
                    value: $previewProgramManager.crossfaderValue,
                    in: 0...1
                ) {
                    Text("Crossfader")
                } minimumValueLabel: {
                    Text("PGM")
                        .font(.caption2)
                        .foregroundColor(.red)
                } maximumValueLabel: {
                    Text("PVW")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
                .accentColor(.blue)
            }
            
            // Source selection buttons
            VStack(spacing: 6) {
                Text("Sources")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                // Camera sources
                if !productionManager.cameraFeedManager.activeFeeds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(productionManager.cameraFeedManager.activeFeeds) { feed in
                                sourceButton(for: feed.asContentSource(), label: feed.device.displayName, icon: "camera.fill")
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                
                // Media sources
                if !mediaFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(mediaFiles.prefix(5)) { file in
                                sourceButton(for: file.asContentSource(), label: file.name, icon: file.fileType.icon)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                
                // Virtual sources
                if !productionManager.availableVirtualCameras.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(productionManager.availableVirtualCameras, id: \.id) { camera in
                                sourceButton(for: camera.asContentSource(), label: camera.name, icon: "video.3d")
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            
            // Media playback controls (only show if media is selected)
            if case .media(let file, let player) = previewProgramManager.previewSource {
                VJMediaPlaybackControls(
                    previewProgramManager: previewProgramManager,
                    isPreview: true
                )
            }
            
            if case .media(let file, let player) = previewProgramManager.programSource {
                VJMediaPlaybackControls(
                    previewProgramManager: previewProgramManager,
                    isPreview: false
                )
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func sourceButton(for source: ContentSource, label: String, icon: String) -> some View {
        Menu {
            Button("Load to Preview") {
                previewProgramManager.loadToPreview(source)
            }
            
            Button("Load to Program") {
                previewProgramManager.loadToProgram(source)
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(width: 60, height: 40)
            .background(Color.blue.opacity(0.2))
            .foregroundColor(.blue)
            .cornerRadius(4)
        }
        .menuStyle(BorderlessButtonMenuStyle())
    }
}

struct VJPreviewMonitor: View {
    let source: ContentSource
    let image: CGImage?
    @ObservedObject var cameraFeedManager: CameraFeedManager
    @ObservedObject var effectManager: EffectManager
    @ObservedObject var previewProgramManager: PreviewProgramManager
    let isPreview: Bool
    
    @State private var isTargeted = false
    
    private var effectCount: Int {
        isPreview ? 
            (previewProgramManager.getPreviewEffectChain()?.effects.count ?? 0) :
            (previewProgramManager.getProgramEffectChain()?.effects.count ?? 0)
    }
    
    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(Color.black)
            
            // Content based on source type
            switch source {
            case .camera(let feed):
                // FIXED: Use efficient NSView wrapper instead of SwiftUI Image
                EfficientCameraMonitorView(
                    feed: feed,
                    previewProgramManager: previewProgramManager,
                    isPreview: isPreview
                )
                
            case .media(let file, let player):
                // Always use the actual player from the PreviewProgramManager
                if let actualPlayer = isPreview ? previewProgramManager.previewPlayer : previewProgramManager.programPlayer {
                    FrameBasedVideoPlayerView(player: actualPlayer)
                } else {
                    VStack {
                        Image(systemName: file.fileType.icon)
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                        Text(file.name)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                
            case .virtual(let camera):
                VStack {
                    Image(systemName: "video.3d")
                        .font(.title2)
                        .foregroundColor(.blue.opacity(0.7))
                    Text(camera.name)
                        .font(.caption2)
                        .foregroundColor(.blue.opacity(0.7))
                        .lineLimit(1)
                }
                
            case .none:
                VStack {
                    Image(systemName: isPreview ? "tv" : "dot.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundColor(.gray.opacity(0.5))
                    Text(isPreview ? "No Preview" : "No Program")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.5))
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
            handleEffectDrop(items)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .contextMenu {
            if effectCount > 0 {
                Button("Clear Effects") {
                    if isPreview {
                        previewProgramManager.clearPreviewEffects()
                    } else {
                        previewProgramManager.clearProgramEffects()
                    }
                }
                
                Button("View Effects") {
                    let chain = isPreview ? 
                        previewProgramManager.getPreviewEffectChain() :
                        previewProgramManager.getProgramEffectChain()
                    effectManager.selectedChain = chain
                }
            }
        }
    }
    
    private func handleEffectDrop(_ items: [EffectDragItem]) -> Bool {
        guard let item = items.first else { return false }
        
        if isPreview {
            previewProgramManager.addEffectToPreview(item.effectType)
        } else {
            previewProgramManager.addEffectToProgram(item.effectType)
        }
        
        // Visual feedback
        let feedbackGenerator = NSHapticFeedbackManager.defaultPerformer
        feedbackGenerator.perform(.generic, performanceTime: .now)
        
        return true
    }
}

// MARK: - EFFICIENT Camera Monitor (CPU Optimized)

struct EfficientCameraMonitorView: NSViewRepresentable {
    let feed: CameraFeed
    let previewProgramManager: PreviewProgramManager
    let isPreview: Bool
    
    func makeNSView(context: Context) -> EfficientCameraView {
        let view = EfficientCameraView(
            feed: feed,
            previewProgramManager: previewProgramManager,
            isPreview: isPreview
        )
        return view
    }
    
    func updateNSView(_ nsView: EfficientCameraView, context: Context) {
        // No updates needed - view handles its own observation
    }
}

class EfficientCameraView: NSView {
    private let feed: CameraFeed
    private let previewProgramManager: PreviewProgramManager
    private let isPreview: Bool
    private var imageLayer: CALayer!
    private var lastProcessedFrameCount: Int = 0
    
    // Use simple observation instead of Combine
    private var frameObservationTimer: Timer?
    
    init(feed: CameraFeed, previewProgramManager: PreviewProgramManager, isPreview: Bool) {
        self.feed = feed
        self.previewProgramManager = previewProgramManager
        self.isPreview = isPreview
        super.init(frame: .zero)
        
        setupEfficientLayer()
        setupSimpleObservation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
    
    private func setupEfficientLayer() {
        // Simple, efficient CALayer for video display
        imageLayer = CALayer()
        imageLayer.frame = bounds
        imageLayer.backgroundColor = CGColor.black
        imageLayer.contentsGravity = .resizeAspectFill
        
        // Optimize for video
        imageLayer.isOpaque = true
        imageLayer.drawsAsynchronously = true
        
        wantsLayer = true
        layer = imageLayer
    }
    
    private func setupSimpleObservation() {
        // EFFICIENT: Use simple timer that only processes when frame count changes
        frameObservationTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            guard let self = self,
                  self.feed.frameCount != self.lastProcessedFrameCount,
                  self.feed.connectionStatus == .connected else { return }
            
            self.lastProcessedFrameCount = self.feed.frameCount
            self.updateImageContent()
        }
    }
    
    private func updateImageContent() {
        guard let cgImage = feed.previewImage else {
            // Show loading state
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageLayer.contents = nil
            CATransaction.commit()
            return
        }
        
        // Apply effects if they exist
        var processedImage = cgImage
        
        if let effectChain = isPreview ? 
            previewProgramManager.getPreviewEffectChain() :
            previewProgramManager.getProgramEffectChain(),
           !effectChain.effects.isEmpty {
            
            let outputType: PreviewProgramManager.OutputType = isPreview ? .preview : .program
            if let effectsProcessed = previewProgramManager.processImageWithEffects(cgImage, for: outputType) {
                processedImage = effectsProcessed
            }
        }
        
        // EFFICIENT: Direct layer content update
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = processedImage
        CATransaction.commit()
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }
    
    deinit {
        frameObservationTimer?.invalidate()
        frameObservationTimer = nil
    }
}

struct VJMediaPlaybackControls: View {
    @ObservedObject var previewProgramManager: PreviewProgramManager
    let isPreview: Bool
    
    private var isPlaying: Bool {
        isPreview ? previewProgramManager.isPreviewPlaying : previewProgramManager.isProgramPlaying
    }
    
    private var currentTime: TimeInterval {
        isPreview ? previewProgramManager.previewCurrentTime : previewProgramManager.programCurrentTime
    }
    
    private var duration: TimeInterval {
        isPreview ? previewProgramManager.previewDuration : previewProgramManager.programDuration
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Progress bar
            ProgressView(value: duration > 0 ? currentTime / duration : 0.0)
                .progressViewStyle(LinearProgressViewStyle(tint: isPreview ? .yellow : .red))
                .frame(height: 4)
            
            // Time display and controls
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
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
                        .foregroundColor(isPreview ? .yellow : .red)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.2))
        .cornerRadius(4)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}