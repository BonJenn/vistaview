//
//  CommandPaletteView.swift
//  Vistaview - Raycast-Inspired Command Palette
//

import SwiftUI
import SceneKit

struct CommandPaletteView: View {
    @EnvironmentObject var studioManager: VirtualStudioManager
    @Binding var searchText: String
    @Binding var selectedTool: StudioTool
    @State private var selectedIndex: Int = 0
    @State private var hoveredIndex: Int? = nil
    
    // Spacing constants
    private let spacing2: CGFloat = 8
    private let spacing3: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            
            Divider()
                .background(.tertiary.opacity(0.5))
            
            commandResults
        }
        .frame(width: 600)
        .frame(maxHeight: 500)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var searchHeader: some View {
        HStack(spacing: spacing2) {
            Image(systemName: "command")
                .font(.system(.callout, design: .default, weight: .semibold))
                .foregroundColor(.blue)
            
            TextField("Search tools, objects, templates...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .default, weight: .regular))
                .onSubmit {
                    executeSelectedCommand()
                }
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, spacing3)
        .padding(.vertical, 12)
    }
    
    private var commandResults: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if searchText.isEmpty {
                    recentCommands
                    studioActions
                    toolCommands  
                    templateCommands
                } else {
                    filteredResults
                }
            }
            .padding(.vertical, spacing2)
        }
    }
    
    private var recentCommands: some View {
        CommandSection(title: "Recent") {
            CommandItem(
                icon: "tv",
                title: "Add LED Wall",
                subtitle: "Place a new LED wall in the scene",
                shortcut: "L",
                index: 0,
                selectedIndex: $selectedIndex,
                hoveredIndex: $hoveredIndex
            ) {
                addLEDWall()
            }
            
            CommandItem(
                icon: "cube",
                title: "Add Set Piece",
                subtitle: "Browse and place set pieces",
                shortcut: "P", 
                index: 1,
                selectedIndex: $selectedIndex,
                hoveredIndex: $hoveredIndex
            ) {
                selectedTool = .setPiece
            }
            
            CommandItem(
                icon: "video",
                title: "Add Camera",
                subtitle: "Place a virtual camera",
                shortcut: "C",
                index: 2,
                selectedIndex: $selectedIndex,
                hoveredIndex: $hoveredIndex
            ) {
                addCamera()
            }
        }
    }
    
    private var studioActions: some View {
        CommandSection(title: "Studio Actions") {
            CommandItem(
                icon: "square.grid.3x3",
                title: "Load News Template",
                subtitle: "Pre-built news studio layout",
                shortcut: "⌘1",
                index: 3,
                selectedIndex: $selectedIndex,
                hoveredIndex: $hoveredIndex
            ) {
                loadTemplate("News")
            }
            
            CommandItem(
                icon: "mic.circle",
                title: "Load Podcast Template", 
                subtitle: "Intimate podcast studio setup",
                shortcut: "⌘2",
                index: 4,
                selectedIndex: $selectedIndex,
                hoveredIndex: $hoveredIndex
            ) {
                loadTemplate("Podcast")
            }
            
            CommandItem(
                icon: "music.note",
                title: "Load Concert Template",
                subtitle: "Large concert stage layout",
                shortcut: "⌘3",
                index: 5,
                selectedIndex: $selectedIndex,
                hoveredIndex: $hoveredIndex
            ) {
                loadTemplate("Concert")
            }
        }
    }
    
    private var toolCommands: some View {
        CommandSection(title: "Tools") {
            ForEach(Array(StudioTool.allCases.enumerated()), id: \.element) { index, tool in
                CommandItem(
                    icon: tool.icon,
                    title: tool.name,
                    subtitle: "Switch to \(tool.name.lowercased()) tool",
                    shortcut: shortcutForTool(tool),
                    index: 6 + index,
                    selectedIndex: $selectedIndex,
                    hoveredIndex: $hoveredIndex
                ) {
                    selectedTool = tool
                }
            }
        }
    }
    
    private var templateCommands: some View {
        CommandSection(title: "Scene Management") {
            CommandItem(
                icon: "trash",
                title: "Clear Scene",
                subtitle: "Remove all objects from scene",
                shortcut: "⌘⌫",
                index: 15,
                selectedIndex: $selectedIndex,
                hoveredIndex: $hoveredIndex,
                isDestructive: true
            ) {
                clearScene()
            }
            
            CommandItem(
                icon: "square.and.arrow.up",
                title: "Export Scene",
                subtitle: "Save current scene layout",
                shortcut: "⌘E",
                index: 16,
                selectedIndex: $selectedIndex,
                hoveredIndex: $hoveredIndex
            ) {
                exportScene()
            }
            
            CommandItem(
                icon: "square.and.arrow.down",
                title: "Import Scene",
                subtitle: "Load saved scene layout",
                shortcut: "⌘I",
                index: 17,
                selectedIndex: $selectedIndex,
                hoveredIndex: $hoveredIndex
            ) {
                importScene()
            }
        }
    }
    
    private var filteredResults: some View {
        Group {
            // This would contain filtered search results
            // For now, showing a simple implementation
            Text("Search results for '\(searchText)'")
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundColor(.secondary)
                .padding()
        }
    }
    
    // MARK: - Helper Functions
    
    private func shortcutForTool(_ tool: StudioTool) -> String {
        switch tool {
        case .select: return "Tab"
        case .ledWall: return "L"
        case .camera: return "C"
        case .setPiece: return "P"
        case .light: return "Shift+L"
        case .staging: return "S"
        }
    }
    
    private func executeSelectedCommand() {
        // Execute command at selected index
        print("Executing command at index: \(selectedIndex)")
    }
    
    // MARK: - Actions
    
    private func addLEDWall() {
        if let wall = LEDWallAsset.predefinedWalls.first {
            studioManager.addLEDWall(from: wall, at: SCNVector3(0, 2, 0))
        }
    }
    
    private func addCamera() {
        let camera = VirtualCamera(name: "Camera \(studioManager.virtualCameras.count + 1)", position: SCNVector3(0, 1.5, 5))
        studioManager.virtualCameras.append(camera)
        studioManager.scene.rootNode.addChildNode(camera.node)
    }
    
    private func loadTemplate(_ name: String) {
        print("Loading template: \(name)")
        // Template loading implementation
    }
    
    private func clearScene() {
        studioManager.studioObjects.removeAll()
        // Clear scene nodes
    }
    
    private func exportScene() {
        print("Exporting scene...")
        // Export implementation
    }
    
    private func importScene() {
        print("Importing scene...")
        // Import implementation
    }
}

