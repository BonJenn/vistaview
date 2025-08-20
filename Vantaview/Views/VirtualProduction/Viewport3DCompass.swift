//
//  Viewport3DCompass.swift
//  Vistaview - Blender-style 3D orientation compass
//

import SwiftUI
import SceneKit

struct Viewport3DCompass: View {
    @Binding var cameraAzimuth: Float
    @Binding var cameraElevation: Float
    @Binding var cameraRoll: Float
    
    // Layout constants
    private let compassSize: CGFloat = 60
    private let axisLength: CGFloat = 20
    private let labelOffset: CGFloat = 25
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                
                VStack {
                    ZStack {
                        // Background circle
                        Circle()
                            .fill(.black.opacity(0.7))
                            .frame(width: compassSize, height: compassSize)
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.3), lineWidth: 1)
                            )
                        
                        // 3D Compass using SceneView
                        CompassSceneView(
                            cameraAzimuth: cameraAzimuth,
                            cameraElevation: cameraElevation,
                            cameraRoll: cameraRoll
                        )
                        .frame(width: compassSize, height: compassSize)
                        .clipShape(Circle())
                    }
                    
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
            
            Spacer()
        }
    }
}

struct CompassSceneView: NSViewRepresentable {
    let cameraAzimuth: Float
    let cameraElevation: Float
    let cameraRoll: Float
    
    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.rendersContinuously = true
        
        // Create the compass scene
        let scene = SCNScene()
        scnView.scene = scene
        
        // Setup camera
        setupCamera(in: scene, scnView: scnView)
        
        // Create compass axes
        createCompassAxes(in: scene)
        
        // Setup lighting
        setupLighting(in: scene)
        
