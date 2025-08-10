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
    
    var preferVTDecode: Bool = true
    private var previewVTPlayback: VideoPlaybackVT?
    private var programVTPlayback: VideoPlaybackVT?
    
    private var previewAVPlayback: AVPlayerMetalPlayback?
    private var programAVPlayback: AVPlayerMetalPlayback?
    
    @Published var previewVideoTexture: MTLTexture?
    @Published var programVideoTexture: MTLTexture?
    private var previewAudioPlayer: AVPlayer?
    private var programAudioPlayer: AVPlayer?
    private let gpuProcessQueue = DispatchQueue(label: "vistaview.vt.gpu.process", qos: .userInitiated)

    @Published var previewVTReady: Bool = false
    @Published var programVTReady: Bool = false
    private var previewPrimedForPoster = false
    private var programPrimedForPoster = false

    @Published var previewVideoFrame: CGImage?
    @Published var programVideoFrame: CGImage?

    // Playback tuning & diagnostics
    @Published var hdrToneMapEnabled: Bool = false
    @Published var targetFPS: Double = 60
    @Published var previewFPS: Double = 0
    @Published var programFPS: Double = 0

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

        self.previewEffectRunner = EffectRunner(device: effectManager.metalDevice, chain: effectManager.getPreviewEffectChain())
        self.programEffectRunner = EffectRunner(device: effectManager.metalDevice, chain: effectManager.getProgramEffectChain())
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
        
        stopProgram()
        let previewContent = previewSource
        print("✂️ TAKE DEBUG: Moving \(previewContent) to program")
        loadToProgram(previewContent)
        effectManager.copyPreviewEffectsToProgram(overwrite: true)
        print("✨ TAKE: Copied Preview effects to Program")
        crossfaderValue = 0.0
        objectWillChange.send()
        print("✅ Take complete: Program now showing \(programSourceDisplayName)")
        print("✅ TAKE DEBUG: Final program source: \(programSource)")
        
        playProgram()
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
        if preferVTDecode, let vt = previewVTPlayback {
            print("▶️ playPreview (VT)")
            previewPrimedForPoster = false
            previewAudioPlayer?.play()
            vt.start()
            isPreviewPlaying = true
            return
        }
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
        if preferVTDecode, previewVTPlayback != nil {
            print("⏸️ pausePreview (VT)")
            previewAudioPlayer?.pause()
            previewVTPlayback?.stop()
            isPreviewPlaying = false
            return
        }
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
        if preferVTDecode, previewVTPlayback != nil {
            previewAudioPlayer?.pause()
            previewAudioPlayer?.seek(to: .zero)
            previewVTPlayback?.stop()
            isPreviewPlaying = false
            previewCurrentTime = 0.0
            previewVideoTexture = nil
            return
        }
        if case .media(let file, let player) = previewSource, let actualPlayer = previewPlayer {
            actualPlayer.pause()
            actualPlayer.seek(to: CMTime.zero)
            isPreviewPlaying = false
            previewCurrentTime = 0.0
            print("⏹️ Preview stopped: \(file.name)")
        }
    }
    
    func playProgram() {
        if preferVTDecode, let vt = programVTPlayback {
            print("▶️ playProgram (VT)")
            programPrimedForPoster = false
            programAudioPlayer?.play()
            vt.start()
            isProgramPlaying = true
            return
        }
        guard case .media(let file, let player) = programSource else { return }
        guard let actualPlayer = programPlayer else { return }
        actualPlayer.play()
        isProgramPlaying = true
        print("▶️ Program playing: \(file.name)")
    }
    
    func pauseProgram() {
        if preferVTDecode, programVTPlayback != nil {
            print("⏸️ pauseProgram (VT)")
            programAudioPlayer?.pause()
            programVTPlayback?.stop()
            isProgramPlaying = false
            return
        }
        guard case .media(let file, let player) = programSource else { return }
        guard let actualPlayer = programPlayer else { return }
        actualPlayer.pause()
        isProgramPlaying = false
        print("⏸️ Program paused: \(file.name)")
    }
    
    func stopProgram() {
        if preferVTDecode, programVTPlayback != nil {
            programAudioPlayer?.pause()
            programAudioPlayer?.seek(to: .zero)
            programVTPlayback?.stop()
            isProgramPlaying = false
            programCurrentTime = 0.0
            programVideoTexture = nil
            return
        }
        if case .media(let file, let player) = programSource, let actualPlayer = programPlayer {
            actualPlayer.pause()
            actualPlayer.seek(to: CMTime.zero)
            isProgramPlaying = false
            programCurrentTime = 0.0
            print("⏹️ Program stopped: \(file.name)")
        }
    }
    
    func seekPreview(to time: TimeInterval) {
        if preferVTDecode, let vt = previewVTPlayback {
            print("⏭️ seekPreview (VT): \(time)")
            let cm = CMTime(seconds: time, preferredTimescale: 600)
            previewAudioPlayer?.seek(to: cm)
            vt.seek(to: time)
            return
        }
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
        if preferVTDecode, let vt = programVTPlayback {
            print("⏭️ seekProgram (VT): \(time)")
            let cm = CMTime(seconds: time, preferredTimescale: 600)
            programAudioPlayer?.seek(to: cm)
            vt.seek(to: time)
            return
        }
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
        // Stop previous preview pipeline
        previewVTPlayback?.stop()
        previewVTPlayback = nil
        previewAVPlayback?.stop()
        previewAVPlayback = nil
        previewVideoTexture = nil
        
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
        
        // Start accessing security-scoped resource
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for: \(file.name)")
            return
        }
        
        // Duration via AVAsset (async load)
        let asset = AVURLAsset(url: file.url)
        Task {
            do {
                let duration = try await asset.load(.duration)
                if duration.isValid {
                    await MainActor.run {
                        self.previewDuration = CMTimeGetSeconds(duration)
                        print("📼 PREVIEW duration loaded (asset): \(self.previewDuration) s")
                    }
                }
            } catch {
                print("Failed to load PREVIEW duration: \(error)")
            }
        }

        let hasVideoTrack = !asset.tracks(withMediaType: .video).isEmpty
        if file.fileType == .audio || !hasVideoTrack {
            print("🎧 Preview: Configuring audio-only playback for \(file.name) (hasVideoTrack=\(hasVideoTrack))")
            let player = createAudioOnlyPlayer(for: asset) ?? AVPlayer(playerItem: AVPlayerItem(asset: asset))
            previewAudioPlayer = player
            previewPlayer = player
            previewSource = .media(file, player: player)
            
            let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
            previewTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
                self?.previewCurrentTime = CMTimeGetSeconds(t)
            }
            isPreviewPlaying = false
            objectWillChange.send()
            print("✅ Preview audio-only configured")
            return
        }
        
        if preferVTDecode && file.fileType == .video {
            // VT path currently disabled by default. Fallthrough to AVPlayer path.
        }

        // AVPlayer + ItemOutput path
        let playerItem = AVPlayerItem(url: file.url)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        output.suppressesPlayerRendering = true
        playerItem.add(output)

        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false

        if let playback = AVPlayerMetalPlayback(player: player, itemOutput: output, device: effectManager.metalDevice) {
            previewAVPlayback = playback
            playback.setEffectRunner(previewEffectRunner)
            playback.toneMapEnabled = hdrToneMapEnabled
            playback.targetFPS = targetFPS
            playback.onFPSUpdate = { [weak self] fps in
                Task { @MainActor in
                    self?.previewFPS = fps
                }
            }
            playback.onWatchdog = { [weak self] in
                print("⚠️ Preview watchdog: FPS below target, capturing next frame")
                self?.captureNextPreviewFrame()
            }
            playback.start()
        }

        // Autoplay & time observer
        var statusObserver: NSKeyValueObservation?
        statusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                if item.status != .unknown { statusObserver?.invalidate() }
                if item.status == .readyToPlay {
                    self?.isPreviewPlaying = true
                    self?.previewPlayer?.play()
                }
            }
        }

        previewSource = .media(file, player: player)
        previewPlayer = player

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        previewTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            self?.previewCurrentTime = CMTimeGetSeconds(t)
        }

        objectWillChange.send()
        print("📼 PREVIEW AVPlayer + ItemOutput + Metal playback configured")
    }

    private func loadMediaToProgram(_ file: MediaFile) {
        // Stop previous program pipeline
        programVTPlayback?.stop()
        programVTPlayback = nil
        programAVPlayback?.stop()
        programAVPlayback = nil
        programVideoTexture = nil
        
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
        
        // Start accessing security-scoped resource
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for PROGRAM: \(file.name)")
            return
        }
        
        // Duration via AVAsset
        let asset = AVURLAsset(url: file.url)
        Task {
            do {
                let duration = try await asset.load(.duration)
                if duration.isValid {
                    await MainActor.run {
                        self.programDuration = CMTimeGetSeconds(duration)
                        print("📼 PROGRAM duration loaded (asset): \(self.programDuration) s")
                    }
                }
            } catch {
                print("Failed to load PROGRAM duration: \(error)")
            }
        }

        let hasVideoTrack = !asset.tracks(withMediaType: .video).isEmpty
        if file.fileType == .audio || !hasVideoTrack {
            print("🎧 Program: Configuring audio-only playback for \(file.name) (hasVideoTrack=\(hasVideoTrack))")
            let player = createAudioOnlyPlayer(for: asset) ?? AVPlayer(playerItem: AVPlayerItem(asset: asset))
            programAudioPlayer = player
            programPlayer = player
            programSource = .media(file, player: player)
            
            let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
            programTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
                self?.programCurrentTime = CMTimeGetSeconds(t)
            }
            isProgramPlaying = false
            print("✅ Program audio-only configured")
            return
        }
        
        if preferVTDecode && file.fileType == .video {
            // VT path currently disabled by default. Fallthrough to AVPlayer path.
        }
        
        // AVPlayer + ItemOutput path
        let playerItem = AVPlayerItem(url: file.url)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        output.suppressesPlayerRendering = true
        playerItem.add(output)

        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false

        if let playback = AVPlayerMetalPlayback(player: player, itemOutput: output, device: effectManager.metalDevice) {
            programAVPlayback = playback
            playback.setEffectRunner(programEffectRunner)
            playback.toneMapEnabled = hdrToneMapEnabled
            playback.targetFPS = targetFPS
            playback.onFPSUpdate = { [weak self] fps in
                Task { @MainActor in
                    self?.programFPS = fps
                }
            }
            playback.onWatchdog = { [weak self] in
                print("⚠️ Program watchdog: FPS below target, capturing next frame")
                self?.captureNextProgramFrame()
            }
            playback.start()
        }

        var statusObserver: NSKeyValueObservation?
        statusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                if item.status != .unknown { statusObserver?.invalidate() }
                if item.status == .readyToPlay {
                    self?.isProgramPlaying = true
                    self?.programPlayer?.play()
                }
            }
        }

        programSource = .media(file, player: player)
        programPlayer = player

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        programTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            self?.programCurrentTime = CMTimeGetSeconds(t)
        }

        print("📼 PROGRAM AVPlayer + ItemOutput + Metal playback configured")
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
        previewVTPlayback?.stop()
        previewVTPlayback = nil
        previewVideoTexture = nil
        previewAudioPlayer = nil
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
        previewVTReady = false
        previewPrimedForPoster = false
    }
    
    private func clearProgram() {
        programVTPlayback?.stop()
        programVTPlayback = nil
        programVideoTexture = nil
        programAudioPlayer = nil
        programSource = .none
        programPlayer = nil
        programImage = nil
        isProgramPlaying = false
        programCurrentTime = 0
        programDuration = 0
        programVTReady = false
        programPrimedForPoster = false
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
    
    private var previewEffectRunner: EffectRunner?
    private var programEffectRunner: EffectRunner?

    func addEffectToPreview(_ effectType: String) {
        print("✨ PreviewProgramManager: Adding \(effectType) effect to Preview output")
        effectManager.addEffectToPreview(effectType)
        
        // Force UI update to ensure effects are applied immediately
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.previewEffectRunner?.setChain(self.getPreviewEffectChain())
        print("✨ PreviewProgramManager: Preview now has \(getPreviewEffectChain()?.effects.count ?? 0) effects")
    }
    
    func addEffectToProgram(_ effectType: String) {
        print("✨ PreviewProgramManager: Adding \(effectType) effect to Program output")
        effectManager.addEffectToProgram(effectType);
        
        // Force UI update to ensure effects are applied immediately
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.programEffectRunner?.setChain(self.getProgramEffectChain())
        print("✨ PreviewProgramManager: Program now has \(getProgramEffectChain()?.effects.count ?? 0) effects")
    }
    
    func addEffectToPreview(_ effect: any VideoEffect) {
        print("✨ PreviewProgramManager: Adding \(effect.name) effect instance to Preview output")
        effectManager.addEffectToPreview(effect);
        
        // Force UI update to ensure effects are applied immediately
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.previewEffectRunner?.setChain(self.getPreviewEffectChain())
        print("✨ PreviewProgramManager: Preview now has \(getPreviewEffectChain()?.effects.count ?? 0) effects")
    }
    
    func addEffectToProgram(_ effect: any VideoEffect) {
        print("✨ PreviewProgramManager: Adding \(effect.name) effect instance to Program output")
        effectManager.addEffectToProgram(effect);
        
        // Force UI update to ensure effects are applied immediately
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.programEffectRunner?.setChain(self.getProgramEffectChain())
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
        self.previewEffectRunner?.setChain(self.getPreviewEffectChain())
    }
    
    func clearProgramEffects() {
        effectManager.clearProgramEffects()
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.programEffectRunner?.setChain(self.getProgramEffectChain())
    }

    private func createAudioOnlyPlayer(for asset: AVAsset) -> AVPlayer? {
        let composition = AVMutableComposition()
        let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        do {
            let audioTracks = asset.tracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else { return nil }
            for track in audioTracks {
                let compTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try compTrack?.insertTimeRange(timeRange, of: track, at: .zero)
            }
            let item = AVPlayerItem(asset: composition)
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            player.allowsExternalPlayback = false
            return player
        } catch {
            print("Audio-only composition error:", error)
            return nil
        }
    }

    var previewCurrentTexture: MTLTexture? {
        previewAVPlayback?.latestTexture ?? previewVideoTexture
    }

    var programCurrentTexture: MTLTexture? {
        programAVPlayback?.latestTexture ?? programVideoTexture
    }

    func captureNextPreviewFrame() {
        previewAVPlayback?.captureNextFrame()
    }
    
    func captureNextProgramFrame() {
        programAVPlayback?.captureNextFrame()
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