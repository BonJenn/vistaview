//
//  AudioEngine.swift
//  Vantaview
//
//  Audio processing actor for handling audio capture, processing, and streaming off the main thread
//

import Foundation
import AVFoundation
import CoreMedia
import CoreAudio

/// Sendable wrapper for audio buffers
struct AudioBufferWrapper: Sendable {
    let sampleBuffer: CMSampleBuffer
    let timestamp: CMTime
    let channelCount: Int
    let sampleRate: Double
    let sourceID: String
    
    init(sampleBuffer: CMSampleBuffer, sourceID: String) {
        self.sampleBuffer = sampleBuffer
        self.sourceID = sourceID
        self.timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
            self.channelCount = Int(asbd?.pointee.mChannelsPerFrame ?? 2)
            self.sampleRate = asbd?.pointee.mSampleRate ?? 48000.0
        } else {
            self.channelCount = 2
            self.sampleRate = 48000.0
        }
    }
}

/// Audio processing result
struct AudioProcessingResult: Sendable {
    let outputBuffer: CMSampleBuffer?
    let rmsLevel: Float
    let peakLevel: Float
    let processingTime: TimeInterval
    let error: AudioProcessingError?
    
    enum AudioProcessingError: Error, Sendable {
        case deviceUnavailable
        case formatConversionFailed
        case bufferCreationFailed
        case processingFailed(String)
        case cancelled
    }
}

/// Audio mixing configuration
struct AudioMixConfiguration: Sendable {
    let sources: [String: AudioSourceConfig]
    let masterVolume: Float
    let targetSampleRate: Double
    let targetChannelCount: Int
    
    struct AudioSourceConfig: Sendable {
        let volume: Float
        let pan: Float
        let muted: Bool
        let soloEnabled: Bool
    }
    
    static let `default` = AudioMixConfiguration(
        sources: [:],
        masterVolume: 1.0,
        targetSampleRate: 48000.0,
        targetChannelCount: 2
    )
}

/// Audio engine statistics
struct AudioEngineStats: Sendable {
    let buffersProcessed: Int
    let averageProcessingTime: TimeInterval
    let droppedBuffers: Int
    let currentLatency: TimeInterval
    let activeSources: Int
}

