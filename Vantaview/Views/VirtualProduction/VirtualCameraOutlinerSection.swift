//
//  VirtualCameraOutlinerSection.swift
//  Vantaview
//

import SwiftUI

struct VirtualCameraOutlinerSection: View {
    let virtualCameras: [VirtualCamera]
    @Binding var selectedObjects: Set<UUID>
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Section Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "camera")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text("Virtual Cameras")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(virtualCameras.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Camera List
            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(virtualCameras, id: \.id) { camera in
                        VirtualCameraRow(
                            camera: camera,
                            isSelected: selectedObjects.contains(camera.id),
                            onSelect: {
                                if selectedObjects.contains(camera.id) {
                                    selectedObjects.remove(camera.id)
                                } else {
                                    selectedObjects.insert(camera.id)
                                }
                            }
                        )
                    }
                }
                .padding(.leading, 16)
            }
        }
    }
}

struct VirtualCameraRow: View {
    let camera: VirtualCamera
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isVisible = true
    
    var body: some View {
        HStack(spacing: 8) {
            // Visibility Toggle
            Button(action: {
                isVisible.toggle()
                camera.node.isHidden = !isVisible
            }) {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.caption)
                    .foregroundColor(isVisible ? .primary : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Camera Icon
            Image(systemName: "camera")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Camera Name
            Text(camera.name)
                .font(.caption)
                .foregroundColor(isSelected ? .white : .primary)
            
            Spacer()
            
            // Active indicator
            if camera.isActive {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(isSelected ? Color.blue : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Set Active") {
                // Handle set active
            }
            Button("Rename") {
                // Handle rename
            }
            Button("Duplicate") {
                // Handle duplicate
            }
            Button("Delete") {
                // Handle delete
            }
        }
    }
}