import MetalKit
import AVFoundation
import simd
import QuartzCore

struct BlurParams {
    var values: SIMD2<Float>
}

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    var commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState
    var vertexBuffer: MTLBuffer

    var player: AVPlayer?
    var videoOutput: AVPlayerItemVideoOutput?
    var textureCache: CVMetalTextureCache?
    var currentTexture: MTLTexture? = nil

    var blurEnabled: Bool = false
    var blurAmount: Float = 0.5

    weak var currentView: MTKView?
    var displayLink: CVDisplayLink?

    init(mtkView: MTKView, blurEnabled: Bool, blurAmount: Float) {
        guard let metalDevice = mtkView.device,
              let metalQueue = metalDevice.makeCommandQueue() else {
            fatalError("❌ Metal device or command queue could not be initialized.")
        }

        self.device = metalDevice
        self.commandQueue = metalQueue
        self.blurEnabled = blurEnabled
        self.blurAmount = blurAmount
        self.currentView = mtkView

        let defaultLibrary = device.makeDefaultLibrary()!
        guard let vertexFunction = defaultLibrary.makeFunction(name: "vertex_main"),
              let fragmentFunction = defaultLibrary.makeFunction(name: "fragment_main") else {
            fatalError("❌ Could not find Metal shader functions.")
        }

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

        NotificationCenter.default.addObserver(forName: .loadNewVideo, object: nil, queue: .main) { [weak self] notification in
            if let url = notification.object as? URL {
                self?.loadVideo(url: url)
            }
        }

        if let defaultURL = Bundle.main.url(forResource: "clip", withExtension: "mp4") {
            loadVideo(url: defaultURL)
        } else {
            print("⚠️ Default video clip.mp4 not found in bundle.")
        }

        setupDisplayLink()
    }

    func setupDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        displayLink = link

        guard let displayLink = displayLink else {
            print("❌ Failed to create display link")
            return
        }

        CVDisplayLinkSetOutputCallback(displayLink, { (_, _, _, _, _, userInfo) -> CVReturn in
            let renderer = Unmanaged<Renderer>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                renderer.currentView?.draw()
            }
            return kCVReturnSuccess
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        CVDisplayLinkStart(displayLink)
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
        player?.currentItem?.add(videoOutput!)
        player?.isMuted = true
        player?.play()
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        if let videoOutput = videoOutput,
           let player = player,
           let textureCache = textureCache {

            let currentTime = player.currentTime()

            if videoOutput.hasNewPixelBuffer(forItemTime: currentTime),
               let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {

                var cvTextureOut: CVMetalTexture?
                CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil,
                                                          .bgra8Unorm,
                                                          CVPixelBufferGetWidth(pixelBuffer),
                                                          CVPixelBufferGetHeight(pixelBuffer),
                                                          0, &cvTextureOut)

                if let cvTexture = cvTextureOut {
                    currentTexture = CVMetalTextureGetTexture(cvTexture)
                }
            }
        }

        if let texture = currentTexture {
            encoder.setFragmentTexture(texture, index: 0)

            var blurParams = BlurParams(values: SIMD2<Float>(blurEnabled ? 1.0 : 0.0, max(0.0, min(1.0, blurAmount))))
            encoder.setFragmentBytes(&blurParams, length: MemoryLayout<BlurParams>.size, index: 0)

            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

