//
//  BlenderStudioView.swift
//  Vistaview - Virtual Production Studio Builder
//

import SwiftUI
import SceneKit

// MARK: - Studio Tool Types

enum StudioToolType: String, CaseIterable {
    case select = "Select"
    case ledWall = "LED Wall"
    case camera = "Camera" 
    case setPiece = "Set Piece"
    case light = "Light"
    
    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .ledWall: return "display"
        case .camera: return "camera"
        case .setPiece: return "cube"
        case .light: return "lightbulb"
        }
    }
    
    var shortcut: String {
        switch self {
        case .select: return "Tab"
        case .ledWall: return "L"
        case .camera: return "C"
        case .setPiece: return "P"
        case .light: return "Shift+L"
        }
    }
}

enum TransformMode: String, CaseIterable {
    case move = "Move"
    case rotate = "Rotate"
    case scale = "Scale"
    
    var icon: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: return "arrow.clockwise"
        case .scale: return "arrow.up.left.and.arrow.down.right"
        }
    }
    
    var shortcut: String {
        switch self {
        case .move: return "G"
        case .rotate: return "R"
        case .scale: return "S"
        }
    }
}

enum ViewMode: String, CaseIterable {
    case wireframe = "Wireframe"
    case solid = "Solid"
    case material = "Material"
    
    var icon: String {
        switch self {
        case .wireframe: return "grid"
        case .solid: return "cube"
        case .material: return "paintbrush"
        }
    }
}

// MARK: - Main Blender-Style Interface

struct BlenderStudioView: View {
    @EnvironmentObject var studioManager: VirtualStudioManager
    
    // Tool States
    @State private var selectedTool: StudioToolType = .select
    @State private var transformMode: TransformMode = .move
    @State private var viewMode: ViewMode = .solid
    @State private var selectedObjects: Set<UUID> = []
    @State private var showingProperties = true
    @State private var showingOutliner = true
    
    // 3D Viewport States
    @State private var cameraPosition = SCNVector3(0, 5, 10)
    @State private var cameraTarget = SCNVector3(0, 0, 0)
    @State private var gridSize: Float = 20.0
    @State private var snapToGrid = true
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left Sidebar (Tools + Outliner)
                leftSidebar
                    .frame(width: showingOutliner ? 280 : 0)
                    .opacity(showingOutliner ? 1 : 0)
                
                // Main Content Area
                VStack(spacing: 0) {
                    // Top Toolbar
                    topToolbar
                        .frame(height: 50)
                        .background(Color.black.opacity(0.9))
                    
                    // 3D Viewport
                    viewport3D
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }
                
