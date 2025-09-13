import SwiftUI
import AppKit
import Metal
import MetalKit

struct CompositedLayersContent: View {
    @EnvironmentObject var layerManager: LayerStackManager
    @ObservedObject var productionManager: UnifiedProductionManager
    
    // Add Metal device and chroma key pipeline for processing
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
                ForEach(layerManager.layers.sorted(by: { $0.zIndex < $1.zIndex })) { model in
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
                ChromaKeyAwareCameraView(
                    feed: feed, 
                    chromaKeySettings: model.chromaKey,
                    metalDevice: metalDevice,
                    commandQueue: commandQueue
                )
                .background(Color.black)
                .id("camera-\(feedId)-\(model.chromaKey.enabled)-\(model.chromaKey.keyR)-\(model.chromaKey.keyG)-\(model.chromaKey.keyB)")
            } else {
                Color.black.overlay(
                    Text("Camera offline").font(.caption).foregroundColor(.white)
                )
            }

        case .media(let file):
            switch file.fileType {
            case .image:
                if let img = NSImage(contentsOf: file.url) {
                    ChromaKeyAwareImageView(
                        image: img,
                        chromaKeySettings: model.chromaKey,
                        metalDevice: metalDevice,
                        commandQueue: commandQueue
                    )
                    .background(Color.black)
                    .id("image-\(file.id)-\(model.chromaKey.enabled)-\(model.chromaKey.keyR)-\(model.chromaKey.keyG)-\(model.chromaKey.keyB)")
                } else {
                    Color.black.overlay(
                        Text("Image not found").font(.caption).foregroundColor(.white)
                    )
                }
            case .video:
                // For now, keep using the existing video player - chroma key for video would require more complex integration
                LayerAVPlayerView(url: file.url, isMuted: true, autoplay: true, loop: true, layerId: model.id)
                    .environmentObject(layerManager)
                    .background(Color.black)
            case .audio:
                Color.clear
            }