        return scnView
    }
    
    func updateNSView(_ nsView: SCNView, context: Context) {
        // Update compass orientation to match main viewport camera EXACTLY like Blender
        guard let scene = nsView.scene,
              let compassCamera = scene.rootNode.childNode(withName: "compassCamera", recursively: false) else { return }
        
        // Position the compass camera to view the axes from the SAME angle as the main camera
        // This creates the Blender-like behavior where the compass shows your current viewing angle
        let distance: Float = 8.0 // Increase distance for better view
        
        // Use the SAME camera angles as the main viewport (not inverted)
        // This makes the compass axes align exactly with the viewport orientation
        let x = distance * cos(cameraElevation) * sin(cameraAzimuth)
        let y = distance * sin(cameraElevation)
        let z = distance * cos(cameraElevation) * cos(cameraAzimuth)
        
        compassCamera.position = SCNVector3(x, y, z)
        
        // Create up vector that matches the viewport camera's roll
        let sinRoll = sin(cameraRoll)
        let cosRoll = cos(cameraRoll)
        
        // Apply roll to the up vector for proper orientation
        let upVector = SCNVector3(
            CGFloat(sinRoll),
            CGFloat(cosRoll),
            0
        )
        
        compassCamera.look(at: SCNVector3(0, 0, 0), up: upVector, localFront: SCNVector3(0, 0, -1))
        
        // Update axis visibility based on viewing angle (like Blender)
        updateAxisVisibility(scene: scene)
    }
    
    private func updateAxisVisibility(scene: SCNScene) {
        // Make axes more prominent when they're facing the camera
        // and less prominent when they're facing away (depth cueing like Blender)
        
        let frontThreshold: Float = 0.5
        
        // Calculate which axes are facing the camera
        let viewDirection = SCNVector3(
            cos(cameraElevation) * sin(cameraAzimuth),
            sin(cameraElevation),
            cos(cameraElevation) * cos(cameraAzimuth)
        )
        
        // X-axis visibility
        if let xAxis = scene.rootNode.childNode(withName: "xAxis", recursively: false),
           let xLabel = scene.rootNode.childNode(withName: "xLabel", recursively: false) {
            let xDot = abs(viewDirection.x)
            let xAlpha = max(0.3, min(1.0, xDot + 0.3))
            
            updateNodeOpacity(xAxis, opacity: CGFloat(xAlpha))
            updateNodeOpacity(xLabel, opacity: CGFloat(xAlpha))
        }
        
        // Y-axis visibility
        if let yAxis = scene.rootNode.childNode(withName: "yAxis", recursively: false),
           let yLabel = scene.rootNode.childNode(withName: "yLabel", recursively: false) {
            let yDot = abs(viewDirection.y)
            let yAlpha = max(0.3, min(1.0, yDot + 0.3))
            
            updateNodeOpacity(yAxis, opacity: CGFloat(yAlpha))
            updateNodeOpacity(yLabel, opacity: CGFloat(yAlpha))
        }
        
        // Z-axis visibility
        if let zAxis = scene.rootNode.childNode(withName: "zAxis", recursively: false),
           let zLabel = scene.rootNode.childNode(withName: "zLabel", recursively: false) {
            let zDot = abs(viewDirection.z)
            let zAlpha = max(0.3, min(1.0, zDot + 0.3))
            
            updateNodeOpacity(zAxis, opacity: CGFloat(zAlpha))
            updateNodeOpacity(zLabel, opacity: CGFloat(zAlpha))
        }
    }
    
    private func updateNodeOpacity(_ node: SCNNode, opacity: CGFloat) {
        node.enumerateChildNodes { child, _ in
            if let geometry = child.geometry {
                for material in geometry.materials {
                    material.transparency = opacity
                }
            }
        }
        
        // Update node itself if it has geometry
        if let geometry = node.geometry {
            for material in geometry.materials {
                material.transparency = opacity
            }
        }
    }
    
    private func setupCamera(in scene: SCNScene, scnView: SCNView) {
        let camera = SCNCamera()
        camera.fieldOfView = 35
        camera.zNear = 0.1
        camera.zFar = 100
        camera.automaticallyAdjustsZRange = true
        
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "compassCamera"
        cameraNode.position = SCNVector3(0, 0, 5)
        
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
    }
    
    private func createCompassAxes(in scene: SCNScene) {
        // X-axis (Red)
        let xAxis = createAxisLine(color: .systemRed, startPos: SCNVector3(0, 0, 0), endPos: SCNVector3(1.5, 0, 0))
        xAxis.name = "xAxis"
        scene.rootNode.addChildNode(xAxis)
        
        // X-axis label
        let xLabel = createAxisLabel(text: "X", color: .systemRed, position: SCNVector3(1.8, 0, 0))
        xLabel.name = "xLabel"
        scene.rootNode.addChildNode(xLabel)
        
        // Y-axis (Green)
        let yAxis = createAxisLine(color: .systemGreen, startPos: SCNVector3(0, 0, 0), endPos: SCNVector3(0, 1.5, 0))
        yAxis.name = "yAxis"
        scene.rootNode.addChildNode(yAxis)
        
        // Y-axis label
        let yLabel = createAxisLabel(text: "Y", color: .systemGreen, position: SCNVector3(0, 1.8, 0))
        yLabel.name = "yLabel"
        scene.rootNode.addChildNode(yLabel)
        
        // Z-axis (Blue)
        let zAxis = createAxisLine(color: .systemBlue, startPos: SCNVector3(0, 0, 0), endPos: SCNVector3(0, 0, 1.5))
        zAxis.name = "zAxis"
        scene.rootNode.addChildNode(zAxis)
        
        // Z-axis label
        let zLabel = createAxisLabel(text: "Z", color: .systemBlue, position: SCNVector3(0, 0, 1.8))
        zLabel.name = "zLabel"
        scene.rootNode.addChildNode(zLabel)
        
        // Center sphere
        let centerSphere = SCNSphere(radius: 0.05)
        let centerMaterial = SCNMaterial()
        centerMaterial.diffuse.contents = NSColor.white
        centerMaterial.emission.contents = NSColor.white.withAlphaComponent(0.3)
        centerSphere.materials = [centerMaterial]
        
        let centerNode = SCNNode(geometry: centerSphere)
        centerNode.name = "center"
        scene.rootNode.addChildNode(centerNode)
    }
    
    private func createAxisLine(color: NSColor, startPos: SCNVector3, endPos: SCNVector3) -> SCNNode {
        let lineNode = SCNNode()
        
        // Calculate line direction and length
        let direction = SCNVector3(
            endPos.x - startPos.x,
            endPos.y - startPos.y,
            endPos.z - startPos.z
        )
        let length = sqrt(pow(direction.x, 2) + pow(direction.y, 2) + pow(direction.z, 2))
        
        // Create cylinder geometry
        let cylinder = SCNCylinder(radius: 0.02, height: CGFloat(length))
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.3)
        cylinder.materials = [material]
        
        let cylinderNode = SCNNode(geometry: cylinder)
        
        // Position cylinder at midpoint
        cylinderNode.position = SCNVector3(
            (startPos.x + endPos.x) / 2,
            (startPos.y + endPos.y) / 2,
            (startPos.z + endPos.z) / 2
        )
        
        // Orient cylinder towards direction
        if length > 0 {
            let normalizedDirection = SCNVector3(
                direction.x / CGFloat(length),
                direction.y / CGFloat(length),
                direction.z / CGFloat(length)
            )
            
            // Calculate rotation to align with direction
            let defaultDirection = SCNVector3(0, 1, 0) // Cylinder's default orientation
            let rotationAxis = crossProduct(defaultDirection, normalizedDirection)
            let rotationAngle = acos(dotProduct(defaultDirection, normalizedDirection))
            
            if vectorLength(rotationAxis) > 0.001 {
                cylinderNode.rotation = SCNVector4(
                    rotationAxis.x / CGFloat(vectorLength(rotationAxis)),
                    rotationAxis.y / CGFloat(vectorLength(rotationAxis)),
                    rotationAxis.z / CGFloat(vectorLength(rotationAxis)),
                    rotationAngle
                )
            }
        }
        
        lineNode.addChildNode(cylinderNode)
        
        // Add arrow at the end
        let arrow = createArrowHead(color: color)
        arrow.position = endPos
        
        // Orient arrow in the same direction as the line
        if CGFloat(length) > 0 {
            let normalizedDirection = SCNVector3(
                direction.x / CGFloat(length),
                direction.y / CGFloat(length),
                direction.z / CGFloat(length)
            )
            
            let defaultDirection = SCNVector3(0, 1, 0)
            let rotationAxis = crossProduct(defaultDirection, normalizedDirection)
            let rotationAngle = acos(dotProduct(defaultDirection, normalizedDirection))
            
            if vectorLength(rotationAxis) > 0.001 {
                arrow.rotation = SCNVector4(
                    rotationAxis.x / CGFloat(vectorLength(rotationAxis)),
                    rotationAxis.y / CGFloat(vectorLength(rotationAxis)),
                    rotationAxis.z / CGFloat(vectorLength(rotationAxis)),
                    rotationAngle
                )
            }
        }
        
        lineNode.addChildNode(arrow)
        
        return lineNode
    }
    
    private func createArrowHead(color: NSColor) -> SCNNode {
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.08, height: 0.2)
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.5)
        cone.materials = [material]
        
        let arrowNode = SCNNode(geometry: cone)
        return arrowNode
    }
    
    private func createAxisLabel(text: String, color: NSColor, position: SCNVector3) -> SCNNode {
        let textGeometry = SCNText(string: text, extrusionDepth: 0.02)
        textGeometry.font = NSFont.boldSystemFont(ofSize: 0.3)
        textGeometry.flatness = 0.1
        
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.7)
        textGeometry.materials = [material]
        
        let textNode = SCNNode(geometry: textGeometry)
        textNode.position = position
        
        // Scale down the text
        textNode.scale = SCNVector3(0.5, 0.5, 0.5)
        
        // Make text face camera (billboard effect)
        textNode.constraints = [SCNBillboardConstraint()]
        
        return textNode
    }
    
    private func setupLighting(in scene: SCNScene) {
        // Ambient light for general illumination
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = NSColor.white.withAlphaComponent(0.4)
        
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        // Directional light for better visibility
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.color = NSColor.white.withAlphaComponent(0.8)
        
        let lightNode = SCNNode()
        lightNode.light = directionalLight
        lightNode.position = SCNVector3(2, 3, 5)
        lightNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(lightNode)
    }
    
    // Helper functions for vector math
    private func crossProduct(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        return SCNVector3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }
    
    private func dotProduct(_ a: SCNVector3, _ b: SCNVector3) -> CGFloat {
        return a.x * b.x + a.y * b.y + a.z * b.z
    }
    
    private func vectorLength(_ vector: SCNVector3) -> CGFloat {
        return sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    }
}

#Preview {
    Viewport3DCompass(
        cameraAzimuth: .constant(0.5),
        cameraElevation: .constant(0.3),
        cameraRoll: .constant(0.2)
    )
    .frame(width: 200, height: 200)
    .background(.black)
}