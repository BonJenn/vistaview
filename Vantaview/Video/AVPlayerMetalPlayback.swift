import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import Metal
import QuartzCore
import os
#if os(macOS)
import AppKit
#endif

final class AVPlayerMetalPlayback: NSObject, AVPlayerItemOutputPullDelegate, DisplayLinkClient {
    private static let log = OSLog(subsystem: "com.vantaview", category: "AVPlayerMetalPlayback")

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var converter: NV12ToBGRAConverter?
    private var currentSize: (w: Int, h: Int) = (0, 0)
    private let inFlight = DispatchSemaphore(value: 3)
    
    private var isActive = false

    private let player: AVPlayer
    private let itemOutput: AVPlayerItemVideoOutput
    
    private(set) var latestTexture: MTLTexture?
    private let captureScope: MTLCaptureScope?
    private var effectRunner: EffectRunner?
    private let heapPool: TextureHeapPool
    
    // Triple-buffer ring
    private var outputRing: [MTLTexture] = []
    private var ringIndex: Int = 0
    
    private var frameIndex: UInt64 = 0
    private var loggedPixelFormatOnce = false

    // FPS + Watchdog
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()
    private var fpsAccumulator: Double = 0
    private var fpsCount: Int = 0
    var onFPSUpdate: ((Double) -> Void)?
    var targetFPS: Double = 60
    private var lowFPSConsecutive = 0
    var onWatchdog: (() -> Void)?
    private var lastWatchdogFire: CFTimeInterval = 0

    // HDR tone map toggle (auto-enabled if PQ/HLG detected)
    var toneMapEnabled: Bool = false
    var swapUV: Bool = false

    var onSizeChange: ((Int, Int) -> Void)?

    // Output kick + stall handling
    private let outputQueue = DispatchQueue(label: "vantaview.avplayeritemvideooutput.queue", qos: .userInitiated)
    private var consecutiveMisses = 0
    private var droppedDueToBackpressure = 0

    // Shared display link subscription
    private var displaySubID: UUID?
    
    // Frame gating
    private var contentFPS: Double = 30
    private var lastGatedHostSeconds: Double = 0
    
    init?(player: AVPlayer, itemOutput: AVPlayerItemVideoOutput, device: MTLDevice) {
        self.player = player
        self.itemOutput = itemOutput
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        self.converter = NV12ToBGRAConverter(device: device)
        self.heapPool = TextureHeapPool(device: device)
        
        let capMgr = MTLCaptureManager.shared()
        let scope = capMgr.makeCaptureScope(commandQueue: queue)
        scope.label = "PlaybackCaptureScope"
        self.captureScope = scope
        if capMgr.defaultCaptureScope === scope { capMgr.defaultCaptureScope = nil }
        
        super.init()
        
        self.itemOutput.setDelegate(self, queue: outputQueue)
        self.contentFPS = estimateContentFPS()
    }
    
    deinit {
        stop()
        itemOutput.setDelegate(nil, queue: nil)
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }
    
    func setEffectRunner(_ runner: EffectRunner?) {
        self.effectRunner = runner
    }

    func enableAutoCaptureOnWatchdog(_ enabled: Bool) { }
    func captureNextFrame() { }

    func start() {
        isActive = true
        lastFrameTime = CACurrentMediaTime()
        fpsAccumulator = 0
        fpsCount = 0
        lowFPSConsecutive = 0
        consecutiveMisses = 0
        droppedDueToBackpressure = 0
        contentFPS = estimateContentFPS()

        itemOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
        
        DisplayLinkHub.shared.ensureRunning()
        Task { [weak self] in
            guard let self else { return }
            self.displaySubID = await DisplayLinkActor.shared.register(self)
        }
        
        os_signpost(.event, log: Self.log, name: "PlaybackStart")
    }
    
    func stop() {
        isActive = false
        latestTexture = nil
        
        if let id = displaySubID {
            Task {
                await DisplayLinkActor.shared.unregister(id)
            }
            displaySubID = nil
        }
        
        itemOutput.setDelegate(nil, queue: nil)
        
        os_signpost(.event, log: Self.log, name: "PlaybackStop", "dropped=%d misses=%d", droppedDueToBackpressure, consecutiveMisses)
    }

    // MARK: - DisplayLinkClient

    func displayTick(hostTime: UInt64) {
        Task { [weak self] in
            await self?.pullFrameAsync(hostTime: hostTime)
        }
    }

    // MARK: - AVPlayerItemOutputPullDelegate

