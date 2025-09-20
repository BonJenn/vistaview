import Foundation
import Metal
import QuartzCore
import CoreVideo

// MEMORY-OPTIMIZED Metal Renderer for External Displays
final class ExternalProgramMetalRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private weak var metalLayer: CAMetalLayer?
    private var pipelineState: MTLRenderPipelineState?
    private var displayLink: CVDisplayLink?
    private final class CallbackBox {
        weak var owner: ExternalProgramMetalRenderer?
        init(owner: ExternalProgramMetalRenderer) { self.owner = owner }
    }
    private var callbackBox: CallbackBox?
    private var isRunning = false
    
    // MEMORY OPTIMIZATION: Texture management
    private let textureProvider: () -> MTLTexture?
    private var lastTexture: MTLTexture?
    private var textureReferenceCount = 0
    private let maxTextureReferences = 3  // Limit texture retention
    
    // MEMORY OPTIMIZATION: Frame rate limiting for external displays
    private var lastFrameTime: CFTimeInterval = 0
    private let targetFrameInterval: CFTimeInterval = 1.0/30.0  // 30fps for LED walls
    
    // MEMORY OPTIMIZATION: Autorelease pool management
    private var frameCount = 0
    
    init?(device: MTLDevice, metalLayer: CAMetalLayer, textureProvider: @escaping () -> MTLTexture?) {
        self.device = device
        self.metalLayer = metalLayer
        self.textureProvider = textureProvider
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        guard makePipeline() else { return nil }
        guard setupDisplayLink() else { return nil }
        
        print("🎬 ExternalProgramMetalRenderer: Initialized with memory optimizations")
    }
    
    deinit {
        cleanup()
    }
    
    func start() {
        guard !isRunning, let link = displayLink else { return }
        isRunning = true
        CVDisplayLinkStart(link)
        print("🎬 ExternalProgramMetalRenderer: Started")
    }
    
    func stop() {
        guard let link = displayLink else { return }
        if CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
        isRunning = false
        print("🎬 ExternalProgramMetalRenderer: Stopped")
    }
    
    // MEMORY OPTIMIZATION: Comprehensive cleanup
    private func cleanup() {
        print("🧹 ExternalProgramMetalRenderer: Starting cleanup")
        
        stop()
        
        if let link = displayLink {
            CVDisplayLinkSetOutputCallback(link, { _,_,_,_,_,_ in kCVReturnSuccess }, nil)
            displayLink = nil
        }
        
        callbackBox?.owner = nil
        callbackBox = nil
        
        // Clear texture references
        lastTexture = nil
        textureReferenceCount = 0
        
        print("🧹 ExternalProgramMetalRenderer: Cleanup completed")
    }
    
    private func makePipeline() -> Bool {
        guard let lib = device.makeDefaultLibrary(),
              let vtx = lib.makeFunction(name: "vertex_main"),
              let frag = lib.makeFunction(name: "fragment_passthrough") else {
            return false
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.label = "ExternalProgramMetalRendererPipeline"
        desc.vertexFunction = vtx
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
            return true
        } catch {
            print("❌ Failed to create pipeline state: \(error)")
            return false
        }
    }
    
    private func setupDisplayLink() -> Bool {
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else { return false }
        displayLink = link
        let box = CallbackBox(owner: self)
        callbackBox = box
        let userPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(box).toOpaque())
        CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, user) -> CVReturn in
            guard let user else { return kCVReturnSuccess }
            let box = Unmanaged<CallbackBox>.fromOpaque(user).takeUnretainedValue()
            guard let owner = box.owner else { return kCVReturnSuccess }
            owner.drawFrameFromDisplayLink()
            return kCVReturnSuccess
        }, userPtr)
        return true
    }
    
    private func drawFrameFromDisplayLink() {
        // MEMORY OPTIMIZATION: Frame rate limiting
        let currentTime = CACurrentMediaTime()
        if currentTime - lastFrameTime < targetFrameInterval {
            return
        }
        lastFrameTime = currentTime
        
        // MEMORY OPTIMIZATION: Autorelease pool every frame
        autoreleasepool {
            drawFrame()
        }
    }
    
    private func drawFrame() {
        guard let pipelineState = pipelineState,
              let layer = metalLayer,
              let drawable = layer.nextDrawable() else {
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "ExternalProgramMetalRendererCB"
        
        let rpDesc = MTLRenderPassDescriptor()
        rpDesc.colorAttachments[0].texture = drawable.texture
        rpDesc.colorAttachments[0].loadAction = .clear
        rpDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpDesc.colorAttachments[0].storeAction = .store
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpDesc) else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }
        encoder.label = "ExternalProgramMetalRendererEncoder"
        encoder.setRenderPipelineState(pipelineState)
        
        // MEMORY OPTIMIZATION: Smart texture management
        let currentTexture = textureProvider()
        
        // Only update if we have a new texture or significant change
        let shouldUpdateTexture: Bool
        if let current = currentTexture, let last = lastTexture {
            shouldUpdateTexture = current !== last
        } else {
            shouldUpdateTexture = currentTexture != nil
        }
        
        if let tex = currentTexture, shouldUpdateTexture {
            encoder.setFragmentTexture(tex, index: 0)
            
            // MEMORY OPTIMIZATION: Limit texture reference retention
            if textureReferenceCount < maxTextureReferences {
                lastTexture = tex
                textureReferenceCount += 1
            } else {
                lastTexture = nil
                textureReferenceCount = 0
            }
            
            // Calculate aspect-fit viewport
            let dw = drawable.texture.width
            let dh = drawable.texture.height
            let tw = tex.width
            let th = tex.height
            
            if dw > 0 && dh > 0 && tw > 0 && th > 0 {
                let drawableAspect = Double(dw) / Double(dh)
                let textureAspect = Double(tw) / Double(th)
                var viewW = Double(dw)
                var viewH = Double(dh)
                var originX = 0.0
                var originY = 0.0
                
                if textureAspect > drawableAspect {
                    viewW = Double(dw)
                    viewH = Double(dw) / textureAspect
                    originY = (Double(dh) - viewH) * 0.5
                } else {
                    viewH = Double(dh)
                    viewW = Double(dh) * textureAspect
                    originX = (Double(dw) - viewW) * 0.5
                }
                let viewport = MTLViewport(originX: originX, originY: originY, width: viewW, height: viewH, znear: 0.0, zfar: 1.0)
                encoder.setViewport(viewport)
            }
        } else if let tex = lastTexture {
            // MEMORY OPTIMIZATION: Reuse last texture if available
            encoder.setFragmentTexture(tex, index: 0)
            let dw = drawable.texture.width
            let dh = drawable.texture.height
            let viewport = MTLViewport(originX: 0.0, originY: 0.0, width: Double(dw), height: Double(dh), znear: 0.0, zfar: 1.0)
            encoder.setViewport(viewport)
        } else {
            // No texture available - render black
            let dw = drawable.texture.width
            let dh = drawable.texture.height
            let viewport = MTLViewport(originX: 0.0, originY: 0.0, width: Double(dw), height: Double(dh), znear: 0.0, zfar: 1.0)
            encoder.setViewport(viewport)
        }
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        // MEMORY OPTIMIZATION: Don't retain drawable longer than necessary
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        frameCount += 1
        
        // MEMORY OPTIMIZATION: Periodic cleanup every 300 frames (~10 seconds at 30fps)
        if frameCount % 300 == 0 {
            autoreleasepool {
                // Force cleanup of old textures
                if textureReferenceCount > maxTextureReferences {
                    lastTexture = nil
                    textureReferenceCount = 0
                }
            }
        }
    }
}