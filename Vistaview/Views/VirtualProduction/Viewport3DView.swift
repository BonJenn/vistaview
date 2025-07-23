//
//  Viewport3DView.swift
//  Vistaview
//

import SwiftUI
import SceneKit

#if os(macOS)
struct Viewport3DView: NSViewRepresentable {
    let studioManager: VirtualStudioManager
    @Binding var selectedTool: StudioToolType
    @Binding var transformMode: TransformMode
    @Binding var viewMode: ViewMode
    @Binding var selectedObjects: Set<UUID>
    @Binding var snapToGrid: Bool
    @Binding var gridSize: Float
    
    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = studioManager.scene
        scnView.backgroundColor = NSColor.black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics = false
        scnView.delegate = context.coordinator
        
        // Add gesture recognizers
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(clickGesture)
        
        let rightClickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRightClick(_:)))
        rightClickGesture.buttonMask = 2 
        scnView.addGestureRecognizer(rightClickGesture)
        
        // Enable drag and drop
        scnView.registerForDraggedTypes([.string])
        
        // Setup default camera
        setupDefaultCamera(scnView)
        
        return scnView
    }
    
    func updateNSView(_ nsView: SCNView, context: Context) {
        // Update view mode
        switch viewMode {
        case .wireframe:
            nsView.debugOptions = [.showWireframe]
        case .solid:
            nsView.debugOptions = []
        case .material:
            nsView.debugOptions = []
        }
        
        context.coordinator.selectedTool = selectedTool
        context.coordinator.transformMode = transformMode
        context.coordinator.selectedObjects = selectedObjects
        context.coordinator.snapToGrid = snapToGrid
        context.coordinator.gridSize = gridSize
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func setupDefaultCamera(_ scnView: SCNView) {
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.zNear = 0.1
        camera.zFar = 1000
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(10, 10, 10)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        
        studioManager.scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
    }
    
    final class Coordinator: NSObject, SCNSceneRendererDelegate, NSDraggingDestination {
        let parent: Viewport3DView
        var selectedTool: StudioToolType = .select
        var transformMode: TransformMode = .move
        var selectedObjects: Set<UUID> = []
        var snapToGrid: Bool = true
        var gridSize: Float = 1.0
        
        init(_ parent: Viewport3DView) {
            self.parent = parent
        }
        
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)
            
            Task { @MainActor in
                switch selectedTool {
                case .select:
                    handleSelection(at: location, in: scnView)
                case .ledWall, .camera, .setPiece, .light:
                    handleObjectPlacement(at: location, in: scnView)
                }
            }
        }
        
        @objc func handleRightClick(_ gesture: NSClickGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)
            
            Task { @MainActor in
                showContextMenu(at: location, in: scnView)
            }
        }
        
        @MainActor
        private func showContextMenu(at point: CGPoint, in scnView: SCNView) {
            let menu = NSMenu()
            
            // Add context menu items based on what's under the cursor
            let hitResults = scnView.hitTest(point, options: nil)
            
            if let hitResult = hitResults.first,
               let object = parent.studioManager.getObject(from: hitResult.node) {
                
                // Object-specific menu
                menu.addItem(NSMenuItem(title: "Select \(object.name)", action: #selector(selectObject), keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
                menu.addItem(NSMenuItem(title: "Focus on Object", action: #selector(focusOnObject), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Duplicate", action: #selector(duplicateObject), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Delete", action: #selector(deleteObject), keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
                menu.addItem(NSMenuItem(title: "Reset Transform", action: #selector(resetTransform), keyEquivalent: ""))
                
            } else {
                // Empty space menu
                menu.addItem(NSMenuItem(title: "Add LED Wall", action: #selector(addLEDWall), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Add Camera", action: #selector(addCamera), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Add Set Piece", action: #selector(addSetPiece), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Add Light", action: #selector(addLight), keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
                menu.addItem(NSMenuItem(title: "Select All", action: #selector(selectAll), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Deselect All", action: #selector(deselectAll), keyEquivalent: ""))
            }
            
            // Show the menu
            menu.popUp(positioning: nil, at: point, in: scnView)
        }
        
        // MARK: - NSDraggingDestination
        
        func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            return .copy
        }
        
        func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            return .copy
        }
        
        func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let location = sender.draggingLocation
            
            // Check if dragging a set piece
            if let data = sender.draggingPasteboard.data(forType: .string),
               let setPieceID = String(data: data, encoding: .utf8),
               let setPiece = SetPieceAsset.predefinedPieces.first(where: { $0.id.uuidString == setPieceID }) {
                
                Task { @MainActor in  
                    // Convert drop location to world position - need to get the SCNView from elsewhere
                    let worldPos = SCNVector3(Float.random(in: -5...5), 0, Float.random(in: -5...5))
                    let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
                    
                    // Add the set piece to the scene
                    parent.studioManager.addSetPieceFromAsset(setPiece, at: finalPos)
                }
                
                return true
            }
            
            return false
        }
        
        // Context menu actions
        @objc private func selectObject() { /* Implement */ }
        @objc private func focusOnObject() { /* Implement */ }
        @objc private func duplicateObject() { /* Implement */ }
        @objc private func deleteObject() { /* Implement */ }
        @objc private func resetTransform() { /* Implement */ }
        @objc private func addLEDWall() { /* Implement */ }
        @objc private func addCamera() { /* Implement */ }
        @objc private func addSetPiece() { /* Implement */ }
        @objc private func addLight() { /* Implement */ }
        @objc private func selectAll() { /* Implement */ }
        @objc private func deselectAll() { /* Implement */ }
        
        @MainActor
        private func handleSelection(at point: CGPoint, in scnView: SCNView) {
            let hitResults = scnView.hitTest(point, options: nil)
            
            if let hitResult = hitResults.first {
                let hitNode = hitResult.node
                
                // Find the studio object that contains this node
                if let object = parent.studioManager.getObject(from: hitNode) {
                    if selectedObjects.contains(object.id) {
                        selectedObjects.remove(object.id)
                    } else {
                        // Clear previous selection if not holding modifier
                        selectedObjects.removeAll()
                        selectedObjects.insert(object.id)
                    }
                }
            } else {
                // Clicked on empty space, clear selection
                selectedObjects.removeAll()
            }
        }
        
        @MainActor
        private func handleObjectPlacement(at point: CGPoint, in scnView: SCNView) {
            // Convert screen point to world position
            let worldPos = parent.studioManager.worldPosition(from: point, in: scnView)
            
            // Snap to grid if enabled
            let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
            
            // Convert StudioToolType to StudioTool
            let studioTool: StudioTool
            switch selectedTool {
            case .select: studioTool = .select
            case .ledWall: studioTool = .ledWall
            case .camera: studioTool = .camera
            case .setPiece: studioTool = .setPiece
            case .light: studioTool = .light
            }
            
            // Place the object
            parent.studioManager.addObject(type: studioTool, at: finalPos)
        }
        
        private func snapToGridPosition(_ position: SCNVector3) -> SCNVector3 {
            let gridStep = CGFloat(gridSize)
            return SCNVector3(
                round(position.x / gridStep) * gridStep,
                position.y, // Don't snap Y to allow vertical positioning
                round(position.z / gridStep) * gridStep
            )
        }
    }
}
#else
// iOS implementation would go here
struct Viewport3DView: UIViewRepresentable {
    // Similar implementation for iOS
    func makeUIView(context: Context) -> SCNView { SCNView() }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
#endif