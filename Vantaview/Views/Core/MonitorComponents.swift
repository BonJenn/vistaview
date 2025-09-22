//
//  MonitorComponents.swift
//  Vantaview
//
//  Missing monitor and control components for ContentView
//

import SwiftUI
import AVFoundation
import MetalKit

// MARK: - Simple Preview Monitor View (unchanged data path)

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
            
            switch productionManager.previewProgramManager.previewSource {
            case .camera(let feed):
                CameraFeedLivePreview(feed: feed)
                
            case .media(let file, _):
                if file.fileType == .image, let previewImage = productionManager.previewProgramManager.previewImage {
                    Image(previewImage, scale: 1.0, label: Text("Preview"))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    MetalVideoView(
                        textureSupplier: productionManager.previewProgramManager.makePreviewTextureSupplier(),
                        preferredFPS: 60,
                        device: productionManager.effectManager.metalDevice
                    )
                }
                
            case .virtual(_):
                VStack(spacing: 8) {
                    Image(systemName: "video.3d")
                        .font(.system(size: 24))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Virtual Source")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.5))
                }
                
            case .none:
                VStack(spacing: 8) {
                    Image(systemName: "tv")
                        .font(.system(size: 24))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No Preview")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            
            // Render composited PiP layers (non-interactive surface)
            CompositedLayersContent(productionManager: productionManager, isPreview: true)
                .allowsHitTesting(false)
            
            // Interactive overlay for selecting/moving/scaling/editing titles & PiPs
            LayersInteractiveOverlay(isPreview: true)
                .allowsHitTesting(true)
            
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
    }
    
    private func handleEffectDrop(_ items: [EffectDragItem], isPreview: Bool) {
        guard let item = items.first else { return }
        if isPreview {
            productionManager.previewProgramManager.addEffectToPreview(item.effectType)
        } else {
            productionManager.previewProgramManager.addEffectToProgram(item.effectType)
        }
        let feedbackGenerator = NSHapticFeedbackManager.defaultPerformer
        feedbackGenerator.perform(.generic, performanceTime: .now)
    }
}

private struct CameraFeedLivePreview: View {
    @ObservedObject var feed: CameraFeed
    
    var body: some View {
        Group {
            if let img = feed.previewImage {
                Image(img, scale: 1.0, label: Text("Camera Preview"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        VStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                            Text("Waiting for camera...")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )
            }
        }
        .clipped()
    }
}

// MARK: - Simple Program Monitor View (NOW backed by ProgramFeedView renderer)

struct SimpleProgramMonitorView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @State private var isTargeted = false
    
    private var effectCount: Int {
        productionManager.previewProgramManager.getProgramEffectChain()?.effects.count ?? 0
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)
            
            switch productionManager.previewProgramManager.programSource {
            case .camera(let feed):
                CameraFeedLivePreview(feed: feed)
                
            case .media(let file, _):
                if file.fileType == .image, let programImage = productionManager.previewProgramManager.programImage {
                    Image(programImage, scale: 1.0, label: Text("Program"))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    MetalVideoView(
                        textureSupplier: productionManager.previewProgramManager.makeProgramTextureSupplier(),
                        preferredFPS: 60,
                        device: productionManager.effectManager.metalDevice
                    )
                }
                
            case .virtual(_):
                VStack(spacing: 8) {
                    Image(systemName: "video.3d")
                        .font(.system(size: 24))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Virtual Source")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.5))
                }
                
            case .none:
                ProgramFeedView(productionManager: productionManager)
            }
            
            // Render composited PiP layers (non-interactive surface)
            CompositedLayersContent(productionManager: productionManager, isPreview: false)
                .allowsHitTesting(false)
            
            // Interactive overlay for selecting/moving/scaling/editing titles & PiPs
            LayersInteractiveOverlay(isPreview: false)
                .allowsHitTesting(true)
            
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
    }
    
    private func handleEffectDrop(_ items: [EffectDragItem], isPreview: Bool) {
        guard let item = items.first else { return }
        if isPreview {
            productionManager.previewProgramManager.addEffectToPreview(item.effectType)
        } else {
            productionManager.previewProgramManager.addEffectToProgram(item.effectType)
        }
        let feedbackGenerator = NSHapticFeedbackManager.defaultPerformer
        feedbackGenerator.perform(.generic, performanceTime: .now)
    }
}

// MARK: - Camera Device Button (selecting starts feed AND switches program immediately)

struct CameraDeviceButton: View {
    let device: LegacyCameraDevice
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        Button(action: {
            Task {
                // Convert LegacyCameraDevice to CameraDeviceInfo for the new API
                let deviceInfo = device.asCameraDeviceInfo
                _ = await productionManager.cameraFeedManager.startFeed(for: deviceInfo)
            }
        }) {
            VStack(spacing: 8) {
                Rectangle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(height: 60)
                    .overlay(
                        // Use a generic camera icon since device.icon doesn't exist
                        Image(systemName: "video.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                    )
                    .liquidGlassMonitor(borderColor: TahoeDesign.Colors.preview, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: true)
                
                VStack(spacing: 2) {
                    Text(device.displayName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(device.manufacturer)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LiveCameraFeedButton: View {
    @ObservedObject var feed: CameraFeed
    @ObservedObject var productionManager: UnifiedProductionManager
    
    var body: some View {
        Button(action: {
            productionManager.previewProgramManager.loadToPreview(.camera(feed))
        }) {
            VStack(spacing: 8) {
                Rectangle()
                    .fill(Color.green.opacity(0.2))
                    .frame(height: 60)
                    .overlay(
                        Group {
                            if let previewImage = feed.previewImage {
                                Image(nsImage: NSImage(cgImage: previewImage, size: NSSize(width: previewImage.width, height: previewImage.height)))
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .clipped()
                            } else {
                                Image(systemName: "video.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.green)
                            }
                        }
                    )
                    .liquidGlassMonitor(borderColor: TahoeDesign.Colors.live, cornerRadius: TahoeDesign.CornerRadius.lg, glowIntensity: 0.4, isActive: feed.isActive)
                
                VStack(spacing: 2) {
                    Text(feed.device.displayName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(feed.connectionStatus.color)
                            .frame(width: 6, height: 6)
                        Text("\(feed.frameCount) frames")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}