        case .title(let overlay):
            if layerManager.editingLayerID == model.id {
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

// MARK: - Chrome Key Processor Classes

class ChromaKeyProcessor: NSView {
    private let feed: CameraFeed
    private var chromaKeySettings: PiPChromaKeySettings
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    private var imageLayer: CALayer!
    private var frameObservationTimer: Timer?
    private var lastProcessedFrameCount: Int = 0
    
    // Chroma key pipeline state
    private var ckPipelineState: MTLComputePipelineState?
    private var ckFallbackBGTexture: MTLTexture?
    
    // Processing queue and safety
    private let processingQueue = DispatchQueue(label: "chromakey.processing", qos: .userInitiated)
    private var isDestroyed = false
    private var needsReprocessing = false
    
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
            print("❌ Failed to load chromaKeyKernel function")
            return
        }
        
        do {
            ckPipelineState = try metalDevice.makeComputePipelineState(function: function)
        } catch {
            print("❌ Failed to create chroma key pipeline state: \(error)")
        }
        
        // Create fallback background texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        if let tex = metalDevice.makeTexture(descriptor: desc) {
            var pixel: UInt32 = 0x000000FF // Black with full alpha
            tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
            ckFallbackBGTexture = tex
        }
    }
    
    private func setupFrameObservation() {
        frameObservationTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            guard let self = self,
                  !self.isDestroyed else { return }
            
            // Process if we have a new frame OR if settings changed
            let hasNewFrame = self.feed.frameCount != self.lastProcessedFrameCount && self.feed.connectionStatus == .connected
            
            if hasNewFrame || self.needsReprocessing {
                self.lastProcessedFrameCount = self.feed.frameCount
                self.needsReprocessing = false
                self.updateFrameContent()
            }
        }
    }
    
    func updateChromaKeySettings(_ newSettings: PiPChromaKeySettings) {
        // Only update if settings actually changed
        if chromaKeySettings != newSettings {
            chromaKeySettings = newSettings
            needsReprocessing = true
            print("🎨 ChromaKeyProcessor: Settings updated, flagging for reprocessing")
        }
    }
    
    private func updateFrameContent() {
        guard !isDestroyed, let cgImage = feed.previewImage else { return }
        
        // If chroma key is not enabled, just display the original image
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
        
        // Apply chroma key asynchronously
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
        
        // Convert CGImage to Metal texture
        guard let inputTexture = convertCGImageToMetalTexture(cgImage) else { return nil }
        
        // Create output texture
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: inputTexture.pixelFormat,
            width: inputTexture.width,
            height: inputTexture.height,
            mipmapped: false
        )
        outputDesc.usage = [.shaderRead, .shaderWrite]
        guard let outputTexture = metalDevice.makeTexture(descriptor: outputDesc) else { return nil }
        
        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        
        // Set up uniforms
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
            outputMode: 1.0 // Premultiplied alpha output for PiP
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
        
        // IMPORTANT: Submit asynchronously, don't wait!
        commandBuffer.commit()
        
        // Use a semaphore with timeout instead of blocking wait
        let semaphore = DispatchSemaphore(value: 0)
        var result: CGImage?
        
        commandBuffer.addCompletedHandler { _ in
            if !self.isDestroyed {
                result = self.convertMetalTextureToCGImage(outputTexture)
            }
            semaphore.signal()
        }
        
        // Wait with timeout to avoid blocking indefinitely
        let timeout = DispatchTime.now() + .milliseconds(100)
        if semaphore.wait(timeout: timeout) == .timedOut {
            print("⚠️ Chroma key processing timed out")
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
            print("❌ Failed to convert CGImage to Metal texture: \(error)")
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
    
    // Processing queue and safety
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
            print("❌ Failed to load chromaKeyKernel function")
            return
        }
        
        do {
            ckPipelineState = try metalDevice.makeComputePipelineState(function: function)
        } catch {
            print("❌ Failed to create chroma key pipeline state: \(error)")
        }
        
        // Create fallback background texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        if let tex = metalDevice.makeTexture(descriptor: desc) {
            var pixel: UInt32 = 0x000000FF // Black with full alpha
            tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
            ckFallbackBGTexture = tex
        }
    }
    
    func updateChromaKeySettings(_ newSettings: PiPChromaKeySettings) {
        // Only update if settings actually changed
        if chromaKeySettings != newSettings {
            chromaKeySettings = newSettings
            updateImageContent()
            print("🎨 ChromaKeyImageProcessor: Settings updated, reprocessing image")
        }
    }
    
    private func updateImageContent() {
        guard !isDestroyed, let cgImage = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        // If chroma key is not enabled, just display the original image
        if !chromaKeySettings.enabled {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageLayer.contents = cgImage
            CATransaction.commit()
            return
        }
        
        // Apply chroma key asynchronously
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
        
        // Convert CGImage to Metal texture
        guard let inputTexture = convertCGImageToMetalTexture(cgImage) else { return nil }
        
        // Create output texture
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: inputTexture.pixelFormat,
            width: inputTexture.width,
            height: inputTexture.height,
            mipmapped: false
        )
        outputDesc.usage = [.shaderRead, .shaderWrite]
        guard let outputTexture = metalDevice.makeTexture(descriptor: outputDesc) else { return nil }
        
        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        
        // Set up uniforms (same as camera processor)
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
            outputMode: 1.0 // Premultiplied alpha output for PiP
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
        
        // IMPORTANT: Submit asynchronously, don't wait!
        commandBuffer.commit()
        
        // Use a semaphore with timeout instead of blocking wait
        let semaphore = DispatchSemaphore(value: 0)
        var result: CGImage?
        
        commandBuffer.addCompletedHandler { _ in
            if !self.isDestroyed {
                result = self.convertMetalTextureToCGImage(outputTexture)
            }
            semaphore.signal()
        }
        
        // Wait with timeout to avoid blocking indefinitely
        let timeout = DispatchTime.now() + .milliseconds(100)
        if semaphore.wait(timeout: timeout) == .timedOut {
            print("⚠️ Chroma key processing timed out")
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
            print("❌ Failed to convert CGImage to Metal texture: \(error)")
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

// MARK: - Chroma Key Uniforms Structure

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