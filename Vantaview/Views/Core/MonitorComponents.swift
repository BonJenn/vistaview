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
            
            CompositedLayersContent(productionManager: productionManager)
                .allowsHitTesting(false)
            
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
            _ = await productionManager.cameraFeedManager.startFeed(for: device)
            await MainActor.run {
                productionManager.switchProgram(to: device.deviceID)
                isConnecting = false
            }
        }
    }
}

// MARK: - Live Camera Feed Button (route to Preview using new pipeline)

struct LiveCameraFeedButton: View {
    @ObservedObject var feed: CameraFeed
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
                Task { await productionManager.cameraFeedManager.stopFeed(feed) }
            }
        }
    }
    
    private func loadFeedToPreview() {
        productionManager.previewProgramManager.loadToPreview(feed.asContentSource())
        productionManager.selectedPreviewCameraID = feed.device.deviceID
        productionManager.previewProgramManager.objectWillChange.send()
        productionManager.objectWillChange.send()
    }
    
    private func loadFeedToProgram() {
        productionManager.switchProgram(to: feed.device.deviceID)
    }
}