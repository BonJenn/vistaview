//
//  PreviewProgramManager.swift
//  Vistaview
//
//  Manager for handling Preview/Program workflow in VJ-style production
//

import Foundation
import SwiftUI
import AVFoundation
import CoreVideo
import Metal
import MetalKit
import CoreImage

/// Represents a media file that can be loaded into preview/program
struct MediaFile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: URL
    let duration: TimeInterval?
    let fileType: MediaFileType
    
    enum MediaFileType: String, CaseIterable {
        case video = "video"
        case audio = "audio"
        case image = "image"
        
        var icon: String {
            switch self {
            case .video: return "video.fill"
            case .audio: return "waveform"
            case .image: return "photo.fill"
            }
        }
    }
    
    init(name: String, url: URL, fileType: MediaFileType, duration: TimeInterval? = nil) {
        self.name = name
        self.url = url
        self.fileType = fileType
        self.duration = duration
    }
    
    static func == (lhs: MediaFile, rhs: MediaFile) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Represents different types of content that can be displayed
enum ContentSource: Identifiable, Equatable {
    case camera(CameraFeed)
    case media(MediaFile, player: AVPlayer?)
    case virtual(VirtualCamera)
    case none
    
    var id: String {
        switch self {
        case .camera(let feed):
            return "camera-\(feed.id)"
        case .media(let file, let player):
            return "media-\(file.id)-\(player?.description ?? "nil")"
        case .virtual(let camera):
            return "virtual-\(camera.id)"
        case .none:
            return "none"
        }
    }
    
    static func == (lhs: ContentSource, rhs: ContentSource) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages the Preview/Program workflow for VJ-style operation
@MainActor
final class PreviewProgramManager: ObservableObject {
    // Current content sources
    @Published var previewSource: ContentSource = .none
    @Published var programSource: ContentSource = .none
    
    // Media players for video/audio content
    @Published var previewPlayer: AVPlayer?
    @Published var programPlayer: AVPlayer?
    
    // Playback state
    @Published var isPreviewPlaying = false
    @Published var isProgramPlaying = false
    @Published var previewCurrentTime: TimeInterval = 0
    @Published var programCurrentTime: TimeInterval = 0
    @Published var previewDuration: TimeInterval = 0
    @Published var programDuration: TimeInterval = 0
    
    // Preview images for UI display
    @Published var previewImage: CGImage?
    @Published var programImage: CGImage?
    
    // Crossfader value (0.0 = full program, 1.0 = full preview)
    @Published var crossfaderValue: Double = 0.0
    
    // Transition state
    @Published var isTransitioning = false
    @Published var transitionProgress: Double = 0.0
    
    // Dependencies
    private let cameraFeedManager: CameraFeedManager
    private let unifiedProductionManager: UnifiedProductionManager
    private let effectManager: EffectManager
    
    // Timers for updating playback time
    private var previewTimeObserver: Any?
    private var programTimeObserver: Any?
    
    // Image processing
    private let ciContext = CIContext()
    
    // MARK: - Computed Properties for UI
    
    /// Safe access to preview source display name
    var previewSourceDisplayName: String {
        return getDisplayName(for: previewSource)
    }
    
    /// Safe access to program source display name
    var programSourceDisplayName: String {
        return getDisplayName(for: programSource)
    }
    
    init(cameraFeedManager: CameraFeedManager, unifiedProductionManager: UnifiedProductionManager, effectManager: EffectManager) {
        self.cameraFeedManager = cameraFeedManager
        self.unifiedProductionManager = unifiedProductionManager
        self.effectManager = effectManager
    }
    
    deinit {
        // Clean up observers
        Task { @MainActor in
            self.removeTimeObservers()
        }
    }
    
    // MARK: - Cleanup Method
    
    /// Call this method to clean up resources when done with the manager
    func cleanup() {
        removeTimeObservers()
        previewPlayer = nil
        programPlayer = nil
    }
    
