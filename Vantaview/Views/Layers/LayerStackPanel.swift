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
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { layer.isEnabled },
                                set: { newVal in
                                    var l = layer
                                    l.isEnabled = newVal
                                    layerManager.update(l)
                                }
                            ))
                            .labelsHidden()

                            VStack(alignment: .leading) {
                                Text(layer.name)
                                    .font(.caption)
                                Text(sourceLabel(layer))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

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
                .frame(height: 140)
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
        }
        .font(.caption2)
    }

    private func sourceLabel(_ layer: CompositedLayer) -> String {
        switch layer.source {
        case .camera:
            return "Camera"
        case .media(let file):
            return file.fileType == .image ? "Image" : "Video"
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}