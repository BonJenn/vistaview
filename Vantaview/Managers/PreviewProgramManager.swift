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
import os

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
    private static let log = OSLog(subsystem: "com.vantaview", category: "PreviewProgram")

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
    
    private var previewNotificationTokens: [NSObjectProtocol] = []
    private var programNotificationTokens: [NSObjectProtocol] = []
    private var previewKVO: [NSKeyValueObservation] = []
    private var programKVO: [NSKeyValueObservation] = []
    
    @Published var previewVideoTexture: MTLTexture?
    @Published var programVideoTexture: MTLTexture?
    private var previewAudioPlayer: AVPlayer?
    private var programAudioPlayer: AVPlayer?
    
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

    // CHANGE: Studio Mode toggle (Preview UI/pipeline opt-in). Default off to match Gaming template behavior.
    @Published var studioModeEnabled: Bool = false
    
    var previewSourceDisplayName: String {
        return getDisplayName(for: previewSource)
    }
    var programSourceDisplayName: String {
        return getDisplayName(for: programSource)
    }
    
    private var previewEffectRunner: EffectRunner?
    private var programEffectRunner: EffectRunner?
    
    // Background feed loop for submitting preview textures to FrameProcessor
    private var previewFeedLoopTask: Task<Void, Never>?
    private var previewFeedLoopID: UUID?
    
    // Security-scoped URL lifetimes (do not stop early)
    private var previewSecurityScopedURL: URL?
    private var programSecurityScopedURL: URL?
    
    // Time smoothing / seek state
    private var previewIsSeeking = false
    private var programIsSeeking = false
    private var lastPreviewTime: Double = 0
    private var lastProgramTime: Double = 0
    
    // Seek debouncing to avoid playhead bounce
    private var previewSeekTarget: Double?
    private var programSeekTarget: Double?
    private var previewSuppressObserverUntil: CFTimeInterval = 0
    private var programSuppressObserverUntil: CFTimeInterval = 0
    
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
            self.previewFeedLoopTask?.cancel()
            self.previewFeedLoopTask = nil
            if let url = self.previewSecurityScopedURL { url.stopAccessingSecurityScopedResource() }
            if let url = self.programSecurityScopedURL { url.stopAccessingSecurityScopedResource() }
            self.previewSecurityScopedURL = nil
            self.programSecurityScopedURL = nil
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
        previewFeedLoopTask?.cancel()
        previewFeedLoopTask = nil
        if let url = previewSecurityScopedURL { url.stopAccessingSecurityScopedResource() }
        if let url = programSecurityScopedURL { url.stopAccessingSecurityScopedResource() }
        previewSecurityScopedURL = nil
        programSecurityScopedURL = nil
        previewPlayer = nil
        programPlayer = nil
    }
    
    // ADD: Studio Mode API
    func setStudioModeEnabled(_ enabled: Bool) {
        guard studioModeEnabled != enabled else { return }
        studioModeEnabled = enabled
        if !enabled {
            stopPreview()
            clearPreview()
        }
        objectWillChange.send()
    }
    
    func toggleStudioMode() {
        setStudioModeEnabled(!studioModeEnabled)
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
        // ADD: In non-Studio mode, route preview requests directly to Program to keep the pipeline lean.
        if !studioModeEnabled {
            loadToProgram(source)
            return
        }
        
        let displayName = getDisplayName(for: source)
        print("🎬 PreviewProgramManager.loadToPreview() called with: \(displayName)")
        print("🎬 Source type: \(source)")
        
        stopPreview()
        removePlayerNotifications(isPreview: true)
        removeKVO(isPreview: true)
        
        switch source {
        case .camera(let feed):
            print("🎬 PreviewProgramManager: Loading camera feed to preview: \(feed.device.displayName)")
            unifiedProductionManager.selectedPreviewCameraID = feed.device.deviceID
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
                loadImageToPreview(file)
            case .video, .audio:
                Task {
                    await loadMediaToPreview(file)
                }
            }
        case .virtual(let camera):
            unifiedProductionManager.selectedPreviewCameraID = nil
            previewSource = source
            Task {
                updatePreviewFromVirtual(camera)
            }
        case .none:
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
            switch file.fileType {
            case .image:
                loadImageToProgram(file)
            case .video, .audio:
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
        guard previewSource != .none else { return }
        
        if case .camera(let feed) = previewSource {
            Task {
                await unifiedProductionManager.switchProgram(to: feed.device.deviceID)
            }
        }
        
        if let url = programSecurityScopedURL {
            url.stopAccessingSecurityScopedResource()
            programSecurityScopedURL = nil
        }
        
        let oldProgramPlayer = programPlayer
        let oldProgramAVPlayback = programAVPlayback
        let oldProgramTimeObserver = programTimeObserver
        
        if let observer = oldProgramTimeObserver {
            oldProgramPlayer?.removeTimeObserver(observer)
        }
        oldProgramAVPlayback?.stop()
        
        removePlayerNotifications(isPreview: false)
        programNotificationTokens = previewNotificationTokens
        previewNotificationTokens.removeAll()
        
        // Transfer live pipeline + security token
        programSource = previewSource
        programPlayer = previewPlayer
        programAVPlayback = previewAVPlayback
        programAudioTap = previewAudioTap
        programImage = previewImage
        programDuration = previewDuration
        programCurrentTime = previewCurrentTime
        isProgramPlaying = isPreviewPlaying
        programAspect = previewAspect
        programLoopEnabled = previewLoopEnabled
        programMuted = previewMuted
        programRate = previewRate
        programVolume = previewVolume
        programSecurityScopedURL = previewSecurityScopedURL
        previewSecurityScopedURL = nil
        
        if let programAVPlayback = programAVPlayback {
            programAVPlayback.setEffectRunner(programEffectRunner)
        }
        
        effectManager.copyPreviewEffectsToProgram(overwrite: true)
        programEffectRunner?.setChain(getProgramEffectChain())
        
        if let transferredPlayer = programPlayer {
            if let prevObs = previewTimeObserver {
                transferredPlayer.removeTimeObserver(prevObs)
            }
            previewTimeObserver = nil
            attachProgramTimeObserver(to: transferredPlayer)
        } else {
            removeProgramTimeObserver()
        }
        
        // Reset preview state
        previewSource = .none
        previewPlayer = nil
        previewAVPlayback = nil
        previewAudioTap = nil
        previewImage = nil
        isPreviewPlaying = false
        previewCurrentTime = 0
        previewDuration = 0
        previewVTReady = false
        previewPrimedForPoster = false
        lastPreviewTime = 0
        previewIsSeeking = false
        previewSeekTarget = nil
        previewSuppressObserverUntil = 0
        
        stopPreviewMediaPipeline()
        
        crossfaderValue = 0.0
        objectWillChange.send()
        
        print("✅ TAKE completed - programMetalTexture available: \(programMetalTexture != nil)")
    }
    
    func transition(duration: TimeInterval = 1.0) {
        guard previewSource != .none else { return }
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
        if !studioModeEnabled { return }
        if preferVTDecode, let vt = previewVTPlayback {
            previewPrimedForPoster = false
            previewAudioPlayer?.rate = previewRate
            previewAudioPlayer?.volume = previewMuted ? 0.0 : previewVolume
            previewAudioPlayer?.play()
            vt.start()
            isPreviewPlaying = true
            return
        }
        guard case .media = previewSource, let actualPlayer = previewPlayer else { return }
        actualPlayer.rate = previewRate
        actualPlayer.volume = previewMuted ? 0.0 : previewVolume
        actualPlayer.play()
        isPreviewPlaying = true
    }
    
    func pausePreview() {
        if !studioModeEnabled { return }
        if preferVTDecode, previewVTPlayback != nil {
            previewAudioPlayer?.pause()
            previewVTPlayback?.stop()
            isPreviewPlaying = false
            return
        }
        guard case .media = previewSource, let actualPlayer = previewPlayer else { return }
        actualPlayer.pause()
        isPreviewPlaying = false
    }
    
    func stopPreview() {
        if preferVTDecode, previewVTPlayback != nil {
            previewAudioPlayer?.pause()
            previewAudioPlayer?.seek(to: .zero)
            previewVTPlayback?.stop()
            isPreviewPlaying = false
            previewCurrentTime = 0.0
            lastPreviewTime = 0
            previewVideoTexture = nil
            previewSeekTarget = nil
            previewSuppressObserverUntil = 0
            removePreviewTimeObserver()
            stopPreviewMediaPipeline()
            if let pav = previewAVPlayback, pav !== programAVPlayback {
                detachOutputs(from: previewPlayer)
            }
            return
        }
        if case .media = previewSource, let actualPlayer = previewPlayer {
            actualPlayer.pause()
            actualPlayer.seek(to: CMTime.zero)
            isPreviewPlaying = false
            previewCurrentTime = 0.0
            lastPreviewTime = 0
        }
        previewSeekTarget = nil
        previewSuppressObserverUntil = 0
        removePreviewTimeObserver()
        stopPreviewMediaPipeline()
        if let pav = previewAVPlayback, pav !== programAVPlayback {
            detachOutputs(from: previewPlayer)
        }
    }
    
    func playProgram() {
        if preferVTDecode, let vt = programVTPlayback {
            programPrimedForPoster = false
            programAudioPlayer?.rate = programRate
            programAudioPlayer?.volume = programMuted ? 0.0 : programVolume
            programAudioPlayer?.play()
            vt.start()
            isProgramPlaying = true
            return
        }
        guard case .media = programSource, let actualPlayer = programPlayer else { return }
        actualPlayer.rate = programRate
        actualPlayer.volume = programMuted ? 0.0 : programVolume
        actualPlayer.play()
        isProgramPlaying = true
    }
    
    func pauseProgram() {
        if preferVTDecode, programVTPlayback != nil {
            programAudioPlayer?.pause()
            programVTPlayback?.stop()
            isProgramPlaying = false
            return
        }
        guard case .media = programSource, let actualPlayer = programPlayer else { return }
        actualPlayer.pause()
        isProgramPlaying = false
    }
    
    func stopProgram() {
        if preferVTDecode, programVTPlayback != nil {
            programAudioPlayer?.pause()
            programAudioPlayer?.seek(to: .zero)
            programVTPlayback?.stop()
            isProgramPlaying = false
            programCurrentTime = 0.0
            lastProgramTime = 0
            programVideoTexture = nil
            programSeekTarget = nil
            programSuppressObserverUntil = 0
            removeProgramTimeObserver()
            if programAVPlayback != nil {
                detachOutputs(from: programPlayer)
            }
            return
        }
        if case .media = programSource, let actualPlayer = programPlayer {
            actualPlayer.pause()
            actualPlayer.seek(to: CMTime.zero)
            isProgramPlaying = false
            programCurrentTime = 0.0
            lastProgramTime = 0
        }
        programSeekTarget = nil
        programSuppressObserverUntil = 0
        removeProgramTimeObserver()
        if programAVPlayback != nil {
            detachOutputs(from: programPlayer)
        }
    }
    
    func seekPreview(to time: TimeInterval) {
        if !studioModeEnabled { return }
        if preferVTDecode, let vt = previewVTPlayback {
            let cm = CMTime(seconds: time, preferredTimescale: 600)
            previewIsSeeking = true
            previewSeekTarget = time
            previewCurrentTime = time
            lastPreviewTime = time
            previewAudioPlayer?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.previewIsSeeking = false
                    self.previewSuppressObserverUntil = CACurrentMediaTime() + 0.2
                }
            })
            vt.seek(to: time)
            return
        }
        guard case .media = previewSource, let actualPlayer = previewPlayer else { return }
        let shouldResume = actualPlayer.rate > 0.0 || isPreviewPlaying
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        previewIsSeeking = true
        previewSeekTarget = time
        previewCurrentTime = time
        lastPreviewTime = time
        actualPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            Task { @MainActor in
                guard let self else { return }
                self.previewIsSeeking = false
                self.previewSuppressObserverUntil = CACurrentMediaTime() + 0.2
                if completed {
                    if shouldResume {
                        actualPlayer.rate = self.previewRate
                        actualPlayer.volume = self.previewMuted ? 0.0 : self.previewVolume
                        actualPlayer.play()
                        self.isPreviewPlaying = true
                    }
                }
            }
        }
    }
    
    func seekProgram(to time: TimeInterval) {
        if preferVTDecode, let vt = programVTPlayback {
            let cm = CMTime(seconds: time, preferredTimescale: 600)
            programIsSeeking = true
            programSeekTarget = time
            programCurrentTime = time
            lastProgramTime = time
            programAudioPlayer?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.programIsSeeking = false
                    self.programSuppressObserverUntil = CACurrentMediaTime() + 0.2
                }
            })
            vt.seek(to: time)
            return
        }
        guard case .media = programSource, let actualPlayer = programPlayer else { return }
        let shouldResume = actualPlayer.rate > 0.0 || isProgramPlaying
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        programIsSeeking = true
        programSeekTarget = time
        programCurrentTime = time
        lastProgramTime = time
        actualPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            Task { @MainActor in
                guard let self else { return }
                self.programIsSeeking = false
                self.programSuppressObserverUntil = CACurrentMediaTime() + 0.2
                if completed {
                    if shouldResume {
                        actualPlayer.rate = self.programRate
                        actualPlayer.volume = self.programMuted ? 0.0 : self.programVolume
                        actualPlayer.play()
                        self.isProgramPlaying = true
                    }
                }
            }
        }
    }
    
    func stepPreviewForward() {
        if !studioModeEnabled { return }
        guard case .media(_, _) = previewSource, let player = previewPlayer else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let frameRate: Double = 30.0
        let newTime = currentTime + 1.0 / frameRate
        seekPreview(to: newTime)
    }
    
    func stepPreviewBackward() {
        if !studioModeEnabled { return }
        guard case .media(_, _) = previewSource, let player = previewPlayer else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let frameRate: Double = 30.0
        let newTime = max(0, currentTime - 1.0 / frameRate)
        seekPreview(to: newTime)
    }
    
    func stepProgramForward() {
        guard case .media(_, _) = programSource, let player = programPlayer else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let frameRate: Double = 30.0
        let newTime = currentTime + 1.0 / frameRate
        seekProgram(to: newTime)
    }
    
    func stepProgramBackward() {
        guard case .media(_, _) = programSource, let player = programPlayer else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let frameRate: Double = 30.0
        let newTime = max(0, currentTime - 1.0 / frameRate)
        seekProgram(to: newTime)
    }
    
    private func loadMediaToPreview(_ file: MediaFile) async {
        print("🎬 [PVW] Preparing media pipeline...")
        stopPreviewMediaPipeline()
        previewFeedLoopTask?.cancel()
        previewFeedLoopTask = nil
        previewFeedLoopID = nil
        lastPreviewTime = 0
        previewIsSeeking = false
        previewSeekTarget = nil
        previewSuppressObserverUntil = 0
        
        if let observer = self.previewTimeObserver {
            self.previewPlayer?.removeTimeObserver(observer)
            self.previewTimeObserver = nil
        }
        
        if let prevURL = previewSecurityScopedURL, prevURL != file.url {
            prevURL.stopAccessingSecurityScopedResource()
            previewSecurityScopedURL = nil
        }
        
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for: \(file.name)")
            return
        }
        previewSecurityScopedURL = file.url
        
        let asset = AVURLAsset(url: file.url)
        Task {
            do {
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.previewDuration = (duration.isValid && !duration.isIndefinite) ? CMTimeGetSeconds(duration) : 0
                }
            } catch {
                print("Failed to load PREVIEW duration: \(error)")
            }
        }
        
        previewProcessingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await withTaskCancellationHandler(operation: {
                    try Task.checkCancellation()
                    
                    let processingStream = await self.frameProcessor.createFrameStream(
                        for: "preview_media",
                        effectChain: self.effectManager.getPreviewEffectChain()
                    )
                    
                    let playerItem = AVPlayerItem(url: file.url)
                    playerItem.preferredForwardBufferDuration = 0.2
                    let player = AVPlayer(playerItem: playerItem)
                    player.automaticallyWaitsToMinimizeStalling = false
                    player.allowsExternalPlayback = false
                    player.actionAtItemEnd = .pause
                    
                    await MainActor.run {
                        self.previewSource = .media(file, player: player)
                        self.previewPlayer = player
                    }

                    let attrs: [String: Any] = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                        kCVPixelBufferMetalCompatibilityKey as String: true,
                        kCVPixelBufferPoolMinimumBufferCountKey as String: 3
                    ]
                    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
                    playerItem.add(output)
                    output.suppressesPlayerRendering = true
                    output.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
                    
                    await MainActor.run {
                        self.setupPlayerNotifications(for: player, isPreview: true)
                    }
                    
                    if let playback = AVPlayerMetalPlayback(player: player, itemOutput: output, device: self.effectManager.metalDevice) {
                        await MainActor.run {
                            self.previewAVPlayback = playback
                        }
                        playback.setEffectRunner(self.previewEffectRunner)
                        playback.toneMapEnabled = self.hdrToneMapEnabled
                        playback.targetFPS = self.targetFPS
                        playback.onSizeChange = { [weak self] (w: Int, h: Int) in
                            Task { @MainActor in
                                if h > 0 { self?.previewAspect = CGFloat(w) / CGFloat(h) }
                            }
                        }
                        playback.onFPSUpdate = { [weak self] fps in
                            Task { @MainActor in
                                self?.previewFPS = fps
                            }
                        }
                        playback.onWatchdog = { [weak self] in
                            self?.captureNextPreviewFrame()
                        }
                        playback.start()
                        
                        await MainActor.run {
                            player.volume = self.previewMuted ? 0.0 : self.previewVolume
                            player.playImmediately(atRate: self.previewRate)
                            self.isPreviewPlaying = true
                        }
                        
                        let interval = CMTime(seconds: 1.0/30.0, preferredTimescale: 600)
                        let obs = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
                            guard let self else { return }
                            let seconds = CMTimeGetSeconds(t)
                            Task { @MainActor in
                                self.updatePreviewTime(seconds: seconds)
                            }
                        }
                        await MainActor.run {
                            self.previewTimeObserver = obs
                        }
                        
                        let statusObs = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                            Task { @MainActor in
                                guard let self else { return }
                                if item.status == .readyToPlay {
                                    self.isPreviewPlaying = true
                                    self.previewPlayer?.volume = self.previewMuted ? 0.0 : self.previewVolume
                                    self.previewPlayer?.playImmediately(atRate: self.previewRate)
                                }
                            }
                        }
                        await MainActor.run {
                            self.previewKVO.append(statusObs)
                        }
                        
                        for await _ in processingStream {
                            if Task.isCancelled { break }
                        }
                    }
                }, onCancel: { [weak self] in
                    print("🛑 [PVW] previewProcessingTask cancelled")
                    Task { [weak self] in
                        await self?.frameProcessor.stopFrameStream(for: "preview_media")
                    }
                })
            } catch is CancellationError {
                print("🎬 Preview media processing cancelled")
            } catch {
                print("❌ Preview media processing failed: \(error)")
            }
        }
    }
    
    private func loadMediaToProgram(_ file: MediaFile) async {
        print("📺 [PGM] Preparing media pipeline...")
        programVTPlayback?.stop()
        programVTPlayback = nil
        programAVPlayback?.stop()
        programAVPlayback = nil
        programVideoTexture = nil
        lastProgramTime = 0
        programIsSeeking = false
        programSeekTarget = nil
        programSuppressObserverUntil = 0
        
        if let observer = programTimeObserver {
            programPlayer?.removeTimeObserver(observer)
            programTimeObserver = nil
        }
        
        if let prevURL = programSecurityScopedURL, prevURL != file.url {
            prevURL.stopAccessingSecurityScopedResource()
            programSecurityScopedURL = nil
        }
        
        guard file.url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to start accessing security-scoped resource for PROGRAM: \(file.name)")
            return
        }
        programSecurityScopedURL = file.url
        
        let asset = AVURLAsset(url: file.url)
        Task {
            do {
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.programDuration = (duration.isValid && !duration.isIndefinite) ? CMTimeGetSeconds(duration) : 0
                }
            } catch {
                print("Failed to load PROGRAM duration: \(error)")
            }
        }
        
        let hasVideoTrack = !asset.tracks(withMediaType: .video).isEmpty
        if file.fileType == .audio || !hasVideoTrack {
            let player = createAudioOnlyPlayer(for: asset) ?? AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player.currentItem?.preferredForwardBufferDuration = 0.2
            programAudioPlayer = player
            programPlayer = player
            programSource = .media(file, player: player)
            
            if let item = player.currentItem {
                self.programAudioTap = PlayerAudioTap(playerItem: item)
            } else {
                self.programAudioTap = nil
            }
            
            setupPlayerNotifications(for: player, isPreview: false)
            
            attachProgramTimeObserver(to: player)
            isProgramPlaying = false
            return
        }
        
        let playerItem = AVPlayerItem(url: file.url)
        playerItem.preferredForwardBufferDuration = 0.2
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        playerItem.add(output)
        output.suppressesPlayerRendering = true
        output.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)

        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = .pause
        
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
                self?.captureNextProgramFrame()
            }
            playback.start()
            
            Task { @MainActor in
                self.objectWillChange.send()
            }
        }
        
        Task { @MainActor in
            player.volume = self.programMuted ? 0.0 : self.programVolume
            player.playImmediately(atRate: self.programRate)
            self.isProgramPlaying = true
        }

        let statusObs = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                if item.status == .readyToPlay {
                    self?.isProgramPlaying = true
                    self?.programPlayer?.volume = (self?.programMuted ?? false) ? 0.0 : (self?.programVolume ?? 1.0)
                    if let rate = self?.programRate {
                        self?.programPlayer?.playImmediately(atRate: rate)
                    }
                }
            }
        }
        programKVO.append(statusObs)

        programSource = .media(file, player: player)
        programPlayer = player
        
        attachProgramTimeObserver(to: player)
    }
    
    private func loadImageToPreview(_ file: MediaFile) {
        if let observer = previewTimeObserver {
            previewPlayer?.removeTimeObserver(observer)
            previewTimeObserver = nil
        }
        previewPlayer = nil
        
        if let url = previewSecurityScopedURL {
            url.stopAccessingSecurityScopedResource()
            previewSecurityScopedURL = nil
        }
        
        guard file.url.startAccessingSecurityScopedResource() else { return }
        previewSecurityScopedURL = file.url
        
        Task {
            defer {
                self.previewSecurityScopedURL?.stopAccessingSecurityScopedResource()
                self.previewSecurityScopedURL = nil
            }
            do {
                let imageData = try Data(contentsOf: file.url)
                if let cgImage = NSImage(data: imageData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    await MainActor.run {
                        self.previewImage = cgImage
                        if cgImage.height > 0 { self.previewAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height) }
                        self.previewSource = .media(file, player: nil)
                        self.previewDuration = 0
                        self.previewCurrentTime = 0
                        self.isPreviewPlaying = false
                        self.objectWillChange.send()
                    }
                }
            } catch {
                print("❌ Failed to load image data: \(error)")
            }
        }
    }
    
    private func loadImageToProgram(_ file: MediaFile) {
        if let observer = programTimeObserver {
            programPlayer?.removeTimeObserver(observer)
            programTimeObserver = nil
        }
        programPlayer = nil
        
        if let url = programSecurityScopedURL {
            url.stopAccessingSecurityScopedResource()
            programSecurityScopedURL = nil
        }
        
        guard file.url.startAccessingSecurityScopedResource() else { return }
        programSecurityScopedURL = file.url
        
        Task {
            defer {
                self.programSecurityScopedURL?.stopAccessingSecurityScopedResource()
                self.programSecurityScopedURL = nil
            }
            do {
                let imageData = try Data(contentsOf: file.url)
                if let cgImage = NSImage(data: imageData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    await MainActor.run {
                        self.programImage = cgImage
                        if cgImage.height > 0 { self.programAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height) }
                        self.programSource = .media(file, player: nil)
                        self.programDuration = 0
                        self.programCurrentTime = 0
                        self.isProgramPlaying = false
                        self.objectWillChange.send()
                    }
                }
            } catch {
                print("❌ Failed to load image data: \(error)")
            }
        }
    }
    
    private func updatePreviewFromCamera(_ feed: CameraFeed) {
        objectWillChange.send()
    }
    
    private func updateProgramFromCamera(_ feed: CameraFeed) {
        objectWillChange.send()
    }
    
    private func updatePreviewFromVirtual(_ camera: VirtualCamera) {}
    private func updateProgramFromVirtual(_ camera: VirtualCamera) {}
    
    private func clearPreview() {
        previewVTPlayback?.stop()
        previewVTPlayback = nil
        previewVideoTexture = nil
        previewAudioPlayer = nil
        if let url = previewSecurityScopedURL {
            url.stopAccessingSecurityScopedResource()
            previewSecurityScopedURL = nil
        }
        previewSource = .none
        previewPlayer = nil
        previewImage = nil
        isPreviewPlaying = false
        previewCurrentTime = 0
        previewDuration = 0
        lastPreviewTime = 0
        previewVTReady = false
        previewPrimedForPoster = false
        previewAudioTap = nil
        previewSeekTarget = nil
        previewSuppressObserverUntil = 0
        removePreviewTimeObserver()
        stopPreviewMediaPipeline()
    }
    
    private func clearProgram() {
        programVTPlayback?.stop()
        programVTPlayback = nil
        programVideoTexture = nil
        programAudioPlayer = nil
        if let url = programSecurityScopedURL {
            url.stopAccessingSecurityScopedResource()
            programSecurityScopedURL = nil
        }
        programSource = .none
        programPlayer = nil
        programImage = nil
        isProgramPlaying = false
        programCurrentTime = 0
        programDuration = 0
        lastProgramTime = 0
        programVTReady = false
        programPrimedForPoster = false
        programAudioTap = nil
        programSeekTarget = nil
        programSuppressObserverUntil = 0
        removeProgramTimeObserver()
    }
    
    private func removePreviewTimeObserver() {
        if let observer = previewTimeObserver {
            print("🧹 Removing preview time observer")
            previewPlayer?.removeTimeObserver(observer)
            previewTimeObserver = nil
        }
    }
    
    private func removeProgramTimeObserver() {
        if let observer = programTimeObserver {
            print("🧹 Removing program time observer")
            programPlayer?.removeTimeObserver(observer)
            programTimeObserver = nil
        }
    }
    
    private func removeTimeObservers() {
        removePreviewTimeObserver()
        removeProgramTimeObserver()
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
        effectManager.addEffectToPreview(effectType)
        Task { @MainActor in
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.previewEffectRunner?.setChain(self.getPreviewEffectChain())
    }
    
    func addEffectToProgram(_ effectType: String) {
        effectManager.addEffectToProgram(effectType)
        Task { @MainActor in
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.programEffectRunner?.setChain(self.getProgramEffectChain())
    }
    
    func addEffectToPreview(_ effect: any VideoEffect) {
        effectManager.addEffectToPreview(effect)
        Task { @MainActor in
            self.objectWillChange.send()
            self.unifiedProductionManager.objectWillChange.send()
        }
        self.previewEffectRunner?.setChain(self.getPreviewEffectChain())
    }
    
    func addEffectToProgram(_ effect: any VideoEffect) {
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
            item.preferredForwardBufferDuration = 0.2
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
                    player.seek(to: .zero)
                    player.play()
                } else if !isPreview && self.programLoopEnabled {
                    player.seek(to: .zero)
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

extension PreviewProgramManager {
    private func stopPreviewMediaPipeline() {
        previewProcessingTask?.cancel()
        previewProcessingTask = nil
        
        previewFeedLoopTask?.cancel()
        previewFeedLoopTask = nil
        previewFeedLoopID = nil
        
        Task { [weak self] in
            await self?.frameProcessor.stopFrameStream(for: "preview_media")
        }
        
        if let pav = previewAVPlayback, pav !== programAVPlayback {
            pav.stop()
        }
        previewAVPlayback = nil
    }
    
    private func detachOutputs(from player: AVPlayer?) {
        guard let item = player?.currentItem else { return }
        if !item.outputs.isEmpty {
            print("🧹 Detaching \(item.outputs.count) AVPlayerItemVideoOutput(s) from item")
        }
        for out in item.outputs {
            item.remove(out)
        }
    }
    
    private func updatePreviewTime(seconds: Double) {
        if previewIsSeeking { return }
        let now = CACurrentMediaTime()
        if now < previewSuppressObserverUntil { return }
        if let target = previewSeekTarget {
            if seconds + 0.05 < target {
                return
            } else {
                previewSeekTarget = nil
            }
        }
        let delta = seconds - lastPreviewTime
        if isPreviewPlaying && delta < -0.25 {
            return
        }
        lastPreviewTime = seconds
        previewCurrentTime = seconds
    }
    
    private func updateProgramTime(seconds: Double) {
        if programIsSeeking { return }
        let now = CACurrentMediaTime()
        if now < programSuppressObserverUntil { return }
        if let target = programSeekTarget {
            if seconds + 0.05 < target {
                return
            } else {
                programSeekTarget = nil
            }
        }
        let delta = seconds - lastProgramTime
        if isProgramPlaying && delta < -0.25 {
            return
        }
        lastProgramTime = seconds
        programCurrentTime = seconds
    }
    
    private func attachProgramTimeObserver(to player: AVPlayer) {
        removeProgramTimeObserver()
        let interval = CMTime(seconds: 1.0/30.0, preferredTimescale: 600)
        programTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(t)
            Task { @MainActor in
                self.updateProgramTime(seconds: seconds)
            }
        }
    }
}