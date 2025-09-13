import Foundation
import SwiftUI

struct SceneLayout: Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var layers: [CompositedLayer]

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), layers: [CompositedLayer]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.layers = layers
    }
}

@MainActor
final class ScenesManager: ObservableObject {
    @Published var scenes: [SceneLayout] = []
    @Published var selectedSceneID: UUID?

    func createScene(from layers: [CompositedLayer], name: String? = nil) {
        let number = (scenes.count + 1)
        let scene = SceneLayout(name: name ?? "Scene \(number)", layers: layers)
        scenes.append(scene)
        selectedSceneID = scene.id
    }

    func applyScene(_ scene: SceneLayout, to layerManager: LayerStackManager) {
        layerManager.layers = scene.layers
        layerManager.selectedLayerID = nil
        layerManager.objectWillChange.send()
    }

    func deleteScene(_ id: UUID) {
        scenes.removeAll { $0.id == id }
        if selectedSceneID == id { selectedSceneID = nil }
    }

    func duplicateScene(_ id: UUID) {
        guard let scene = scenes.first(where: { $0.id == id }) else { return }
        var copy = scene
        copy.name = "\(scene.name) Copy"
        copy.layers = scene.layers
        scenes.append(copy)
    }

    func renameScene(_ id: UUID, to newName: String) {
        guard let i = scenes.firstIndex(where: { $0.id == id }) else { return }
        scenes[i].name = newName
    }
}