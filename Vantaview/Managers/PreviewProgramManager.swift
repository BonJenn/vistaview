//
//  PreviewProgramManager.swift
//  Vantaview
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
import AVKit

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

@MainActor
final class PreviewProgramManager: ObservableObject {
    @Published var previewSource: ContentSource = .none
    @Published var programSource: ContentSource = .none
    
    @Published var previewPlayer: AVPlayer?
    @Published var programPlayer: AVPlayer?
    
    @Published var programAudioTap: PlayerAudioTap?
    @Published var previewAudioTap: PlayerAudioTap?
    
    @Published var isPreviewPlaying = false
    @Published var isProgramPlaying = false
    @Published var previewCurrentTime: TimeInterval = 0
    @Published var programCurrentTime: TimeInterval = 0
    @Published var previewDuration: TimeInterval = 0
    @Published var programDuration: TimeInterval = 0
    
    @Published var previewLoopEnabled = false
    @Published var programLoopEnabled = false
    @Published var previewMuted = false
    @Published var programMuted = false
    @Published var previewRate: Float = 1.0
    @Published var programRate: Float = 1.0
    @Published var previewVolume: Float = 1.0
    @Published var programVolume: Float = 1.0
    
    @Published var previewImage: CGImage?
    @Published var programImage: CGImage?
    
    @Published var crossfaderValue: Double = 0.0
    @Published var isTransitioning = false
    @Published var transitionProgress: Double = 0.0
    
    private let cameraFeedManager: CameraFeedManager
    private let unifiedProductionManager: UnifiedProductionManager
    private let effectManager: EffectManager
    private let frameProcessor: FrameProcessor
    private let audioEngine: AudioEngine
    
    private var previewTimeObserver: Any?
    private var programTimeObserver: Any?
    
    private let ciContext = CIContext()
    
    var preferVTDecode: Bool = true
    private var previewVTPlayback: VideoPlaybackVT?
    private var programVTPlayback: VideoPlaybackVT?
    
    private var previewAVPlayback: AVPlayerMetalPlayback?
    private var programAVPlayback: AVPlayerMetalPlayback?
    
    private var previewProcessingTask: Task<Void, Never>?
    private var programProcessingTask: Task<Void, Never>?
    
    // Notification/KVO tracking for cleanup
    private var previewNotificationTokens: [NSObjectProtocol] = []
    private var programNotificationTokens: [NSObjectProtocol] = []
    private var previewKVO: [NSKeyValueObservation] = []
    private var programKVO: [NSKeyValueObservation] = []
    
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
    
    @Published var hdrToneMapEnabled: Bool = false
    @Published var targetFPS: Double = 60
    @Published var previewFPS: Double = 0
    @Published var programFPS: Double = 0
    
    @Published var previewAspect: CGFloat = 16.0/9.0
    @Published var programAspect: CGFloat = 16.0/9.0
    
    var previewSourceDisplayName: String {
        return getDisplayName(for: previewSource)
    }
    var programSourceDisplayName: String {
        return getDisplayName(for: programSource)
    }
    
    private var previewEffectRunner: EffectRunner?
    private var programEffectRunner: EffectRunner?
    
    init(cameraFeedManager: CameraFeedManager,
         unifiedProductionManager: UnifiedProductionManager,
         effectManager: EffectManager,
         frameProcessor: FrameProcessor,
         audioEngine: AudioEngine) {
        self.cameraFeedManager = cameraFeedManager
        self.unifiedProductionManager = unifiedProductionManager
        self.effectManager = effectManager
        self.frameProcessor = frameProcessor
        self.audioEngine = audioEngine
        
        self.previewEffectRunner = EffectRunner(device: effectManager.metalDevice, chain: effectManager.getPreviewEffectChain())
        self.programEffectRunner = EffectRunner(device: effectManager.metalDevice, chain: effectManager.getProgramEffectChain())
    }
    
