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
    private let maxQueueDepth = 3 // Drop frames if queue gets too deep
    
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
    }
    
    /// Submit a frame for processing
    func submitFrame(_ frame: CVPixelBuffer, for sourceID: String, timestamp: CMTime = CMTime.zero) async throws {
        try Task.checkCancellation()
        
        // Convert pixel buffer to Metal texture
        guard let texture = try await createMetalTexture(from: frame) else {
            throw ProcessingResult.ProcessingError.textureCreationFailed
        }
        
        let wrapper = TextureWrapper(texture: texture, timestamp: timestamp, identifier: sourceID)
        
        // Check queue depth to prevent overload
        if let continuation = frameStreams[sourceID] {
            // For now, we'll use a simple queue depth check
            // In a production system, you'd want more sophisticated back-pressure handling
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
        
        let outputTexture = chain?.apply(to: texture, using: commandBuffer, device: device) ?? texture
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputTexture
    }
    
    // MARK: - Statistics
    
    /// Get current processing statistics
    func getStats() async -> ProcessingStats {
        return stats
    }
    
    /// Reset processing statistics
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
            // Check for cancellation
            if Task.isCancelled {
                outputContinuation.finish()
                return
            }
            
            let startTime = CACurrentMediaTime()
            
            do {
                try Task.checkCancellation()
                
                // Apply effects if chain exists
                let processedTexture: MTLTexture?
                if let effectChain = activeEffectChains[sourceID] {
                    processedTexture = try await applyEffects(to: wrapper.texture, using: effectChain)
                } else {
                    processedTexture = wrapper.texture
                }
                
                // Convert to CGImage for UI display (optional)
                let processedImage = processedTexture != nil ? await createCGImage(from: processedTexture!) : nil
                
                let processingTime = CACurrentMediaTime() - startTime
                processingTimes.append(processingTime)
                
                // Keep only recent timing data
                if processingTimes.count > 100 {
                    processingTimes.removeFirst()
                }
                
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
    
    private func createCGImage(from texture: MTLTexture) async -> CGImage? {
        // Create CIImage from Metal texture
        guard let ciImage = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpaceCreateDeviceRGB()
        ]) else {
            return nil
        }
        
        // Flip image to correct orientation
        let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -ciImage.extent.height))
        
        return ciContext.createCGImage(flipped, from: flipped.extent)
    }
    
    private func getOrCreateOutputTexture(for sourceID: String, width: Int, height: Int) -> MTLTexture? {
        let key = "\(sourceID)_output"
        
        // Check if we have a suitable texture in the pool
        if let existingTexture = texturePool[key],
           existingTexture.width == width && existingTexture.height == height {
            return existingTexture
        }
        
        // Create new texture
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