//
//  MediaMixer.swift
//  Vantaview
//
//  Minimal RTMP stream mixer that wires HaishinKit to StreamingViewModel
//

import Foundation
import AVFoundation
import HaishinKit
import CoreMedia

@MainActor
final class MediaMixer {
    private var mixer = HaishinKit.MediaMixer()
    private var stream: RTMPStream?
    private var desiredFPS: Int = 30
    private var desiredPreset: AVCaptureSession.Preset = .medium

    func setFrameRate(_ fps: Int) async {
        desiredFPS = fps
        await mixer.setFrameRate(Double(fps))
    }

    func setSessionPreset(_ preset: AVCaptureSession.Preset) async {
        desiredPreset = preset
        await mixer.setSessionPreset(preset)
    }

    func addOutput(_ stream: RTMPStream) async throws {
        self.stream = stream
        await mixer.addOutput(stream)
        await mixer.setFrameRate(Double(desiredFPS))
        await mixer.setSessionPreset(desiredPreset)
    }

    func attachVideo(_ device: AVCaptureDevice) async throws {
        try await mixer.attachVideo(device, track: 0, configuration: nil)
        await mixer.setFrameRate(Double(desiredFPS))
        await mixer.setSessionPreset(desiredPreset)
    }

    func attachAudio(_ device: AVCaptureDevice?) async throws {
        try await mixer.attachAudio(device, track: 0, configuration: nil)
    }

    func stopAllAudioCapture() async {
        do {
            try await mixer.attachAudio(nil, track: 0, configuration: nil)
        } catch {
            // ignore
        }
    }

    func resetForProgramMirror() async {
        mixer = HaishinKit.MediaMixer()
        await mixer.setFrameRate(Double(desiredFPS))
        await mixer.setSessionPreset(desiredPreset)
    }

    func stopAllVideoCapture() async {
        await mixer.stopCapturing()
        do {
            try await mixer.attachVideo(nil, track: 0, configuration: nil)
        } catch {
            // best-effort; ignore
        }
    }

    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) async {
        await mixer.append(sampleBuffer, track: 0)
    }
}

@MainActor
extension RTMPStream {
    func addOutput(_ preview: MTHKView) async throws {
        await (self as HaishinKit.HKStream).addOutput(preview)
    }

    // async forwarder for actor isolation
    func appendVideo(_ sampleBuffer: CMSampleBuffer) async {
        await (self as HaishinKit.HKStream).append(sampleBuffer)
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) async {
        await (self as HaishinKit.HKStream).append(sampleBuffer)
    }
}