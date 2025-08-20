//
//  TransformController.swift
//  Vistaview - Blender-Style Transform Controls
//

import SwiftUI
import SceneKit

@MainActor
class TransformController: ObservableObject {
    @Published var isActive = false
    @Published var mode: TransformMode = .move
    @Published var axis: TransformAxis = .free
    @Published var currentValues: TransformValues = TransformValues()
    @Published var selectedObjects: [StudioObject] = []
    @Published var isDragging = false
    @Published var isSnapMode = false // Track when Shift is held for snapping
    @Published var isDistanceScaling = false // Track cursor-based scaling mode
    
    private var originalPositions: [UUID: SCNVector3] = [:]
    private var originalRotations: [UUID: SCNVector3] = [:]
    private var originalScales: [UUID: SCNVector3] = [:]
    private var startMousePos: CGPoint = .zero
    private var lastMousePos: CGPoint = .zero
    private var accumulator: Float = 0.0
    
    // Cursor-based scaling state
    private var scaleStartMousePos: CGPoint = .zero
    private var scaleReferenceDistance: CGFloat = 0.0
    private var initialScaleFactors: [UUID: SCNVector3] = [:]
    
    // Visual gizmo nodes for axis constraints
    private var axisGizmoNodes: [SCNNode] = []
    private weak var scene: SCNScene?
    
    // Mouse interaction state
    private var dragStartPoint: CGPoint = .zero
    private var minimumDragDistance: CGFloat = 5.0 // Pixels to start drag
    
    // Snap settings for Blender-like behavior
    private let snapAngleIncrement: Float = 15.0 * Float.pi / 180.0 // 15 degrees in radians
    private let fineSnapAngleIncrement: Float = 5.0 * Float.pi / 180.0 // 5 degrees for precise work
    
    enum TransformMode {
        case move, rotate, scale
        
        var rawValue: String {
            switch self {
            case .move: return "move"
            case .rotate: return "rotate"
            case .scale: return "scale"
            }
        }
        
        var instruction: String {
            switch self {
            case .move: return "Move: Mouse to position, X/Y/Z to constrain, Shift for snap, Enter to confirm, Esc to cancel"
            case .rotate: return "Rotate: Mouse to rotate, X/Y/Z to constrain, Shift for angle snap, Enter to confirm, Esc to cancel"
            case .scale: return "Scale: Mouse to scale, X/Y/Z to constrain, Shift for increment snap, Enter to confirm, Esc to cancel"
            }
        }
    }
    
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
        