    deinit {
        Task { @MainActor in
            self.removeTimeObservers()
            self.removePlayerNotifications(isPreview: true)
            self.removePlayerNotifications(isPreview: false)
            self.removeKVO(isPreview: true)
            self.removeKVO(isPreview: false)
            self.stopPreviewMediaPipeline()
            print("🧹 PreviewProgramManager deinit")
        }
    }
    
    func cleanup() {
        removeTimeObservers()
        removePlayerNotifications(isPreview: true)
        removePlayerNotifications(isPreview: false)
        removeKVO(isPreview: true)
        removeKVO(isPreview: false)
        stopPreviewMediaPipeline()
        previewPlayer = nil
        programPlayer = nil
    }
    
    func getDisplayName(for source: ContentSource) -> String {
        switch source {
        case .camera(let feed):
            return feed.device.displayName
        case .media(let file, _):
            return file.name
        case .virtual(let camera):
            return camera.name
        case .none:
            return "No Source"
        }
    }
    
    func loadToPreview(_ source: ContentSource) {
        let displayName = getDisplayName(for: source)
        print("🎬 PreviewProgramManager.loadToPreview() called with: \(displayName)")
        print("🎬 Source type: \(source)")
        
        stopPreview()
        removePlayerNotifications(isPreview: true)
        removeKVO(isPreview: true)
        
        switch source {
        case .camera(let feed):
            print("🎬 PreviewProgramManager: Loading camera feed to preview: \(feed.device.displayName)")
            previewSource = source
            Task {
                updatePreviewFromCamera(feed)
            }
            print("🎬 PreviewProgramManager: Preview source set to camera")
        case .media(let file, _):
            unifiedProductionManager.selectedPreviewCameraID = nil
            print("🎬 PreviewProgramManager: Loading media file to preview: \(file.name)")
            print("🎬 PreviewProgramManager: File type is: \(file.fileType)")
            previewSource = .media(file, player: nil)
            
            switch file.fileType {
            case .image:
                print("🖼️ PreviewProgramManager: Loading image to preview")
                loadImageToPreview(file)
            case .video, .audio:
                print("🎬 PreviewProgramManager: Loading video/audio to preview")
                Task {
                    await loadMediaToPreview(file)
                }
            }
        case .virtual(let camera):
            unifiedProductionManager.selectedPreviewCameraID = nil
            print("🎬 PreviewProgramManager: Loading virtual camera to preview: \(camera.name)")
            previewSource = source
            Task {
                updatePreviewFromVirtual(camera)
            }
        case .none:
            print("🎬 PreviewProgramManager: Clearing preview")
            clearPreview()
        }
        
        print("🎬 PreviewProgramManager: loadToPreview completed. Current preview source: \(previewSourceDisplayName)")
    }
    
    func loadToProgram(_ source: ContentSource) {
        let displayName = getDisplayName(for: source)
        print("📺 Loading to program: \(displayName)")
        
        stopProgram()
        removePlayerNotifications(isPreview: false)
        removeKVO(isPreview: false)
        
        switch source {
        case .camera(let feed):
            programSource = source
            Task {
                updateProgramFromCamera(feed)
            }
        case .media(let file, _):
            print("📺 PreviewProgramManager: Loading media file to program: \(file.name)")
            print("📺 PreviewProgramManager: File type is: \(file.fileType)")
            switch file.fileType {
            case .image:
                print("🖼️ PreviewProgramManager: Loading image to program")
                loadImageToProgram(file)
            case .video, .audio:
                print("📺 PreviewProgramManager: Loading video/audio to program")
                Task {
                    await loadMediaToProgram(file)
                }
            }
        case .virtual(let camera):
            programSource = source
            Task {
                updateProgramFromVirtual(camera)
            }
        case .none:
            clearProgram()
        }
    }
    