    func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        consecutiveMisses = 0
    }
    
    func outputSequenceWasFlushed(_ output: AVPlayerItemOutput) {
        consecutiveMisses = 0
        itemOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
    }

    // MARK: - Frame Pull (async with registry + gating)

    private func pullFrameAsync(hostTime: UInt64) async {
        autoreleasepool {
            // Intentionally empty to bound ARC scope
        }
        guard let cache = textureCache, let converter = converter, isActive else { return }
        
        let hostSeconds = CMTimeGetSeconds(CMClockMakeHostTimeFromSystemUnits(hostTime))
        let desiredFPS = min(max(contentFPS, 1), targetFPS)
        let minInterval = 1.0 / desiredFPS
        if hostSeconds - lastGatedHostSeconds < minInterval {
            return
        }
        lastGatedHostSeconds = hostSeconds
        
        // Dedup across panes: ensure only one conversion per source per tick
        let key = sourceKey()
        let (produce, shared) = await MediaFrameRegistry.shared.acquireFrameSlot(sourceKey: key, hostTime: hostTime)
        if let shared {
            // Use shared converted/FX texture
            self.latestTexture = shared
            postPresentBookkeeping()
            return
        } else if !produce {
            // Someone else is producing this frame; skip work this tick
            return
        }
        
        // Map host time to item time and check for new frames
        var itemTime = itemOutput.itemTime(forHostTime: hostSeconds)
        if !itemTime.isValid {
            itemTime = player.currentTime()
        }
        var displayTime = CMTime.invalid
        guard itemOutput.hasNewPixelBuffer(forItemTime: itemTime),
              let pb = itemOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime) else {
            await MediaFrameRegistry.shared.cancelProduction(sourceKey: key, hostTime: hostTime)
            consecutiveMisses &+= 1
            if consecutiveMisses % 30 == 0 {
                itemOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
            }
            return
        }
        consecutiveMisses = 0
        
        let fmt = CVPixelBufferGetPixelFormatType(pb)
        if !loggedPixelFormatOnce {
            loggedPixelFormatOnce = true
            let fmtStr = String(format: "0x%08X", fmt)
            print("AVPlayerMetalPlayback: First pixelBuffer format = \(fmtStr) (NV12 full=0x0000000F, video=0x0000002F)")
        }
        
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        if currentSize.w != w || currentSize.h != h || outputRing.isEmpty {
            currentSize = (w, h)
            outputRing.removeAll(keepingCapacity: true)
            heapPool.ensureHeap(width: w, height: h, pixelFormat: .bgra8Unorm, usage: [.shaderRead, .shaderWrite])
            for _ in 0..<3 {
                if let tex = converter.makeOutputTexture(width: w, height: h, heap: heapPool.heap) {
                    tex.label = "Playback BGRA Output \(w)x\(h)"
                    outputRing.append(tex)
                }
            }
            ringIndex = 0
            onSizeChange?(w, h)
        }
        guard !outputRing.isEmpty else {
            await MediaFrameRegistry.shared.cancelProduction(sourceKey: key, hostTime: hostTime)
            return
        }
        let outBGRA = outputRing[ringIndex]
        ringIndex = (ringIndex + 1) % outputRing.count
        
        // Back-pressure: if GPU queue is saturated, drop this frame instead of blocking CPU
        if inFlight.wait(timeout: .now()) == .timedOut {
            droppedDueToBackpressure &+= 1
            await MediaFrameRegistry.shared.cancelProduction(sourceKey: key, hostTime: hostTime)
            return
        }
        
        guard let cb = commandQueue.makeCommandBuffer() else {
            inFlight.signal()
            await MediaFrameRegistry.shared.cancelProduction(sourceKey: key, hostTime: hostTime)
            return
        }
        frameIndex &+= 1
        cb.label = "Playback CB #\(frameIndex)"
        cb.addCompletedHandler { [weak self] _ in
            self?.inFlight.signal()
        }
        
        let is10BitNV12 = (fmt == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange) ||
                          (fmt == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        let yFmt: MTLPixelFormat = is10BitNV12 ? .r16Unorm : .r8Unorm
        let uvFmt: MTLPixelFormat = is10BitNV12 ? .rg16Unorm : .rg8Unorm
        
        guard let yTex = makeTexture(from: pb, plane: 0, pixelFormat: yFmt, cache: cache),
              let uvTex = makeTexture(from: pb, plane: 1, pixelFormat: uvFmt, cache: cache) else {
            cb.commit()
            await MediaFrameRegistry.shared.cancelProduction(sourceKey: key, hostTime: hostTime)
            return
        }
        
        let params = makeParams(for: pb, pixelFormat: fmt)
        converter.encode(commandBuffer: cb, luma: yTex, chroma: uvTex, output: outBGRA, params: params)
        
        let finalTex = effectRunner?.encodeEffects(input: outBGRA, commandBuffer: cb) ?? outBGRA
        
        cb.addCompletedHandler { [weak self] _ in
            guard let self = self else { return }
            self.latestTexture = finalTex
            Task {
                await MediaFrameRegistry.shared.publish(sourceKey: key, hostTime: hostTime, texture: finalTex)
            }
            self.postPresentBookkeeping()
        }
        
        cb.commit()
    }
    
    private func postPresentBookkeeping() {
        let now = CACurrentMediaTime()
        let dt = now - self.lastFrameTime
        self.lastFrameTime = now
        if dt > 0 {
            let fps = 1.0 / dt
            self.fpsAccumulator += fps
            self.fpsCount += 1
            if self.fpsCount >= 10 {
                let avg = self.fpsAccumulator / Double(self.fpsCount)
                self.fpsAccumulator = 0
                self.fpsCount = 0
                self.onFPSUpdate?(avg)
                if avg + 0.5 < self.targetFPS {
                    self.lowFPSConsecutive += 1
                } else {
                    self.lowFPSConsecutive = 0
                }
                let tNow = CACurrentMediaTime()
                if self.lowFPSConsecutive >= 6 && (tNow - self.lastWatchdogFire) > 60 {
                    self.lastWatchdogFire = tNow
                    self.onWatchdog?()
                }
            }
        }
        
        if self.frameIndex % 120 == 0, let cache = self.textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }
    
    private func makeTexture(from pixelBuffer: CVPixelBuffer, plane: Int, pixelFormat: MTLPixelFormat, cache: CVMetalTextureCache) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        var cvTextureOut: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            plane,
            &cvTextureOut
        )
        guard status == kCVReturnSuccess, let cvTex = cvTextureOut, let tex = CVMetalTextureGetTexture(cvTex) else {
            return nil
        }
        return tex
    }

    private func makeParams(for pixelBuffer: CVPixelBuffer, pixelFormat: OSType) -> ConvertParams {
        var m = simd_float3x3(
            simd_float3(1.0,  1.0,    1.0),
            simd_float3(0.0, -0.1873, 1.8556),
            simd_float3(1.5748, -0.4681, 0.0)
        )

        if let matrix = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, nil)?.takeUnretainedValue() as? String {
            if matrix == kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String {
                m = simd_float3x3(
                    simd_float3(1.0,  1.0,    1.0),
                    simd_float3(0.0, -0.344136, 1.7720),
                    simd_float3(1.4020, -0.714136, 0.0)
                )
            } else if matrix == kCVImageBufferYCbCrMatrix_ITU_R_2020 as String {
                m = simd_float3x3(
                    simd_float3(1.0,  1.0,    1.0),
                    simd_float3(0.0, -0.16455, 1.8814),
                    simd_float3(1.4746, -0.57135, 0.0)
                )
            }
        }

        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
            return ConvertParams(
                yuv2rgb: m,
                yOffset: 16.0/255.0,
                uvOffset: 128.0/255.0,
                yScale: 255.0/219.0,
                uvScale: 255.0/224.0,
                toneMapEnabled: toneMapEnabled ? 1.0 : 0.0,
                swapUV: swapUV ? 1.0 : 0.0
            )
        } else {
            return ConvertParams(
                yuv2rgb: m,
                yOffset: 0.0,
                uvOffset: 0.5,
                yScale: 1.0,
                uvScale: 1.0,
                toneMapEnabled: toneMapEnabled ? 1.0 : 0.0,
                swapUV: swapUV ? 1.0 : 0.0
            )
        }
    }
    
    private func estimateContentFPS() -> Double {
        guard let item = player.currentItem else { return 30 }
        if let track = item.asset.tracks(withMediaType: .video).first {
            let fps = Double(track.nominalFrameRate)
            if fps > 0 { return fps }
        }
        return 30
    }
    
    private func sourceKey() -> String {
        if let urlAsset = player.currentItem?.asset as? AVURLAsset {
            return "url:\(urlAsset.url.absoluteString)"
        } else if let item = player.currentItem {
            return "item:\(ObjectIdentifier(item).hashValue)"
        } else {
            return "player:\(ObjectIdentifier(player).hashValue)"
        }
    }
}