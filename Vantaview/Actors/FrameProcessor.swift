//
//  FrameProcessor.swift
//  Vantaview
//
//  Frame processing actor for handling video frames, effects, and Metal rendering off the main thread
//

import Foundation
import Metal
import MetalKit
import CoreVideo
import CoreImage
import AVFoundation

/// Sendable wrapper for Metal textures to safely pass between actors
struct TextureWrapper: Sendable {
    let texture: MTLTexture
    let timestamp: CMTime
    let size: CGSize
    let identifier: String
    
    init(texture: MTLTexture, timestamp: CMTime = CMTime.zero, identifier: String = UUID().uuidString) {
        self.texture = texture
        self.timestamp = timestamp
        self.size = CGSize(width: texture.width, height: texture.height)
        self.identifier = identifier
    }
}

/// Result of frame processing operations
struct ProcessingResult: Sendable {
    let outputTexture: MTLTexture?
    let processedImage: CGImage?
    let processingTime: TimeInterval
    let error: ProcessingError?
    
    enum ProcessingError: Error, Sendable {
        case metalDeviceUnavailable
        case textureCreationFailed
        case effectApplicationFailed(String)
        case cancelled
    }
}

/// Frame processing statistics
struct ProcessingStats: Sendable {
    let framesProcessed: Int
    let averageProcessingTime: TimeInterval
    let droppedFrames: Int
    let queueDepth: Int
}

