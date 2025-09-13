import SwiftUI

struct LayerStackPanel: View {
    @ObservedObject var layerManager: LayerStackManager
    @ObservedObject var productionManager: UnifiedProductionManager

    // Use centralized selection in manager so it syncs with canvas overlay
    private var selection: Binding<UUID?> {
        Binding(
            get: { layerManager.selectedLayerID },
            set: { layerManager.selectedLayerID = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Layers", systemImage: "square.stack.3d.up")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Menu {
                    Section("Add Camera") {
                        if productionManager.cameraFeedManager.activeFeeds.isEmpty {
                            Text("No active cameras").disabled(true)
                        } else {
                            ForEach(productionManager.cameraFeedManager.activeFeeds) { feed in
                                Button(feed.device.displayName) {
                                    layerManager.addCameraLayer(feedId: feed.id, name: feed.device.displayName)
                                }
                            }
                        }
                    }
                    Section("Add Overlay") {
                        Button("Title") {
                            var layer = CompositedLayer(
                                name: "Title",
                                isEnabled: true,
                                zIndex: (layerManager.layers.map { $0.zIndex }.max() ?? 0) + 1,
                                centerNorm: CGPoint(x: 0.5, y: 0.2),
                                sizeNorm: CGSize(width: 0.6, height: 0.2),
                                rotationDegrees: 0,
                                opacity: 1.0,
                                source: .title(TitleOverlay())
                            )
                            layerManager.layers.append(layer)
                            layerManager.selectedLayerID = layer.id
                            layerManager.objectWillChange.send()
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .help("Add Layer")
            }

            if layerManager.layers.isEmpty {
                Text("No layers. Add a camera PIP to start.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                List(selection: selection) {
                    ForEach(layerManager.layers) { layer in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { layer.isEnabled },
                                set: { newVal in
                                    var l = layer
                                    l.isEnabled = newVal
                                    layerManager.update(l)
                                }
                            ))
                            .labelsHidden()

                            VStack(alignment: .leading, spacing: 2) {
                                Text(layer.name)
                                    .font(.caption)
                                Text(sourceLabel(layer))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Inline audio controls for video layers
                            if case .media(let file) = layer.source, file.fileType == .video {
                                // Mute
                                Toggle("M", isOn: Binding(
                                    get: { layer.audioMuted },
                                    set: { v in
                                        var l = layer
                                        l.audioMuted = v
                                        layerManager.update(l)
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .help("Mute")

                                // Solo
                                Toggle("S", isOn: Binding(
                                    get: { layer.audioSolo },
                                    set: { v in
                                        var l = layer
                                        l.audioSolo = v
                                        layerManager.update(l)
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .help("Solo (limits PiP mix to soloed layers)")

                                // Pan
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.left.and.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Slider(value: Binding(
                                        get: { Double(layer.audioPan) },
                                        set: { v in
                                            var l = layer
                                            l.audioPan = Float(v.clamped(to: -1...1))
                                            layerManager.update(l)
                                        }
                                    ), in: -1...1)
                                    .frame(width: 80)
                                }
                                .help("Pan")

                                // Meter
                                if let meter = layerManager.pipAudioMeters[layer.id] {
                                    AudioMeterView(rms: meter.rms, peak: meter.peak)
                                        .frame(width: 80, height: 8)
                                } else {
                                    AudioMeterView(rms: 0, peak: 0)
                                        .frame(width: 80, height: 8)
                                }
                            }

                            Text("#\(layer.zIndex)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .tag(layer.id)
                        .contextMenu {
                            Button("Remove") { layerManager.removeLayer(layer.id) }
                        }
                    }
                    .onMove(perform: layerManager.moveLayer)
                }
                .listStyle(.plain)
                .frame(height: 180)
            }

            if let sel = layerManager.selectedLayerID,
               let layer = layerManager.layers.first(where: { $0.id == sel }) {
                controls(for: layer)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func controls(for layer: CompositedLayer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Layer Controls")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(role: .destructive) {
                    layerManager.removeLayer(layer.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Text("X").frame(width: 12, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(layer.centerNorm.x) },
                    set: { v in
                        var l = layer
                        l.centerNorm.x = CGFloat(v.clamped(to: 0...1))
                        layerManager.update(l)
                    }
                ), in: 0...1)
            }
            HStack {
                Text("Y").frame(width: 12, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(layer.centerNorm.y) },
                    set: { v in
                        var l = layer
                        l.centerNorm.y = CGFloat(v.clamped(to: 0...1))
                        layerManager.update(l)
                    }
                ), in: 0...1)
            }
            HStack {
                Text("W").frame(width: 12, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(layer.sizeNorm.width) },
                    set: { v in
                        var l = layer
                        l.sizeNorm.width = CGFloat(v.clamped(to: 0.05...1))
                        layerManager.update(l)
                    }
                ), in: 0.05...1)
            }
            HStack {
                Text("H").frame(width: 12, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(layer.sizeNorm.height) },
                    set: { v in
                        var l = layer
                        l.sizeNorm.height = CGFloat(v.clamped(to: 0.05...1))
                        layerManager.update(l)
                    }
                ), in: 0.05...1)
            }
            HStack {
                Text("Opacity").frame(width: 50, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(layer.opacity) },
                    set: { v in
                        var l = layer
                        l.opacity = Float(v.clamped(to: 0...1))
                        layerManager.update(l)
                    }
                ), in: 0...1)
            }

            // Audio controls (detailed) for PiP Video layers
            if case .media(let file) = layer.source, file.fileType == .video {
                Divider().padding(.vertical, 4)
                Text("Audio")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Toggle("Mute", isOn: Binding(
                        get: { layer.audioMuted },
                        set: { v in
                            var l = layer
                            l.audioMuted = v
                            layerManager.update(l)
                        }
                    ))
                    .toggleStyle(.switch)
                    .font(.caption2)

                    Toggle("Solo", isOn: Binding(
                        get: { layer.audioSolo },
                        set: { v in
                            var l = layer
                            l.audioSolo = v
                            layerManager.update(l)
                        }
                    ))
                    .toggleStyle(.switch)
                    .font(.caption2)

                    HStack(spacing: 6) {
                        Text("Gain")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Slider(value: Binding(
                            get: { Double(layer.audioGain) },
                            set: { v in
                                var l = layer
                                l.audioGain = Float(v.clamped(to: 0...2))
                                layerManager.update(l)
                            }
                        ), in: 0...2)
                        .frame(width: 120)

                        Text(String(format: "%.2fx", layer.audioGain))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }

                    HStack(spacing: 6) {
                        Text("Pan")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Slider(value: Binding(
                            get: { Double(layer.audioPan) },
                            set: { v in
                                var l = layer
                                l.audioPan = Float(v.clamped(to: -1...1))
                                layerManager.update(l)
                            }
                        ), in: -1...1)
                        .frame(width: 120)

                        Text(String(format: "%.2f", layer.audioPan))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                if let meter = layerManager.pipAudioMeters[layer.id] {
                    AudioMeterView(rms: meter.rms, peak: meter.peak)
                        .frame(height: 10)
                } else {
                    AudioMeterView(rms: 0, peak: 0)
                        .frame(height: 10)
                }
            }

            if case .title(let overlay) = layer.source {
                Divider().padding(.vertical, 4)
                Text("Title")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Text", text: Binding(
                        get: { overlay.text },
                        set: { newText in
                            var l = layer
                            if case .title(var ov) = l.source {
                                ov.text = newText
                                l.source = .title(ov)
                                layerManager.update(l)
                            }
                        }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.caption2)

                    HStack {
                        Text("Font Size").font(.caption2).foregroundColor(.secondary)
                        Slider(value: Binding(
                            get: { Double(overlay.fontSize) },
                            set: { v in
                                var l = layer
                                if case .title(var ov) = l.source {
                                    ov.fontSize = CGFloat(v.clamped(to: 8...200))
                                    l.source = .title(ov)
                                    layerManager.update(l)
                                }
                            }
                        ), in: 8...200)
                        Text("\(Int(overlay.fontSize))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }

                    HStack {
                        Text("Color").font(.caption2).foregroundColor(.secondary)
                        ColorPicker("", selection: Binding(
                            get: { Color(red: overlay.color.r, green: overlay.color.g, blue: overlay.color.b, opacity: overlay.color.a) },
                            set: { c in
                                var l = layer
                                if case .title(var ov) = l.source {
                                    if let comps = c.toRGBA() {
                                        ov.color = comps
                                        l.source = .title(ov)
                                        layerManager.update(l)
                                    }
                                }
                            }
                        ))
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    HStack {
                        Text("Alignment").font(.caption2).foregroundColor(.secondary)
                        Picker("", selection: Binding(
                            get: { overlay.alignment },
                            set: { value in
                                var l = layer
                                if case .title(var ov) = l.source {
                                    ov.alignment = value
                                    l.source = .title(ov)
                                    layerManager.update(l)
                                }
                            }
                        )) {
                            Text("Left").tag(TextAlignment.leading)
                            Text("Center").tag(TextAlignment.center)
                            Text("Right").tag(TextAlignment.trailing)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .labelsHidden()
                    }

                    Toggle("Auto-fit to text", isOn: Binding(
                        get: { overlay.autoFit },
                        set: { v in
                            var l = layer
                            if case .title(var ov) = l.source {
                                ov.autoFit = v
                                l.source = .title(ov)
                                layerManager.update(l)
                            }
                        }
                    ))
                    .font(.caption2)
                }
            }
        }
        .font(.caption2)
    }

    private func sourceLabel(_ layer: CompositedLayer) -> String {
        switch layer.source {
        case .camera:
            return "Camera"
        case .media(let file):
            return file.fileType == .image ? "Image" : "Video"
        case .title:
            return "Title"
        }
    }
}

private struct AudioMeterView: View {
    var rms: Float  // 0..1
    var peak: Float // 0..1

    private func db(from x: Float) -> Float {
        let v = max(x, 1e-6)
        return 20.0 * log10f(v)
    }
    private func normalizedDB(_ db: Float) -> CGFloat {
        // Map -60 dB .. 0 dB to 0..1
        let clamped = max(min(db, 0), -60)
        return CGFloat((clamped + 60) / 60.0)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let rmsDB = normalizedDB(db(from: rms))
            let peakDB = normalizedDB(db(from: peak))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: h/2)
                    .fill(Color.black.opacity(0.2))
                RoundedRectangle(cornerRadius: h/2)
                    .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * rmsDB)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 2, height: h)
                    .offset(x: w * peakDB)
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}