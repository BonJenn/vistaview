import Foundation
import AVFoundation
import VideoToolbox
import Metal
import MetalKit
import CoreVideo

final class VideoPlaybackVT {
    let url: URL
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var converter: NV12ToBGRAConverter?
    private var decoder: VideoDecoder?
    private var outputTexture: MTLTexture?
    private var currentSize: (w: Int, h: Int) = (0, 0)
    private let inFlight = DispatchSemaphore(value: 3)
    
    var onFrame: ((MTLTexture, CMTime) -> Void)?
    var onFinished: (() -> Void)?
    var onError: ((Error) -> Void)?
    
    private let effectManager: EffectManager
    private let sourceID: String
    
    // Audio clock provider for sync
    var audioClockProvider: (() -> CMTime?)?
    
    init?(url: URL, device: MTLDevice, effectManager: EffectManager, sourceID: String) {
        self.url = url
        self.device = device
        self.effectManager = effectManager
        self.sourceID = sourceID
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        self.converter = NV12ToBGRAConverter(device: device)
    }
    
    func start() {
        stop()
        let decoder = VideoDecoder(url: url)
        self.decoder = decoder
        
        decoder.onFrame = { [weak self] pb, pts in
            guard let self = self, let cache = self.textureCache, let converter = self.converter else { return }
            
            // Audio-gated presentation decision (only while playing)
            if let audioTime = self.audioClockProvider?() {
                let a = CMTimeGetSeconds(audioTime)
                let p = CMTimeGetSeconds(pts)
                if p < a - 0.050 { return }
                if p > a + 0.030 { return }
            }
            
            let w = CVPixelBufferGetWidth(pb)
            let h = CVPixelBufferGetHeight(pb)
            if self.currentSize.w != w || self.currentSize.h != h || self.outputTexture == nil {
                self.currentSize = (w, h)
                self.outputTexture = converter.makeOutputTexture(width: w, height: h)
            }
            guard let outBGRA = self.outputTexture else { return }
            
            self.inFlight.wait()
            guard let cb = self.commandQueue.makeCommandBuffer() else {
                self.inFlight.signal()
                return
            }
            cb.addCompletedHandler { [weak self] _ in
                self?.inFlight.signal()
            }
            
            if let yTex = self.makeTexture(from: pb, plane: 0, pixelFormat: .r8Unorm, cache: cache),
               let uvTex = self.makeTexture(from: pb, plane: 1, pixelFormat: .rg8Unorm, cache: cache) {
                converter.encode(commandBuffer: cb, luma: yTex, chroma: uvTex, output: outBGRA)
                
                let presented = outBGRA
                cb.addCompletedHandler { [weak self] _ in
                    guard let self = self else { return }
                    self.onFrame?(presented, pts)
                }
                cb.commit()
            } else {
                // Nothing to convert; still commit to release semaphore
                cb.commit()
            }
        }
        decoder.onFinished = { [weak self] in
            self?.onFinished?()
        }
        decoder.onError = { [weak self] error in
            self?.onError?(error)
        }
        decoder.start()
    }
    
    func stop() {
        decoder?.stop()
        decoder = nil
    }
    
    func seek(to seconds: Double) {
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        decoder?.seek(to: t)
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