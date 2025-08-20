//
//  AxisGizmo.swift
//  Vistaview - Camera-Synced 3D Compass
//

import SwiftUI
import SceneKit

struct AxisGizmo: View {
    @State private var cameraRotation: SCNMatrix4 = SCNMatrix4Identity
    @State private var hoveredAxis: AxisType? = nil
    
    enum AxisType {
        case x, y, z
        
        var color: Color {
            switch self {
            case .x: return .red
            case .y: return .green  
            case .z: return .blue
            }
        }
        
        var label: String {
            switch self {
            case .x: return "X"
            case .y: return "Y"
            case .z: return "Z"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Background Circle
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            
            // Rotation indicator ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 70, height: 70)
            
            // Camera-synced axes
            CameraSyncedAxes(
                cameraRotation: cameraRotation,
                hoveredAxis: $hoveredAxis,
                onAxisTap: snapToView
            )
            
            // Center Origin Point
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(Color.gray, lineWidth: 1)
                )
                .onTapGesture {
                    snapToView(.home)
                }
            
            // View Mode Indicator
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("PERSP")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.trailing, 4)
                        .padding(.bottom, 4)
                }
            }
        }
        .frame(width: 80, height: 80)
        .animation(.easeInOut(duration: 0.15), value: hoveredAxis)
        .onReceive(NotificationCenter.default.publisher(for: .cameraDidMove)) { notification in
            if let matrix = notification.object as? SCNMatrix4 {
                withAnimation(.easeInOut(duration: 0.1)) {
                    cameraRotation = matrix
                }
            }
        }
    }
    
    private func snapToView(_ view: ViewType) {
        // Post notification to update camera
        NotificationCenter.default.post(
            name: .snapToView,
            object: view
        )
        
        // Add haptic feedback
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }
    
    enum ViewType {
        case front, top, right, home
    }
}

struct CameraSyncedAxes: View {
    let cameraRotation: SCNMatrix4
    @Binding var hoveredAxis: AxisGizmo.AxisType?
    let onAxisTap: (AxisGizmo.ViewType) -> Void
    
    var body: some View {
        // Calculate axis directions based on camera rotation
        let xAxis = axisDirection(.x)
        let yAxis = axisDirection(.y)
        let zAxis = axisDirection(.z)
        
        ZStack {
            // X Axis (Red)
            AxisLine(
                direction: xAxis,
                axis: .x,
                isHovered: hoveredAxis == .x,
                onTap: { onAxisTap(.right) },
                onHover: { hovering in
                    hoveredAxis = hovering ? .x : nil
                }
            )
            
            // Y Axis (Green)
            AxisLine(
                direction: yAxis,
                axis: .y,
                isHovered: hoveredAxis == .y,
                onTap: { onAxisTap(.top) },
                onHover: { hovering in
                    hoveredAxis = hovering ? .y : nil
                }
            )
            
            // Z Axis (Blue)
            AxisLine(
                direction: zAxis,
                axis: .z,
                isHovered: hoveredAxis == .z,
                onTap: { onAxisTap(.front) },
                onHover: { hovering in
                    hoveredAxis = hovering ? .z : nil
                }
            )
        }
    }
    
    private func axisDirection(_ axis: AxisGizmo.AxisType) -> CGPoint {
        // Extract axis direction from camera rotation matrix
        let matrix = cameraRotation
        
        switch axis {
        case .x:
            // X axis direction (right vector)
            let x = matrix.m11
            let y = -matrix.m21 // Flip Y for screen coordinates
            return CGPoint(x: x * 25, y: y * 25)
            
        case .y:
            // Y axis direction (up vector)
            let x = matrix.m12
            let y = -matrix.m22 // Flip Y for screen coordinates
            return CGPoint(x: x * 25, y: y * 25)
            
        case .z:
            // Z axis direction (forward vector)
            let x = matrix.m13
            let y = -matrix.m23 // Flip Y for screen coordinates
            return CGPoint(x: x * 25, y: y * 25)
        }
    }
}

struct AxisLine: View {
    let direction: CGPoint
    let axis: AxisGizmo.AxisType
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        ZStack {
            // Axis Line
            Rectangle()
                .fill(isHovered ? axis.color.opacity(0.8) : axis.color)
                .frame(width: max(2, sqrt(direction.x * direction.x + direction.y * direction.y)), height: 3)
                .rotationEffect(.radians(atan2(direction.y, direction.x)))
                .offset(x: direction.x / 2, y: direction.y / 2)
            
            // Arrow Head
            Triangle()
                .fill(isHovered ? axis.color.opacity(0.8) : axis.color)
                .frame(width: 6, height: 6)
                .rotationEffect(.radians(atan2(direction.y, direction.x)))
                .offset(x: direction.x, y: direction.y)
            
            // Axis Label
            Text(axis.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isHovered ? .white : axis.color)
                .offset(x: direction.x * 1.3, y: direction.y * 1.3)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 16, height: 16)
                        .opacity(isHovered ? 1 : 0)
                )
            
            // Invisible tap area
            Circle()
                .fill(Color.clear)
                .frame(width: 20, height: 20)
                .offset(x: direction.x, y: direction.y)
                .onTapGesture(perform: onTap)
                .onHover(perform: onHover)
        }
    }
}

// Triangle shape for arrow heads
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let cameraDidMove = Notification.Name("cameraDidMove")
    static let snapToView = Notification.Name("snapToView")
}

enum ViewType {
    case front, top, right, home
}