import SwiftUI
import AppKit

struct ChromaKeyControlsView: View {
    @ObservedObject var effect: ChromaKeyEffect
    @EnvironmentObject var effectManager: EffectManager
    
    private var keyColorBinding: Binding<Color> {
        Binding<Color>(
            get: {
                let r = Double(effect.parameters["keyR"]?.value ?? 0.0)
                let g = Double(effect.parameters["keyG"]?.value ?? 1.0)
                let b = Double(effect.parameters["keyB"]?.value ?? 0.0)
                return Color(red: r, green: g, blue: b)
            },
            set: { newValue in
                if let ns = NSColor(newValue).usingColorSpace(.sRGB) {
                    effect.parameters["keyR"]?.value = Float(ns.redComponent)
                    effect.parameters["keyG"]?.value = Float(ns.greenComponent)
                    effect.parameters["keyB"]?.value = Float(ns.blueComponent)
                    effect.objectWillChange.send()
                }
            }
        )
    }
    
    private var viewMatteBinding: Binding<Bool> {
        Binding<Bool>(
            get: { (effect.parameters["viewMatte"]?.value ?? 0.0) > 0.5 },
            set: { effect.parameters["viewMatte"]?.value = $0 ? 1.0 : 0.0 }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // KEY SECTION
            VStack(alignment: .leading, spacing: 6) {
                // Row 1: Key color + eyedropper + View Matte
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Text("Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ColorPicker("", selection: keyColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 44, height: 22)
                    }
                    
                    Button {
                        startEyedropper()
                    } label: {
                        Label("Eyedropper", systemImage: "eyedropper.halffull")
                            .font(.caption)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Toggle("", isOn: viewMatteBinding)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .teal))
                            .controlSize(.small)
                        Text("View Matte")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                
                // Row 2: Presets
                HStack(spacing: 8) {
                    Button("Green") { setKeyPreset(r: 0.0, g: 1.0, b: 0.0) }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    Button("Blue") { setKeyPreset(r: 0.0, g: 0.5, b: 1.0) }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }
            }
            
            // BACKGROUND SECTION
            GroupBox("Background") {
                VStack(alignment: .leading, spacing: 10) {
                    // Row A: Thumbnail + Upload/Clear
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.08))
                                .frame(width: 128, height: 72)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            
                            if let img = effect.backgroundPreview {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .frame(width: 128, height: 72)
                                    .clipped()
                                    .cornerRadius(6)
                            } else {
                                Text("No Background")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Button {
                                    uploadBackground()
                                } label: {
                                    Label("Upload", systemImage: "square.and.arrow.up")
                                        .font(.caption)
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                                
                                Button {
                                    effect.clearBackground()
                                } label: {
                                    Label("Clear", systemImage: "trash")
                                        .font(.caption)
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                .disabled(effect.backgroundName == nil)
                            }
                            
                            // Row B: Play/Pause + Loop
                            HStack(spacing: 12) {
                                Button {
                                    effect.bgIsPlaying ? effect.pauseBackgroundVideo() : effect.playBackgroundVideo()
                                } label: {
                                    Label(effect.bgIsPlaying ? "Pause" : "Play", systemImage: effect.bgIsPlaying ? "pause.fill" : "play.fill")
                                        .font(.caption)
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                
                                Toggle("Loop", isOn: Binding(
                                    get: { (effect.parameters["bgLoop"]?.value ?? 1.0) > 0.5 },
                                    set: { effect.parameters["bgLoop"]?.value = $0 ? 1.0 : 0.0 }
                                ))
                                .toggleStyle(SwitchToggleStyle(tint: .teal))
                                .controlSize(.small)
                                .font(.caption)
                            }
                            
                            if let name = effect.backgroundName {
                                Text(name)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 260, alignment: .leading)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    
                    // Row C: Transform sliders
                    VStack(spacing: 8) {
                        slider("Scale", key: "bgScale", range: 0.1...4.0, step: 0.01)
                        HStack(spacing: 12) {
                            slider("Pos X", key: "bgOffsetX", range: -1.0...1.0, step: 0.01)
                            slider("Pos Y", key: "bgOffsetY", range: -1.0...1.0, step: 0.01)
                        }
                        slider("Rotation", key: "bgRotation", range: -180.0...180.0, step: 1.0)
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func slider(_ label: String, key: String, range: ClosedRange<Float>, step: Float) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .leading)
            Slider(
                value: Binding(
                    get: { effect.parameters[key]?.value ?? 0 },
                    set: { effect.parameters[key]?.value = $0; effect.objectWillChange.send() }
                ),
                in: range,
                step: step
            )
            Text(String(format: "%.2f", effect.parameters[key]?.value ?? 0))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .controlSize(.small)
    }
    
    private func setKeyPreset(r: Double, g: Double, b: Double) {
        effect.parameters["keyR"]?.value = Float(r)
        effect.parameters["keyG"]?.value = Float(g)
        effect.parameters["keyB"]?.value = Float(b)
        effect.objectWillChange.send()
    }
    
    private func startEyedropper() {
        let sampler = NSColorSampler()
        sampler.show { color in
            guard let c = color?.usingColorSpace(.sRGB) else { return }
            effect.parameters["keyR"]?.value = Float(c.redComponent)
            effect.parameters["keyG"]?.value = Float(c.greenComponent)
            effect.parameters["keyB"]?.value = Float(c.blueComponent)
            effect.objectWillChange.send()
        }
    }
    
    private func uploadBackground() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie]
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            effect.setBackground(from: url, device: effectManager.metalDevice)
        }
    }
}