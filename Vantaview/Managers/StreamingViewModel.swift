import Foundation
import SwiftUI
import HaishinKit
import AVFoundation
import CoreVideo
import CoreMedia
import CoreImage
import Metal
import ImageIO
import CoreGraphics
import VideoToolbox
#if os(macOS)
import AppKit
#endif

@MainActor
class StreamingViewModel: ObservableObject {
    private let mixer = MediaMixer()
    private let connection = RTMPConnection()
    private let stream: RTMPStream
    private var previewView: MTHKView?

    @Published var isPublishing = false
    @Published var cameraSetup = false
    @Published var statusMessage = "Initializing..."
    @Published var mirrorProgramOutput: Bool = true

    @Published var programAudioRMS: Float = 0
    @Published var programAudioPeak: Float = 0
    @Published var avSyncOffsetMs: Double = 0

    private let targetSampleRate: Double = 48_000

    private var lastAudioPTS: CMTime = .zero
    private var lastVideoPTS: CMTime = .zero

    private var micEngine: AVAudioEngine?
    private let micLock = NSLock()
    private var micLatestData = Data()
    private var micLatestFrames: Int = 0
    private var micSampleRate: Double = 48_000

    enum AudioSource: String, CaseIterable, Identifiable {
        case microphone, program, none
        case micAndProgram
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .microphone: return "Microphone"
            case .program: return "Program Audio"
            case .none: return "None"
            case .micAndProgram: return "Mic + Program"
            }
        }
    }
    @Published var selectedAudioSource: AudioSource = .microphone
    @Published var includePiPAudioInProgram: Bool = false

    // External managers for PiP and Program mirroring
    weak var programManager: PreviewProgramManager?
    weak var layerManager: LayerStackManager?
    weak var productionManager: UnifiedProductionManager?

    // Video encode/composite context
    private let programTargetFPS: Double = 60
    private let programCIContext = CIContext(options: [.cacheIntermediates: false])
    private var programPixelBufferPool: CVPixelBufferPool?
    private var programVideoFormat: CMVideoFormatDescription?

    // Timing
    private let hostClock: CMClock = CMClockGetHostTimeClock()

    // Audio capture/pump
    private var micAttached: Bool = false
    private let audioPollInterval: TimeInterval = 1.0 / 240.0
    private let audioQueue = DispatchQueue(label: "vantaview.stream.audio", qos: .userInteractive)
    private var audioSource: DispatchSourceTimer?

    // Video frame pump
    private let videoQueue = DispatchQueue(label: "vantaview.stream.video", qos: .userInteractive)
    private var frameSource: DispatchSourceTimer?

    // Simplified rendering
    private var isRenderingFrame = false

    private typealias AudioSnapshot = (programGain: Float, programTap: PlayerAudioTap?, includePiP: Bool, taps: [(tap: PlayerAudioTap, gain: Float, pan: Float, id: UUID)])

    init() {
        stream = RTMPStream(connection: connection)
        setupAudioSession()
        #if DEBUG
        print("StreamingViewModel: Initialized")
        #endif
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            statusMessage = "Audio session configured"
            print("✅ Audio session setup successful")
        } catch {
            statusMessage = "Audio session error: \(error.localizedDescription)"
            print("❌ Audio session setup error:", error)
        }
        #else
        statusMessage = "macOS - no audio session needed"
        print("✅ macOS detected - skipping audio session setup")
        #endif
    }
    
    func setupCameraWithDevice(_ videoDevice: AVCaptureDevice) async {
        if mirrorProgramOutput {
            print("🪞 Program mirroring active: skipping setupCameraWithDevice")
            statusMessage = "Program mirroring: camera disabled"
            cameraSetup = false
            return
        }
        statusMessage = "Setting up selected camera..."
        print("🎥 Setting up camera with specific device: \(videoDevice.localizedName)")
        
        do {
            print("✅ Using selected camera: \(videoDevice.localizedName)")
            statusMessage = "Connecting to: \(videoDevice.localizedName)"
            print("📹 Attaching selected camera to mixer...")
            try await mixer.attachVideo(videoDevice)
            cameraSetup = true
            statusMessage = "✅ Camera ready: \(videoDevice.localizedName)"
            print("✅ Camera setup successful with selected device!")
        } catch {
            statusMessage = "❌ Camera error: \(error.localizedDescription)"
            print("❌ Camera setup error with selected device:", error)
            cameraSetup = false
        }
    }
    
    func setupCamera() async {
        if mirrorProgramOutput {
            print("🪞 Program mirroring active: skipping setupCamera")
            statusMessage = "Program mirroring: camera disabled"
            cameraSetup = false
            return
        }
        statusMessage = "Setting up camera..."
        print("🎥 Starting automatic camera setup...")
        
        do {
            print("📝 Configuring mixer...")
            try await mixer.setFrameRate(30)
            try await mixer.setSessionPreset(AVCaptureSession.Preset.medium)
            
            print("🔍 Looking for camera devices...")
            #if os(macOS)
            let cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video)
            #else
            let cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            #endif
            
            guard let videoDevice = cameraDevice else {
                statusMessage = "❌ No camera device found"
                print("❌ No camera device found")
                return
            }
            
            print("✅ Found camera: \(videoDevice.localizedName)")
            statusMessage = "Found camera: \(videoDevice.localizedName)"
            print("📹 Attaching camera to mixer...")
            try await mixer.attachVideo(videoDevice)
            cameraSetup = true
            statusMessage = "✅ Camera ready"
            print("✅ Camera setup successful!")
        } catch {
            statusMessage = "❌ Camera error: \(error.localizedDescription)"
            print("❌ Camera setup error:", error)
        }
    }
    
    func attachPreview(_ view: MTHKView) async {
        print("🖼️ Attaching preview view...")
        previewView = view
        print("ℹ️ Skipping HK preview attach (publisher is Program-only)")
        statusMessage = "✅ Preview ready"
    }

    func bindToProgramManager(_ manager: PreviewProgramManager) {
        self.programManager = manager
        print("🔗 StreamingViewModel bound to PreviewProgramManager")
    }

    func bindToLayerManager(_ manager: LayerStackManager) {
        self.layerManager = manager
        print("🔗 StreamingViewModel bound to LayerStackManager")
    }

    func bindToProductionManager(_ manager: UnifiedProductionManager) {
        self.productionManager = manager
        print("🔗 StreamingViewModel bound to UnifiedProductionManager")
    }

    func start(rtmpURL: String, streamKey: String) async throws {
        print("🚀 Starting stream...")
        statusMessage = "Starting stream..."
        cameraSetup = false

        do {
            print("🌐 Connecting to: \(rtmpURL)")
            statusMessage = "Connecting to server..."
            try await connection.connect(rtmpURL)
            
            // Configure encoder (best-effort; API surface varies by HK version)
            await configureLowLatencyEncoder()

            print("📡 Publishing Program stream with key: \(streamKey)")
            statusMessage = "Publishing stream..."
            try await stream.publish(streamKey)
            
            isPublishing = true
            statusMessage = "✅ Live (Program output)"
            print("✅ Streaming started successfully (Program-only)")

            await configureAudioRouting()
            startProgramFramePump()
        } catch {
            statusMessage = "❌ Stream error: \(error.localizedDescription)"
            print("❌ Streaming start error:", error)
            isPublishing = false
            throw error
        }
    }

    private func configureLowLatencyEncoder() async {
        // Instead use HaishinKit's documented API if available, or skip configuration
        print("🛠 Configuring low latency encoder (safe mode)")
        
        // Some versions of HaishinKit allow direct property setting
        // This is a safer approach than KVO setValue
        do {
            // Safely attempt to configure frame rate if the mixer supports it
            try? await mixer.setFrameRate(Int(programTargetFPS))
        } catch {
            print("⚠️ Could not set mixer frame rate: \(error)")
        }
        
        print("✅ Low latency encoder configured (conservative)")
    }

    func stop() async {
        print("🛑 Stopping stream...")
        statusMessage = "Stopping stream..."

        stopProgramFramePump()
        stopProgramAudioPump()
        stopMicCapture()
        await detachMicrophoneIfNeeded()
        
        do {
            try await stream.close()
            try await connection.close()
            isPublishing = false
            statusMessage = "✅ Stream stopped"
            print("✅ Streaming stopped")
        } catch {
            statusMessage = "❌ Stop error: \(error.localizedDescription)"
            print("❌ Stop streaming error:", error)
            isPublishing = false
        }
    }

    func applyAudioSourceChange() {
        guard isPublishing else { return }
        Task { @MainActor in
            await configureAudioRouting()
        }
    }

    // MARK: - Audio Routing

    private func configureAudioRouting() async {
        switch selectedAudioSource {
        case .microphone:
            stopProgramAudioPump()
            await detachProgramAudioIfNeeded()
            stopMicCapture()
            await attachDefaultMicrophone()
        case .program:
            await detachMicrophoneIfNeeded()
            stopMicCapture()
            startProgramAudioPump()
        case .micAndProgram:
            stopProgramAudioPump()
            await detachMicrophoneIfNeeded()
            await detachProgramAudioIfNeeded()
            startMicCapture()
            startProgramAudioPump()
        case .none:
            stopProgramAudioPump()
            await detachMicrophoneIfNeeded()
            stopMicCapture()
            await detachProgramAudioIfNeeded()
        }
        print("🎚️ Audio routing set to: \(selectedAudioSource.displayName) (PiP=\(includePiPAudioInProgram))")
    }

    private func attachDefaultMicrophone() async {
        guard !micAttached else { return }
        #if os(macOS)
        let device = AVCaptureDevice.default(for: .audio)
        #else
        let device = AVCaptureDevice.default(for: .audio)
        #endif
        do {
            try await mixer.addOutput(stream)
            try await mixer.attachAudio(device)
            micAttached = true
            print("🎤 Microphone attached via MediaMixer")
        } catch {
            print("❌ Failed to attach microphone: \(error)")
            micAttached = false
        }
    }

    private func detachMicrophoneIfNeeded() async {
        guard micAttached else { return }
        await mixer.stopAllAudioCapture()
        micAttached = false
        print("🔇 Microphone detached from MediaMixer")
    }

    private func detachProgramAudioIfNeeded() async {
        // placeholder; program tap is owned by PreviewProgramManager
    }

    private func startProgramAudioPump() {
        guard audioSource == nil else { return }
        print("🔊 Starting Program audio pump (background)")
        let src = DispatchSource.makeTimerSource(queue: audioQueue)
        src.schedule(deadline: .now(), repeating: audioPollInterval, leeway: .milliseconds(1))
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task(priority: .userInteractive) {
                await self.pushCurrentProgramAudioFrameBackground()
            }
        }
        audioSource = src
        src.resume()
    }

    private func startMicCapture() {
        guard micEngine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let channels = Int(format.channelCount)
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }

            // Convert to interleaved stereo float32 in Data
            var interleaved = [Float32](repeating: 0, count: frames * 2)
            if channels >= 2, let ch0 = buffer.floatChannelData?[0], let ch1 = buffer.floatChannelData?[1] {
                for f in 0..<frames {
                    let so = f * 2
                    interleaved[so] = ch0[f]
                    interleaved[so + 1] = ch1[f]
                }
            } else if channels >= 1, let ch0 = buffer.floatChannelData?[0] {
                for f in 0..<frames {
                    let v = ch0[f]
                    let so = f * 2
                    interleaved[so] = v
                    interleaved[so + 1] = v
                }
            } else {
                return
            }

            self.micLock.lock()
            self.micLatestData.removeAll(keepingCapacity: true)
            self.micLatestData = interleaved.withUnsafeBufferPointer { Data(buffer: $0) }
            self.micLatestFrames = frames
            self.micSampleRate = format.sampleRate
            self.micLock.unlock()
        }

        do {
            try engine.start()
            micEngine = engine
            print("🎤 Mic engine started for Mic+Program mix")
        } catch {
            print("❌ Mic engine start error: \(error)")
            micEngine = nil
        }
    }

    private func stopMicCapture() {
        if let engine = micEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            micEngine = nil
            print("🔇 Mic engine stopped")
        }
        micLock.lock()
        micLatestData.removeAll()
        micLatestFrames = 0
        micLock.unlock()
    }

    private func fetchLatestMicInterleavedStereo() -> (UnsafePointer<Float32>, Int, Double)? {
        micLock.lock()
        defer { micLock.unlock() }
        guard micLatestFrames > 0, micLatestData.count >= micLatestFrames * 2 * MemoryLayout<Float32>.size else {
            return nil
        }
        let ptr = micLatestData.withUnsafeBytes { $0.bindMemory(to: Float32.self).baseAddress! }
        return (ptr, micLatestFrames, micSampleRate)
    }

    private func stopProgramAudioPump() {
        audioSource?.cancel()
        audioSource = nil
        print("🔊 Stopped Program audio pump")
    }

    private func pushCurrentProgramAudioFrameBackground() async {
        guard selectedAudioSource == .program || selectedAudioSource == .micAndProgram else { return }
        guard isPublishing else { return }

        // Target frames per pump at 48 kHz
        let outChannels = 2
        let framesOut = max(64, Int(targetSampleRate * audioPollInterval)) // ~200 at 240 Hz
        let samplesOut = framesOut * outChannels
        let outBuffer = UnsafeMutablePointer<Float32>.allocate(capacity: samplesOut)
        for i in 0..<samplesOut { outBuffer[i] = 0 }
        defer { outBuffer.deallocate() }

        struct Src {
            let data: [Float32]
            let frames: Int
            let layerId: UUID?
        }
        var sources: [Src] = []

        // Snapshot main-actor state
        let (programTap, programGain, includePiP, pipTaps, includeMic): (PlayerAudioTap?, Float, Bool, [(PlayerAudioTap, Float, Float, UUID)], Bool) = {
            var taps: [(PlayerAudioTap, Float, Float, UUID)] = []
            let pm = programManager
            let tap = pm?.programAudioTap
            let gain = (pm?.programMuted ?? false) ? 0.0 : Float(pm?.programVolume ?? 1.0)
            let include = includePiPAudioInProgram
            if include, let lm = layerManager {
                let soloIDs = Set(lm.layers.filter { $0.isEnabled && ($0.source.isVideo) && $0.audioSolo }.map { $0.id })
                for layer in lm.layers where layer.isEnabled {
                    guard case .media(let file) = layer.source, file.fileType == .video else { continue }
                    if !soloIDs.isEmpty && !soloIDs.contains(layer.id) { continue }
                    if let layerTap = lm.pipAudioTaps[layer.id] {
                        taps.append((layerTap, layer.audioMuted ? 0.0 : layer.audioGain, layer.audioPan, layer.id))
                    }
                }
            }
            let micIncluded = (selectedAudioSource == .micAndProgram)
            return (tap, gain, include, taps, micIncluded)
        }()

        // Program main audio (resample to framesOut @ 48 kHz)
        if let progTap = programTap, let (ptr, frames, ch, sr) = progTap.fetchLatestInterleavedBuffer() {
            let resampled = resampleInterleaved(ptr: ptr, frames: frames, srcChannels: ch, srcRate: sr, dstFrames: framesOut, dstRate: targetSampleRate)
            let g = programGain
            let scaled = resampled.map { $0 * g }
            sources.append(Src(data: scaled, frames: framesOut, layerId: nil))
        }

        // Include PiP taps
        if includePiP {
            for (tap, gain, pan, id) in pipTaps {
                if let (ptr, frames, ch, sr) = tap.fetchLatestInterleavedBuffer() {
                    var resampled = resampleInterleaved(ptr: ptr, frames: frames, srcChannels: ch, srcRate: sr, dstFrames: framesOut, dstRate: targetSampleRate)
                    applyPan(inoutStereo: &resampled, pan: pan)
                    let scaled = resampled.map { $0 * gain }
                    sources.append(Src(data: scaled, frames: framesOut, layerId: id))
                }
            }
        }

        // Include microphone if selected
        if includeMic, let (micPtr, micFrames, micSR) = fetchLatestMicInterleavedStereo() {
            let resampled = resampleInterleaved(ptr: micPtr, frames: micFrames, srcChannels: 2, srcRate: micSR, dstFrames: framesOut, dstRate: targetSampleRate)
            sources.append(Src(data: resampled, frames: framesOut, layerId: nil))
        }

        guard !sources.isEmpty else { return }

        // Mix down
        var perSourcePeak: [UUID: Float] = [:]
        var perSourceRMSAcc: [UUID: Double] = [:]
        var totalPeak: Float = 0
        var totalRMSAcc: Double = 0

        for src in sources {
            // Sum and meter per-source
            var srcPeak: Float = 0
            var srcRMSAcc: Double = 0
            for f in 0..<framesOut {
                let so = f * outChannels
                let sL = src.data[so]
                let sR = src.data[so + 1]
                srcPeak = max(srcPeak, max(abs(sL), abs(sR)))
                srcRMSAcc += Double((sL * sL + sR * sR) * 0.5)

                outBuffer[so] = outBuffer[so] + sL
                outBuffer[so + 1] = outBuffer[so + 1] + sR
            }
            if let lid = src.layerId {
                perSourcePeak[lid] = srcPeak
                perSourceRMSAcc[lid] = srcRMSAcc
            }
        }

        // Soft-clip limiter to avoid hard clipping
        for i in 0..<samplesOut {
            outBuffer[i] = softClipSample(outBuffer[i])
            totalPeak = max(totalPeak, abs(outBuffer[i]))
        }
        for f in 0..<framesOut {
            let so = f * outChannels
            let l = outBuffer[so]
            let r = outBuffer[so + 1]
            totalRMSAcc += Double((l * l + r * r) * 0.5)
        }

        // Update layer meters on main
        Task { @MainActor in
            if let lm = self.layerManager {
                let denom = Double(framesOut)
                for (lid, peak) in perSourcePeak {
                    let rmsAcc = perSourceRMSAcc[lid] ?? 0
                    let rms = sqrt(rmsAcc / max(denom, 1))
                    lm.updatePiPAudioMeter(for: lid, rms: Float(rms), peak: peak)
                }
            }
            // Program meters
            let totalRMS = sqrt(totalRMSAcc / max(Double(framesOut), 1))
            self.programAudioRMS = Float(totalRMS)
            self.programAudioPeak = totalPeak
        }

        // PTS and A/V sync offset using host clock
        let audioPTS = CMClockGetTime(hostClock)
        let audioDuration = CMTime(value: CMTimeValue(framesOut), timescale: CMTimeScale(Int32(targetSampleRate)))
        lastAudioPTS = audioPTS

        // Update AV sync readout
        Task { @MainActor in
            let diff = CMTimeSubtract(self.lastVideoPTS, self.lastAudioPTS)
            self.avSyncOffsetMs = CMTimeGetSeconds(diff) * 1000.0
        }

        if let mixed = makeAudioSampleBuffer(
            from: outBuffer,
            frames: framesOut,
            channels: outChannels,
            sampleRate: targetSampleRate,
            pts: audioPTS,
            duration: audioDuration
        ) {
            Task { @MainActor in
                await stream.appendAudio(mixed)
            }
        }
    }

    private func makeAudioSampleBuffer(from floatData: UnsafeMutablePointer<Float32>, frames: Int, channels: Int, sampleRate: Double, pts: CMTime, duration: CMTime) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var fmtDesc: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fmtDesc) == noErr,
              let formatDesc = fmtDesc else { return nil }

        let totalBytes = frames * channels * MemoryLayout<Float32>.size
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: totalBytes,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: totalBytes,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == noErr, let bb = blockBuffer else { return nil }

        let copyStatus = CMBlockBufferReplaceDataBytes(
            with: UnsafeRawPointer(floatData),
            blockBuffer: bb,
            offsetIntoDestination: 0,
            dataLength: totalBytes
        )
        guard copyStatus == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBufferOut: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: frames,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBufferOut
        ) == noErr else { return nil }

        return sampleBufferOut
    }

    // MARK: - Program frame pump (video)

    private func startProgramFramePump() {
        guard frameSource == nil else { return }
        print("🖼️ Starting Program frame pump (background) at \(programTargetFPS) FPS")
        let src = DispatchSource.makeTimerSource(queue: videoQueue)
        let interval = DispatchTimeInterval.nanoseconds(Int(1_000_000_000.0 / programTargetFPS))
        src.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.isRenderingFrame { return }
            self.isRenderingFrame = true
            Task(priority: .userInteractive) {
                await self.renderAndPushProgramFrame()
            }
        }
        frameSource = src
        src.resume()
    }

    private func stopProgramFramePump() {
        frameSource?.cancel()
        frameSource = nil
        isRenderingFrame = false
        print("🖼️ Stopped Program frame pump")
    }

    private func ensurePixelBufferPool(width: Int, height: Int) {
        if programPixelBufferPool == nil {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
            programPixelBufferPool = pool
        }
    }

    private func pixelBuffer(from width: Int, height: Int, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        if status != kCVReturnSuccess { return nil }
        return pb
    }

    private struct OverlaySnapshot {
        let image: CGImage
        let centerNorm: CGPoint
        let sizeNorm: CGSize
        let rotationDegrees: Float
        let opacity: Float
    }

    private func snapshotOverlays(base: CGImage) -> [OverlaySnapshot] {
        guard let layerManager else { return [] }
        let layers = layerManager.layers
            .filter { $0.isEnabled }
            .sorted { $0.zIndex < $1.zIndex }

        var snapshots: [OverlaySnapshot] = []
        for model in layers {
            var overlayCG: CGImage?
            switch model.source {
            case .camera(let feedId):
                if let feed = productionManager?.cameraFeedManager.activeFeeds.first(where: { $0.id == feedId }) {
                    overlayCG = feed.previewImage
                }
            case .media(let file):
                switch file.fileType {
                case .image:
                    overlayCG = loadCGImage(from: file.url)
                case .video:
                    overlayCG = nil
                case .audio:
                    overlayCG = nil
                }
            case .title(let overlay):
                #if os(macOS)
                let baseSize = CGSize(width: base.width, height: base.height)
                let targetSize = CGSize(width: baseSize.width * model.sizeNorm.width,
                                        height: baseSize.height * model.sizeNorm.height)
                overlayCG = makeTitleCGImage(
                    text: overlay.text,
                    fontSize: overlay.fontSize,
                    color: overlay.color,
                    alignment: overlay.alignment,
                    size: targetSize
                )
                #else
                overlayCG = nil
                #endif
            }
            if let image = overlayCG {
                snapshots.append(OverlaySnapshot(image: image, centerNorm: model.centerNorm, sizeNorm: model.sizeNorm, rotationDegrees: model.rotationDegrees, opacity: model.opacity))
            }
        }
        return snapshots
    }

    private func renderAndPushProgramFrame() async {
        defer { isRenderingFrame = false }
        
        guard isPublishing else { return }

        guard let base = makeBaseProgramCGImage() else { return }

        ensurePixelBufferPool(width: base.width, height: base.height)
        guard let pixelPool = programPixelBufferPool else { return }

        let overlays = snapshotOverlays(base: base)
        let outputCI = compositePiPLayersCI(base: base, overlays: overlays)

        guard let pb = pixelBuffer(from: base.width, height: base.height, pool: pixelPool) else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        programCIContext.render(outputCI, to: pb)
        CVPixelBufferUnlockBaseAddress(pb, [])

        if programVideoFormat == nil {
            var fdesc: CMVideoFormatDescription?
            if CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescriptionOut: &fdesc) == noErr {
                programVideoFormat = fdesc
            }
        }

        let ptsNow = CMClockGetTime(hostClock)
        lastVideoPTS = ptsNow
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(Int32(programTargetFPS)))
        var timing = CMSampleTimingInfo(duration: frameDuration, presentationTimeStamp: ptsNow, decodeTimeStamp: .invalid)

        // Update AV sync readout (video vs audio)
        Task { @MainActor in
            let diff = CMTimeSubtract(self.lastVideoPTS, self.lastAudioPTS)
            self.avSyncOffsetMs = CMTimeGetSeconds(diff) * 1000.0
        }

        var sb: CMSampleBuffer?
        if let fmt = programVideoFormat,
           CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescription: fmt, sampleTiming: &timing, sampleBufferOut: &sb) == noErr,
           let sampleBuffer = sb {
            await stream.appendVideo(sampleBuffer)
        }
    }

    private func compositePiPLayersCI(base: CGImage, overlays: [OverlaySnapshot]) -> CIImage {
        let baseW = base.width
        let baseH = base.height
        var output = CIImage(cgImage: base)

        for o in overlays {
            var img = CIImage(cgImage: o.image)
            let srcW = CGFloat(o.image.width)
            let srcH = CGFloat(o.image.height)
            if srcW <= 0 || srcH <= 0 { continue }

            let targetW = CGFloat(baseW) * o.sizeNorm.width
            let targetH = CGFloat(baseH) * o.sizeNorm.height
            if targetW <= 0 || targetH <= 0 { continue }

            let scale = max(targetW / srcW, targetH / srcH)
            let drawW = srcW * scale
            let drawH = srcH * scale

            let centerX = CGFloat(baseW) * o.centerNorm.x
            let centerY = CGFloat(baseH) * (1.0 - o.centerNorm.y)

            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: centerX, y: centerY)
            if abs(o.rotationDegrees) > 0.001 {
                let radians = CGFloat(o.rotationDegrees) * .pi / 180.0
                transform = transform.rotated(by: radians)
            }
            transform = transform.translatedBy(x: -drawW/2, y: -drawH/2)
            transform = transform.scaledBy(x: scale, y: scale)

            img = img.transformed(by: transform)
            if o.opacity < 0.999 {
                img = img.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(o.opacity)),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                ])
            }
            output = img.composited(over: output)
        }

        return output
    }

    private func makeBaseProgramCGImage() -> CGImage? {
        guard let pm = programManager else { return nil }

        if let tex = pm.programCurrentTexture, let cg = cgImage(from: tex) {
            return cg
        }

        if let cg = pm.programImage {
            return cg
        }

        if case .camera(let feed) = pm.programSource, let pb = feed.currentFrame {
            return cgImage(from: pb)
        }

        return nil
    }

    private func cgImage(from texture: MTLTexture) -> CGImage? {
        guard let ci = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) else { return nil }
        let flipped = ci.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -ci.extent.height))
        return programCIContext.createCGImage(flipped, from: flipped.extent)
    }

    private func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        return programCIContext.createCGImage(ci, from: ci.extent)
    }

    private func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let width = image.width
        let height = image.height

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb else { return nil }

        let ciImage = CIImage(cgImage: image)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        programCIContext.render(ciImage, to: pixelBuffer)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [
            kCGImageSourceShouldCache: true as CFBoolean
        ] as CFDictionary)
    }

    #if os(macOS)
    private func makeTitleCGImage(text: String, fontSize: CGFloat, color: RGBAColor, alignment: TextAlignment, size: CGSize) -> CGImage? {
        let width = max(Int(size.width.rounded()), 2)
        let height = max(Int(size.height.rounded()), 2)
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        // Transparent background
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        let nsctx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsctx

        let paragraph = NSMutableParagraphStyle()
        switch alignment {
        case .leading: paragraph.alignment = .left
        case .trailing: paragraph.alignment = .right
        default: paragraph.alignment = .center
        }

        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let nsColor = NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor,
            .paragraphStyle: paragraph
        ]

        let inset: CGFloat = max(4, fontSize * 0.15)
        let drawRect = CGRect(x: inset, y: inset, width: CGFloat(width) - inset*2, height: CGFloat(height) - inset*2)
        let attributed = NSAttributedString(string: text, attributes: attrs)
        attributed.draw(in: drawRect)

        NSGraphicsContext.restoreGraphicsState()

        return ctx.makeImage()
    }
    #endif

    func resetAndSetupWithDevice(_ videoDevice: AVCaptureDevice) async {
        print("🔄 Resetting StreamingViewModel to use device: \(videoDevice.localizedName)")
        if isPublishing {
            await stop()
        }
        await mixer.setFrameRate(30)
        await mixer.setSessionPreset(AVCaptureSession.Preset.medium)
        await setupCameraWithDevice(videoDevice)
    }


    private func softClipSample(_ x: Float) -> Float {
        let k: Float = 2.5
        return tanhf(k * x) / tanhf(k)
    }

    private func applyPan(inoutStereo data: inout [Float32], pan: Float) {
        let panClamped = max(-1.0, min(1.0, pan))
        let angle = (Double(panClamped) + 1.0) * (Double.pi / 4.0)
        let panL = Float(cos(angle))
        let panR = Float(sin(angle))
        let frames = data.count / 2
        for f in 0..<frames {
            let i = f * 2
            data[i] *= panL
            data[i + 1] *= panR
        }
    }

    private func resampleInterleaved(ptr: UnsafePointer<Float32>, frames: Int, srcChannels: Int, srcRate: Double, dstFrames: Int, dstRate: Double) -> [Float32] {
        // Output stereo interleaved
        var out = [Float32](repeating: 0, count: dstFrames * 2)
        if frames <= 1 {
            return out
        }
        let step = srcRate / dstRate
        var pos: Double = 0
        for i in 0..<dstFrames {
            let s0 = Int(pos)
            let s1 = min(s0 + 1, frames - 1)
            let frac = Float(pos - Double(s0))
            if srcChannels >= 2 {
                let i0L = s0 * srcChannels
                let i0R = i0L + 1
                let i1L = s1 * srcChannels
                let i1R = i1L + 1
                let l0 = ptr[i0L]
                let r0 = ptr[i0R]
                let l1 = ptr[i1L]
                let r1 = ptr[i1R]
                let l = l0 + (l1 - l0) * frac
                let r = r0 + (r1 - r0) * frac
                let o = i * 2
                out[o] = l
                out[o + 1] = r
            } else {
                let i0 = s0
                let i1 = s1
                let v0 = ptr[i0]
                let v1 = ptr[i1]
                let v = v0 + (v1 - v0) * frac
                let o = i * 2
                out[o] = v
                out[o + 1] = v
            }
            pos += step
            if pos > Double(frames - 1) { pos = Double(frames - 1) }
        }
        return out
    }
}

enum StreamingError: Error, LocalizedError {
    case noCamera
    case noMicrophone
    case connectionFailed
    
    var errorDescription: String? {
        switch self {
        case .noCamera:
            return "No camera device found"
        case .noMicrophone:
            return "No microphone device found"
        case .connectionFailed:
            return "Failed to connect to streaming server"
        }
    }
}

private extension LayerSource {
    var isVideo: Bool {
        if case .media(let file) = self {
            return file.fileType == .video
        }
        return false
    }
}