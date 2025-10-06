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
    
    enum RecordingSourceMode: Sendable {
        case live
        case filePlayback
    }
    
    struct FinalizeSnapshot: Sendable {
        var isFinalizing: Bool
        var fraction: Double
        var remainingVideo: Int
        var remainingAudio: Int
        var totalWrittenVideo: Int64
        var totalWrittenAudio: Int64
    }
    
    // State
    private(set) var isRecording = false
    private(set) var outputURL: URL?
    private(set) var lastError: Error?
    private(set) var startedAtCMTime: CMTime?
    
    private var isFinalizingWriter = false
    private var sessionStarted = false
    private var hasReceivedFrames = false
    private var lastVideoPTS: CMTime?
    private var sourceMode: RecordingSourceMode = .live
    private var acceptingNewAppends = false
    
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
    
    // Drainers (Task-based, persistent)
    private var drainingVideoTask: Task<Void, Never>?
    private var drainingAudioTask: Task<Void, Never>?
    private var drainingVideo = false
    private var drainingAudio = false
    
    // Finalization progress bookkeeping
    private var initialPendingVideo: Int = 0
    private var initialPendingAudio: Int = 0
    private var lastFinalizeCompletedAt: CFAbsoluteTime?
    
    // MARK: - Public Configuration
    
    func setSourceMode(_ mode: RecordingSourceMode) {
        sourceMode = mode
        print("🎬 ProgramRecorder: Source mode set to \(mode == .live ? "LIVE" : "FILE PLAYBACK")")
    }
    
    func updateVideoConfig(expectedFPS: Double? = nil, allowFrameReordering: Bool? = nil) {
        if let fps = expectedFPS {
            requestedVideoConfig.fps = fps
        }
        if let allow = allowFrameReordering {
            requestedVideoConfig.allowFrameReordering = allow
        }
        print("🎬 ProgramRecorder: Updated video config - fps: \(requestedVideoConfig.fps), reorder: \(requestedVideoConfig.allowFrameReordering)")
    }
    
    // Expose a lightweight progress snapshot for UI polling
    func progressSnapshot() -> FinalizeSnapshot {
        let remainingV = videoQueue.count
        let remainingA = audioQueue.count
        let initial = max(1, initialPendingVideo + initialPendingAudio)
        var fraction: Double = 0.0
        if isFinalizingWriter {
            let remaining = remainingV + remainingA
            fraction = Double(initial - remaining) / Double(initial)
            if remaining == 0 {
                fraction = min(0.99, max(0.0, fraction))
            }
            fraction = min(0.99, max(0.0, fraction))
        } else if lastFinalizeCompletedAt != nil {
            fraction = 1.0
        } else {
            fraction = isRecording ? 0.0 : 0.0
        }
        return FinalizeSnapshot(
            isFinalizing: isFinalizingWriter,
            fraction: fraction,
            remainingVideo: remainingV,
            remainingAudio: remainingA,
            totalWrittenVideo: totalVideoFramesWritten,
            totalWrittenAudio: totalAudioFramesWritten
        )
    }
    
    // MARK: - Lifecycle
    
    func start(url: URL, container: Container = .mov, requestedVideo: VideoConfig = .default(), requestedAudio: AudioConfig = .default()) async throws {
        try Task.checkCancellation()
        guard !isRecording else { return }
        
        await teardownInternalState(reason: "begin start()")
        
        let preparedURL = try await prepareOutputURL(url)
        print("🎬 ProgramRecorder: STARTING RECORDING SESSION")
        print("🎬 ProgramRecorder: Output path: \(preparedURL.path)")
        print("🎬 ProgramRecorder: Container: \(container)")
        print("🎬 ProgramRecorder: Requested Video cfg: \(requestedVideo.width)x\(requestedVideo.height) @\(requestedVideo.fps)fps reorder=\(requestedVideo.allowFrameReordering)")
        print("🎬 ProgramRecorder: Requested Audio cfg: \(requestedAudio.sampleRate)Hz \(requestedAudio.channels)ch")
        
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
        lastVideoPTS = nil
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
        
        // Reset finalize progress state
        initialPendingVideo = 0
        initialPendingAudio = 0
        lastFinalizeCompletedAt = nil
        
        isRecording = true
        acceptingNewAppends = true
        print("🎬 ProgramRecorder: Recording session initialized, waiting for first VIDEO frame for timebase…")
    }
    
    private func prepareOutputURL(_ url: URL) async throws -> URL {
        let fileManager = FileManager.default
        let parentDir = url.deletingLastPathComponent()
        
        print("🎬 ProgramRecorder: Preparing output URL: \(url.path)")
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
                print("🎬 ProgramRecorder: Removed pre-existing file at destination")
            } catch {
                print("🎬 ProgramRecorder: Could not remove pre-existing file: \(error)")
                throw error
            }
        }
        
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
        guard isRecording || hasReceivedFrames else {
            if let url = outputURL { return url }
            throw RecordingError.notRecording
        }
        
        acceptingNewAppends = false
        isFinalizingWriter = true
        isRecording = false
        
        // Capture initial pending counts for progress
        initialPendingVideo = videoQueue.count
        initialPendingAudio = audioQueue.count
        print("🎬 ProgramRecorder: Initial pending for finalize - video:\(initialPendingVideo) audio:\(initialPendingAudio)")
        
        startVideoDrainIfNeeded()
        startAudioDrainIfNeeded()
        
        let didFlush = await flushQueuesBeforeFinish(timeoutSeconds: 10.0)
        print("🎬 ProgramRecorder: Flush before finish completed (ok=\(didFlush)). Remaining - video:\(videoQueue.count) audio:\(audioQueue.count)")
        
        guard let writer = writer else {
            print("🎬 ProgramRecorder: No writer created, no file to finalize")
            guard let url = outputURL else { throw RecordingError.noWriter }
            await teardownInternalState(reason: "stopAndFinalize() with no writer")
            lastFinalizeCompletedAt = CFAbsoluteTimeGetCurrent()
            return url
        }
        
        if writer.status == .failed {
            print("🎬 ProgramRecorder: Writer is FAILED before finish - \(writer.error?.localizedDescription ?? "unknown error")")
        }
        
        guard hasReceivedFrames else {
            print("🎬 ProgramRecorder: No frames received, cancelling writer")
            writer.cancelWriting()
            await teardownInternalState(reason: "stopAndFinalize() no frames")
            throw RecordingError.noFramesReceived
        }
        
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        let url: URL = try await withCheckedThrowingContinuation { cont in
            writer.finishWriting {
                print("🎬 ProgramRecorder: finishWriting() completed with status: \(writer.status.rawValue), error: \(writer.error?.localizedDescription ?? "nil")")
                if writer.status == .completed {
                    cont.resume(returning: writer.outputURL)
                } else {
                    cont.resume(throwing: writer.error ?? RecordingError.finalizeFailed)
                }
            }
        }
        
        lastFinalizeCompletedAt = CFAbsoluteTimeGetCurrent()
        await teardownInternalState(reason: "post-finishWriting")
        return url
    }
    
    // MARK: - Public Ingest
    
    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) async {
        guard acceptingNewAppends && !isFinalizingWriter else { return }
        totalVideoFramesReceived &+= 1
        
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            droppedVideoFrames &+= 1
            print("🎬 ProgramRecorder: DROP video - no image buffer")
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        await appendVideoPixelBuffer(pb, presentationTime: pts)
    }
    
    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) async {
        guard acceptingNewAppends && !isFinalizingWriter else { return }
        totalAudioFramesReceived &+= 1
        
        do {
            try Task.checkCancellation()
            audioQueue.append(sampleBuffer)
            startAudioDrainIfNeeded()
        } catch {
            lastError = error
            logFatalIfNeeded(context: "appendAudioSampleBuffer()", error: error)
        }
    }
    
    func appendVideoPixelBuffer(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) async {
        guard acceptingNewAppends && !isFinalizingWriter else { return }
        totalVideoFramesReceived &+= 1
        
        if let last = lastVideoPTS, CMTimeCompare(presentationTime, last) <= 0 {
            droppedVideoFrames &+= 1
            print("🎬 ProgramRecorder: DROP video - nonmonotonic PTS (last: \(last.seconds), new: \(presentationTime.seconds))")
            return
        }
        lastVideoPTS = presentationTime
        
        do {
            try Task.checkCancellation()
            if writer == nil {
                try configureWriterForFirstVideoPixelBuffer(pixelBuffer)
            } else if videoInput == nil {
                try addVideoInputToExistingWriter(for: pixelBuffer)
            } else if let w = writer, w.status != .writing {
                print("🎬 ProgramRecorder: Writer status is not writing (\(w.status.rawValue)); reinitializing writer")
                await teardownWriterOnly(reason: "writer not writing on append")
                try configureWriterForFirstVideoPixelBuffer(pixelBuffer)
            }
            if !sessionStarted {
                try startSession(at: presentationTime)
            }
            let wasEmpty = videoQueue.isEmpty
            videoQueue.append((pixelBuffer, presentationTime))
            if videoQueue.count == 1 || videoQueue.count % 60 == 0 {
                print("🎬 ProgramRecorder: Video queue depth = \(videoQueue.count)")
            }
            if wasEmpty { startVideoDrainIfNeeded() }
            startAudioDrainIfNeeded()
        } catch {
            lastError = error
            logFatalIfNeeded(context: "appendVideoPixelBuffer()", error: error)
        }
    }
    
    // MARK: - Drainers (Task-based, persistent)
    
    private func startVideoDrainIfNeeded() {
        guard let input = videoInput, let adaptor = pixelBufferAdaptor else { return }
        if drainingVideoTask != nil { return }
        drainingVideo = true
        drainingVideoTask = Task.detached(priority: .userInitiated) { [weak self, input, adaptor] in
            guard let self else { return }
            print("🎬 ProgramRecorder: Video drain task started (expectsRealTime=\(input.expectsMediaDataInRealTime))")
            while await self.shouldKeepDrainingVideo() {
                while !input.isReadyForMoreMediaData {
                    let keep = await self.shouldKeepDrainingVideo()
                    if !keep { break }
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
                
                var processed = 0
                while input.isReadyForMoreMediaData {
                    let next: (CVPixelBuffer, CMTime)? = await self.popNextVideo()
                    guard let (pb, ts) = next else { break }
                    let ok = adaptor.append(pb, withPresentationTime: ts)
                    if !ok {
                        print("🎬 ProgramRecorder: VIDEO append FAILED at \(ts.seconds) (writerStatus=\(String(describing: await self.writer?.status.rawValue)), error=\(String(describing: await self.writer?.error?.localizedDescription)))")
                    } else if await self.totalVideoFramesWritten == 0 {
                        print("🎬 ProgramRecorder: First video frame appended at \(ts.seconds)s")
                    }
                    await self.afterVideoAppend(ok: ok, ts: ts)
                    processed &+= 1
                }
                
                if processed == 0 {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
            }
            await self.endVideoDrain()
            print("🎬 ProgramRecorder: Video drain task ended")
        }
    }
    
    private func startAudioDrainIfNeeded() {
        guard let input = audioInput else { return }
        guard sessionStarted else { return }
        if drainingAudioTask != nil { return }
        drainingAudio = true
        drainingAudioTask = Task.detached(priority: .userInitiated) { [weak self, input] in
            guard let self else { return }
            print("🎬 ProgramRecorder: Audio drain task started (expectsRealTime=\(input.expectsMediaDataInRealTime))")
            while await self.shouldKeepDrainingAudio() {
                while !input.isReadyForMoreMediaData {
                    let keep = await self.shouldKeepDrainingAudio()
                    if !keep { break }
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
                
                var processed = 0
                while input.isReadyForMoreMediaData {
                    let next: CMSampleBuffer? = await self.popNextAudio()
                    guard let sb = next else { break }
                    let t0 = CFAbsoluteTimeGetCurrent()
                    let ok = input.append(sb)
                    if !ok {
                        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
                        print("🎬 ProgramRecorder: AUDIO append FAILED at \(pts.seconds) (writerStatus=\(String(describing: await self.writer?.status.rawValue)), error=\(String(describing: await self.writer?.error?.localizedDescription)))")
                    }
                    await self.afterAudioAppend(ok: ok, t0: t0, buffer: sb)
                    processed &+= 1
                }
                
                if processed == 0 {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
            }
            await self.endAudioDrain()
            print("🎬 ProgramRecorder: Audio drain task ended")
        }
    }
    
    private func shouldKeepDrainingVideo() async -> Bool {
        if isFinalizingWriter { return !videoQueue.isEmpty }
        return drainingVideo && (isRecording || !videoQueue.isEmpty) && !isFinalizingWriter
    }
    
    private func shouldKeepDrainingAudio() async -> Bool {
        if isFinalizingWriter { return !audioQueue.isEmpty }
        return drainingAudio && (isRecording || !audioQueue.isEmpty) && !isFinalizingWriter
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
        if writer.status == .unknown {
            print("🎬 ProgramRecorder: Writer status unknown at startSession; did we call startWriting()? (will throw)")
            throw RecordingError.noWriter
        }
        guard writer.status == .writing else {
            print("🎬 ProgramRecorder: Writer not in writing state at startSession (status=\(writer.status.rawValue), error=\(writer.error?.localizedDescription ?? "nil"))")
            throw writer.error ?? RecordingError.finalizeFailed
        }
        writer.startSession(atSourceTime: pts)
        sessionStarted = true
        startedAtCMTime = pts
        print("🎬 ProgramRecorder: startSession at VIDEO PTS = \(pts.seconds)s (value=\(pts.value), timescale=\(pts.timescale))")
        startAudioDrainIfNeeded()
    }
    
    private func configureWriterForFirstVideoPixelBuffer(_ pb: CVPixelBuffer) throws {
        guard let url = outputURL else { throw RecordingError.missingURL }
        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pb)
        
        print("🎬 ProgramRecorder: Creating AVAssetWriter at \(url.path)")
        let writer = try AVAssetWriter(outputURL: url, fileType: pendingContainer.avFileType)
        writer.shouldOptimizeForNetworkUse = (pendingContainer == .mp4)
        
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: requestedVideoConfig.bitrate,
            AVVideoExpectedSourceFrameRateKey: Int(max(1.0, requestedVideoConfig.fps.rounded())),
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
        vInput.expectsMediaDataInRealTime = (sourceMode == .live)
        guard writer.canAdd(vInput) else {
            print("🎬 ProgramRecorder: cannot add video input to writer")
            throw RecordingError.cannotAddVideoInput
        }
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
            print("🎬 ProgramRecorder: startWriting FAILED: \(writer.error?.localizedDescription ?? "unknown")")
            throw writer.error ?? RecordingError.finalizeFailed
        }
        print("🎬 ProgramRecorder: startWriting OK (status=\(writer.status.rawValue)) expectsRealTime(video)=\(vInput.expectsMediaDataInRealTime) expectsRealTime(audio)=\(audioInput?.expectsMediaDataInRealTime ?? false)")
        
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
            AVVideoExpectedSourceFrameRateKey: Int(max(1.0, requestedVideoConfig.fps.rounded())),
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
        vInput.expectsMediaDataInRealTime = (sourceMode == .live)
        
        guard writer.canAdd(vInput) else {
            print("🎬 ProgramRecorder: cannot add late video input")
            throw RecordingError.cannotAddVideoInput
        }
        writer.add(vInput)
        
        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vInput, sourcePixelBufferAttributes: adaptorAttrs)
        
        print("🎬 ProgramRecorder: Added late video input. expectsRealTime(video)=\(vInput.expectsMediaDataInRealTime)")
        
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
            print("🎬 ProgramRecorder: startWriting (audio-only) FAILED: \(writer.error?.localizedDescription ?? "unknown")")
            throw writer.error ?? RecordingError.finalizeFailed
        }
        print("🎬 ProgramRecorder: Audio-only writer created. expectsRealTime(audio)=\(aInput.expectsMediaDataInRealTime)")
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
        input.expectsMediaDataInRealTime = (sourceMode == .live)
        return input
    }
    
    private func flushQueuesBeforeFinish(timeoutSeconds: Double) async -> Bool {
        let start = CFAbsoluteTimeGetCurrent()
        while CFAbsoluteTimeGetCurrent() - start < timeoutSeconds {
            if videoQueue.isEmpty && audioQueue.isEmpty {
                print("🎬 ProgramRecorder: Queues empty before finish")
                return true
            }
            startVideoDrainIfNeeded()
            startAudioDrainIfNeeded()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return videoQueue.isEmpty && audioQueue.isEmpty
    }
    
    private func logFatalIfNeeded(context: String, error: Error) {
        print("🎬 ProgramRecorder: ERROR in \(context): \(error.localizedDescription)")
        if let w = writer {
            print("🎬 ProgramRecorder: Writer status=\(w.status.rawValue) error=\(w.error?.localizedDescription ?? "nil")")
        } else {
            print("🎬 ProgramRecorder: Writer is nil at time of error")
        }
    }
    
    private func stopSilentlyOnError() async {
        print("🎬 ProgramRecorder: stopSilentlyOnError() invoked - lastError=\(lastError?.localizedDescription ?? "nil") writerStatus=\(String(describing: writer?.status.rawValue)) writerError=\(String(describing: writer?.error?.localizedDescription))")
    }
    
    // MARK: - Teardown helpers
    
    private func teardownWriterOnly(reason: String) async {
        print("🎬 ProgramRecorder: Tearing down writer only (\(reason))")
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        writer = nil
        sessionStarted = false
        startedAtCMTime = nil
    }
    
    private func teardownInternalState(reason: String) async {
        print("🎬 ProgramRecorder: Full teardown (\(reason))")
        drainingVideoTask?.cancel()
        drainingAudioTask?.cancel()
        drainingVideoTask = nil
        drainingAudioTask = nil
        drainingVideo = false
        drainingAudio = false
        
        videoQueue.removeAll()
        audioQueue.removeAll()
        
        await teardownWriterOnly(reason: reason)
        
        acceptingNewAppends = false
        isFinalizingWriter = false
        isRecording = false
        hasReceivedFrames = false
        lastVideoPTS = nil
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