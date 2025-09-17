import Foundation
import AVFoundation
import CoreGraphics

@MainActor
final class LayerStackManager: ObservableObject {
    // Program layers (legacy API keeps using \\"layers\\")
    @Published var layers: [CompositedLayer] = []
    @Published var selectedLayerID: UUID?
    @Published var editingLayerID: UUID?

    // Preview layers (independent from Program)
    @Published var previewLayers: [CompositedLayer] = []
    @Published var selectedPreviewLayerID: UUID?
    @Published var editingPreviewLayerID: UUID?

    private weak var productionManager: UnifiedProductionManager?

    var pipAudioTaps: [UUID: PlayerAudioTap] = [:]

    struct AudioMeter: Equatable {
        var rms: Float
        var peak: Float
    }
    @Published var pipAudioMeters: [UUID: AudioMeter] = [:]

    func setProductionManager(_ pm: UnifiedProductionManager) {
        self.productionManager = pm
    }

    // MARK: - Generic helpers for Preview vs Program

    func layers(isPreview: Bool) -> [CompositedLayer] {
        isPreview ? previewLayers : layers
    }

    func setLayers(_ newLayers: [CompositedLayer], isPreview: Bool) {
        if isPreview {
            previewLayers = newLayers
        } else {
            layers = newLayers
        }
        objectWillChange.send()
    }

    func update(_ layer: CompositedLayer, isPreview: Bool) {
        if isPreview {
            guard let i = previewLayers.firstIndex(where: { $0.id == layer.id }) else { return }
            previewLayers[i] = layer
        } else {
            guard let i = layers.firstIndex(where: { $0.id == layer.id }) else { return }
            layers[i] = layer
        }
        objectWillChange.send()
    }

    func selectLayer(_ id: UUID?, isPreview: Bool) {
        if isPreview {
            selectedPreviewLayerID = id
        } else {
            selectedLayerID = id
        }
        objectWillChange.send()
    }

    func beginEditingLayer(_ id: UUID, isPreview: Bool) {
        if isPreview {
            editingPreviewLayerID = id
        } else {
            editingLayerID = id
        }
        objectWillChange.send()
    }

    func endEditing(isPreview: Bool) {
        if isPreview {
            editingPreviewLayerID = nil
        } else {
            editingLayerID = nil
        }
        objectWillChange.send()
    }

    func removeLayer(_ id: UUID, isPreview: Bool) {
        if isPreview {
            previewLayers.removeAll { $0.id == id }
            if selectedPreviewLayerID == id { selectedPreviewLayerID = nil }
        } else {
            layers.removeAll { $0.id == id }
            if selectedLayerID == id { selectedLayerID = nil }
        }
        pipAudioTaps.removeValue(forKey: id)
        pipAudioMeters.removeValue(forKey: id)
        objectWillChange.send()
    }

    func moveLayer(from offsets: IndexSet, to index: Int, isPreview: Bool) {
        if isPreview {
            previewLayers.move(fromOffsets: offsets, toOffset: index)
            for (i, idx) in previewLayers.indices.enumerated() {
                previewLayers[idx].zIndex = i
            }
        } else {
            layers.move(fromOffsets: offsets, toOffset: index)
            for (i, idx) in layers.indices.enumerated() {
                layers[idx].zIndex = i
            }
        }
        objectWillChange.send()
    }

    // MARK: - Program-specific (legacy API)

    func addCameraLayer(feedId: UUID, name: String) {
        let layer = CompositedLayer(
            name: name,
            isEnabled: true,
            zIndex: (layers.map { $0.zIndex }.max() ?? 0) + 1,
            centerNorm: CGPoint(x: 0.82, y: 0.82),
            sizeNorm: CGSize(width: 0.25, height: 0.25),
            rotationDegrees: 0,
            opacity: 1.0,
            source: .camera(feedId)
        )
        layers.append(layer)
        objectWillChange.send()
    }

    func addCameraLayer(feedId: UUID, name: String, centerNorm: CGPoint, sizeNorm: CGSize = CGSize(width: 0.3, height: 0.3)) {
        let layer = CompositedLayer(
            name: name,
            isEnabled: true,
            zIndex: (layers.map { $0.zIndex }.max() ?? 0) + 1,
            centerNorm: centerNorm,
            sizeNorm: sizeNorm,
            rotationDegrees: 0,
            opacity: 1.0,
            source: .camera(feedId)
        )
        layers.append(layer)
        selectedLayerID = layer.id
        objectWillChange.send()
    }

    func addMediaLayer(file: MediaFile, centerNorm: CGPoint, sizeNorm: CGSize = CGSize(width: 0.35, height: 0.35)) {
        let layer = CompositedLayer(
            name: file.name,
            isEnabled: true,
            zIndex: (layers.map { $0.zIndex }.max() ?? 0) + 1,
            centerNorm: centerNorm,
            sizeNorm: sizeNorm,
            rotationDegrees: 0,
            opacity: 1.0,
            source: .media(file)
        )
        layers.append(layer)
        selectedLayerID = layer.id
        objectWillChange.send()
    }

    func removeLayer(_ id: UUID) {
        removeLayer(id, isPreview: false)
    }

    func moveLayer(from offsets: IndexSet, to index: Int) {
        moveLayer(from: offsets, to: index, isPreview: false)
    }

    func update(_ layer: CompositedLayer) {
        update(layer, isPreview: false)
    }

    func registerPiPAudioTap(for id: UUID, tap: PlayerAudioTap?) {
        if let tap {
            pipAudioTaps[id] = tap
        } else {
            pipAudioTaps.removeValue(forKey: id)
        }
    }

    func updatePiPAudioMeter(for id: UUID, rms: Float, peak: Float) {
        pipAudioMeters[id] = AudioMeter(rms: rms, peak: peak)
    }

    func beginEditingLayer(_ id: UUID) {
        beginEditingLayer(id, isPreview: false)
    }

    func endEditing() {
        endEditing(isPreview: false)
    }

    // MARK: - TAKE integration

    func pushPreviewToProgram(overwrite: Bool = true) {
        if overwrite {
            layers = previewLayers
        } else {
            // Append with zIndex normalization (optional behavior)
            let maxZ = (layers.map { $0.zIndex }.max() ?? 0)
            var incoming = previewLayers
            // Rebase zIndex so incoming sit on top
            for i in incoming.indices {
                incoming[i].zIndex = maxZ + 1 + i
            }
            layers.append(contentsOf: incoming)
        }
        selectedLayerID = nil
        editingLayerID = nil
        objectWillChange.send()
    }
}