        var label: String {
            switch self {
            case .free: return "Free"
            case .x: return "X-Axis"
            case .y: return "Y-Axis"
            case .z: return "Z-Axis"
            }
        }
    }
    
    struct TransformValues {
        var position = SCNVector3Zero
        var rotation = SCNVector3Zero
        var scale = SCNVector3(1, 1, 1)
        var delta = SCNVector3Zero
        var snapAngle: Float? = nil // Current snap angle for rotation
    }
    
    func startTransform(_ newMode: TransformMode, objects: [StudioObject], startPoint: CGPoint, scene: SCNScene) {
        guard !objects.isEmpty else { return }
        
        mode = newMode
        axis = .free
        isActive = true
        startMousePos = startPoint
        lastMousePos = startPoint
        accumulator = 0.0
        selectedObjects = objects
        self.scene = scene
        
        // Store CURRENT values (not original) - this fixes the reset issue
        originalPositions.removeAll()
        originalRotations.removeAll()
        originalScales.removeAll()
        
        for obj in objects {
            originalPositions[obj.id] = obj.position // Current position
            originalRotations[obj.id] = obj.rotation // Current rotation  
            originalScales[obj.id] = obj.scale       // Current scale (not original!)
        }
        
        updateCurrentValues(from: objects)
        updateAxisGizmos()
    }
    
    func updateTransformWithMouse(mousePos: CGPoint) {
        guard isActive else { return }
        
        // Check if Shift is currently pressed for snap mode
        updateSnapMode()
        
        // Calculate delta from start position for more accurate transforms
        let totalDeltaX = Float(mousePos.x - startMousePos.x) * 0.01
        let totalDeltaY = Float(startMousePos.y - mousePos.y) * 0.01 // Invert Y
        
        switch mode {
        case .move:
            updateMoveTransform(deltaX: totalDeltaX, deltaY: totalDeltaY, objects: selectedObjects)
        case .rotate:
            updateRotateTransform(deltaX: totalDeltaX, deltaY: totalDeltaY, objects: selectedObjects)
        case .scale:
            updateScaleTransform(deltaX: totalDeltaX, deltaY: totalDeltaY, objects: selectedObjects)
        }
        
        lastMousePos = mousePos
        updateCurrentValues(from: selectedObjects)
        updateGizmoPositions()
    }
    
    func setAxis(_ newAxis: TransformAxis) {
        axis = newAxis
        updateAxisGizmos()
    }
    
    func confirmTransform() {
        // Make sure all objects have their final transform values properly set
        for obj in selectedObjects {
            obj.updateNodeTransform() // Ensure the node reflects the current object state
        }
        
        isActive = false
        clearAxisGizmos()
        clearStoredValues()
    }
    
    func cancelTransform() {
        // Restore original values
        for obj in selectedObjects {
            if let originalPos = originalPositions[obj.id] {
                obj.position = originalPos
            }
            if let originalRot = originalRotations[obj.id] {
                obj.rotation = originalRot
            }
            if let originalScale = originalScales[obj.id] {
                obj.scale = originalScale
            }
            obj.updateNodeTransform()
        }
        
        isActive = false
        clearAxisGizmos()
        clearStoredValues()
    }
    
    private func updateMoveTransform(deltaX: Float, deltaY: Float, objects: [StudioObject]) {
        for obj in objects {
            guard let originalPos = originalPositions[obj.id] else { continue }
            
            var newPosition = originalPos
            
            switch axis {
            case .free:
                newPosition.x += CGFloat(deltaX)
                newPosition.y += CGFloat(deltaY)
            case .x:
                newPosition.x += CGFloat(deltaX)
            case .y:
                newPosition.y += CGFloat(deltaY)
            case .z:
                newPosition.z += CGFloat(deltaX) // Use X mouse movement for Z
            }
            
            obj.position = newPosition
            obj.updateNodeTransform()
        }
        
        // Update gizmo positions to follow the objects
        updateGizmoPositions()
    }
    
    private func updateRotateTransform(deltaX: Float, deltaY: Float, objects: [StudioObject]) {
        let baseTotalRotationDelta = Float(lastMousePos.x - startMousePos.x) * Float.pi / 180 * 0.25 // Base rotation sensitivity
        
        var finalRotationDelta = baseTotalRotationDelta
        
        // Apply snapping if Shift is held
        if isSnapMode {
            // Snap rotation to increments
            let snapIncrement = snapAngleIncrement
            finalRotationDelta = round(baseTotalRotationDelta / snapIncrement) * snapIncrement
            
            // Store the current snap angle for UI feedback
            currentValues.snapAngle = finalRotationDelta * 180 / Float.pi // Convert to degrees for display
            
            // Debug feedback for snapping
            let snapDegrees = finalRotationDelta * 180 / Float.pi
            if abs(finalRotationDelta - baseTotalRotationDelta) > 0.01 { // Only log when actually snapping
                print("🔒 SNAP: \(baseTotalRotationDelta * 180 / Float.pi)° → \(snapDegrees)°")
            }
        } else {
            currentValues.snapAngle = nil
        }
        
        for obj in objects {
            guard let originalRot = originalRotations[obj.id] else { continue }
            
            var newRotation = originalRot
            
            switch axis {
            case .free, .y:
                newRotation.y += CGFloat(finalRotationDelta)
            case .x:
                newRotation.x += CGFloat(finalRotationDelta)
            case .z:
                newRotation.z += CGFloat(finalRotationDelta)
            }
            
            obj.rotation = newRotation
            obj.updateNodeTransform()
        }
    }
    
    private func updateScaleTransform(deltaX: Float, deltaY: Float, objects: [StudioObject]) {
        let totalDelta = Float(lastMousePos.x - startMousePos.x) * 0.005 // Much more sensitive (was 0.01)
        let scaleFactor = max(0.05, 1.0 + totalDelta) // Allow scaling down to 5% of original size
        
        for obj in objects {
            guard let originalScale = originalScales[obj.id] else { continue }
            
            var newScale = originalScale
            
            switch axis {
            case .free:
                newScale = SCNVector3(
                    originalScale.x * CGFloat(scaleFactor),
                    originalScale.y * CGFloat(scaleFactor),
                    originalScale.z * CGFloat(scaleFactor)
                )
            case .x:
                newScale.x = originalScale.x * CGFloat(scaleFactor)
            case .y:
                newScale.y = originalScale.y * CGFloat(scaleFactor)
            case .z:
                newScale.z = originalScale.z * CGFloat(scaleFactor)
            }
            
            obj.scale = newScale
            obj.updateNodeTransform()
        }
    }
    
    private func updateCurrentValues(from objects: [StudioObject]) {
        guard let firstObj = objects.first else { return }
        
        currentValues.position = firstObj.position
        currentValues.rotation = firstObj.rotation
        currentValues.scale = firstObj.scale
        
        // Calculate delta from original
        if let originalPos = originalPositions[firstObj.id] {
            currentValues.delta = SCNVector3(
                firstObj.position.x - originalPos.x,
                firstObj.position.y - originalPos.y,
                firstObj.position.z - originalPos.z
            )
        }
        
        // Note: snapAngle is set in the rotation methods, don't reset it here
    }
    
    private func clearStoredValues() {
        originalPositions.removeAll()
        originalRotations.removeAll()
        originalScales.removeAll()
    }
    
    // MARK: - Visual Axis Gizmos
    
    private func updateAxisGizmos() {
        clearAxisGizmos()
        
        guard isActive, axis != .free, let scene = scene else { return }
        
        // Create axis constraint lines for each selected object
        for obj in selectedObjects {
            let gizmoNode = createAxisGizmo(for: obj, axis: axis)
            scene.rootNode.addChildNode(gizmoNode)
            axisGizmoNodes.append(gizmoNode)
        }
    }
    
    private func createAxisGizmo(for object: StudioObject, axis: TransformAxis) -> SCNNode {
        let gizmoNode = SCNNode()
        gizmoNode.name = "transform_gizmo_\(object.id.uuidString)"
        
        // CRITICAL: Set initial position to object's current position
        gizmoNode.position = object.position
        
        // Create the constraint line geometry
        let lineLength: CGFloat = 30.0
        let lineGeometry = SCNCylinder(radius: 0.03, height: lineLength)
        
        let lineMaterial = SCNMaterial()
        lineMaterial.diffuse.contents = axis.color
        lineMaterial.emission.contents = axis.color.withAlphaComponent(0.6)
        lineMaterial.emission.intensity = 2.0
        lineMaterial.transparency = 0.9
        lineMaterial.isDoubleSided = true
        
        lineGeometry.materials = [lineMaterial]
        
        let lineNode = SCNNode(geometry: lineGeometry)
        lineNode.position = SCNVector3Zero // Centered within the gizmo node
        
        // Orient the line based on axis
        switch axis {
        case .x:
            lineNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2) // Rotate to X-axis
        case .y:
            // Y-axis is default (vertical)
            lineNode.eulerAngles = SCNVector3Zero
        case .z:
            lineNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0) // Rotate to Z-axis
        case .free:
            break // Should not happen
        }
        
        gizmoNode.addChildNode(lineNode)
        
        // Create arrow indicators
        let arrowGeometry = SCNCone(topRadius: 0, bottomRadius: 0.15, height: 0.5)
        let arrowMaterial = SCNMaterial()
        arrowMaterial.diffuse.contents = axis.color
        arrowMaterial.emission.contents = axis.color.withAlphaComponent(0.8)
        arrowMaterial.emission.intensity = 2.5
        arrowGeometry.materials = [arrowMaterial]
        
        // Positive direction arrow
        let positiveArrow = SCNNode(geometry: arrowGeometry)
        positiveArrow.position = SCNVector3(0, Float(lineLength/2 + 0.25), 0)
        lineNode.addChildNode(positiveArrow)
        
        // Negative direction arrow
        let negativeArrow = SCNNode(geometry: arrowGeometry)
        negativeArrow.position = SCNVector3(0, -Float(lineLength/2 + 0.25), 0)
        negativeArrow.eulerAngles = SCNVector3(Float.pi, 0, 0)
        lineNode.addChildNode(negativeArrow)
        
        print("✨ Created axis gizmo for \(axis.label) at object position \(object.position)")
        return gizmoNode
    }
    
    private func clearAxisGizmos() {
        for gizmoNode in axisGizmoNodes {
            gizmoNode.removeFromParentNode()
        }
        axisGizmoNodes.removeAll()
    }
    
    private func updateGizmoPositions() {
        // Update gizmo positions to follow the transformed objects
        guard axisGizmoNodes.count == selectedObjects.count else {
            print("⚠️ Gizmo count mismatch: \(axisGizmoNodes.count) gizmos, \(selectedObjects.count) objects")
            return
        }
        
        for (index, obj) in selectedObjects.enumerated() {
            if index < axisGizmoNodes.count {
                let gizmo = axisGizmoNodes[index]
                
                // CRITICAL FIX: Set the gizmo position to match the object's current position
                gizmo.position = obj.position
                
                print("🎯 Updated gizmo \(index) position to match object at \(obj.position)")
            }
        }
    }
    
    // MARK: - Mouse Interaction
    
    func handleMouseDown(at point: CGPoint, on object: StudioObject?) -> Bool {
        // Check if clicking on a selected object while in constraint mode
        if axis != .free, let object = object, selectedObjects.contains(where: { $0.id == object.id }) {
            dragStartPoint = point
            startMousePos = point
            lastMousePos = point
            isDragging = false // Will become true after minimum drag distance
            return true // Consume the click
        }
        return false // Let normal selection handling proceed
    }
    
    func handleMouseDrag(to point: CGPoint) {
        guard axis != .free && !selectedObjects.isEmpty else { return }
        
        let dragDistance = sqrt(pow(point.x - dragStartPoint.x, 2) + pow(point.y - dragStartPoint.y, 2))
        
        if !isDragging && dragDistance > minimumDragDistance {
            // Start dragging - enter transform mode
            isDragging = true
            isActive = true
            startMousePos = dragStartPoint
            lastMousePos = dragStartPoint
            
            // Store original values
            originalPositions.removeAll()
            originalRotations.removeAll()
            originalScales.removeAll()
            
            for obj in selectedObjects {
                originalPositions[obj.id] = obj.position
                originalRotations[obj.id] = obj.rotation
                originalScales[obj.id] = obj.scale
            }
            
            updateAxisGizmos()
        }
        
        if isDragging {
            updateTransformWithMouse(mousePos: point)
        }
    }
    
    func handleMouseUp() {
        if isDragging {
            // Automatically confirm transform when mouse is released
            confirmTransform()
        }
        isDragging = false
    }
    
    // MARK: - Mouse-Based Transform System
    
    var isMouseTransformActive: Bool {
        return isActive && axis != .free
    }
    
    func startMouseTransform(_ mode: TransformMode, objects: [StudioObject], mousePosition: CGPoint, scene: SCNScene) {
        guard !objects.isEmpty else { return }
        
        self.mode = mode
        self.isActive = true
        self.selectedObjects = objects
        self.scene = scene
        self.startMousePos = mousePosition
        self.lastMousePos = mousePosition
        
        // Store original values
        originalPositions.removeAll()
        originalRotations.removeAll()
        originalScales.removeAll()
        
        for obj in objects {
            originalPositions[obj.id] = obj.position
            originalRotations[obj.id] = obj.rotation
            originalScales[obj.id] = obj.scale
        }
        
        updateCurrentValues(from: objects)
        updateAxisGizmos()
        
        print("🎯 Started mouse transform: \(mode.rawValue) on \(axis.label) for \(objects.count) objects")
    }
    
    func updateMouseTransform(mousePosition: CGPoint) {
        guard isActive else { return }
        
        let deltaX = Float(mousePosition.x - startMousePos.x) * 0.01
        let deltaY = Float(startMousePos.y - mousePosition.y) * 0.01 // Invert Y
        
        switch mode {
        case .move:
            updateMouseMoveTransform(deltaX: deltaX, deltaY: deltaY)
        case .rotate:
            updateMouseRotateTransform(deltaX: deltaX, deltaY: deltaY)
        case .scale:
            updateMouseScaleTransform(deltaX: deltaX, deltaY: deltaY)
        }
        
        updateCurrentValues(from: selectedObjects)
        updateGizmoPositions()
    }
    
    private func updateMouseMoveTransform(deltaX: Float, deltaY: Float) {
        for obj in selectedObjects {
            guard let originalPos = originalPositions[obj.id] else { continue }
            
            var newPosition = originalPos
            
            switch axis {
            case .x:
                newPosition.x += CGFloat(deltaX)
            case .y:
                newPosition.y += CGFloat(deltaY)
            case .z:
                newPosition.z += CGFloat(deltaX) // Use X mouse movement for Z
            case .free:
                newPosition.x += CGFloat(deltaX)
                newPosition.y += CGFloat(deltaY)
            }
            
            obj.position = newPosition
            obj.updateNodeTransform()
        }
    }
    
    private func updateMouseRotateTransform(deltaX: Float, deltaY: Float) {
        let baseRotationAmount = deltaX * Float.pi / 2 // Base rotation sensitivity
        
        var finalRotationAmount = baseRotationAmount
        
        // Apply snapping if Shift is held
        if isSnapMode {
            let snapIncrement = snapAngleIncrement
            finalRotationAmount = round(baseRotationAmount / snapIncrement) * snapIncrement
            
            // Store snap angle for UI feedback
            currentValues.snapAngle = finalRotationAmount * 180 / Float.pi
            
            // Debug feedback
            let snapDegrees = finalRotationAmount * 180 / Float.pi
            if abs(finalRotationAmount - baseRotationAmount) > 0.01 {
                print("🔒 MOUSE SNAP: \(baseRotationAmount * 180 / Float.pi)° → \(snapDegrees)°")
            }
        } else {
            currentValues.snapAngle = nil
        }
        
        for obj in selectedObjects {
            guard let originalRot = originalRotations[obj.id] else { continue }
            
            var newRotation = originalRot
            
            switch axis {
            case .x:
                newRotation.x += CGFloat(finalRotationAmount)
            case .y:
                newRotation.y += CGFloat(finalRotationAmount)
            case .z:
                newRotation.z += CGFloat(finalRotationAmount)
            case .free:
                newRotation.y += CGFloat(finalRotationAmount)
            }
            
            obj.rotation = newRotation
            obj.updateNodeTransform()
        }
    }
    
    private func updateMouseScaleTransform(deltaX: Float, deltaY: Float) {
        let scaleFactor = max(0.1, 1.0 + deltaX)
        
        for obj in selectedObjects {
            guard let originalScale = originalScales[obj.id] else { continue }
            
            var newScale = originalScale
            
            switch axis {
            case .x:
                newScale.x = originalScale.x * CGFloat(scaleFactor)
            case .y:
                newScale.y = originalScale.y * CGFloat(scaleFactor)
            case .z:
                newScale.z = originalScale.z * CGFloat(scaleFactor)
            case .free:
                newScale = SCNVector3(
                    originalScale.x * CGFloat(scaleFactor),
                    originalScale.y * CGFloat(scaleFactor),
                    originalScale.z * CGFloat(scaleFactor)
                )
            }
            
            obj.scale = newScale
            obj.updateNodeTransform()
        }
    }
    
    // MARK: - Keyboard Arrow Key Support - SIMPLIFIED VERSION
    
    func nudgeObjects(_ direction: NudgeDirection, amount: Float = 0.1) {
        guard isActive && !selectedObjects.isEmpty else { 
            print("⚠️ Cannot nudge: isActive=\(isActive), objects=\(selectedObjects.count)")
            return 
        }
        
        print("🎯 Nudging \(selectedObjects.count) objects \(direction.description) by \(amount) on axis \(axis.label)")
        
        for obj in selectedObjects {
            let originalPosition = obj.position
            var newPosition = obj.position
            var moved = false
            
            switch direction {
            case .up:
                if axis == .free || axis == .y {
                    newPosition.y += CGFloat(amount)
                    moved = true
                    print("   Y+ nudge: \(originalPosition.y) → \(newPosition.y)")
                } else if axis == .z {
                    // When Z-axis is constrained, up/down arrows control Z movement
                    newPosition.z += CGFloat(amount)
                    moved = true
                    print("   Z+ nudge (via up arrow): \(originalPosition.z) → \(newPosition.z)")
                }
                
            case .down:
                if axis == .free || axis == .y {
                    newPosition.y -= CGFloat(amount)
                    moved = true
                    print("   Y- nudge: \(originalPosition.y) → \(newPosition.y)")
                } else if axis == .z {
                    // When Z-axis is constrained, up/down arrows control Z movement
                    newPosition.z -= CGFloat(amount)
                    moved = true
                    print("   Z- nudge (via down arrow): \(originalPosition.z) → \(newPosition.z)")
                }
                
            case .left:
                if axis == .free || axis == .x {
                    newPosition.x -= CGFloat(amount)
                    moved = true
                    print("   X- nudge: \(originalPosition.x) → \(newPosition.x)")
                }
                
            case .right:
                if axis == .free || axis == .x {
                    newPosition.x += CGFloat(amount)
                    moved = true
                    print("   X+ nudge: \(originalPosition.x) → \(newPosition.x)")
                }
                
            case .forward, .backward:
                // These are no longer needed since we use up/down for Z
                if axis == .free || axis == .z {
                    let zDelta = direction == .forward ? amount : -amount
                    newPosition.z += CGFloat(zDelta)
                    moved = true
                    print("   Z nudge: \(originalPosition.z) → \(newPosition.z)")
                }
            }
            
            if moved {
                obj.position = newPosition
                obj.updateNodeTransform()
            } else {
                print("   Movement blocked by axis constraint: \(axis.label)")
            }
        }
        
        updateCurrentValues(from: selectedObjects)
        updateGizmoPositions() // This should now work correctly
        
        print("✅ Nudge complete - gizmos updated")
    }
    
    private func updateSnapMode() {
        let wasSnapMode = isSnapMode
        isSnapMode = NSEvent.modifierFlags.contains(.shift)
        
        // Provide feedback when entering/exiting snap mode
        if isSnapMode != wasSnapMode {
            if isSnapMode {
                switch mode {
                case .rotate:
                    print("🔒 SNAP MODE: Rotation will snap to \(Int(snapAngleIncrement * 180 / Float.pi))° increments")
                case .move:
                    print("🔒 SNAP MODE: Movement will snap to grid")
                case .scale:
                    print("🔒 SNAP MODE: Scale will snap to increments")
                }
            } else {
                print("🔓 FREE MODE: No snapping")
            }
        }
    }
    
    func startDistanceBasedScaling(_ objects: [StudioObject], startPoint: CGPoint, scene: SCNScene) {
        guard !objects.isEmpty else {
            print("⚠️ No objects selected for distance-based scaling")
            return
        }
        
        mode = .scale
        axis = .free
        isActive = true
        isDistanceScaling = true
        selectedObjects = objects
        self.scene = scene
        scaleStartMousePos = startPoint
        scaleReferenceDistance = 100.0 // Initial reference distance
        
        // Store original scale values
        originalScales.removeAll()
        initialScaleFactors.removeAll()
        
        for obj in objects {
            originalScales[obj.id] = obj.scale
            initialScaleFactors[obj.id] = obj.scale
        }
        
        updateCurrentValues(from: objects)
        updateAxisGizmos()
        
        print("📏 Started distance-based scaling for \(objects.count) objects")
        print("   Reference distance: \(scaleReferenceDistance)px")
    }
    
    func updateDistanceBasedScaling(currentMousePos: CGPoint) {
        guard isActive && isDistanceScaling else { return }
        
        // Calculate distance from start point
        let deltaX = currentMousePos.x - scaleStartMousePos.x
        let deltaY = currentMousePos.y - scaleStartMousePos.y
        let currentDistance = sqrt(deltaX * deltaX + deltaY * deltaY)
        
        // Calculate scale factor based on distance change
        // Moving away from start = scale up
        // Moving toward start = scale down
        let distanceRatio = currentDistance / scaleReferenceDistance
        let scaleFactor = max(0.1, distanceRatio) // Minimum 10% scale
        
        // Apply distance-based scaling
        for obj in selectedObjects {
            guard let originalScale = originalScales[obj.id] else { continue }
            
            var newScale = originalScale
            
            switch axis {
            case .free:
                newScale = SCNVector3(
                    originalScale.x * CGFloat(scaleFactor),
                    originalScale.y * CGFloat(scaleFactor),
                    originalScale.z * CGFloat(scaleFactor)
                )
            case .x:
                newScale.x = originalScale.x * CGFloat(scaleFactor)
            case .y:
                newScale.y = originalScale.y * CGFloat(scaleFactor)
            case .z:
                newScale.z = originalScale.z * CGFloat(scaleFactor)
            }
            
            obj.scale = newScale
            obj.updateNodeTransform()
        }
        
        // Update UI values
        updateCurrentValues(from: selectedObjects)
        updateGizmoPositions()
        
        // Debug output (limit frequency)
        if Int(currentDistance) % 10 == 0 {
            print("📏 Distance scaling: \(String(format: "%.0f", currentDistance))px → \(String(format: "%.2f", scaleFactor))x")
        }
    }
    
    func confirmDistanceScaling() {
        guard isDistanceScaling else { return }
        
        // Finalize the scaling
        for obj in selectedObjects {
            obj.updateNodeTransform() // Ensure the node reflects the current object state
        }
        
        isActive = false
        isDistanceScaling = false
        clearAxisGizmos()
        clearStoredValues()
        
        print("✅ Distance-based scaling confirmed")
    }
    
    func cancelDistanceScaling() {
        guard isDistanceScaling else { return }
        
        // Restore original scale values
        for obj in selectedObjects {
            if let originalScale = originalScales[obj.id] {
                obj.scale = originalScale
                obj.updateNodeTransform()
            }
        }
        
        isActive = false
        isDistanceScaling = false
        clearAxisGizmos()
        clearStoredValues()
        
        print("❌ Distance-based scaling cancelled")
    }
    
    enum NudgeDirection {
        case up, down, left, right, forward, backward
        
        var description: String {
            switch self {
            case .up: return "up"
            case .down: return "down"
            case .left: return "left"
            case .right: return "right"  
            case .forward: return "forward"
            case .backward: return "backward"
            }
        }
    }
}

