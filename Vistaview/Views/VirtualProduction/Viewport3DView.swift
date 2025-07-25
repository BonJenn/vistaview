//
//  Viewport3DView.swift
//  Vistaview
//

import SwiftUI
import SceneKit

#if os(macOS)
struct Viewport3DView: NSViewRepresentable {
    let studioManager: VirtualStudioManager
    @Binding var selectedTool: StudioTool
    @Binding var transformMode: TransformController.TransformMode
    @Binding var viewMode: ViewportViewMode
    @Binding var selectedObjects: Set<UUID>
    @Binding var snapToGrid: Bool
    @Binding var gridSize: Float
    @ObservedObject var transformController: TransformController  // Add this parameter
    
    // Add missing enum
    enum ViewportViewMode {
        case wireframe, solid, material
    }
    
    func makeNSView(context: Context) -> CustomSCNView {
        let scnView = CustomSCNView()
        scnView.scene = studioManager.scene
        scnView.backgroundColor = NSColor.black
        
        // Disable built-in camera controls so we can implement Y-axis rotation
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics = false
        
        // Enable first responder to receive scroll events
        scnView.wantsLayer = true
        DispatchQueue.main.async {
            _ = scnView.becomeFirstResponder()
        }
        
        // Setup camera controller
        context.coordinator.setupCamera(in: scnView)
        context.coordinator.setupGestures(for: scnView)
        
        // Set the coordinator as the custom view's gesture handler
        scnView.gestureHandler = context.coordinator
        
        // Enable drag and drop
        scnView.registerForDraggedTypes([.string])
        
        return scnView
    }
    
    func updateNSView(_ nsView: CustomSCNView, context: Context) {
        // Keep camera controls disabled since we're handling it ourselves
        nsView.allowsCameraControl = false
        
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
    
    @MainActor
    final class Coordinator: NSObject, NSDraggingDestination, NSGestureRecognizerDelegate {
        let parent: Viewport3DView
        var selectedTool: StudioTool = .select
        var transformMode: TransformController.TransformMode = .move
        var selectedObjects: Set<UUID> = []
        var snapToGrid: Bool = true
        var gridSize: Float = 1.0
        
        // Camera control properties
        private var cameraNode: SCNNode!
        private var cameraDistance: Float = 15.0
        private var cameraAzimuth: Float = 0.0      // Y-axis rotation (horizontal)
        private var cameraElevation: Float = 0.3    // X-axis rotation (vertical)
        private var focusPoint = SCNVector3(0, 1, 0)
        
        init(_ parent: Viewport3DView) {
            self.parent = parent
        }
        
        func setupCamera(in scnView: SCNView) {
            // Remove any existing camera
            parent.studioManager.scene.rootNode.childNode(withName: "viewport_camera", recursively: true)?.removeFromParentNode()
            
            let camera = SCNCamera()
            camera.fieldOfView = 60
            camera.zNear = 0.1
            camera.zFar = 1000
            camera.automaticallyAdjustsZRange = true
            
            cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.name = "viewport_camera"
            
            parent.studioManager.scene.rootNode.addChildNode(cameraNode)
            scnView.pointOfView = cameraNode
            
            updateCameraPosition()
        }
        
        func setupGestures(for view: SCNView) {
            // Magnify gesture for zooming
            let magnifyGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
            magnifyGesture.delegate = self
            view.addGestureRecognizer(magnifyGesture)
            
            // Click gesture for selection
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            clickGesture.delegate = self
            view.addGestureRecognizer(clickGesture)
            
            // Right-click for context menu
            let rightClickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
            rightClickGesture.buttonMask = 2
            rightClickGesture.delegate = self
            view.addGestureRecognizer(rightClickGesture)
            
            // Use pan gesture with specific configuration for trackpad
            let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            panGesture.delegate = self
            panGesture.buttonMask = 0 // Accept all buttons/touches
            view.addGestureRecognizer(panGesture)
            
            // Try rotation gesture for trackpad rotate
            let rotationGesture = NSRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            rotationGesture.delegate = self
            view.addGestureRecognizer(rotationGesture)
        }
        
        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
            return true
        }
        
        // Handle trackpad scroll for orbiting
        func handleTrackpadScroll(deltaX: Float, deltaY: Float) {
            let sensitivity: Float = 0.01
            let deltaAzimuth = deltaX * sensitivity     // Horizontal = Y-axis rotation
            let deltaElevation = deltaY * sensitivity   // Vertical = X-axis rotation
            
            cameraAzimuth += deltaAzimuth
            cameraElevation += deltaElevation
            
            // Clamp elevation to prevent flipping
            let maxElevation: Float = Float.pi / 2 - 0.1
            cameraElevation = max(-maxElevation, min(maxElevation, cameraElevation))
            
            updateCameraPosition()
        }
        
        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)
            let currentPoint = gesture.location(in: view)
            
            // Check if we're in transform mode first
            if parent.transformController.isActive {
                // Update transform with mouse movement
                parent.transformController.updateTransformWithMouse(mousePos: currentPoint)
                gesture.setTranslation(.zero, in: view)
                return
            }
            
