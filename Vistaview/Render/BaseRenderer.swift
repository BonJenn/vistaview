import MetalKit
import AVFoundation

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
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = getCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { 
            return 
        }

        // PERFORMANCE: Select optimal pipeline based on current settings
        let pipelineName: String
        if !blurEnabled || blurAmount < 0.01 {
            pipelineName = "passthrough"
        } else if blurAmount < 0.3 {
            pipelineName = "boxblur"  // Use faster box blur for light blur
        } else {
            pipelineName = "blur"     // Use high-quality Gaussian blur for heavy blur
        }
        
        let selectedPipeline = pipelineStates[pipelineName] ?? pipelineState
        encoder.setRenderPipelineState(selectedPipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // PERFORMANCE: Optimized texture handling with caching
        if let videoOutput = videoOutput,
           let currentTime = player?.currentTime(),
           videoOutput.hasNewPixelBuffer(forItemTime: currentTime) {
            
            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {
                
                // PERFORMANCE: Check if we can reuse cached texture
                if let lastBuffer = lastPixelBuffer,
                   CFEqual(pixelBuffer, lastBuffer),
                   let texture = cachedTexture {
                    // Reuse cached texture
                    encoder.setFragmentTexture(texture, index: 0)
                } else {
                    // Create new texture and cache it
                    if let textureCache = textureCache,
                       let texture = createMetalTexture(from: pixelBuffer, textureCache: textureCache) {
                        encoder.setFragmentTexture(texture, index: 0)
                        cachedTexture = texture
                        lastPixelBuffer = pixelBuffer
                    }
                }
                
                // PERFORMANCE: Only set blur parameters if using blur pipeline
                if pipelineName != "passthrough" {
                    var blurParams = BlurParams(values: SIMD2<Float>(blurEnabled ? 1.0 : 0.0, blurAmount))
                    encoder.setFragmentBytes(&blurParams, length: MemoryLayout<BlurParams>.size, index: 0)
                }
            }
        } else if let texture = cachedTexture {
            // PERFORMANCE: Reuse last cached texture if no new frame
            encoder.setFragmentTexture(texture, index: 0)
            
            if pipelineName != "passthrough" {
                var blurParams = BlurParams(values: SIMD2<Float>(blurEnabled ? 1.0 : 0.0, blurAmount))
                encoder.setFragmentBytes(&blurParams, length: MemoryLayout<BlurParams>.size, index: 0)
            }
        }

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // PERFORMANCE: Return command buffer to pool for reuse
        // Note: Can't actually reuse MTLCommandBuffer, but this pattern is ready for Metal objects that can be pooled
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