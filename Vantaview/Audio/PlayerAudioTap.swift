import Foundation
import AVFoundation
import CoreMedia
import MediaToolbox

final class PlayerAudioTap: NSObject {
    private(set) var sampleRate: Double = 44100
    private(set) var channels: Int = 2

    private var latestData = Data()
    private var latestFrames: Int = 0

    private(set) var rms: Float = 0
    private(set) var peak: Float = 0

    private var tap: MTAudioProcessingTap?
    private let lock = NSLock()

    init(playerItem: AVPlayerItem) {
        super.init()
        installTap(on: playerItem)
    }

    deinit {
        uninstallTap()
    }

    func fetchLatestInterleavedBuffer() -> (UnsafePointer<Float32>, Int, Int, Double)? {
        lock.lock()
        defer { lock.unlock() }
        guard latestFrames > 0, latestData.count >= latestFrames * channels * MemoryLayout<Float32>.size else {
            return nil
        }
        return (latestData.withUnsafeBytes { $0.bindMemory(to: Float32.self).baseAddress! }, latestFrames, channels, sampleRate)
    }

    private func installTap(on item: AVPlayerItem) {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            init: { tap, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { _ in },
            prepare: { tap, maxFrames, processingFormat in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let obj = Unmanaged<PlayerAudioTap>.fromOpaque(storage).takeUnretainedValue()
                let asbd = processingFormat.pointee
                obj.sampleRate = asbd.mSampleRate
                obj.channels = Int(asbd.mChannelsPerFrame)
            },
            unprepare: { _ in },
            process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
                var sourceFlags: MTAudioProcessingTapFlags = 0
                var framesFromSource: CMItemCount = 0
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap,
                    numberFrames,
                    bufferListInOut,
                    &sourceFlags,
                    nil,
                    &framesFromSource
                )
                guard status == noErr, framesFromSource > 0 else {
                    numberFramesOut.pointee = 0
                    flagsOut.pointee = 0
                    return
                }

                flagsOut.pointee = sourceFlags
                numberFramesOut.pointee = framesFromSource

                let storage = MTAudioProcessingTapGetStorage(tap)
                let obj = Unmanaged<PlayerAudioTap>.fromOpaque(storage).takeUnretainedValue()

                let abl = bufferListInOut.pointee
                let mBuffer = abl.mBuffers
                guard let base = mBuffer.mData else { return }

                let bytes = Int(mBuffer.mDataByteSize)
                let count = bytes / MemoryLayout<Float32>.size
                let ptr = base.assumingMemoryBound(to: Float32.self)

                var localPeak: Float = 0
                var localRMSAcc: Double = 0
                for i in 0..<count {
                    let s = ptr[i]
                    let a = abs(s)
                    if a > localPeak { localPeak = a }
                    localRMSAcc += Double(s * s)
                }
                let localRMS = sqrt(localRMSAcc / Double(max(count, 1)))

                obj.lock.lock()
                obj.latestFrames = Int(framesFromSource)
                obj.latestData.removeAll(keepingCapacity: true)
                obj.latestData = Data(bytes: UnsafeRawPointer(ptr), count: bytes)
                obj.rms = Float(localRMS)
                obj.peak = localPeak
                obj.lock.unlock()
            }
        )

        var unmanagedTap: Unmanaged<MTAudioProcessingTap>?
        let err = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &unmanagedTap
        )
        if err == noErr, let unmanagedTap {
            let tapRef = unmanagedTap.takeRetainedValue()
            self.tap = tapRef
            let params = AVMutableAudioMixInputParameters()
            params.audioTapProcessor = tapRef
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            item.audioMix = mix
        } else {
            print("❌ Failed to create MTAudioProcessingTap (err=\(err))")
        }
    }

    private func uninstallTap() {
        tap = nil
    }
}