import SwiftUI
import Foundation

// MARK: - Audio Level Panel
struct AudioLevelPanel: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @State private var isMonitoring = true

    @State private var audioLevels: AudioLevelData = AudioLevelData(
        left: AudioChannelLevel.silent,
        right: AudioChannelLevel.silent,
        program: AudioChannelLevel.silent
    )

    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Audio Levels")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: toggleMonitoring) {
                    Image(systemName: isMonitoring ? "speaker.wave.3.fill" : "speaker.slash.fill")
                        .font(.system(size: 12))
                        .foregroundColor(isMonitoring ? .green : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(isMonitoring ? "Stop monitoring" : "Start monitoring")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            
            Divider()
            
            // JUST THE METERS - NO DB SCALE
            VStack(spacing: 12) {
                // Stereo output meters
                HStack(spacing: 20) {
                    AudioLevelMeter(
                        label: "LEFT",
                        level: audioLevels.left.rms,
                        peak: audioLevels.left.peak,
                        isClipping: audioLevels.left.isClipping
                    )
                    
                    AudioLevelMeter(
                        label: "RIGHT",
                        level: audioLevels.right.rms,
                        peak: audioLevels.right.peak,
                        isClipping: audioLevels.right.isClipping
                    )
                }
                
                Divider()
                    .padding(.horizontal, 16)
                
                // Program output meter
                AudioLevelMeter(
                    label: "PROGRAM",
                    level: audioLevels.program.rms,
                    peak: audioLevels.program.peak,
                    isClipping: audioLevels.program.isClipping
                )
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .onAppear {
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }
    
    private func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    private func startMonitoring() {
        isMonitoring = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            pollAudio()
        }
    }
    
    private func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        audioLevels = AudioLevelData(
            left: AudioChannelLevel.silent,
            right: AudioChannelLevel.silent,
            program: AudioChannelLevel.silent
        )
    }

    private func pollAudio() {
        guard isMonitoring else { return }
        let ppm = productionManager.previewProgramManager

        // Prefer Program if playing, else Preview, else any available tap
        let activeTap: PlayerAudioTap? = {
            if ppm.isProgramPlaying, let t = ppm.programAudioTap { return t }
            if ppm.isPreviewPlaying, let t = ppm.previewAudioTap { return t }
            return ppm.programAudioTap ?? ppm.previewAudioTap
        }()

        guard let tap = activeTap,
              let (ptr, frames, channels, _) = tap.fetchLatestInterleavedBuffer(),
              frames > 0
        else {
            audioLevels = AudioLevelData(
                left: AudioChannelLevel.silent,
                right: AudioChannelLevel.silent,
                program: AudioChannelLevel.silent
            )
            return
        }

        let (lRMS, rRMS, pRMS, lPeak, rPeak, pPeak) = computeLevels(ptr: ptr, frames: frames, channels: channels)

        // Peak hold decay
        let decay: Float = 0.95
        let newLeftPeak = max(lPeak, audioLevels.left.peak * decay)
        let newRightPeak = max(rPeak, audioLevels.right.peak * decay)
        let newProgramPeak = max(pPeak, audioLevels.program.peak * decay)

        audioLevels = AudioLevelData(
            left: AudioChannelLevel(
                rms: clamp01(lRMS),
                peak: clamp01(newLeftPeak),
                isClipping: newLeftPeak > 0.98
            ),
            right: AudioChannelLevel(
                rms: clamp01(rRMS),
                peak: clamp01(newRightPeak),
                isClipping: newRightPeak > 0.98
            ),
            program: AudioChannelLevel(
                rms: clamp01(pRMS),
                peak: clamp01(newProgramPeak),
                isClipping: newProgramPeak > 0.98
            )
        )
    }

    private func computeLevels(ptr: UnsafePointer<Float32>, frames: Int, channels: Int) -> (Float, Float, Float, Float, Float, Float) {
        let ch = max(1, channels)
        var lAcc: Double = 0
        var rAcc: Double = 0
        var pAcc: Double = 0
        var lPeak: Float = 0
        var rPeak: Float = 0

        for f in 0..<frames {
            let base = f * ch
            let l: Float
            let r: Float
            if ch >= 2 {
                l = ptr[base]
                r = ptr[base + 1]
            } else {
                let v = ptr[base]
                l = v
                r = v
            }
            let la = abs(l)
            let ra = abs(r)
            if la > lPeak { lPeak = la }
            if ra > rPeak { rPeak = ra }
            lAcc += Double(l * l)
            rAcc += Double(r * r)
            pAcc += Double((l * l + r * r) * 0.5)
        }

        let denom = Double(max(frames, 1))
        let lRMS = Float(sqrt(lAcc / denom))
        let rRMS = Float(sqrt(rAcc / denom))
        let pRMS = Float(sqrt(pAcc / denom))
        let progPeak = max(lPeak, rPeak)
        return (lRMS, rRMS, pRMS, lPeak, rPeak, progPeak)
    }

    private func clamp01(_ x: Float) -> Float {
        return max(0, min(1, x))
    }
}