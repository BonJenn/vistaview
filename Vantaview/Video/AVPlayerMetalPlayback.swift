import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import Metal
import QuartzCore
#if os(macOS)
import AppKit
#endif

final class AVPlayerMetalPlayback: NSObject, AVPlayerItemOutputPullDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var converter: NV12ToBGRAConverter?
    private var outputTexture: MTLTexture?
    private var currentSize: (w: Int, h: Int) = (0, 0)
    private let inFlight = DispatchSemaphore(value: 3)
    
    private var displayLink: CVDisplayLink?
    private let lock = NSLock()
    private var lastHostTime: UInt64 = 0
    
    private final class CallbackBox {
        weak var owner: AVPlayerMetalPlayback?
        init(owner: AVPlayerMetalPlayback) { self.owner = owner }
    }
    private var callbackBox: CallbackBox?
    
    private var isActive = false

    private let player: AVPlayer
    private let itemOutput: AVPlayerItemVideoOutput
    
    private(set) var latestTexture: MTLTexture?
    private let captureScope: MTLCaptureScope?
    private var effectRunner: EffectRunner?
    private let heapPool: TextureHeapPool
    
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

    // Fallback timer if display link fails (headless/offscreen)
    private var fallbackTimer: DispatchSourceTimer?

    init?(player: AVPlayer, itemOutput: AVPlayerItemVideoOutput, device: MTLDevice) {
        self.player = player
        self.itemOutput = itemOutput
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        self.converter = NV12ToBGRAConverter(device: device)
        self.heapPool = TextureHeapPool(device: device)
        
        // Optional capture scope
        let capMgr = MTLCaptureManager.shared()
        let scope = capMgr.makeCaptureScope(commandQueue: queue)
        scope.label = "PlaybackCaptureScope"
        self.captureScope = scope
        if capMgr.defaultCaptureScope === scope { capMgr.defaultCaptureScope = nil }
        
        super.init()
        
        // Register output delegate so AVF will actively notify on data changes
        self.itemOutput.setDelegate(self, queue: outputQueue)
        
        // Display link callback
        self.callbackBox = CallbackBox(owner: self)
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else { return nil }
        self.displayLink = link
        let userPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(callbackBox!).toOpaque())
        CVDisplayLinkSetOutputCallback(link, { (_, _, outputTime, _, _, user) -> CVReturn in
            guard let user else { return kCVReturnSuccess }
            let box = Unmanaged<CallbackBox>.fromOpaque(user).takeUnretainedValue()
            guard let owner = box.owner else { return kCVReturnSuccess }
            owner.lastHostTime = outputTime.pointee.hostTime
            owner.pullFrame()
            return kCVReturnSuccess
        }, userPtr)
    }
    
    deinit {
        stop()
        if let link = displayLink {
            CVDisplayLinkSetOutputCallback(link, { _,_,_,_,_,_ in kCVReturnSuccess }, nil)
            CVDisplayLinkStop(link)
        }
        itemOutput.setDelegate(nil, queue: nil)
        callbackBox?.owner = nil
        displayLink = nil
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
        fallbackTimer?.cancel()
        fallbackTimer = nil
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

        // Prime output
        itemOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
        
        // Start display link or fallback timer
        if let link = displayLink {
            if !CVDisplayLinkIsRunning(link) {
                CVDisplayLinkStart(link)
            }
        } else {
            startFallbackTimer()
        }
    }
    
    func stop() {
        isActive = false
        latestTexture = nil
        
        if let link = displayLink {
            CVDisplayLinkSetOutputCallback(link, { _,_,_,_,_,_ in kCVReturnSuccess }, nil)
            if CVDisplayLinkIsRunning(link) {
                CVDisplayLinkStop(link)
            }
        }
        fallbackTimer?.cancel()
        fallbackTimer = nil
        
        // Break delegate link to avoid retaining chains
        itemOutput.setDelegate(nil, queue: nil)
    }

    // MARK: - AVPlayerItemOutputPullDelegate

    func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        consecutiveMisses = 0
    }
    
    func outputSequenceWasFlushed(_ output: AVPlayerItemOutput) {
        consecutiveMisses = 0
        itemOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
    }

    // MARK: - Fallback timer

    private func startFallbackTimer() {
        let t = DispatchSource.makeTimerSource(queue: outputQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(Int(1000.0 / max(targetFPS, 1))))
        t.setEventHandler { [weak self] in
            self?.pullFrame()
        }
        t.resume()
        fallbackTimer = t
    }

    // MARK: - Frame Pull

    private func pullFrame() {
        autoreleasepool {
            guard let cache = textureCache, let converter = converter, isActive else { return }
            
            // Get a host time and map to item time
            let hostUnits = (lastHostTime != 0) ? lastHostTime : CVGetCurrentHostTime()
            let hostCMTime = CMClockMakeHostTimeFromSystemUnits(hostUnits)
            let hostSeconds = CMTimeGetSeconds(hostCMTime)
            
            var itemTime = itemOutput.itemTime(forHostTime: hostSeconds)
            if !itemTime.isValid {
                // Fallback if output isn't ready to map host time yet
                itemTime = player.currentTime()
            }
            
            // Pull only when a new buffer is advertised
            var displayTime = CMTime.invalid
            guard itemOutput.hasNewPixelBuffer(forItemTime: itemTime),
                  let pb = itemOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime) else {
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
            if currentSize.w != w || currentSize.h != h || outputTexture == nil {
                currentSize = (w, h)
                heapPool.ensureHeap(width: w, height: h, pixelFormat: .bgra8Unorm, usage: [.shaderRead, .shaderWrite])
                outputTexture = converter.makeOutputTexture(width: w, height: h, heap: heapPool.heap)
                outputTexture?.label = "Playback BGRA Output \(w)x\(h)"
                onSizeChange?(w, h)
            }
            guard let outBGRA = outputTexture else { return }
            
            inFlight.wait()
            guard let cb = commandQueue.makeCommandBuffer() else {
                inFlight.signal()
                return
            }
            frameIndex &+= 1
            cb.label = "Playback CB #\(frameIndex)"
            cb.addCompletedHandler { [weak self] _ in
                self?.inFlight.signal()
            }

            cb.pushDebugGroup("PlaybackFrame")
            
            // Plane textures: select proper formats for 8/10-bit NV12
            let is10BitNV12 = (fmt == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange) ||
                              (fmt == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
            let yFmt: MTLPixelFormat = is10BitNV12 ? .r16Unorm : .r8Unorm
            let uvFmt: MTLPixelFormat = is10BitNV12 ? .rg16Unorm : .rg8Unorm

            guard let yTex = makeTexture(from: pb, plane: 0, pixelFormat: yFmt, cache: cache),
                  let uvTex = makeTexture(from: pb, plane: 1, pixelFormat: uvFmt, cache: cache) else {
                cb.popDebugGroup()
                cb.commit()
                return
            }
            yTex.label = "Luma (Y) \(w)x\(h)"
            uvTex.label = "Chroma (UV) \(w/2)x\(h/2)"
            
            let params = makeParams(for: pb, pixelFormat: fmt)

            converter.encode(commandBuffer: cb, luma: yTex, chroma: uvTex, output: outBGRA, params: params)
            
            cb.pushDebugGroup("Effects")
            let finalTex = effectRunner?.encodeEffects(input: outBGRA, commandBuffer: cb) ?? outBGRA
            cb.popDebugGroup()
            
            cb.addCompletedHandler { [weak self] _ in
                guard let self = self else { return }
                self.lock.lock()
                self.latestTexture = finalTex
                self.lock.unlock()
                
                // FPS + watchdog
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
            
            cb.popDebugGroup()
            cb.commit()
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
        var yOffset: Float = 0.0
        var uvOffset: Float = 0.5
        var yScale: Float = 1.0
        var uvScale: Float = 1.0

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
}