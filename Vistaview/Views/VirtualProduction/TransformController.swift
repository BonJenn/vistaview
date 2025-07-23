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
    
    private var originalPositions: [UUID: SCNVector3] = [:]
    private var originalRotations: [UUID: SCNVector3] = [:]
    private var originalScales: [UUID: SCNVector3] = [:]
    private var startMousePos: CGPoint = .zero
    private var accumulator: Float = 0.0
    
    enum TransformMode {
        case move, rotate, scale
        
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
    
    func startTransform(_ newMode: TransformMode, objects: [StudioObject], startPoint: CGPoint) {
        guard !objects.isEmpty else { return }
        
        mode = newMode
        axis = .free
        isActive = true
        startMousePos = startPoint
        accumulator = 0.0
        
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
    }
    
    func updateTransform(mousePos: CGPoint, objects: [StudioObject]) {
        guard isActive else { return }
        
        let deltaX = Float(mousePos.x - startMousePos.x) * 0.01
        let deltaY = Float(startMousePos.y - mousePos.y) * 0.01 // Invert Y
        
        switch mode {
        case .move:
            updateMoveTransform(deltaX: deltaX, deltaY: deltaY, objects: objects)
        case .rotate:
            updateRotateTransform(deltaX: deltaX, deltaY: deltaY, objects: objects)
        case .scale:
            updateScaleTransform(deltaX: deltaX, deltaY: deltaY, objects: objects)
        }
        
        updateCurrentValues(from: objects)
    }
    
    func setAxis(_ newAxis: TransformAxis) {
        axis = newAxis
    }
    
    func confirmTransform() {
        isActive = false
        clearStoredValues()
    }
    
    func cancelTransform(objects: [StudioObject]) {
        // Restore original values
        for obj in objects {
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
    }
    
    private func updateRotateTransform(deltaX: Float, deltaY: Float, objects: [StudioObject]) {
        let rotationDelta = deltaX * Float.pi / 180 * 10 // Convert to radians, scale
        
        for obj in objects {
            guard let originalRot = originalRotations[obj.id] else { continue }
            
            var newRotation = originalRot
            
            switch axis {
            case .free, .y:
                newRotation.y += CGFloat(rotationDelta)
            case .x:
                newRotation.x += CGFloat(rotationDelta)
            case .z:
                newRotation.z += CGFloat(rotationDelta)
            }
            
            obj.rotation = newRotation
            obj.updateNodeTransform()
        }
    }
    
    private func updateScaleTransform(deltaX: Float, deltaY: Float, objects: [StudioObject]) {
        let scaleFactor = max(0.1, 1.0 + deltaX) // Prevent negative scaling
        
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