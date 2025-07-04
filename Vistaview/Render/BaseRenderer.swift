import MetalKit
import AVFoundation

class BaseRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    var commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState
    var vertexBuffer: MTLBuffer

    var player: AVPlayer?
    var videoOutput: AVPlayerItemVideoOutput?
    var textureCache: CVMetalTextureCache?

    var blurEnabled: Bool = false
    var blurAmount: Float = 0.5

    init(mtkView: MTKView, blurEnabled: Bool = false, blurAmount: Float = 0.5) {
        self.device = mtkView.device ?? MTLCreateSystemDefaultDevice()!
        self.commandQueue = device.makeCommandQueue()!
        self.blurEnabled = blurEnabled
        self.blurAmount = blurAmount

        let defaultLibrary = device.makeDefaultLibrary()!
        let vertexFunction = defaultLibrary.makeFunction(name: "vertex_main")!
        let fragmentFunction = defaultLibrary.makeFunction(name: "fragment_main")!

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        self.pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        let vertices: [Float] = [
            -1, -1, 0, 1,
             1, -1, 1, 1,
            -1,  1, 0, 0,
             1,  1, 1, 0
        ]
        self.vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Float>.size * vertices.count, options: [])!

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

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        if let videoOutput = videoOutput,
           let currentTime = player?.currentTime(),
           videoOutput.hasNewPixelBuffer(forItemTime: currentTime),
           let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil),
           let textureCache = textureCache {

            var cvTextureOut: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &cvTextureOut)

            if let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) {
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentBytes(&blurEnabled, length: MemoryLayout<Bool>.size, index: 0)
                encoder.setFragmentBytes(&blurAmount, length: MemoryLayout<Float>.size, index: 1)
            }
        }

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
