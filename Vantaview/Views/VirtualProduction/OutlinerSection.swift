//
//  OutlinerSection.swift
//  Vantaview
//

import SwiftUI

struct OutlinerSection: View {
    let title: String
    let icon: String
    let objects: [StudioObject]
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
                    
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(objects.count)")
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
            
            // Object List
            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(objects, id: \.id) { object in
                        OutlinerObjectRow(
                            object: object,
                            isSelected: selectedObjects.contains(object.id),
                            onSelect: {
                                if selectedObjects.contains(object.id) {
                                    selectedObjects.remove(object.id)
                                } else {
                                    selectedObjects.insert(object.id)
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

struct OutlinerObjectRow: View {
    let object: StudioObject
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isVisible = true
    @State private var isRenaming = false
    @State private var editedName: String = ""
    
    var body: some View {
        HStack(spacing: 8) {
            // Visibility Toggle
            Button(action: {
                isVisible.toggle()
                object.node.isHidden = !isVisible
                object.isVisible = isVisible
            }) {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.caption)
                    .foregroundColor(isVisible ? .primary : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize()
            
            // Object Icon
            Image(systemName: object.type.icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize()
            
            // Object Name (editable)
            if isRenaming {
                TextField("Name", text: $editedName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.caption)
                    .onSubmit {
                        if !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            object.name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                            object.node.name = object.name
                        }
                        isRenaming = false
                    }
                    .onExitCommand {
                        editedName = object.name
                        isRenaming = false
                    }
            } else {
                Text(object.name)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        startRenaming()
                    }
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(isSelected ? Color.blue : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            FunctionalContextMenu(
                object: object,
                onRename: startRenaming,
                onDuplicate: duplicateObject,
                onDelete: deleteObject
            )
        }
        .onAppear {
            editedName = object.name
        }
    }
    
    private func startRenaming() {
        editedName = object.name
        isRenaming = true
    }
    
    private func duplicateObject() {
        // Post notification to duplicate object
        NotificationCenter.default.post(
            name: .duplicateObject,
            object: object.id
        )
    }
    
    private func deleteObject() {
        // Post notification to delete object
        NotificationCenter.default.post(
            name: .deleteObject,
            object: object.id
        )
    }
}

struct FunctionalContextMenu: View {
    let object: StudioObject
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Group {
            Button("Rename") {
                onRename()
            }
            .keyboardShortcut("r", modifiers: [])
            
            Button("Duplicate") {
                onDuplicate()
            }
            .keyboardShortcut("d", modifiers: [.shift])
            
            Divider()
            
            Button("Focus") {
                // Focus camera on object
                NotificationCenter.default.post(
                    name: .focusOnObject,
                    object: object.id
                )
            }
            .keyboardShortcut("f", modifiers: [])
            
            Button("Hide Others") {
                // Hide all other objects
                NotificationCenter.default.post(
                    name: .hideOthers,
                    object: object.id
                )
            }
            .keyboardShortcut("h", modifiers: [.shift])
            
            Divider()
            
            Button("Delete", role: .destructive) {
                onDelete()
            }
            .keyboardShortcut(.delete, modifiers: [])
        }
    }
}

// MARK: - Additional Notifications

extension Notification.Name {
    static let duplicateObject = Notification.Name("duplicateObject")
    static let deleteObject = Notification.Name("deleteObject")
    static let focusOnObject = Notification.Name("focusOnObject")
    static let hideOthers = Notification.Name("hideOthers")
}