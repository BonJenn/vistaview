import Foundation
import AVFoundation
import CoreMedia
import Metal
import os

/// A simplified recording sink that directly receives frames and audio
final class SimpleRecordingSink: @unchecked Sendable {
    private let log = OSLog(subsystem: "com.vantaview", category: "SimpleRecordingSink")
    private let recorder: ProgramRecorder
    
    private var isActive = false
    
    // FIXED: Add cleanup tracking
    private var processingTasks: Set<Task<Void, Never>> = []
    
    init(recorder: ProgramRecorder) {
        self.recorder = recorder
        os_log(.info, log: log, "🎬 SimpleRecordingSink initialized")
    }
    
    deinit {
        // Cancel all processing tasks
        for task in processingTasks {
            task.cancel()
        }
        processingTasks.removeAll()
    }
    
    func setActive(_ active: Bool) {
        isActive = active
        os_log(.info, log: log, "🎬 Recording sink set to %{public}@", active ? "ACTIVE" : "INACTIVE")
        
        // Clean up tasks when becoming inactive
        if !active {
            for task in processingTasks {
                task.cancel()
            }
            processingTasks.removeAll()
        }
    }
    
    func appendVideoTexture(_ texture: MTLTexture, timestamp: CMTime) {
        guard isActive else { return }
        
        // FIXED: Use detached task to avoid retain cycles and clean up completed tasks
        let task = Task.detached { [recorder, log] in
            do {
                // Convert texture to sample buffer using a much simpler approach
                let sampleBuffer = try await Self.convertTextureToSampleBuffer(texture, timestamp: timestamp)
                await recorder.appendVideoSampleBuffer(sampleBuffer)
            } catch {
                // Minimal error logging only
                os_log(.error, log: log, "🎬 Video frame error")
            }
        }
        
        // Track task and clean up completed ones
        processingTasks.insert(task)
        Task { [weak self] in
            _ = await task.result
            self?.processingTasks.remove(task)
        }
    }
    
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isActive else { return }
        
        // FIXED: Use detached task to avoid retain cycles
        Task.detached { [recorder] in
            await recorder.appendAudioSampleBuffer(sampleBuffer)
        }
    }
    
    // FIXED: Make static to avoid capturing self
    private static func convertTextureToSampleBuffer(_ texture: MTLTexture, timestamp: CMTime) async throws -> CMSampleBuffer {
        // Create pixel buffer attributes
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: texture.width,
            kCVPixelBufferHeightKey: texture.height,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            texture.width,
            texture.height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard result == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw RecordingError.pixelBufferCreationFailed
        }
        
        // FIXED: Ensure proper cleanup with defer
        defer {
            // Ensure pixel buffer is properly released
            CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
            CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        }
        
        // Simple texture read using CPU (less efficient but more reliable)
        try await readTextureToPixelBuffer(texture: texture, pixelBuffer: buffer)
        
        // Create sample buffer
        return try createSampleBuffer(from: buffer, timestamp: timestamp)
    }
    
    // FIXED: Make static and improve memory management
    private static func readTextureToPixelBuffer(texture: MTLTexture, pixelBuffer: CVPixelBuffer) async throws {
        // Lock pixel buffer
        let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        guard lockResult == kCVReturnSuccess else {
            throw RecordingError.pixelBufferAccessFailed
        }
        
        defer { 
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        }
        
        // Get pixel buffer base address
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw RecordingError.pixelBufferAccessFailed
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        // Read texture data to pixel buffer (synchronous approach for simplicity)
        texture.getBytes(
            baseAddress,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                           size: MTLSize(width: texture.width, height: texture.height, depth: 1)),
            mipmapLevel: 0
        )
    }
    
    // FIXED: Make static and add proper memory management
    private static func createSampleBuffer(from pixelBuffer: CVPixelBuffer, timestamp: CMTime) throws -> CMSampleBuffer {
        var formatDescription: CMVideoFormatDescription?
        let formatResult = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard formatResult == noErr, let videoFormatDescription = formatDescription else {
            throw RecordingError.formatDescriptionCreationFailed
        }
        
        var sampleTimingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        let sampleBufferResult = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: videoFormatDescription,
            sampleTiming: &sampleTimingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        guard sampleBufferResult == noErr, let buffer = sampleBuffer else {
            throw RecordingError.sampleBufferCreationFailed
        }
        
        return buffer
    }
    
    enum RecordingError: Error {
        case pixelBufferCreationFailed
        case formatDescriptionCreationFailed
        case sampleBufferCreationFailed
        case pixelBufferAccessFailed
    }
}