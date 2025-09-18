//
//  StreamingEngine.swift
//  Vantaview
//
//  Streaming engine actor for handling RTMP streaming operations off the main thread
//

import Foundation
import HaishinKit
import AVFoundation
import CoreMedia
import Metal

/// Sendable representation of stream configuration
struct StreamConfiguration: Sendable {
    let rtmpURL: String
    let streamKey: String
    let videoSettings: VideoSettings
    let audioSettings: AudioSettings
    let reconnectionSettings: ReconnectionSettings
    
    struct VideoSettings: Sendable {
        let resolution: CGSize
        let frameRate: Double
        let bitrate: Int
        let keyFrameInterval: Int
        let codecType: String
        
        static let `default` = VideoSettings(
            resolution: CGSize(width: 1920, height: 1080),
            frameRate: 30.0,
            bitrate: 2500000, // 2.5 Mbps
            keyFrameInterval: 30,
            codecType: "H.264"
        )
    }
    
    struct AudioSettings: Sendable {
        let sampleRate: Double
        let channelCount: Int
        let bitrate: Int
        let codecType: String
        
        static let `default` = AudioSettings(
            sampleRate: 48000.0,
            channelCount: 2,
            bitrate: 128000, // 128 kbps
            codecType: "AAC"
        )
    }
    
    struct ReconnectionSettings: Sendable {
        let enabled: Bool
        let maxAttempts: Int
        let initialDelay: TimeInterval
        let maxDelay: TimeInterval
        let backoffMultiplier: Double
        
        static let `default` = ReconnectionSettings(
            enabled: true,
            maxAttempts: 5,
            initialDelay: 1.0,
            maxDelay: 30.0,
            backoffMultiplier: 2.0
        )
    }
    
    static let `default` = StreamConfiguration(
        rtmpURL: "",
        streamKey: "",
        videoSettings: .default,
        audioSettings: .default,
        reconnectionSettings: .default
    )
}

/// Stream status information
struct StreamingStatus: Sendable {
    enum State: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case publishing
        case reconnecting
        case error(String)
        
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.publishing, .publishing),
                 (.reconnecting, .reconnecting):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    
    let state: State
    let connectionTime: Date?
    let publishingTime: Date?
    let bytesPublished: Int64
    let framesPublished: Int64
    let audioBuffersPublished: Int64
    let currentBitrate: Double
    let averageBitrate: Double
    let connectionQuality: Double // 0.0 - 1.0
    
    static let disconnected = StreamingStatus(
        state: .disconnected,
        connectionTime: nil,
        publishingTime: nil,
        bytesPublished: 0,
        framesPublished: 0,
        audioBuffersPublished: 0,
        currentBitrate: 0,
        averageBitrate: 0,
        connectionQuality: 0
    )
}

/// Stream statistics over time
struct StreamStatistics: Sendable {
    let duration: TimeInterval
    let totalFrames: Int64
    let droppedFrames: Int64
    let totalAudioBuffers: Int64
    let droppedAudioBuffers: Int64
    let averageFrameRate: Double
    let averageBitrate: Double
    let peakBitrate: Double
    let reconnectionCount: Int
    let qualityScore: Double // 0.0 - 1.0 overall quality
}

/// Frame submission for streaming
struct StreamFrame: Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestamp: CMTime
    let duration: CMTime
    
    init(pixelBuffer: CVPixelBuffer, timestamp: CMTime, duration: CMTime) {
        self.pixelBuffer = pixelBuffer
        self.timestamp = timestamp
        self.duration = duration
    }
}

/// Audio submission for streaming
struct StreamAudioBuffer: Sendable {
    let sampleBuffer: CMSampleBuffer
    let timestamp: CMTime
    
    init(sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
        self.timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    }
}

