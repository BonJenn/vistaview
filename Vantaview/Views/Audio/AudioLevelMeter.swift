import SwiftUI

// MARK: - Audio Level Meter Component
struct AudioLevelMeter: View {
    let label: String
    let level: Float // 0.0 to 1.0
    let peak: Float // 0.0 to 1.0
    let isClipping: Bool
    
    private let meterWidth: CGFloat = 12
    private let meterHeight: CGFloat = 140
    
    var body: some View {
        VStack(spacing: 4) {
            // Meter container
            ZStack(alignment: .bottom) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.6))
                    .frame(width: meterWidth, height: meterHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                
                // Level fill with gradient
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(levelGradient)
                    .frame(
                        width: meterWidth - 2,
                        height: max(2, meterHeight * CGFloat(level))
                    )
                    .animation(.easeOut(duration: 0.08), value: level)
                
                if level > 0.01 {
                    let capThickness: CGFloat = 2.0
                    let capPosition = max(0, min(meterHeight - capThickness, meterHeight * CGFloat(level)))
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: meterWidth - 2, height: capThickness)
                        .offset(y: -capPosition)
                        .animation(.easeOut(duration: 0.05), value: level)
                }

                // Clipping indicator
                if isClipping {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: meterWidth, height: meterHeight)
                        .animation(.easeInOut(duration: 0.1), value: isClipping)
                }
                
                // Scale markers
                meterScaleMarkers
            }
            .clipped() // ensure all overlays (peak/markers) stay within the meter track
            
            // Label
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: meterWidth + 8)
                .multilineTextAlignment(.center)
        }
    }
    
    private var levelGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.green,           // -60 to -18 dB
                Color.green,
                Color.yellow,          // -18 to -6 dB
                Color.orange,          // -6 to -3 dB
                Color.red              // -3 to 0 dB
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
    
    private var peakColor: Color {
        if peak > 0.85 {
            return .red
        } else if peak > 0.7 {
            return .orange
        } else {
            return .white
        }
    }
    
    private var meterScaleMarkers: some View {
        HStack {
            // Left scale markers
            VStack(spacing: 0) {
                let dbMarkers = ["0", "-3", "-6", "-12", "-18", "-24", "-30", "-∞"]
                ForEach(Array(dbMarkers.reversed().enumerated()), id: \.offset) { index, db in
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 3, height: 0.5)
                        
                        Spacer()
                    }
                    .frame(height: meterHeight / 8)
                }
            }
            .frame(width: 8)
            
            Spacer()
        }
        .offset(x: -12)
    }
}

// MARK: - Audio Level Data Model
struct AudioLevelData {
    let left: AudioChannelLevel
    let right: AudioChannelLevel
    let program: AudioChannelLevel
}

struct AudioChannelLevel {
    let rms: Float      // RMS level (0.0 to 1.0)
    let peak: Float     // Peak level (0.0 to 1.0)
    let isClipping: Bool
    
    static let silent = AudioChannelLevel(rms: 0.0, peak: 0.0, isClipping: false)
}

// MARK: - Mock Audio Data Generator
class MockAudioDataGenerator: ObservableObject {
    @Published var audioLevels = AudioLevelData(
        left: .silent,
        right: .silent,
        program: .silent
    )
    
    private var timer: Timer?
    private var leftPhase: Float = 0
    private var rightPhase: Float = 0.3
    private var programPhase: Float = 0.6
    
    func startGenerating() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            self.generateMockLevels()
        }
    }
    
    func stopGenerating() {
        timer?.invalidate()
        timer = nil
        
        // Reset to silent
        audioLevels = AudioLevelData(
            left: .silent,
            right: .silent,
            program: .silent
        )
    }
    
    private func generateMockLevels() {
        leftPhase += 0.08
        rightPhase += 0.12
        programPhase += 0.06
        
        // Generate realistic audio patterns
        let leftBase = sin(leftPhase) * 0.4 + 0.5
        let rightBase = sin(rightPhase) * 0.3 + 0.4
        let programBase = sin(programPhase) * 0.5 + 0.6
        
        // Add some randomness for realism
        let leftNoise = Float.random(in: -0.1...0.1)
        let rightNoise = Float.random(in: -0.1...0.1)
        let programNoise = Float.random(in: -0.15...0.15)
        
        let leftLevel = max(0, min(1, leftBase + leftNoise))
        let rightLevel = max(0, min(1, rightBase + rightNoise))
        let programLevel = max(0, min(1, programBase + programNoise))
        
        // Peak hold simulation (peaks decay slower)
        let leftPeak = max(leftLevel, audioLevels.left.peak * 0.95)
        let rightPeak = max(rightLevel, audioLevels.right.peak * 0.95)
        let programPeak = max(programLevel, audioLevels.program.peak * 0.95)
        
        audioLevels = AudioLevelData(
            left: AudioChannelLevel(
                rms: leftLevel,
                peak: leftPeak,
                isClipping: leftPeak > 0.95
            ),
            right: AudioChannelLevel(
                rms: rightLevel,
                peak: rightPeak,
                isClipping: rightPeak > 0.95
            ),
            program: AudioChannelLevel(
                rms: programLevel,
                peak: programPeak,
                isClipping: programPeak > 0.95
            )
        )
    }
    
    deinit {
        stopGenerating()
    }
}