import Foundation
import Metal
import MetalKit
import CoreVideo

public protocol VideoRenderable: AnyObject {
    func push(_ pixelBuffer: CVPixelBuffer)
    var currentTexture: MTLTexture? { get }
}

public final class ProgramRenderer: NSObject, VideoRenderable {
    private let device: MTLDevice
    private var textureCache: CVMetalTextureCache?
    private let textureQueue = DispatchQueue(label: "app.vantaview.programrenderer", qos: .userInitiated)
    
    private var _currentTexture: MTLTexture?
    public var currentTexture: MTLTexture? { _currentTexture }
    
    // Keep CVMetalTexture alive for as long as we use the MTLTexture
    private var lastCVTexture: CVMetalTexture?
    private var frameCounter: Int = 0
    private let flushInterval: Int = 300
    
    public init(device: MTLDevice) {
        self.device = device
        super.init()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }
    
    deinit {
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
        lastCVTexture = nil
        _currentTexture = nil
    }
    
    public func push(_ pixelBuffer: CVPixelBuffer) {
        guard let cache = textureCache else { return }
        textureQueue.async { [weak self] in
            guard let self else { return }
            var cvTexture: CVMetalTexture?
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                cache,
                pixelBuffer,
                nil,
                .bgra8Unorm,
                width,
                height,
                0,
                &cvTexture
            )
            if status == kCVReturnSuccess, let cvTexture, let tex = CVMetalTextureGetTexture(cvTexture) {
                // Retain CVMetalTexture while we expose MTLTexture
                self.lastCVTexture = cvTexture
                self._currentTexture = tex
            }
            self.frameCounter &+= 1
            if self.frameCounter % self.flushInterval == 0 {
                CVMetalTextureCacheFlush(cache, 0)
            }
        }
    }
}