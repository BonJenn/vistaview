// // File: Views/Core/Streamer.swift
import Foundation
import AVFoundation
import CoreVideo
import AppKit
import VideoToolbox
import HaishinKit

/// Streamer captures frames from an AVPlayerItem, encodes them to H.264,
/// and streams via RTMP using HaishinKit 2.x MediaMixer + HKStream.
final class Streamer: ObservableObject {
    // MARK: - Public Properties
    @Published var isStreaming: Bool = false

    // MARK: - Private Properties
    private let videoOutput: AVPlayerItemVideoOutput
    private weak var hostView: NSView?
    private var cvDisplayLink: CVDisplayLink?
    private var compressionSession: VTCompressionSession?
    private var frameCount: Int64 = 0
    private let rtmpConnection: RTMPConnection
    private let rtmpStream: RTMPStream
    private let mixer: MediaMixer

    // MARK: - Initialization
    /// - Parameters:
    ///   - streamURL: RTMP server URL (e.g. rtmp://example.com/app)
    ///   - streamName: Stream key or name
    init(streamURL: String, streamName: String) {
        // Configure pixel buffer output for BGRA frames
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)

        // Setup HaishinKit pipeline
        rtmpConnection = RTMPConnection()
        rtmpStream = RTMPStream(connection: rtmpConnection)
        mixer = MediaMixer()
        
        // Attach mixer to stream and connect
        Task {
            await mixer.addOutput(rtmpStream)
            _ = try? await rtmpStream.publish(streamName)
            _ = try? await rtmpConnection.connect(streamURL)
        }

        // Setup H.264 compression
        setupCompressionSession()
    }

    deinit {
        stopStreaming()
    }

    // MARK: - Public Methods
    /// Start capturing and streaming frames from the player item.
    func startStreaming(playerItem: AVPlayerItem, on view: NSView) {
        guard !isStreaming else { return }
        // Attach video output and start display link
        playerItem.add(videoOutput)
        hostView = view
        setupDisplayLink(for: view)
        isStreaming = true
    }

    /// Stop streaming and release resources.
    func stopStreaming() {
        guard isStreaming else { return }
        isStreaming = false
        hostView = nil
        // Invalidate display link
        if #available(macOS 15.0, *) {
            // NSView.displayLink auto-invalidates
        } else {
            if let dl = cvDisplayLink {
                CVDisplayLinkStop(dl)
                cvDisplayLink = nil
            }
        }
        // Complete and invalidate compression
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        // Close RTMP connection
        Task {
            _ = try? await rtmpStream.close()
            _ = try? await rtmpConnection.close()
        }
    }

    // MARK: - Display Link Setup
    private func setupDisplayLink(for view: NSView) {
        if #available(macOS 15.0, *) {
            // Modern API for view vsync
            view.displayLink(target: self, selector: #selector(onDisplayLinkFired))
        } else {
            // Fallback CVDisplayLink
            var dl: CVDisplayLink?
            CVDisplayLinkCreateWithActiveCGDisplays(&dl)
            guard let displayLink = dl else { return }
            cvDisplayLink = displayLink
            CVDisplayLinkSetOutputCallback(displayLink, { _, _, _, _, _, ctx in
                let streamer = Unmanaged<Streamer>.fromOpaque(ctx!).takeUnretainedValue()
                streamer.captureFrame()
                return kCVReturnSuccess
            }, Unmanaged.passUnretained(self).toOpaque())
            CVDisplayLinkStart(displayLink)
        }
    }

    @objc private func onDisplayLinkFired(_ link: CVDisplayLink) {
        captureFrame()
    }

    // MARK: - Frame Capture & Encoding
    private func captureFrame() {
        let hostTime = CACurrentMediaTime()
        let itemTime = videoOutput.itemTime(forHostTime: hostTime)
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
              let pixelBuffer = videoOutput.copyPixelBuffer(
                  forItemTime: itemTime,
                  itemTimeForDisplay: nil
              ),
              let session = compressionSession else {
            return
        }
        let pts = CMTime(value: frameCount, timescale: 30)
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        if status != noErr {
            print("❌ Error encoding frame: \(status)")
        }
        frameCount += 1
    }

    private func setupCompressionSession() {
        // TODO: Use actual video dimensions
        let width: Int32 = 1280
        let height: Int32 = 720
        var sessionOut: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            compressionSessionOut: &sessionOut
        )
        guard status == noErr, let session = sessionOut else {
            print("❌ VTCompressionSessionCreate failed: \(status)")
            return
        }
        compressionSession = session
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: 3_000_000))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
    }

    // MARK: - Compression Callback
    private let compressionOutputCallback: VTCompressionOutputCallback = { refCon, _, status, _, sampleBuffer in
        guard status == noErr,
              let sbuf = sampleBuffer,
              CMSampleBufferDataIsReady(sbuf) else { return }
        let streamer = Unmanaged<Streamer>.fromOpaque(refCon!).takeUnretainedValue()
        Task {
            // TODO: Replace with actual MediaMixer API call:
            // await streamer.mixer.appendSampleBuffer(sbuf, type: .video)
        }
    }
}
