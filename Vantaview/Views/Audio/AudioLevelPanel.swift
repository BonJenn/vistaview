import SwiftUI

// MARK: - Audio Level Panel
struct AudioLevelPanel: View {
    @StateObject private var audioGenerator = MockAudioDataGenerator()
    @State private var isMonitoring = false
    
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
                        level: isMonitoring ? audioGenerator.audioLevels.left.rms : 0.0,
                        peak: isMonitoring ? audioGenerator.audioLevels.left.peak : 0.0,
                        isClipping: isMonitoring ? audioGenerator.audioLevels.left.isClipping : false
                    )
                    
                    AudioLevelMeter(
                        label: "RIGHT",
                        level: isMonitoring ? audioGenerator.audioLevels.right.rms : 0.0,
                        peak: isMonitoring ? audioGenerator.audioLevels.right.peak : 0.0,
                        isClipping: isMonitoring ? audioGenerator.audioLevels.right.isClipping : false
                    )
                }
                
                Divider()
                    .padding(.horizontal, 16)
                
                // Program output meter
                AudioLevelMeter(
                    label: "PROGRAM",
                    level: isMonitoring ? audioGenerator.audioLevels.program.rms : 0.0,
                    peak: isMonitoring ? audioGenerator.audioLevels.program.peak : 0.0,
                    isClipping: isMonitoring ? audioGenerator.audioLevels.program.isClipping : false
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
            // Don't auto-start monitoring
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
        audioGenerator.startGenerating()
    }
    
    private func stopMonitoring() {
        isMonitoring = false
        audioGenerator.stopGenerating()
    }
}

// MARK: - Compact Audio Level Panel (Alternative version)
struct CompactAudioLevelPanel: View {
    @StateObject private var audioGenerator = MockAudioDataGenerator()
    @State private var isActive = false
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("AUDIO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { isActive.toggle() }) {
                    Circle()
                        .fill(isActive ? .green : .gray)
                        .frame(width: 8, height: 8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            HStack(spacing: 16) {
                AudioLevelMeter(
                    label: "L",
                    level: isActive ? audioGenerator.audioLevels.left.rms : 0.0,
                    peak: isActive ? audioGenerator.audioLevels.left.peak : 0.0,
                    isClipping: isActive ? audioGenerator.audioLevels.left.isClipping : false
                )
                
                AudioLevelMeter(
                    label: "R",
                    level: isActive ? audioGenerator.audioLevels.right.rms : 0.0,
                    peak: isActive ? audioGenerator.audioLevels.right.peak : 0.0,
                    isClipping: isActive ? audioGenerator.audioLevels.right.isClipping : false
                )
                
                AudioLevelMeter(
                    label: "PGM",
                    level: isActive ? audioGenerator.audioLevels.program.rms : 0.0,
                    peak: isActive ? audioGenerator.audioLevels.program.peak : 0.0,
                    isClipping: isActive ? audioGenerator.audioLevels.program.isClipping : false
                )
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.15))
        .cornerRadius(8)
        .onChange(of: isActive) { _, newValue in
            if newValue {
                audioGenerator.startGenerating()
            } else {
                audioGenerator.stopGenerating()
            }
        }
    }
}