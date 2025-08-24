//
//  TransformPropertiesView.swift
//  Vantaview
//

import SwiftUI
import SceneKit

struct TransformPropertiesView: View {
    let selectedObjects: Set<UUID>
    @ObservedObject var studioManager: VirtualStudioManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Multi-Selection")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("\(selectedObjects.count) objects selected")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Delete All") {
                let objectsToDelete = studioManager.studioObjects.filter { selectedObjects.contains($0.id) }
                for object in objectsToDelete {
                    studioManager.deleteObject(object)
                }
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
    }
}