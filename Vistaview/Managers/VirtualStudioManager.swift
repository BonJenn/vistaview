//
//  VirtualStudioManager.swift
//  Vistaview
//

import Foundation
import SceneKit
import SwiftUI
import simd

#if os(macOS)
import AppKit
typealias UXColor = NSColor
#else
import UIKit
typealias UXColor = UIColor
#endif

@MainActor
final class VirtualStudioManager: ObservableObject {
    // MARK: - Published State
    @Published var studioObjects: [StudioObject] = []
    @Published var virtualCameras: [VirtualCamera] = []
    @Published var selectedCamera: VirtualCamera?
    
    // MARK: - Scene
    let scene = SCNScene()
    private let rootNode: SCNNode
    private let floorNode: SCNNode
    
    // MARK: - Init
    init() {
        rootNode = scene.rootNode
        
        floorNode = Self.makeFloor()
        rootNode.addChildNode(floorNode)
        Self.addGrid(on: floorNode)
        
        setupDefaultLighting()
        addDefaultCamera()
        
        // Add a test cube for debugging selection
        addTestCube()
    }
    
    private func addTestCube() {
        // Create a large, obvious test cube
        let box = SCNBox(width: 3, height: 3, length: 3, chamferRadius: 0.1)
        let material = SCNMaterial()
        material.diffuse.contents = UXColor.systemRed // Bright red
        material.emission.contents = UXColor.systemRed.withAlphaComponent(0.2) // Slight glow
        box.materials = [material]
        
        let obj = StudioObject(name: "DEBUG_CUBE", type: .setPiece, position: SCNVector3(0, 1.5, 0))
        obj.node.geometry = box
        obj.node.name = "DEBUG_CUBE"
        obj.setupHighlightAfterGeometry()
        
        studioObjects.append(obj)
        scene.rootNode.addChildNode(obj.node)
        
        print("🧪 Added large red DEBUG_CUBE at (0, 1.5, 0)")
        print("   Cube node: \(obj.node)")
        print("   Cube geometry: \(obj.node.geometry != nil)")
        print("   Total objects in scene: \(studioObjects.count)")
    }
    
    // MARK: - Floor & Grid
    private static func makeFloor() -> SCNNode {
        let plane = SCNPlane(width: 200, height: 200)
        let mat = SCNMaterial()
        mat.diffuse.contents = UXColor.darkGray
        plane.materials = [mat]
        
        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        node.name = "Floor"
        return node
    }
    
    private static func addGrid(on floor: SCNNode) {
        let size: Float = 50.0
        let step: Float = 1.0
        
        for i in stride(from: -size, through: size, by: step) {
            floor.addChildNode(line(from: SCNVector3(CGFloat(i), 0.001, CGFloat(-size)),
                                    to:   SCNVector3(CGFloat(i), 0.001,  CGFloat(size))))
            floor.addChildNode(line(from: SCNVector3(CGFloat(-size), 0.001, CGFloat(i)),
                                    to:   SCNVector3( CGFloat(size), 0.001, CGFloat(i))))
        }
    }
    
    private static func line(from a: SCNVector3, to b: SCNVector3, color: UXColor = .lightGray) -> SCNNode {
        let diff = simd_float3(Float(b.x - a.x), Float(b.y - a.y), Float(b.z - a.z))
        let len  = CGFloat(simd_length(diff))
        
        let box = SCNBox(width: 0.02, height: 0.02, length: len, chamferRadius: 0)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        box.materials = [mat]
        
        let node = SCNNode(geometry: box)
        // midpoint (no operator overloads)
        node.position = SCNVector3(
            (a.x + b.x) * CGFloat(0.5),
            (a.y + b.y) * CGFloat(0.5),
            (a.z + b.z) * CGFloat(0.5)
        )
        node.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
        return node
    }
    
    // MARK: - Default Lighting & Camera
    private func setupDefaultLighting() {
        let light = SCNLight()
        light.type = .ambient
        light.intensity = 400.0 // This should be CGFloat by default
        light.color = UXColor.white
        
        let node = SCNNode()
        node.light = light
        rootNode.addChildNode(node)
    }
    
