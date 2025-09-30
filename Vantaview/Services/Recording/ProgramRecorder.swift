import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
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
    
    // State
    private(set) var isRecording = false
    private(set) var outputURL: URL?
    private(set) var lastError: Error?
    private(set) var startedAtCMTime: CMTime?
    
    private var isFinalizingWriter = false
    private var sessionStarted = false
    private var hasReceivedFrames = false
    
    // Diagnostics
    private(set) var totalVideoFramesReceived: Int64 = 0
    private(set) var totalAudioFramesReceived: Int64 = 0
    private(set) var totalVideoFramesWritten: Int64 = 0
    private(set) var totalAudioFramesWritten: Int64 = 0
    private(set) var droppedVideoFrames = 0
    private(set) var droppedAudioFrames = 0
    private(set) var averageWriteLatencyMs: Double = 0
    private var writeMeasurementsCount: Int = 0
    private var bytesWritten: Int64 = 0
    private var lastBitrateSampleTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private(set) var estimatedBitrateBps: Double = 0
    
    // Writer
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    // Configuration
    private var pendingContainer: Container = .mov
    private var requestedVideoConfig: VideoConfig = .default()
    private var requestedAudioConfig: AudioConfig = .default()
    
    // Internal queues (actor-protected)
    private var videoQueue: [(CVPixelBuffer, CMTime)] = []
    private var audioQueue: [CMSampleBuffer] = []
    private var drainingVideoTask: Task<Void, Never>?
    private var drainingAudioTask: Task<Void, Never>?
    private var drainingVideo = false
    private var drainingAudio = false
    
    // MARK: - Lifecycle
    
    func start(url: URL, container: Container = .mov, requestedVideo: VideoConfig = .default(), requestedAudio: AudioConfig = .default()) async throws {
        try Task.checkCancellation()
        guard !isRecording else { return }
        
        let preparedURL = try await prepareOutputURL(url)
        print("🎬 ProgramRecorder: STARTING RECORDING SESSION")
        print("🎬 ProgramRecorder: Output path: \(preparedURL.path)")
        print("🎬 ProgramRecorder: Container: \(container)")
        print("🎬 ProgramRecorder: Video config: \(requestedVideo.width)x\(requestedVideo.height) @\(requestedVideo.fps)fps")
        print("🎬 ProgramRecorder: Audio config: \(requestedAudio.sampleRate)Hz \(requestedAudio.channels)ch")
        
        // Reset state
        isFinalizingWriter = false
        sessionStarted = false
        hasReceivedFrames = false
        totalVideoFramesReceived = 0
        totalAudioFramesReceived = 0
        totalVideoFramesWritten = 0
        totalAudioFramesWritten = 0
        droppedVideoFrames = 0
        droppedAudioFrames = 0
        averageWriteLatencyMs = 0
        writeMeasurementsCount = 0
        bytesWritten = 0
        estimatedBitrateBps = 0
        lastBitrateSampleTime = CFAbsoluteTimeGetCurrent()
        startedAtCMTime = nil
        videoQueue.removeAll()
        audioQueue.removeAll()
        drainingVideoTask?.cancel()
        drainingAudioTask?.cancel()
        drainingVideoTask = nil
        drainingAudioTask = nil
        drainingVideo = false
        drainingAudio = false
        
        lastError = nil
        outputURL = preparedURL
        pendingContainer = container
        requestedVideoConfig = requestedVideo
        requestedAudioConfig = requestedAudio
        
        isRecording = true
        print("🎬 ProgramRecorder: Recording session initialized, waiting for first frame…")
    }
    
    private func prepareOutputURL(_ url: URL) async throws -> URL {
        let fileManager = FileManager.default
        let parentDir = url.deletingLastPathComponent()
        
        print("🎬 ProgramRecorder: Preparing output URL: \(url.path)")
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        
        // Probe write access
        try Data().write(to: url)
        try fileManager.removeItem(at: url)
        
        return url
    }
    
    func stopAndFinalize() async throws -> URL {
        try Task.checkCancellation()
        
        print("🎬 ProgramRecorder: STOPPING RECORDING SESSION")
        print("🎬 ProgramRecorder: Current state - isRecording: \(isRecording), hasReceivedFrames: \(hasReceivedFrames)")
        print("🎬 ProgramRecorder: Frame counts - Video: \(totalVideoFramesWritten), Audio: \(totalAudioFramesWritten)")
        
        guard !isFinalizingWriter else {
            if let url = outputURL { return url }
            throw RecordingError.finalizeFailed
        }
        guard isRecording else {
            if let url = outputURL { return url }
            throw RecordingError.notRecording
        }
        
        isFinalizingWriter = true
        isRecording = false
        
        drainingVideoTask?.cancel()
        drainingAudioTask?.cancel()
        drainingVideoTask = nil
        drainingAudioTask = nil
        drainingVideo = false
        drainingAudio = false
        
        guard let writer = writer else {
            print("🎬 ProgramRecorder: No writer created, no file to finalize")
            guard let url = outputURL else { throw RecordingError.noWriter }
            return url
        }
        
        guard hasReceivedFrames else {
            print("🎬 ProgramRecorder: No frames received, cancelling writer")
            writer.cancelWriting()
            throw RecordingError.noFramesReceived
        }
        
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        return try await withCheckedThrowingContinuation { cont in
            writer.finishWriting {
                if writer.status == .completed {
                    cont.resume(returning: writer.outputURL)
                } else {
                    cont.resume(throwing: writer.error ?? RecordingError.finalizeFailed)
                }
            }
        }
    }
    
    // MARK: - Public Ingest
    
    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) async {
        guard isRecording && !isFinalizingWriter else { return }
        totalVideoFramesReceived &+= 1
        
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            droppedVideoFrames &+= 1
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        await appendVideoPixelBuffer(pb, presentationTime: pts)
    }
    
    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) async {
        guard isRecording && !isFinalizingWriter else { return }
        totalAudioFramesReceived &+= 1
        
        do {
            try Task.checkCancellation()
            if writer == nil {
                try configureWriterForAudioOnly()
            }
            audioQueue.append(sampleBuffer)
            startAudioDrainIfNeeded()
        } catch {
            lastError = error
            await stopSilentlyOnError()
        }
    }
    
    func appendVideoPixelBuffer(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) async {
        guard isRecording && !isFinalizingWriter else { return }
        totalVideoFramesReceived &+= 1
        
        do {
            try Task.checkCancellation()
            if writer == nil {
                try configureWriterForFirstVideoPixelBuffer(pixelBuffer)
            } else if videoInput == nil {
                try addVideoInputToExistingWriter(for: pixelBuffer)
            }
            if !sessionStarted {
                try startSession(at: presentationTime)
            }
            videoQueue.append((pixelBuffer, presentationTime))
            startVideoDrainIfNeeded()
        } catch {
            lastError = error
            await stopSilentlyOnError()
        }
    }
    
    // MARK: - Drainers (no AVAssetWriterInput callbacks)
    
    private func startVideoDrainIfNeeded() {
        guard let input = videoInput, let adaptor = pixelBufferAdaptor else { return }
        if drainingVideoTask != nil { return }
        drainingVideo = true
        drainingVideoTask = Task.detached(priority: .userInitiated) { [weak self, input, adaptor] in
            guard let self else { return }
            while await self.shouldKeepDrainingVideo() {
                // Wait until the input is ready without using 'await' in an autoclosure
                while true {
                    if input.isReadyForMoreMediaData { break }
                    let keep = await self.shouldKeepDrainingVideo()
                    if !keep { break }
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }

                var processed = 0
                while input.isReadyForMoreMediaData {
                    let next: (CVPixelBuffer, CMTime)? = await self.popNextVideo()
                    guard let (pb, ts) = next else { break }
                    let ok = adaptor.append(pb, withPresentationTime: ts)
                    await self.afterVideoAppend(ok: ok, ts: ts)
                    processed &+= 1
                }

                if processed == 0 {
                    try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
                }
            }
            await self.endVideoDrain()
        }
    }
    
    private func startAudioDrainIfNeeded() {
        guard let input = audioInput else { return }
        if drainingAudioTask != nil { return }
        drainingAudio = true
        drainingAudioTask = Task.detached(priority: .userInitiated) { [weak self, input] in
            guard let self else { return }
            while await self.shouldKeepDrainingAudio() {
                // Wait until the input is ready without using 'await' in an autoclosure
                while true {
                    if input.isReadyForMoreMediaData { break }
                    let keep = await self.shouldKeepDrainingAudio()
                    if !keep { break }
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }

                var processed = 0
                while input.isReadyForMoreMediaData {
                    let next: CMSampleBuffer? = await self.popNextAudio()
                    guard let sb = next else { break }
                    let t0 = CFAbsoluteTimeGetCurrent()
                    let ok = input.append(sb)
                    await self.afterAudioAppend(ok: ok, t0: t0, buffer: sb)
                    processed &+= 1
                }

                if processed == 0 {
                    try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
                }
            }
            await self.endAudioDrain()
        }
    }

    private func shouldKeepDrainingVideo() async -> Bool {
        return drainingVideo && isRecording && !isFinalizingWriter
    }

    private func shouldKeepDrainingAudio() async -> Bool {
        return drainingAudio && isRecording && !isFinalizingWriter
    }
    
    // Helpers for drainers (actor-isolated)
    private func popNextVideo() -> (CVPixelBuffer, CMTime)? {
        if videoQueue.isEmpty { return nil }
        return videoQueue.removeFirst()
    }
    private func popNextAudio() -> CMSampleBuffer? {
        if audioQueue.isEmpty { return nil }
        return audioQueue.removeFirst()
    }
    private func afterVideoAppend(ok: Bool, ts: CMTime) {
        if ok {
            totalVideoFramesWritten &+= 1
            if !hasReceivedFrames {
                hasReceivedFrames = true
            }
        } else {
            droppedVideoFrames &+= 1
        }
    }
    private func afterAudioAppend(ok: Bool, t0: CFAbsoluteTime, buffer: CMSampleBuffer) {
        if ok {
            totalAudioFramesWritten &+= 1
            if !hasReceivedFrames {
                hasReceivedFrames = true
            }
            // Diagnostics
            let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            writeMeasurementsCount &+= 1
            averageWriteLatencyMs = averageWriteLatencyMs + (dt - averageWriteLatencyMs) / Double(max(writeMeasurementsCount, 1))
            if let dataBuffer = CMSampleBufferGetDataBuffer(buffer) {
                let byteCount = CMBlockBufferGetDataLength(dataBuffer)
                bytesWritten &+= Int64(byteCount)
            }
            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - lastBitrateSampleTime
            if elapsed >= 1.0 {
                estimatedBitrateBps = Double(bytesWritten) * 8.0 / elapsed
                bytesWritten = 0
                lastBitrateSampleTime = now
            }
        } else {
            droppedAudioFrames &+= 1
        }
    }
    private func endVideoDrain() {
        drainingVideoTask = nil
        drainingVideo = false
    }
    private func endAudioDrain() {
        drainingAudioTask = nil
        drainingAudio = false
    }
    
    // MARK: - Session & Config
    
    private func startSession(at pts: CMTime) throws {
        guard let writer = writer, !sessionStarted else { return }
        guard writer.status == .writing else {
            throw writer.error ?? RecordingError.finalizeFailed
        }
        writer.startSession(atSourceTime: pts)
        sessionStarted = true
        startedAtCMTime = pts
    }
    
    private func configureWriterForFirstVideoPixelBuffer(_ pb: CVPixelBuffer) throws {
        guard let url = outputURL else { throw RecordingError.missingURL }
        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pb)
        
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
        guard writer.canAdd(vInput) else { throw RecordingError.cannotAddVideoInput }
        writer.add(vInput)
        
        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vInput, sourcePixelBufferAttributes: adaptorAttrs)
        
        if audioInput == nil {
            try maybeAddDefaultAudioInput(to: writer)
        }
        
        writer.startWriting()
        if writer.status == .failed {
            throw writer.error ?? RecordingError.finalizeFailed
        }
        
        self.writer = writer
        self.videoInput = vInput
        self.pixelBufferAdaptor = adaptor
    }
    
    private func addVideoInputToExistingWriter(for pb: CVPixelBuffer) throws {
        guard let writer = writer else { throw RecordingError.noWriter }
        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pb)
        
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
        
        guard writer.canAdd(vInput) else { throw RecordingError.cannotAddVideoInput }
        writer.add(vInput)
        
        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vInput, sourcePixelBufferAttributes: adaptorAttrs)
        
        self.videoInput = vInput
        self.pixelBufferAdaptor = adaptor
    }
    
    private func configureWriterForAudioOnly() throws {
        guard let url = outputURL else { throw RecordingError.missingURL }
        let writer = try AVAssetWriter(outputURL: url, fileType: pendingContainer.avFileType)
        writer.shouldOptimizeForNetworkUse = (pendingContainer == .mp4)
        let aInput = try buildAudioInput()
        guard writer.canAdd(aInput) else { throw RecordingError.cannotAddAudioInput }
        writer.add(aInput)
        writer.startWriting()
        if writer.status == .failed {
            throw writer.error ?? RecordingError.finalizeFailed
        }
        self.writer = writer
        self.audioInput = aInput
    }
    
    private func maybeAddDefaultAudioInput(to writer: AVAssetWriter) throws {
        let aInput = try buildAudioInput()
        if writer.canAdd(aInput) {
            writer.add(aInput)
            self.audioInput = aInput
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
    
    private func stopSilentlyOnError() async {
        guard !isFinalizingWriter else { return }
        isFinalizingWriter = true
        isRecording = false
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer?.cancelWriting()
        drainingVideoTask?.cancel()
        drainingAudioTask?.cancel()
        drainingVideoTask = nil
        drainingAudioTask = nil
        drainingVideo = false
        drainingAudio = false
        print("🎬 ProgramRecorder: Stopped silently due to error")
    }
    
    enum RecordingError: Error {
        case notRecording
        case missingURL
        case noWriter
        case cannotAddVideoInput
        case cannotAddAudioInput
        case finalizeFailed
        case outputURLNotWritable
        case noFramesReceived
        case fileNotCreated
    }
}