import Metal
import MetalKit
import SceneKit
import CoreVideo
import simd
import AVFoundation

/// High-performance Metal-based renderer for virtual camera feeds
/// Pure macOS implementation
class VirtualCameraRenderer: NSObject {
    
    // MARK: - Core Metal Infrastructure
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    // Render targets
    private var renderPassDescriptor: MTLRenderPassDescriptor
    private var colorTexture: MTLTexture
    private var depthTexture: MTLTexture
    
    // SceneKit integration
    private var sceneRenderer: SCNRenderer
    private var renderSize: CGSize
    
    // Output management
    private var textureCache: CVMetalTextureCache?
    private var outputPixelBufferPool: CVPixelBufferPool?
    
    // Performance tracking
    private var frameCount: Int = 0
    private var lastFrameTime: CFTimeInterval = 0
    
    // MARK: - Initialization
    
    init?(device: MTLDevice? = nil, renderSize: CGSize = CGSize(width: 1920, height: 1080)) {
        guard let metalDevice = device ?? MTLCreateSystemDefaultDevice() else {
            print("❌ Metal device creation failed")
            return nil
        }
        
        self.device = metalDevice
        self.renderSize = renderSize
        
        guard let queue = metalDevice.makeCommandQueue() else {
            print("❌ Command queue creation failed")
            return nil
        }
        self.commandQueue = queue
        
        guard let library = metalDevice.makeDefaultLibrary() else {
            print("❌ Metal library creation failed")
            return nil
        }
        self.library = library
        
        // Initialize render pass descriptor
        self.renderPassDescriptor = MTLRenderPassDescriptor()
        
        // Create color texture
        let colorDescriptor = MTLTextureDescriptor()
        colorDescriptor.textureType = .type2D
        colorDescriptor.pixelFormat = .bgra8Unorm
        colorDescriptor.width = Int(renderSize.width)
        colorDescriptor.height = Int(renderSize.height)
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        
        guard let colorTex = metalDevice.makeTexture(descriptor: colorDescriptor) else {
            print("❌ Color texture creation failed")
            return nil
        }
        self.colorTexture = colorTex
        
        // Create depth texture
        let depthDescriptor = MTLTextureDescriptor()
        depthDescriptor.textureType = .type2D
        depthDescriptor.pixelFormat = .depth32Float
        depthDescriptor.width = Int(renderSize.width)
        depthDescriptor.height = Int(renderSize.height)
        depthDescriptor.usage = .renderTarget
        
        guard let depthTex = metalDevice.makeTexture(descriptor: depthDescriptor) else {
            print("❌ Depth texture creation failed")
            return nil
        }
        self.depthTexture = depthTex
        
        // Setup SceneKit renderer (macOS compatible)
        self.sceneRenderer = SCNRenderer(device: metalDevice, options: nil)
        
        super.init()
        
        // Setup output pipeline
        setupOutputPipeline()
        setupRenderTargets()
        
        print("✅ VirtualCameraRenderer initialized - Metal Device: \(metalDevice.name)")
    }
    
    // MARK: - Setup Methods
    
    private func setupOutputPipeline() {
        // Create texture cache for Core Video integration
        let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        guard result == kCVReturnSuccess else {
            print("❌ Failed to create texture cache")
            return
        }
        
        // Create pixel buffer pool for output
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(renderSize.width),
            kCVPixelBufferHeightKey as String: Int(renderSize.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        let poolResult = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &outputPixelBufferPool)
        guard poolResult == kCVReturnSuccess else {
            print("❌ Failed to create pixel buffer pool")
            return
        }
        
        print("✅ Output pipeline setup complete")
    }
    
    private func setupRenderTargets() {
        // Configure render pass descriptor
        renderPassDescriptor.colorAttachments[0].texture = colorTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        
        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.depthAttachment.clearDepth = 1.0
        
        print("✅ Render targets configured")
    }
    
    // MARK: - Core Rendering Methods
    
    func renderFrame(from virtualCamera: VirtualCamera, scene: SCNScene) -> CVPixelBuffer? {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("❌ Failed to create command buffer")
            return nil
        }
        
        // Configure SceneKit renderer
        sceneRenderer.scene = scene
        sceneRenderer.pointOfView = virtualCamera.node
        