    func take() {
        print("✂️ TAKE: Moving preview to program")
        
        guard previewSource != .none else {
            print("❌ TAKE: No preview source to take")
            return
        }
        
        if case .camera(let feed) = previewSource {
            Task {
                await unifiedProductionManager.switchProgram(to: feed.device.deviceID)
            }
        }
        
        let oldProgramSource = programSource
        let oldProgramPlayer = programPlayer
        let oldProgramAVPlayback = programAVPlayback
        let oldProgramAudioTap = programAudioTap
        let oldProgramTimeObserver = programTimeObserver
        
        if let observer = oldProgramTimeObserver {
            oldProgramPlayer?.removeTimeObserver(observer)
        }
        oldProgramAVPlayback?.stop()
        if case .media(let file, _) = oldProgramSource {
            file.url.stopAccessingSecurityScopedResource()
        }
        
        removePlayerNotifications(isPreview: false)
        programNotificationTokens = previewNotificationTokens
        previewNotificationTokens.removeAll()
        
        programSource = previewSource
        programPlayer = previewPlayer
        programAVPlayback = previewAVPlayback
        programAudioTap = previewAudioTap
        programTimeObserver = previewTimeObserver
        programImage = previewImage
        programDuration = previewDuration
        programCurrentTime = previewCurrentTime
        isProgramPlaying = isPreviewPlaying
        programAspect = previewAspect
        programLoopEnabled = previewLoopEnabled
        programMuted = previewMuted
        programRate = previewRate
        programVolume = previewVolume
        
        if let programAVPlayback = programAVPlayback {
            programAVPlayback.setEffectRunner(programEffectRunner)
        }
        
        effectManager.copyPreviewEffectsToProgram(overwrite: true)
        
        if let prevChain = effectManager.getPreviewEffectChain(),
           let progChain = effectManager.getProgramEffectChain() {
            let prevKeys = prevChain.effects.compactMap { $0 as? ChromaKeyEffect }
            let progKeys = progChain.effects.compactMap { $0 as? ChromaKeyEffect }
            for (idx, srcCK) in prevKeys.enumerated() {
                guard idx < progKeys.count else { break }
                let dstCK = progKeys[idx]
                if let url = srcCK.backgroundURL {
                    dstCK.setBackground(from: url, device: effectManager.metalDevice)
                    if srcCK.bgIsPlaying { dstCK.playBackgroundVideo() } else { dstCK.pauseBackgroundVideo() }
                    dstCK.parameters["bgScale"]?.value = srcCK.parameters["bgScale"]?.value ?? 1.0
                    dstCK.parameters["bgOffsetX"]?.value = srcCK.parameters["bgOffsetX"]?.value ?? 0.0
                    dstCK.parameters["bgOffsetY"]?.value = srcCK.parameters["bgOffsetY"]?.value ?? 0.0
                    dstCK.parameters["bgRotation"]?.value = srcCK.parameters["bgRotation"]?.value ?? 0.0
                    dstCK.parameters["bgFillMode"]?.value = srcCK.parameters["bgFillMode"]?.value ?? 0.0
                }
            }
        }
        
        programEffectRunner?.setChain(getProgramEffectChain())
        
        previewSource = .none
        previewPlayer = nil
        previewAVPlayback = nil
        previewAudioTap = nil
        previewTimeObserver = nil
        previewImage = nil
        isPreviewPlaying = false
        previewCurrentTime = 0
        previewDuration = 0
        previewVTReady = false
        previewPrimedForPoster = false
        
        stopPreviewMediaPipeline()
        
        crossfaderValue = 0.0
        
        objectWillChange.send()
        
        print("✅ TAKE completed - preview resources transferred to program")
        print("   - Program source: \(programSourceDisplayName)")
        print("   - Program metal texture available: \(programMetalTexture != nil)")
    }
    
