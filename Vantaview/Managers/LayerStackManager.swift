import Foundation
import AVFoundation

@MainActor
final class LayerStackManager: ObservableObject {
    @Published var layers: [CompositedLayer] = []
    @Published var selectedLayerID: UUID?

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
        layers.removeAll { $0.id == id }
        if selectedLayerID == id { selectedLayerID = nil }
        pipAudioTaps.removeValue(forKey: id)
        pipAudioMeters.removeValue(forKey: id)
        objectWillChange.send()
    }

    func moveLayer(from offsets: IndexSet, to index: Int) {
        layers.move(fromOffsets: offsets, toOffset: index)
        // Normalize zIndex top-to-bottom
        for (i, idx) in layers.indices.enumerated() {
            layers[idx].zIndex = i
        }
        objectWillChange.send()
    }

    func update(_ layer: CompositedLayer) {
        guard let i = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        layers[i] = layer
        objectWillChange.send()
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
}