/// Actor responsible for RTMP streaming operations
actor StreamingEngine {
    
    // MARK: - Core Dependencies
    
    private let connection: RTMPConnection
    private let stream: RTMPStream
    private var mixer: MediaMixer?
    
    // MARK: - Configuration and State
    
    private var configuration: StreamConfiguration = .default
    private var status: StreamingStatus = .disconnected
    private var statistics: StreamStatistics = StreamStatistics(
        duration: 0,
        totalFrames: 0,
        droppedFrames: 0,
        totalAudioBuffers: 0,
        droppedAudioBuffers: 0,
        averageFrameRate: 0,
        averageBitrate: 0,
        peakBitrate: 0,
        reconnectionCount: 0,
        qualityScore: 0
    )
    
    // MARK: - Streaming Pipeline
    
    private var videoFrameStream: AsyncStream<StreamFrame>?
    private var audioBufferStream: AsyncStream<StreamAudioBuffer>?
    private var streamingTask: Task<Void, Never>?
    private var reconnectionTask: Task<Void, Never>?
    
    // MARK: - Status Notifications
    
    private var statusContinuation: AsyncStream<StreamingStatus>.Continuation?
    private var statusStream: AsyncStream<StreamingStatus>?
    
    // MARK: - Performance Tracking
    
    private var startTime: Date?
    private var connectionStartTime: Date?
    private var publishingStartTime: Date?
    private var lastBitrateCalculation: Date = Date()
    private var bytesSinceLastCalculation: Int64 = 0
    private var frameRateTracker: [Date] = []
    
    init() async {
        connection = RTMPConnection()
        stream = RTMPStream(connection: connection)
        
        await setupConnectionObservers()
    }
    
    deinit {
        streamingTask?.cancel()
        reconnectionTask?.cancel()
    }
    
    // MARK: - Stream Management
    
    /// Start streaming with the provided configuration
    func startStream(configuration: StreamConfiguration) async throws {
        try Task.checkCancellation()
        
        // Stop any existing stream
        await stopStream()
        
        self.configuration = configuration
        startTime = Date()
        connectionStartTime = Date()
        
        // Update status
        await updateStatus(.connecting)
        
        do {
            // Configure mixer settings
            if let mixer = mixer {
                try await configureMixer(mixer, with: configuration)
            }
            
            // Connect to RTMP server
            try await connection.connect(configuration.rtmpURL)
            
            // Start publishing
            try await stream.publish(configuration.streamKey)
            
            // Update status
            publishingStartTime = Date()
            await updateStatus(.publishing)
            
            // Start streaming pipeline
            await startStreamingPipeline()
            
        } catch {
            await updateStatus(.error(error.localizedDescription))
            throw StreamingEngineError.connectionFailed(error.localizedDescription)
        }
    }
    
    /// Stop streaming
    func stopStream() async {
        streamingTask?.cancel()
        streamingTask = nil
        
        reconnectionTask?.cancel()
        reconnectionTask = nil
        
        do {
            try await stream.close()
            try await connection.close()
        } catch {
            print("StreamingEngine: Error closing stream: \(error)")
        }
        
        await updateStatus(.disconnected)
        await resetStatistics()
        
        startTime = nil
        connectionStartTime = nil
        publishingStartTime = nil
    }
    
    /// Submit a video frame for streaming
    func submitVideoFrame(_ frame: StreamFrame) async throws {
        try Task.checkCancellation()
        
        guard status.state == .publishing else {
            throw StreamingEngineError.notPublishing
        }
        
        // Create sample buffer from pixel buffer
        let sampleBuffer = try await createVideoSampleBuffer(from: frame)
        
        // Submit to stream
        await stream.appendVideo(sampleBuffer)
        
        // Update statistics
        await updateVideoStatistics()
    }
    
    /// Submit an audio buffer for streaming
    func submitAudioBuffer(_ buffer: StreamAudioBuffer) async throws {
        try Task.checkCancellation()
        
        guard status.state == .publishing else {
            throw StreamingEngineError.notPublishing
        }
        
        // Submit to stream
        await stream.appendAudio(buffer.sampleBuffer)
        
        // Update statistics
        await updateAudioStatistics()
    }
    
    /// Submit Metal texture for streaming (converts to pixel buffer)
    func submitTexture(_ texture: MTLTexture, timestamp: CMTime, duration: CMTime) async throws {
        try Task.checkCancellation()
        
        // Convert texture to pixel buffer
        let pixelBuffer = try await createPixelBuffer(from: texture)
        let frame = StreamFrame(pixelBuffer: pixelBuffer, timestamp: timestamp, duration: duration)
        
        try await submitVideoFrame(frame)
    }
    
    // MARK: - Configuration
    
    /// Update streaming configuration (may require restart)
    func updateConfiguration(_ newConfiguration: StreamConfiguration) async throws {
        let wasPublishing = status.state == .publishing
        
        if wasPublishing {
            await stopStream()
        }
        
        self.configuration = newConfiguration
        
        if wasPublishing {
            try await startStream(configuration: newConfiguration)
        }
    }
    
    /// Get current configuration
    func getConfiguration() async -> StreamConfiguration {
        return configuration
    }
    
    // MARK: - Status and Statistics
    
    /// Get current stream status
    func getStatus() async -> StreamingStatus {
        return status
    }
    
    /// Get streaming statistics
    func getStatistics() async -> StreamStatistics {
        return statistics
    }
    
    /// Create a stream for status updates
    func statusUpdates() async -> AsyncStream<StreamingStatus> {
        if let existingStream = statusStream {
            return existingStream
        }
        
        let (stream, continuation) = AsyncStream<StreamingStatus>.makeStream()
        statusContinuation = continuation
        statusStream = stream
        
        return stream
    }
    
    // MARK: - Reconnection
    
    /// Enable or disable automatic reconnection
    func setReconnectionEnabled(_ enabled: Bool) async {
        var newSettings = configuration.reconnectionSettings
        // Note: In a real implementation, you'd create a new ReconnectionSettings struct
        // For now, we'll update the entire configuration
        configuration = StreamConfiguration(
            rtmpURL: configuration.rtmpURL,
            streamKey: configuration.streamKey,
            videoSettings: configuration.videoSettings,
            audioSettings: configuration.audioSettings,
            reconnectionSettings: StreamConfiguration.ReconnectionSettings(
                enabled: enabled,
                maxAttempts: newSettings.maxAttempts,
                initialDelay: newSettings.initialDelay,
                maxDelay: newSettings.maxDelay,
                backoffMultiplier: newSettings.backoffMultiplier
            )
        )
    }
    
    // MARK: - Private Implementation
    
    private func setupConnectionObservers() async {
        // In a real implementation, you'd set up HaishinKit connection observers
        // For now, we'll use a simplified approach
    }
    
    private func configureMixer(_ mixer: MediaMixer, with config: StreamConfiguration) async throws {
        try await mixer.setFrameRate(Int(config.videoSettings.frameRate))
        try await mixer.setSessionPreset(.high) // Map resolution to preset
    }
    
    private func startStreamingPipeline() async {
        streamingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                do {
                    try Task.checkCancellation()
                    
                    // Monitor connection health
                    await self.monitorConnectionHealth()
                    
                    // Update statistics periodically
                    await self.updatePeriodicStatistics()
                    
                    // Small delay to prevent tight loop
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    
                } catch is CancellationError {
                    break
                } catch {
                    print("StreamingEngine: Pipeline error: \(error)")
                    await self.handleStreamingError(error)
                }
            }
        }
    }
    
    private func updateStatus(_ newState: StreamingStatus.State) async {
        let connectionTime = status.connectionTime ?? (newState == .connected ? Date() : nil)
        let publishingTime = status.publishingTime ?? (newState == .publishing ? Date() : nil)
        
        status = StreamingStatus(
            state: newState,
            connectionTime: connectionTime,
            publishingTime: publishingTime,
            bytesPublished: status.bytesPublished,
            framesPublished: status.framesPublished,
            audioBuffersPublished: status.audioBuffersPublished,
            currentBitrate: status.currentBitrate,
            averageBitrate: status.averageBitrate,
            connectionQuality: calculateConnectionQuality()
        )
        
        statusContinuation?.yield(status)
    }
    
    private func updateVideoStatistics() async {
        let currentTime = Date()
        frameRateTracker.append(currentTime)
        
        // Keep only recent frame times (last second)
        frameRateTracker.removeAll { currentTime.timeIntervalSince($0) > 1.0 }
        
        // Update frame count
        let newFramesPublished = status.framesPublished + 1
        
        status = StreamingStatus(
            state: status.state,
            connectionTime: status.connectionTime,
            publishingTime: status.publishingTime,
            bytesPublished: status.bytesPublished,
            framesPublished: newFramesPublished,
            audioBuffersPublished: status.audioBuffersPublished,
            currentBitrate: status.currentBitrate,
            averageBitrate: status.averageBitrate,
            connectionQuality: status.connectionQuality
        )
    }
    
    private func updateAudioStatistics() async {
        let newAudioBuffersPublished = status.audioBuffersPublished + 1
        
        status = StreamingStatus(
            state: status.state,
            connectionTime: status.connectionTime,
            publishingTime: status.publishingTime,
            bytesPublished: status.bytesPublished,
            framesPublished: status.framesPublished,
            audioBuffersPublished: newAudioBuffersPublished,
            currentBitrate: status.currentBitrate,
            averageBitrate: status.averageBitrate,
            connectionQuality: status.connectionQuality
        )
    }
    
    private func updatePeriodicStatistics() async {
        let currentTime = Date()
        
        // Update bitrate every second
        if currentTime.timeIntervalSince(lastBitrateCalculation) >= 1.0 {
            let timeDelta = currentTime.timeIntervalSince(lastBitrateCalculation)
            let bytesDelta = status.bytesPublished - bytesSinceLastCalculation
            let currentBitrate = Double(bytesDelta * 8) / timeDelta // bits per second
            
            // Update running average
            let alpha: Double = 0.1 // Smoothing factor
            let newAverageBitrate = status.averageBitrate * (1 - alpha) + currentBitrate * alpha
            
            status = StreamingStatus(
                state: status.state,
                connectionTime: status.connectionTime,
                publishingTime: status.publishingTime,
                bytesPublished: status.bytesPublished,
                framesPublished: status.framesPublished,
                audioBuffersPublished: status.audioBuffersPublished,
                currentBitrate: currentBitrate,
                averageBitrate: newAverageBitrate,
                connectionQuality: status.connectionQuality
            )
            
            lastBitrateCalculation = currentTime
            bytesSinceLastCalculation = status.bytesPublished
        }
        
        // Update overall statistics
        if let startTime = startTime {
            let duration = currentTime.timeIntervalSince(startTime)
            let avgFrameRate = Double(status.framesPublished) / duration
            
            statistics = StreamStatistics(
                duration: duration,
                totalFrames: status.framesPublished,
                droppedFrames: statistics.droppedFrames,
                totalAudioBuffers: status.audioBuffersPublished,
                droppedAudioBuffers: statistics.droppedAudioBuffers,
                averageFrameRate: avgFrameRate,
                averageBitrate: status.averageBitrate,
                peakBitrate: max(statistics.peakBitrate, status.currentBitrate),
                reconnectionCount: statistics.reconnectionCount,
                qualityScore: calculateQualityScore()
            )
        }
    }
    
    private func monitorConnectionHealth() async {
        // In a real implementation, you'd check HaishinKit connection metrics
        // For now, we'll use a simplified health check
    }
    
    private func handleStreamingError(_ error: Error) async {
        await updateStatus(.error(error.localizedDescription))
        
        if configuration.reconnectionSettings.enabled {
            await startReconnection()
        }
    }
    
    private func startReconnection() async {
        reconnectionTask?.cancel()
        
        reconnectionTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            
            var attempt = 0
            let reconnectionSettings = await self.configuration.reconnectionSettings
            var delay = reconnectionSettings.initialDelay
            
            while attempt < reconnectionSettings.maxAttempts && !Task.isCancelled {
                attempt += 1
                
                await self.updateStatus(.reconnecting)
                
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    let config = await self.configuration
                    try await self.startStream(configuration: config)
                    return // Success
                } catch {
                    print("StreamingEngine: Reconnection attempt \(attempt) failed: \(error)")
                    delay = min(delay * reconnectionSettings.backoffMultiplier, 
                              reconnectionSettings.maxDelay)
                }
            }
            
            // All attempts failed
            await self.updateStatus(.error("Reconnection failed after \(attempt) attempts"))
        }
    }
    
    private func calculateConnectionQuality() -> Double {
        // Simplified quality calculation based on frame rate and bitrate
        let targetFrameRate = configuration.videoSettings.frameRate
        let actualFrameRate = Double(frameRateTracker.count)
        let frameRateQuality = min(actualFrameRate / targetFrameRate, 1.0)
        
        let targetBitrate = Double(configuration.videoSettings.bitrate)
        let actualBitrate = status.currentBitrate
        let bitrateQuality = min(actualBitrate / targetBitrate, 1.0)
        
        return (frameRateQuality + bitrateQuality) / 2.0
    }
    
    private func calculateQualityScore() -> Double {
        let connectionQuality = status.connectionQuality
        let frameDropRate = Double(statistics.droppedFrames) / max(Double(statistics.totalFrames), 1.0)
        let frameDropQuality = max(1.0 - frameDropRate, 0.0)
        
        return (connectionQuality + frameDropQuality) / 2.0
    }
    
    private func resetStatistics() async {
        statistics = StreamStatistics(
            duration: 0,
            totalFrames: 0,
            droppedFrames: 0,
            totalAudioBuffers: 0,
            droppedAudioBuffers: 0,
            averageFrameRate: 0,
            averageBitrate: 0,
            peakBitrate: 0,
            reconnectionCount: 0,
            qualityScore: 0
        )
        
        frameRateTracker.removeAll()
        bytesSinceLastCalculation = 0
        lastBitrateCalculation = Date()
    }
    
    private func createVideoSampleBuffer(from frame: StreamFrame) async throws -> CMSampleBuffer {
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: frame.pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard status == noErr, let formatDesc = formatDescription else {
            throw StreamingEngineError.sampleBufferCreationFailed("Video format description creation failed")
        }
        
        var timing = CMSampleTimingInfo(
            duration: frame.duration,
            presentationTimeStamp: frame.timestamp,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        let bufferStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: frame.pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        
        guard bufferStatus == noErr, let buffer = sampleBuffer else {
            throw StreamingEngineError.sampleBufferCreationFailed("Video sample buffer creation failed")
        }
        
        return buffer
    }
    
    private func createPixelBuffer(from texture: MTLTexture) async throws -> CVPixelBuffer {
        let width = texture.width
        let height = texture.height
        
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw StreamingEngineError.pixelBufferCreationFailed("Failed to create pixel buffer")
        }
        
        // TODO: Copy texture data to pixel buffer
        // This would typically involve creating a render pass to copy the texture
        
        return buffer
    }
}

// MARK: - Error Types

enum StreamingEngineError: Error, LocalizedError, Sendable {
    case connectionFailed(String)
    case notPublishing
    case sampleBufferCreationFailed(String)
    case pixelBufferCreationFailed(String)
    case configurationInvalid(String)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .notPublishing:
            return "Stream is not currently publishing"
        case .sampleBufferCreationFailed(let reason):
            return "Sample buffer creation failed: \(reason)"
        case .pixelBufferCreationFailed(let reason):
            return "Pixel buffer creation failed: \(reason)"
        case .configurationInvalid(let reason):
            return "Configuration invalid: \(reason)"
        }
    }
}

// MARK: - Sendable Conformance

extension MediaMixer: @unchecked Sendable {}
extension RTMPConnection: @unchecked Sendable {}
extension RTMPStream: @unchecked Sendable {}