    // MARK: - Helper Methods
    
    /// Get display name for a content source
    func getDisplayName(for source: ContentSource) -> String {
        switch source {
        case .camera(let feed):
            return feed.device.displayName
        case .media(let file, let player):
            return file.name
        case .virtual(let camera):
            return camera.name
        case .none:
            return "No Source"
        }
    }
    
    // MARK: - Preview Operations
    
    /// Load content into preview (doesn't affect program)
    func loadToPreview(_ source: ContentSource) {
        let displayName = getDisplayName(for: source)
        
        print("🎬 Loading to preview: \(displayName)")
        
        // Stop current preview if playing
        stopPreview()
        
        switch source {
        case .camera(let feed):
            previewSource = source
            updatePreviewFromCamera(feed)
            
        case .media(let file, let player):
            loadMediaToPreview(file)
            
        case .virtual(let camera):
            previewSource = source
            updatePreviewFromVirtual(camera)
            
        case .none:
            clearPreview()
        }
    }
    
    /// Load content into program (goes live immediately)
    func loadToProgram(_ source: ContentSource) {
        let displayName = getDisplayName(for: source)
        
        print("📺 Loading to program: \(displayName)")
        
        // Stop current program if playing
        stopProgram()
        
        switch source {
        case .camera(let feed):
            programSource = source
            updateProgramFromCamera(feed)
            
        case .media(let file, let player):
            loadMediaToProgram(file)
            
        case .virtual(let camera):
            programSource = source
            updateProgramFromVirtual(camera)
            
        case .none:
            clearProgram()
        }
    }
    
    /// "Take" - Cut preview to program instantly
    func take() {
        print("✂️ TAKE: Moving preview to program")
        
        // Stop current program
        stopProgram()
        
        // Move preview content to program
        let previewContent = previewSource
        loadToProgram(previewContent)
        
        // Reset crossfader to full program
        crossfaderValue = 0.0
        
        print("✅ Take complete: Program now showing \(programSourceDisplayName)")
    }
    
