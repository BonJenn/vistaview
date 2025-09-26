import Foundation
import Metal
import AVFoundation
import CoreVideo
import CoreMedia

actor TextureToSampleBufferConverter {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private let pixelBufferPool: CVPixelBufferPool
    
    // Video format configuration
    private let targetWidth: Int
    private let targetHeight: Int
    // Use BGRA format directly instead of NV12 to avoid complex color space conversion
    private let pixelFormat: OSType = kCVPixelFormatType_32BGRA
    
    init(device: MTLDevice, targetWidth: Int = 1920, targetHeight: Int = 1080) throws {
        self.device = device
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
        
        guard let commandQueue = device.makeCommandQueue() else {
            throw ConversionError.deviceError("Failed to create command queue")
        }
        self.commandQueue = commandQueue
        
        var textureCache: CVMetalTextureCache?
        let textureCacheResult = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        )
        
        guard textureCacheResult == kCVReturnSuccess, let cache = textureCache else {
            throw ConversionError.textureCacheCreationFailed
        }
        self.textureCache = cache
        
        // Create pixel buffer pool for efficient buffer reuse
        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 3,
            kCVPixelBufferPoolMaximumBufferAgeKey: 0
        ]
        
        let pixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: targetWidth,
            kCVPixelBufferHeightKey: targetHeight,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        
        var pixelBufferPool: CVPixelBufferPool?
        let poolResult = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pixelBufferPool
        )
        
        guard poolResult == kCVReturnSuccess, let pool = pixelBufferPool else {
            throw ConversionError.pixelBufferPoolCreationFailed
        }
        self.pixelBufferPool = pool
        
        print("🎬 TextureConverter: Initialized for \(targetWidth)x\(targetHeight) BGRA")
    }
    
    /// Convert MTLTexture to CMSampleBuffer
    func convertTexture(_ texture: MTLTexture, timestamp: CMTime, duration: CMTime = CMTime(value: 1, timescale: 30)) async throws -> CMSampleBuffer {
        try Task.checkCancellation()
        
        print("🎬 TextureConverter: Converting texture \(texture.width)x\(texture.height) at timestamp \(timestamp.seconds)")
        
        // Get pixel buffer from pool
        var pixelBuffer: CVPixelBuffer?
        let pixelBufferResult = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pixelBufferPool,
            &pixelBuffer
        )
        
        guard pixelBufferResult == kCVReturnSuccess, let outputPixelBuffer = pixelBuffer else {
            throw ConversionError.pixelBufferCreationFailed
        }
        
        // Lock pixel buffer for GPU access
        CVPixelBufferLockBaseAddress(outputPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(outputPixelBuffer, CVPixelBufferLockFlags(rawValue: 0)) }
        
        // Copy texture data directly to pixel buffer
        try await copyTextureToBGRAPixelBuffer(
            sourceTexture: texture,
            destinationPixelBuffer: outputPixelBuffer
        )
        
        // Create sample buffer from pixel buffer
        let sampleBuffer = try createSampleBuffer(
            from: outputPixelBuffer,
            timestamp: timestamp,
            duration: duration
        )
        
        print("🎬 TextureConverter: Successfully converted texture to sample buffer")
        return sampleBuffer
    }
    
    private func copyTextureToBGRAPixelBuffer(sourceTexture: MTLTexture, destinationPixelBuffer: CVPixelBuffer) async throws {
        // Create Metal texture from the BGRA pixel buffer
        let destinationTexture = try createMetalTexture(
            from: destinationPixelBuffer,
            planeIndex: 0,
            pixelFormat: .bgra8Unorm
        )
        
        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ConversionError.commandBufferCreationFailed
        }
        
        // Use blit encoder to copy directly
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw ConversionError.encoderCreationFailed
        }
        
        // Calculate copy dimensions (handle different sizes)
        let copyWidth = min(sourceTexture.width, destinationTexture.width)
        let copyHeight = min(sourceTexture.height, destinationTexture.height)
        
        print("🎬 TextureConverter: Copying \(copyWidth)x\(copyHeight) from \(sourceTexture.width)x\(sourceTexture.height) to \(destinationTexture.width)x\(destinationTexture.height)")
        
        // Copy texture data
        blitEncoder.copy(
            from: sourceTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: copyWidth, height: copyHeight, depth: 1),
            to: destinationTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        
        blitEncoder.endEncoding()
        
        // Commit and wait for completion
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        if let error = commandBuffer.error {
            throw ConversionError.metalComputeError(error.localizedDescription)
        }
        
        print("🎬 TextureConverter: Texture copy completed successfully")
    }
    
    private func createMetalTexture(from pixelBuffer: CVPixelBuffer, planeIndex: Int, pixelFormat: MTLPixelFormat) throws -> MTLTexture {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var metalTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            planeIndex,
            &metalTexture
        )
        
        guard result == kCVReturnSuccess,
              let texture = metalTexture,
              let mtlTexture = CVMetalTextureGetTexture(texture) else {
            print("🎬 TextureConverter: Failed to create Metal texture - result: \(result)")
            throw ConversionError.metalTextureCreationFailed
        }
        
        return mtlTexture
    }
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer, timestamp: CMTime, duration: CMTime) throws -> CMSampleBuffer {
        var formatDescription: CMVideoFormatDescription?
        let formatResult = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard formatResult == noErr, let videoFormatDescription = formatDescription else {
            print("🎬 TextureConverter: Failed to create format description - result: \(formatResult)")
            throw ConversionError.formatDescriptionCreationFailed
        }
        
        var sampleTimingInfo = CMSampleTimingInfo(
            duration: duration,
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
            print("🎬 TextureConverter: Failed to create sample buffer - result: \(sampleBufferResult)")
            throw ConversionError.sampleBufferCreationFailed
        }
        
        return buffer
    }
    
    enum ConversionError: Error, LocalizedError {
        case deviceError(String)
        case textureCacheCreationFailed
        case pixelBufferPoolCreationFailed
        case pixelBufferCreationFailed
        case metalTextureCreationFailed
        case commandBufferCreationFailed
        case encoderCreationFailed
        case metalComputeError(String)
        case formatDescriptionCreationFailed
        case sampleBufferCreationFailed
        
        var errorDescription: String? {
            switch self {
            case .deviceError(let msg):
                return "Metal device error: \(msg)"
            case .textureCacheCreationFailed:
                return "Failed to create Metal texture cache"
            case .pixelBufferPoolCreationFailed:
                return "Failed to create pixel buffer pool"
            case .pixelBufferCreationFailed:
                return "Failed to create pixel buffer"
            case .metalTextureCreationFailed:
                return "Failed to create Metal texture from pixel buffer"
            case .commandBufferCreationFailed:
                return "Failed to create Metal command buffer"
            case .encoderCreationFailed:
                return "Failed to create Metal encoder"
            case .metalComputeError(let msg):
                return "Metal compute error: \(msg)"
            case .formatDescriptionCreationFailed:
                return "Failed to create video format description"
            case .sampleBufferCreationFailed:
                return "Failed to create sample buffer"
            }
        }
    }
}