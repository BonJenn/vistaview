import MetalKit
import AVFoundation
import VideoToolbox

// PERFORMANCE: BlurParams struct for efficient parameter passing to Metal shaders
struct BlurParams {
    let values: SIMD2<Float>
}

class BaseRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    var commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState
    var vertexBuffer: MTLBuffer
    
    // PERFORMANCE: Add pipeline state caching for different effects
    private var pipelineStates: [String: MTLRenderPipelineState] = [:]

    var player: AVPlayer?
    var videoOutput: AVPlayerItemVideoOutput?
    var textureCache: CVMetalTextureCache?
    
    // PERFORMANCE: Add texture caching to avoid recreating textures
    private var cachedTexture: MTLTexture?
    private var lastPixelBuffer: CVPixelBuffer?

    var blurEnabled: Bool = false
    var blurAmount: Float = 0.5
    
    // PERFORMANCE: Add command buffer pooling
    private var commandBufferPool: [MTLCommandBuffer] = []
    private let maxPoolSize = 3

    private let inFlightSemaphore = DispatchSemaphore(value: 3)

    private var useVTDecode = false
    private var vtDecoder: VideoDecoder?
    private var lastDecodedPixelBuffer: CVPixelBuffer?
    private let frameLock = NSLock()
    
    private var nv12Converter: NV12ToBGRAConverter?
    private var intermediateBGRA: MTLTexture?
    private var videoSize: (width: Int, height: Int) = (0, 0)

    init(mtkView: MTKView, blurEnabled: Bool = false, blurAmount: Float = 0.5) {
        self.device = mtkView.device ?? MTLCreateSystemDefaultDevice()!
        self.commandQueue = device.makeCommandQueue()!
        self.blurEnabled = blurEnabled
        self.blurAmount = blurAmount

        let defaultLibrary = device.makeDefaultLibrary()!
        
        // PERFORMANCE: Create multiple pipeline states for different scenarios
        let vertexFunction = defaultLibrary.makeFunction(name: "vertex_main")!
        
        // Default pipeline with blur
        let blurFragmentFunction = defaultLibrary.makeFunction(name: "fragment_main")!
        let blurPipelineDescriptor = MTLRenderPipelineDescriptor()
        blurPipelineDescriptor.vertexFunction = vertexFunction
        blurPipelineDescriptor.fragmentFunction = blurFragmentFunction
        blurPipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        
        self.pipelineState = try! device.makeRenderPipelineState(descriptor: blurPipelineDescriptor)
        pipelineStates["blur"] = pipelineState
        
        // PERFORMANCE: Add pass-through pipeline for no-effect scenarios
        if let passthroughFragment = defaultLibrary.makeFunction(name: "fragment_passthrough") {
            let passthroughDescriptor = MTLRenderPipelineDescriptor()
            passthroughDescriptor.vertexFunction = vertexFunction
            passthroughDescriptor.fragmentFunction = passthroughFragment
            passthroughDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            
            if let passthroughPipeline = try? device.makeRenderPipelineState(descriptor: passthroughDescriptor) {
                pipelineStates["passthrough"] = passthroughPipeline
            }
        }
        
        // PERFORMANCE: Add efficient box blur pipeline
        if let boxBlurFragment = defaultLibrary.makeFunction(name: "fragment_boxblur") {
            let boxBlurDescriptor = MTLRenderPipelineDescriptor()
            boxBlurDescriptor.vertexFunction = vertexFunction
            boxBlurDescriptor.fragmentFunction = boxBlurFragment
            boxBlurDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            
            if let boxBlurPipeline = try? device.makeRenderPipelineState(descriptor: boxBlurDescriptor) {
                pipelineStates["boxblur"] = boxBlurPipeline
            }
        }

        // PERFORMANCE: Create vertex buffer more efficiently
        let vertices: [Float] = [
            -1, -1, 0, 1,
             1, -1, 1, 1,
            -1,  1, 0, 0,
             1,  1, 1, 0
        ]
        self.vertexBuffer = device.makeBuffer(bytes: vertices, 
                                            length: MemoryLayout<Float>.size * vertices.count, 
                                            options: [.storageModeShared])!

        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        
        self.nv12Converter = NV12ToBGRAConverter(device: device)
    }

    func loadVideo(url: URL) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        let pixelBufferAttributes: [String: Any] = [
            (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
        ]

        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        item.add(videoOutput!)

        player = AVPlayer(playerItem: item)
        player?.play()
    }
    
    func loadVideoUsingVT(url: URL) {
        useVTDecode = true
        vtDecoder?.stop()
        let decoder = VideoDecoder(url: url)
        decoder.onFrame = { [weak self] pixelBuffer, pts in
            guard let self = self else { return }
            self.frameLock.lock()
            self.lastDecodedPixelBuffer = pixelBuffer
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            if self.videoSize.width != w || self.videoSize.height != h {
                self.videoSize = (w, h)
                self.intermediateBGRA = nil
                self.cachedTexture = nil
            }
            self.frameLock.unlock()
        }
        decoder.onError = { error in
            print("VT decode error: \(error)")
        }
        decoder.onFinished = {
            print("VT decode finished")
        }
        vtDecoder = decoder
        decoder.start()
    }
    
    // PERFORMANCE: Optimized command buffer creation with pooling
    private func getCommandBuffer() -> MTLCommandBuffer? {
        if !commandBufferPool.isEmpty {
            return commandBufferPool.removeFirst()
        }
        return commandQueue.makeCommandBuffer()
    }
    
    private func returnCommandBuffer(_ buffer: MTLCommandBuffer) {
        if commandBufferPool.count < maxPoolSize {
            commandBufferPool.append(buffer)
        }
    }

    // PERFORMANCE: Optimized draw method with texture caching and pipeline selection
    func draw(in view: MTKView) {
        guard let commandBuffer = getCommandBuffer() else {
            return
        }
        
        inFlightSemaphore.wait()
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
        }

        var textureForRendering: MTLTexture?

        if useVTDecode {
            // NV12 -> BGRA conversion path
            var pixelBuffer: CVPixelBuffer?
            frameLock.lock()
            pixelBuffer = lastDecodedPixelBuffer
            frameLock.unlock()
            
            if let pb = pixelBuffer, let textureCache = textureCache {
                let yTex = makeTexture(from: pb, plane: 0, pixelFormat: .r8Unorm, cache: textureCache)
                let cbcrTex = makeTexture(from: pb, plane: 1, pixelFormat: .rg8Unorm, cache: textureCache)
                
                if let yTex, let cbcrTex, let converter = nv12Converter {
                    if intermediateBGRA == nil {
                        intermediateBGRA = converter.makeOutputTexture(width: videoSize.width, height: videoSize.height)
                    }
                    if let out = intermediateBGRA {
                        converter.encode(commandBuffer: commandBuffer, luma: yTex, chroma: cbcrTex, output: out)
                        textureForRendering = out
                    }
                }
            } else if let cached = cachedTexture {
                textureForRendering = cached
            }
        } else {
            // Existing AVPlayerItemVideoOutput path
            if let videoOutput = videoOutput,
               let currentTime = player?.currentTime(),
               videoOutput.hasNewPixelBuffer(forItemTime: currentTime) {
                
                if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {
                    if let lastBuffer = lastPixelBuffer,
                       CFEqual(pixelBuffer, lastBuffer),
                       let texture = cachedTexture {
                        textureForRendering = texture
                    } else {
                        if let textureCache = textureCache,
                           let texture = createMetalTexture(from: pixelBuffer, textureCache: textureCache) {
                            textureForRendering = texture
                            cachedTexture = texture
                            lastPixelBuffer = pixelBuffer
                        }
                    }
                }
            } else if let texture = cachedTexture {
                textureForRendering = texture
            }
        }
        
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            commandBuffer.commit()
            return
        }

        // PERFORMANCE: Select optimal pipeline based on current settings
        let pipelineName: String
        if !blurEnabled || blurAmount < 0.01 {
            pipelineName = "passthrough"
        } else if blurAmount < 0.3 {
            pipelineName = "boxblur"
        } else {
            pipelineName = "blur"
        }
        
        let selectedPipeline = pipelineStates[pipelineName] ?? pipelineState
        encoder.setRenderPipelineState(selectedPipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        if let tex = textureForRendering {
            encoder.setFragmentTexture(tex, index: 0)
        }
        
        if pipelineName != "passthrough" {
            var blurParams = BlurParams(values: SIMD2<Float>(blurEnabled ? 1.0 : 0.0, blurAmount))
            encoder.setFragmentBytes(&blurParams, length: MemoryLayout<BlurParams>.size, index: 0)
        }

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
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

    // PERFORMANCE: Optimized Metal texture creation
    private func createMetalTexture(from pixelBuffer: CVPixelBuffer, textureCache: CVMetalTextureCache) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTextureOut: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTextureOut
        )
        
        guard result == kCVReturnSuccess,
              let cvTexture = cvTextureOut,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        
        return texture
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // PERFORMANCE: Clear cached texture when size changes
        cachedTexture = nil
        lastPixelBuffer = nil
    }
}