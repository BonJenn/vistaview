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
    
    public init(device: MTLDevice) {
        self.device = device
        super.init()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }
    
    public func push(_ pixelBuffer: CVPixelBuffer) {
        let cache = textureCache
        textureQueue.async { [weak self] in
            guard let self, let cache else { return }
            var cvTexture: CVMetalTexture?
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                      cache,
                                                      pixelBuffer,
                                                      nil,
                                                      .bgra8Unorm,
                                                      width,
                                                      height,
                                                      0,
                                                      &cvTexture)
            if let cvTexture, let tex = CVMetalTextureGetTexture(cvTexture) {
                self._currentTexture = tex
            }
        }
    }
}