                // Right Properties Panel
                rightPropertiesPanel
                    .frame(width: showingProperties ? 300 : 0)
                    .opacity(showingProperties ? 1 : 0)
            }
        }
        .background(Color.black)
        .onAppear {
            setupDefaultScene()
        }
        .focusable()  
        .onKeyPress(.return) { return .handled }
        .onKeyPress(.delete) { 
            deleteSelectedObjects()
            return .handled 
        }
        .onKeyPress(.init("g")) { 
            transformMode = .move
            return .handled 
        }
        .onKeyPress(.init("r")) { 
            transformMode = .rotate
            return .handled 
        }
        .onKeyPress(.init("s")) { 
            transformMode = .scale
            return .handled 
        }
        .onKeyPress(.init("l")) { 
            selectedTool = .ledWall
            return .handled 
        }
        .onKeyPress(.init("c")) { 
            selectedTool = .camera
            return .handled 
        }
        .onKeyPress(.init("p")) { 
            selectedTool = .setPiece
            return .handled 
        }
        .onKeyPress(.tab) { 
            selectedTool = .select
            return .handled 
        }
    }
    
    // MARK: - Left Sidebar
    
    private var leftSidebar: some View {
        VStack(spacing: 0) {
            // Set Pieces Panel - New comprehensive drag-drop system
            SetPiecePanelView()
                .frame(height: 400)
                .background(Color.gray.opacity(0.1))
            
            Divider()
            
            // Scene Outliner  
            sceneOutliner
                .frame(maxHeight: .infinity)
                .background(Color.gray.opacity(0.05))
        }
    }
    
    private var sceneOutliner: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Scene Outliner")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: {}) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))
            
            // Object Categories
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    // LED Walls Section
                    OutlinerSection(
                        title: "LED Walls",
                        icon: "display",
                        objects: studioManager.studioObjects.filter { $0.type == .ledWall },
                        selectedObjects: $selectedObjects
                    )
                    
                    VirtualCameraOutlinerSection(
                        virtualCameras: studioManager.virtualCameras,
                        selectedObjects: $selectedObjects
                    )
                    
                    // Set Pieces Section
                    OutlinerSection(
                        title: "Set Pieces",
                        icon: "cube",
                        objects: studioManager.studioObjects.filter { $0.type == .setPiece },
                        selectedObjects: $selectedObjects
                    )
                    
                    // Lighting Section
                    OutlinerSection(
                        title: "Lighting",
                        icon: "lightbulb",
                        objects: studioManager.studioObjects.filter { $0.type == .light },
                        selectedObjects: $selectedObjects
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Top Toolbar
    
    private var topToolbar: some View {
        HStack(spacing: 8) {
            // Studio Templates
            HStack(spacing: 6) {
                Text("Templates:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize()
                
                ForEach(["News", "Talk Show", "Podcast", "Concert"], id: \.self) { template in
                    Button(template) {
                        loadStudioTemplate(template)
                    }
                    .keyboardShortcut(keyForTemplate(template), modifiers: [.command])
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
                    .fixedSize()
                }
            }
            
            Spacer()
            
            // Transform Tools with Shortcuts
            HStack(spacing: 6) {
                Button(action: { transformMode = .move }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 12))
                        Text("Move")
                            .font(.caption)
                        Text("(G)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(transformMode == .move ? .white : .primary)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(transformMode == .move ? Color.blue : Color.clear)
                .cornerRadius(4)
                .fixedSize()
                
                Button(action: { transformMode = .rotate }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                        Text("Rotate")
                            .font(.caption)
                        Text("(R)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(transformMode == .rotate ? .white : .primary)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(transformMode == .rotate ? Color.blue : Color.clear)
                .cornerRadius(4)
                .fixedSize()
                
                Button(action: { transformMode = .scale }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12))
                        Text("Scale")
                            .font(.caption)
                        Text("(S)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(transformMode == .scale ? .white : .primary)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(transformMode == .scale ? Color.blue : Color.clear)
                .cornerRadius(4)
                .fixedSize()
            }
            
            Spacer()
            
            // View Controls
            HStack(spacing: 8) {
                // View Mode Toggle
                HStack(spacing: 4) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in  
                        Button(action: {
                            viewMode = mode
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 12))
                                Text(mode.rawValue.prefix(1))
                                    .font(.caption2)
                            }
                            .foregroundColor(viewMode == mode ? .blue : .secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .fixedSize()
                    }
                }
                
                Divider()
                    .frame(height: 20)
                
                // Grid Settings
                Button(action: { snapToGrid.toggle() }) {
                    VStack(spacing: 2) {
                        Image(systemName: snapToGrid ? "grid" : "grid")
                            .foregroundColor(snapToGrid ? .blue : .secondary)
                        Text("Grid")
                            .font(.caption2)
                            .foregroundColor(snapToGrid ? .blue : .secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .fixedSize()
                
                Divider()
                    .frame(height: 20)
                
                // Panel Toggles
                Button(action: { showingOutliner.toggle() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "sidebar.left")
                            .foregroundColor(showingOutliner ? .blue : .secondary)
                        Text("L")
                            .font(.caption2)
                            .foregroundColor(showingOutliner ? .blue : .secondary)
                    }
                }
                .keyboardShortcut("1", modifiers: [.command])
                .buttonStyle(PlainButtonStyle())
                .fixedSize()
                
                Button(action: { showingProperties.toggle() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "sidebar.right")
                            .foregroundColor(showingProperties ? .blue : .secondary)
                        Text("R")
                            .font(.caption2)
                            .foregroundColor(showingProperties ? .blue : .secondary)
                    }
                }
                .keyboardShortcut("2", modifiers: [.command])
                .buttonStyle(PlainButtonStyle())
                .fixedSize()
            }
            
            Spacer()
            
            // Selection Actions
            HStack(spacing: 6) {
                Button("Select All") {
                    selectAll()
                }
                .keyboardShortcut("a", modifiers: [.command])
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
                .fixedSize()
                
                if !selectedObjects.isEmpty {
                    Button("Delete") {
                        deleteSelectedObjects()
                    }
                    .keyboardShortcut(.delete)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(4)
                    .fixedSize()
                    
                    Button("Duplicate") {
                        duplicateSelected()
                    }
                    .keyboardShortcut("d", modifiers: [.command])
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)
                    .fixedSize()
                }
            }
            
            Spacer()
            
            // Export/Import
            HStack(spacing: 6) {
                Button("Import") {
                    // Import studio layout
                }
                .keyboardShortcut("i", modifiers: [.command])
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
                .fixedSize()
                
                Button("Export") {
                    // Export studio layout
                }
                .keyboardShortcut("e", modifiers: [.command])
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .cornerRadius(4)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func keyForTemplate(_ template: String) -> KeyEquivalent {
        switch template {
        case "News": return "1"
        case "Talk Show": return "2"
        case "Podcast": return "3"
        case "Concert": return "4"
        default: return "1"
        }
    }
    
    // MARK: - 3D Viewport
    
    private var viewport3D: some View {
        ZStack {
            Enhanced3DViewport(
                selectedTool: $selectedTool,
                transformMode: $transformMode,
                viewMode: $viewMode,
                selectedObjects: $selectedObjects,
                snapToGrid: $snapToGrid,
                gridSize: $gridSize
            )
            
            // Drop feedback overlay
            DropFeedbackOverlay()
            
            // Debug overlay (temporary)
            InteractionDebugOverlay()
            
            // 3D Viewport Overlays
            VStack {
                HStack {
                    Spacer()
                    
                    // Enhanced 3D Axis Gizmo with camera integration
                    AxisGizmo()
                        .frame(width: 80, height: 80)
                }
                
                Spacer()
                
                // Bottom Viewport Info Bar
                HStack {
                    // Left info
                    HStack(spacing: 12) {
                        Text("Objects: \(studioManager.studioObjects.count)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        if !selectedObjects.isEmpty {
                            Text("Selected: \(selectedObjects.count)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        
                        Text("Tool: \(selectedTool.rawValue)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Center - Instructions
                    VStack(spacing: 2) {
                        Text("💡 Click & drag to orbit camera • Drag set pieces from left panel to place")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("G=Move • R=Rotate • S=Scale • Enter=Confirm • Esc=Cancel")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    // Right - View mode and grid
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: snapToGrid ? "grid" : "grid")
                                .foregroundColor(snapToGrid ? .blue : .secondary)
                            Text("Grid: \(gridSize, specifier: "%.1f")m")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        HStack(spacing: 4) {
                            Text("View: \(viewMode.rawValue)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Image(systemName: viewMode.icon)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(12)
        }
    }
    
    // MARK: - Right Properties Panel
    
    private var rightPropertiesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Properties")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if selectedObjects.isEmpty {
                        // No Selection State
                        VStack(spacing: 16) {
                            Image(systemName: "cube.transparent")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            
                            Text("No Object Selected")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Select an object in the viewport or outliner to view its properties")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        // Object Properties
                        if let firstSelectedId = selectedObjects.first,
                           let selectedObject = studioManager.studioObjects.first(where: { $0.id == firstSelectedId }) {
                            
                            ObjectPropertiesView(object: selectedObject)
                        }
                        
                        // Transform Properties
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Multi-Selection")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("\(selectedObjects.count) objects selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("Delete All") {
                                deleteSelectedObjects()
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color.gray.opacity(0.05))
    }
    
    // MARK: - Actions
    
    private func setupDefaultScene() {
        // Setup will be handled by VirtualStudioManager init
    }
    
    private func loadStudioTemplate(_ template: String) {
        // Clear current scene
        studioManager.studioObjects.removeAll()
        studioManager.virtualCameras.removeAll()
        
        // Load template based on name
        switch template {
        case "News":
            createNewsStudioTemplate()
        case "Talk Show":
            createTalkShowTemplate()
        case "Podcast":
            createPodcastTemplate()
        case "Concert":
            createConcertTemplate()
        default:
            break
        }
    }
    
    private func createNewsStudioTemplate() {
        // Add LED wall backdrop
        if let wall = LEDWallAsset.predefinedWalls.first {
            studioManager.addLEDWall(from: wall, at: SCNVector3(0, 2, -5))
        }
        
        // Add desk
        if let desk = SetPieceAsset.predefinedPieces.first(where: { $0.name.contains("Desk") }) {
            studioManager.addSetPiece(from: desk, at: SCNVector3(0, 0, -2))
        }
        
        // Add cameras
        let mainCam = VirtualCamera(name: "Main Camera", position: SCNVector3(0, 1.5, 4))
        let sideCam = VirtualCamera(name: "Side Camera", position: SCNVector3(3, 1.5, 1))
        
        studioManager.virtualCameras.append(contentsOf: [mainCam, sideCam])
        studioManager.scene.rootNode.addChildNode(mainCam.node)
        studioManager.scene.rootNode.addChildNode(sideCam.node)
    }
    
    private func createTalkShowTemplate() {
        // Similar template creation logic
    }
    
    private func createPodcastTemplate() {
        // Similar template creation logic
    }
    
    private func createConcertTemplate() {
        // Similar template creation logic
    }
    
    // MARK: - Keyboard Actions
    
    private func deleteSelectedObjects() {
        let objectsToDelete = studioManager.studioObjects.filter { selectedObjects.contains($0.id) }
        for object in objectsToDelete {
            studioManager.deleteObject(object)
        }
        selectedObjects.removeAll()
    }
    
    private func selectAll() {
        selectedObjects = Set(studioManager.studioObjects.map { $0.id })
    }
    
    private func duplicateSelected() {
        let objectsToDuplicate = studioManager.studioObjects.filter { selectedObjects.contains($0.id) }
        var newSelection: Set<UUID> = []
        
        for object in objectsToDuplicate {
            let newPosition = SCNVector3(
                object.position.x + 1,
                object.position.y,
                object.position.z + 1
            )
            
            let duplicate = StudioObject(name: "\(object.name) Copy", type: object.type, position: newPosition)
            duplicate.rotation = object.rotation
            duplicate.scale = object.scale
            
            if let geometry = object.node.geometry?.copy() as? SCNGeometry {
                duplicate.node.geometry = geometry
            }
            
            studioManager.studioObjects.append(duplicate)
            studioManager.scene.rootNode.addChildNode(duplicate.node)
            newSelection.insert(duplicate.id)
        }
        
        selectedObjects = newSelection
    }
}