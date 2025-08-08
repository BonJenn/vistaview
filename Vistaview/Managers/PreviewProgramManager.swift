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
        
        print("🎬 PreviewProgramManager.loadToPreview() called with: \(displayName)")
        print("🎬 Source type: \(source)")
        
        // Stop current preview if playing
        stopPreview()
        
        switch source {
        case .camera(let feed):
            print("🎬 PreviewProgramManager: Loading camera feed to preview: \(feed.device.displayName)")
            previewSource = source
            updatePreviewFromCamera(feed)
            print("🎬 PreviewProgramManager: Preview source set to camera")
            
        case .media(let file, let player):
            print("🎬 PreviewProgramManager: Loading media file to preview: \(file.name)")
            print("🎬 PreviewProgramManager: Player is \(player == nil ? "nil" : "not nil")")
            print("🎬 PreviewProgramManager: File type is: \(file.fileType)")
            
            // Handle different media types appropriately
            switch file.fileType {
            case .image:
                print("🖼️ PreviewProgramManager: Loading image to preview")
                loadImageToPreview(file)
            case .video, .audio:
                print("🎬 PreviewProgramManager: Loading video/audio to preview")
                loadMediaToPreview(file)
            }
            
        case .virtual(let camera):
            print("🎬 PreviewProgramManager: Loading virtual camera to preview: \(camera.name)")
            previewSource = source
            updatePreviewFromVirtual(camera)
            
        case .none:
            print("🎬 PreviewProgramManager: Clearing preview")
            clearPreview()
        }
        
        print("🎬 PreviewProgramManager: loadToPreview completed. Current preview source: \(previewSourceDisplayName)")
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
            print("📺 PreviewProgramManager: Loading media file to program: \(file.name)")
            print("📺 PreviewProgramManager: File type is: \(file.fileType)")
            
            // Handle different media types appropriately
            switch file.fileType {
            case .image:
                print("🖼️ PreviewProgramManager: Loading image to program")
                loadImageToProgram(file)
            case .video, .audio:
                print("📺 PreviewProgramManager: Loading video/audio to program")
                loadMediaToProgram(file)
            }
            
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
        print("✂️ TAKE DEBUG: Current preview source: \(previewSource)")
        print("✂️ TAKE DEBUG: Current program source: \(programSource)")
        
        // Stop current program
        stopProgram()
        
        // Move preview content to program
        let previewContent = previewSource
        print("✂️ TAKE DEBUG: Moving \(previewContent) to program")
        
        loadToProgram(previewContent)
        
        effectManager.copyPreviewEffectsToProgram(overwrite: true)
        print("✨ TAKE: Copied Preview effects to Program")
        
        // Reset crossfader to full program
        crossfaderValue = 0.0
        
        // Force UI updates
        objectWillChange.send()
        
        print("✅ Take complete: Program now showing \(programSourceDisplayName)")
        print("✅ TAKE DEBUG: Final program source: \(programSource)")
    }
    
    /// Smooth transition from program to preview over time
    func transition(duration: TimeInterval = 1.0) {
        guard previewSource != .none else { return }
        
        print("🔄 Starting transition over \(duration)s")
        isTransitioning = true
        transitionProgress = 0.0
        
        // EFFICIENT: Use single timer instead of 30 dispatch operations
        let startTime = CACurrentMediaTime()
        let transitionTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(elapsed / duration, 1.0)
            
            self.transitionProgress = progress
            self.crossfaderValue = progress
            
            if progress >= 1.0 {
                // Transition complete
                timer.invalidate()
                self.take()
                self.isTransitioning = false
                self.transitionProgress = 0.0
            }
        }
    }
    
    // MARK: - Media Playback Controls
    
    func playPreview() {
        guard case .media(let file, let player) = previewSource else { 
            print("❌ playPreview: No media source in preview")
            return 
        }
        guard let actualPlayer = previewPlayer else { 
            print("❌ playPreview: No preview player found")
            return 
        }
        
        if let currentItem = actualPlayer.currentItem {
            print("🎬 BEFORE PLAY - Preview player time: \(CMTimeGetSeconds(currentItem.currentTime()))")
            print("🎬 BEFORE PLAY - Preview player rate: \(actualPlayer.rate)")
            print("🎬 BEFORE PLAY - Preview player status: \(currentItem.status.description)")
            print("🎬 BEFORE PLAY - Preview player duration: \(CMTimeGetSeconds(currentItem.duration))")
        }
        
        print("🎬 About to play preview player: \(actualPlayer)")
        actualPlayer.play()
        isPreviewPlaying = true
        print("▶️ Preview playing: \(file.name)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let currentItem = actualPlayer.currentItem {
                print("🎬 AFTER PLAY - Preview player time: \(CMTimeGetSeconds(currentItem.currentTime()))")
                print("🎬 AFTER PLAY - Preview player rate: \(actualPlayer.rate)")
            }
        }
    }
    
    func pausePreview() {
        guard case .media(let file, let player) = previewSource else { 
            print("❌ pausePreview: No media source in preview")
            return 
        }
        guard let actualPlayer = previewPlayer else { 
            print("❌ pausePreview: No preview player found")
            return 
        }
        print("🎬 About to pause preview player: \(actualPlayer)")
        actualPlayer.pause()
        isPreviewPlaying = false
        print("⏸️ Preview paused: \(file.name)")
    }
    
    func stopPreview() {
        if case .media(let file, let player) = previewSource, let actualPlayer = previewPlayer {
            actualPlayer.pause()
            actualPlayer.seek(to: CMTime.zero)
            isPreviewPlaying = false
            previewCurrentTime = 0.0
            print("⏹️ Preview stopped: \(file.name)")
        }
    }
    
    func playProgram() {
        guard case .media(let file, let player) = programSource else { return }
        guard let actualPlayer = programPlayer else { return }
        actualPlayer.play()
        isProgramPlaying = true
        print("▶️ Program playing: \(file.name)")
    }
    
    func pauseProgram() {
        guard case .media(let file, let player) = programSource else { return }
        guard let actualPlayer = programPlayer else { return }
        actualPlayer.pause()
        isProgramPlaying = false
        print("⏸️ Program paused: \(file.name)")
    }
    
    func stopProgram() {
        if case .media(let file, let player) = programSource, let actualPlayer = programPlayer {
            actualPlayer.pause()
            actualPlayer.seek(to: CMTime.zero)
            isProgramPlaying = false
            programCurrentTime = 0.0
            print("⏹️ Program stopped: \(file.name)")
        }
    }
    
    func seekPreview(to time: TimeInterval) {
        guard case .media(let file, let player) = previewSource else { 
            print("❌ seekPreview: No media source in preview")
            return 
        }
        guard let actualPlayer = previewPlayer else { 
            print("❌ seekPreview: No preview player found")
            return 
        }
        print("🎬 About to seek preview player: \(actualPlayer) to \(time)")
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        actualPlayer.seek(to: cmTime) { [weak self] completed in
            if completed {
                print("🎯 Preview seeked to: \(time) seconds")
                Task { @MainActor in
                    self?.previewCurrentTime = time
                }
            } else {
                print("❌ Preview seek failed to: \(time) seconds")
            }
        }
    }
    
    func seekProgram(to time: TimeInterval) {
        guard case .media(let file, let player) = programSource else { return }
        guard let actualPlayer = programPlayer else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        actualPlayer.seek(to: cmTime) { [weak self] completed in
            if completed {
                print("🎯 Program seeked to: \(time) seconds")
                Task { @MainActor in
                    self?.programCurrentTime = time
                }
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func loadMediaToPreview(_ file: MediaFile) {
        print("🎬 PreviewProgramManager: Starting loadMediaToPreview for: \(file.name)")
        
        // Remove existing observer if any
        if let observer = previewTimeObserver {
            previewPlayer?.removeTimeObserver(observer)
            previewTimeObserver = nil
        }
        
        // Stop accessing previous security-scoped resource if needed
        if case .media(let previousFile, _) = previewSource {
            previousFile.url.stopAccessingSecurityScopedResource()
        }
        
        // Clear previous player
        previewPlayer = nil
        
        // Start accessing the security-scoped resource
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for: \(file.name)")
            return
        }
        
        print("✅ Security-scoped resource access granted for: \(file.name)")
        
        // FIXED: Use EXACTLY the same method as program (create from URL, not asset)
        let playerItem = AVPlayerItem(url: file.url)
        
        // Create a new AVPlayer instance specifically for preview
        let player = AVPlayer(playerItem: playerItem)
        
        // Important: Configure player for optimal performance
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
        
        // Set up status observer BEFORE setting the source (exactly like program)
        var statusObserver: NSKeyValueObservation?
        statusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, change in
            Task { @MainActor in
                print("🎬 PREVIEW Player item status changed to: \(item.status.rawValue) (\(item.status.description))")
                
                switch item.status {
                case .readyToPlay:
                    print("✅ PREVIEW Player item is ready to play")
                    
                case .failed:
                    print("❌ PREVIEW Player item failed: \(item.error?.localizedDescription ?? "Unknown error")")
                    
                case .unknown:
                    print("🤔 PREVIEW Player item status is still unknown")
                    
                @unknown default:
                    print("🆕 PREVIEW Player item has unknown status: \(item.status.rawValue)")
                }
                
                // Clean up observer when done
                if item.status != .unknown {
                    statusObserver?.invalidate()
                    statusObserver = nil
                }
            }
        }
        
        // Set source and player BEFORE setting up observer
        let newSource = ContentSource.media(file, player: player)
        previewSource = newSource
        previewPlayer = player
        
        print("🎬 PreviewProgramManager: AVPlayer created for PREVIEW and source updated")
        print("🔍 PREVIEW DEBUG: Player stored in previewPlayer: \(player)")
        print("🔍 PREVIEW DEBUG: Player in ContentSource: \(String(describing: (previewSource as? ContentSource)))")
        
        // CRITICAL: Verify the player is actually stored correctly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🔍 PREVIEW VERIFICATION: previewPlayer after delay: \(String(describing: self.previewPlayer))")
            print("🔍 PREVIEW VERIFICATION: Are they the same object? \(self.previewPlayer === player)")
        }
        
        // Get duration using modern API (exactly like program)  
        Task {
            do {
                let duration = try await playerItem.asset.load(.duration)
                if duration.isValid {
                    await MainActor.run {
                        self.previewDuration = CMTimeGetSeconds(duration)
                        print("📼 PREVIEW Media duration loaded: \(self.previewDuration) seconds")
                    }
                }
            } catch {
                print("Failed to load PREVIEW duration: \(error)")
            }
        }
        
        // Set up time observer for new player
        let previewInterval = CMTime(seconds: 0.1, preferredTimescale: 600)
        previewTimeObserver = player.addPeriodicTimeObserver(forInterval: previewInterval, queue: DispatchQueue.main) { [weak self] time in
            Task { @MainActor in
                self?.previewCurrentTime = CMTimeGetSeconds(time)
            }
        }
        
        print("📼 PREVIEW Media setup complete: \(file.name)")
        
        // Force UI update
        objectWillChange.send()
    }
    
    private func loadMediaToProgram(_ file: MediaFile) {
        print("🎬 PreviewProgramManager: Starting loadMediaToProgram for: \(file.name)")
        
        // Remove existing observer if any
        if let observer = programTimeObserver {
            programPlayer?.removeTimeObserver(observer)
            programTimeObserver = nil
        }
        
        // Stop accessing previous security-scoped resource if needed
        if case .media(let previousFile, _) = programSource {
            previousFile.url.stopAccessingSecurityScopedResource()
        }
        
        // Clear previous player
        programPlayer = nil
        
        // Start accessing the security-scoped resource
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for PROGRAM: \(file.name)")
            return
        }
        
        // Create AVPlayerItem first to monitor its status
        let playerItem = AVPlayerItem(url: file.url)
        
        // Create a new AVPlayer instance specifically for program
        let player = AVPlayer(playerItem: playerItem)
        
        // Important: Configure player for optimal performance  
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
        
        // Set up status observer BEFORE setting the source
        var statusObserver: NSKeyValueObservation?
        statusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, change in
            Task { @MainActor in
                print("🎬 PROGRAM Player item status changed to: \(item.status.rawValue) (\(item.status.description))")
                
                switch item.status {
                case .readyToPlay:
                    print("✅ PROGRAM Player item is ready to play")
                    
                case .failed:
                    print("❌ PROGRAM Player item failed: \(item.error?.localizedDescription ?? "Unknown error")")
                    
                case .unknown:
                    print("🤔 PROGRAM Player item status is still unknown")
                    
                @unknown default:
                    print("🆕 PROGRAM Player item has unknown status: \(item.status.rawValue)")
                }
                
                // Clean up observer when done
                if item.status != .unknown {
                    statusObserver?.invalidate()
                    statusObserver = nil
                }
            }
        }
        
        let newSource = ContentSource.media(file, player: player)
        programSource = newSource
        programPlayer = player
        
        print("🎬 PreviewProgramManager: AVPlayer created for PROGRAM and source updated")
        
        // Get duration using modern API
        Task {
            do {
                let duration = try await playerItem.asset.load(.duration)
                if duration.isValid {
                    await MainActor.run {
                        self.programDuration = CMTimeGetSeconds(duration)
                        print("📼 PROGRAM Media duration loaded: \(self.programDuration) seconds")
                    }
                }
            } catch {
                print("Failed to load PROGRAM duration: \(error)")
            }
        }
        
        // Set up time observer for new player
        let programInterval = CMTime(seconds: 0.1, preferredTimescale: 600)
        programTimeObserver = player.addPeriodicTimeObserver(forInterval: programInterval, queue: DispatchQueue.main) { [weak self] time in
            Task { @MainActor in
                self?.programCurrentTime = CMTimeGetSeconds(time)
            }
        }
        
        print("📼 PROGRAM Media setup complete: \(file.name)")
    }
    
    private func loadImageToPreview(_ file: MediaFile) {
        print("🖼️ PreviewProgramManager: Starting loadImageToPreview for: \(file.name)")
        
        // Clear any existing media player for preview
        if let observer = previewTimeObserver {
            previewPlayer?.removeTimeObserver(observer)
            previewTimeObserver = nil
        }
        previewPlayer = nil
        
        // Stop accessing previous security-scoped resource if needed
        if case .media(let previousFile, _) = previewSource {
            previousFile.url.stopAccessingSecurityScopedResource()
        }
        
        // Start accessing the security-scoped resource
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for image: \(file.name)")
            return
        }
        
        print("✅ Security-scoped resource access granted for image: \(file.name)")
        
        // Load the image directly
        Task {
            do {
                let imageData = try Data(contentsOf: file.url)
                if let cgImage = NSImage(data: imageData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    await MainActor.run {
                        // Store the image directly in previewImage
                        self.previewImage = cgImage
                        
                        // Set up the source without a player
                        let newSource = ContentSource.media(file, player: nil)
                        self.previewSource = newSource
                        
                        // Set static values for image
                        self.previewDuration = 0 // Images don't have duration
                        self.previewCurrentTime = 0
                        self.isPreviewPlaying = false
                        
                        print("✅ Image loaded to preview: \(file.name)")
                        
                        // Force UI update
                        self.objectWillChange.send()
                    }
                } else {
                    print("❌ Failed to create CGImage from: \(file.name)")
                }
            } catch {
                print("❌ Failed to load image data: \(error)")
            }
        }
    }
    
    private func loadImageToProgram(_ file: MediaFile) {
        print("🖼️ PreviewProgramManager: Starting loadImageToProgram for: \(file.name)")
        
        // Clear any existing media player for program
        if let observer = programTimeObserver {
            programPlayer?.removeTimeObserver(observer)
            programTimeObserver = nil
        }
        programPlayer = nil
        
        // Stop accessing previous security-scoped resource if needed
        if case .media(let previousFile, _) = programSource {
            previousFile.url.stopAccessingSecurityScopedResource()
        }
        
        // Start accessing the security-scoped resource
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for image: \(file.name)")
            return
        }
        
        print("✅ Security-scoped resource access granted for image: \(file.name)")
        
        // Load the image directly
        Task {
            do {
                let imageData = try Data(contentsOf: file.url)
                if let cgImage = NSImage(data: imageData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    await MainActor.run {
                        // Store the image directly in programImage
                        self.programImage = cgImage
                        
                        // Set up the source without a player
                        let newSource = ContentSource.media(file, player: nil)
                        self.programSource = newSource
                        
                        // Set static values for image
                        self.programDuration = 0 // Images don't have duration
                        self.programCurrentTime = 0
                        self.isProgramPlaying = false
                        
                        print("✅ Image loaded to program: \(file.name)")
                        
                        // Force UI update
                        self.objectWillChange.send()
                    }
                } else {
                    print("❌ Failed to create CGImage from: \(file.name)")
                }
            } catch {
                print("❌ Failed to load image data: \(error)")
            }
        }
    }
    
    private func updatePreviewFromCamera(_ feed: CameraFeed) {
        print("📹 CAMERA DEBUG: updatePreviewFromCamera called for: \(feed.device.displayName)")
        print("📹 CAMERA DEBUG: Feed has image: \(feed.previewImage != nil)")
        print("📹 CAMERA DEBUG: Feed status: \(feed.connectionStatus.displayText)")
        print("📹 CAMERA DEBUG: Feed frame count: \(feed.frameCount)")
        
        // FIXED: The monitor views will display the camera feed directly
        // We don't need to process images here, just ensure the source is set
        // The UI will react to the camera feed's published properties automatically
        
        print("📹 Camera feed connected to preview: \(feed.device.displayName)")
        
        // Force immediate UI update to ensure preview monitor updates
        objectWillChange.send()
    }
    
    private func updateProgramFromCamera(_ feed: CameraFeed) {
        print("📺 CAMERA DEBUG: updateProgramFromCamera called for: \(feed.device.displayName)")
        print("📺 CAMERA DEBUG: Feed has image: \(feed.previewImage != nil)")
        print("📺 CAMERA DEBUG: Feed status: \(feed.connectionStatus.displayText)")
        print("📺 CAMERA DEBUG: Feed frame count: \(feed.frameCount)")
        
        // FIXED: The monitor views will display the camera feed directly
        // We don't need to process images here, just ensure the source is set
        // The UI will react to the camera feed's published properties automatically
        
        print("📺 Camera feed connected to program: \(feed.device.displayName)")
        
        // Force immediate UI update to ensure program monitor updates
        objectWillChange.send()
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
        // Stop accessing security-scoped resource if needed
        if case .media(let file, _) = previewSource {
            file.url.stopAccessingSecurityScopedResource()
        }
        
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
    
    // MARK: - Public Methods for Effects Processing
    
    /// Process image with effects - made public for view access
    func processImageWithEffects(_ image: CGImage?, for output: OutputType) -> CGImage? {
        guard let image = image else { return nil }
        
        // PERFORMANCE: Skip processing if no effects are applied
        let effectChain = output == .preview ? getPreviewEffectChain() : getProgramEffectChain()
        guard let chain = effectChain, !chain.effects.isEmpty else {
            return image // Return original image if no effects
        }
        
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
                MTKTextureLoader.Option.textureStorageMode: MTLStorageMode.shared.rawValue,
                MTKTextureLoader.Option.generateMipmaps: NSNumber(value: false) // Skip mipmaps for performance
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
        
        // PERFORMANCE: Use existing ciContext for better performance
        return ciContext.createCGImage(flippedImage, from: flippedImage.extent)
    }
    
    // MARK: - Public Types
    
    /// Output type for effects processing - made public
    enum OutputType {
        case preview, program
    }
    
    // MARK: - Effect Integration
    
    func addEffectToPreview(_ effectType: String) {
        print("✨ PreviewProgramManager: Adding \(effectType) effect to Preview output")
        effectManager.addEffectToPreview(effectType)
        
        // Force UI update to ensure effects are applied immediately
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        
        print("✨ PreviewProgramManager: Preview now has \(getPreviewEffectChain()?.effects.count ?? 0) effects")
    }
    
    func addEffectToProgram(_ effectType: String) {
        print("✨ PreviewProgramManager: Adding \(effectType) effect to Program output")
        effectManager.addEffectToProgram(effectType)
        
        // Force UI update to ensure effects are applied immediately
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        
        print("✨ PreviewProgramManager: Program now has \(getProgramEffectChain()?.effects.count ?? 0) effects")
    }
    
    func addEffectToPreview(_ effect: any VideoEffect) {
        print("✨ PreviewProgramManager: Adding \(effect.name) effect instance to Preview output")
        effectManager.addEffectToPreview(effect)
        
        // Force UI update to ensure effects are applied immediately
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        
        print("✨ PreviewProgramManager: Preview now has \(getPreviewEffectChain()?.effects.count ?? 0) effects")
    }
    
    func addEffectToProgram(_ effect: any VideoEffect) {
        print("✨ PreviewProgramManager: Adding \(effect.name) effect instance to Program output")
        effectManager.addEffectToProgram(effect)
        
        // Force UI update to ensure effects are applied immediately
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        
        print("✨ PreviewProgramManager: Program now has \(getProgramEffectChain()?.effects.count ?? 0) effects")
    }
    
    func getPreviewEffectChain() -> EffectChain? {
        return effectManager.getPreviewEffectChain()
    }
    
    func getProgramEffectChain() -> EffectChain? {
        return effectManager.getProgramEffectChain()
    }
    
    func clearPreviewEffects() {
        effectManager.clearPreviewEffects()
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
    }
    
    func clearProgramEffects() {
        effectManager.clearProgramEffects()
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
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