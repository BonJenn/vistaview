import Foundation
import HaishinKit
import AVFoundation

/// Observable class that manages camera/mic capture and RTMP streaming
@MainActor
final class Streamer: ObservableObject {
    /// The RTMP connection
    let rtmpConnection = RTMPConnection()
    /// The mixer that captures camera + mic
    let mixer = MediaMixer()
    /// The RTMP stream that wraps connection
    let rtmpStream: RTMPStream

    init() {
        rtmpStream = RTMPStream(connection: rtmpConnection)
        
        Task {
            // Add stream as output to mixer
            await mixer.addOutput(rtmpStream)
            
            // Configure stream settings
            await configureStream()
            
            // Configure capture devices
            await configureCaptureSession()
        }
    }
    
    /// Configure stream settings
    private func configureStream() async {
        // Configure video settings
        var videoSettings = VideoCodecSettings(
            videoSize: .init(width: 1280, height: 720),
            profileLevel: kVTProfileLevel_H264_Baseline_3_1 as String,
            bitRate: 2_000_000,
            maxKeyFrameIntervalDuration: 2,
            scalingMode: .trim,
            bitRateMode: .average,
            allowFrameReordering: nil,
            isHardwareEncoderEnabled: true
        )
        await rtmpStream.setVideoSettings(videoSettings)
        
        // Configure audio settings
        var audioSettings = AudioCodecSettings()
        audioSettings.bitrate = 128_000
        await rtmpStream.setAudioSettings(audioSettings)
    }

    /// Configure the underlying capture session via MediaMixer
    private func configureCaptureSession() async {
        // Video device (webcam)
        if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            do {
                try await mixer.attachCamera(videoDevice, track: 0) { videoUnit in
                    videoUnit.isVideoMirrored = true
                    videoUnit.preferredVideoStabilizationMode = .standard
                    videoUnit.colorFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                }
            } catch {
                print("⚠️ Streamer: failed to add camera device – \(error)")
            }
        }

        // Audio device (mic)
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                try await mixer.attachAudio(audioDevice, track: 0) { audioDeviceUnit in
                    // Configure audio device unit if needed
                }
            } catch {
                print("⚠️ Streamer: failed to add audio device – \(error)")
            }
        }
    }

    /// Starts the RTMP stream to the given URL/key
    func startStreaming(streamURL: String, streamKey: String) {
        Task {
            do {
                try await rtmpConnection.connect(streamURL)
                try await rtmpStream.publish(streamKey)
            } catch {
                print("⚠️ Streamer: failed to start streaming – \(error)")
            }
        }
    }

    /// Stops the RTMP stream and closes connection
    func stopStreaming() {
        Task {
            do {
                try await rtmpStream.close()
                try await rtmpConnection.close()
            } catch {
                print("⚠️ Streamer: failed to stop streaming – \(error)")
            }
        }
    }
    
    /// Get the mixer for preview purposes
    var mediaMixer: MediaMixer {
        return mixer
    }
}