            // Check if this is likely a trackpad scroll gesture (high velocity, smooth movement)
            if abs(velocity.x) > 50 || abs(velocity.y) > 50 {
                // This looks like a scroll gesture - use for orbiting
                let sensitivity: Float = 0.005
                let deltaAzimuth = Float(translation.x) * sensitivity     // Horizontal = Y-axis rotation
                let deltaElevation = -Float(translation.y) * sensitivity  // Vertical = X-axis rotation
                
                cameraAzimuth += deltaAzimuth
                cameraElevation += deltaElevation
                
                // Clamp elevation
                let maxElevation: Float = Float.pi / 2 - 0.1
                cameraElevation = max(-maxElevation, min(maxElevation, cameraElevation))
                
                updateCameraPosition()
                gesture.setTranslation(.zero, in: view)
            } else if NSEvent.modifierFlags.contains(.shift) {
                // Slow movement with Shift = pan focus point
                handleCameraPan(deltaX: Float(translation.x), deltaY: Float(translation.y))
                gesture.setTranslation(.zero, in: view)
            }
        }
        
        @objc func handleRotation(_ gesture: NSRotationGestureRecognizer) {
            // Handle trackpad rotation gesture
            let rotationSensitivity: Float = 1.0
            let deltaRotation = Float(gesture.rotation) * rotationSensitivity
            
            cameraAzimuth += deltaRotation
            updateCameraPosition()
            gesture.rotation = 0
        }
        
        @objc func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
            let zoomFactor = 1.0 + gesture.magnification
            let newDistance = cameraDistance / Float(zoomFactor)
            
            cameraDistance = max(1.0, min(100.0, newDistance))
            updateCameraPosition()
            gesture.magnification = 0
        }
        
        private func handleCameraPan(deltaX: Float, deltaY: Float) {
            // Calculate right and up vectors from camera transform
            let cameraTransform = cameraNode.worldTransform
            let rightVector = SCNVector3(cameraTransform.m11, cameraTransform.m12, cameraTransform.m13)
            let upVector = SCNVector3(cameraTransform.m21, cameraTransform.m22, cameraTransform.m23)
            
            let panScale = cameraDistance * 0.001
            let panX = deltaX * panScale
            let panY = deltaY * panScale
            
            // Break up the complex expression with proper type conversion
            let rightMovement = SCNVector3(
                -Float(rightVector.x) * panX,
                -Float(rightVector.y) * panX,
                -Float(rightVector.z) * panX
            )
            let upMovement = SCNVector3(
                -Float(upVector.x) * panY,
                -Float(upVector.y) * panY,
                -Float(upVector.z) * panY
            )
            
            focusPoint = SCNVector3(
                focusPoint.x + CGFloat(rightMovement.x + upMovement.x),
                focusPoint.y + CGFloat(rightMovement.y + upMovement.y),
                focusPoint.z + CGFloat(rightMovement.z + upMovement.z)
            )
            
            updateCameraPosition()
        }
        
        private func updateCameraPosition() {
            // Spherical to Cartesian conversion
            // Azimuth rotates around Y-axis (horizontal movement)
            // Elevation rotates around X-axis (vertical movement)
            let x = cameraDistance * cos(cameraElevation) * sin(cameraAzimuth)
            let y = cameraDistance * sin(cameraElevation)
            let z = cameraDistance * cos(cameraElevation) * cos(cameraAzimuth)
            
            cameraNode.position = SCNVector3(
                focusPoint.x + CGFloat(x),
                focusPoint.y + CGFloat(y),
                focusPoint.z + CGFloat(z)
            )
            
            cameraNode.look(at: focusPoint, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
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
            
            // Use StudioTool directly - no conversion needed
            parent.studioManager.addObject(type: selectedTool, at: finalPos)
        }
        
        private func snapToGridPosition(_ position: SCNVector3) -> SCNVector3 {
            let gridStep = Float(gridSize)
            return SCNVector3(
                Float(round(position.x / CGFloat(gridStep)) * CGFloat(gridStep)),
                Float(position.y), // Don't snap Y to allow vertical positioning
                Float(round(position.z / CGFloat(gridStep)) * CGFloat(gridStep))
            )
        }
    }
    
    // Custom SCNView that handles trackpad scroll events
    class CustomSCNView: SCNView {
        weak var gestureHandler: Coordinator?
        
        override var acceptsFirstResponder: Bool {
            return true
        }
        
        override func becomeFirstResponder() -> Bool {
            return true
        }
        
        override func awakeFromNib() {
            super.awakeFromNib()
            // Ensure we can receive scroll events
            self.wantsLayer = true
        }
        
        override func scrollWheel(with event: NSEvent) {
            // Always handle trackpad gestures, regardless of phase
            let deltaX = Float(event.scrollingDeltaX)
            let deltaY = Float(event.scrollingDeltaY)
            
            // Check if there's actual movement
            if abs(deltaX) > 0.1 || abs(deltaY) > 0.1 {
                gestureHandler?.handleTrackpadScroll(deltaX: deltaX, deltaY: deltaY)
            } else {
                // Pass through if no movement  
                super.scrollWheel(with: event)
            }
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