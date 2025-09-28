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
    
    let recorder: ProgramRecorder
    
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
            for await ev in stream {
                try? Task.checkCancellation()
                switch ev {
                case .video(let sb):
                    await recorder.appendVideoSampleBuffer(sb)
                case .audio(let sb):
                    await recorder.appendAudioSampleBuffer(sb)
                }
            }
        }
    }
    
    deinit {
        stop()
    }
    
    func stop() {
        continuation.finish()
        workerTask?.cancel()
        workerTask = nil
    }
    
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        videoFrameCount += 1
        continuation.yield(.video(sampleBuffer))
    }
    
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        audioFrameCount += 1
        continuation.yield(.audio(sampleBuffer))
    }
}