import SwiftUI
import AVFoundation

@MainActor
struct ComprehensiveMediaControls: View {
    @ObservedObject var previewProgramManager: PreviewProgramManager
    let isPreview: Bool
    let mediaFile: MediaFile

    @State private var isSeeking = false
    @State private var seekTime: Double = 0

    private var isPlaying: Bool {
        isPreview ? previewProgramManager.isPreviewPlaying : previewProgramManager.isProgramPlaying
    }

    private var currentTime: Double {
        isPreview ? previewProgramManager.previewCurrentTime : previewProgramManager.programCurrentTime
    }

    private var duration: Double {
        isPreview ? previewProgramManager.previewDuration : previewProgramManager.programDuration
    }

    private var loopBinding: Binding<Bool> {
        Binding(
            get: { isPreview ? previewProgramManager.previewLoopEnabled : previewProgramManager.programLoopEnabled },
            set: {
                if isPreview {
                    previewProgramManager.previewLoopEnabled = $0
                } else {
                    previewProgramManager.programLoopEnabled = $0
                }
            }
        )
    }

    private var mutedBinding: Binding<Bool> {
        Binding(
            get: { isPreview ? previewProgramManager.previewMuted : previewProgramManager.programMuted },
            set: {
                if isPreview {
                    previewProgramManager.previewMuted = $0
                    previewProgramManager.previewPlayer?.volume = $0 ? 0.0 : previewProgramManager.previewVolume
                } else {
                    previewProgramManager.programMuted = $0
                    previewProgramManager.programPlayer?.volume = $0 ? 0.0 : previewProgramManager.programVolume
                }
            }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: {
                Double(isPreview ? previewProgramManager.previewVolume : previewProgramManager.programVolume)
            },
            set: { newValue in
                let clamped = Float(min(max(newValue, 0.0), 1.0))
                if isPreview {
                    previewProgramManager.previewVolume = clamped
                    if !previewProgramManager.previewMuted {
                        previewProgramManager.previewPlayer?.volume = clamped
                    }
                } else {
                    previewProgramManager.programVolume = clamped
                    if !previewProgramManager.programMuted {
                        previewProgramManager.programPlayer?.volume = clamped
                    }
                }
            }
        )
    }

    private var rateBinding: Binding<Double> {
        Binding(
            get: {
                Double(isPreview ? previewProgramManager.previewRate : previewProgramManager.programRate)
            },
            set: { newValue in
                let rate = Float(newValue)
                if isPreview {
                    previewProgramManager.previewRate = rate
                    if isPlaying {
                        previewProgramManager.previewPlayer?.rate = rate
                    }
                } else {
                    previewProgramManager.programRate = rate
                    if isPlaying {
                        previewProgramManager.programPlayer?.rate = rate
                    }
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            // Transport
            HStack(spacing: 10) {
                Button {
                    if isPreview {
                        previewProgramManager.stepPreviewBackward()
                    } else {
                        previewProgramManager.stepProgramBackward()
                    }
                } label: {
                    Image(systemName: "backward.frame.fill")
                }

                Button {
                    if isPlaying {
                        if isPreview {
                            previewProgramManager.pausePreview()
                        } else {
                            previewProgramManager.pauseProgram()
                        }
                    } else {
                        if isPreview {
                            previewProgramManager.playPreview()
                        } else {
                            previewProgramManager.playProgram()
                        }
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }

                Button {
                    if isPreview {
                        previewProgramManager.stopPreview()
                    } else {
                        previewProgramManager.stopProgram()
                    }
                } label: {
                    Image(systemName: "stop.fill")
                }

                Button {
                    if isPreview {
                        previewProgramManager.stepPreviewForward()
                    } else {
                        previewProgramManager.stepProgramForward()
                    }
                } label: {
                    Image(systemName: "forward.frame.fill")
                }

                Spacer(minLength: 8)

                // Loop and Mute
                Toggle(isOn: loopBinding) {
                    Image(systemName: "repeat")
                }
                .toggleStyle(.button)

                Toggle(isOn: mutedBinding) {
                    Image(systemName: "speaker.slash.fill")
                }
                .toggleStyle(.button)
            }
            .controlSize(.small)

            // Scrubber
            HStack(spacing: 8) {
                Text(formatTime(isSeeking ? seekTime : currentTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Slider(
                    value: Binding(
                        get: { isSeeking ? seekTime : currentTime },
                        set: { seekTime = $0 }
                    ),
                    in: 0...(max(duration, 0.001)),
                    onEditingChanged: { editing in
                        isSeeking = editing
                        if !editing {
                            let t = seekTime
                            if isPreview {
                                previewProgramManager.seekPreview(to: t)
                            } else {
                                previewProgramManager.seekProgram(to: t)
                            }
                        }
                    }
                )

                Text(formatTime(duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Volume and Rate
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.secondary)
                    Slider(value: volumeBinding, in: 0...1, step: 0.01)
                        .frame(minWidth: 120)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .foregroundColor(.secondary)
                    Picker("", selection: rateBinding) {
                        Text("0.5x").tag(0.5)
                        Text("1.0x").tag(1.0)
                        Text("1.25x").tag(1.25)
                        Text("1.5x").tag(1.5)
                        Text("2.0x").tag(2.0)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .frame(width: 220)
                }
            }
        }
        .onChange(of: previewProgramManager.previewMuted) { _, newValue in
            if isPreview {
                previewProgramManager.previewPlayer?.volume = newValue ? 0.0 : previewProgramManager.previewVolume
            }
        }
        .onChange(of: previewProgramManager.programMuted) { _, newValue in
            if !isPreview {
                previewProgramManager.programPlayer?.volume = newValue ? 0.0 : previewProgramManager.programVolume
            }
        }
        .onChange(of: previewProgramManager.previewRate) { _, newValue in
            if isPreview, isPlaying {
                previewProgramManager.previewPlayer?.rate = newValue
            }
        }
        .onChange(of: previewProgramManager.programRate) { _, newValue in
            if !isPreview, isPlaying {
                previewProgramManager.programPlayer?.rate = newValue
            }
        }
    }

    private func formatTime(_ t: Double) -> String {
        guard t.isFinite && t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}