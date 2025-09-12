import Foundation
import AVFoundation
import CoreMedia
import MediaToolbox
import AudioToolbox

final class PlayerAudioTap: NSObject {
    private(set) var sampleRate: Double = 44100
    private(set) var channels: Int = 2

    private var latestData = Data()
    private var latestFrames: Int = 0

    private(set) var rms: Float = 0
    private(set) var peak: Float = 0

    private var tap: MTAudioProcessingTap?
    private let lock = NSLock()

    private var isFloat32: Bool = true
    private var isInterleaved: Bool = true
    private var bytesPerSample: Int = 4

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
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
            init: { tap, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<PlayerAudioTap>.fromOpaque(storage).release()
            },
            prepare: { tap, maxFrames, processingFormat in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let obj = Unmanaged<PlayerAudioTap>.fromOpaque(storage).takeUnretainedValue()
                let asbd = processingFormat.pointee
                obj.sampleRate = asbd.mSampleRate
                obj.channels = Int(asbd.mChannelsPerFrame)
                obj.isFloat32 = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
                obj.isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                obj.bytesPerSample = Int(asbd.mBitsPerChannel / 8)
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

                // Build a stereo Float32 interleaved buffer and compute meters safely
                let frames = Int(framesFromSource)
                var outStereo = [Float32](repeating: 0, count: frames * 2)

                var leftPeak: Float = 0
                var rightPeak: Float = 0
                var leftAcc: Double = 0
                var rightAcc: Double = 0

                // Swift helper to walk buffer list safely
                let ablPtr = UnsafeMutableAudioBufferListPointer(bufferListInOut)

                func sampleFloat32Interleaved(_ base: UnsafeMutableRawPointer, channels: Int) {
                    let ptr = base.bindMemory(to: Float32.self, capacity: frames * channels)
                    for f in 0..<frames {
                        let i = f * channels
                        let l = channels > 0 ? ptr[i] : 0
                        let r = channels > 1 ? ptr[i + 1] : l
                        outStereo[f * 2] = l
                        outStereo[f * 2 + 1] = r
                        let la = abs(l), ra = abs(r)
                        if la > leftPeak { leftPeak = la }
                        if ra > rightPeak { rightPeak = ra }
                        leftAcc += Double(l * l)
                        rightAcc += Double(r * r)
                    }
                }

                func sampleInt16Interleaved(_ base: UnsafeMutableRawPointer, channels: Int) {
                    let ptr = base.bindMemory(to: Int16.self, capacity: frames * channels)
                    let scale: Float = 1.0 / Float(Int16.max)
                    for f in 0..<frames {
                        let i = f * channels
                        let l16 = channels > 0 ? ptr[i] : 0
                        let r16 = channels > 1 ? ptr[i + 1] : l16
                        let l = Float(l16) * scale
                        let r = Float(r16) * scale
                        outStereo[f * 2] = l
                        outStereo[f * 2 + 1] = r
                        let la = abs(l), ra = abs(r)
                        if la > leftPeak { leftPeak = la }
                        if ra > rightPeak { rightPeak = ra }
                        leftAcc += Double(l * l)
                        rightAcc += Double(r * r)
                    }
                }

                func sampleFloat32Planar(_ buffers: UnsafeMutableAudioBufferListPointer) {
                    let lBuf = buffers.indices.contains(0) ? buffers[0] : AudioBuffer()
                    let rBuf = buffers.indices.contains(1) ? buffers[1] : lBuf
                    let lPtr = lBuf.mData?.bindMemory(to: Float32.self, capacity: frames)
                    let rPtr = rBuf.mData?.bindMemory(to: Float32.self, capacity: frames)
                    for f in 0..<frames {
                        let l = lPtr?[f] ?? 0
                        let r = rPtr?[f] ?? l
                        outStereo[f * 2] = l
                        outStereo[f * 2 + 1] = r
                        let la = abs(l), ra = abs(r)
                        if la > leftPeak { leftPeak = la }
                        if ra > rightPeak { rightPeak = ra }
                        leftAcc += Double(l * l)
                        rightAcc += Double(r * r)
                    }
                }

                func sampleInt16Planar(_ buffers: UnsafeMutableAudioBufferListPointer) {
                    let lBuf = buffers.indices.contains(0) ? buffers[0] : AudioBuffer()
                    let rBuf = buffers.indices.contains(1) ? buffers[1] : lBuf
                    let lPtr = lBuf.mData?.bindMemory(to: Int16.self, capacity: frames)
                    let rPtr = rBuf.mData?.bindMemory(to: Int16.self, capacity: frames)
                    let scale: Float = 1.0 / Float(Int16.max)
                    for f in 0..<frames {
                        let l = Float(lPtr?[f] ?? 0) * scale
                        let r = Float(rPtr?[f] ?? 0) * scale
                        outStereo[f * 2] = l
                        outStereo[f * 2 + 1] = r
                        let la = abs(l), ra = abs(r)
                        if la > leftPeak { leftPeak = la }
                        if ra > rightPeak { rightPeak = ra }
                        leftAcc += Double(l * l)
                        rightAcc += Double(r * r)
                    }
                }

                if obj.isInterleaved, let buf = ablPtr.first, let base = buf.mData, buf.mDataByteSize > 0 {
                    if obj.isFloat32 {
                        sampleFloat32Interleaved(base, channels: obj.channels)
                    } else if obj.bytesPerSample == 2 {
                        sampleInt16Interleaved(base, channels: obj.channels)
                    } else {
                        // Unsupported sample format; bail safely
                        return
                    }
                } else {
                    // Planar (non-interleaved)
                    if obj.isFloat32 {
                        sampleFloat32Planar(ablPtr)
                    } else if obj.bytesPerSample == 2 {
                        sampleInt16Planar(ablPtr)
                    } else {
                        return
                    }
                }

                let totalFrames = max(frames, 1)
                let lRMS = Float(sqrt(leftAcc / Double(totalFrames)))
                let rRMS = Float(sqrt(rightAcc / Double(totalFrames)))
                let totalPeak = max(leftPeak, rightPeak)
                let avgRMS = Float(sqrt(((leftAcc + rightAcc) * 0.5) / Double(totalFrames)))

                obj.lock.lock()
                obj.latestFrames = frames
                obj.latestData = outStereo.withUnsafeBufferPointer { Data(buffer: $0) }
                obj.rms = avgRMS
                obj.peak = totalPeak
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

            let mix = AVMutableAudioMix()
            var paramsArray: [AVMutableAudioMixInputParameters] = []

            if let firstTrack = item.asset.tracks(withMediaType: .audio).first {
                let params = AVMutableAudioMixInputParameters(track: firstTrack)
                params.audioTapProcessor = tapRef
                paramsArray = [params]
            } else {
                let params = AVMutableAudioMixInputParameters()
                params.audioTapProcessor = tapRef
                paramsArray = [params]
            }

            mix.inputParameters = paramsArray
            item.audioMix = mix
        } else {
            print("❌ Failed to create MTAudioProcessingTap (err=\(err))")
        }
    }

    private func uninstallTap() {
        tap = nil
    }
}