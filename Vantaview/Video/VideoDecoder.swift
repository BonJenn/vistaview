import Foundation
import AVFoundation
import VideoToolbox
import CoreVideo
import CoreMedia

final class VideoDecoder {
    private let url: URL
    private let decodeQueue = DispatchQueue(label: "video.decoder.queue", qos: .userInitiated)
    private var asset: AVAsset?
    private var reader: AVAssetReader?
    private var trackOutput: AVAssetReaderTrackOutput?
    private var session: VTDecompressionSession?
    private var formatDesc: CMFormatDescription?
    private var videoTrack: AVAssetTrack?
    private var startTime: CMTime = .zero
    
    // Public callbacks
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    var onFinished: (() -> Void)?
    var onError: ((Error) -> Void)?
    
    // Control
    private var isRunning = false
    
    init(url: URL) {
        self.url = url
    }
    
    deinit {
        invalidateSession()
        reader?.cancelReading()
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        decodeQueue.async { [weak self] in
            self?.setupAndRun()
        }
    }
    
    func stop() {
        isRunning = false
        decodeQueue.async { [weak self] in
            self?.reader?.cancelReading()
            self?.invalidateSession()
        }
    }
    
    func seek(to time: CMTime) {
        decodeQueue.async { [weak self] in
            guard let self else { return }
            self.startTime = time
            self.reader?.cancelReading()
            self.invalidateSession()
            self.isRunning = true
            self.setupAndRun()
        }
    }
    
    private func setupAndRun() {
        do {
            let asset = AVURLAsset(url: url)
            self.asset = asset
            
            let videoTrack = try awaitTrack(asset: asset)
            if let anyDesc = videoTrack.formatDescriptions.first {
                self.formatDesc = (anyDesc as! CMFormatDescription)
            } else {
                self.formatDesc = nil
            }
            
            try setupReader(for: asset, track: videoTrack, startTime: startTime)
            try setupDecompressionSession(with: videoTrack)
            runReadLoop()
        } catch {
            onError?(error)
            stop()
        }
    }
    
    private func awaitTrack(asset: AVAsset) throws -> AVAssetTrack {
        let semaphore = DispatchSemaphore(value: 0)
        var resultTrack: AVAssetTrack?
        var resultError: Error?
        
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "tracks", error: &error)
            if status == .loaded, let track = asset.tracks(withMediaType: .video).first {
                resultTrack = track
            } else {
                resultError = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        
        if let track = resultTrack { return track }
        throw resultError ?? NSError(domain: "VideoDecoder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video track"])
    }
    
    private func setupReader(for asset: AVAsset, track: AVAssetTrack, startTime: CMTime) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        if startTime > .zero {
            let duration = CMTime.positiveInfinity
            reader.timeRange = CMTimeRange(start: startTime, duration: duration)
        }
        guard reader.canAdd(output) else {
            throw NSError(domain: "VideoDecoder", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add track output"])
        }
        reader.add(output)
        if !reader.startReading() {
            throw reader.error ?? NSError(domain: "VideoDecoder", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to start reading"])
        }
        self.reader = reader
        self.trackOutput = output
    }
    
    private func setupDecompressionSession(with track: AVAssetTrack) throws {
        guard let formatDesc = self.formatDesc else {
            throw NSError(domain: "VideoDecoder", code: -4, userInfo: [NSLocalizedDescriptionKey: "Missing format description"])
        }
        
        let pixelBufferAttrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionOutputCallback,
            decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: nil,
            imageBufferAttributes: pixelBufferAttrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        
        guard status == noErr, let session else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "VTDecompressionSessionCreate failed: \(status)"])
        }
        
        // Real-time config
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        let threads = NSNumber(value: 4)
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_ThreadCount, value: threads)
        
        self.session = session
    }
    
    private func runReadLoop() {
        guard let reader = reader, let output = trackOutput else { return }
        while isRunning, reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else {
                break
            }
            guard let session = session else { break }
            
            let decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
            var outputFlags = VTDecodeInfoFlags()
            
            let status = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sample,
                flags: decodeFlags,
                frameRefcon: nil,
                infoFlagsOut: &outputFlags
            )
            
            if status != noErr {
                onError?(NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "DecodeFrame failed: \(status)"]))
            }
        }
        
        if let session = session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
        }
        
        if reader.status == .completed || reader.status == .failed || reader.status == .cancelled {
            onFinished?()
        }
        
        stop()
    }
    
    private func invalidateSession() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
    }
}

private func decompressionOutputCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard status == noErr,
          let refCon = decompressionOutputRefCon,
          let imageBuffer = imageBuffer else { return }
    
    let decoder = Unmanaged<VideoDecoder>.fromOpaque(refCon).takeUnretainedValue()
    if let pb = imageBuffer as? CVPixelBuffer {
        decoder.onFrame?(pb, presentationTimeStamp)
    }
}