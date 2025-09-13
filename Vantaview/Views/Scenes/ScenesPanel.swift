import SwiftUI

struct ScenesPanel: View {
    @ObservedObject var scenesManager: ScenesManager
    @ObservedObject var layerManager: LayerStackManager

    @State private var newSceneName: String = ""
    @State private var renamingSceneID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    scenesManager.createScene(from: layerManager.layers)
                } label: {
                    Label("New Scene", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                if let sel = scenesManager.selectedSceneID,
                   let scene = scenesManager.scenes.first(where: { $0.id == sel }) {
                    Button {
                        scenesManager.applyScene(scene, to: layerManager)
                    } label: {
                        Label("Apply", systemImage: "play.rectangle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()
            }

            if scenesManager.scenes.isEmpty {
                Text("Create scenes by saving the current layer layout. Drag cameras, media and titles onto Program, then click New Scene.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                List(selection: Binding(
                    get: { scenesManager.selectedSceneID },
                    set: { scenesManager.selectedSceneID = $0 }
                )) {
                    ForEach(scenesManager.scenes) { scene in
                        HStack {
                            if renamingSceneID == scene.id {
                                TextField("Scene Name", text: Binding(
                                    get: { scene.name },
                                    set: { scenesManager.renameScene(scene.id, to: $0) }
                                ), onCommit: { renamingSceneID = nil })
                                .textFieldStyle(.roundedBorder)
                            } else {
                                Text(scene.name)
                                    .font(.caption)
                            }
                            Spacer()
                            Button {
                                scenesManager.applyScene(scene, to: layerManager)
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Apply Scene")
                        }
                        .contextMenu {
                            Button("Rename") { renamingSceneID = scene.id }
                            Button("Duplicate") { scenesManager.duplicateScene(scene.id) }
                            Button(role: .destructive) { scenesManager.deleteScene(scene.id) } label: {
                                Text("Delete")
                            }
                        }
                        .tag(scene.id)
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }
}