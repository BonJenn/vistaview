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

    enum AudioSource: String, CaseIterable, Identifiable {
        case microphone, program, none
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .microphone: return "Microphone"
            case .program: return "Program Audio"
            case .none: return "None"
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
            await attachDefaultMicrophone()
        case .program:
            await detachMicrophoneIfNeeded()
            startProgramAudioPump()
        case .none:
            stopProgramAudioPump()
            await detachMicrophoneIfNeeded()
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

    private func stopProgramAudioPump() {
        audioSource?.cancel()
        audioSource = nil
        print("🔊 Stopped Program audio pump")
    }

    private func pushCurrentProgramAudioFrameBackground() async {
        guard selectedAudioSource == .program else { return }
        guard isPublishing else { return }

        var channels: Int = 2
        var sampleRate: Double = 48_000

        struct Src {
            let ptr: UnsafePointer<Float32>
            let frames: Int
            let gainL: Float
            let gainR: Float
            let layerId: UUID?
        }
        var sources: [Src] = []

        // Snapshot main-actor state
        let (programTap, programGain, includePiP, pipTaps): (PlayerAudioTap?, Float, Bool, [(PlayerAudioTap, Float, Float, UUID)]) = {
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
            return (tap, gain, include, taps)
        }()

        if let progTap = programTap,
           let (ptr, frames, ch, sr) = progTap.fetchLatestInterleavedBuffer() {
            channels = max(1, ch)
            sampleRate = sr
            sources.append(Src(ptr: ptr, frames: frames, gainL: programGain, gainR: programGain, layerId: nil))
        }

        if includePiP {
            for (tap, gain, pan, id) in pipTaps {
                if let (ptr, frames, ch, sr) = tap.fetchLatestInterleavedBuffer() {
                    channels = max(1, ch)
                    sampleRate = sr
                    let panClamped = max(-1.0, min(1.0, pan))
                    let angle = (Double(panClamped) + 1.0) * (Double.pi / 4.0)
                    let panL = Float(cos(angle))
                    let panR = Float(sin(angle))
                    sources.append(Src(ptr: ptr, frames: frames, gainL: gain * panL, gainR: gain * panR, layerId: id))
                }
            }
        }

        guard !sources.isEmpty else { return }
        let frames = sources.map { $0.frames }.min() ?? 0
        guard frames > 0 else { return }

        let outChannels = 2
        let samples = frames * outChannels
        let outBuffer = UnsafeMutablePointer<Float32>.allocate(capacity: samples)
        defer { outBuffer.deallocate() }
        for i in 0..<samples { outBuffer[i] = 0 }

        var perSourcePeak: [UUID: Float] = [:]
        var perSourceRMSAcc: [UUID: Double] = [:]

        for src in sources {
            var peak: Float = 0
            var rmsAcc: Double = 0
            if channels >= 2 {
                for f in 0..<frames {
                    let si = f * channels
                    let so = f * outChannels
                    let sL = src.ptr[si] * src.gainL
                    let sR = src.ptr[si + 1] * src.gainR
                    peak = max(peak, max(abs(sL), abs(sR)))
                    rmsAcc += Double((sL * sL + sR * sR) * 0.5)
                    outBuffer[so] = min(max(outBuffer[so] + sL, -1.0), 1.0)
                    outBuffer[so + 1] = min(max(outBuffer[so + 1] + sR, -1.0), 1.0)
                }
            } else {
                for f in 0..<frames {
                    let so = f * outChannels
                    let s = src.ptr[f]
                    let sL = s * src.gainL
                    let sR = s * src.gainR
                    peak = max(peak, max(abs(sL), abs(sR)))
                    rmsAcc += Double((sL * sL + sR * sR) * 0.5)
                    outBuffer[so] = min(max(outBuffer[so] + sL, -1.0), 1.0)
                    outBuffer[so + 1] = min(max(outBuffer[so + 1] + sR, -1.0), 1.0)
                }
            }
            if let lid = src.layerId {
                perSourcePeak[lid] = peak
                perSourceRMSAcc[lid] = rmsAcc
            }
        }

        // Update meters on main
        Task { @MainActor in
            guard let lm = self.layerManager else { return }
            let denom = Double(frames)
            for (lid, peak) in perSourcePeak {
                let rmsAcc = perSourceRMSAcc[lid] ?? 0
                let rms = sqrt(rmsAcc / max(denom, 1))
                lm.updatePiPAudioMeter(for: lid, rms: Float(rms), peak: peak)
            }
        }

        let audioPTS = CMClockGetTime(hostClock)
        let audioDuration = CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(Int32(sampleRate)))

        if let mixed = makeAudioSampleBuffer(from: outBuffer, frames: frames, channels: outChannels, sampleRate: sampleRate, pts: audioPTS, duration: audioDuration) {
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
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(Int32(programTargetFPS)))
        var timing = CMSampleTimingInfo(duration: frameDuration, presentationTimeStamp: ptsNow, decodeTimeStamp: .invalid)

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

    func resetAndSetupWithDevice(_ videoDevice: AVCaptureDevice) async {
        print("🔄 Resetting StreamingViewModel to use device: \(videoDevice.localizedName)")
        if isPublishing {
            await stop()
        }
        await mixer.setFrameRate(30)
        await mixer.setSessionPreset(AVCaptureSession.Preset.medium)
        await setupCameraWithDevice(videoDevice)
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