/// Actor responsible for audio processing, mixing, and streaming
actor AudioEngine {
    
    // MARK: - Core Dependencies
    
    private let targetSampleRate: Double = 48000.0
    private let targetChannelCount = 2
    private let bufferDuration: TimeInterval = 1024.0 / 48000.0 // ~21ms at 48kHz
    
    // MARK: - Audio Pipeline
    
    private var audioStreams: [String: AsyncStream<AudioBufferWrapper>.Continuation] = [:]
    private var processingTasks: [String: Task<Void, Never>] = [:]
    private var mixConfiguration = AudioMixConfiguration.default
    
    // MARK: - Audio Session and Capture
    
    private var microphoneEngine: AVAudioEngine?
    #if os(iOS)
    private var audioSession: AVAudioSession?
    #endif
    
    // MARK: - Statistics and Performance
    
    private var stats = AudioEngineStats(
        buffersProcessed: 0,
        averageProcessingTime: 0,
        droppedBuffers: 0,
        currentLatency: 0,
        activeSources: 0
    )
    private var processingTimes: [TimeInterval] = []
    
    // MARK: - Audio Format Management
    
    private lazy var targetFormat: AVAudioFormat = {
        AVAudioFormat(
            standardFormatWithSampleRate: targetSampleRate,
            channels: AVAudioChannelCount(targetChannelCount)
        )!
    }()
    
    private let audioQueue = DispatchQueue(label: "com.vantaview.audioengine", qos: .userInitiated)
    
    init() async throws {
        try await setupAudioSession()
    }
    
    // MARK: - Audio Stream Management
    
    /// Create an audio processing stream for a specific source
    func createAudioStream(for sourceID: String, configuration: AudioMixConfiguration.AudioSourceConfig? = nil) async -> AsyncStream<AudioProcessingResult> {
        // Cancel existing stream if present
        await stopAudioStream(for: sourceID)
        
        // Update mix configuration if provided
        if let config = configuration {
            var newSources = mixConfiguration.sources
            newSources[sourceID] = config
            mixConfiguration = AudioMixConfiguration(
                sources: newSources,
                masterVolume: mixConfiguration.masterVolume,
                targetSampleRate: mixConfiguration.targetSampleRate,
                targetChannelCount: mixConfiguration.targetChannelCount
            )
        }
        
        let (outputStream, outputContinuation) = AsyncStream<AudioProcessingResult>.makeStream()
        
        // Create input stream
        let (inputStream, inputContinuation) = AsyncStream<AudioBufferWrapper>.makeStream()
        audioStreams[sourceID] = inputContinuation
        
        // Start processing task
        processingTasks[sourceID] = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.processAudioStream(sourceID: sourceID, inputStream: inputStream, outputContinuation: outputContinuation)
        }
        
        return outputStream
    }
    
    /// Stop audio processing for a specific source
    func stopAudioStream(for sourceID: String) async {
        audioStreams[sourceID]?.finish()
        audioStreams.removeValue(forKey: sourceID)
        
        processingTasks[sourceID]?.cancel()
        processingTasks.removeValue(forKey: sourceID)
        
        // Remove from mix configuration
        var newSources = mixConfiguration.sources
        newSources.removeValue(forKey: sourceID)
        mixConfiguration = AudioMixConfiguration(
            sources: newSources,
            masterVolume: mixConfiguration.masterVolume,
            targetSampleRate: mixConfiguration.targetSampleRate,
            targetChannelCount: mixConfiguration.targetChannelCount
        )
    }
    
    /// Submit an audio buffer for processing
    func submitAudioBuffer(_ buffer: CMSampleBuffer, for sourceID: String) async throws {
        try Task.checkCancellation()
        
        let wrapper = AudioBufferWrapper(sampleBuffer: buffer, sourceID: sourceID)
        
        if let continuation = audioStreams[sourceID] {
            continuation.yield(wrapper)
        }
    }
    
    /// Submit PCM audio data for processing
    func submitPCMData(_ data: Data, sampleRate: Double, channelCount: Int, for sourceID: String, timestamp: CMTime = CMTime.zero) async throws {
        try Task.checkCancellation()
        
        // Convert PCM data to CMSampleBuffer
        guard let sampleBuffer = try await createSampleBuffer(from: data, sampleRate: sampleRate, channelCount: channelCount, timestamp: timestamp) else {
            throw AudioProcessingResult.AudioProcessingError.bufferCreationFailed
        }
        
        try await submitAudioBuffer(sampleBuffer, for: sourceID)
    }
    
    // MARK: - Microphone Capture
    
    /// Start microphone capture
    func startMicrophoneCapture() async throws -> AsyncStream<AudioProcessingResult> {
        try await stopMicrophoneCapture()
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        
        // Create output stream for microphone
        let outputStream = await createAudioStream(for: "microphone")
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            Task { [weak self] in
                guard let self else { return }
                
                do {
                    // Convert buffer to CMSampleBuffer
                    if let sampleBuffer = try await self.createSampleBuffer(from: buffer, timestamp: time.hostTime) {
                        try await self.submitAudioBuffer(sampleBuffer, for: "microphone")
                    }
                } catch {
                    print("AudioEngine: Error processing microphone buffer: \(error)")
                }
            }
        }
        
        try engine.start()
        microphoneEngine = engine
        
        return outputStream
    }
    
    /// Stop microphone capture
    func stopMicrophoneCapture() async throws {
        if let engine = microphoneEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            microphoneEngine = nil
        }
        
        await stopAudioStream(for: "microphone")
    }
    
    // MARK: - Audio Mixing
    
    /// Update mix configuration
    func updateMixConfiguration(_ configuration: AudioMixConfiguration) async {
        mixConfiguration = configuration
    }
    
    /// Mix multiple audio sources into a single output
    func mixAudioSources(_ sources: [String: AudioBufferWrapper]) async throws -> AudioProcessingResult {
        let startTime = CACurrentMediaTime()
        
        do {
            try Task.checkCancellation()
            
            guard !sources.isEmpty else {
                throw AudioProcessingResult.AudioProcessingError.processingFailed("No sources to mix")
            }
            
            // Calculate output buffer size
            let outputFrameCount = Int(targetSampleRate * bufferDuration)
            let outputSampleCount = outputFrameCount * targetChannelCount
            
            // Create output buffer
            var outputSamples = [Float32](repeating: 0.0, count: outputSampleCount)
            var maxRMS: Float = 0
            var maxPeak: Float = 0
            
            // Mix sources
            for (sourceID, wrapper) in sources {
                guard let sourceConfig = mixConfiguration.sources[sourceID],
                      !sourceConfig.muted else { continue }
                
                // Check for solo mode
                let hasSolo = mixConfiguration.sources.values.contains { $0.soloEnabled }
                if hasSolo && !sourceConfig.soloEnabled { continue }
                
                // Convert and resample source audio
                if let sourceSamples = try await extractPCMData(from: wrapper.sampleBuffer) {
                    let resampledSamples = try await resampleAudio(
                        sourceSamples,
                        fromSampleRate: wrapper.sampleRate,
                        toSampleRate: targetSampleRate,
                        channelCount: wrapper.channelCount
                    )
                    
                    // Apply volume and pan
                    let processedSamples = applyVolumeAndPan(
                        resampledSamples,
                        volume: sourceConfig.volume,
                        pan: sourceConfig.pan
                    )
                    
                    // Mix into output buffer
                    mixSamples(processedSamples, into: &outputSamples)
                    
                    // Calculate levels
                    let (rms, peak) = calculateAudioLevels(processedSamples)
                    maxRMS = max(maxRMS, rms)
                    maxPeak = max(maxPeak, peak)
                }
            }
            
            // Apply master volume
            for i in 0..<outputSamples.count {
                outputSamples[i] *= mixConfiguration.masterVolume
            }
            
            // Apply soft limiting
            applySoftLimiting(&outputSamples)
            
            // Create output sample buffer
            let outputBuffer = try await createSampleBuffer(
                from: outputSamples,
                sampleRate: targetSampleRate,
                channelCount: targetChannelCount,
                timestamp: CMClockGetTime(CMClockGetHostTimeClock())
            )
            
            let processingTime = CACurrentMediaTime() - startTime
            processingTimes.append(processingTime)
            
            return AudioProcessingResult(
                outputBuffer: outputBuffer,
                rmsLevel: maxRMS,
                peakLevel: maxPeak,
                processingTime: processingTime,
                error: nil
            )
            
        } catch is CancellationError {
            throw AudioProcessingResult.AudioProcessingError.cancelled
        } catch {
            return AudioProcessingResult(
                outputBuffer: nil,
                rmsLevel: 0,
                peakLevel: 0,
                processingTime: CACurrentMediaTime() - startTime,
                error: .processingFailed(error.localizedDescription)
            )
        }
    }
    
    // MARK: - Statistics
    
    /// Get current audio engine statistics
    func getStats() async -> AudioEngineStats {
        return stats
    }
    
    /// Reset audio engine statistics
    func resetStats() async {
        stats = AudioEngineStats(
            buffersProcessed: 0,
            averageProcessingTime: 0,
            droppedBuffers: 0,
            currentLatency: 0,
            activeSources: audioStreams.count
        )
        processingTimes.removeAll()
    }
    
    // MARK: - Private Implementation
    
    private func setupAudioSession() async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        audioSession = session
        #endif
    }
    
    private func processAudioStream(
        sourceID: String,
        inputStream: AsyncStream<AudioBufferWrapper>,
        outputContinuation: AsyncStream<AudioProcessingResult>.Continuation
    ) async {
        var processedBuffers = 0
        var droppedBuffers = 0
        
        for await wrapper in inputStream {
            if Task.isCancelled {
                outputContinuation.finish()
                return
            }
            
            let startTime = CACurrentMediaTime()
            
            do {
                try Task.checkCancellation()
                
                // Process single source (for individual source monitoring)
                let sources = [sourceID: wrapper]
                let result = try await mixAudioSources(sources)
                
                processedBuffers += 1
                outputContinuation.yield(result)
                
            } catch is CancellationError {
                let result = AudioProcessingResult(
                    outputBuffer: nil,
                    rmsLevel: 0,
                    peakLevel: 0,
                    processingTime: CACurrentMediaTime() - startTime,
                    error: .cancelled
                )
                outputContinuation.yield(result)
                break
            } catch {
                droppedBuffers += 1
                let result = AudioProcessingResult(
                    outputBuffer: nil,
                    rmsLevel: 0,
                    peakLevel: 0,
                    processingTime: CACurrentMediaTime() - startTime,
                    error: .processingFailed(error.localizedDescription)
                )
                outputContinuation.yield(result)
            }
        }
        
        // Update statistics
        let avgTime = processingTimes.isEmpty ? 0 : processingTimes.reduce(0, +) / Double(processingTimes.count)
        stats = AudioEngineStats(
            buffersProcessed: processedBuffers,
            averageProcessingTime: avgTime,
            droppedBuffers: droppedBuffers,
            currentLatency: avgTime,
            activeSources: audioStreams.count
        )
        
        outputContinuation.finish()
    }
    
    private func createSampleBuffer(from data: Data, sampleRate: Double, channelCount: Int, timestamp: CMTime) async throws -> CMSampleBuffer? {
        let frameCount = data.count / (MemoryLayout<Float32>.size * channelCount)
        
        var format: AudioStreamBasicDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size * channelCount),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size * channelCount),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &format,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr else {
            throw AudioProcessingResult.AudioProcessingError.formatConversionFailed
        }
        
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == noErr else {
            throw AudioProcessingResult.AudioProcessingError.bufferCreationFailed
        }
        
        data.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer!,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }
        
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr else {
            throw AudioProcessingResult.AudioProcessingError.bufferCreationFailed
        }
        
        return sampleBuffer
    }
    
    private func createSampleBuffer(from samples: [Float32], sampleRate: Double, channelCount: Int, timestamp: CMTime) async throws -> CMSampleBuffer? {
        let data = Data(bytes: samples, count: samples.count * MemoryLayout<Float32>.size)
        return try await createSampleBuffer(from: data, sampleRate: sampleRate, channelCount: channelCount, timestamp: timestamp)
    }
    
    private func createSampleBuffer(from buffer: AVAudioPCMBuffer, timestamp: UInt64) async throws -> CMSampleBuffer? {
        guard let channelData = buffer.floatChannelData else {
            throw AudioProcessingResult.AudioProcessingError.formatConversionFailed
        }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate
        
        var interleavedSamples = [Float32](repeating: 0, count: frameCount * channelCount)
        
        // Interleave channels
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                interleavedSamples[frame * channelCount + channel] = channelData[channel][frame]
            }
        }
        
        let cmTime = CMTime(value: CMTimeValue(timestamp), timescale: CMTimeScale(NSEC_PER_SEC))
        return try await createSampleBuffer(from: interleavedSamples, sampleRate: sampleRate, channelCount: channelCount, timestamp: cmTime)
    }
    
    private func extractPCMData(from sampleBuffer: CMSampleBuffer) async throws -> [Float32]? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        
        var dataPointer: UnsafeMutablePointer<Int8>?
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        
        guard CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        ) == noErr, let pointer = dataPointer else {
            throw AudioProcessingResult.AudioProcessingError.formatConversionFailed
        }
        
        let floatCount = totalLength / MemoryLayout<Float32>.size
        let floatPointer = pointer.withMemoryRebound(to: Float32.self, capacity: floatCount) { $0 }
        
        return Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))
    }
    
    private func resampleAudio(_ samples: [Float32], fromSampleRate: Double, toSampleRate: Double, channelCount: Int) async throws -> [Float32] {
        if abs(fromSampleRate - toSampleRate) < 1.0 {
            return samples // No resampling needed
        }
        
        let ratio = toSampleRate / fromSampleRate
        let inputFrameCount = samples.count / channelCount
        let outputFrameCount = Int(Double(inputFrameCount) * ratio)
        
        var outputSamples = [Float32](repeating: 0, count: outputFrameCount * channelCount)
        
        for outputFrame in 0..<outputFrameCount {
            let inputPosition = Double(outputFrame) / ratio
            let inputFrame = Int(inputPosition)
            let fraction = Float32(inputPosition - Double(inputFrame))
            
            for channel in 0..<channelCount {
                let outputIndex = outputFrame * channelCount + channel
                let inputIndex1 = min(inputFrame * channelCount + channel, samples.count - 1)
                let inputIndex2 = min((inputFrame + 1) * channelCount + channel, samples.count - 1)
                
                let sample1 = samples[inputIndex1]
                let sample2 = samples[inputIndex2]
                
                outputSamples[outputIndex] = sample1 + (sample2 - sample1) * fraction
            }
        }
        
        return outputSamples
    }
    
    private func applyVolumeAndPan(_ samples: [Float32], volume: Float, pan: Float) -> [Float32] {
        guard samples.count >= 2 else { return samples }
        
        var output = samples
        let frameCount = samples.count / 2
        
        // Calculate pan coefficients
        let panRadians = (pan + 1.0) * Float.pi / 4.0
        let leftGain = cos(panRadians) * volume
        let rightGain = sin(panRadians) * volume
        
        for frame in 0..<frameCount {
            let leftIndex = frame * 2
            let rightIndex = frame * 2 + 1
            
            output[leftIndex] *= leftGain
            output[rightIndex] *= rightGain
        }
        
        return output
    }
    
    private func mixSamples(_ source: [Float32], into destination: inout [Float32]) {
        let count = min(source.count, destination.count)
        for i in 0..<count {
            destination[i] += source[i]
        }
    }
    
    private func calculateAudioLevels(_ samples: [Float32]) -> (rms: Float, peak: Float) {
        var rmsSum: Float = 0
        var peak: Float = 0
        
        for sample in samples {
            let absSample = abs(sample)
            peak = max(peak, absSample)
            rmsSum += sample * sample
        }
        
        let rms = sqrt(rmsSum / Float(samples.count))
        return (rms, peak)
    }
    
    private func applySoftLimiting(_ samples: inout [Float32]) {
        let threshold: Float = 0.95
        let ratio: Float = 10.0
        
        for i in 0..<samples.count {
            let input = abs(samples[i])
            if input > threshold {
                let excess = input - threshold
                let compressed = threshold + excess / ratio
                samples[i] = samples[i] > 0 ? compressed : -compressed
            }
        }
    }
}