import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import Metal
import os

final class SimpleRecordingSink: @unchecked Sendable {
    private let log = OSLog(subsystem: "com.vantaview", category: "SimpleRecordingSink")
    private let recorder: ProgramRecorder
    private let converter: TextureToSampleBufferConverter?
    
    private var isActive = false
    private var processingTasks: Set<Task<Void, Never>> = []
    
    init(recorder: ProgramRecorder, device: MTLDevice) {
        self.recorder = recorder
        self.converter = try? TextureToSampleBufferConverter(device: device)
        os_log(.info, log: log, "🎬 SimpleRecordingSink initialized (GPU converter: %{public}@)", converter == nil ? "unavailable" : "available")
    }
    
    deinit {
        for task in processingTasks { task.cancel() }
        processingTasks.removeAll()
    }
    
    func setActive(_ active: Bool) {
        isActive = active
        os_log(.info, log: log, "🎬 Recording sink set to %{public}@", active ? "ACTIVE" : "INACTIVE")
        if !active {
            for task in processingTasks { task.cancel() }
            processingTasks.removeAll()
        }
    }
    
    func appendVideoTexture(_ texture: MTLTexture, timestamp: CMTime) {
        guard isActive else {
            os_log(.info, log: log, "🎬 Ignoring video texture - sink inactive")
            return
        }
        guard let converter else {
            os_log(.error, log: log, "🎬 No GPU converter available; cannot record video")
            return
        }
        
        let task = Task.detached { [recorder, converter, log] in
            do {
                let sb = try await converter.convertTexture(texture, timestamp: timestamp)
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sb) {
                    await recorder.appendVideoPixelBuffer(pixelBuffer, presentationTime: timestamp)
                    print("🎬 SimpleRecordingSink: appended video pixel at \(timestamp.seconds)")
                } else {
                    os_log(.error, log: log, "🎬 Failed to extract pixel buffer from CMSampleBuffer")
                }
            } catch {
                os_log(.error, log: log, "🎬 Video conversion/append error: %{public}@", error.localizedDescription)
            }
        }
        processingTasks.insert(task)
        Task { [weak self] in
            _ = await task.result
            self?.processingTasks.remove(task)
        }
    }
    
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isActive else {
            os_log(.info, log: log, "🎬 Ignoring audio buffer - sink inactive")
            return
        }
        Task.detached { [recorder] in
            await recorder.appendAudioSampleBuffer(sampleBuffer)
        }
    }
}