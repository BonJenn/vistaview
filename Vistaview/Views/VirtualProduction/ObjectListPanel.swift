//
//  ObjectListPanel.swift
//  Vistaview - Scene object management panel
//

import SwiftUI
import SceneKit

struct ObjectListPanel: View {
    @EnvironmentObject var studioManager: VirtualStudioManager
    @Binding var selectedObjects: Set<UUID>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Scene Objects")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(studioManager.studioObjects.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.black.opacity(0.8))
            
            Divider()
                .background(.white.opacity(0.2))
            
            // Object List
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(studioManager.studioObjects, id: \.id) { object in
                        ObjectListRow(
                            object: object,
                            isSelected: selectedObjects.contains(object.id),
                            onSelect: { selectObject(object) },
                            onToggleVisibility: { toggleVisibility(object) },
                            onToggleLock: { toggleLock(object) },
                            onDelete: { deleteObject(object) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .background(.black.opacity(0.4))
        }
        .background(.regularMaterial)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private func selectObject(_ object: StudioObject) {
        // Clear other selections
        for obj in studioManager.studioObjects {
            obj.setSelected(false)
        }
        selectedObjects.removeAll()
        
        // Select this object
        object.setSelected(true)
        selectedObjects.insert(object.id)
        
        print("✅ Selected object from list: \(object.name)")
    }
    
    private func toggleVisibility(_ object: StudioObject) {
        object.isVisible.toggle()
        object.updateNodeTransform()
        print("👁️ Toggled visibility for \(object.name): \(object.isVisible)")
    }
    
    private func toggleLock(_ object: StudioObject) {
        object.isLocked.toggle()
        print("🔒 Toggled lock for \(object.name): \(object.isLocked)")
    }
    
    private func deleteObject(_ object: StudioObject) {
        studioManager.deleteObject(object)
        selectedObjects.remove(object.id)
        print("🗑️ Deleted object: \(object.name)")
    }
}

struct ObjectListRow: View {
    let object: StudioObject
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleVisibility: () -> Void
    let onToggleLock: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Object type icon
            Image(systemName: iconForObjectType(object.type))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorForObjectType(object.type))
                .frame(width: 20)
            
            // Object name
            Text(object.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            // Controls (show on hover or when selected)
            if isHovered || isSelected {
                HStack(spacing: 4) {
                    // Visibility toggle
                    Button(action: onToggleVisibility) {
                        Image(systemName: object.isVisible ? "eye" : "eye.slash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(object.isVisible ? .green : .red)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help(object.isVisible ? "Hide object" : "Show object")
                    
                    // Lock toggle
                    Button(action: onToggleLock) {
                        Image(systemName: object.isLocked ? "lock.fill" : "lock.open")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(object.isLocked ? .orange : .gray)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help(object.isLocked ? "Unlock object" : "Lock object")
                    
                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Delete object")
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColorForRow())
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColorForRow(), lineWidth: isSelected ? 2 : 0)
        )
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    private func backgroundColorForRow() -> Color {
        if isSelected {
            return colorForObjectType(object.type).opacity(0.3)
        } else if isHovered {
            return .white.opacity(0.1)
        } else {
            return .clear
        }
    }
    
    private func borderColorForRow() -> Color {
        return colorForObjectType(object.type)
    }
    
    private func iconForObjectType(_ type: StudioTool) -> String {
        switch type {
        case .ledWall: return "tv"
        case .camera: return "video"
        case .light: return "lightbulb"
        case .setPiece: return "cube.box"
        case .select: return "cursorarrow"
        }
    }
    
    private func colorForObjectType(_ type: StudioTool) -> Color {
        switch type {
        case .ledWall: return .blue
        case .camera: return .orange
        case .light: return .yellow
        case .setPiece: return .green
        case .select: return .purple
        }
    }
}

#Preview {
    VStack {
        ObjectListPanel(selectedObjects: .constant([]))
            .frame(width: 280, height: 400)
            .background(.black)
    }
}