import Foundation
import AVFoundation
import CoreVideo
import Metal
import QuartzCore

final class AVPlayerMetalPlayback {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var converter: NV12ToBGRAConverter?
    private var outputTexture: MTLTexture?
    private var currentSize: (w: Int, h: Int) = (0, 0)
    private let inFlight = DispatchSemaphore(value: 3)
    
    private var displayLink: CVDisplayLink?
    private let lock = NSLock()
    
    private let player: AVPlayer
    private let itemOutput: AVPlayerItemVideoOutput
    
    private(set) var latestTexture: MTLTexture?
    
    private var effectRunner: EffectRunner?
    
    init?(player: AVPlayer, itemOutput: AVPlayerItemVideoOutput, device: MTLDevice) {
        self.player = player
        self.itemOutput = itemOutput
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        self.converter = NV12ToBGRAConverter(device: device)
        
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else { return nil }
        self.displayLink = link
        CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, user) -> CVReturn in
            let obj = Unmanaged<AVPlayerMetalPlayback>.fromOpaque(user!).takeUnretainedValue()
            obj.pullFrame()
            return kCVReturnSuccess
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }
    
    deinit {
        stop()
    }
    
    func start() {
        guard let link = displayLink, !CVDisplayLinkIsRunning(link) else { return }
        CVDisplayLinkStart(link)
    }
    
    func stop() {
        if let link = displayLink, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
    }
    
    func setEffectRunner(_ runner: EffectRunner?) {
        self.effectRunner = runner
    }
    
    private func pullFrame() {
        guard let cache = textureCache, let converter = converter else { return }
        
        let hostTimeTicks = CVGetCurrentHostTime()
        let hostTimeSec = Double(hostTimeTicks) / CVGetHostClockFrequency()
        let itemTime = itemOutput.itemTime(forHostTime: hostTimeSec)
        guard itemOutput.hasNewPixelBuffer(forItemTime: itemTime),
              let pb = itemOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
            return
        }
        
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        if currentSize.w != w || currentSize.h != h || outputTexture == nil {
            currentSize = (w, h)
            outputTexture = converter.makeOutputTexture(width: w, height: h)
        }
        guard let outBGRA = outputTexture else { return }
        
        inFlight.wait()
        guard let cb = commandQueue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        cb.addCompletedHandler { [weak self] _ in
            self?.inFlight.signal()
        }
        
        guard let yTex = makeTexture(from: pb, plane: 0, pixelFormat: .r8Unorm, cache: cache),
              let uvTex = makeTexture(from: pb, plane: 1, pixelFormat: .rg8Unorm, cache: cache) else {
            cb.commit()
            return
        }
        
        converter.encode(commandBuffer: cb, luma: yTex, chroma: uvTex, output: outBGRA)
        
        let finalTex = effectRunner?.encodeEffects(input: outBGRA, commandBuffer: cb) ?? outBGRA
        
        cb.addCompletedHandler { [weak self] _ in
            guard let self = self else { return }
            self.lock.lock()
            self.latestTexture = finalTex
            self.lock.unlock()
        }
        cb.commit()
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
}