import Foundation
import Metal
import QuartzCore
import CoreVideo

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
    
    private let textureProvider: () -> MTLTexture?
    
    init?(device: MTLDevice, metalLayer: CAMetalLayer, textureProvider: @escaping () -> MTLTexture?) {
        self.device = device
        self.metalLayer = metalLayer
        self.textureProvider = textureProvider
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        guard makePipeline() else { return nil }
        guard setupDisplayLink() else { return nil }
    }
    
    deinit {
        stop()
        if let link = displayLink {
            CVDisplayLinkSetOutputCallback(link, { _,_,_,_,_,_ in kCVReturnSuccess }, nil)
        }
        callbackBox?.owner = nil
        callbackBox = nil
    }
    
    func start() {
        guard !isRunning, let link = displayLink else { return }
        isRunning = true
        CVDisplayLinkStart(link)
    }
    
    func stop() {
        guard let link = displayLink else { return }
        if CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
        isRunning = false
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
        
        if let tex = textureProvider() {
            encoder.setFragmentTexture(tex, index: 0)
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
        } else {
            let dw = drawable.texture.width
            let dh = drawable.texture.height
            let viewport = MTLViewport(originX: 0.0, originY: 0.0, width: Double(dw), height: Double(dh), znear: 0.0, zfar: 1.0)
            encoder.setViewport(viewport)
        }
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}