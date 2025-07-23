//
//  Enhanced3DViewport.swift  
//  Vistaview - Functional 3D Viewport with Drag & Drop
//

import SwiftUI
import SceneKit

#if os(macOS)
import AppKit

struct Enhanced3DViewport: NSViewRepresentable {
    @EnvironmentObject var studioManager: VirtualStudioManager
    @Binding var selectedTool: StudioToolType
    @Binding var transformMode: TransformMode
    @Binding var viewMode: ViewMode
    @Binding var selectedObjects: Set<UUID>
    @Binding var snapToGrid: Bool
    @Binding var gridSize: Float
    
    // Transform modal states
    @State private var isTransforming = false
    @State private var transformAxis: TransformAxis = .free
    @State private var originalPositions: [UUID: SCNVector3] = [:]
    
    enum TransformAxis {
        case free, x, y, z
        
        var color: NSColor {
            switch self {
            case .free: return .white
            case .x: return .systemRed
            case .y: return .systemGreen  
            case .z: return .systemBlue
            }
        }
    }
    
    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = studioManager.scene
        scnView.backgroundColor = NSColor.black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics = false
        scnView.delegate = context.coordinator
        
        // Enable drag and drop
        scnView.registerForDraggedTypes([.string])
        
        // Set coordinator as the dragging destination delegate
        let draggingDestination = DraggingDestinationView()
        draggingDestination.coordinator = context.coordinator
        draggingDestination.scnView = scnView
        scnView.addSubview(draggingDestination)
        draggingDestination.frame = scnView.bounds
        draggingDestination.autoresizingMask = [.width, .height]
        
        // Add gesture recognizers
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(clickGesture)
        