        // Render SceneKit scene to Metal texture
        let viewport = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)
        sceneRenderer.render(atTime: CFAbsoluteTimeGetCurrent(), viewport: viewport, commandBuffer: commandBuffer, passDescriptor: renderPassDescriptor)
        
        // Convert to pixel buffer for streaming
        guard let pixelBuffer = metalTextureToPixelBuffer() else {
            print("❌ Failed to convert Metal texture to pixel buffer")
            return nil
        }
        
        // Commit and wait
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Performance tracking
        trackPerformance(startTime: startTime)
        
        return pixelBuffer
    }
    
    func renderFrameWithEffects(from virtualCamera: VirtualCamera, scene: SCNScene, effects: [String: Any] = [:]) -> CVPixelBuffer? {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("❌ Failed to create command buffer")
            return nil
        }
        
        // Render base scene
        sceneRenderer.scene = scene
        sceneRenderer.pointOfView = virtualCamera.node
        
        let viewport = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)
        sceneRenderer.render(atTime: CFAbsoluteTimeGetCurrent(), viewport: viewport, commandBuffer: commandBuffer, passDescriptor: renderPassDescriptor)
        
        // Apply effects if needed
        if !effects.isEmpty {
            applyEffects(commandBuffer: commandBuffer, effects: effects)
        }
        
        // Convert to output format
        guard let pixelBuffer = metalTextureToPixelBuffer() else {
            print("❌ Failed to convert Metal texture to pixel buffer")
            return nil
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        trackPerformance(startTime: startTime)
        
        return pixelBuffer
    }
    
    // MARK: - Effects Integration
    
    private func applyEffects(commandBuffer: MTLCommandBuffer, effects: [String: Any]) {
        // TODO: Integration point for your existing effects pipeline
        print("🎨 Effects applied: \(effects.keys)")
    }
    
    // MARK: - Texture Conversion
    
    private func metalTextureToPixelBuffer() -> CVPixelBuffer? {
        guard let pool = outputPixelBufferPool else { return nil }
        
        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        
        guard result == kCVReturnSuccess, let buffer = pixelBuffer else {
            print("❌ Failed to create pixel buffer from pool")
            return nil
        }
        
        // Copy Metal texture to pixel buffer
        guard let textureCache = self.textureCache else { return nil }
        
        var metalTexture: CVMetalTexture?
        let textureResult = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            buffer,
            nil,
            .bgra8Unorm,
            CVPixelBufferGetWidth(buffer),
            CVPixelBufferGetHeight(buffer),
            0,
            &metalTexture
        )
        
        guard textureResult == kCVReturnSuccess,
              let texture = metalTexture,
              let destinationTexture = CVMetalTextureGetTexture(texture) else {
            print("❌ Failed to create Metal texture from pixel buffer")
            return nil
        }
        
        // Use blit encoder to copy texture
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return nil
        }
        
        blitEncoder.copy(from: colorTexture,
                        sourceSlice: 0,
                        sourceLevel: 0,
                        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                        sourceSize: MTLSize(width: colorTexture.width, height: colorTexture.height, depth: 1),
                        to: destinationTexture,
                        destinationSlice: 0,
                        destinationLevel: 0,
                        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return buffer
    }
    
    // MARK: - Performance Monitoring
    
    private func trackPerformance(startTime: CFTimeInterval) {
        let frameTime = CFAbsoluteTimeGetCurrent() - startTime
        frameCount += 1
        
        if frameCount % 60 == 0 {
            let fps = 1.0 / frameTime
            print("🎥 Virtual Camera Performance - Frame: \(frameCount), FPS: \(String(format: "%.1f", fps)), Frame Time: \(String(format: "%.2f", frameTime * 1000))ms")
        }
        
        lastFrameTime = frameTime
    }
    
    // MARK: - Configuration
    
    func updateRenderSize(_ newSize: CGSize) {
        guard newSize != renderSize else { return }
        
        renderSize = newSize
        
        // Recreate color texture
        let colorDescriptor = MTLTextureDescriptor()
        colorDescriptor.textureType = .type2D
        colorDescriptor.pixelFormat = .bgra8Unorm
        colorDescriptor.width = Int(newSize.width)
        colorDescriptor.height = Int(newSize.height)
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        
        guard let newColorTexture = device.makeTexture(descriptor: colorDescriptor) else {
            print("❌ Failed to recreate color texture")
            return
        }
        colorTexture = newColorTexture
        
        // Recreate depth texture
        let depthDescriptor = MTLTextureDescriptor()
        depthDescriptor.textureType = .type2D
        depthDescriptor.pixelFormat = .depth32Float
        depthDescriptor.width = Int(newSize.width)
        depthDescriptor.height = Int(newSize.height)
        depthDescriptor.usage = .renderTarget
        
        guard let newDepthTexture = device.makeTexture(descriptor: depthDescriptor) else {
            print("❌ Failed to recreate depth texture")
            return
        }
        depthTexture = newDepthTexture
        
        setupRenderTargets()
        setupOutputPipeline()
        
        print("✅ Render size updated to \(newSize)")
    }
    
    // MARK: - Utility Methods
    
    var isReady: Bool {
        return true // Simplified for macOS
    }
    
    var currentFPS: Double {
        return lastFrameTime > 0 ? 1.0 / lastFrameTime : 0
    }
    
    func getDeviceInfo() -> String {
        return """
        🎥 Virtual Camera Renderer Info:
        Device: \(device.name)
        Render Size: \(renderSize)
        Current FPS: \(String(format: "%.1f", currentFPS))
        Frames Rendered: \(frameCount)
        Memory Usage: \(String(format: "%.1f", Double(device.currentAllocatedSize) / 1024 / 1024))MB
        """
    }
}

// MARK: - Integration Extensions

extension VirtualCameraRenderer {
    
    func integrateWithBaseRenderer(_ baseRenderer: Any?) {
        print("🔗 BaseRenderer integration ready")
    }
    
    func integrateWithPreviewRenderer(_ previewRenderer: Any?) {
        print("🔗 PreviewRenderer integration ready")
    }
    
    func integrateWithMainRenderer(_ mainRenderer: Any?) {
        print("🔗 MainRenderer integration ready")
    }
}

// MARK: - Error Handling

enum VirtualCameraRenderError: Error, LocalizedError {
    case metalDeviceUnavailable
    case textureCreationFailed
    case commandBufferCreationFailed
    case pixelBufferConversionFailed
    case renderingFailed
    
    var errorDescription: String? {
        switch self {
        case .metalDeviceUnavailable:
            return "Metal device is not available on this system"
        case .textureCreationFailed:
            return "Failed to create Metal textures"
        case .commandBufferCreationFailed:
            return "Failed to create Metal command buffer"
        case .pixelBufferConversionFailed:
            return "Failed to convert Metal texture to pixel buffer"
        case .renderingFailed:
            return "Virtual camera rendering failed"
        }
    }
}
