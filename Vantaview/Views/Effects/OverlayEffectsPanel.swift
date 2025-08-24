import SwiftUI

struct OverlayEffectsPanel: View {
    @ObservedObject var overlayManager: OverlayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Overlays").font(.headline)
                Spacer()
                Button { overlayManager.addTextOverlay() } label: {
                    Label("Text", systemImage: "textformat")
                }
                Button { overlayManager.addCountdownOverlay(seconds: 10) } label: {
                    Label("Countdown", systemImage: "timer")
                }
            }

            List {
                ForEach(overlayManager.overlays, id: \.id) { ov in
                    if let t = ov as? TextOverlayEffect {
                        OverlayTextRow(text: t, remove: { overlayManager.remove(t.id) })
                    } else if let c = ov as? CountdownOverlayEffect {
                        OverlayCountdownRow(cdown: c, remove: { overlayManager.remove(c.id) })
                    }
                }
            }
            .frame(minHeight: 220)
        }
        .padding()
    }
}

private struct OverlayTextRow: View {
    @ObservedObject var text: TextOverlayEffect
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(name: $text.name, isOn: $text.isEnabled, z: $text.zIndex, remove: remove)
            placement(ctr: $text.centerNorm, size: $text.sizeNorm, rot: $text.rotationDegrees, opacity: $text.opacity)
            Text("Text").font(.caption)
            TextField("Enter text", text: Binding(get: { text.text }, set: { text.text = $0; text.markNeedsRedraw() }))
            HStack {
                ColorPicker("Color", selection: Binding(get: { text.textColor }, set: { text.textColor = $0; text.markNeedsRedraw() }))
                Toggle("Shadow", isOn: Binding(get: { text.shadow }, set: { text.shadow = $0; text.markNeedsRedraw() }))
            }
        }
    }
}

private struct OverlayCountdownRow: View {
    @ObservedObject var cdown: CountdownOverlayEffect
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(name: $cdown.name, isOn: $cdown.isEnabled, z: $cdown.zIndex, remove: remove)
            placement(ctr: $cdown.centerNorm, size: $cdown.sizeNorm, rot: $cdown.rotationDegrees, opacity: $cdown.opacity)
            HStack {
                Stepper("Seconds: \(cdown.totalSeconds)", value: $cdown.totalSeconds, in: 0...36000)
                Button("Start") { cdown.start() }
                Button("Stop") { cdown.stop() }
            }
            HStack {
                TextField("Prefix", text: Binding(get: { cdown.prefix }, set: { cdown.prefix = $0; cdown.markNeedsRedraw() }))
                TextField("Suffix", text: Binding(get: { cdown.suffix }, set: { cdown.suffix = $0; cdown.markNeedsRedraw() }))
            }
            HStack {
                ColorPicker("Color", selection: Binding(get: { cdown.textColor }, set: { cdown.textColor = $0; cdown.markNeedsRedraw() }))
                Toggle("Shadow", isOn: Binding(get: { cdown.shadow }, set: { cdown.shadow = $0; cdown.markNeedsRedraw() }))
            }
        }
    }
}

private func header(name: Binding<String>, isOn: Binding<Bool>, z: Binding<Int>, remove: @escaping () -> Void) -> some View {
    HStack {
        Toggle("", isOn: isOn).labelsHidden()
        TextField("Name", text: name)
        Spacer()
        Stepper("Z: \(z.wrappedValue)", value: z).labelsHidden()
        Button(role: .destructive) { remove() } label: { Image(systemName: "trash") }
    }
}

private func placement(ctr: Binding<CGPoint>, size: Binding<CGSize>, rot: Binding<Float>, opacity: Binding<Float>) -> some View {
    VStack(alignment: .leading) {
        HStack {
            Text("X")
            Slider(value: Binding(get: { Double(ctr.wrappedValue.x) }, set: { ctr.wrappedValue.x = CGFloat($0) }), in: 0...1)
            Text("Y")
            Slider(value: Binding(get: { Double(ctr.wrappedValue.y) }, set: { ctr.wrappedValue.y = CGFloat($0) }), in: 0...1)
        }
        HStack {
            Text("W")
            Slider(value: Binding(get: { Double(size.wrappedValue.width) }, set: { size.wrappedValue.width = CGFloat($0) }), in: 0.05...1)
            Text("H")
            Slider(value: Binding(get: { Double(size.wrappedValue.height) }, set: { size.wrappedValue.height = CGFloat($0) }), in: 0.05...1)
        }
        HStack {
            Text("Rot")
            Slider(value: Binding(get: { Double(rot.wrappedValue) }, set: { rot.wrappedValue = Float($0) }), in: -180...180)
            Text("Opacity")
            Slider(value: Binding(get: { Double(opacity.wrappedValue) }, set: { opacity.wrappedValue = Float($0) }), in: 0...1)
        }
    }
}