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
                    safeSet("keyR", Float(ns.redComponent))
                    safeSet("keyG", Float(ns.greenComponent))
                    safeSet("keyB", Float(ns.blueComponent))
                }
            }
        )
    }
    
    private var viewMatteBinding: Binding<Bool> {
        Binding<Bool>(
            get: { (effect.parameters["viewMatte"]?.value ?? 0.0) > 0.5 },
            set: { safeSet("viewMatte", $0 ? 1.0 : 0.0) }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Centered, lightweight control row (instant open)
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    ColorPicker("", selection: keyColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 44, height: 22)
                        .controlSize(.small)

                    Button {
                        startEyedropper()
                    } label: {
                        Label("Eyedropper", systemImage: "eyedropper.halffull")
                            .font(.caption)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)

                    Button("Green") { setKeyPreset(r: 0.0, g: 1.0, b: 0.0) }
                        .controlSize(.small)
                        .buttonStyle(.bordered)

                    Button("Blue") { setKeyPreset(r: 0.0, g: 0.5, b: 1.0) }
                        .controlSize(.small)
                        .buttonStyle(.bordered)

                    Toggle("View Matte", isOn: viewMatteBinding)
                        .toggleStyle(SwitchToggleStyle(tint: .teal))
                        .controlSize(.small)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
            }

            GroupBox("Keying") {
                VStack(alignment: .leading, spacing: 8) {
                    // Range widens tolerance around the eyedropped color (maps to \\"strength\\")
                    interactiveSlider("Range", key: "strength", range: 0.0...1.0, step: 0.01)
                    // Feather softens the transition (maps to \\"softness\\")
                    interactiveSlider("Feather", key: "softness", range: 0.0...1.0, step: 0.01)
                }
                .padding(10)
            }

            GroupBox("Background") {
                VStack(alignment: .leading, spacing: 10) {
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
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 128, height: 72)
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
                                    set: { safeSet("bgLoop", $0 ? 1.0 : 0.0) }
                                ))
                                .toggleStyle(SwitchToggleStyle(tint: .teal))
                                .controlSize(.small)
                                .font(.caption)
                            }

                            HStack(spacing: 8) {
                                Text("Fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Picker("", selection: Binding<Int>(
                                    get: { Int(effect.parameters["bgFillMode"]?.value ?? 0.0) },
                                    set: { safeSet("bgFillMode", Float($0)) }
                                )) {
                                    Text("Contain").tag(0)
                                    Text("Cover").tag(1)
                                }
                                .pickerStyle(.segmented)
                                .controlSize(.small)
                                .frame(width: 180)
                            }

                            HStack(spacing: 8) {
                                Button {
                                    quickFitContain()
                                } label: {
                                    Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption)
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)

                                Button {
                                    quickFillCover()
                                } label: {
                                    Label("Fill", systemImage: "arrow.down.right.and.arrow.up.left")
                                        .font(.caption)
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)

                                Button {
                                    quickCenter()
                                } label: {
                                    Label("Center", systemImage: "circle")
                                        .font(.caption)
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
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
                    
                    // Interactive-friendly sliders: tell effect when dragging
                    VStack(spacing: 8) {
                        interactiveSlider("Scale", key: "bgScale", range: 0.1...4.0, step: 0.01)
                        HStack(spacing: 12) {
                            interactiveSlider("Pos X", key: "bgOffsetX", range: -1.0...1.0, step: 0.01)
                            interactiveSlider("Pos Y", key: "bgOffsetY", range: -1.0...1.0, step: 0.01)
                        }
                        interactiveSlider("Rotation", key: "bgRotation", range: -180.0...180.0, step: 1.0)
                        interactiveSlider("Light Wrap", key: "lightWrap", range: 0.0...1.0, step: 0.01)
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func interactiveSlider(_ label: String, key: String, range: ClosedRange<Float>, step: Float) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Slider(
                value: Binding(
                    get: { effect.parameters[key]?.value ?? 0 },
                    set: { safeSet(key, $0) }
                ),
                in: range,
                step: step,
                onEditingChanged: { editing in
                    if editing {
                        effect.beginInteractive()
                    } else {
                        effect.endInteractive(after: 0.2)
                    }
                }
            )
            .controlSize(.small)
            Text(String(format: "%.2f", effect.parameters[key]?.value ?? 0))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
    
    private func setKeyPreset(r: Double, g: Double, b: Double) {
        safeSet("keyR", Float(r))
        safeSet("keyG", Float(g))
        safeSet("keyB", Float(b))
    }
    
    private func startEyedropper() {
        let sampler = NSColorSampler()
        sampler.show { color in
            guard let c = color?.usingColorSpace(.sRGB) else { return }
            safeSet("keyR", Float(c.redComponent))
            safeSet("keyG", Float(c.greenComponent))
            safeSet("keyB", Float(c.blueComponent))
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

private extension ChromaKeyControlsView {
    func quickCenter() {
        safeSet("bgOffsetX", 0.0)
        safeSet("bgOffsetY", 0.0)
    }
    
    func quickFitContain() {
        safeSet("bgFillMode", 0.0)
        safeSet("bgScale", 1.0)
        safeSet("bgOffsetX", 0.0)
        safeSet("bgOffsetY", 0.0)
        safeSet("bgRotation", 0.0)
    }
    
    func quickFillCover() {
        safeSet("bgFillMode", 1.0)
        safeSet("bgScale", 1.0)
        safeSet("bgOffsetX", 0.0)
        safeSet("bgOffsetY", 0.0)
        safeSet("bgRotation", 0.0)
    }
    
    func safeSet(_ key: String, _ value: Float) {
        if var p = effect.parameters[key] {
            p.value = value
            effect.parameters[key] = p
        }
        effect.objectWillChange.send()
    }
}