import Foundation

/// Uses an external ffmpeg process to capture the Mac webcam + mic
/// and push to any RTMP endpoint.
final class FFmpegStreamer {
    private var process: Process?

    /// Starts streaming via ffmpeg.
    /// - Parameters:
    ///   - rtmpURL: base RTMP URL, e.g. "rtmp://live.twitch.tv/app"
    ///   - streamKey: your service-specific stream key
    func start(rtmpURL: String, streamKey: String) {
        stop()

        // build full destination URL
        let destination = "\(rtmpURL)/\(streamKey)"

        let ffmpeg = Process()
        ffmpeg.executableURL = URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
        ffmpeg.arguments = [
            "-f", "avfoundation",        // macOS AVFoundation input
            "-framerate", "30",
            "-video_size", "1280x720",
            "-i", "0:0",                 // device indexes (camera:mic)
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-b:v", "2000k", "-maxrate", "2000k", "-bufsize", "4000k",
            "-g", "60",
            "-c:a", "aac", "-b:a", "128k", "-ar", "44100",
            "-f", "flv", destination
        ]

        // optionally capture ffmpeg logs
        ffmpeg.standardOutput = FileHandle.nullDevice
        ffmpeg.standardError  = FileHandle.standardError

        do {
            try ffmpeg.run()
            process = ffmpeg
            print("✅ FFmpeg started, streaming to \(destination)")
        } catch {
            print("❌ FFmpeg failed to start:", error)
        }
    }

    /// Stops the running ffmpeg process, if any.
    func stop() {
        process?.terminate()
        process = nil
        print("🛑 FFmpeg stopped")
    }
}