        let rightClickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRightClick(_:)))
        rightClickGesture.buttonMask = 2
        scnView.addGestureRecognizer(rightClickGesture)
        
        // Mouse move for transform tracking
        let mouseMoveGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMouseMove(_:)))
        scnView.addGestureRecognizer(mouseMoveGesture)
        
        // Key event monitoring
        scnView.window?.makeFirstResponder(scnView)
        
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
        
        // Update coordinator state
        context.coordinator.selectedTool = selectedTool
        context.coordinator.transformMode = transformMode
        context.coordinator.selectedObjects = selectedObjects
        context.coordinator.snapToGrid = snapToGrid
        context.coordinator.gridSize = gridSize
        
        // Handle transform mode changes
        if transformMode != context.coordinator.lastTransformMode {
            context.coordinator.startTransformMode()
            context.coordinator.lastTransformMode = transformMode
        }
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
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    
    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        let parent: Enhanced3DViewport
        var selectedTool: StudioToolType = .select
        var transformMode: TransformMode = .move
        var lastTransformMode: TransformMode = .move
        var selectedObjects: Set<UUID> = []
        var snapToGrid: Bool = true
        var gridSize: Float = 1.0
        
        // Transform state
        var isTransforming = false
        var transformAxis: TransformAxis = .free
        var originalPositions: [UUID: SCNVector3] = [:]
        var transformStartPoint: CGPoint = .zero
        
        init(_ parent: Enhanced3DViewport) {
            self.parent = parent
            super.init()
        }
        
        // MARK: - Mouse Events
        
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)
            
            Task { @MainActor in
                if isTransforming {
                    // Confirm transform
                    confirmTransform()
                    return
                }
                
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
                if isTransforming {
                    cancelTransform()
                    return
                }
                
                showContextMenu(at: location, in: scnView)
            }
        }
        
        @objc func handleMouseMove(_ gesture: NSPanGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            
            if isTransforming {
                let location = gesture.location(in: scnView)
                updateTransform(at: location, in: scnView)
            }
        }
        
        // MARK: - Transform Modal System
        
        func startTransformMode() {
            guard !selectedObjects.isEmpty else { return }
            
            isTransforming = true
            transformAxis = .free
            
            // Store original positions
            originalPositions.removeAll()
            
            Task { @MainActor in
                for objId in selectedObjects {
                    if let obj = parent.studioManager.studioObjects.first(where: { $0.id == objId }) {
                        originalPositions[objId] = obj.position
                    }
                }
            }
            
            // Disable camera control during transform
            if let scnView = findSCNView() {
                scnView.allowsCameraControl = false
            }
        }
        
        func confirmTransform() {
            isTransforming = false
            transformAxis = .free
            originalPositions.removeAll()
            
            // Re-enable camera control
            if let scnView = findSCNView() {
                scnView.allowsCameraControl = true
            }
        }
        
        func cancelTransform() {
            // Restore original positions
            Task { @MainActor in
                for (objId, originalPos) in originalPositions {
                    if let obj = parent.studioManager.studioObjects.first(where: { $0.id == objId }) {
                        obj.position = originalPos
                        obj.updateNodeTransform()
                    }
                }
            }
            
            confirmTransform()
        }
        
        func updateTransform(at point: CGPoint, in scnView: SCNView) {
            guard isTransforming else { return }
            
            let deltaX = Float(point.x - transformStartPoint.x) * 0.01
            let deltaY = Float(transformStartPoint.y - point.y) * 0.01 // Invert Y
            
            Task { @MainActor in
                for objId in selectedObjects {
                    guard let obj = parent.studioManager.studioObjects.first(where: { $0.id == objId }),
                          let originalPos = originalPositions[objId] else { continue }
                    
                    var newPosition = originalPos
                    
                    switch transformMode {
                    case .move:
                        switch transformAxis {
                        case .free:
                            newPosition.x += CGFloat(deltaX)
                            newPosition.y += CGFloat(deltaY)
                        case .x:
                            newPosition.x += CGFloat(deltaX)
                        case .y:
                            newPosition.y += CGFloat(deltaY)
                        case .z:
                            newPosition.z += CGFloat(deltaX) // Use X movement for Z
                        }
                        
                    case .rotate:
                        // Implement rotation transform
                        let rotationDelta = deltaX * Float.pi / 180 * 10 // Convert to radians
                        switch transformAxis {
                        case .free, .y:
                            obj.rotation.y += CGFloat(rotationDelta)
                        case .x:
                            obj.rotation.x += CGFloat(rotationDelta)
                        case .z:
                            obj.rotation.z += CGFloat(rotationDelta)
                        }
                        
                    case .scale:
                        // Implement scale transform
                        let scaleDelta = 1.0 + deltaX
                        switch transformAxis {
                        case .free:
                            obj.scale = SCNVector3(scaleDelta, scaleDelta, scaleDelta)
                        case .x:
                            obj.scale.x = CGFloat(scaleDelta)
                        case .y:
                            obj.scale.y = CGFloat(scaleDelta)
                        case .z:
                            obj.scale.z = CGFloat(scaleDelta)
                        }
                    }
                    
                    if transformMode == .move {
                        if snapToGrid {
                            newPosition = snapToGridPosition(newPosition)
                        }
                        obj.position = newPosition
                    }
                    
                    obj.updateNodeTransform()
                }
            }
        }
        
        // MARK: - Drag & Drop Implementation
        
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
                    // Get SCNView from drag info
                    guard let scnView = findSCNView() else { return }
                    
                    // Convert drop location to world position
                    let worldPos = convertScreenToWorld(point: location, in: scnView)
                    let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
                    
                    // Add the set piece to the scene
                    parent.studioManager.addSetPieceFromAsset(setPiece, at: finalPos)
                }
                
                return true
            }
            
            return false
        }
        
        // MARK: - Selection & Context Menu
        
        @MainActor
        private func handleSelection(at point: CGPoint, in scnView: SCNView) {
            let hitResults = scnView.hitTest(point, options: nil)
            
            if let hitResult = hitResults.first {
                let hitNode = hitResult.node
                
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
                selectedObjects.removeAll()
            }
        }
        
        @MainActor
        private func handleObjectPlacement(at point: CGPoint, in scnView: SCNView) {
            let worldPos = convertScreenToWorld(point: point, in: scnView)
            let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
            
            let studioTool: StudioTool
            switch selectedTool {
            case .select: studioTool = .select
            case .ledWall: studioTool = .ledWall
            case .camera: studioTool = .camera
            case .setPiece: studioTool = .setPiece
            case .light: studioTool = .light
            }
            
            parent.studioManager.addObject(type: studioTool, at: finalPos)
        }
        
        @MainActor
        private func showContextMenu(at point: CGPoint, in scnView: SCNView) {
            let menu = NSMenu()
            
            let hitResults = scnView.hitTest(point, options: nil)
            
            if let hitResult = hitResults.first,
               let object = parent.studioManager.getObject(from: hitResult.node) {
                
                // Object-specific menu
                let selectItem = NSMenuItem(title: "Select \(object.name)", action: #selector(selectObject), keyEquivalent: "")
                selectItem.target = self
                selectItem.representedObject = object.id
                menu.addItem(selectItem)
                
                menu.addItem(NSMenuItem.separator())
                
                let duplicateItem = NSMenuItem(title: "Duplicate", action: #selector(duplicateObject), keyEquivalent: "")
                duplicateItem.target = self
                duplicateItem.representedObject = object.id
                menu.addItem(duplicateItem)
                
                let renameItem = NSMenuItem(title: "Rename", action: #selector(renameObject), keyEquivalent: "")
                renameItem.target = self
                renameItem.representedObject = object.id
                menu.addItem(renameItem)
                
                let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteObject), keyEquivalent: "")
                deleteItem.target = self
                deleteItem.representedObject = object.id
                menu.addItem(deleteItem)
                
            } else {
                // Empty space menu
                menu.addItem(NSMenuItem(title: "Add LED Wall", action: #selector(addLEDWall), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Add Camera", action: #selector(addCamera), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Add Set Piece", action: #selector(addSetPiece), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Add Light", action: #selector(addLight), keyEquivalent: ""))
            }
            
            menu.popUp(positioning: nil, at: point, in: scnView)
        }
        
        // MARK: - Context Menu Actions
        
        @objc private func selectObject(_ sender: NSMenuItem) {
            guard let objId = sender.representedObject as? UUID else { return }
            Task { @MainActor in
                selectedObjects = [objId]
            }
        }
        
        @objc private func duplicateObject(_ sender: NSMenuItem) {
            guard let objId = sender.representedObject as? UUID else { return }
            
            Task { @MainActor in
                guard let object = parent.studioManager.studioObjects.first(where: { $0.id == objId }) else { return }
                
                let newPosition = SCNVector3(
                    object.position.x + 1,
                    object.position.y,
                    object.position.z + 1
                )
                
                let duplicate = StudioObject(name: "\(object.name).001", type: object.type, position: newPosition)
                duplicate.rotation = object.rotation
                duplicate.scale = object.scale
                
                if let geometry = object.node.geometry?.copy() as? SCNGeometry {
                    duplicate.node.geometry = geometry
                }
                
                parent.studioManager.studioObjects.append(duplicate)
                parent.studioManager.scene.rootNode.addChildNode(duplicate.node)
                
                // Select the duplicate
                selectedObjects = [duplicate.id]
            }
        }
        
        @objc private func renameObject(_ sender: NSMenuItem) {
            guard let objId = sender.representedObject as? UUID else { return }
            
            Task { @MainActor in
                guard let object = parent.studioManager.studioObjects.first(where: { $0.id == objId }) else { return }
                
                // Show rename dialog
                let alert = NSAlert()
                alert.messageText = "Rename Object"
                alert.informativeText = "Enter new name:"
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")
                
                let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                textField.stringValue = object.name
                alert.accessoryView = textField
                
                if alert.runModal() == .alertFirstButtonReturn {
                    let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !newName.isEmpty {
                        object.name = newName
                        object.node.name = newName
                    }
                }
            }
        }
        
        @objc private func deleteObject(_ sender: NSMenuItem) {
            guard let objId = sender.representedObject as? UUID else { return }
            
            Task { @MainActor in
                guard let object = parent.studioManager.studioObjects.first(where: { $0.id == objId }) else { return }
                
                parent.studioManager.deleteObject(object)
                selectedObjects.remove(objId)
            }
        }
        
        @objc private func addLEDWall() { /* Implement */ }
        @objc private func addCamera() { /* Implement */ }
        @objc private func addSetPiece() { /* Implement */ }
        @objc private func addLight() { /* Implement */ }
        
        // MARK: - Utilities
        
        func convertScreenToWorld(point: CGPoint, in scnView: SCNView) -> SCNVector3 {
            // Convert screen point to world coordinates using ray casting
            let nearPoint = scnView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
            let farPoint = scnView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
            
            // Create ray from near to far
            let direction = SCNVector3(
                farPoint.x - nearPoint.x,
                farPoint.y - nearPoint.y,
                farPoint.z - nearPoint.z
            )
            
            // Intersect with ground plane (Y = 0)
            let t = -nearPoint.y / direction.y
            let intersectionPoint = SCNVector3(
                nearPoint.x + direction.x * t,
                0, // Place on ground
                nearPoint.z + direction.z * t
            )
            
            return intersectionPoint
        }
        
        private func snapToGridPosition(_ position: SCNVector3) -> SCNVector3 {
            let gridStep = CGFloat(gridSize)
            return SCNVector3(
                round(position.x / gridStep) * gridStep,
                position.y,
                round(position.z / gridStep) * gridStep
            )
        }
        
        private func findSCNView() -> SCNView? {
            return nil
        }
    }
}

#else
// iOS placeholder
struct Enhanced3DViewport: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView { SCNView() }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
#endif