//
//  Enhanced3DViewport.swift  
//  Vistaview - Functional 3D Viewport with Integrated Drag & Drop
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
        let scnView = DragDropSCNView()
        scnView.scene = studioManager.scene
        scnView.backgroundColor = NSColor.black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics = false
        scnView.delegate = context.coordinator
        
        // Set up drag & drop directly on SCNView
        scnView.registerForDraggedTypes([.string])
        scnView.coordinator = context.coordinator
        
        // Add gesture recognizers
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(clickGesture)
        
        let rightClickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRightClick(_:)))
        rightClickGesture.buttonMask = 2
        scnView.addGestureRecognizer(rightClickGesture)
        
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
        
        // Handle transform mode changes - START TRANSFORM MODE HERE  
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
    
    // MARK: - Custom SCNView with Drag & Drop
    
    class DragDropSCNView: SCNView {
        weak var coordinator: Enhanced3DViewport.Coordinator?
        
        // MARK: - NSDraggingDestination
        
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            // Disable camera control during drag
            allowsCameraControl = false
            
            // Visual feedback
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.systemBlue.cgColor
            
            NotificationCenter.default.post(name: .dragEntered, object: nil)
            return .copy
        }
        
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            let location = sender.draggingLocation
            NotificationCenter.default.post(name: .dragUpdated, object: location)
            return .copy
        }
        
        override func draggingExited(_ sender: NSDraggingInfo?) {
            // Re-enable camera control
            allowsCameraControl = true
            
            // Remove visual feedback
            layer?.borderWidth = 0
            
            NotificationCenter.default.post(name: .dragExited, object: nil)
        }
        
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            // Re-enable camera control
            allowsCameraControl = true
            
            // Remove visual feedback
            layer?.borderWidth = 0
            
            // Get drag data
            guard let data = sender.draggingPasteboard.data(forType: .string),
                  let setPieceID = String(data: data, encoding: .utf8),
                  let coordinator = coordinator else {
                print("❌ Drop failed: Missing data or coordinator")
                return false
            }
            
            // Find the set piece
            guard let setPiece = SetPieceAsset.predefinedPieces.first(where: { $0.id.uuidString == setPieceID }) else {
                print("❌ Drop failed: SetPiece not found for ID: \(setPieceID)")
                return false
            }
            
            // Get drop location and convert to world coordinates
            let dropLocation = sender.draggingLocation
            
            Task { @MainActor in
                let worldPosition = coordinator.convertScreenToWorld(point: dropLocation, in: self)
                
                // Apply grid snapping if enabled
                var finalPosition = worldPosition
                if coordinator.snapToGrid {
                    let gridStep = CGFloat(coordinator.gridSize)
                    finalPosition = SCNVector3(
                        round(worldPosition.x / gridStep) * gridStep,
                        worldPosition.y,
                        round(worldPosition.z / gridStep) * gridStep
                    )
                }
                
                print("✅ Dropping \(setPiece.name) at \(finalPosition)")
                
                // Add to scene
                coordinator.parent.studioManager.addSetPieceFromAsset(setPiece, at: finalPosition)
            }
            
            return true
        }
        
        // MARK: - Key Event Handling for Transform Mode
        
        override var acceptsFirstResponder: Bool {
            return true
        }
        
        override func keyDown(with event: NSEvent) {
            guard let coordinator = coordinator else {
                super.keyDown(with: event)
                return
            }
            
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            
            // Handle transform keys
            switch key {
            case "g":
                coordinator.enterTransformMode(.move)
                return
            case "r":
                coordinator.enterTransformMode(.rotate)  
                return
            case "s":
                coordinator.enterTransformMode(.scale)
                return
            case "x":
                if coordinator.isTransforming {
                    coordinator.setTransformAxis(.x)
                    return
                }
            case "y":
                if coordinator.isTransforming {
                    coordinator.setTransformAxis(.y)
                    return
                }
            case "z":
                if coordinator.isTransforming {
                    coordinator.setTransformAxis(.z)
                    return
                }
            case "\r": // Enter key
                if coordinator.isTransforming {
                    coordinator.confirmTransform()
                    return
                }
            case "\u{1b}": // Escape key
                if coordinator.isTransforming {
                    coordinator.cancelTransform()
                    return
                }
            default:
                break
            }
            
            super.keyDown(with: event)
        }
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
        var originalRotations: [UUID: SCNVector3] = [:]
        var originalScales: [UUID: SCNVector3] = [:]
        var transformStartPoint: CGPoint = .zero
        
        init(_ parent: Enhanced3DViewport) {
            self.parent = parent
            super.init()
        }
        
        // MARK: - Transform Mode Methods
        
        func enterTransformMode(_ mode: TransformMode) {
            guard !selectedObjects.isEmpty else {
                print("⚠️ No objects selected for transform")
                return
            }
            
            print("🔧 Entering transform mode: \(mode)")
            
            isTransforming = true 
            transformAxis = .free
            
            // Store original values
            originalPositions.removeAll()
            originalRotations.removeAll()
            originalScales.removeAll()
            
            Task { @MainActor in
                for objId in selectedObjects {
                    if let obj = parent.studioManager.studioObjects.first(where: { $0.id == objId }) {
                        originalPositions[objId] = obj.position
                        originalRotations[objId] = obj.rotation
                        originalScales[objId] = obj.scale
                    }
                }
                
                // Update transform mode in parent
                parent.transformMode = mode
                
                NotificationCenter.default.post(name: .transformStarted, object: mode)
            }
        }
        
        func setTransformAxis(_ axis: TransformAxis) {
            guard isTransforming else { return }
            transformAxis = axis
            print("🎯 Transform axis set to: \(axis)")
        }
        
        func confirmTransform() {
            print("✅ Transform confirmed")
            isTransforming = false
            transformAxis = .free
            clearStoredValues()
            NotificationCenter.default.post(name: .transformEnded, object: nil)
        }
        
        func cancelTransform() {
            print("❌ Transform cancelled")
            
            // Restore original values
            Task { @MainActor in
                for (objId, originalPos) in originalPositions {
                    if let obj = parent.studioManager.studioObjects.first(where: { $0.id == objId }) {
                        obj.position = originalPos
                        if let originalRot = originalRotations[objId] {
                            obj.rotation = originalRot
                        }
                        if let originalScale = originalScales[objId] {
                            obj.scale = originalScale
                        }
                        obj.updateNodeTransform()
                    }
                }
            }
            
            isTransforming = false
            transformAxis = .free
            clearStoredValues()
            NotificationCenter.default.post(name: .transformEnded, object: nil)
        }
        
        func startTransformMode() {
            // This is called from updateNSView - don't auto-enter transform mode
            // Transform mode should only be entered via key presses
        }
        
        private func clearStoredValues() {
            originalPositions.removeAll()
            originalRotations.removeAll()
            originalScales.removeAll()
        }
        
        // MARK: - Mouse Events
        
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)
            
            Task { @MainActor in
                if isTransforming {
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
        
        // MARK: - Coordinate Conversion
        
        func convertScreenToWorld(point: CGPoint, in scnView: SCNView) -> SCNVector3 {
            let nearPoint = scnView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
            let farPoint = scnView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
            
            let direction = SCNVector3(
                farPoint.x - nearPoint.x,
                farPoint.y - nearPoint.y,
                farPoint.z - nearPoint.z
            )
            
            // Intersect with ground plane (Y = 0)
            let t = -nearPoint.y / direction.y
            let intersectionPoint = SCNVector3(
                nearPoint.x + direction.x * t,
                0,
                nearPoint.z + direction.z * t
            )
            
            return intersectionPoint
        }
        
        // MARK: - Selection & Context Menu (simplified)
        
        @MainActor
        private func handleSelection(at point: CGPoint, in scnView: SCNView) {
            let hitResults = scnView.hitTest(point, options: nil)
            
            if let hitResult = hitResults.first {
                let hitNode = hitResult.node
                if let object = parent.studioManager.getObject(from: hitNode) {
                    if selectedObjects.contains(object.id) {
                        selectedObjects.remove(object.id)
                    } else {
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
            let studioTool: StudioTool
            switch selectedTool {
            case .select: studioTool = .select
            case .ledWall: studioTool = .ledWall
            case .camera: studioTool = .camera
            case .setPiece: studioTool = .setPiece
            case .light: studioTool = .light
            }
            parent.studioManager.addObject(type: studioTool, at: worldPos)
        }
        
        @MainActor
        private func showContextMenu(at point: CGPoint, in scnView: SCNView) {
            // Simplified context menu
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Add Set Piece", action: nil, keyEquivalent: ""))
            menu.popUp(positioning: nil, at: point, in: scnView)
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