struct CommandSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            content
        }
    }
}

struct CommandItem: View {
    let icon: String
    let title: String  
    let subtitle: String
    let shortcut: String?
    let index: Int
    @Binding var selectedIndex: Int
    @Binding var hoveredIndex: Int?
    let isDestructive: Bool
    let action: () -> Void
    
    init(
        icon: String,
        title: String,
        subtitle: String,
        shortcut: String? = nil,
        index: Int,
        selectedIndex: Binding<Int>,
        hoveredIndex: Binding<Int?>,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.shortcut = shortcut
        self.index = index
        self._selectedIndex = selectedIndex
        self._hoveredIndex = hoveredIndex
        self.isDestructive = isDestructive
        self.action = action
    }
    
    private var isHighlighted: Bool {
        selectedIndex == index || hoveredIndex == index
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: icon)
                    .font(.system(.callout, design: .default, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .blue)
                    .frame(width: 20, height: 20)
                
                // Content
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.body, design: .default, weight: .regular))
                        .foregroundColor(isDestructive ? .red : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(subtitle)
                        .font(.system(.caption, design: .default, weight: .regular))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
                
                // Shortcut
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tertiary.opacity(0.5))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHighlighted ? .blue.opacity(0.1) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredIndex = hovering ? index : nil
        }
        .animation(.easeInOut(duration: 0.1), value: isHighlighted)
    }
}