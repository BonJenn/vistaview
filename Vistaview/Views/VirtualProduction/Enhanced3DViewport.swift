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
    
    func makeNSView(context: Context) -> DragDropSCNView {
        let scnView = DragDropSCNView()
        scnView.scene = studioManager.scene
        scnView.backgroundColor = NSColor.black
        scnView.allowsCameraControl = false  // Disable built-in controls for custom Blender-style controls
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics = false
        scnView.delegate = context.coordinator
        
        // Set up drag & drop directly on SCNView
        scnView.registerForDraggedTypes([.string])
        scnView.coordinator = context.coordinator
        
        // Set up camera controls first
        context.coordinator.setupCamera(in: scnView)
        
        // Add gesture recognizers for camera control
        let leftPanGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLeftPan(_:)))
        leftPanGesture.buttonMask = 1 // Left mouse button
        scnView.addGestureRecognizer(leftPanGesture)
        
        let middlePanGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMiddlePan(_:)))
        middlePanGesture.buttonMask = 4 // Middle mouse button
        scnView.addGestureRecognizer(middlePanGesture)
        
        let magnifyGesture = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnify(_:)))
        scnView.addGestureRecognizer(magnifyGesture)
        
        // Click gestures for selection/placement
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(clickGesture)
        
        let rightClickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRightClick(_:)))
        rightClickGesture.buttonMask = 2
        scnView.addGestureRecognizer(rightClickGesture)
        
        setupDefaultCamera(scnView)
        return scnView
    }
    
    func updateNSView(_ nsView: DragDropSCNView, context: Context) {
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
        // Remove any existing camera to avoid conflicts
        studioManager.scene.rootNode.childNode(withName: "enhanced_viewport_camera", recursively: true)?.removeFromParentNode()
        
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.zNear = 0.1
        camera.zFar = 1000
        cameraNode.camera = camera
        cameraNode.name = "enhanced_viewport_camera"
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
        
        // Track mouse movement without button press for Blender-style shift+drag
        private var lastMouseLocation: CGPoint = .zero
        private var isTrackingShiftDrag = false
        
        override var acceptsFirstResponder: Bool {
            return true
        }
        
        override func becomeFirstResponder() -> Bool {
            return true
        }
        
        override func awakeFromNib() {
            super.awakeFromNib()
            self.wantsLayer = true
        }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            registerForDraggedTypes([.string])
            setupTrackingArea()
        }
        
        private func setupTrackingArea() {
            // Remove existing tracking areas
            trackingAreas.forEach { removeTrackingArea($0) }
            
            // Add new tracking area for the entire view
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
        }
        
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            setupTrackingArea()
        }
        
        override func mouseMoved(with event: NSEvent) {
            let currentLocation = convert(event.locationInWindow, from: nil)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            
            print("🖱️ [Enhanced] MOUSE MOVED: shift=\(isShiftPressed), location=\(currentLocation)")
            
            // Check if we should start or continue shift+drag panning
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    // Start tracking
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print("🎯 [Enhanced] STARTED Shift+Mouse tracking")
                } else {
                    // Continue tracking - calculate delta and pan
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    if abs(deltaX) > 0.5 || abs(deltaY) > 0.5 { // Only pan if there's meaningful movement
                        print("🎯 [Enhanced] SHIFT + MOUSE MOVE: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                        coordinator?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    }
                    
                    lastMouseLocation = currentLocation
                }
            } else {
                // Stop tracking if shift is released
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print("🎯 [Enhanced] STOPPED Shift+Mouse tracking")
                }
            }
            
            super.mouseMoved(with: event)
        }
        
        override func mouseDragged(with event: NSEvent) {
            let currentLocation = convert(event.locationInWindow, from: nil)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            
            print("🖱️ [Enhanced] MOUSE DRAGGED: shift=\(isShiftPressed), location=\(currentLocation)")
            
            // If shift is pressed during drag, override normal drag behavior with panning
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print("🎯 [Enhanced] STARTED Shift+Drag tracking")
                } else {
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    print("🎯 [Enhanced] SHIFT + DRAG: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                    coordinator?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    
                    lastMouseLocation = currentLocation
                }
                return // Don't pass to super - we're handling this drag ourselves
            } else {
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print("🎯 [Enhanced] STOPPED Shift+Drag tracking")
                }
            }
            
            super.mouseDragged(with: event)
        }
        
        override func rightMouseDragged(with event: NSEvent) {
            let currentLocation = convert(event.locationInWindow, from: nil)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            
            print("🖱️ [Enhanced] RIGHT MOUSE DRAGGED: shift=\(isShiftPressed)")
            
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print("🎯 [Enhanced] STARTED Shift+Right Drag tracking")
                } else {
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    print("🎯 [Enhanced] SHIFT + RIGHT DRAG: Activating pan")
                    coordinator?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    
                    lastMouseLocation = currentLocation
                }
                return
            } else {
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print("🎯 [Enhanced] STOPPED Shift+Right Drag tracking")
                }
            }
            
            super.rightMouseDragged(with: event)
        }
        
        override func otherMouseDragged(with event: NSEvent) {
            let currentLocation = convert(event.locationInWindow, from: nil)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            
            print("🖱️ [Enhanced] OTHER MOUSE DRAGGED: shift=\(isShiftPressed), button=\(event.buttonNumber)")
            
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print("🎯 [Enhanced] STARTED Shift+Middle Drag tracking")
                } else {
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    print("🎯 [Enhanced] SHIFT + MIDDLE DRAG: Activating pan")
                    coordinator?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    
                    lastMouseLocation = currentLocation
                }
                return
            } else {
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print("🎯 [Enhanced] STOPPED Shift+Middle Drag tracking")
                }
            }
            
            super.otherMouseDragged(with: event)
        }
        
        override func mouseExited(with event: NSEvent) {
            // Reset tracking when mouse leaves view
            isTrackingShiftDrag = false
            super.mouseExited(with: event)
        }
        
        override func scrollWheel(with event: NSEvent) {
            // Handle scroll wheel for zooming
            if let coordinator = coordinator {
                let scrollDelta = Float(event.scrollingDeltaY)
                if abs(scrollDelta) > 0.1 {
                    // Zoom based on scroll direction
                    let zoomFactor: Float = scrollDelta > 0 ? 1.1 : 0.9
                    let newDistance = coordinator.cameraDistance * zoomFactor
                    coordinator.cameraDistance = max(1.0, min(100.0, newDistance))
                    coordinator.updateCameraPositionPublic()
                }
            } else {
                super.scrollWheel(with: event)
            }
        }
        
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
        
        // Camera control properties
        var cameraNode: SCNNode!
        var cameraDistance: Float = 15.0
        var cameraAzimuth: Float = 0.0      // Y-axis rotation (horizontal)
        var cameraElevation: Float = 0.3    // X-axis rotation (vertical)
        var cameraRoll: Float = 0.0         // Z-axis rotation
        var focusPoint = SCNVector3(0, 1, 0)
        
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
        
        // MARK: - Camera Control Methods
        
        func setupCamera(in scnView: SCNView) {
            let camera = SCNCamera()
            camera.fieldOfView = 60
            camera.zNear = 0.1
            camera.zFar = 1000
            camera.automaticallyAdjustsZRange = true
            
            cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.name = "enhanced_viewport_camera"
            
            parent.studioManager.scene.rootNode.addChildNode(cameraNode)
            scnView.pointOfView = cameraNode
            
            updateCameraPosition()
        }
        
        @objc func handleLeftPan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            
            let translation = gesture.translation(in: view)
            let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
            
            print("🖱️ [Enhanced] LEFT PAN: shift=\(isShiftPressed), translation=\(translation)")
            
            if isShiftPressed {
                // Shift + Left Mouse = Blender-style pan
                print("🎯 [Enhanced] SHIFT + LEFT MOUSE: Activating Blender-style pan")
                handleBlenderStylePan(deltaX: Float(translation.x), deltaY: Float(translation.y))
                gesture.setTranslation(.zero, in: view)
            } else {
                // Normal Left Mouse = Orbit
                print("🌀 [Enhanced] NORMAL LEFT MOUSE: Activating orbit")
                let sensitivity: Float = 0.005
                let deltaAzimuth = Float(translation.x) * sensitivity
                let deltaElevation = -Float(translation.y) * sensitivity
                
                cameraAzimuth += deltaAzimuth
                cameraElevation += deltaElevation
                
                // Clamp elevation
                let maxElevation: Float = Float.pi / 2 - 0.1
                cameraElevation = max(-maxElevation, min(maxElevation, cameraElevation))
                
                updateCameraPosition()
                gesture.setTranslation(.zero, in: view)
            }
        }
        
        @objc func handleMiddlePan(_ gesture: NSPanGestureRecognizer) {
            guard gesture.view is SCNView else { return }
            
            let translation = gesture.translation(in: gesture.view!)
            let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
            
            print("🖱️ [Enhanced] MIDDLE PAN: shift=\(isShiftPressed), translation=\(translation)")
            
            if isShiftPressed {
                // Shift + Middle Mouse Button = Blender-style pan (exactly like Blender!)
                print("🎯 [Enhanced] SHIFT + MIDDLE MOUSE: Activating Blender-style pan")
            } else {
                print("🖱️ [Enhanced] PLAIN MIDDLE MOUSE: Activating pan")
            }
            
            // Both Shift+MMB and plain MMB do Blender-style panning
            handleBlenderStylePan(deltaX: Float(translation.x), deltaY: Float(translation.y))
            gesture.setTranslation(.zero, in: gesture.view!)
        }
        
        @objc func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
            let zoomFactor = 1.0 + gesture.magnification
            let newDistance = cameraDistance / Float(zoomFactor)
            
            cameraDistance = max(1.0, min(100.0, newDistance))
            updateCameraPosition()
            gesture.magnification = 0
        }
        
        private func handleBlenderStylePan(deltaX: Float, deltaY: Float) {
            // Calculate screen-space pan vectors from the camera's perspective
            // This creates the exact same behavior as Blender's Shift + MMB pan
            
            let cameraTransform = cameraNode.worldTransform
            
            // Extract right vector (local X axis) - ensure CGFloat compatibility for macOS
            let rightX = CGFloat(cameraTransform.m11)
            let rightY = CGFloat(cameraTransform.m12)
            let rightZ = CGFloat(cameraTransform.m13)
            
            // Extract up vector (local Y axis) - ensure CGFloat compatibility for macOS
            let upX = CGFloat(cameraTransform.m21)
            let upY = CGFloat(cameraTransform.m22)
            let upZ = CGFloat(cameraTransform.m23)
            
            // Scale pan speed based on camera distance (closer = slower pan, farther = faster pan)
            // This matches Blender's behavior exactly
            let panScale = CGFloat(cameraDistance * 0.002)
            let panXAmount = CGFloat(deltaX) * panScale
            let panYAmount = CGFloat(deltaY) * panScale
            
            // Move the focus point in screen space
            // X movement = right/left in camera space
            // Y movement = up/down in camera space
            let deltaFocusX = -(rightX * panXAmount - upX * panYAmount)
            let deltaFocusY = -(rightY * panXAmount - upY * panYAmount)
            let deltaFocusZ = -(rightZ * panXAmount - upZ * panYAmount)
            
            focusPoint = SCNVector3(
                focusPoint.x + deltaFocusX,
                focusPoint.y + deltaFocusY,
                focusPoint.z + deltaFocusZ
            )
            
            // Update camera position to maintain the same relative position to the new focus point
            updateCameraPosition()
            
            print("🎯 Enhanced viewport Blender-style pan: focus point now at \(focusPoint)")
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
            
            // Look at the focus point
            cameraNode.look(at: focusPoint, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            
            // Apply roll rotation if needed
            if abs(cameraRoll) > 0.001 {
                let currentTransform = cameraNode.worldTransform
                let rollTransform = SCNMatrix4MakeRotation(CGFloat(cameraRoll), 0, 0, 1)
                cameraNode.transform = SCNMatrix4Mult(currentTransform, rollTransform)
            }
        }
        
        // Add public wrapper for the private method
        func updateCameraPositionPublic() {
            updateCameraPosition()
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
                case .ledWall, .camera, .setPiece, .light, .staging:
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
            case .staging: studioTool = .staging
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
        
        // Add direct pan method
        func handleBlenderStylePanDirect(deltaX: Float, deltaY: Float) {
            // Debug logging
            print("🎯 [Enhanced] EXECUTING Direct Blender-style pan: deltaX=\(deltaX), deltaY=\(deltaY)")
            
            // Calculate screen-space pan vectors from the camera's perspective
            let cameraTransform = cameraNode.worldTransform
            
            // Extract right vector (local X axis) - ensure CGFloat compatibility for macOS
            let rightX = CGFloat(cameraTransform.m11)
            let rightY = CGFloat(cameraTransform.m12)
            let rightZ = CGFloat(cameraTransform.m13)
            
            // Extract up vector (local Y axis) - ensure CGFloat compatibility for macOS
            let upX = CGFloat(cameraTransform.m21)
            let upY = CGFloat(cameraTransform.m22)
            let upZ = CGFloat(cameraTransform.m23)
            
            // Scale pan speed based on camera distance (closer = slower pan, farther = faster pan)
            // This matches Blender's behavior exactly
            let panScale = CGFloat(cameraDistance * 0.002)
            let panXAmount = CGFloat(deltaX) * panScale
            let panYAmount = CGFloat(deltaY) * panScale
            
            // Move the focus point in screen space
            // X movement = right/left in camera space
            // Y movement = up/down in camera space
            let deltaFocusX = -(rightX * panXAmount - upX * panYAmount)
            let deltaFocusY = -(rightY * panXAmount - upY * panYAmount)
            let deltaFocusZ = -(rightZ * panXAmount - upZ * panYAmount)
            
            let oldFocusPoint = focusPoint
            focusPoint = SCNVector3(
                focusPoint.x + deltaFocusX,
                focusPoint.y + deltaFocusY,
                focusPoint.z + deltaFocusZ
            )
            
            // Update camera position to maintain the same relative position to the new focus point
            updateCameraPosition()
            
            print("🎯 [Enhanced] Direct Blender-style pan complete: \(oldFocusPoint) -> \(focusPoint)")
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