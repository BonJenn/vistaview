//
//  Viewport3DView.swift
//  Vistaview
//

import SwiftUI
import SceneKit
import AppKit

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
    
    // Camera orientation bindings for compass
    @Binding var cameraAzimuth: Float
    @Binding var cameraElevation: Float
    @Binding var cameraRoll: Float
    
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
        
        // IMPORTANT: Set the coordinator as the drag destination
        context.coordinator.currentSCNView = scnView
        
        // Enable drag and drop - do this AFTER setting up the coordinator
        scnView.registerForDraggedTypes([.string])
        print("🎯 Viewport3DView registered SCNView for drag types")
        
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
        
        // Update camera orientation bindings
        let (azimuth, elevation, roll) = context.coordinator.getCameraOrientation()
        if cameraAzimuth != azimuth {
            cameraAzimuth = azimuth
        }
        if cameraElevation != elevation {
            cameraElevation = elevation
        }
        if cameraRoll != roll {
            cameraRoll = roll
        }
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
        
        // Store reference to current SCNView for drag operations
        weak var currentSCNView: SCNView?
        
        // Store context menu point for actions
        private var currentContextMenuPoint: CGPoint = .zero
        private var currentContextMenuObject: StudioObject? // Add this to store the clicked object
        
        // Camera control properties
        private var cameraNode: SCNNode!
        private var cameraDistance: Float = 15.0
        private var cameraAzimuth: Float = 0.0      // Y-axis rotation (horizontal)
        private var cameraElevation: Float = 0.3    // X-axis rotation (vertical)
        private var focusPoint = SCNVector3(0, 1, 0)
        
        // Add new property for Z-axis rotation
        private var cameraRoll: Float = 0.0 // Z-axis rotation
        
        init(_ parent: Viewport3DView) {
            self.parent = parent
            super.init()
        }
        
        func setupCamera(in scnView: SCNView) {
            // Store the SCNView reference
            currentSCNView = scnView
            
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
            
            // Left Mouse Button pan gesture for orbiting
            let leftPanGesture = NSPanGestureRecognizer(target: self, action: #selector(handleLeftPan(_:)))
            leftPanGesture.delegate = self
            leftPanGesture.buttonMask = 1 // Left mouse button only
            view.addGestureRecognizer(leftPanGesture)
            
            // Middle Mouse Button pan gesture for Blender-style panning
            let middlePanGesture = NSPanGestureRecognizer(target: self, action: #selector(handleMiddlePan(_:)))
            middlePanGesture.delegate = self
            middlePanGesture.buttonMask = 4 // Middle mouse button
            view.addGestureRecognizer(middlePanGesture)
            
            // Use pan gesture with specific configuration for trackpad
            let trackpadPanGesture = NSPanGestureRecognizer(target: self, action: #selector(handleTrackpadPan(_:)))
            trackpadPanGesture.delegate = self
            trackpadPanGesture.buttonMask = 0 // Accept all buttons/touches for trackpad
            view.addGestureRecognizer(trackpadPanGesture)
            
            // Enhanced rotation gesture for trackpad rotate (Z-axis rotation)
            let rotationGesture = NSRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            rotationGesture.delegate = self
            view.addGestureRecognizer(rotationGesture)
        }
        
        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
            // Allow rotation gesture to work simultaneously with trackpad pan for proper multitouch
            if (gestureRecognizer is NSRotationGestureRecognizer && otherGestureRecognizer is NSPanGestureRecognizer) ||
               (gestureRecognizer is NSPanGestureRecognizer && otherGestureRecognizer is NSRotationGestureRecognizer) {
                return true
            }
            
            // Allow magnify to work with pan gestures for zoom + orbit/pan combinations
            if (gestureRecognizer is NSMagnificationGestureRecognizer && otherGestureRecognizer is NSPanGestureRecognizer) ||
               (gestureRecognizer is NSPanGestureRecognizer && otherGestureRecognizer is NSMagnificationGestureRecognizer) {
                return true
            }
            
            // Prevent conflicts between different pan gestures (left, middle, trackpad)
            if gestureRecognizer is NSPanGestureRecognizer && otherGestureRecognizer is NSPanGestureRecognizer {
                let leftPan = gestureRecognizer as? NSPanGestureRecognizer
                let rightPan = otherGestureRecognizer as? NSPanGestureRecognizer
                
                // Don't allow different mouse button pan gestures to conflict
                if leftPan?.buttonMask != rightPan?.buttonMask {
                    return false
                }
            }
            
            return true // Allow most gestures to work together for better multitouch support
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
        
        @objc func handleLeftPan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            
            let translation = gesture.translation(in: view)
            let currentPoint = gesture.location(in: view)
            
            // Debug logging
            let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
            print("🖱️ LEFT PAN: shift=\(isShiftPressed), translation=\(translation)")
            
            // PRIORITY 1: Check if we're in active transform mode
            if parent.transformController.isActive {
                // Use the transform controller's mouse update method
                parent.transformController.updateTransformWithMouse(mousePos: currentPoint)
                gesture.setTranslation(.zero, in: view)
                return
            }
            
            // PRIORITY 2: Check for Shift + Left Mouse Button = Blender-style pan
            if isShiftPressed {
                // Shift + Left Mouse = Pan (Blender style)
                print("🎯 SHIFT + LEFT MOUSE: Activating Blender-style pan")
                handleBlenderStylePan(deltaX: Float(translation.x), deltaY: Float(translation.y))
                gesture.setTranslation(.zero, in: view)
            } else {
                // Normal Left Mouse = Orbit
                print("🌀 NORMAL LEFT MOUSE: Activating orbit")
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
            }
        }
        
        @objc func handleMiddlePan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            
            let translation = gesture.translation(in: view)
            let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
            
            print("🖱️ MIDDLE PAN: shift=\(isShiftPressed), translation=\(translation)")
            
            if isShiftPressed {
                // Shift + Middle Mouse Button = Blender-style pan (exactly like Blender!)
                print("🎯 SHIFT + MIDDLE MOUSE: Activating Blender-style pan")
                handleBlenderStylePan(deltaX: Float(translation.x), deltaY: Float(translation.y))
                gesture.setTranslation(.zero, in: view)
            } else {
                // Plain middle mouse button could be used for other functions
                // For now, also do panning (some users prefer this)
                print("🖱️ PLAIN MIDDLE MOUSE: Activating pan")
                handleBlenderStylePan(deltaX: Float(translation.x), deltaY: Float(translation.y))
                gesture.setTranslation(.zero, in: view)
            }
        }
        
        @objc func handleTrackpadPan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)
            let currentPoint = gesture.location(in: view)
            
            // Debug logging for trackpad
            let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
            let isCommandPressed = NSEvent.modifierFlags.contains(.command)
            let isHighVelocityScroll = abs(velocity.x) > 50 || abs(velocity.y) > 50
            
            print("🖱️ TRACKPAD PAN: shift=\(isShiftPressed), cmd=\(isCommandPressed), highVel=\(isHighVelocityScroll), translation=\(translation)")
            
            // PRIORITY 1: Check if we're in active transform mode
            if parent.transformController.isActive {
                // Use the transform controller's mouse update method
                parent.transformController.updateTransformWithMouse(mousePos: currentPoint)
                gesture.setTranslation(.zero, in: view)
                return
            }
            
            // PRIORITY 2: Trackpad gestures (high velocity indicates scroll gestures)
            if isHighVelocityScroll || (!isShiftPressed && !isCommandPressed) {
                // This looks like a scroll gesture or normal orbit - use for orbiting
                print("🌀 TRACKPAD ORBIT")
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
            } else if isShiftPressed {
                // Shift + trackpad drag = Blender-style pan
                print("🎯 SHIFT + TRACKPAD: Activating Blender-style pan")
                handleBlenderStylePan(deltaX: Float(translation.x), deltaY: Float(translation.y))
                gesture.setTranslation(.zero, in: view)
            } else if isCommandPressed {
                // Command + drag = alternative orbit mode
                print("⌘ COMMAND + TRACKPAD: Alternative orbit")
                let sensitivity: Float = 0.01
                let deltaAzimuth = Float(translation.x) * sensitivity
                let deltaElevation = -Float(translation.y) * sensitivity
                
                cameraAzimuth += deltaAzimuth
                cameraElevation += deltaElevation
                
                let maxElevation: Float = Float.pi / 2 - 0.1
                cameraElevation = max(-maxElevation, min(maxElevation, cameraElevation))
                
                updateCameraPosition()
                gesture.setTranslation(.zero, in: view)
            }
        }
        
        @objc func handleRotation(_ gesture: NSRotationGestureRecognizer) {
            // Handle trackpad rotation gesture for Z-axis rotation (roll)
            let rotationSensitivity: Float = 0.5
            let deltaRotation = Float(gesture.rotation) * rotationSensitivity
            
            // Apply Z-axis rotation (roll)
            cameraRoll += deltaRotation
            
            // Keep roll within reasonable bounds
            if cameraRoll > Float.pi * 2 {
                cameraRoll -= Float.pi * 2
            } else if cameraRoll < -Float.pi * 2 {
                cameraRoll += Float.pi * 2
            }
            
            // Debug output for multitouch rotation
            if abs(deltaRotation) > 0.01 {
                print("🌀 Z-axis rotation: \(cameraRoll * 180 / Float.pi)°")
            }
            
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
        
        private func handleBlenderStylePan(deltaX: Float, deltaY: Float) {
            // Debug logging
            print("🎯 EXECUTING Blender-style pan: deltaX=\(deltaX), deltaY=\(deltaY)")
            
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
            
            let oldFocusPoint = focusPoint
            focusPoint = SCNVector3(
                focusPoint.x + deltaFocusX,
                focusPoint.y + deltaFocusY,
                focusPoint.z + deltaFocusZ
            )
            
            // Update camera position to maintain the same relative position to the new focus point
            updateCameraPosition()
            
            print("🎯 Blender-style pan complete: \(oldFocusPoint) -> \(focusPoint)")
        }
        
        private func updateCameraPosition() {
            // Spherical to Cartesian conversion with Z-axis rotation (roll)
            // Azimuth rotates around Y-axis (horizontal movement)
            // Elevation rotates around X-axis (vertical movement)
            // Roll rotates around Z-axis (twist)
            let x = cameraDistance * cos(cameraElevation) * sin(cameraAzimuth)
            let y = cameraDistance * sin(cameraElevation)
            let z = cameraDistance * cos(cameraElevation) * cos(cameraAzimuth)
            
            cameraNode.position = SCNVector3(
                focusPoint.x + CGFloat(x),
                focusPoint.y + CGFloat(y),
                focusPoint.z + CGFloat(z)
            )
            
            // For now, use a simpler approach to roll that doesn't cause compilation issues
            // Apply Z-axis rotation using Euler angles
            cameraNode.look(at: focusPoint, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            
            // Apply roll rotation after look-at
            let currentTransform = cameraNode.worldTransform
            let rollTransform = SCNMatrix4MakeRotation(CGFloat(cameraRoll), 0, 0, 1)
            cameraNode.transform = SCNMatrix4Mult(currentTransform, rollTransform)
        }
        
        // Add helper functions for vector math
        private func crossProduct(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
            return SCNVector3(
                a.y * b.z - a.z * b.y,
                a.z * b.x - a.x * b.z,
                a.x * b.y - a.y * b.x
            )
        }
        
        private func normalize(_ vector: SCNVector3) -> SCNVector3 {
            let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
            if length > 0 {
                return SCNVector3(vector.x / length, vector.y / length, vector.z / length)
            }
            return SCNVector3(0, 1, 0) // Default up
        }
        
        // Add method to get current camera orientation for compass
        func getCameraOrientation() -> (azimuth: Float, elevation: Float, roll: Float) {
            return (cameraAzimuth, cameraElevation, cameraRoll)
        }
        
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)
            
            DispatchQueue.main.async {
                switch self.selectedTool {
                case .select:
                    self.handleSelection(at: location, in: scnView)
                case .ledWall, .camera, .setPiece, .light, .staging:
                    self.handleObjectPlacement(at: location, in: scnView)
                }
            }
        }
        
        @objc func handleRightClick(_ gesture: NSClickGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)
            
            DispatchQueue.main.async {
                self.showContextMenu(at: location, in: scnView)
            }
        }
        
        private func showContextMenu(at point: CGPoint, in scnView: SCNView) {
            let menu = NSMenu()
            
            // Add context menu items based on what's under the cursor
            let hitResults = scnView.hitTest(point, options: nil)
            
            if let hitResult = hitResults.first,
               let object = parent.studioManager.getObject(from: hitResult.node) {
                
                // Store the clicked object for use in actions
                currentContextMenuObject = object
                
                // Object-specific menu
                let selectItem = NSMenuItem(title: "Select \(object.name)", action: #selector(selectClickedObject), keyEquivalent: "")
                selectItem.target = self
                menu.addItem(selectItem)
                
                // LED Wall specific options
                if object.type == .ledWall {
                    // Add separator before LED wall specific options
                    menu.addItem(NSMenuItem.separator())
                    
                    // Connect to Camera option
                    let connectItem = NSMenuItem(title: "Connect to Camera", action: #selector(connectToCamera), keyEquivalent: "")
                    connectItem.target = self
                    connectItem.representedObject = object
                    menu.addItem(connectItem)
                    
                    // Disconnect camera option (if currently connected)
                    if object.isDisplayingCameraFeed {
                        let disconnectItem = NSMenuItem(title: "Disconnect Camera", action: #selector(disconnectCamera), keyEquivalent: "")
                        disconnectItem.target = self
                        disconnectItem.representedObject = object
                        menu.addItem(disconnectItem)
                    }
                    
                    menu.addItem(NSMenuItem.separator())
                }
                
                let focusItem = NSMenuItem(title: "Focus on Object", action: #selector(focusOnClickedObject), keyEquivalent: "")
                focusItem.target = self
                menu.addItem(focusItem)
                
                let duplicateItem = NSMenuItem(title: "Duplicate", action: #selector(duplicateClickedObject), keyEquivalent: "")
                duplicateItem.target = self
                menu.addItem(duplicateItem)
                
                let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteClickedObject), keyEquivalent: "")
                deleteItem.target = self
                menu.addItem(deleteItem)
                
                let resetItem = NSMenuItem(title: "Reset Transform", action: #selector(resetClickedObjectTransform), keyEquivalent: "")
                resetItem.target = self
                menu.addItem(resetItem)
                
            } else {
                // Clear stored object for empty space menu
                currentContextMenuObject = nil
                
                // Empty space menu
                let addLEDItem = NSMenuItem(title: "Add LED Wall", action: #selector(addLEDWall), keyEquivalent: "")
                addLEDItem.target = self
                menu.addItem(addLEDItem)
                
                let addCameraItem = NSMenuItem(title: "Add Camera", action: #selector(addCamera), keyEquivalent: "")
                addCameraItem.target = self
                menu.addItem(addCameraItem)
                
                let addSetPieceItem = NSMenuItem(title: "Add Set Piece", action: #selector(addSetPiece), keyEquivalent: "")
                addSetPieceItem.target = self
                menu.addItem(addSetPieceItem)
                
                let addLightItem = NSMenuItem(title: "Add Light", action: #selector(addLight), keyEquivalent: "")
                addLightItem.target = self
                menu.addItem(addLightItem)
                
                let selectAllItem = NSMenuItem(title: "Select All", action: #selector(selectAll), keyEquivalent: "")
                selectAllItem.target = self
                menu.addItem(selectAllItem)
                
                let deselectAllItem = NSMenuItem(title: "Deselect All", action: #selector(deselectAll), keyEquivalent: "")
                deselectAllItem.target = self
                menu.addItem(deselectAllItem)
            }
            
            // Store the menu point for use in actions
            currentContextMenuPoint = point
            
            // Show the menu
            menu.popUp(positioning: nil, at: point, in: scnView)
        }
        
        // MARK: - NSDraggingDestination
        
        func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            print("🎯 COORDINATOR: Drag session entered 3D viewport")
            
            // Check if we have string data (asset ID)
            if sender.draggingPasteboard.canReadObject(forClasses: [NSString.self], options: nil) {
                print("🎯 COORDINATOR: Valid drag data detected")
                return .copy
            }
            
            print("🎯 COORDINATOR: No valid drag data found")
            return []
        }
        
        func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            // Continue to accept the drag as long as we have valid data
            if sender.draggingPasteboard.canReadObject(forClasses: [NSString.self], options: nil) {
                return .copy
            }
            return []
        }
        
        func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let location = sender.draggingLocation
            
            print("🎯 COORDINATOR: Performing drag operation at location: \(location)")
            
            // Use the stored SCNView reference
            guard let scnView = currentSCNView else {
                print("⚠️ No SCNView available for drag operation")
                return false 
            }
            
            // Try multiple methods to get the asset ID
            var assetIDString: String?
            
            // Method 1: Try to get string directly
            if let data = sender.draggingPasteboard.data(forType: .string),
               let string = String(data: data, encoding: .utf8) {
                assetIDString = string
                print("🎯 COORDINATOR: Found asset ID via .string type: \(string)")
            }
            
            // Method 2: Try to read as NSString object
            if assetIDString == nil,
               let objects = sender.draggingPasteboard.readObjects(forClasses: [NSString.self], options: nil),
               let string = objects.first as? String {
                assetIDString = string
                print("🎯 COORDINATOR: Found asset ID via NSString: \(string)")
            }
            
            // Method 3: Debug all available data
            if assetIDString == nil {
                print("⚠️ No asset ID found in drag operation")
                if let types = sender.draggingPasteboard.types {
                    print("   Available pasteboard types: \(types)")
                    for type in types {
                        if let data = sender.draggingPasteboard.data(forType: type) {
                            print("   Type \(type): data length \(data.count)")
                            if let string = String(data: data, encoding: .utf8) {
                                print("   String representation: '\(string)'")
                                if assetIDString == nil {
                                    assetIDString = string
                                }
                            }
                        }
                    }
                }
            }
            
            guard let finalAssetID = assetIDString else {
                print("⚠️ Could not extract asset ID from drag operation")
                return false
            }
            
            print("🎯 COORDINATOR: Processing asset ID: \(finalAssetID)")
            
            // Perform the actual drop operation on the main thread
            DispatchQueue.main.async {
                // Convert drop location to 3D world position
                let worldPos = self.parent.studioManager.worldPosition(from: location, in: scnView)
                let finalPos = self.snapToGrid ? self.snapToGridPosition(worldPos) : worldPos
                
                print("🎯 COORDINATOR: World position: \(worldPos) -> Final: \(finalPos)")
                
                // Find and add the appropriate asset
                var assetFound = false
                
                if let ledWallAsset = LEDWallAsset.predefinedWalls.first(where: { $0.id.uuidString == finalAssetID }) {
                    self.parent.studioManager.addLEDWall(from: ledWallAsset, at: finalPos)
                    print("🖱️ Successfully dropped LED Wall: \(ledWallAsset.name) at \(finalPos)")
                    assetFound = true
                    
                } else if let cameraAsset = CameraAsset.predefinedCameras.first(where: { $0.id.uuidString == finalAssetID }) {
                    let camera = VirtualCamera(name: cameraAsset.name, position: finalPos)
                    camera.focalLength = Float(cameraAsset.focalLength)
                    self.parent.studioManager.virtualCameras.append(camera)
                    self.parent.studioManager.scene.rootNode.addChildNode(camera.node)
                    print("🖱️ Successfully dropped Camera: \(cameraAsset.name) at \(finalPos)")
                    assetFound = true
                    
                } else if let lightAsset = LightAsset.predefinedLights.first(where: { $0.id.uuidString == finalAssetID }) {
                    self.parent.studioManager.addLight(from: lightAsset, at: finalPos)
                    print("🖱️ Successfully dropped Light: \(lightAsset.name) at \(finalPos)")
                    assetFound = true
                    
                } else if let setPieceAsset = SetPieceAsset.predefinedPieces.first(where: { $0.id.uuidString == finalAssetID }) {
                    self.parent.studioManager.addSetPiece(from: setPieceAsset, at: finalPos)
                    print("🖱️ Successfully dropped Set Piece: \(setPieceAsset.name) at \(finalPos)")
                    assetFound = true
                    
                } else if let stagingAsset = StagingAsset.predefinedStaging.first(where: { $0.id.uuidString == finalAssetID }) {
                    self.parent.studioManager.addStagingEquipment(from: stagingAsset, at: finalPos)
                    print("🖱️ Successfully dropped Staging Equipment: \(stagingAsset.name) at \(finalPos)")
                    assetFound = true
                }
                
                if !assetFound {
                    print("⚠️ No matching asset found for ID: \(finalAssetID)")
                }
            }
            
            return true
        }
        
        // Context menu actions - PROPERLY IMPLEMENTED
        @objc private func selectClickedObject(_ sender: NSMenuItem) {
            guard let object = currentContextMenuObject else { return }
            print("🎯 Context menu: Select object \(object.name)")
            
            // Clear other selections
            for obj in parent.studioManager.studioObjects {
                obj.setSelected(false)
            }
            selectedObjects.removeAll()
            
            // Select the clicked object
            object.setSelected(true)
            selectedObjects.insert(object.id)
            parent.selectedObjects = selectedObjects
        }
        
        @objc private func focusOnClickedObject(_ sender: NSMenuItem) {
            guard let object = currentContextMenuObject else { return }
            print("🎯 Context menu: Focus on object \(object.name)")
            
            // Move camera to focus on the object
            focusPoint = object.position
            cameraDistance = 10.0 // Set a good viewing distance
            updateCameraPosition()
        }
        
        @objc private func duplicateClickedObject(_ sender: NSMenuItem) {
            guard let object = currentContextMenuObject else { return }
            print("🎯 Context menu: Duplicate object \(object.name)")
            
            // Create duplicate at offset position
            let offset: Float = 2.0
            let newPosition = SCNVector3(
                object.position.x + CGFloat(offset),
                object.position.y,
                object.position.z + CGFloat(offset)
            )
            
            // Add based on object type
            parent.studioManager.addObject(type: object.type, at: newPosition)
        }
        
        @objc private func deleteClickedObject(_ sender: NSMenuItem) {
            guard let object = currentContextMenuObject else { return }
            print("🎯 Context menu: Delete object \(object.name)")
            
            // Remove from selection if selected
            selectedObjects.remove(object.id)
            parent.selectedObjects = selectedObjects
            
            // Delete the object
            parent.studioManager.deleteObject(object)
        }
        
        @objc private func resetClickedObjectTransform(_ sender: NSMenuItem) {
            guard let object = currentContextMenuObject else { return }
            print("🎯 Context menu: Reset transform for \(object.name)")
            
            // Reset transform to origin
            object.position = SCNVector3(0, 0, 0)
            object.rotation = SCNVector3(0, 0, 0)
            object.scale = SCNVector3(1, 1, 1)
            object.updateNodeTransform()
        }
        
        @objc private func addLEDWall(_ sender: NSMenuItem) {
            print("🎯 Context menu: Add LED Wall action")
            // Add LED wall at the clicked position
            guard let scnView = currentSCNView else { return }
            let worldPos = parent.studioManager.worldPosition(from: currentContextMenuPoint, in: scnView)
            let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
            
            if let asset = LEDWallAsset.predefinedWalls.first {
                parent.studioManager.addLEDWall(from: asset, at: finalPos)
            }
        }
        
        @objc private func addCamera(_ sender: NSMenuItem) {
            print("🎯 Context menu: Add Camera action")
            // Add camera at the clicked position
            guard let scnView = currentSCNView else { return }
            let worldPos = parent.studioManager.worldPosition(from: currentContextMenuPoint, in: scnView)
            let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
            
            if let asset = CameraAsset.predefinedCameras.first {
                let camera = VirtualCamera(name: asset.name, position: finalPos)
                camera.focalLength = Float(asset.focalLength)
                parent.studioManager.virtualCameras.append(camera)
                parent.studioManager.scene.rootNode.addChildNode(camera.node)
            }
        }
        
        @objc private func addSetPiece(_ sender: NSMenuItem) {
            print("🎯 Context menu: Add Set Piece action")
            // Add set piece at the clicked position
            guard let scnView = currentSCNView else { return }
            let worldPos = parent.studioManager.worldPosition(from: currentContextMenuPoint, in: scnView)
            let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
            
            if let asset = SetPieceAsset.predefinedPieces.first {
                parent.studioManager.addSetPiece(from: asset, at: finalPos)
            }
        }
        
        @objc private func addLight(_ sender: NSMenuItem) {
            print("🎯 Context menu: Add Light action")
            // Add light at the clicked position
            guard let scnView = currentSCNView else { return }
            let worldPos = parent.studioManager.worldPosition(from: currentContextMenuPoint, in: scnView)
            let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
            
            if let asset = LightAsset.predefinedLights.first {
                parent.studioManager.addLight(from: asset, at: finalPos)
            }
        }
        
        @objc private func selectAll(_ sender: NSMenuItem) {
            print("🎯 Context menu: Select All action")
            // Select all objects in the scene
            selectedObjects.removeAll()
            for obj in parent.studioManager.studioObjects {
                obj.setSelected(true)
                selectedObjects.insert(obj.id)
            }
            parent.selectedObjects = selectedObjects
        }
        
        @objc private func deselectAll(_ sender: NSMenuItem) {
            print("🎯 Context menu: Deselect All action")
            // Clear all selections
            for obj in parent.studioManager.studioObjects {
                obj.setSelected(false)
            }
            selectedObjects.removeAll()
            parent.selectedObjects = selectedObjects
        }
        
        // NEW: LED Wall camera connection actions
        @objc private func connectToCamera(_ sender: NSMenuItem) {
            guard let ledWall = sender.representedObject as? StudioObject,
                  ledWall.type == .ledWall else {
                print("❌ Connect to camera called on non-LED wall object")
                return
            }
            
            print("📹 Connect to camera requested for LED wall: \(ledWall.name)")
            
            // Trigger the camera feed modal via a notification or callback
            DispatchQueue.main.async {
                // Post notification to show the camera feed modal
                NotificationCenter.default.post(
                    name: .showLEDWallCameraFeedModal,
                    object: ledWall
                )
            }
        }
        
        @objc private func disconnectCamera(_ sender: NSMenuItem) {
            guard let ledWall = sender.representedObject as? StudioObject,
                  ledWall.type == .ledWall else {
                print("❌ Disconnect camera called on non-LED wall object")
                return
            }
            
            print("🔌 Disconnect camera requested for LED wall: \(ledWall.name)")
            
            // Disconnect the camera feed directly
            DispatchQueue.main.async {
                ledWall.disconnectCameraFeed()
                
                // Post notification to update any observers
                NotificationCenter.default.post(
                    name: .ledWallCameraFeedDisconnected,
                    object: ledWall
                )
            }
        }
        
        // Enhanced selection handling with better visual feedback
        private func handleSelection(at point: CGPoint, in scnView: SCNView) {
            print("🎯 CLICK at \(point)")
            
            let hitResults = scnView.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .ignoreChildNodes: false,
                .ignoreHiddenNodes: true,
                .boundingBoxOnly: false
            ])
            
            print("   Found \(hitResults.count) hit results")
            
            // Filter out highlight/gizmo nodes from hits
            let validHits = hitResults.filter { hit in
                let nodeName = hit.node.name ?? ""
                return !nodeName.contains("selection_outline") && 
                       !nodeName.contains("transform_gizmo") &&
                       !nodeName.contains("highlight")
            }
            
            print("   Valid hits (excluding UI): \(validHits.count)")
            
            if let hitResult = validHits.first {
                let hitNode = hitResult.node
                print("   Hit node: \(hitNode.name ?? "unnamed")")
                
                // Find the studio object
                if let object = parent.studioManager.getObject(from: hitNode) {
                    let wasSelected = selectedObjects.contains(object.id)
                    let isMultiSelect = NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command)
                    
                    print("   Found object: \(object.name), currently selected: \(wasSelected)")
                    
                    if isMultiSelect {
                        // Multi-selection
                        if wasSelected {
                            selectedObjects.remove(object.id)
                            object.setSelected(false)
                            print("   ➖ Removed from selection: \(object.name)")
                        } else {
                            selectedObjects.insert(object.id)
                            object.setSelected(true)
                            print("   ➕ Added to selection: \(object.name)")
                        }
                    } else {
                        // Single selection - clear others first
                        for obj in parent.studioManager.studioObjects {
                            obj.setSelected(false)
                        }
                        selectedObjects.removeAll()
                        
                        // Select clicked object
                        selectedObjects.insert(object.id)
                        object.setSelected(true)
                        print("   ✅ Selected: \(object.name)")
                        
                        // Haptic feedback
                        #if os(macOS)
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        #endif
                    }
                    
                    // Update parent binding immediately
                    parent.selectedObjects = selectedObjects
                    print("   🔄 Updated selection binding: \(selectedObjects.count) objects")
                    
                } else {
                    print("   ⚠️ No StudioObject found for hit node: \(hitNode.name ?? "unnamed")")
                }
                
            } else {
                // Clicked empty space
                if !NSEvent.modifierFlags.contains(.shift) && !NSEvent.modifierFlags.contains(.command) {
                    print("   🌌 Clicked empty space - clearing selection")
                    
                    for obj in parent.studioManager.studioObjects {
                        obj.setSelected(false)
                    }
                    selectedObjects.removeAll()
                    parent.selectedObjects = selectedObjects
                }
            }
        }
        
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
        
        // Add method for direct pan handling (without gesture recognizer)
        func handleBlenderStylePanDirect(deltaX: Float, deltaY: Float) {
            // Debug logging
            print("🎯 EXECUTING Direct Blender-style pan: deltaX=\(deltaX), deltaY=\(deltaY)")
            
            // Don't pan if we're in transform mode
            if parent.transformController.isActive {
                print("⚠️ Skipping pan - transform mode active")
                return
            }
            
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
            
            print("🎯 Direct Blender-style pan complete: \(oldFocusPoint) -> \(focusPoint)")
        }
    }
    
    // Custom SCNView that handles trackpad scroll events AND drag operations
    class CustomSCNView: SCNView {
        weak var gestureHandler: Coordinator?
        
        // Track mouse movement without button press
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
            // Ensure we can receive scroll events and drag operations
            self.wantsLayer = true
        }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Ensure drag registration happens when view is in window
            registerForDraggedTypes([.string])
            print("🎯 CustomSCNView registered for drag types: [.string]")
            
            // Set up tracking area for mouse movement
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
            
            print("🖱️ MOUSE MOVED: shift=\(isShiftPressed), location=\(currentLocation)")
            
            // Check if we should start or continue shift+drag panning
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    // Start tracking
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print("🎯 STARTED Shift+Mouse tracking")
                } else {
                    // Continue tracking - calculate delta and pan
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    if abs(deltaX) > 0.5 || abs(deltaY) > 0.5 { // Only pan if there's meaningful movement
                        print("🎯 SHIFT + MOUSE MOVE: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                        gestureHandler?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    }
                    
                    lastMouseLocation = currentLocation
                }
            } else {
                // Stop tracking if shift is released
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print("🎯 STOPPED Shift+Mouse tracking")
                }
            }
            
            super.mouseMoved(with: event)
        }
        
        override func mouseDragged(with event: NSEvent) {
            let currentLocation = convert(event.locationInWindow, from: nil)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            
            print("🖱️ MOUSE DRAGGED: shift=\(isShiftPressed), location=\(currentLocation), button=\(event.buttonNumber)")
            
            // If shift is pressed during drag, override normal drag behavior with panning
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    // Start tracking
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print("🎯 STARTED Shift+Drag tracking")
                } else {
                    // Continue tracking - calculate delta and pan
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    print("🎯 SHIFT + DRAG: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                    gestureHandler?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    
                    lastMouseLocation = currentLocation
                }
                
                // Don't pass to super - we're handling this drag ourselves
                return
            } else {
                // Stop tracking if shift is released during drag
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print("🎯 STOPPED Shift+Drag tracking")
                }
            }
            
            // Let normal drag behavior continue if shift is not pressed
            super.mouseDragged(with: event)
        }
        
        override func rightMouseDragged(with event: NSEvent) {
            let currentLocation = convert(event.locationInWindow, from: nil)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            
            print("🖱️ RIGHT MOUSE DRAGGED: shift=\(isShiftPressed), location=\(currentLocation)")
            
            // If shift is pressed during right drag, override with panning
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print("🎯 STARTED Shift+Right Drag tracking")
                } else {
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    print("🎯 SHIFT + RIGHT DRAG: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                    gestureHandler?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    
                    lastMouseLocation = currentLocation
                }
                return
            } else {
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print("🎯 STOPPED Shift+Right Drag tracking")
                }
            }
            
            super.rightMouseDragged(with: event)
        }
        
        override func otherMouseDragged(with event: NSEvent) {
            let currentLocation = convert(event.locationInWindow, from: nil)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            
            print("🖱️ OTHER MOUSE DRAGGED: shift=\(isShiftPressed), location=\(currentLocation), button=\(event.buttonNumber)")
            
            // If shift is pressed during middle mouse drag, override with panning
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print("🎯 STARTED Shift+Middle Drag tracking")
                } else {
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    print("🎯 SHIFT + MIDDLE DRAG: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                    gestureHandler?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    
                    lastMouseLocation = currentLocation
                }
                return
            } else {
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print("🎯 STOPPED Shift+Middle Drag tracking")
                }
            }
            
            super.otherMouseDragged(with: event)
        }
        
        override func scrollWheel(with event: NSEvent) {
            // Check if Shift is pressed for panning
            let isShiftPressed = event.modifierFlags.contains(.shift)
            let deltaX = Float(event.scrollingDeltaX)
            let deltaY = Float(event.scrollingDeltaY)
            
            // Check if there's actual movement
            if abs(deltaX) > 0.1 || abs(deltaY) > 0.1 {
                if isShiftPressed {
                    // Shift + scroll = Blender-style pan
                    print("🎯 SHIFT + SCROLL: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                    gestureHandler?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                } else {
                    // Normal scroll = orbit
                    print("🌀 NORMAL SCROLL: Activating orbit")
                    gestureHandler?.handleTrackpadScroll(deltaX: deltaX, deltaY: deltaY)
                }
            } else {
                // Pass through if no movement  
                super.scrollWheel(with: event)
            }
        }
        
        // MARK: - NSDraggingDestination Implementation
        
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            print("🎯 CustomSCNView: Drag entered 3D viewport")
            print("   Available types: \(sender.draggingPasteboard.types ?? [])")
            return gestureHandler?.draggingEntered(sender) ?? []
        }
        
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            // Don't spam the log with updated messages, but return the right operation
            return gestureHandler?.draggingUpdated(sender) ?? []
        }
        
        override func draggingExited(_ sender: NSDraggingInfo?) {
            print("🎯 CustomSCNView: Drag exited 3D viewport")
        }
        
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            print("🎯 CustomSCnView: Performing drag operation")
            let result = gestureHandler?.performDragOperation(sender) ?? false
            print("🎯 CustomSCNView: Drag operation result: \(result)")
            return result
        }
        
        override func concludeDragOperation(_ sender: NSDraggingInfo?) {
            print("🎯 CustomSCNView: Concluded drag operation")
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