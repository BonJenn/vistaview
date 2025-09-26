import Foundation
import AVFoundation

protocol RecordingSink: Sendable {
    func appendVideo(_ sampleBuffer: CMSampleBuffer)
    func appendAudio(_ sampleBuffer: CMSampleBuffer)
}

final class ProgramFrameTap: @unchecked Sendable, RecordingSink {
    enum Event {
        case video(CMSampleBuffer)
        case audio(CMSampleBuffer)
    }
    
    private let recorder: ProgramRecorder
    private let stream: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private var workerTask: Task<Void, Never>?
    
    private(set) var droppedEvents = 0
    private var videoFrameCount: Int64 = 0
    private var audioFrameCount: Int64 = 0
    
    init(recorder: ProgramRecorder, bufferCapacity: Int = 240) {
        self.recorder = recorder
        var cont: AsyncStream<Event>.Continuation!
        self.stream = AsyncStream<Event>(bufferingPolicy: .bufferingNewest(bufferCapacity)) { c in
            cont = c
        }
        self.continuation = cont
        self.workerTask = Task.detached(priority: .utility) { [stream, recorder] in
            print("🎬 ProgramFrameTap: Worker task started")
            for await ev in stream {
                try? Task.checkCancellation()
                switch ev {
                case .video(let sb):
                    print("🎬 ProgramFrameTap: Processing video sample buffer")
                    await recorder.appendVideoSampleBuffer(sb)
                case .audio(let sb):
                    print("🎬 ProgramFrameTap: Processing audio sample buffer")
                    await recorder.appendAudioSampleBuffer(sb)
                }
            }
            print("🎬 ProgramFrameTap: Worker task ended")
        }
        print("🎬 ProgramFrameTap: Initialized with buffer capacity \(bufferCapacity)")
    }
    
    deinit {
        print("🎬 ProgramFrameTap: Deinitializing")
        stop()
    }
    
    func stop() {
        print("🎬 ProgramFrameTap: Stopping")
        continuation.finish()
        workerTask?.cancel()
        workerTask = nil
    }
    
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        videoFrameCount += 1
        if videoFrameCount % 30 == 0 {
            print("🎬 ProgramFrameTap: Received video frame #\(videoFrameCount)")
        }
        continuation.yield(.video(sampleBuffer))
    }
    
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        audioFrameCount += 1
        if audioFrameCount % 100 == 0 {
            print("🎬 ProgramFrameTap: Received audio frame #\(audioFrameCount)")
        }
        continuation.yield(.audio(sampleBuffer))
    }
}