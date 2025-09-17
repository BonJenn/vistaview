import SwiftUI
import AppKit
import Metal
import MetalKit
import AVFoundation
import CoreImage

struct CompositedLayersContent: View {
    @EnvironmentObject var layerManager: LayerStackManager
    @ObservedObject var productionManager: UnifiedProductionManager
    let isPreview: Bool
    
    private var metalDevice: MTLDevice {
        productionManager.outputMappingManager.metalDevice
    }
    
    private var commandQueue: MTLCommandQueue {
        metalDevice.makeCommandQueue()!
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(layerManager.layers(isPreview: isPreview).sorted(by: { $0.zIndex < $1.zIndex })) { model in
                    if model.isEnabled {
                        layerView(for: model, canvasSize: size)
                            .frame(
                                width: size.width * model.sizeNorm.width,
                                height: size.height * model.sizeNorm.height
                            )
                            .position(
                                x: size.width * model.centerNorm.x,
                                y: size.height * model.centerNorm.y
                            )
                            .rotationEffect(.degrees(Double(model.rotationDegrees)))
                            .opacity(Double(model.opacity))
                            .clipped()
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func layerView(for model: CompositedLayer, canvasSize: CGSize) -> some View {
        switch model.source {
        case .camera(let feedId):
            if let feed = productionManager.cameraFeedManager.activeFeeds.first(where: { $0.id == feedId }) {
                let ck = effectiveChromaKeySettings(for: model)
                ChromaKeyAwareCameraView(
                    feed: feed,
                    chromaKeySettings: ck,
                    metalDevice: metalDevice,
                    commandQueue: commandQueue
                )
                .background(Color.clear)
                .id("camera-\(feedId)-\(ck.enabled)-\(ck.keyR)-\(ck.keyG)-\(ck.keyB)")
            } else {
                Color.black.overlay(
                    Text("Camera offline").font(.caption).foregroundColor(.white)
                )
            }

        case .media(let file):
            switch file.fileType {
            case .image:
                if let img = NSImage(contentsOf: file.url) {
                    let ck = effectiveChromaKeySettings(for: model)
                    ChromaKeyAwareImageView(
                        image: img,
                        chromaKeySettings: ck,
                        metalDevice: metalDevice,
                        commandQueue: commandQueue
                    )
                    .background(Color.clear)
                    .id("image-\(file.id)-\(ck.enabled)-\(ck.keyR)-\(ck.keyG)-\(ck.keyB)")
                } else {
                    Color.black.overlay(
                        Text("Image not found").font(.caption).foregroundColor(.white)
                    )
                }
            case .video:
                let ck = effectiveChromaKeySettings(for: model)
                ChromaKeyAwareVideoView(
                    mediaFile: file,
                    chromaKeySettings: ck,
                    metalDevice: metalDevice,
                    commandQueue: commandQueue
                )
                .background(Color.clear)
                .id("video-\(file.id)-\(ck.enabled)-\(ck.keyR)-\(ck.keyG)-\(ck.keyB)")
            case .audio:
                Color.clear
            }

        case .title(let overlay):
            if (isPreview ? layerManager.editingPreviewLayerID : layerManager.editingLayerID) == model.id {
                Color.clear
            } else {
                ZStack {
                    Color.clear
                    Text(overlay.text)
                        .font(.system(size: overlay.fontSize, weight: .bold))
                        .foregroundColor(Color(red: overlay.color.r, green: overlay.color.g, blue: overlay.color.b, opacity: overlay.color.a))
                        .multilineTextAlignment(overlay.alignment)
                        .minimumScaleFactor(0.2)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: {
                            switch overlay.alignment {
                            case .leading: return .leading
                            case .trailing: return .trailing
                            case .center: return .center
                            default: return .center
                            }
                        }())
                }
            }
        }
    }
    
    private func effectiveChromaKeySettings(for model: CompositedLayer) -> PiPChromaKeySettings {
        var s = model.chromaKey
        let programCK = productionManager.previewProgramManager
            .getProgramEffectChain()?
            .effects.compactMap { $0 as? ChromaKeyEffect }.first
        let previewCK = productionManager.previewProgramManager
            .getPreviewEffectChain()?
            .effects.compactMap { $0 as? ChromaKeyEffect }.first
        
        if let ck = programCK ?? previewCK {
            s.keyR = ck.parameters["keyR"]?.value ?? s.keyR
            s.keyG = ck.parameters["keyG"]?.value ?? s.keyG
            s.keyB = ck.parameters["keyB"]?.value ?? s.keyB
        }
        return s
    }
}

// MARK: - Chroma Key Aware Camera View

struct ChromaKeyAwareCameraView: NSViewRepresentable {
    let feed: CameraFeed
    let chromaKeySettings: PiPChromaKeySettings
    let metalDevice: MTLDevice
    let commandQueue: MTLCommandQueue
    
    func makeNSView(context: Context) -> ChromaKeyProcessor {
        return ChromaKeyProcessor(
            feed: feed,
            chromaKeySettings: chromaKeySettings,
            metalDevice: metalDevice,
            commandQueue: commandQueue
        )
    }
    
    func updateNSView(_ nsView: ChromaKeyProcessor, context: Context) {
        nsView.updateChromaKeySettings(chromaKeySettings)
    }
}

// MARK: - Chroma Key Aware Image View

struct ChromaKeyAwareImageView: NSViewRepresentable {
    let image: NSImage
    let chromaKeySettings: PiPChromaKeySettings
    let metalDevice: MTLDevice
    let commandQueue: MTLCommandQueue
    
    func makeNSView(context: Context) -> ChromaKeyImageProcessor {
        return ChromaKeyImageProcessor(
            image: image,
            chromaKeySettings: chromaKeySettings,
            metalDevice: metalDevice,
            commandQueue: commandQueue
        )
    }
    
    func updateNSView(_ nsView: ChromaKeyImageProcessor, context: Context) {
        nsView.updateChromaKeySettings(chromaKeySettings)
    }
}

// MARK: - Chroma Key Aware Video View

struct ChromaKeyAwareVideoView: NSViewRepresentable {
    let mediaFile: MediaFile
    let chromaKeySettings: PiPChromaKeySettings
    let metalDevice: MTLDevice
    let commandQueue: MTLCommandQueue
    
    func makeNSView(context: Context) -> ChromaKeyVideoProcessor {
        return ChromaKeyVideoProcessor(
            url: mediaFile.url,
            chromaKeySettings: chromaKeySettings,
            metalDevice: metalDevice,
            commandQueue: commandQueue
        )
    }
    
    func updateNSView(_ nsView: ChromaKeyVideoProcessor, context: Context) {
        nsView.updateChromaKeySettings(chromaKeySettings)
    }
}

// MARK: - Chroma Key Video Processor

class ChromaKeyVideoProcessor: NSView {
    private let url: URL
    private var chromaKeySettings: PiPChromaKeySettings
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    private var imageLayer: CALayer!
    private var ckPipelineState: MTLComputePipelineState?
    private var ckFallbackBGTexture: MTLTexture?
    private var ciContext: CIContext!
    private var frameTimer: Timer?
    private var isDestroyed = false
    
    private var player: AVPlayer!
    private var itemOutput: AVPlayerItemVideoOutput!
    private var lastDisplayedImage: CGImage?
    private var hasSecurityAccess = false
    
    init(url: URL, chromaKeySettings: PiPChromaKeySettings, metalDevice: MTLDevice, commandQueue: MTLCommandQueue) {
        self.url = url
        self.chromaKeySettings = chromaKeySettings
        self.metalDevice = metalDevice
        self.commandQueue = commandQueue
        super.init(frame: .zero)
        
        setupLayer()
        setupMetal()
        setupPlayer()
        startFrameTimer()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
    
    private func setupLayer() {
        wantsLayer = true
        imageLayer = CALayer()
        imageLayer.frame = bounds
        imageLayer.backgroundColor = CGColor.clear
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.isOpaque = false
        layer = imageLayer
    }
    
    private func setupMetal() {
        ciContext = CIContext(mtlDevice: metalDevice, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        
        if let library = metalDevice.makeDefaultLibrary(),
           let function = library.makeFunction(name: "chromaKeyKernel") {
            ckPipelineState = try? metalDevice.makeComputePipelineState(function: function)
        }
        
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        if let tex = metalDevice.makeTexture(descriptor: desc) {
            var px: UInt32 = 0x000000FF
            tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
            ckFallbackBGTexture = tex
        }
    }
    
    private func setupPlayer() {
        if url.isFileURL {
            hasSecurityAccess = url.startAccessingSecurityScopedResource()
        }
        
        let item = AVPlayerItem(url: url)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        output.suppressesPlayerRendering = true
        item.add(output)
        
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(self, selector: #selector(loopVideo(_:)), name: .AVPlayerItemDidPlayToEndTime, object: item)
        
        self.player = player
        self.itemOutput = output
        
        player.play()
    }
    
    @objc private func loopVideo(_ note: Notification) {
        player.seek(to: .zero)
        player.play()
    }
    
    private func startFrameTimer() {
        frameTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            self?.pullAndRenderFrame()
        }
    }
    
    func updateChromaKeySettings(_ newSettings: PiPChromaKeySettings) {
        chromaKeySettings = newSettings
        pullAndRenderFrame()
    }
    
    private func pullAndRenderFrame() {
        guard !isDestroyed, let output = itemOutput else { return }
        
        var t = player.currentTime()
        let host = CACurrentMediaTime()
        let itemTime = output.itemTime(forHostTime: host)
        if output.hasNewPixelBuffer(forItemTime: itemTime) {
            t = itemTime
        } else if !output.hasNewPixelBuffer(forItemTime: t) {
            return
        }
        
        var displayTime = CMTime.zero
        guard let pb = output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: &displayTime) else { return }
        
        if !chromaKeySettings.enabled {
            if let cg = cgImage(from: pb) {
                display(cg)
                lastDisplayedImage = cg
            }
            return
        }
        
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        
        let inputDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        inputDesc.usage = [.shaderRead, .shaderWrite]
        guard let inputTex = metalDevice.makeTexture(descriptor: inputDesc) else { return }
        
        guard let cb = commandQueue.makeCommandBuffer() else { return }
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let ciSrc = CIImage(cvPixelBuffer: pb)
        ciContext.render(ciSrc, to: inputTex, commandBuffer: cb, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        guard let pipelineState = ckPipelineState else {
            cb.addCompletedHandler { [weak self] _ in
                if let cg = self?.cgImage(from: pb) {
                    self?.display(cg)
                    self?.lastDisplayedImage = cg
                }
            }
            cb.commit()
            return
        }
        
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: inputTex.pixelFormat, width: w, height: h, mipmapped: false)
        outputDesc.usage = [.shaderRead, .shaderWrite]
        guard let outputTex = metalDevice.makeTexture(descriptor: outputDesc),
              let enc = cb.makeComputeCommandEncoder() else {
            cb.addCompletedHandler { [weak self] _ in
                if let cg = self?.cgImage(from: pb) {
                    self?.display(cg)
                    self?.lastDisplayedImage = cg
                }
            }
            cb.commit()
            return
        }
        
        var uniforms = ChromaKeyUniforms(
            keyR: chromaKeySettings.keyR,
            keyG: chromaKeySettings.keyG,
            keyB: chromaKeySettings.keyB,
            strength: chromaKeySettings.strength,
            softness: chromaKeySettings.softness,
            balance: chromaKeySettings.balance,
            matteShift: chromaKeySettings.matteShift,
            edgeSoftness: chromaKeySettings.edgeSoftness,
            blackClip: chromaKeySettings.blackClip,
            whiteClip: chromaKeySettings.whiteClip,
            spillStrength: chromaKeySettings.spillStrength,
            spillDesat: chromaKeySettings.spillDesat,
            despillBias: chromaKeySettings.despillBias,
            viewMatte: chromaKeySettings.viewMatte ? 1.0 : 0.0,
            width: Float(w),
            height: Float(h),
            padding: 0,
            bgScale: 1,
            bgOffsetX: 0,
            bgOffsetY: 0,
            bgRotationRad: 0,
            bgEnabled: 0,
            interactive: 0,
            lightWrap: chromaKeySettings.lightWrap,
            bgW: 0,
            bgH: 0,
            fillMode: 0,
            outputMode: 1.0
        )
        enc.setComputePipelineState(pipelineState)
        enc.setTexture(inputTex, index: 0)
        enc.setTexture(outputTex, index: 1)
        enc.setTexture(ckFallbackBGTexture, index: 2)
        enc.setBytes(&uniforms, length: MemoryLayout<ChromaKeyUniforms>.stride, index: 0)
        
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroupsPerGrid = MTLSize(
            width: (w + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (h + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        enc.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        enc.endEncoding()
        
        cb.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            if let cgOut = self.convertMetalTextureToCGImage(outputTex) {
                self.display(cgOut)
                self.lastDisplayedImage = cgOut
            } else if let last = self.lastDisplayedImage {
                self.display(last)
            }
        }
        cb.commit()
    }
    
    private func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ci, from: CGRect(x: 0, y: 0, width: w, height: h))
    }
    
    private func convertMetalTextureToCGImage(_ texture: MTLTexture) -> CGImage? {
        guard let ciImage = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpaceCreateDeviceRGB()
        ]) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        return ciContext.createCGImage(ciImage, from: rect)
    }
    
    private func display(_ cg: CGImage) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDestroyed else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.imageLayer.contents = cg
            CATransaction.commit()
        }
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }
    
    deinit {
        isDestroyed = true
        frameTimer?.invalidate()
        frameTimer = nil
        NotificationCenter.default.removeObserver(self)
        player?.pause()
        player = nil
        itemOutput = nil
        if hasSecurityAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

// MARK: - Chroma Key Camera Processor

class ChromaKeyProcessor: NSView {
    private let feed: CameraFeed
    private var chromaKeySettings: PiPChromaKeySettings
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue

    private var imageLayer: CALayer!
    private var frameObservationTimer: Timer?
    private var lastProcessedFrameCount: Int = 0

    private var ckPipelineState: MTLComputePipelineState?
    private var ckFallbackBGTexture: MTLTexture?

    private let processingQueue = DispatchQueue(label: "chromakey.processing", qos: .userInitiated)
    private var isDestroyed = false

    init(feed: CameraFeed, chromaKeySettings: PiPChromaKeySettings, metalDevice: MTLDevice, commandQueue: MTLCommandQueue) {
        self.feed = feed
        self.chromaKeySettings = chromaKeySettings
        self.metalDevice = metalDevice
        self.commandQueue = commandQueue
        super.init(frame: .zero)

        setupLayer()
        setupChromaKeyPipeline()
        setupFrameObservation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupLayer() {
        wantsLayer = true
        imageLayer = CALayer()
        imageLayer.frame = bounds
        imageLayer.backgroundColor = CGColor.black
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.isOpaque = false
        imageLayer.drawsAsynchronously = true
        layer = imageLayer
    }

    private func setupChromaKeyPipeline() {
        guard let library = metalDevice.makeDefaultLibrary(),
              let function = library.makeFunction(name: "chromaKeyKernel") else {
            return
        }

        ckPipelineState = try? metalDevice.makeComputePipelineState(function: function)

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        if let tex = metalDevice.makeTexture(descriptor: desc) {
            var pixel: UInt32 = 0x000000FF
            tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
            ckFallbackBGTexture = tex
        }
    }

    private func setupFrameObservation() {
        frameObservationTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            guard let self = self, !self.isDestroyed else { return }

            let hasNewFrame = self.feed.frameCount != self.lastProcessedFrameCount && self.feed.connectionStatus == .connected
            if hasNewFrame {
                self.lastProcessedFrameCount = self.feed.frameCount
            }

            if self.chromaKeySettings.enabled || hasNewFrame {
                self.updateFrameContent()
            }
        }
    }

    func updateChromaKeySettings(_ newSettings: PiPChromaKeySettings) {
        self.chromaKeySettings = newSettings
        self.updateFrameContent()
    }

    private func updateFrameContent() {
        guard !isDestroyed, let cgImage = feed.previewImage else { return }

        if !chromaKeySettings.enabled {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isDestroyed else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.imageLayer.contents = cgImage
                CATransaction.commit()
            }
            return
        }

        processingQueue.async { [weak self] in
            guard let self = self, !self.isDestroyed else { return }
            let processedImage = self.applyChromaKey(to: cgImage, with: self.chromaKeySettings) ?? cgImage
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isDestroyed else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.imageLayer.contents = processedImage
                CATransaction.commit()
            }
        }
    }
    
    private func applyChromaKey(to cgImage: CGImage, with settings: PiPChromaKeySettings) -> CGImage? {
        guard !isDestroyed,
              let pipelineState = ckPipelineState,
              let fallbackBG = ckFallbackBGTexture else { return nil }
        
        guard let inputTexture = convertCGImageToMetalTexture(cgImage) else { return nil }
        
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: inputTexture.pixelFormat,
            width: inputTexture.width,
            height: inputTexture.height,
            mipmapped: false
        )
        outputDesc.usage = [.shaderRead, .shaderWrite]
        guard let outputTexture = metalDevice.makeTexture(descriptor: outputDesc) else { return nil }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        
        var uniforms = ChromaKeyUniforms(
            keyR: settings.keyR,
            keyG: settings.keyG,
            keyB: settings.keyB,
            strength: settings.strength,
            softness: settings.softness,
            balance: settings.balance,
            matteShift: settings.matteShift,
            edgeSoftness: settings.edgeSoftness,
            blackClip: settings.blackClip,
            whiteClip: settings.whiteClip,
            spillStrength: settings.spillStrength,
            spillDesat: settings.spillDesat,
            despillBias: settings.despillBias,
            viewMatte: settings.viewMatte ? 1.0 : 0.0,
            width: Float(inputTexture.width),
            height: Float(inputTexture.height),
            padding: 0,
            bgScale: 1,
            bgOffsetX: 0,
            bgOffsetY: 0,
            bgRotationRad: 0,
            bgEnabled: 0,
            interactive: 0,
            lightWrap: settings.lightWrap,
            bgW: 0,
            bgH: 0,
            fillMode: 0,
            outputMode: 1.0
        )
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setTexture(fallbackBG, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<ChromaKeyUniforms>.stride, index: 0)
        
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroupsPerGrid = MTLSize(
            width: (inputTexture.width + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (inputTexture.height + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: CGImage?
        
        commandBuffer.addCompletedHandler { _ in
            if !self.isDestroyed {
                result = self.convertMetalTextureToCGImage(outputTexture)
            }
            semaphore.signal()
        }
        
        let timeout = DispatchTime.now() + .milliseconds(100)
        if semaphore.wait(timeout: timeout) == .timedOut {
            return nil
        }
        
        return result
    }
    
    private func convertCGImageToMetalTexture(_ cgImage: CGImage) -> MTLTexture? {
        let textureLoader = MTKTextureLoader(device: metalDevice)
        do {
            return try textureLoader.newTexture(cgImage: cgImage, options: [
                MTKTextureLoader.Option.textureUsage: MTLTextureUsage.shaderRead.rawValue,
                MTKTextureLoader.Option.textureStorageMode: MTLStorageMode.shared.rawValue
            ])
        } catch {
            return nil
        }
    }
    
    private func convertMetalTextureToCGImage(_ texture: MTLTexture) -> CGImage? {
        guard !isDestroyed else { return nil }
        
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: totalBytes, alignment: 64)
        defer { buffer.deallocate() }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(buffer, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        
        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        return context.makeImage()
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }
    
    deinit {
        isDestroyed = true
        frameObservationTimer?.invalidate()
        frameObservationTimer = nil
    }
}

// MARK: - Chroma Key Image Processor

class ChromaKeyImageProcessor: NSView {
    private let originalImage: NSImage
    private var chromaKeySettings: PiPChromaKeySettings
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    private var imageLayer: CALayer!
    private var ckPipelineState: MTLComputePipelineState?
    private var ckFallbackBGTexture: MTLTexture?
    
    private let processingQueue = DispatchQueue(label: "chromakey.image.processing", qos: .userInitiated)
    private var isDestroyed = false
    
    init(image: NSImage, chromaKeySettings: PiPChromaKeySettings, metalDevice: MTLDevice, commandQueue: MTLCommandQueue) {
        self.originalImage = image
        self.chromaKeySettings = chromaKeySettings
        self.metalDevice = metalDevice
        self.commandQueue = commandQueue
        super.init(frame: .zero)
        
        setupLayer()
        setupChromaKeyPipeline()
        updateImageContent()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
    
    private func setupLayer() {
        wantsLayer = true
        imageLayer = CALayer()
        imageLayer.frame = bounds
        imageLayer.backgroundColor = CGColor.black
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.isOpaque = false
        layer = imageLayer
    }
    
    private func setupChromaKeyPipeline() {
        guard let library = metalDevice.makeDefaultLibrary(),
              let function = library.makeFunction(name: "chromaKeyKernel") else {
            return
        }
        
        ckPipelineState = try? metalDevice.makeComputePipelineState(function: function)
        
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        if let tex = metalDevice.makeTexture(descriptor: desc) {
            var pixel: UInt32 = 0x000000FF
            tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
            ckFallbackBGTexture = tex
        }
    }
    
    func updateChromaKeySettings(_ newSettings: PiPChromaKeySettings) {
        if chromaKeySettings != newSettings {
            chromaKeySettings = newSettings
            updateImageContent()
        }
    }
    
    private func updateImageContent() {
        guard !isDestroyed, let cgImage = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        if !chromaKeySettings.enabled {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageLayer.contents = cgImage
            CATransaction.commit()
            return
        }
        
        processingQueue.async { [weak self] in
            guard let self = self, !self.isDestroyed else { return }
            
            let processedImage = self.applyChromaKey(to: cgImage, with: self.chromaKeySettings) ?? cgImage
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isDestroyed else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.imageLayer.contents = processedImage
                CATransaction.commit()
            }
        }
    }
    
    private func applyChromaKey(to cgImage: CGImage, with settings: PiPChromaKeySettings) -> CGImage? {
        guard !isDestroyed,
              let pipelineState = ckPipelineState,
              let fallbackBG = ckFallbackBGTexture else { return nil }
        
        guard let inputTexture = convertCGImageToMetalTexture(cgImage) else { return nil }
        
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: inputTexture.pixelFormat,
            width: inputTexture.width,
            height: inputTexture.height,
            mipmapped: false
        )
        outputDesc.usage = [.shaderRead, .shaderWrite]
        guard let outputTexture = metalDevice.makeTexture(descriptor: outputDesc) else { return nil }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        
        var uniforms = ChromaKeyUniforms(
            keyR: settings.keyR,
            keyG: settings.keyG,
            keyB: settings.keyB,
            strength: settings.strength,
            softness: settings.softness,
            balance: settings.balance,
            matteShift: settings.matteShift,
            edgeSoftness: settings.edgeSoftness,
            blackClip: settings.blackClip,
            whiteClip: settings.whiteClip,
            spillStrength: settings.spillStrength,
            spillDesat: settings.spillDesat,
            despillBias: settings.despillBias,
            viewMatte: settings.viewMatte ? 1.0 : 0.0,
            width: Float(inputTexture.width),
            height: Float(inputTexture.height),
            padding: 0,
            bgScale: 1,
            bgOffsetX: 0,
            bgOffsetY: 0,
            bgRotationRad: 0,
            bgEnabled: 0,
            interactive: 0,
            lightWrap: settings.lightWrap,
            bgW: 0,
            bgH: 0,
            fillMode: 0,
            outputMode: 1.0
        )
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setTexture(fallbackBG, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<ChromaKeyUniforms>.stride, index: 0)
        
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroupsPerGrid = MTLSize(
            width: (inputTexture.width + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (inputTexture.height + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: CGImage?
        
        commandBuffer.addCompletedHandler { _ in
            if !self.isDestroyed {
                result = self.convertMetalTextureToCGImage(outputTexture)
            }
            semaphore.signal()
        }
        
        let timeout = DispatchTime.now() + .milliseconds(100)
        if semaphore.wait(timeout: timeout) == .timedOut {
            return nil
        }
        
        return result
    }
    
    private func convertCGImageToMetalTexture(_ cgImage: CGImage) -> MTLTexture? {
        let textureLoader = MTKTextureLoader(device: metalDevice)
        do {
            return try textureLoader.newTexture(cgImage: cgImage, options: [
                MTKTextureLoader.Option.textureUsage: MTLTextureUsage.shaderRead.rawValue,
                MTKTextureLoader.Option.textureStorageMode: MTLStorageMode.shared.rawValue
            ])
        } catch {
            return nil
        }
    }
    
    private func convertMetalTextureToCGImage(_ texture: MTLTexture) -> CGImage? {
        guard !isDestroyed else { return nil }
        
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: totalBytes, alignment: 64)
        defer { buffer.deallocate() }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(buffer, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        
        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        return context.makeImage()
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }
    
    deinit {
        isDestroyed = true
    }
}

// MARK: - Chroma Key Uniforms (processors)

private struct ChromaKeyUniforms {
    let keyR: Float
    let keyG: Float
    let keyB: Float
    let strength: Float
    let softness: Float
    let balance: Float
    let matteShift: Float
    let edgeSoftness: Float
    let blackClip: Float
    let whiteClip: Float
    let spillStrength: Float
    let spillDesat: Float
    let despillBias: Float
    let viewMatte: Float
    let width: Float
    let height: Float
    let padding: Float
    let bgScale: Float
    let bgOffsetX: Float
    let bgOffsetY: Float
    let bgRotationRad: Float
    let bgEnabled: Float
    let interactive: Float
    let lightWrap: Float
    let bgW: Float
    let bgH: Float
    let fillMode: Float
    let outputMode: Float
}