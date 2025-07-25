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
    
    private var originalPositions: [UUID: SCNVector3] = [:]
    private var originalRotations: [UUID: SCNVector3] = [:]
    private var originalScales: [UUID: SCNVector3] = [:]
    private var startMousePos: CGPoint = .zero
    private var lastMousePos: CGPoint = .zero
    private var accumulator: Float = 0.0
    
    // Visual gizmo nodes for axis constraints
    private var axisGizmoNodes: [SCNNode] = []
    private weak var scene: SCNScene?
    
    // Mouse interaction state
    private var dragStartPoint: CGPoint = .zero
    private var minimumDragDistance: CGFloat = 5.0 // Pixels to start drag
    
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
            case .move: return "Move: Mouse to position, X/Y/Z to constrain, Enter to confirm, Esc to cancel"
            case .rotate: return "Rotate: Mouse to rotate, X/Y/Z to constrain, Enter to confirm, Esc to cancel"
            case .scale: return "Scale: Mouse to scale, X/Y/Z to constrain, Enter to confirm, Esc to cancel"
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
        
        let deltaX = Float(mousePos.x - lastMousePos.x) * 0.01
        let deltaY = Float(lastMousePos.y - mousePos.y) * 0.01 // Invert Y
        
        switch mode {
        case .move:
            updateMoveTransform(deltaX: deltaX, deltaY: deltaY, objects: selectedObjects)
        case .rotate:
            updateRotateTransform(deltaX: deltaX, deltaY: deltaY, objects: selectedObjects)
        case .scale:
            updateScaleTransform(deltaX: deltaX, deltaY: deltaY, objects: selectedObjects)
        }
        
        lastMousePos = mousePos
        updateCurrentValues(from: selectedObjects)
        updateAxisGizmos()
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
            let totalDeltaX = Float(lastMousePos.x - startMousePos.x) * 0.005 // More sensitive (was 0.01)
            let totalDeltaY = Float(startMousePos.y - lastMousePos.y) * 0.005 // More sensitive (was 0.01)
            
            switch axis {
            case .free:
                newPosition.x += CGFloat(totalDeltaX)
                newPosition.y += CGFloat(totalDeltaY)
            case .x:
                newPosition.x += CGFloat(totalDeltaX)
            case .y:
                newPosition.y += CGFloat(totalDeltaY)
            case .z:
                newPosition.z += CGFloat(totalDeltaX) // Use X mouse movement for Z
            }
            
            obj.position = newPosition
            obj.updateNodeTransform()
        }
        
        // Update gizmo positions to follow the objects
        updateGizmoPositions()
    }
    
    private func updateRotateTransform(deltaX: Float, deltaY: Float, objects: [StudioObject]) {
        let totalRotationDelta = Float(lastMousePos.x - startMousePos.x) * Float.pi / 180 * 0.25 // More sensitive (was 0.5)
        
        for obj in objects {
            guard let originalRot = originalRotations[obj.id] else { continue }
            
            var newRotation = originalRot
            
            switch axis {
            case .free, .y:
                newRotation.y += CGFloat(totalRotationDelta)
            case .x:
                newRotation.x += CGFloat(totalRotationDelta)
            case .z:
                newRotation.z += CGFloat(totalRotationDelta)
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
        
        // Create the constraint line
        let lineGeometry = SCNCylinder(radius: 0.02, height: 20) // Long thin cylinder as line
        let lineMaterial = SCNMaterial()
        lineMaterial.diffuse.contents = axis.color
        lineMaterial.emission.contents = axis.color.withAlphaComponent(0.3)
        lineGeometry.materials = [lineMaterial]
        
        let lineNode = SCNNode(geometry: lineGeometry)
        
        // Position and orient the line based on axis
        lineNode.position = object.position
        
        switch axis {
        case .x:
            lineNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2) // Rotate to X-axis
        case .y:
            // Y-axis is default (vertical)
            break
        case .z:
            lineNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0) // Rotate to Z-axis
        case .free:
            break // Should not happen
        }
        
        gizmoNode.addChildNode(lineNode)
        
        // Add small arrow indicators at the ends
        let arrowGeometry = SCNCone(topRadius: 0, bottomRadius: 0.1, height: 0.3)
        let arrowMaterial = SCNMaterial()
        arrowMaterial.diffuse.contents = axis.color
        arrowGeometry.materials = [arrowMaterial]
        
        // Positive direction arrow
        let positiveArrow = SCNNode(geometry: arrowGeometry)
        positiveArrow.position = SCNVector3(0, 10.15, 0) // At the top of the line
        lineNode.addChildNode(positiveArrow)
        
        // Negative direction arrow (flipped)
        let negativeArrow = SCNNode(geometry: arrowGeometry)
        negativeArrow.position = SCNVector3(0, -10.15, 0)
        negativeArrow.eulerAngles = SCNVector3(Float.pi, 0, 0) // Flip it
        lineNode.addChildNode(negativeArrow)
        
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
        for (index, obj) in selectedObjects.enumerated() {
            if index < axisGizmoNodes.count {
                axisGizmoNodes[index].position = obj.position
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
}

// MARK: - Transform UI Overlay

struct TransformOverlay: View {
    @ObservedObject var controller: TransformController
    let selectedObjects: [StudioObject]
    
    var body: some View {
        if controller.isActive {
            VStack {
                Spacer()
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        // Mode and axis indicator
                        HStack(spacing: 8) {
                            Text(controller.mode.instruction)
                                .font(.caption)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text("Axis: \(controller.axis.label)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(controller.axis.color.swiftUIColor)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                        
                        // Current values
                        HStack(spacing: 16) {
                            Text("Pos: (\(controller.currentValues.position.x, specifier: "%.2f"), \(controller.currentValues.position.y, specifier: "%.2f"), \(controller.currentValues.position.z, specifier: "%.2f"))")
                                .font(.caption)
                                .foregroundColor(.white)
                            
                            Text("Delta: (\(controller.currentValues.delta.x, specifier: "%.2f"), \(controller.currentValues.delta.y, specifier: "%.2f"), \(controller.currentValues.delta.z, specifier: "%.2f"))")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    Spacer()
                }
                .padding(12)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(controller.axis.color.swiftUIColor, lineWidth: 2)
                )
            }
            .padding(16)
        }
    }
}

// Extension to convert NSColor to SwiftUI Color
extension NSColor {
    var swiftUIColor: Color {
        Color(self)
    }
}