    private func addDefaultCamera() {
        // No assumption about your assets; create a basic one
        let cam = VirtualCamera(name: "Default Cam", position: SCNVector3(0, 2, 5))
        virtualCameras.append(cam)
        rootNode.addChildNode(cam.node)
        selectedCamera = cam
    }
    
    // MARK: - Public Stubs
    func exportScene()  { NSLog("[VSM] exportScene stub")  }
    func importScene()  { NSLog("[VSM] importScene stub")  }
    func renderPreview(){ NSLog("[VSM] renderPreview stub") }
    func resetView()    { selectedCamera = nil }
    
    // MARK: - Object Ops
    func addObject(type: StudioTool, at pos: SCNVector3) {
        switch type {
        case .ledWall:
            if let asset = LEDWallAsset.predefinedWalls.first {
                addLEDWall(from: asset, at: pos)
            }
        case .camera:
            if let asset = CameraAsset.predefinedCameras.first {
                addCamera(from: asset, at: pos)
            }
        case .setPiece:
            if let asset = SetPieceAsset.predefinedPieces.first {
                addSetPiece(from: asset, at: pos)
            }
        case .light:
            if let asset = LightAsset.predefinedLights.first {
                addLight(from: asset, at: pos)
            }
        case .select:
            break
        }
    }
    
    func deleteObject(_ obj: StudioObject) {
        obj.node.removeFromParentNode()
        studioObjects.removeAll { $0.id == obj.id }
    }
    
    func node(for obj: StudioObject) -> SCNNode { obj.node }
    
    func getObject(from node: SCNNode) -> StudioObject? {
        print("🔍 Looking for object from node: \(node.name ?? "unnamed")")
        print("   Node geometry: \(node.geometry != nil)")
        print("   Checking \(studioObjects.count) studio objects...")
        
        for obj in studioObjects {
            print("   - Checking object: \(obj.name)")
            if isNode(node, descendantOf: obj.node) {
                print("   ✅ Found match: \(obj.name)")
                return obj
            }
            if node === obj.node {
                print("   ✅ Direct node match: \(obj.name)")
                return obj
            }
        }
        
        print("   ❌ No studio object found for node")
        return nil
    }
    
    func updateObjectTransform(_ obj: StudioObject, from node: SCNNode) {
        guard let idx = studioObjects.firstIndex(where: { $0.id == obj.id }) else { return }
        studioObjects[idx].position = node.position
        studioObjects[idx].rotation = node.eulerAngles
        studioObjects[idx].scale    = node.scale
    }
    
    // MARK: - Specific Adds
    func addLEDWall(from asset: LEDWallAsset, at pos: SCNVector3) {
        let plane = SCNPlane(width: CGFloat(asset.width), height: CGFloat(asset.height))
        let mat = SCNMaterial()
        
        // Set up the material properly for video content
        mat.diffuse.contents = UXColor.darkGray // Default content
        mat.lightingModel = .physicallyBased // Will be changed to .constant for camera feeds
        mat.isDoubleSided = true
        
        // Configure texture properties for smooth video
        mat.diffuse.magnificationFilter = .linear
        mat.diffuse.minificationFilter = .linear
        mat.diffuse.wrapS = .clamp
        mat.diffuse.wrapT = .clamp
        
        plane.materials = [mat]
        
        let obj = StudioObject(name: asset.name, type: .ledWall, position: pos)
        obj.node.geometry = plane
        obj.node.name = asset.name
        
        // Optimize the LED wall for video display
        obj.optimizeLEDWallForVideo()
        obj.setupHighlightAfterGeometry() // Add highlight after geometry is set
        
        studioObjects.append(obj)
        rootNode.addChildNode(obj.node)
        
        print("➕ Added LED Wall: \(asset.name) at \(pos)")
        print("   - Optimized for video content")
        print("   - Material configured for camera feeds")
    }
    
    func addSetPiece(from asset: SetPieceAsset, at pos: SCNVector3) {
        let box = SCNBox(width: CGFloat(asset.size.x),
                         height: CGFloat(asset.size.y),
                         length: CGFloat(asset.size.z),
                         chamferRadius: 0)
        let mat = SCNMaterial()
        mat.diffuse.contents = asset.color
        box.materials = [mat]
        
        let obj = StudioObject(name: asset.name, type: .setPiece, position: pos)
        obj.node.geometry = box
        obj.node.name = asset.name
        obj.setupHighlightAfterGeometry() // Add highlight after geometry is set
        
        studioObjects.append(obj)
        rootNode.addChildNode(obj.node)
        
        print("➕ Added Set Piece: \(asset.name) at \(pos)")
    }
    