/// Actor responsible for video frame processing, effects application, and Metal rendering
actor FrameProcessor {
    
    // MARK: - Core Dependencies
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let effectManager: EffectManager
    
    // MARK: - Processing Pipeline
    
    private var frameStreams: [String: AsyncStream<TextureWrapper>.Continuation] = [:]
    private var processingTasks: [String: Task<Void, Never>] = [:]
    private var activeEffectChains: [String: EffectChain] = [:]
    
    // MARK: - Statistics and Performance
    
    private var stats = ProcessingStats(framesProcessed: 0, averageProcessingTime: 0, droppedFrames: 0, queueDepth: 0)
    private var processingTimes: [TimeInterval] = []
    private let maxQueueDepth = 3 // Potential future back-pressure control
    
    // MARK: - Texture Management
    
    private var textureCache: CVMetalTextureCache?
    private var texturePool: [String: MTLTexture] = [:] // Reuse textures to avoid allocations
    
    init(device: MTLDevice, effectManager: EffectManager) async throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw ProcessingResult.ProcessingError.metalDeviceUnavailable
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.effectManager = effectManager
        
        // Create optimized CIContext for frame processing
        self.ciContext = CIContext(
            mtlDevice: device,
            options: [
                .cacheIntermediates: false,
                .workingColorSpace: CGColorSpaceCreateDeviceRGB()
            ]
        )
        
        // Initialize texture cache
        CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        )
    }
    
    // MARK: - Frame Stream Management
    
    /// Create a frame processing stream for a specific source
    func createFrameStream(for sourceID: String, effectChain: EffectChain?) async -> AsyncStream<ProcessingResult> {
        // Cancel existing stream if present
        await stopFrameStream(for: sourceID)
        
        // Store effect chain for this source
        if let effectChain = effectChain {
            activeEffectChains[sourceID] = effectChain
        }
        
        let (stream, continuation) = AsyncStream<ProcessingResult>.makeStream()
        
        // Create input stream
        let (inputStream, inputContinuation) = AsyncStream<TextureWrapper>.makeStream()
        frameStreams[sourceID] = inputContinuation
        
        // Start processing task
        processingTasks[sourceID] = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.processFrameStream(sourceID: sourceID, inputStream: inputStream, outputContinuation: continuation)
        }
        
        return stream
    }
    
    /// Stop frame processing for a specific source
    func stopFrameStream(for sourceID: String) async {
        frameStreams[sourceID]?.finish()
        frameStreams.removeValue(forKey: sourceID)
        
        processingTasks[sourceID]?.cancel()
        processingTasks.removeValue(forKey: sourceID)
        
        activeEffectChains.removeValue(forKey: sourceID)
        
        // Clean up texture pool for this source
        texturePool.removeValue(forKey: "\(sourceID)_output")
        
        // Periodically flush the CVMetalTextureCache to free transient CVMetalTextures
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }
    
    /// Submit a frame for processing
    func submitFrame(_ frame: CVPixelBuffer, for sourceID: String, timestamp: CMTime = CMTime.zero) async throws {
        try Task.checkCancellation()
        
        guard let texture = try await createMetalTexture(from: frame) else {
            throw ProcessingResult.ProcessingError.textureCreationFailed
        }
        
        let wrapper = TextureWrapper(texture: texture, timestamp: timestamp, identifier: sourceID)
        
        if let continuation = frameStreams[sourceID] {
            continuation.yield(wrapper)
        }
    }
    
    /// Submit a Metal texture directly for processing
    func submitTexture(_ texture: MTLTexture, for sourceID: String, timestamp: CMTime = CMTime.zero) async throws {
        try Task.checkCancellation()
        
        let wrapper = TextureWrapper(texture: texture, timestamp: timestamp, identifier: sourceID)
        
        if let continuation = frameStreams[sourceID] {
            continuation.yield(wrapper)
        }
    }
    
    // MARK: - Effect Management
    
    /// Update the effect chain for a specific source
    func updateEffectChain(for sourceID: String, chain: EffectChain?) async {
        if let chain = chain {
            activeEffectChains[sourceID] = chain
        } else {
            activeEffectChains.removeValue(forKey: sourceID)
        }
    }
    
    /// Apply effects to a texture synchronously (for one-off processing)
    func applyEffects(to texture: MTLTexture, using chain: EffectChain?) async throws -> MTLTexture? {
        try Task.checkCancellation()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ProcessingResult.ProcessingError.metalDeviceUnavailable
        }
        commandBuffer.label = "FrameProcessor.applyEffects"
        
        let outputTexture = chain?.apply(to: texture, using: commandBuffer, device: device) ?? texture
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputTexture
    }
    
    // MARK: - Statistics
    
    func getStats() async -> ProcessingStats {
        return stats
    }
    
    func resetStats() async {
        stats = ProcessingStats(framesProcessed: 0, averageProcessingTime: 0, droppedFrames: 0, queueDepth: 0)
        processingTimes.removeAll()
    }
    
    // MARK: - Private Implementation
    
    private func processFrameStream(
        sourceID: String,
        inputStream: AsyncStream<TextureWrapper>,
        outputContinuation: AsyncStream<ProcessingResult>.Continuation
    ) async {
        var droppedFrames = 0
        var processedFrames = 0
        
        for await wrapper in inputStream {
            if Task.isCancelled {
                outputContinuation.finish()
                return
            }
            
            let startTime = CACurrentMediaTime()
            
            do {
                try Task.checkCancellation()
                
                // Apply effects if chain exists (can suspend)
                let processedTexture: MTLTexture?
                if let effectChain = activeEffectChains[sourceID] {
                    processedTexture = try await applyEffects(to: wrapper.texture, using: effectChain)
                } else {
                    processedTexture = wrapper.texture
                }
                
                // Do not produce per-frame CGImages for streaming playback
                let processedImage: CGImage? = nil
                
                // Use an autoreleasepool only around sync work (no awaits inside)
                let processingTime: TimeInterval = autoreleasepool {
                    CACurrentMediaTime() - startTime
                }
                
                processingTimes.append(processingTime)
                if processingTimes.count > 100 { processingTimes.removeFirst() }
                processedFrames += 1
                
                let result = ProcessingResult(
                    outputTexture: processedTexture,
                    processedImage: processedImage,
                    processingTime: processingTime,
                    error: nil
                )
                
                outputContinuation.yield(result)
                
            } catch is CancellationError {
                let result = ProcessingResult(
                    outputTexture: nil,
                    processedImage: nil,
                    processingTime: CACurrentMediaTime() - startTime,
                    error: .cancelled
                )
                outputContinuation.yield(result)
                break
            } catch {
                droppedFrames += 1
                let processingTime = CACurrentMediaTime() - startTime
                
                let result = ProcessingResult(
                    outputTexture: nil,
                    processedImage: nil,
                    processingTime: processingTime,
                    error: .effectApplicationFailed(error.localizedDescription)
                )
                
                outputContinuation.yield(result)
            }
        }
        
        // Update statistics
        let avgTime = processingTimes.isEmpty ? 0 : processingTimes.reduce(0, +) / Double(processingTimes.count)
        stats = ProcessingStats(
            framesProcessed: processedFrames,
            averageProcessingTime: avgTime,
            droppedFrames: droppedFrames,
            queueDepth: frameStreams.count
        )
        
        outputContinuation.finish()
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
        texturePool.removeValue(forKey: "\(sourceID)_output")
    }
    
    private func createMetalTexture(from pixelBuffer: CVPixelBuffer) async throws -> MTLTexture? {
        guard let textureCache = textureCache else {
            throw ProcessingResult.ProcessingError.metalDeviceUnavailable
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard status == kCVReturnSuccess, let cvTexture = cvTexture else {
            throw ProcessingResult.ProcessingError.textureCreationFailed
        }
        
        return CVMetalTextureGetTexture(cvTexture)
    }
    
    // Retained for one-off stills only (not used for streaming playback now)
    private func createCGImage(from texture: MTLTexture) async -> CGImage? {
        guard let ciImage = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpaceCreateDeviceRGB()
        ]) else {
            return nil
        }
        
        let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -ciImage.extent.height))
        return ciContext.createCGImage(flipped, from: flipped.extent)
    }
    
    private func getOrCreateOutputTexture(for sourceID: String, width: Int, height: Int) -> MTLTexture? {
        let key = "\(sourceID)_output"
        
        if let existingTexture = texturePool[key],
           existingTexture.width == width && existingTexture.height == height {
            return existingTexture
        }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        let texture = device.makeTexture(descriptor: descriptor)
        texturePool[key] = texture
        
        return texture
    }
}

// MARK: - Sendable Conformance

extension EffectChain: @unchecked Sendable {}
extension EffectManager: @unchecked Sendable {}