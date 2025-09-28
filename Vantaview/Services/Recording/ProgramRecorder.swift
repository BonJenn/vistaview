import Foundation
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers

actor ProgramRecorder {
    struct VideoConfig: Sendable {
        var width: Int
        var height: Int
        var fps: Double
        var bitrate: Int
        var codec: AVVideoCodecType
        var allowFrameReordering: Bool
        
        static func `default`(width: Int = 1920, height: Int = 1080, fps: Double = 30.0) -> VideoConfig {
            VideoConfig(width: width, height: height, fps: fps, bitrate: 16_000_000, codec: .h264, allowFrameReordering: false)
        }
    }
    
    struct AudioConfig: Sendable {
        var sampleRate: Double
        var channels: Int
        var bitrate: Int
        var formatID: AudioFormatID
        
        static func `default`() -> AudioConfig {
            AudioConfig(sampleRate: 48_000, channels: 2, bitrate: 192_000, formatID: kAudioFormatMPEG4AAC)
        }
    }
    
    enum Container: Sendable {
        case mov, mp4
        
        var avFileType: AVFileType {
            switch self {
            case .mov: return .mov
            case .mp4: return .mp4
            }
        }
        
        var utType: UTType {
            switch self {
            case .mov: return .quickTimeMovie
            case .mp4: return .mpeg4Movie
            }
        }
        
        var fileExtension: String {
            switch self {
            case .mov: return "mov"
            case .mp4: return "mp4"
            }
        }
    }
    
    private(set) var isRecording = false
    private(set) var outputURL: URL?
    private(set) var lastError: Error?
    private(set) var startedAtCMTime: CMTime?
    
    private var isFinalizingWriter = false
    
    private(set) var droppedVideoFrames = 0
    private(set) var droppedAudioFrames = 0
    private(set) var averageWriteLatencyMs: Double = 0
    private var writeMeasurementsCount: Int = 0
    private var bytesWritten: Int64 = 0
    private var lastBitrateSampleTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private(set) var estimatedBitrateBps: Double = 0
    
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    
    private var pendingContainer: Container = .mov
    private var requestedVideoConfig: VideoConfig = .default()
    private var requestedAudioConfig: AudioConfig = .default()
    
    func start(url: URL, container: Container = .mov, requestedVideo: VideoConfig = .default(), requestedAudio: AudioConfig = .default()) async throws {
        try Task.checkCancellation()
        guard !isRecording else { return }
        
        // Reset finalization state
        isFinalizingWriter = false
        
        self.lastError = nil
        self.outputURL = url
        self.pendingContainer = container
        self.requestedVideoConfig = requestedVideo
        self.requestedAudioConfig = requestedAudio
        self.droppedVideoFrames = 0
        self.droppedAudioFrames = 0
        self.averageWriteLatencyMs = 0
        self.writeMeasurementsCount = 0
        self.bytesWritten = 0
        self.estimatedBitrateBps = 0
        self.lastBitrateSampleTime = CFAbsoluteTimeGetCurrent()
        self.startedAtCMTime = nil
        
        isRecording = true
        
        print("🎬 ProgramRecorder: Started recording to \(url.lastPathComponent)")
    }
    
    func stopAndFinalize() async throws -> URL {
        try Task.checkCancellation()
        
        // Prevent multiple finalization attempts
        guard !isFinalizingWriter else {
            print("🎬 ProgramRecorder: Already finalizing, waiting...")
            // Return existing URL if available
            if let url = outputURL {
                return url
            }
            throw RecordingError.finalizeFailed
        }
        
        guard isRecording else {
            if let url = outputURL {
                return url
            }
            throw RecordingError.notRecording
        }
        
        isFinalizingWriter = true
        isRecording = false
        
        print("🎬 ProgramRecorder: Stopping and finalizing recording...")
        
        guard let writer = writer else {
            guard let url = outputURL else { throw RecordingError.noWriter }
            return url
        }
        
        // Mark inputs as finished
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        print("🎬 ProgramRecorder: Inputs marked as finished, finalizing writer...")
        
        return try await withCheckedThrowingContinuation { [writer] (cont: CheckedContinuation<URL, Error>) in
            writer.finishWriting {
                if writer.status == .completed {
                    print("🎬 ProgramRecorder: Writer finalized successfully")
                    cont.resume(returning: writer.outputURL)
                } else {
                    print("🎬 ProgramRecorder: Writer finalization failed - status: \(writer.status.rawValue)")
                    if let error = writer.error {
                        print("🎬 ProgramRecorder: Writer error: \(error)")
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(throwing: RecordingError.finalizeFailed)
                    }
                }
            }
        }
    }
    
    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) async {
        guard isRecording && !isFinalizingWriter else { return }
        do {
            try Task.checkCancellation()
            if writer == nil {
                try configureWriterForFirstVideoBuffer(sampleBuffer)
            }
            guard let videoInput = videoInput else { return }
            if videoInput.isReadyForMoreMediaData {
                let t0 = CFAbsoluteTimeGetCurrent()
                if videoInput.append(sampleBuffer) {
                    updatePostWriteMetrics(t0: t0, buffer: sampleBuffer)
                } else {
                    droppedVideoFrames += 1
                }
            } else {
                droppedVideoFrames += 1
            }
        } catch {
            lastError = error
            await stopSilentlyOnError()
        }
    }
    
    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) async {
        guard isRecording && !isFinalizingWriter else { return }
        do {
            try Task.checkCancellation()
            if writer == nil {
                try configureWriterForFirstAudioBuffer(sampleBuffer)
            }
            guard let audioInput = audioInput else { return }
            if audioInput.isReadyForMoreMediaData {
                let t0 = CFAbsoluteTimeGetCurrent()
                if audioInput.append(sampleBuffer) {
                    updatePostWriteMetrics(t0: t0, buffer: sampleBuffer)
                } else {
                    droppedAudioFrames += 1
                }
            } else {
                droppedAudioFrames += 1
            }
        } catch {
            lastError = error
            await stopSilentlyOnError()
        }
    }
    
    private func configureWriterForFirstVideoBuffer(_ sb: CMSampleBuffer) throws {
        guard let url = outputURL else { throw RecordingError.missingURL }
        let formatDesc = CMSampleBufferGetFormatDescription(sb)
        let dimsOptional = formatDesc.map { CMVideoFormatDescriptionGetDimensions($0) }
        let width = Int(dimsOptional?.width ?? Int32(requestedVideoConfig.width))
        let height = Int(dimsOptional?.height ?? Int32(requestedVideoConfig.height))
        
        print("🎬 ProgramRecorder: Configuring writer for video - \(width)x\(height)")
        
        let writer = try AVAssetWriter(outputURL: url, fileType: pendingContainer.avFileType)
        writer.shouldOptimizeForNetworkUse = (pendingContainer == .mp4)
        
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: requestedVideoConfig.bitrate,
            AVVideoExpectedSourceFrameRateKey: Int(requestedVideoConfig.fps),
            AVVideoAllowFrameReorderingKey: requestedVideoConfig.allowFrameReordering
        ]
        if requestedVideoConfig.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: requestedVideoConfig.codec.rawValue,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        
        if writer.canAdd(vInput) {
            writer.add(vInput)
        } else {
            throw RecordingError.cannotAddVideoInput
        }
        
        if audioInput == nil {
            try maybeAddDefaultAudioInput(to: writer)
        }
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        writer.startWriting()
        writer.startSession(atSourceTime: pts)
        self.startedAtCMTime = pts
        
        self.writer = writer
        self.videoInput = vInput
        
        print("🎬 ProgramRecorder: Writer configured and started for video")
    }
    
    private func configureWriterForFirstAudioBuffer(_ sb: CMSampleBuffer) throws {
        guard let url = outputURL else { throw RecordingError.missingURL }
        
        print("🎬 ProgramRecorder: Configuring writer for audio")
        
        let writer = try AVAssetWriter(outputURL: url, fileType: pendingContainer.avFileType)
        writer.shouldOptimizeForNetworkUse = (pendingContainer == .mp4)
        
        let aInput = try buildAudioInput()
        if writer.canAdd(aInput) {
            writer.add(aInput)
        } else {
            throw RecordingError.cannotAddAudioInput
        }
        
        self.writer = writer
        self.audioInput = aInput
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        writer.startWriting()
        writer.startSession(atSourceTime: pts)
        self.startedAtCMTime = pts
        
        print("🎬 ProgramRecorder: Writer configured and started for audio")
    }
    
    private func maybeAddDefaultAudioInput(to writer: AVAssetWriter) throws {
        let aInput = try buildAudioInput()
        if writer.canAdd(aInput) {
            writer.add(aInput)
            self.audioInput = aInput
            print("🎬 ProgramRecorder: Added default audio input")
        }
    }
    
    private func buildAudioInput() throws -> AVAssetWriterInput {
        var channelLayout = AudioChannelLayout()
        channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        let layoutData = Data(bytes: &channelLayout, count: MemoryLayout<AudioChannelLayout>.size)
        
        let settings: [String: Any] = [
            AVFormatIDKey: requestedAudioConfig.formatID,
            AVSampleRateKey: requestedAudioConfig.sampleRate,
            AVNumberOfChannelsKey: requestedAudioConfig.channels,
            AVEncoderBitRateKey: requestedAudioConfig.bitrate,
            AVChannelLayoutKey: layoutData
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }
    
    private func updatePostWriteMetrics(t0: CFAbsoluteTime, buffer: CMSampleBuffer) {
        let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
        writeMeasurementsCount += 1
        averageWriteLatencyMs = averageWriteLatencyMs + (dt - averageWriteLatencyMs) / Double(max(writeMeasurementsCount, 1))
        
        if let dataBuffer = CMSampleBufferGetDataBuffer(buffer) {
            let byteCount = CMBlockBufferGetDataLength(dataBuffer)
            bytesWritten += Int64(byteCount)
        }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastBitrateSampleTime
        if elapsed >= 1.0 {
            estimatedBitrateBps = Double(bytesWritten) * 8.0 / elapsed
            bytesWritten = 0
            lastBitrateSampleTime = now
        }
    }
    
    private func stopSilentlyOnError() async {
        guard !isFinalizingWriter else { return }
        
        isFinalizingWriter = true
        isRecording = false
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer?.cancelWriting()
        
        print("🎬 ProgramRecorder: Stopped silently due to error")
    }
    
    enum RecordingError: Error {
        case notRecording
        case missingURL
        case noWriter
        case cannotAddVideoInput
        case cannotAddAudioInput
        case finalizeFailed
    }
}