    func addLight(from asset: LightAsset, at pos: SCNVector3) {
        let scnLight = SCNLight()
        switch asset.lightType.lowercased() {
        case "directional": scnLight.type = .directional
        case "spot":        scnLight.type = .spot
        case "omni":        scnLight.type = .omni
        default:            scnLight.type = .omni
        }
        scnLight.intensity = CGFloat(asset.intensity)
        scnLight.color = asset.color
        
        // Create a small visual representation for lights
        let sphere = SCNSphere(radius: 0.2)
        let mat = SCNMaterial()
        mat.diffuse.contents = asset.color
        mat.emission.contents = asset.color.withAlphaComponent(0.5)
        sphere.materials = [mat]
        
        let obj = StudioObject(name: asset.name, type: .light, position: pos)
        obj.node.geometry = sphere // Add geometry so it can be selected
        obj.node.light = scnLight
        obj.node.name = asset.name
        obj.setupHighlightAfterGeometry() // Add highlight after geometry is set
        
        studioObjects.append(obj)
        rootNode.addChildNode(obj.node)
        
        print("➕ Added Light: \(asset.name) at \(pos)")
    }
    
    func addCamera(from asset: CameraAsset, at pos: SCNVector3) {
        let vcam = VirtualCamera(name: asset.name, position: pos)
        if let c = vcam.node.camera {
            c.focalLength = CGFloat(asset.focalLength)
        }
        virtualCameras.append(vcam)
        rootNode.addChildNode(vcam.node)
    }
    
    func selectCamera(_ cam: VirtualCamera) {
        for i in virtualCameras.indices {
            virtualCameras[i].isActive = (virtualCameras[i].id == cam.id)
        }
        selectedCamera = cam
    }
    
    func addSetPieceFromAsset(_ asset: SetPieceAsset, at position: SCNVector3) {
        // Create geometry based on asset
        let geometry: SCNGeometry
        
        switch asset.subcategory {
        case .ledWalls:
            geometry = SCNPlane(width: CGFloat(asset.size.x), height: CGFloat(asset.size.y))
        case .furniture, .props:
            geometry = SCNBox(width: CGFloat(asset.size.x), 
                            height: CGFloat(asset.size.y), 
                            length: CGFloat(asset.size.z), 
                            chamferRadius: 0.05)
        case .lighting:
            geometry = SCNSphere(radius: CGFloat(max(asset.size.x, asset.size.y, asset.size.z)) / 4)
        }
        
        // Create material
        let material = SCNMaterial()
        material.diffuse.contents = asset.color
        geometry.materials = [material]
        
        // Create studio object
        let obj = StudioObject(name: asset.name, type: .setPiece, position: position)
        obj.node.geometry = geometry
        obj.node.name = asset.name
        obj.setupHighlightAfterGeometry() // Add highlight after geometry is set
        
        // Special positioning for LED walls (vertical)
        if asset.subcategory == .ledWalls {
            obj.node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        }
        
        studioObjects.append(obj)
        scene.rootNode.addChildNode(obj.node)
        
        print("➕ Added Set Piece from Asset: \(asset.name) at \(position)")
    }
    
    // MARK: - Screen → World
    func worldPosition(from screenPoint: CGPoint, in view: SCNView) -> SCNVector3 {
        let near = view.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 0))
        let far  = view.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 1))
        let dir  = simd_normalize(simd_float3(Float(far.x - near.x), Float(far.y - near.y), Float(far.z - near.z)))
        let origin = simd_float3(Float(near.x), Float(near.y), Float(near.z))
        let t = -origin.y / dir.y
        let hit = origin + dir * t
        return SCNVector3(CGFloat(hit.x), CGFloat(hit.y), CGFloat(hit.z))
    }
    
    // MARK: - Local helpers (avoid global extensions)
    private func isNode(_ node: SCNNode, descendantOf candidate: SCNNode) -> Bool {
        var cur = node.parent
        while let n = cur {
            if n === candidate { return true }
            cur = n.parent
        }
        return false
    }
}