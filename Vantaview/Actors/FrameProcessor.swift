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
import os

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
    
    private static let log = OSLog(subsystem: "com.vantaview", category: "FrameProcessor")
    
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
    private let maxQueueDepth = 3
    
    // MARK: - Texture Management
    
    private var textureCache: CVMetalTextureCache?
    private var texturePool: [String: [MTLTexture]] = [:]
    private var ringIndex: [String: Int] = [:]
    
    init(device: MTLDevice, effectManager: EffectManager) async throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw ProcessingResult.ProcessingError.metalDeviceUnavailable
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.effectManager = effectManager
        
        self.ciContext = CIContext(
            mtlDevice: device,
            options: [
                .cacheIntermediates: false,
                .workingColorSpace: CGColorSpaceCreateDeviceRGB()
            ]
        )
        
        CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        )
    }
    
    // MARK: - Frame Stream Management
    
    func createFrameStream(for sourceID: String, effectChain: EffectChain?) async -> AsyncStream<ProcessingResult> {
        await stopFrameStream(for: sourceID)
        
        if let effectChain = effectChain {
            activeEffectChains[sourceID] = effectChain
        }
        
        let (stream, continuation) = AsyncStream<ProcessingResult>.makeStream()
        let (inputStream, inputContinuation) = AsyncStream<TextureWrapper>.makeStream()
        frameStreams[sourceID] = inputContinuation
        
        processingTasks[sourceID] = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.processFrameStream(sourceID: sourceID, inputStream: inputStream, outputContinuation: continuation)
        }
        
        return stream
    }
    
    func stopFrameStream(for sourceID: String) async {
        frameStreams[sourceID]?.finish()
        frameStreams.removeValue(forKey: sourceID)
        
        processingTasks[sourceID]?.cancel()
        processingTasks.removeValue(forKey: sourceID)
        
        activeEffectChains.removeValue(forKey: sourceID)
        
        texturePool.removeValue(forKey: sourceID)
        ringIndex.removeValue(forKey: sourceID)
        
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }
    
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
    
    func submitTexture(_ texture: MTLTexture, for sourceID: String, timestamp: CMTime = CMTime.zero) async throws {
        try Task.checkCancellation()
        
        let wrapper = TextureWrapper(texture: texture, timestamp: timestamp, identifier: sourceID)
        
        if let continuation = frameStreams[sourceID] {
            continuation.yield(wrapper)
        }
    }
    
    // MARK: - Effect Management
    
    func updateEffectChain(for sourceID: String, chain: EffectChain?) async {
        if let chain = chain {
            activeEffectChains[sourceID] = chain
        } else {
            activeEffectChains.removeValue(forKey: sourceID)
        }
    }
    
    // GPU-first: no CPU busy-wait. Return immediately after commit; downstream must not CPU-read.
    func applyEffects(to texture: MTLTexture, using chain: EffectChain?) async throws -> MTLTexture? {
        try Task.checkCancellation()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ProcessingResult.ProcessingError.metalDeviceUnavailable
        }
        commandBuffer.label = "FrameProcessor.applyEffects"
        
        let outputTexture = chain?.apply(to: texture, using: commandBuffer, device: device) ?? texture
        
        commandBuffer.addCompletedHandler { _ in
            // No-op: completion used to avoid busy-wait; consumers render on GPU later.
        }
        commandBuffer.commit()
        
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
            let spid = OSSignpostID(log: Self.log)
            os_signpost(.begin, log: Self.log, name: "ProcessFrame", signpostID: spid, "source=%{public}s", sourceID)
            
            do {
                try Task.checkCancellation()
                
                let processedTexture: MTLTexture?
                if let effectChain = activeEffectChains[sourceID] {
                    processedTexture = try await applyEffects(to: wrapper.texture, using: effectChain)
                } else {
                    processedTexture = wrapper.texture
                }
                
                let processedImage: CGImage? = nil
                
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
                
                os_signpost(.end, log: Self.log, name: "ProcessFrame", signpostID: spid, "ok=1 dt=%.2fms", processingTime * 1000.0)
                
            } catch is CancellationError {
                let dt = CACurrentMediaTime() - startTime
                let result = ProcessingResult(
                    outputTexture: nil,
                    processedImage: nil,
                    processingTime: dt,
                    error: .cancelled
                )
                outputContinuation.yield(result)
                os_signpost(.end, log: Self.log, name: "ProcessFrame", signpostID: spid, "cancel=1 dt=%.2fms", dt * 1000.0)
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
                os_signpost(.end, log: Self.log, name: "ProcessFrame", signpostID: spid, "error=1 dt=%.2fms", processingTime * 1000.0)
            }
        }
        
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
        texturePool.removeValue(forKey: sourceID)
        ringIndex.removeValue(forKey: sourceID)
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
    
    private func getOrCreateOutputTexture(for sourceID: String, width: Int, height: Int) -> MTLTexture? {
        var ring = texturePool[sourceID] ?? []
        var idx = ringIndex[sourceID] ?? 0
        
        if ring.isEmpty || ring.first?.width != width || ring.first?.height != height {
            ring.removeAll()
            for _ in 0..<3 {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                descriptor.usage = [.shaderRead, .shaderWrite]
                if let texture = device.makeTexture(descriptor: descriptor) {
                    ring.append(texture)
                }
            }
            idx = 0
        }
        
        guard !ring.isEmpty else { return nil }
        let tex = ring[idx]
        idx = (idx + 1) % ring.count
        texturePool[sourceID] = ring
        ringIndex[sourceID] = idx
        
        return tex
    }
}

// MARK: - Sendable Conformance

extension EffectChain: @unchecked Sendable {}
extension EffectManager: @unchecked Sendable {}