// MARK: - Transform UI Overlay

struct TransformOverlay: View {
    @ObservedObject var controller: TransformController
    let selectedObjects: [StudioObject]
    
    var body: some View {
        if controller.isActive {
            VStack {
                Spacer()
                
                // Beautiful transform information panel
                VStack(alignment: .leading, spacing: 12) {
                    // Header with mode and object count
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: iconForMode(controller.mode))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(controller.axis.color.swiftUIColor)
                            
                            Text(modeDisplayName)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            // Distance scaling indicator
                            if controller.isDistanceScaling {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                        .font(.caption)
                                        .foregroundColor(.cyan)
                                    Text("DISTANCE")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.cyan)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.2))
                                .cornerRadius(4)
                            }
                            
                            // Snap mode indicator
                            if controller.isSnapMode && !controller.isDistanceScaling {
                                HStack(spacing: 4) {
                                    Image(systemName: "magnet.fill")
                                        .font(.caption)
                                        .foregroundColor(.yellow)
                                    Text("SNAP")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.yellow)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.2))
                                .cornerRadius(4)
                            }
                        }
                        
                        Spacer()
                        
                        Text("\(selectedObjects.count) object\(selectedObjects.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    // Axis constraint indicator (only show if not in distance scaling mode)
                    if !controller.isDistanceScaling {
                        HStack {
                            Text("Constraint:")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(controller.axis.color.swiftUIColor)
                                    .frame(width: 8, height: 8)
                                
                                Text(controller.axis.label)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(controller.axis.color.swiftUIColor)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(controller.axis.color.swiftUIColor.opacity(0.2))
                            .cornerRadius(4)
                            
                            Spacer()
                            
                            // Show snap angle for rotation
                            if controller.mode == .rotate, 
                               let snapAngle = controller.currentValues.snapAngle,
                               controller.isSnapMode {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                        .foregroundColor(.yellow)
                                    Text("\(snapAngle, specifier: "%.0f")°")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.yellow)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.2))
                                .cornerRadius(4)
                            }
                        }
                    }
                    
                    // Current values with beautiful formatting
                    VStack(alignment: .leading, spacing: 4) {
                        if controller.mode == .rotate {
                            // Show rotation values in degrees for better readability
                            let rotDegX = Float(controller.currentValues.rotation.x) * 180.0 / Float.pi
                            let rotDegY = Float(controller.currentValues.rotation.y) * 180.0 / Float.pi
                            let rotDegZ = Float(controller.currentValues.rotation.z) * 180.0 / Float.pi
                            
                            HStack {
                                Text("Rotation:")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Spacer()
                                
                                Text("(\(rotDegX, specifier: "%.1f")°, \(rotDegY, specifier: "%.1f")°, \(rotDegZ, specifier: "%.1f")°)")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.white)
                            }
                        } else {
                            HStack {
                                Text(controller.mode == .scale ? "Scale:" : "Position:")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Spacer()
                                
                                if controller.mode == .scale {
                                    let scale = controller.currentValues.scale
                                    Text("(\(scale.x, specifier: "%.2f"), \(scale.y, specifier: "%.2f"), \(scale.z, specifier: "%.2f"))")
                                        .font(.caption.monospaced())
                                        .foregroundColor(.white)
                                } else {
                                    let pos = controller.currentValues.position
                                    Text("(\(pos.x, specifier: "%.2f"), \(pos.y, specifier: "%.2f"), \(pos.z, specifier: "%.2f"))")
                                        .font(.caption.monospaced())
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        
                        HStack {
                            Text("Delta:")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.yellow.opacity(0.7))
                            
                            Spacer()
                            
                            Text("(\(controller.currentValues.delta.x, specifier: "%.2f"), \(controller.currentValues.delta.y, specifier: "%.2f"), \(controller.currentValues.delta.z, specifier: "%.2f"))")
                                .font(.caption.monospaced())
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    // Enhanced instructions with distance scaling info
                    VStack(alignment: .leading, spacing: 2) {
                        if controller.isDistanceScaling {
                            Text("Distance Scale: Move cursor closer to shrink, farther to grow")
                                .font(.caption2)
                                .foregroundColor(.cyan.opacity(0.8))
                            Text("X/Y/Z: Constrain axis • Enter: Lock scale • Esc: Cancel")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        } else if controller.mode == .rotate {
                            Text("Mouse: Rotate • Shift: Snap to 15° increments • Arrow keys: Nudge")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                            Text("X/Y/Z: Constrain axis • Enter: Confirm • Esc: Cancel")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        } else {
                            Text("Mouse: Transform • Shift: Snap mode • Arrow keys: Nudge")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                            Text("X/Y/Z: Constrain axis • Enter: Confirm • Esc: Cancel")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.85))
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            controller.isDistanceScaling ? Color.cyan : 
                            (controller.isSnapMode ? Color.yellow : controller.axis.color.swiftUIColor), 
                            lineWidth: 2
                        )
                )
                .shadow(
                    color: (controller.isDistanceScaling ? Color.cyan : 
                           (controller.isSnapMode ? Color.yellow : controller.axis.color.swiftUIColor)).opacity(0.3), 
                    radius: 8
                )
            }
            .padding(20)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.axis)
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: controller.isSnapMode)
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: controller.isDistanceScaling)
        }
    }
    
    private var modeDisplayName: String {
        if controller.isDistanceScaling {
            return "Distance Scale"
        } else {
            return controller.mode.rawValue.capitalized
        }
    }
    
    private func iconForMode(_ mode: TransformController.TransformMode) -> String {
        switch mode {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: return "arrow.clockwise"
        case .scale: return controller.isDistanceScaling ? "arrow.up.left.and.down.right.magnifyingglass" : "arrow.up.left.and.down.right.magnifyingglass"
        }
    }
}

// Extension to convert NSColor to SwiftUI Color
extension NSColor {
    var swiftUIColor: Color {
        Color(self)
    }
}