    func transition(duration: TimeInterval = 1.0) {
        guard previewSource != .none else { return }
        
        print("🔄 Starting transition over \(duration)s")
        isTransitioning = true
        transitionProgress = 0.0
        
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
                timer.invalidate()
                self.take()
                self.isTransitioning = false
                self.transitionProgress = 0.0
            }
        }
        _ = transitionTimer
    }
    
    func playPreview() {
        if preferVTDecode, let vt = previewVTPlayback {
            print("▶️ playPreview (VT)")
            previewPrimedForPoster = false
            previewAudioPlayer?.rate = previewRate
            previewAudioPlayer?.volume = previewMuted ? 0.0 : previewVolume
            previewAudioPlayer?.play()
            vt.start()
            isPreviewPlaying = true
            return
        }
        guard case .media = previewSource else {
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
        actualPlayer.rate = previewRate
        actualPlayer.volume = previewMuted ? 0.0 : previewVolume
        actualPlayer.play()
        isPreviewPlaying = true
        print("▶️ Preview playing")
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
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
        guard case .media = previewSource else {
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
        print("⏸️ Preview paused")
    }
    
    func stopPreview() {
        if preferVTDecode, previewVTPlayback != nil {
            previewAudioPlayer?.pause()
            previewAudioPlayer?.seek(to: .zero)
            previewVTPlayback?.stop()
            isPreviewPlaying = false
            previewCurrentTime = 0.0
            previewVideoTexture = nil
            stopPreviewMediaPipeline()
            return
        }
        if case .media = previewSource, let actualPlayer = previewPlayer {
            actualPlayer.pause()
            actualPlayer.seek(to: CMTime.zero)
            isPreviewPlaying = false
            previewCurrentTime = 0.0
        }
        stopPreviewMediaPipeline()
    }
    
    func playProgram() {
        if preferVTDecode, let vt = programVTPlayback {
            print("▶️ playProgram (VT)")
            programPrimedForPoster = false
            programAudioPlayer?.rate = programRate
            programAudioPlayer?.volume = programMuted ? 0.0 : programVolume
            programAudioPlayer?.play()
            vt.start()
            isProgramPlaying = true
            return
        }
        guard case .media = programSource else { return }
        guard let actualPlayer = programPlayer else { return }
        actualPlayer.rate = programRate
        actualPlayer.volume = programMuted ? 0.0 : programVolume
        actualPlayer.play()
        isProgramPlaying = true
        print("▶️ Program playing")
    }
    
    func pauseProgram() {
        if preferVTDecode, programVTPlayback != nil {
            print("⏸️ pauseProgram (VT)")
            programAudioPlayer?.pause()
            programVTPlayback?.stop()
            isProgramPlaying = false
            return
        }
        guard case .media = programSource else { return }
        guard let actualPlayer = programPlayer else { return }
        actualPlayer.pause()
        isProgramPlaying = false
        print("⏸️ Program paused")
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
        if case .media = programSource, let actualPlayer = programPlayer {
            actualPlayer.pause()
            actualPlayer.seek(to: CMTime.zero)
            isProgramPlaying = false
            programCurrentTime = 0.0
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
        guard case .media = previewSource else {
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
                Task { @MainActor in
                    self?.previewCurrentTime = time
                }
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
        guard case .media = programSource else { return }
        guard let actualPlayer = programPlayer else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        actualPlayer.seek(to: cmTime) { [weak self] completed in
            if completed {
                Task { @MainActor in
                    self?.programCurrentTime = time
                }
            }
        }
    }
    
    func stepPreviewForward() {
        guard case .media(_, _) = previewSource else { return }
        guard let player = previewPlayer else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let frameRate: Double = 30.0
        let newTime = currentTime + 1.0 / frameRate
        seekPreview(to: newTime)
    }
    
    func stepPreviewBackward() {
        guard case .media(_, _) = previewSource else { return }
        guard let player = previewPlayer else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let frameRate: Double = 30.0
        let newTime = max(0, currentTime - 1.0 / frameRate)
        seekPreview(to: newTime)
    }
    
    func stepProgramForward() {
        guard case .media(_, _) = programSource else { return }
        guard let player = programPlayer else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let frameRate: Double = 30.0
        let newTime = currentTime + 1.0 / frameRate
        seekProgram(to: newTime)
    }
    
    func stepProgramBackward() {
        guard case .media(_, _) = programSource else { return }
        guard let player = programPlayer else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let frameRate: Double = 30.0
        let newTime = max(0, currentTime - 1.0 / frameRate)
        seekProgram(to: newTime)
    }
    
    private func loadMediaToPreview(_ file: MediaFile) async {
        stopPreviewMediaPipeline()
        
        print("🎬 PreviewProgramManager: Starting async loadMediaToPreview for: \(file.name)")
        
        if let observer = self.previewTimeObserver {
            self.previewPlayer?.removeTimeObserver(observer)
            self.previewTimeObserver = nil
        }
        
        if case .media(let previousFile, _) = self.previewSource {
            previousFile.url.stopAccessingSecurityScopedResource()
        }
        
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for: \(file.name)")
            return
        }
        
        // Load preview duration async
        let asset = AVURLAsset(url: file.url)
        Task {
            do {
                let duration = try await asset.load(.duration)
                if duration.isValid {
                    await MainActor.run {
                        self.previewDuration = CMTimeGetSeconds(duration)
                    }
                }
            } catch {
                print("Failed to load PREVIEW duration: \(error)")
            }
        }
        
        previewProcessingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                defer {
                    file.url.stopAccessingSecurityScopedResource()
                    self.stopPreviewMediaPipeline()
                }
                
                try Task.checkCancellation()
                
                let processingStream = await self.frameProcessor.createFrameStream(
                    for: "preview_media",
                    effectChain: self.effectManager.getPreviewEffectChain()
                )
                
                let playerItem = AVPlayerItem(url: file.url)
                let player = AVPlayer(playerItem: playerItem)
                player.automaticallyWaitsToMinimizeStalling = false
                player.allowsExternalPlayback = false
                
                await MainActor.run {
                    self.previewSource = .media(file, player: player)
                    self.previewPlayer = player
                }

                let attrs: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ]
                let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
                playerItem.add(output)
                output.suppressesPlayerRendering = true
                output.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
                
                if let playback = AVPlayerMetalPlayback(player: player, itemOutput: output, device: self.effectManager.metalDevice) {
                    await MainActor.run {
                        self.previewAVPlayback = playback
                    }
                    playback.setEffectRunner(self.previewEffectRunner)
                    playback.start()
                    player.play()
                    
                    // Periodic time observer for preview current time
                    let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
                    self.previewTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
                        guard let self else { return }
                        let seconds = CMTimeGetSeconds(t)
                        Task { @MainActor in
                            self.previewCurrentTime = seconds
                        }
                    }
                    
                    let playbackRef = playback
                    let processor = self.frameProcessor
                    let sourceID = "preview_media"
                    let feedLoop = Task.detached(priority: .userInitiated) {
                        while !Task.isCancelled {
                            try? Task.checkCancellation()
                            if let texture = playbackRef.latestTexture {
                                let timestamp = CMClockGetTime(CMClockGetHostTimeClock())
                                try? await processor.submitTexture(texture, for: sourceID, timestamp: timestamp)
                            }
                            try? await Task.sleep(nanoseconds: 33_333_333)
                        }
                    }
                    
                    for await result in processingStream {
                        if Task.isCancelled { break }
                        await MainActor.run {
                            self.previewVideoTexture = result.outputTexture
                            if let cgImage = result.processedImage {
                                self.previewImage = cgImage
                            }
                            self.objectWillChange.send()
                        }
                    }
                    
                    feedLoop.cancel()
                }
            } catch is CancellationError {
                print("🎬 Preview media processing cancelled")
            } catch {
                print("❌ Preview media processing failed: \(error)")
            }
        }
    }
    
    private func loadMediaToProgram(_ file: MediaFile) async {
        programVTPlayback?.stop()
        programVTPlayback = nil
        programAVPlayback?.stop()
        programAVPlayback = nil
        programVideoTexture = nil
        
        print("🎬 PreviewProgramManager: Starting loadMediaToProgram for: \(file.name)")
        
        if let observer = programTimeObserver {
            programPlayer?.removeTimeObserver(observer)
            programTimeObserver = nil
        }
        
        if case .media(let previousFile, _) = programSource {
            previousFile.url.stopAccessingSecurityScopedResource()
        }
        
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for PROGRAM: \(file.name)")
            return
        }
        
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
            
            if let item = player.currentItem {
                self.programAudioTap = PlayerAudioTap(playerItem: item)
            } else {
                self.programAudioTap = nil
            }
            
            setupPlayerNotifications(for: player, isPreview: false)
            
            let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
            programTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
                guard let self else { return }
                let seconds = CMTimeGetSeconds(t)
                Task { @MainActor in
                    self.programCurrentTime = seconds
                }
            }
            isProgramPlaying = false
            print("✅ Program audio-only configured")
            return
        }
        
        if preferVTDecode && file.fileType == .video {
            // VT path currently disabled by default. Fallthrough to AVPlayer path.
        }
        
        let playerItem = AVPlayerItem(url: file.url)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        playerItem.add(output)
        output.suppressesPlayerRendering = true
        output.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)

        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
        
        self.programAudioTap = PlayerAudioTap(playerItem: playerItem)
        setupPlayerNotifications(for: player, isPreview: false)
        
        if let playback = AVPlayerMetalPlayback(player: player, itemOutput: output, device: effectManager.metalDevice) {
            programAVPlayback = playback
            playback.setEffectRunner(programEffectRunner)
            playback.toneMapEnabled = hdrToneMapEnabled
            playback.targetFPS = targetFPS
            playback.onSizeChange = { [weak self] (w: Int, h: Int) in
                Task { @MainActor in
                    if h > 0 { self?.programAspect = CGFloat(w) / CGFloat(h) }
                }
            }
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
            
            Task { @MainActor in
                self.objectWillChange.send()
                print("📺 PROGRAM Metal playback started - UI updated")
            }
        }
        
        player.rate = programRate
        player.volume = programMuted ? 0.0 : programVolume
        player.play()

        let statusObs = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                if item.status == .readyToPlay {
                    self?.isProgramPlaying = true
                    self?.programPlayer?.rate = self?.programRate ?? 1.0
                    self?.programPlayer?.volume = (self?.programMuted ?? false) ? 0.0 : (self?.programVolume ?? 1.0)
                    self?.programPlayer?.play()
                }
            }
        }
        programKVO.append(statusObs)

        programSource = .media(file, player: player)
        programPlayer = player
        
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        programTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(t)
            Task { @MainActor in
                self.programCurrentTime = seconds
            }
        }

        print("📼 PROGRAM AVPlayer + ItemOutput + Metal playback configured")
    }
    
    private func loadImageToPreview(_ file: MediaFile) {
        print("🖼️ PreviewProgramManager: Starting loadImageToPreview for: \(file.name)")
        
        if let observer = previewTimeObserver {
            previewPlayer?.removeTimeObserver(observer)
            previewTimeObserver = nil
        }
        previewPlayer = nil
        
        if case .media(let previousFile, _) = previewSource {
            previousFile.url.stopAccessingSecurityScopedResource()
        }
        
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for image: \(file.name)")
            return
        }
        
        Task {
            do {
                let imageData = try Data(contentsOf: file.url)
                if let cgImage = NSImage(data: imageData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    await MainActor.run {
                        self.previewImage = cgImage
                        if cgImage.height > 0 { self.previewAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height) }
                        let newSource = ContentSource.media(file, player: nil)
                        self.previewSource = newSource
                        self.previewDuration = 0
                        self.previewCurrentTime = 0
                        self.isPreviewPlaying = false
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
        
        if let observer = programTimeObserver {
            programPlayer?.removeTimeObserver(observer)
            programTimeObserver = nil
        }
        programPlayer = nil
        
        if case .media(let previousFile, _) = programSource {
            previousFile.url.stopAccessingSecurityScopedResource()
        }
        
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for image: \(file.name)")
            return
        }
        
        Task {
            do {
                let imageData = try Data(contentsOf: file.url)
                if let cgImage = NSImage(data: imageData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    await MainActor.run {
                        self.programImage = cgImage
                        if cgImage.height > 0 { self.programAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height) }
                        let newSource = ContentSource.media(file, player: nil)
                        self.programSource = newSource
                        self.programDuration = 0
                        self.programCurrentTime = 0
                        self.isProgramPlaying = false
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
        print("📹 Camera feed connected to preview: \(feed.device.displayName)")
        objectWillChange.send()
    }
    
    private func updateProgramFromCamera(_ feed: CameraFeed) {
        print("📺 Camera feed connected to program: \(feed.device.displayName)")
        objectWillChange.send()
    }
    
    private func updatePreviewFromVirtual(_ camera: VirtualCamera) {
        print("🎭 Virtual camera connected to preview: \(camera.name)")
    }
    
    private func updateProgramFromVirtual(_ camera: VirtualCamera) {
        print("🎭 Virtual camera connected to program: \(camera.name)")
    }
    
    private func clearPreview() {
        previewVTPlayback?.stop()
        previewVTPlayback = nil
        previewVideoTexture = nil
        previewAudioPlayer = nil
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
        previewAudioTap = nil
        stopPreviewMediaPipeline()
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
        programAudioTap = nil
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
    
    private func removePlayerNotifications(isPreview: Bool) {
        let tokens = isPreview ? previewNotificationTokens : programNotificationTokens
        for t in tokens {
            NotificationCenter.default.removeObserver(t)
        }
        if isPreview {
            previewNotificationTokens.removeAll()
        } else {
            programNotificationTokens.removeAll()
        }
    }
    
    private func removeKVO(isPreview: Bool) {
        if isPreview {
            previewKVO.forEach { $0.invalidate() }
            previewKVO.removeAll()
        } else {
            programKVO.forEach { $0.invalidate() }
            programKVO.removeAll()
        }
    }
    
    func processImageWithEffects(_ image: CGImage?, for output: OutputType) -> CGImage? {
        guard let image = image else { return nil }
        let effectChain = output == .preview ? getPreviewEffectChain() : getProgramEffectChain()
        guard let chain = effectChain, !chain.effects.isEmpty else {
            return image
        }
        guard let texture = createMTLTexture(from: image) else { return image }
        let processedTexture: MTLTexture?
        switch output {
        case .preview:
            processedTexture = effectManager.applyPreviewEffects(to: texture)
        case .program:
            processedTexture = effectManager.applyProgramEffects(to: texture)
        }
        return createCGImage(from: processedTexture ?? texture)
    }
    
    private func createMTLTexture(from cgImage: CGImage) -> MTLTexture? {
        let textureLoader = MTKTextureLoader(device: effectManager.metalDevice)
        do {
            let texture = try textureLoader.newTexture(cgImage: cgImage, options: [
                MTKTextureLoader.Option.textureUsage: MTLTextureUsage.shaderRead.rawValue,
                MTKTextureLoader.Option.textureStorageMode: MTLStorageMode.shared.rawValue,
                MTKTextureLoader.Option.generateMipmaps: NSNumber(value: false)
            ])
            return texture
        } catch {
            print("Error creating MTLTexture: \(error)")
            return nil
        }
    }
    
    private func createCGImage(from texture: MTLTexture) -> CGImage? {
        let ciImage = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        guard let image = ciImage else { return nil }
        let flippedImage = image.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -image.extent.height))
        return ciContext.createCGImage(flippedImage, from: flippedImage.extent)
    }
    
    enum OutputType {
        case preview, program
    }
    
    func addEffectToPreview(_ effectType: String) {
        print("✨ PreviewProgramManager: Adding \(effectType) effect to Preview output")
        effectManager.addEffectToPreview(effectType)
        Task { @MainActor in
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.previewEffectRunner?.setChain(self.getPreviewEffectChain())
    }
    
    func addEffectToProgram(_ effectType: String) {
        print("✨ PreviewProgramManager: Adding \(effectType) effect to Program output")
        effectManager.addEffectToProgram(effectType)
        Task { @MainActor in
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.programEffectRunner?.setChain(self.getProgramEffectChain())
    }
    
    func addEffectToPreview(_ effect: any VideoEffect) {
        print("✨ PreviewProgramManager: Adding \(effect.name) effect instance to Preview output")
        effectManager.addEffectToPreview(effect)
        Task { @MainActor in
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.previewEffectRunner?.setChain(self.getPreviewEffectChain())
    }
    
    func addEffectToProgram(_ effect: any VideoEffect) {
        print("✨ PreviewProgramManager: Adding \(effect.name) effect instance to Program output")
        effectManager.addEffectToProgram(effect)
        Task { @MainActor in
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.programEffectRunner?.setChain(self.getProgramEffectChain())
    }
    
    func getPreviewEffectChain() -> EffectChain? {
        return effectManager.getPreviewEffectChain()
    }
    
    func getProgramEffectChain() -> EffectChain? {
        return effectManager.getProgramEffectChain()
    }
    
    func clearPreviewEffects() {
        effectManager.clearPreviewEffects()
        Task { @MainActor in
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.previewEffectRunner?.setChain(self.getPreviewEffectChain())
    }
    
    func clearProgramEffects() {
        effectManager.clearProgramEffects()
        Task { @MainActor in
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
    
    // Back-compat API
    var previewMetalTexture: MTLTexture? {
        previewAVPlayback?.latestTexture ?? previewVideoTexture
    }
    var programMetalTexture: MTLTexture? {
        programAVPlayback?.latestTexture ?? programVideoTexture
    }
    
    func captureNextPreviewFrame() {
        previewAVPlayback?.captureNextFrame()
    }
    func captureNextProgramFrame() {
        programAVPlayback?.captureNextFrame()
    }
    
    private func setupPlayerNotifications(for player: AVPlayer, isPreview: Bool) {
        if let item = player.currentItem {
            let token = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: OperationQueue.main
            ) { [weak self] _ in
                guard let self = self else { return }
                if isPreview && self.previewLoopEnabled {
                    player.seek(to: CMTime.zero)
                    player.play()
                } else if !isPreview && self.programLoopEnabled {
                    player.seek(to: CMTime.zero)
                    player.play()
                } else {
                    if isPreview {
                        self.isPreviewPlaying = false
                    } else {
                        self.isProgramPlaying = false
                    }
                }
            }
            if isPreview {
                previewNotificationTokens.append(token)
            } else {
                programNotificationTokens.append(token)
            }
        }
    }
}

// MARK: - Convenience suppliers

extension PreviewProgramManager {
    func makePreviewTextureSupplier() -> () -> MTLTexture? {
        return { [weak self] in
            guard let self else { return nil }
            return self.previewAVPlayback?.latestTexture ?? self.previewVideoTexture
        }
    }
    func makeProgramTextureSupplier() -> () -> MTLTexture? {
        return { [weak self] in
            guard let self else { return nil }
            return self.programAVPlayback?.latestTexture ?? self.programVideoTexture
        }
    }
}

extension MediaFile {
    func asContentSource() -> ContentSource {
        return .media(self, player: nil)
    }
}

extension CameraFeed {
    func asContentSource() -> ContentSource {
        return .camera(self)
    }
}

extension VirtualCamera {
    func asContentSource() -> ContentSource {
        return .virtual(self)
    }
}

// MARK: - Preview Media Pipeline Cleanup

extension PreviewProgramManager {
    private func stopPreviewMediaPipeline() {
        previewProcessingTask?.cancel()
        previewProcessingTask = nil
        
        Task { [weak self] in
            await self?.frameProcessor.stopFrameStream(for: "preview_media")
        }
        
        if let pav = previewAVPlayback, pav !== programAVPlayback {
            pav.stop()
        }
        previewAVPlayback = nil
    }
}