    /// Smooth transition from program to preview over time
    func transition(duration: TimeInterval = 1.0) {
        guard previewSource != .none else { return }
        
        print("🔄 Starting transition over \(duration)s")
        isTransitioning = true
        transitionProgress = 0.0
        
        let steps = 30 // 30 steps for smooth transition
        let stepDuration = duration / Double(steps)
        
        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(step)) {
                self.transitionProgress = Double(step) / Double(steps)
                self.crossfaderValue = self.transitionProgress
                
                if step == steps {
                    // Transition complete - take the cut
                    self.take()
                    self.isTransitioning = false
                    self.transitionProgress = 0.0
                }
            }
        }
    }
    
    // MARK: - Media Playback Controls
    
    func playPreview() {
        guard case .media(let file, let player) = previewSource, let player = player else { return }
        player.play()
        isPreviewPlaying = true
        print("▶️ Preview playing")
    }
    
    func pausePreview() {
        guard case .media(let file, let player) = previewSource, let player = player else { return }
        player.pause()
        isPreviewPlaying = false
        print("⏸️ Preview paused")
    }
    
    func stopPreview() {
        if case .media(let file, let player) = previewSource, let player = player {
            player.pause()
            player.seek(to: CMTime.zero)
            isPreviewPlaying = false
        }
    }
    
    func playProgram() {
        guard case .media(let file, let player) = programSource, let player = player else { return }
        player.play()
        isProgramPlaying = true
        print("▶️ Program playing")
    }
    
    func pauseProgram() {
        guard case .media(let file, let player) = programSource, let player = player else { return }
        player.pause()
        isProgramPlaying = false
        print("⏸️ Program paused")
    }
    
    func stopProgram() {
        if case .media(let file, let player) = programSource, let player = player {
            player.pause()
            player.seek(to: CMTime.zero)
            isProgramPlaying = false
        }
    }
    
    func seekPreview(to time: TimeInterval) {
        guard case .media(let file, let player) = previewSource, let player = player else { return }
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    func seekProgram(to time: TimeInterval) {
        guard case .media(let file, let player) = programSource, let player = player else { return }
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    // MARK: - Private Implementation
    
    private func loadMediaToPreview(_ file: MediaFile) {
        // Remove existing observer if any
        if let observer = previewTimeObserver {
            previewPlayer?.removeTimeObserver(observer)
        }
        
        let player = AVPlayer(url: file.url)
        let newSource = ContentSource.media(file, player: player)
        previewSource = newSource
        previewPlayer = player
        
        // Get duration using modern API
        Task {
            do {
                if let asset = player.currentItem?.asset {
                    let duration = try await asset.load(.duration)
                    if duration.isValid {
                        await MainActor.run {
                            self.previewDuration = CMTimeGetSeconds(duration)
                        }
                    }
                }
            } catch {
                print("Failed to load duration: \(error)")
            }
        }
        
        // Set up time observer for new player
        let previewInterval = CMTime(seconds: 0.1, preferredTimescale: 600)
        previewTimeObserver = player.addPeriodicTimeObserver(forInterval: previewInterval, queue: DispatchQueue.main) { [weak self] time in
            Task { @MainActor in
                self?.previewCurrentTime = CMTimeGetSeconds(time)
            }
        }
        
        print("📼 Media loaded to preview: \(file.name)")
    }
    
    private func loadMediaToProgram(_ file: MediaFile) {
        // Remove existing observer if any
        if let observer = programTimeObserver {
            programPlayer?.removeTimeObserver(observer)
        }
        
        let player = AVPlayer(url: file.url)
        let newSource = ContentSource.media(file, player: player)
        programSource = newSource
        programPlayer = player
        
        // Get duration using modern API
        Task {
            do {
                if let asset = player.currentItem?.asset {
                    let duration = try await asset.load(.duration)
                    if duration.isValid {
                        await MainActor.run {
                            self.programDuration = CMTimeGetSeconds(duration)
                        }
                    }
                }
            } catch {
                print("Failed to load duration: \(error)")
            }
        }
        
        // Set up time observer for new player
        let programInterval = CMTime(seconds: 0.1, preferredTimescale: 600)
        programTimeObserver = player.addPeriodicTimeObserver(forInterval: programInterval, queue: DispatchQueue.main) { [weak self] time in
            Task { @MainActor in
                self?.programCurrentTime = CMTimeGetSeconds(time)
            }
        }
        
        print("📼 Media loaded to program: \(file.name)")
    }
    
    private func updatePreviewFromCamera(_ feed: CameraFeed) {
        // Set up observer for camera feed updates with effects processing
        previewImage = processImageWithEffects(feed.previewImage, for: .preview)
        
        // TODO: Set up continuous updates from camera feed with effects
        print("📹 Camera feed connected to preview: \(feed.device.displayName)")
    }
    
    private func updateProgramFromCamera(_ feed: CameraFeed) {
        // Set up observer for camera feed updates with effects processing
        programImage = processImageWithEffects(feed.previewImage, for: .program)
        
        // TODO: Set up continuous updates from camera feed with effects
        print("📹 Camera feed connected to program: \(feed.device.displayName)")
    }
    
    private func updatePreviewFromVirtual(_ camera: VirtualCamera) {
        // TODO: Integrate with virtual camera rendering
        print("🎭 Virtual camera connected to preview: \(camera.name)")
    }
    
    private func updateProgramFromVirtual(_ camera: VirtualCamera) {
        // TODO: Integrate with virtual camera rendering
        print("🎭 Virtual camera connected to program: \(camera.name)")
    }
    
    private func clearPreview() {
        previewSource = .none
        previewPlayer = nil
        previewImage = nil
        isPreviewPlaying = false
        previewCurrentTime = 0
        previewDuration = 0
    }
    
    private func clearProgram() {
        programSource = .none
        programPlayer = nil
        programImage = nil
        isProgramPlaying = false
        programCurrentTime = 0
        programDuration = 0
    }
    
    private func removeTimeObservers() {
        if let observer = previewTimeObserver {
            previewPlayer?.removeTimeObserver(observer)
            previewTimeObserver = nil
        }
        if let observer = programTimeObserver {
            programPlayer?.removeTimeObserver(observer)
            programTimeObserver = nil
        }
    }
    
    private func processImageWithEffects(_ image: CGImage?, for output: OutputType) -> CGImage? {
        guard let image = image else { return nil }
        
        // Convert CGImage to MTLTexture
        guard let texture = createMTLTexture(from: image) else { return image }
        
        // Apply effects based on output type
        let processedTexture: MTLTexture?
        switch output {
        case .preview:
            processedTexture = effectManager.applyPreviewEffects(to: texture)
        case .program:
            processedTexture = effectManager.applyProgramEffects(to: texture)
        }
        
        // Convert back to CGImage
        return createCGImage(from: processedTexture ?? texture)
    }
    
    private func createMTLTexture(from cgImage: CGImage) -> MTLTexture? {
        let textureLoader = MTKTextureLoader(device: effectManager.metalDevice)
        
        do {
            let texture = try textureLoader.newTexture(cgImage: cgImage, options: [
                MTKTextureLoader.Option.textureUsage: MTLTextureUsage.shaderRead.rawValue,
                MTKTextureLoader.Option.textureStorageMode: MTLStorageMode.shared.rawValue
            ])
            return texture
        } catch {
            print("Error creating MTLTexture: \(error)")
            return nil
        }
    }
    
    private func createCGImage(from texture: MTLTexture) -> CGImage? {
        // Create a CIImage from the Metal texture with proper coordinate handling
        let ciImage = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        
        guard let image = ciImage else { return nil }
        
        // Apply a transform to correct the coordinate system (flip vertically)
        let flippedImage = image.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -image.extent.height))
        
        // Create a CIContext and render to CGImage
        let context = CIContext(mtlDevice: effectManager.metalDevice, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        
        return context.createCGImage(flippedImage, from: flippedImage.extent)
    }
    
    enum OutputType {
        case preview, program
    }
    
    // MARK: - Effect Integration
    
    func addEffectToPreview(_ effectType: String) {
        effectManager.addEffectToPreview(effectType)
        print("✨ Added \(effectType) effect to Preview output")
    }
    
    func addEffectToProgram(_ effectType: String) {
        effectManager.addEffectToProgram(effectType)
        print("✨ Added \(effectType) effect to Program output")
    }
    
    func addEffectToPreview(_ effect: any VideoEffect) {
        effectManager.addEffectToPreview(effect)
        print("✨ Added \(effect.name) effect to Preview output")
    }
    
    func addEffectToProgram(_ effect: any VideoEffect) {
        effectManager.addEffectToProgram(effect)
        print("✨ Added \(effect.name) effect to Program output")
    }
    
    func getPreviewEffectChain() -> EffectChain? {
        return effectManager.getPreviewEffectChain()
    }
    
    func getProgramEffectChain() -> EffectChain? {
        return effectManager.getProgramEffectChain()
    }
    
    func clearPreviewEffects() {
        effectManager.clearPreviewEffects()
    }
    
    func clearProgramEffects() {
        effectManager.clearProgramEffects()
    }
}

// MARK: - Convenience Extensions

extension MediaFile {
    /// Create a ContentSource from this media file
    func asContentSource() -> ContentSource {
        return .media(self, player: nil)
    }
}

extension CameraFeed {
    /// Create a ContentSource from this camera feed
    func asContentSource() -> ContentSource {
        return .camera(self)
    }
}

extension VirtualCamera {
    /// Create a ContentSource from this virtual camera
    func asContentSource() -> ContentSource {
        return .virtual(self)
    }
}