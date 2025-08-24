//
//  Viewport3DView.swift
//  Vantaview
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
    @ObservedObject var transformController: TransformController
    
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
        
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics = false
        
        scnView.wantsLayer = true
        DispatchQueue.main.async {
            _ = scnView.becomeFirstResponder()
        }
        
        context.coordinator.setupCamera(in: scnView)
        context.coordinator.setupGestures(for: scnView)
        
        scnView.gestureHandler = context.coordinator
        
        context.coordinator.currentSCNView = scnView
        
        scnView.registerForDraggedTypes([.string])
        print(" Viewport3DView registered SCNView for drag types")
        
        return scnView
    }
    
    func updateNSView(_ nsView: CustomSCNView, context: Context) {
        nsView.allowsCameraControl = false
        
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
        
        weak var currentSCNView: SCNView?
        
        private var currentContextMenuPoint: CGPoint = .zero
        private var currentContextMenuObject: StudioObject? 
        
        private var cameraNode: SCNNode!
        private var cameraDistance: Float = 15.0
        private var cameraAzimuth: Float = 0.0      
        private var cameraElevation: Float = 0.3    
        private var focusPoint = SCNVector3(0, 1, 0)
        
        private var cameraRoll: Float = 0.0 // Z-axis rotation
        
        init(_ parent: Viewport3DView) {
            self.parent = parent
            super.init()
        }
        
        func setupCamera(in scnView: SCNView) {
            currentSCNView = scnView
            
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
            let magnifyGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
            magnifyGesture.delegate = self
            view.addGestureRecognizer(magnifyGesture)
            
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            clickGesture.delegate = self
            view.addGestureRecognizer(clickGesture)
            
            let rightClickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
            rightClickGesture.buttonMask = 2
            rightClickGesture.delegate = self
            view.addGestureRecognizer(rightClickGesture)
            
            let leftPanGesture = NSPanGestureRecognizer(target: self, action: #selector(handleLeftPan(_:)))
            leftPanGesture.delegate = self
            leftPanGesture.buttonMask = 1 
            view.addGestureRecognizer(leftPanGesture)
            
            let middlePanGesture = NSPanGestureRecognizer(target: self, action: #selector(handleMiddlePan(_:)))
            middlePanGesture.delegate = self
            middlePanGesture.buttonMask = 4 
            view.addGestureRecognizer(middlePanGesture)
            
            let trackpadPanGesture = NSPanGestureRecognizer(target: self, action: #selector(handleTrackpadPan(_:)))
            trackpadPanGesture.delegate = self
            trackpadPanGesture.buttonMask = 0 
            view.addGestureRecognizer(trackpadPanGesture)
            
            let rotationGesture = NSRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            rotationGesture.delegate = self
            view.addGestureRecognizer(rotationGesture)
        }
        
        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
            if (gestureRecognizer is NSMagnificationGestureRecognizer && otherGestureRecognizer is NSPanGestureRecognizer) ||
               (gestureRecognizer is NSPanGestureRecognizer && otherGestureRecognizer is NSMagnificationGestureRecognizer) {
                return true
            }
            
            if gestureRecognizer is NSPanGestureRecognizer && otherGestureRecognizer is NSPanGestureRecognizer {
                let leftPan = gestureRecognizer as? NSPanGestureRecognizer
                let rightPan = otherGestureRecognizer as? NSPanGestureRecognizer
                
                if leftPan?.buttonMask == rightPan?.buttonMask {
                    return false 
                }
                return false 
            }
            
            if gestureRecognizer is NSRotationGestureRecognizer || otherGestureRecognizer is NSRotationGestureRecognizer {
                return false 
            }
            
            return false 
        }
        
        @objc func handleLeftPan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            
            let translation = gesture.translation(in: view)
            let currentPoint = gesture.location(in: view)
            
            // Debug logging
            let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
            print("🖱️ LEFT PAN: shift=\(isShiftPressed), translation=\(translation)")
            
            // Check for Shift + Left Mouse Button = Blender-style pan
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
            
            print(" MIDDLE PAN: shift=\(isShiftPressed), translation=\(translation)")
            
            if isShiftPressed {
                print(" SHIFT + MIDDLE MOUSE: Activating Blender-style pan")
                handleBlenderStylePan(deltaX: Float(translation.x), deltaY: Float(translation.y))
                gesture.setTranslation(.zero, in: view)
            } else {
                print(" PLAIN MIDDLE MOUSE: Activating pan")
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
            
            // Trackpad gestures (high velocity indicates scroll gestures)
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
            let rotationSensitivity: Float = 0.5
            let deltaRotation = Float(gesture.rotation) * rotationSensitivity
            
            cameraRoll += deltaRotation
            
            if cameraRoll > Float.pi * 2 {
                cameraRoll -= Float.pi * 2
            } else if cameraRoll < -Float.pi * 2 {
                cameraRoll += Float.pi * 2
            }
            
            print(" Z-axis rotation: \(cameraRoll * 180 / Float.pi)°")
            
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
            print(" EXECUTING Blender-style pan: deltaX=\(deltaX), deltaY=\(deltaY)")
            
            let cameraTransform = cameraNode.worldTransform
            
            let rightX = CGFloat(cameraTransform.m11)
            let rightY = CGFloat(cameraTransform.m12)
            let rightZ = CGFloat(cameraTransform.m13)
            
            let upX = CGFloat(cameraTransform.m21)
            let upY = CGFloat(cameraTransform.m22)
            let upZ = CGFloat(cameraTransform.m23)
            
            let panScale = CGFloat(cameraDistance * 0.002)
            let panXAmount = CGFloat(deltaX) * panScale
            let panYAmount = CGFloat(deltaY) * panScale
            
            let deltaFocusX = -(rightX * panXAmount - upX * panYAmount)
            let deltaFocusY = -(rightY * panXAmount - upY * panYAmount)
            let deltaFocusZ = -(rightZ * panXAmount - upZ * panYAmount)
            
            let oldFocusPoint = focusPoint
            focusPoint = SCNVector3(
                focusPoint.x + deltaFocusX,
                focusPoint.y + deltaFocusY,
                focusPoint.z + deltaFocusZ
            )
            
            updateCameraPosition()
            
            print(" Blender-style pan complete: \(oldFocusPoint) -> \(focusPoint)")
        }
        
        private func updateCameraPosition() {
            let x = cameraDistance * cos(cameraElevation) * sin(cameraAzimuth)
            let y = cameraDistance * sin(cameraElevation)
            let z = cameraDistance * cos(cameraElevation) * cos(cameraAzimuth)
            
            cameraNode.position = SCNVector3(
                focusPoint.x + CGFloat(x),
                focusPoint.y + CGFloat(y),
                focusPoint.z + CGFloat(z)
            )
            
            cameraNode.look(at: focusPoint, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            
            let currentTransform = cameraNode.worldTransform
            let rollTransform = SCNMatrix4MakeRotation(CGFloat(cameraRoll), 0, 0, 1)
            cameraNode.transform = SCNMatrix4Mult(currentTransform, rollTransform)
        }
        
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
            return SCNVector3(0, 1, 0) 
        }
        
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
            
            let hitResults = scnView.hitTest(point, options: nil)
            
            if let hitResult = hitResults.first,
               let object = parent.studioManager.getObject(from: hitResult.node) {
                
                currentContextMenuObject = object
                
                let selectItem = NSMenuItem(title: "Select \(object.name)", action: #selector(selectClickedObject), keyEquivalent: "")
                selectItem.target = self
                menu.addItem(selectItem)
                
                if object.type == .ledWall {
                    menu.addItem(NSMenuItem.separator())
                    
                    let connectItem = NSMenuItem(title: "Connect to Camera", action: #selector(connectToCamera), keyEquivalent: "")
                    connectItem.target = self
                    connectItem.representedObject = object
                    menu.addItem(connectItem)
                    
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
                currentContextMenuObject = nil
                
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
            
            currentContextMenuPoint = point
            
            menu.popUp(positioning: nil, at: point, in: scnView)
        }
        
        @objc private func selectClickedObject(_ sender: NSMenuItem) {
            guard let object = currentContextMenuObject else { return }
            print(" Context menu: Select object \(object.name)")
            
            for obj in parent.studioManager.studioObjects {
                obj.setSelected(false)
            }
            selectedObjects.removeAll()
            
            object.setSelected(true)
            selectedObjects.insert(object.id)
            parent.selectedObjects = selectedObjects
        }
        
        @objc private func focusOnClickedObject(_ sender: NSMenuItem) {
            guard let object = currentContextMenuObject else { return }
            print(" Context menu: Focus on object \(object.name)")
            
            focusPoint = object.position
            cameraDistance = 10.0 
            updateCameraPosition()
        }
        
        @objc private func duplicateClickedObject(_ sender: NSMenuItem) {
            guard let object = currentContextMenuObject else { return }
            print(" Context menu: Duplicate object \(object.name)")
            
            let offset: Float = 2.0
            let newPosition = SCNVector3(
                object.position.x + CGFloat(offset),
                object.position.y,
                object.position.z + CGFloat(offset)
            )
            
            parent.studioManager.addObject(type: object.type, at: newPosition)
        }
        
        @objc private func deleteClickedObject(_ sender: NSMenuItem) {
            guard let object = currentContextMenuObject else { return }
            print(" Context menu: Delete object \(object.name)")
            
            selectedObjects.remove(object.id)
            parent.selectedObjects = selectedObjects
            
            parent.studioManager.deleteObject(object)
        }
        
        @objc private func resetClickedObjectTransform(_ sender: NSMenuItem) {
            guard let object = currentContextMenuObject else { return }
            print(" Context menu: Reset transform for \(object.name)")
            
            object.position = SCNVector3(0, 0, 0)
            object.rotation = SCNVector3(0, 0, 0)
            object.scale = SCNVector3(1, 1, 1)
            object.updateNodeTransform()
        }
        
        @objc private func addLEDWall(_ sender: NSMenuItem) {
            print(" Context menu: Add LED Wall action")
            
            guard let scnView = currentSCNView else { return }
            let worldPos = parent.studioManager.worldPosition(from: currentContextMenuPoint, in: scnView)
            let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
            
            if let asset = LEDWallAsset.predefinedWalls.first {
                parent.studioManager.addLEDWall(from: asset, at: finalPos)
            }
        }
        
        @objc private func addCamera(_ sender: NSMenuItem) {
            print(" Context menu: Add Camera action")
            
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
            print(" Context menu: Add Set Piece action")
            
            guard let scnView = currentSCNView else { return }
            let worldPos = parent.studioManager.worldPosition(from: currentContextMenuPoint, in: scnView)
            let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
            
            if let asset = SetPieceAsset.predefinedPieces.first {
                parent.studioManager.addSetPiece(from: asset, at: finalPos)
            }
        }
        
        @objc private func addLight(_ sender: NSMenuItem) {
            print(" Context menu: Add Light action")
            
            guard let scnView = currentSCNView else { return }
            let worldPos = parent.studioManager.worldPosition(from: currentContextMenuPoint, in: scnView)
            let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
            
            if let asset = LightAsset.predefinedLights.first {
                parent.studioManager.addLight(from: asset, at: finalPos)
            }
        }
        
        @objc private func selectAll(_ sender: NSMenuItem) {
            print(" Context menu: Select All action")
            
            selectedObjects.removeAll()
            for obj in parent.studioManager.studioObjects {
                obj.setSelected(true)
                selectedObjects.insert(obj.id)
            }
            parent.selectedObjects = selectedObjects
        }
        
        @objc private func deselectAll(_ sender: NSMenuItem) {
            print(" Context menu: Deselect All action")
            
            for obj in parent.studioManager.studioObjects {
                obj.setSelected(false)
            }
            selectedObjects.removeAll()
            parent.selectedObjects = selectedObjects
        }
        
        @objc private func connectToCamera(_ sender: NSMenuItem) {
            guard let ledWall = sender.representedObject as? StudioObject,
                  ledWall.type == .ledWall else {
                print(" Connect to camera called on non-LED wall object")
                return
            }
            
            print(" Connect to camera requested for LED wall: \(ledWall.name)")
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showLEDWallCameraFeedModal,
                    object: ledWall
                )
            }
        }
        
        @objc private func disconnectCamera(_ sender: NSMenuItem) {
            guard let ledWall = sender.representedObject as? StudioObject,
                  ledWall.type == .ledWall else {
                print(" Disconnect camera called on non-LED wall object")
                return
            }
            
            print(" Disconnect camera requested for LED wall: \(ledWall.name)")
            
            DispatchQueue.main.async {
                ledWall.disconnectCameraFeed()
                
                NotificationCenter.default.post(
                    name: .ledWallCameraFeedDisconnected,
                    object: ledWall
                )
            }
        }
        
        private func handleSelection(at point: CGPoint, in scnView: SCNView) {
            print(" CLICK at \(point)")
            
            let hitResults = scnView.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .ignoreChildNodes: false,
                .ignoreHiddenNodes: true,
                .boundingBoxOnly: false
            ])
            
            print("   Found \(hitResults.count) hit results")
            
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
                
                if let object = parent.studioManager.getObject(from: hitNode) {
                    let wasSelected = selectedObjects.contains(object.id)
                    let isMultiSelect = NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command)
                    
                    print("   Found object: \(object.name), currently selected: \(wasSelected)")
                    
                    if isMultiSelect {
                        if wasSelected {
                            selectedObjects.remove(object.id)
                            object.setSelected(false)
                            print("   Removed from selection: \(object.name)")
                        } else {
                            selectedObjects.insert(object.id)
                            object.setSelected(true)
                            print("   Added to selection: \(object.name)")
                        }
                    } else {
                        for obj in parent.studioManager.studioObjects {
                            obj.setSelected(false)
                        }
                        selectedObjects.removeAll()
                        
                        selectedObjects.insert(object.id)
                        object.setSelected(true)
                        print("   Selected: \(object.name)")
                        
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    
                    parent.selectedObjects = selectedObjects
                    print("   Updated selection binding: \(selectedObjects.count) objects")
                    
                } else {
                    print("   No StudioObject found for hit node: \(hitNode.name ?? "unnamed")")
                }
                
            } else {
                if !NSEvent.modifierFlags.contains(.shift) && !NSEvent.modifierFlags.contains(.command) {
                    print("   Clicked empty space - clearing selection")
                    
                    for obj in parent.studioManager.studioObjects {
                        obj.setSelected(false)
                    }
                    selectedObjects.removeAll()
                    parent.selectedObjects = selectedObjects
                }
            }
        }
        
        private func handleObjectPlacement(at point: CGPoint, in scnView: SCNView) {
            let worldPos = parent.studioManager.worldPosition(from: point, in: scnView)
            
            let finalPos = snapToGrid ? snapToGridPosition(worldPos) : worldPos
            
            parent.studioManager.addObject(type: selectedTool, at: finalPos)
        }
        
        private func snapToGridPosition(_ position: SCNVector3) -> SCNVector3 {
            let gridStep = Float(gridSize)
            return SCNVector3(
                Float(round(position.x / CGFloat(gridStep)) * CGFloat(gridStep)),
                Float(position.y), 
                Float(round(position.z / CGFloat(gridStep)) * CGFloat(gridStep))
            )
        }
        
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
        
        // Add method for direct pan handling (without gesture recognizer)
        func handleBlenderStylePanDirect(deltaX: Float, deltaY: Float) {
            // Debug logging
            print("🎯 EXECUTING Direct Blender-style pan: deltaX=\(deltaX), deltaY=\(deltaY)")
            
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
    
    class CustomSCNView: SCNView {
        weak var gestureHandler: Coordinator?
        
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
            print(" CustomSCNView registered for drag types: [.string]")
            
            setupTrackingArea()
        }
        
        private func setupTrackingArea() {
            trackingAreas.forEach { removeTrackingArea($0) }
            
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
            
            print(" MOUSE MOVED: shift=\(isShiftPressed), location=\(currentLocation)")
            
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print(" STARTED Shift+Mouse tracking")
                } else {
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    if abs(deltaX) > 0.5 || abs(deltaY) > 0.5 { 
                        print(" SHIFT + MOUSE MOVE: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                        gestureHandler?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    }
                    
                    lastMouseLocation = currentLocation
                }
            } else {
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print(" STOPPED Shift+Mouse tracking")
                }
            }
            
            super.mouseMoved(with: event)
        }
        
        override func mouseDragged(with event: NSEvent) {
            let currentLocation = convert(event.locationInWindow, from: nil)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            
            print(" MOUSE DRAGGED: shift=\(isShiftPressed), location=\(currentLocation), button=\(event.buttonNumber)")
            
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print(" STARTED Shift+Drag tracking")
                } else {
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    print(" SHIFT + DRAG: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                    gestureHandler?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    
                    lastMouseLocation = currentLocation
                }
                
                return
            } else {
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print(" STOPPED Shift+Drag tracking")
                }
            }
            
            super.mouseDragged(with: event)
        }
        
        override func rightMouseDragged(with event: NSEvent) {
            let currentLocation = convert(event.locationInWindow, from: nil)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            
            print(" RIGHT MOUSE DRAGGED: shift=\(isShiftPressed), location=\(currentLocation)")
            
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print(" STARTED Shift+Right Drag tracking")
                } else {
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    print(" SHIFT + RIGHT DRAG: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                    gestureHandler?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    
                    lastMouseLocation = currentLocation
                }
                return
            } else {
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print(" STOPPED Shift+Right Drag tracking")
                }
            }
            
            super.rightMouseDragged(with: event)
        }
        
        override func otherMouseDragged(with event: NSEvent) {
            let currentLocation = convert(event.locationInWindow, from: nil)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            
            print(" OTHER MOUSE DRAGGED: shift=\(isShiftPressed), location=\(currentLocation), button=\(event.buttonNumber)")
            
            if isShiftPressed {
                if !isTrackingShiftDrag {
                    isTrackingShiftDrag = true
                    lastMouseLocation = currentLocation
                    print(" STARTED Shift+Middle Drag tracking")
                } else {
                    let deltaX = Float(currentLocation.x - lastMouseLocation.x)
                    let deltaY = Float(currentLocation.y - lastMouseLocation.y)
                    
                    print(" SHIFT + MIDDLE DRAG: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                    gestureHandler?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                    
                    lastMouseLocation = currentLocation
                }
                return
            } else {
                if isTrackingShiftDrag {
                    isTrackingShiftDrag = false
                    print(" STOPPED Shift+Middle Drag tracking")
                }
            }
            
            super.otherMouseDragged(with: event)
        }
        
        override func scrollWheel(with event: NSEvent) {
            let isShiftPressed = event.modifierFlags.contains(.shift)
            let deltaX = Float(event.scrollingDeltaX)
            let deltaY = Float(event.scrollingDeltaY)
            
            if abs(deltaX) > 0.1 || abs(deltaY) > 0.1 {
                if isShiftPressed {
                    print(" SHIFT + SCROLL: Activating Blender-style pan (deltaX=\(deltaX), deltaY=\(deltaY))")
                    gestureHandler?.handleBlenderStylePanDirect(deltaX: deltaX, deltaY: deltaY)
                } else {
                    print(" NORMAL SCROLL: Activating orbit")
                    gestureHandler?.handleTrackpadScroll(deltaX: deltaX, deltaY: deltaY)
                }
            } else {
                super.scrollWheel(with: event)
            }
        }
        
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            print(" CustomSCNView: Drag entered 3D viewport")
            print("   Available types: \(sender.draggingPasteboard.types ?? [])")
            return gestureHandler?.draggingEntered(sender) ?? []
        }
        
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            return gestureHandler?.draggingUpdated(sender) ?? []
        }
        
        override func draggingExited(_ sender: NSDraggingInfo?) {
            print(" CustomSCNView: Drag exited 3D viewport")
        }
        
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            print(" CustomSCnView: Performing drag operation")
            let result = gestureHandler?.performDragOperation(sender) ?? false
            print(" CustomSCNView: Drag operation result: \(result)")
            return result
        }
        
        override func concludeDragOperation(_ sender: NSDraggingInfo?) {
            print(" CustomSCNView: Concluded drag operation")
        }
    }
}
#else
struct Viewport3DView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView { SCNView() }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
#endif