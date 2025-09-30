import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

actor ProgramRecordingBridge {
    private var recorder: ProgramRecorder?
    private weak var previewProgramManager: AnyObject?
    
    private var cameraTask: Task<Void, Never>?
    private var mediaTask: Task<Void, Never>?
    private var isConfigured = false
    private var targetFPS: Double = 60.0
    
    func configure(recorder: ProgramRecorder, previewProgramManager: PreviewProgramManager) async {
        self.recorder = recorder
        self.previewProgramManager = previewProgramManager
        self.targetFPS = await MainActor.run { previewProgramManager.targetFPS }
        isConfigured = true
        startOrRestartMediaPumpIfNeeded()
    }
    
    func stop() {
        cameraTask?.cancel()
        cameraTask = nil
        mediaTask?.cancel()
        mediaTask = nil
        isConfigured = false
        recorder = nil
        previewProgramManager = nil
    }
    
    // Camera path: feed the program recorder directly from camera CMSampleBuffers (video PTS preserved)
    func useCameraStream(_ stream: AsyncStream<CMSampleBuffer>) {
        cameraTask?.cancel()
        cameraTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var first = true
            for await sb in stream {
                if Task.isCancelled { break }
                guard let rec = await self.recorder else { continue }
                await rec.appendVideoSampleBuffer(sb)
                if first {
                    first = false
                    print("🎬 ProgramRecordingBridge: First camera frame forwarded to recorder")
                }
            }
        }
    }
    
    private func snapshotProgramOutputs() async -> (AVPlayerItemVideoOutput?, AVPlayer?, Double) {
        let ppmAny = self.previewProgramManager
        return await MainActor.run {
            if let ppm = ppmAny as? PreviewProgramManager {
                return (ppm.programItemVideoOutput, ppm.programPlayer, ppm.targetFPS)
            } else {
                return (nil, nil, 60.0)
            }
        }
    }
    
    // Media path: poll program AVPlayerItemVideoOutput for pixel buffers and forward to recorder with proper timing
    private func startOrRestartMediaPumpIfNeeded() {
        mediaTask?.cancel()
        mediaTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Obtain AVPlayerItemVideoOutput + player + fps via helper
                let (output, player, fps) = await self.snapshotProgramOutputs()
                if let output, let player {
                    let sleepNs = UInt64((1.0 / max(1.0, fps)) * 1_000_000_000.0)
                    var frameIndex: Int64 = 0
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: sleepNs)
                        let host = CACurrentMediaTime()
                        let itemTime = output.itemTime(forHostTime: host)
                        if output.hasNewPixelBuffer(forItemTime: itemTime),
                           let pb = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                            let ts = itemTime.isValid ? itemTime : player.currentTime()
                            if let rec = await self.recorder {
                                await rec.appendVideoPixelBuffer(pb, presentationTime: ts)
                                if frameIndex == 0 {
                                    print("🎬 ProgramRecordingBridge: First media pixel buffer appended @\(ts.seconds)s")
                                }
                            }
                            frameIndex &+= 1
                        }
                    }
                } else {
                    // No media program yet; back off slightly and re-check
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
    }
}