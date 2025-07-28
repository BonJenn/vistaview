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
        
        // IMPORTANT: Setup highlight AFTER adding geometry and to scene
        studioObjects.append(obj)
        scene.rootNode.addChildNode(obj.node)
        
        // Now setup the highlight system
        obj.setupHighlightAfterGeometry()
        
        print("🧪 Added large red DEBUG_CUBE at (0, 1.5, 0)")
        print("   Cube node: \(obj.node)")
        print("   Cube geometry: \(obj.node.geometry != nil)")
        print("   Total objects in scene: \(studioObjects.count)")
        print("   Highlight node setup: \(obj.node.childNodes.contains { $0.name?.contains("highlight") == true })")
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
        case .staging:
            if let asset = StagingAsset.predefinedStaging.first {
                addStagingEquipment(from: asset, at: pos)
            }
        case .select:
            break
        }
    }
    
    func deleteObject(_ obj: StudioObject) {
        print("🗑️ Deleting object: \(obj.name)")
        
        // Remove from scene
        obj.node.removeFromParentNode()
        
        // Remove from our collections
        studioObjects.removeAll { $0.id == obj.id }
        
        // Also remove from virtual cameras if it's a camera
        if obj.type == .camera {
            virtualCameras.removeAll { $0.id == obj.id }
        }
        
        print("✅ Object deleted. Remaining objects: \(studioObjects.count)")
    }
    
    func node(for obj: StudioObject) -> SCNNode { obj.node }
    
    func getObject(from node: SCNNode) -> StudioObject? {
        print("🔍 Looking for object from node: \(node.name ?? "unnamed")")
        print("   Node geometry: \(node.geometry != nil)")
        print("   Checking \(studioObjects.count) studio objects...")
        
        for obj in studioObjects {
            print("   - Checking object: \(obj.name) (node: \(obj.node.name ?? "unnamed"))")
            
            // Direct match
            if node === obj.node {
                print("   ✅ Direct node match: \(obj.name)")
                return obj
            }
            
            // Check if node is a descendant of the object's node
            if isNode(node, descendantOf: obj.node) {
                print("   ✅ Found descendant match: \(obj.name)")
                return obj
            }
            
            // Check if the node is a direct child with geometry
            if let parent = node.parent, parent === obj.node {
                print("   ✅ Found direct child match: \(obj.name)")
                return obj
            }
            
            // Check if the clicked node is a child geometry node
            var currentNode: SCNNode? = node
            var depth = 0
            while let checkNode = currentNode, depth < 5 {
                if checkNode === obj.node {
                    print("   ✅ Found ancestor match at depth \(depth): \(obj.name)")
                    return obj
                }
                currentNode = checkNode.parent
                depth += 1
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
        // Create the main LED wall plane
        let plane = SCNPlane(width: CGFloat(asset.width), height: CGFloat(asset.height))
        
        // Enhanced material for LED wall
        let screenMaterial = SCNMaterial()
        screenMaterial.diffuse.contents = UXColor.black // Default black screen
        screenMaterial.lightingModel = .physicallyBased
        screenMaterial.isDoubleSided = false
        screenMaterial.diffuse.magnificationFilter = .linear
        screenMaterial.diffuse.minificationFilter = .linear
        screenMaterial.diffuse.wrapS = .clamp
        screenMaterial.diffuse.wrapT = .clamp
        
        // Add subtle screen texture/reflection
        screenMaterial.metalness.contents = 0.1
        screenMaterial.roughness.contents = 0.2
        screenMaterial.emission.intensity = 0.1
        
        plane.materials = [screenMaterial]
        
        // Create LED wall assembly with frame and support structure
        let ledWallGroup = SCNNode()
        ledWallGroup.name = asset.name + "_group"
        
        // Main screen
        let screenNode = SCNNode(geometry: plane)
        screenNode.name = "screen"
        ledWallGroup.addChildNode(screenNode)
        
        // Create realistic frame around the screen
        let frameThickness: CGFloat = 0.1
        let frameDepth: CGFloat = 0.05
        
        // Frame material
        let frameMaterial = SCNMaterial()
        frameMaterial.diffuse.contents = UXColor.darkGray
        frameMaterial.metalness.contents = 0.8
        frameMaterial.roughness.contents = 0.3
        
        // Top frame
        let topFrame = SCNBox(width: CGFloat(asset.width) + frameThickness * 2, 
                             height: frameThickness, 
                             length: frameDepth, 
                             chamferRadius: 0.02)
        topFrame.materials = [frameMaterial]
        let topFrameNode = SCNNode(geometry: topFrame)
        topFrameNode.position = SCNVector3(0, CGFloat(asset.height/2) + frameThickness/2, frameDepth/2)
        ledWallGroup.addChildNode(topFrameNode)
        
        // Bottom frame
        let bottomFrame = SCNBox(width: CGFloat(asset.width) + frameThickness * 2, 
                                height: frameThickness, 
                                length: frameDepth, 
                                chamferRadius: 0.02)
        bottomFrame.materials = [frameMaterial]
        let bottomFrameNode = SCNNode(geometry: bottomFrame)
        bottomFrameNode.position = SCNVector3(0, -CGFloat(asset.height/2) - frameThickness/2, frameDepth/2)
        ledWallGroup.addChildNode(bottomFrameNode)
        
        // Left frame
        let leftFrame = SCNBox(width: frameThickness, 
                              height: CGFloat(asset.height), 
                              length: frameDepth, 
                              chamferRadius: 0.02)
        leftFrame.materials = [frameMaterial]
        let leftFrameNode = SCNNode(geometry: leftFrame)
        leftFrameNode.position = SCNVector3(-CGFloat(asset.width/2) - frameThickness/2, 0, frameDepth/2)
        ledWallGroup.addChildNode(leftFrameNode)
        
        // Right frame
        let rightFrame = SCNBox(width: frameThickness, 
                               height: CGFloat(asset.height), 
                               length: frameDepth, 
                               chamferRadius: 0.02)
        rightFrame.materials = [frameMaterial]
        let rightFrameNode = SCNNode(geometry: rightFrame)
        rightFrameNode.position = SCNVector3(CGFloat(asset.width/2) + frameThickness/2, 0, frameDepth/2)
        ledWallGroup.addChildNode(rightFrameNode)
        
        // Add support legs for larger LED walls
        if asset.width > 8 || asset.height > 6 {
            let legMaterial = SCNMaterial()
            legMaterial.diffuse.contents = UXColor.systemGray
            legMaterial.metalness.contents = 0.9
            legMaterial.roughness.contents = 0.1
            
            // Left support leg
            let leftLeg = SCNCylinder(radius: 0.05, height: CGFloat(asset.height) + 2)
            leftLeg.materials = [legMaterial]
            let leftLegNode = SCNNode(geometry: leftLeg)
            leftLegNode.position = SCNVector3(-CGFloat(asset.width/2) - 0.5, -1, -0.3)
            ledWallGroup.addChildNode(leftLegNode)
            
            // Right support leg
            let rightLeg = SCNCylinder(radius: 0.05, height: CGFloat(asset.height) + 2)
            rightLeg.materials = [legMaterial]
            let rightLegNode = SCNNode(geometry: rightLeg)
            rightLegNode.position = SCNVector3(CGFloat(asset.width/2) + 0.5, -1, -0.3)
            ledWallGroup.addChildNode(rightLegNode)
        }
        
        // Create the studio object
        let obj = StudioObject(name: asset.name, type: .ledWall, position: pos)
        obj.node.addChildNode(ledWallGroup)
        
        // Store reference to screen node for content updates
        obj.node.name = asset.name + "_ledwall"
        screenNode.name = "screen" // Important for finding the screen later
        
        obj.optimizeLEDWallForVideo()
        
        // Add to collections and scene FIRST
        studioObjects.append(obj)
        rootNode.addChildNode(obj.node)
        
        // THEN setup highlight system
        obj.setupHighlightAfterGeometry()
        
        print("➕ Added Enhanced LED Wall: \(asset.name) at \(pos)")
        print("   - Size: \(asset.width)x\(asset.height)m")
        print("   - With realistic frame and support structure")
        print("   - Highlight setup complete: \(obj.node.childNodes.contains { $0.name?.contains("highlight") == true })")
    }
    
    func addSetPiece(from asset: SetPieceAsset, at pos: SCNVector3) {
        let setPieceGroup = SCNNode()
        setPieceGroup.name = asset.name
        
        // Create different geometries based on the asset type
        switch asset.name.lowercased() {
        case let name where name.contains("desk"):
            createDeskGeometry(asset: asset, group: setPieceGroup)
        case let name where name.contains("chair"):
            createChairGeometry(asset: asset, group: setPieceGroup)
        case let name where name.contains("sofa"):
            createSofaGeometry(asset: asset, group: setPieceGroup)
        case let name where name.contains("table"):
            createTableGeometry(asset: asset, group: setPieceGroup)
        case let name where name.contains("stage") || name.contains("platform"):
            createStageGeometry(asset: asset, group: setPieceGroup)
        case let name where name.contains("speaker"):
            createSpeakerGeometry(asset: asset, group: setPieceGroup)
        case let name where name.contains("bookshelf"):
            createBookshelfGeometry(asset: asset, group: setPieceGroup)
        default:
            // Default box geometry with enhanced materials
            createDefaultSetPieceGeometry(asset: asset, group: setPieceGroup)
        }
        
        let obj = StudioObject(name: asset.name, type: .setPiece, position: pos)
        obj.node.addChildNode(setPieceGroup)
        obj.setupHighlightAfterGeometry()
        
        studioObjects.append(obj)
        rootNode.addChildNode(obj.node)
        
        print("➕ Added Enhanced Set Piece: \(asset.name) at \(pos)")
    }
    
    private func createDeskGeometry(asset: SetPieceAsset, group: SCNNode) {
        // Desktop
        let desktop = SCNBox(width: CGFloat(asset.size.x), 
                            height: 0.05, 
                            length: CGFloat(asset.size.z), 
                            chamferRadius: 0.02)
        let deskMaterial = SCNMaterial()
        deskMaterial.diffuse.contents = UXColor.systemBrown
        deskMaterial.roughness.contents = 0.3
        deskMaterial.metalness.contents = 0.1
        desktop.materials = [deskMaterial]
        
        let desktopNode = SCNNode(geometry: desktop)
        desktopNode.position = SCNVector3(0, CGFloat(asset.size.y) - 0.025, 0)
        group.addChildNode(desktopNode)
        
        // Legs
        let legRadius: CGFloat = 0.03
        let legHeight = CGFloat(asset.size.y) - 0.05
        
        let legMaterial = SCNMaterial()
        legMaterial.diffuse.contents = UXColor.darkGray
        legMaterial.metalness.contents = 0.8
        legMaterial.roughness.contents = 0.2
        
        let positions: [SCNVector3] = [
            SCNVector3(CGFloat(asset.size.x/2) - 0.1, legHeight/2, CGFloat(asset.size.z/2) - 0.1),
            SCNVector3(-CGFloat(asset.size.x/2) + 0.1, legHeight/2, CGFloat(asset.size.z/2) - 0.1),
            SCNVector3(CGFloat(asset.size.x/2) - 0.1, legHeight/2, -CGFloat(asset.size.z/2) + 0.1),
            SCNVector3(-CGFloat(asset.size.x/2) + 0.1, legHeight/2, -CGFloat(asset.size.z/2) + 0.1)
        ]
        
        for position in positions {
            let leg = SCNCylinder(radius: legRadius, height: legHeight)
            leg.materials = [legMaterial]
            let legNode = SCNNode(geometry: leg)
            legNode.position = position
            group.addChildNode(legNode)
        }
    }
    
    private func createChairGeometry(asset: SetPieceAsset, group: SCNNode) {
        let chairMaterial = SCNMaterial()
        chairMaterial.diffuse.contents = asset.color
        chairMaterial.roughness.contents = 0.6
        
        // Seat
        let seat = SCNBox(width: CGFloat(asset.size.x), 
                         height: 0.05, 
                         length: CGFloat(asset.size.z), 
                         chamferRadius: 0.02)
        seat.materials = [chairMaterial]
        let seatNode = SCNNode(geometry: seat)
        seatNode.position = SCNVector3(0, CGFloat(asset.size.y) * 0.4, 0)
        group.addChildNode(seatNode)
        
        // Backrest
        let backrest = SCNBox(width: CGFloat(asset.size.x), 
                             height: CGFloat(asset.size.y) * 0.5, 
                             length: 0.05, 
                             chamferRadius: 0.02)
        backrest.materials = [chairMaterial]
        let backrestNode = SCNNode(geometry: backrest)
        backrestNode.position = SCNVector3(0, CGFloat(asset.size.y) * 0.65, -CGFloat(asset.size.z/2) + 0.025)
        group.addChildNode(backrestNode)
        
        // Chair legs
        let legMaterial = SCNMaterial()
        legMaterial.diffuse.contents = UXColor.darkGray
        legMaterial.metalness.contents = 0.8
        
        let legHeight = CGFloat(asset.size.y) * 0.4
        let legPositions: [SCNVector3] = [
            SCNVector3(CGFloat(asset.size.x/2) - 0.05, legHeight/2, CGFloat(asset.size.z/2) - 0.05),
            SCNVector3(-CGFloat(asset.size.x/2) + 0.05, legHeight/2, CGFloat(asset.size.z/2) - 0.05),
            SCNVector3(CGFloat(asset.size.x/2) - 0.05, legHeight/2, -CGFloat(asset.size.z/2) + 0.05),
            SCNVector3(-CGFloat(asset.size.x/2) + 0.05, legHeight/2, -CGFloat(asset.size.z/2) + 0.05)
        ]
        
        for position in legPositions {
            let leg = SCNCylinder(radius: 0.02, height: legHeight)
            leg.materials = [legMaterial]
            let legNode = SCNNode(geometry: leg)
            legNode.position = position
            group.addChildNode(legNode)
        }
    }
    
    private func createSofaGeometry(asset: SetPieceAsset, group: SCNNode) {
        let sofaMaterial = SCNMaterial()
        sofaMaterial.diffuse.contents = asset.color
        sofaMaterial.roughness.contents = 0.8
        
        // Main body
        let body = SCNBox(width: CGFloat(asset.size.x), 
                         height: CGFloat(asset.size.y) * 0.6, 
                         length: CGFloat(asset.size.z), 
                         chamferRadius: 0.05)
        body.materials = [sofaMaterial]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, CGFloat(asset.size.y) * 0.3, 0)
        group.addChildNode(bodyNode)
        
        // Backrest
        let backrest = SCNBox(width: CGFloat(asset.size.x), 
                             height: CGFloat(asset.size.y) * 0.7, 
                             length: 0.2, 
                             chamferRadius: 0.05)
        backrest.materials = [sofaMaterial]
        let backrestNode = SCNNode(geometry: backrest)
        backrestNode.position = SCNVector3(0, CGFloat(asset.size.y) * 0.5, -CGFloat(asset.size.z/2) + 0.1)
        group.addChildNode(backrestNode)
        
        // Armrests
        let armrest = SCNBox(width: 0.2, 
                            height: CGFloat(asset.size.y) * 0.4, 
                            length: CGFloat(asset.size.z) * 0.8, 
                            chamferRadius: 0.05)
        armrest.materials = [sofaMaterial]
        
        let leftArmrestNode = SCNNode(geometry: armrest)
        leftArmrestNode.position = SCNVector3(-CGFloat(asset.size.x/2) + 0.1, CGFloat(asset.size.y) * 0.4, 0)
        group.addChildNode(leftArmrestNode)
        
        let rightArmrestNode = SCNNode(geometry: armrest)
        rightArmrestNode.position = SCNVector3(CGFloat(asset.size.x/2) - 0.1, CGFloat(asset.size.y) * 0.4, 0)
        group.addChildNode(rightArmrestNode)
    }
    
    private func createTableGeometry(asset: SetPieceAsset, group: SCNNode) {
        // Table top
        let tabletop = SCNBox(width: CGFloat(asset.size.x), 
                             height: 0.05, 
                             length: CGFloat(asset.size.z), 
                             chamferRadius: 0.02)
        let tableMaterial = SCNMaterial()
        tableMaterial.diffuse.contents = asset.color
        tableMaterial.roughness.contents = 0.2
        tableMaterial.metalness.contents = 0.1
        tabletop.materials = [tableMaterial]
        
        let tabletopNode = SCNNode(geometry: tabletop)
        tabletopNode.position = SCNVector3(0, CGFloat(asset.size.y) - 0.025, 0)
        group.addChildNode(tabletopNode)
        
        // Single center pedestal for round table, four legs for rectangular
        if asset.name.lowercased().contains("round") {
            let pedestal = SCNCylinder(radius: 0.1, height: CGFloat(asset.size.y) - 0.05)
            let pedestalMaterial = SCNMaterial()
            pedestalMaterial.diffuse.contents = UXColor.darkGray
            pedestalMaterial.metalness.contents = 0.8
            pedestal.materials = [pedestalMaterial]
            
            let pedestalNode = SCNNode(geometry: pedestal)
            pedestalNode.position = SCNVector3(0, (CGFloat(asset.size.y) - 0.05) / 2, 0)
            group.addChildNode(pedestalNode)
        } else {
            // Four legs for rectangular table (reuse desk leg logic)
            createDeskGeometry(asset: asset, group: group)
            return // Don't add another tabletop
        }
    }
    
    private func createStageGeometry(asset: SetPieceAsset, group: SCNNode) {
        // Main platform
        let platform = SCNBox(width: CGFloat(asset.size.x), 
                              height: CGFloat(asset.size.y), 
                              length: CGFloat(asset.size.z), 
                              chamferRadius: 0.02)
        let stageMaterial = SCNMaterial()
        stageMaterial.diffuse.contents = UXColor.black
        stageMaterial.roughness.contents = 0.1
        stageMaterial.metalness.contents = 0.2
        platform.materials = [stageMaterial]
        
        let platformNode = SCNNode(geometry: platform)
        platformNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(platformNode)
        
        // Add edge trim
        let trimMaterial = SCNMaterial()
        trimMaterial.diffuse.contents = UXColor.systemGray
        trimMaterial.metalness.contents = 0.8
        
        // Front trim
        let frontTrim = SCNBox(width: CGFloat(asset.size.x), height: 0.05, length: 0.05, chamferRadius: 0.01)
        frontTrim.materials = [trimMaterial]
        let frontTrimNode = SCNNode(geometry: frontTrim)
        frontTrimNode.position = SCNVector3(0, CGFloat(asset.size.y) + 0.025, CGFloat(asset.size.z/2) + 0.025)
        group.addChildNode(frontTrimNode)
    }
    
    private func createSpeakerGeometry(asset: SetPieceAsset, group: SCNNode) {
        // Main speaker box
        let speakerBox = SCNBox(width: CGFloat(asset.size.x), 
                               height: CGFloat(asset.size.y), 
                               length: CGFloat(asset.size.z), 
                               chamferRadius: 0.05)
        let speakerMaterial = SCNMaterial()
        speakerMaterial.diffuse.contents = UXColor.black
        speakerMaterial.roughness.contents = 0.8
        speakerBox.materials = [speakerMaterial]
        
        let speakerBoxNode = SCNNode(geometry: speakerBox)
        speakerBoxNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(speakerBoxNode)
        
        // Speaker drivers (circles on the front)
        let driverMaterial = SCNMaterial()
        driverMaterial.diffuse.contents = UXColor.darkGray
        driverMaterial.metalness.contents = 0.3
        
        let largeSpeaker = SCNCylinder(radius: CGFloat(asset.size.x) * 0.25, height: 0.02)
        largeSpeaker.materials = [driverMaterial]
        let largeSpeakerNode = SCNNode(geometry: largeSpeaker)
        largeSpeakerNode.position = SCNVector3(0, CGFloat(asset.size.y) * 0.6, CGFloat(asset.size.z/2) + 0.01)
        largeSpeakerNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(largeSpeakerNode)
        
        let smallSpeaker = SCNCylinder(radius: CGFloat(asset.size.x) * 0.15, height: 0.02)
        smallSpeaker.materials = [driverMaterial]
        let smallSpeakerNode = SCNNode(geometry: smallSpeaker)
        smallSpeakerNode.position = SCNVector3(0, CGFloat(asset.size.y) * 0.3, CGFloat(asset.size.z/2) + 0.01)
        smallSpeakerNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(smallSpeakerNode)
    }
    
    private func createBookshelfGeometry(asset: SetPieceAsset, group: SCNNode) {
        let shelfMaterial = SCNMaterial()
        shelfMaterial.diffuse.contents = UXColor.systemBrown
        shelfMaterial.roughness.contents = 0.6
        
        // Back panel
        let backPanel = SCNBox(width: CGFloat(asset.size.x), 
                              height: CGFloat(asset.size.y), 
                              length: 0.02, 
                              chamferRadius: 0.01)
        backPanel.materials = [shelfMaterial]
        let backPanelNode = SCNNode(geometry: backPanel)
        backPanelNode.position = SCNVector3(0, CGFloat(asset.size.y/2), -CGFloat(asset.size.z/2) + 0.01)
        group.addChildNode(backPanelNode)
        
        // Side panels
        let sidePanel = SCNBox(width: 0.02, 
                              height: CGFloat(asset.size.y), 
                              length: CGFloat(asset.size.z), 
                              chamferRadius: 0.01)
        sidePanel.materials = [shelfMaterial]
        
        let leftSideNode = SCNNode(geometry: sidePanel)
        leftSideNode.position = SCNVector3(-CGFloat(asset.size.x/2) + 0.01, CGFloat(asset.size.y/2), 0)
        group.addChildNode(leftSideNode)
        
        let rightSideNode = SCNNode(geometry: sidePanel)  
        rightSideNode.position = SCNVector3(CGFloat(asset.size.x/2) - 0.01, CGFloat(asset.size.y/2), 0)
        group.addChildNode(rightSideNode)
        
        // Shelves
        let shelfThickness: CGFloat = 0.03
        let numShelves = Int(asset.size.y / 0.4) // One shelf every 40cm
        
        for i in 0...numShelves {
            let shelf = SCNBox(width: CGFloat(asset.size.x) - 0.04, 
                              height: shelfThickness, 
                              length: CGFloat(asset.size.z) - 0.02, 
                              chamferRadius: 0.01)
            shelf.materials = [shelfMaterial]
            let shelfNode = SCNNode(geometry: shelf)
            let shelfY = (CGFloat(i) * CGFloat(asset.size.y) / CGFloat(numShelves))
            shelfNode.position = SCNVector3(0, shelfY, 0)
            group.addChildNode(shelfNode)
        }
    }
    
    private func createDefaultSetPieceGeometry(asset: SetPieceAsset, group: SCNNode) {
        let box = SCNBox(width: CGFloat(asset.size.x),
                         height: CGFloat(asset.size.y),
                         length: CGFloat(asset.size.z),
                         chamferRadius: 0.02)
        let mat = SCNMaterial()
        mat.diffuse.contents = asset.color
        mat.roughness.contents = 0.5
        mat.metalness.contents = 0.1
        box.materials = [mat]
        
        let boxNode = SCNNode(geometry: box)
        boxNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(boxNode)
    }
    
    func addLight(from asset: LightAsset, at pos: SCNVector3) {
        let lightGroup = SCNNode()
        lightGroup.name = asset.name
        
        // Create the actual SceneKit light
        let scnLight = SCNLight()
        switch asset.lightType.lowercased() {
        case "directional": 
            scnLight.type = .directional
            createDirectionalLightGeometry(asset: asset, group: lightGroup, light: scnLight)
        case "spot":        
            scnLight.type = .spot
            scnLight.spotInnerAngle = CGFloat(asset.beamAngle ?? 30) * 0.7
            scnLight.spotOuterAngle = CGFloat(asset.beamAngle ?? 30)
            createSpotLightGeometry(asset: asset, group: lightGroup, light: scnLight)
        case "omni":        
            scnLight.type = .omni
            createOmniLightGeometry(asset: asset, group: lightGroup, light: scnLight)
        default:            
            scnLight.type = .omni
            createOmniLightGeometry(asset: asset, group: lightGroup, light: scnLight)
        }
        
        scnLight.intensity = CGFloat(asset.intensity)
        scnLight.color = asset.color
        scnLight.castsShadow = true
        scnLight.shadowMode = .deferred
        scnLight.shadowMapSize = CGSize(width: 1024, height: 1024)
        scnLight.shadowSampleCount = 16
        
        // Add the light to the group
        let lightNode = SCNNode()
        lightNode.light = scnLight
        lightGroup.addChildNode(lightNode)
        
        let obj = StudioObject(name: asset.name, type: .light, position: pos)
        obj.node.addChildNode(lightGroup)
        obj.setupHighlightAfterGeometry()
        
        studioObjects.append(obj)
        rootNode.addChildNode(obj.node)
        
        print("➕ Added Enhanced Light: \(asset.name) (\(asset.lightType)) at \(pos)")
    }
    
    private func createDirectionalLightGeometry(asset: LightAsset, group: SCNNode, light: SCNLight) {
        // Create LED panel light fixture
        let panelWidth: CGFloat = 1.5
        let panelHeight: CGFloat = 1.0
        let panelDepth: CGFloat = 0.1
        
        // Main light panel
        let panel = SCNBox(width: panelWidth, height: panelHeight, length: panelDepth, chamferRadius: 0.02)
        let panelMaterial = SCNMaterial()
        panelMaterial.diffuse.contents = UXColor.white
        panelMaterial.emission.contents = asset.color
        panelMaterial.emission.intensity = 0.8
        panel.materials = [panelMaterial]
        
        let panelNode = SCNNode(geometry: panel)
        group.addChildNode(panelNode)
        
        // Frame around the panel
        let frameMaterial = SCNMaterial()
        frameMaterial.diffuse.contents = UXColor.black
        frameMaterial.metalness.contents = 0.8
        frameMaterial.roughness.contents = 0.2
        
        let frameThickness: CGFloat = 0.05
        let frames = [
            (SCNBox(width: panelWidth + frameThickness*2, height: frameThickness, length: panelDepth + 0.02, chamferRadius: 0.01), 
             SCNVector3(0, panelHeight/2 + frameThickness/2, 0)),
            (SCNBox(width: panelWidth + frameThickness*2, height: frameThickness, length: panelDepth + 0.02, chamferRadius: 0.01), 
             SCNVector3(0, -panelHeight/2 - frameThickness/2, 0)),
            (SCNBox(width: frameThickness, height: panelHeight, length: panelDepth + 0.02, chamferRadius: 0.01), 
             SCNVector3(-panelWidth/2 - frameThickness/2, 0, 0)),
            (SCNBox(width: frameThickness, height: panelHeight, length: panelDepth + 0.02, chamferRadius: 0.01), 
             SCNVector3(panelWidth/2 + frameThickness/2, 0, 0))
        ]
        
        for (frameGeometry, position) in frames {
            frameGeometry.materials = [frameMaterial]
            let frameNode = SCNNode(geometry: frameGeometry)
            frameNode.position = position
            group.addChildNode(frameNode)
        }
        
        // Mounting bracket
        let bracket = SCNCylinder(radius: 0.03, height: 0.5)
        bracket.materials = [frameMaterial]
        let bracketNode = SCNNode(geometry: bracket)
        bracketNode.position = SCNVector3(0, 0, -panelDepth/2 - 0.25)
        bracketNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(bracketNode)
    }
    
    private func createSpotLightGeometry(asset: LightAsset, group: SCNNode, light: SCNLight) {
        // Create traditional spotlight fixture
        let bodyRadius: CGFloat = 0.15
        let bodyLength: CGFloat = 0.4
        
        // Main spotlight body
        let body = SCNCylinder(radius: bodyRadius, height: bodyLength)
        let bodyMaterial = SCNMaterial()
        bodyMaterial.diffuse.contents = UXColor.black
        bodyMaterial.metalness.contents = 0.8
        bodyMaterial.roughness.contents = 0.3
        body.materials = [bodyMaterial]
        
        let bodyNode = SCNNode(geometry: body)
        bodyNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0) // Point forward
        group.addChildNode(bodyNode)
        
        // Lens at the front
        let lens = SCNCylinder(radius: bodyRadius - 0.02, height: 0.02)
        let lensMaterial = SCNMaterial()
        lensMaterial.diffuse.contents = UXColor.white
        lensMaterial.emission.contents = asset.color
        lensMaterial.emission.intensity = 1.0
        lensMaterial.transparency = 0.9
        lens.materials = [lensMaterial]
        
        let lensNode = SCNNode(geometry: lens)
        lensNode.position = SCNVector3(0, 0, bodyLength/2 + 0.01)
        lensNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(lensNode)
        
        // Mounting yoke
        let yoke = SCNTorus(ringRadius: bodyRadius + 0.05, pipeRadius: 0.02)
        yoke.materials = [bodyMaterial]
        let yokeNode = SCNNode(geometry: yoke)
        yokeNode.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        group.addChildNode(yokeNode)
        
        // Base stand
        let base = SCNCylinder(radius: 0.1, height: 0.8)
        base.materials = [bodyMaterial]
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, -0.4, 0)
        group.addChildNode(baseNode)
    }
    
    private func createOmniLightGeometry(asset: LightAsset, group: SCNNode, light: SCNLight) {
        // Create a bulb-style light
        let bulbRadius: CGFloat = 0.1
        
        // Glass bulb
        let bulb = SCNSphere(radius: bulbRadius)
        let bulbMaterial = SCNMaterial()
        bulbMaterial.diffuse.contents = UXColor.white
        bulbMaterial.emission.contents = asset.color
        bulbMaterial.emission.intensity = 1.0
        bulbMaterial.transparency = 0.8
        bulb.materials = [bulbMaterial]
        
        let bulbNode = SCNNode(geometry: bulb)
        group.addChildNode(bulbNode)
        
        // Socket/base
        let socket = SCNCylinder(radius: bulbRadius * 0.7, height: 0.15)
        let socketMaterial = SCNMaterial()
        socketMaterial.diffuse.contents = UXColor.systemGray
        socketMaterial.metalness.contents = 0.8
        socket.materials = [socketMaterial]
        
        let socketNode = SCNNode(geometry: socket)
        socketNode.position = SCNVector3(0, -bulbRadius - 0.075, 0)
        group.addChildNode(socketNode)
        
        // Light fixture housing
        let housing = SCNCone(topRadius: 0, bottomRadius: bulbRadius * 2, height: 0.3)
        let housingMaterial = SCNMaterial()
        housingMaterial.diffuse.contents = UXColor.darkGray
        housingMaterial.metalness.contents = 0.6
        housingMaterial.roughness.contents = 0.4
        housing.materials = [housingMaterial]
        
        let housingNode = SCNNode(geometry: housing)
        housingNode.position = SCNVector3(0, bulbRadius + 0.15, 0)
        group.addChildNode(housingNode)
        
        // Hanging cord for ceiling lights
        if asset.name.lowercased().contains("ambient") || asset.name.lowercased().contains("room") {
            let cord = SCNCylinder(radius: 0.005, height: 1.0)
            let cordMaterial = SCNMaterial()
            cordMaterial.diffuse.contents = UXColor.black
            cord.materials = [cordMaterial]
            
            let cordNode = SCNNode(geometry: cord)
            cordNode.position = SCNVector3(0, 0.5 + bulbRadius + 0.3, 0)
            group.addChildNode(cordNode)
        }
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
    
    func selectObject(_ object: StudioObject) {
        // Clear other selections first (single selection mode)
        for obj in studioObjects {
            obj.setSelected(false)
        }
        
        // Select the target object
        object.setSelected(true)
        print("✅ Selected object: \(object.name)")
    }
    
    func selectObjects(_ objects: [StudioObject]) {
        // Clear all selections first
        for obj in studioObjects {
            obj.setSelected(false)
        }
        
        // Select the target objects
        for object in objects {
            object.setSelected(true)
        }
        print("✅ Selected \(objects.count) objects")
    }
    
    func getSelectedObjects() -> [StudioObject] {
        return studioObjects.filter { $0.isSelected }
    }
    
    func clearSelection() {
        for obj in studioObjects {
            obj.setSelected(false)
        }
        print("🔄 Cleared all selections")
    }
    
    // MARK: - Staging Equipment
    
    func addStagingEquipment(from asset: StagingAsset, at pos: SCNVector3) {
        let stagingGroup = SCNNode()
        stagingGroup.name = asset.name
        
        // Create different geometries based on the staging category and name
        switch asset.category {
        case .trussing:
            createTrussingGeometry(asset: asset, group: stagingGroup)
        case .speakers:
            createSpeakerSystemGeometry(asset: asset, group: stagingGroup)
        case .rigging:
            createRiggingGeometry(asset: asset, group: stagingGroup)
        case .staging:
            createStagingPlatformGeometry(asset: asset, group: stagingGroup)
        case .effects:
            createEffectsGeometry(asset: asset, group: stagingGroup)
        }
        
        let obj = StudioObject(name: asset.name, type: .staging, position: pos)
        obj.node.addChildNode(stagingGroup)
        
        // Add to collections and scene FIRST
        studioObjects.append(obj)
        rootNode.addChildNode(obj.node)
        
        // THEN setup highlight system
        obj.setupHighlightAfterGeometry()
        
        print("➕ Added Staging Equipment: \(asset.name) (\(asset.category.rawValue)) at \(pos)")
    }
    
    // MARK: - Staging Geometry Creation Methods
    
    private func createTrussingGeometry(asset: StagingAsset, group: SCNNode) {
        let trussMaterial = SCNMaterial()
        trussMaterial.diffuse.contents = UXColor.lightGray
        trussMaterial.metalness.contents = 0.8
        trussMaterial.roughness.contents = 0.3
        
        switch asset.name.lowercased() {
        case let name where name.contains("straight truss"):
            createStraightTruss(asset: asset, group: group, material: trussMaterial)
        case let name where name.contains("corner"):
            createCornerTruss(asset: asset, group: group, material: trussMaterial)
        case let name where name.contains("t-junction"):
            createTJunctionTruss(asset: asset, group: group, material: trussMaterial)
        case let name where name.contains("lighting truss"):
            createLightingTruss(asset: asset, group: group, material: trussMaterial)
        case let name where name.contains("tower"):
            createGroundSupportTower(asset: asset, group: group, material: trussMaterial)
        case let name where name.contains("base plate"):
            createTrussBasePlate(asset: asset, group: group, material: trussMaterial)
        default:
            createDefaultTruss(asset: asset, group: group, material: trussMaterial)
        }
    }
    
    private func createStraightTruss(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        let trussSize = CGFloat(0.02) // Truss tube diameter
        let length = CGFloat(asset.size.x)
        
        // Main truss tubes (4 corners of box truss)
        let positions = [
            SCNVector3(0, 0.15, 0.15),   // Top right
            SCNVector3(0, 0.15, -0.15),  // Top left
            SCNVector3(0, -0.15, 0.15),  // Bottom right
            SCNVector3(0, -0.15, -0.15)  // Bottom left
        ]
        
        for position in positions {
            let tube = SCNCylinder(radius: trussSize, height: length)
            tube.materials = [material]
            let tubeNode = SCNNode(geometry: tube)
            tubeNode.position = position
            tubeNode.eulerAngles = SCNVector3(0, 0, Float.pi/2) // Rotate to horizontal
            group.addChildNode(tubeNode)
        }
        
        // Cross braces - create several along the length
        let numBraces = max(3, Int(length / 0.5)) // One brace every 0.5 meters
        
        for i in 0..<numBraces {
            let bracingX = (CGFloat(i) / CGFloat(numBraces - 1)) * length - length/2
            
            // Diagonal cross braces
            createCrossBrace(from: SCNVector3(bracingX, 0.15, 0.15), 
                           to: SCNVector3(bracingX, -0.15, -0.15), 
                           group: group, material: material, radius: trussSize * 0.7)
            
            createCrossBrace(from: SCNVector3(bracingX, 0.15, -0.15), 
                           to: SCNVector3(bracingX, -0.15, 0.15), 
                           group: group, material: material, radius: trussSize * 0.7)
        }
    }
    
    private func createCornerTruss(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        let trussSize = CGFloat(0.02)
        let length = CGFloat(0.3) // Square corner piece
        
        // Create L-shaped truss structure
        // Horizontal section
        for z in [0.15, -0.15] {
            for y in [0.15, -0.15] {
                let tube = SCNCylinder(radius: trussSize, height: length)
                tube.materials = [material]
                let tubeNode = SCNNode(geometry: tube)
                tubeNode.position = SCNVector3(0, y, z)
                tubeNode.eulerAngles = SCNVector3(0, 0, Float.pi/2)
                group.addChildNode(tubeNode)
            }
        }
        
        // Vertical section (perpendicular)
        for x in [0.15, -0.15] {
            for y in [0.15, -0.15] {
                let tube = SCNCylinder(radius: trussSize, height: length)
                tube.materials = [material]
                let tubeNode = SCNNode(geometry: tube)
                tubeNode.position = SCNVector3(x, y, 0)
                group.addChildNode(tubeNode)
            }
        }
        
        // Corner connectors
        let connectorPositions = [
            SCNVector3(0.15, 0.15, 0.15), SCNVector3(-0.15, 0.15, 0.15),
            SCNVector3(0.15, -0.15, 0.15), SCNVector3(-0.15, -0.15, 0.15),
            SCNVector3(0.15, 0.15, -0.15), SCNVector3(-0.15, 0.15, -0.15),
            SCNVector3(0.15, -0.15, -0.15), SCNVector3(-0.15, -0.15, -0.15)
        ]
        
        for position in connectorPositions {
            let connector = SCNSphere(radius: trussSize * 1.5)
            connector.materials = [material]
            let connectorNode = SCNNode(geometry: connector)
            connectorNode.position = position
            group.addChildNode(connectorNode)
        }
    }
    
    private func createTJunctionTruss(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Similar to corner but with three arms instead of two
        let trussSize = CGFloat(0.02)
        let length = CGFloat(0.3)
        
        // Main horizontal truss
        createStraightTrussSection(length: length, group: group, material: material, 
                                 rotation: SCNVector3(0, 0, Float.pi/2))
        
        // Perpendicular section (T-junction arm)
        createStraightTrussSection(length: length, group: group, material: material, 
                                 rotation: SCNVector3(0, Float.pi/2, 0))
        
        // Center connector hub
        let hub = SCNSphere(radius: trussSize * 2)
        hub.materials = [material]
        let hubNode = SCNNode(geometry: hub)
        group.addChildNode(hubNode)
    }
    
    private func createLightingTruss(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Heavy-duty truss with mounting points
        createStraightTruss(asset: asset, group: group, material: material)
        
        // Add lighting clamp mounting points along the truss
        let clampMaterial = SCNMaterial()
        clampMaterial.diffuse.contents = UXColor.black
        clampMaterial.metalness.contents = 0.9
        
        let numClamps = Int(asset.size.x / 0.5) // One clamp every 0.5 meters
        
        for i in 0..<numClamps {
            let clampX = (CGFloat(i) / CGFloat(max(1, numClamps - 1))) * CGFloat(asset.size.x) - CGFloat(asset.size.x)/2
            
            // Lighting clamp
            let clamp = SCNBox(width: 0.05, height: 0.1, length: 0.08, chamferRadius: 0.01)
            clamp.materials = [clampMaterial]
            let clampNode = SCNNode(geometry: clamp)
            clampNode.position = SCNVector3(clampX, -0.2, 0)
            group.addChildNode(clampNode)
            
            // Safety cable anchor
            let anchor = SCNSphere(radius: 0.01)
            anchor.materials = [clampMaterial]
            let anchorNode = SCNNode(geometry: anchor)
            anchorNode.position = SCNVector3(clampX, -0.25, 0)
            group.addChildNode(anchorNode)
        }
    }
    
    private func createGroundSupportTower(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        let trussSize = CGFloat(0.03) // Slightly thicker for tower
        let height = CGFloat(asset.size.y)
        
        // Main vertical legs (4 corners)
        let legPositions = [
            SCNVector3(0.2, 0, 0.2), SCNVector3(-0.2, 0, 0.2),
            SCNVector3(0.2, 0, -0.2), SCNVector3(-0.2, 0, -0.2)
        ]
        
        for position in legPositions {
            let leg = SCNCylinder(radius: trussSize, height: height)
            leg.materials = [material]
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(position.x, height/2, position.z)
            group.addChildNode(legNode)
        }
        
        // Horizontal cross braces at multiple levels
        let numLevels = max(3, Int(height / 1.5))
        
        for level in 0..<numLevels {
            let levelY = (CGFloat(level) / CGFloat(numLevels - 1)) * height
            
            // Create cross braces at this level
            createCrossBrace(from: SCNVector3(0.2, levelY, 0.2), 
                           to: SCNVector3(-0.2, levelY, -0.2), 
                           group: group, material: material, radius: trussSize * 0.8)
            
            createCrossBrace(from: SCNVector3(-0.2, levelY, 0.2), 
                           to: SCNVector3(0.2, levelY, -0.2), 
                           group: group, material: material, radius: trussSize * 0.8)
        }
        
        // Top platform for lighting attachment
        let platform = SCNBox(width: 0.5, height: 0.02, length: 0.5, chamferRadius: 0.01)
        platform.materials = [material]
        let platformNode = SCNNode(geometry: platform)
        platformNode.position = SCNVector3(0, height, 0)
        group.addChildNode(platformNode)
    }
    
    private func createTrussBasePlate(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Heavy steel base plate
        let baseMaterial = SCNMaterial()
        baseMaterial.diffuse.contents = UXColor.darkGray
        baseMaterial.metalness.contents = 0.9
        baseMaterial.roughness.contents = 0.1
        
        let plate = SCNBox(width: CGFloat(asset.size.x), 
                          height: CGFloat(asset.size.y), 
                          length: CGFloat(asset.size.z), 
                          chamferRadius: 0.02)
        plate.materials = [baseMaterial]
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(plateNode)
        
        // Center mounting socket
        let socket = SCNCylinder(radius: 0.05, height: CGFloat(asset.size.y) + 0.05)
        socket.materials = [material]
        let socketNode = SCNNode(geometry: socket)
        socketNode.position = SCNVector3(0, CGFloat(asset.size.y/2) + 0.025, 0)
        group.addChildNode(socketNode)
        
        // Corner weights/handles
        let handlePositions = [
            SCNVector3(CGFloat(asset.size.x/2) - 0.1, CGFloat(asset.size.y), CGFloat(asset.size.z/2) - 0.1),
            SCNVector3(-CGFloat(asset.size.x/2) + 0.1, CGFloat(asset.size.y), CGFloat(asset.size.z/2) - 0.1),
            SCNVector3(CGFloat(asset.size.x/2) - 0.1, CGFloat(asset.size.y), -CGFloat(asset.size.z/2) + 0.1),
            SCNVector3(-CGFloat(asset.size.x/2) + 0.1, CGFloat(asset.size.y), -CGFloat(asset.size.z/2) + 0.1)
        ]
        
        for position in handlePositions {
            let handle = SCNTorus(ringRadius: 0.04, pipeRadius: 0.01)
            handle.materials = [baseMaterial]
            let handleNode = SCNNode(geometry: handle)
            handleNode.position = position
            group.addChildNode(handleNode)
        }
    }
    
    private func createDefaultTruss(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        createStraightTruss(asset: asset, group: group, material: material)
    }
    
    // Helper method for creating cross braces
    private func createCrossBrace(from start: SCNVector3, to end: SCNVector3, 
                                group: SCNNode, material: SCNMaterial, radius: CGFloat = 0.015) {
        let diff = simd_float3(Float(end.x - start.x), Float(end.y - start.y), Float(end.z - start.z))
        let length = CGFloat(simd_length(diff))
        
        let brace = SCNCylinder(radius: radius, height: length)
        brace.materials = [material]
        
        let braceNode = SCNNode(geometry: brace)
        braceNode.position = SCNVector3(
            (start.x + end.x) / 2,
            (start.y + end.y) / 2,
            (start.z + end.z) / 2
        )
        braceNode.look(at: end, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        group.addChildNode(braceNode)
    }
    
    // Helper method for creating straight truss sections
    private func createStraightTrussSection(length: CGFloat, group: SCNNode, 
                                          material: SCNMaterial, rotation: SCNVector3) {
        let trussSize = CGFloat(0.02)
        
        let positions = [
            SCNVector3(0, 0.15, 0.15), SCNVector3(0, 0.15, -0.15),
            SCNVector3(0, -0.15, 0.15), SCNVector3(0, -0.15, -0.15)
        ]
        
        for position in positions {
            let tube = SCNCylinder(radius: trussSize, height: length)
            tube.materials = [material]
            let tubeNode = SCNNode(geometry: tube)
            tubeNode.position = position
            tubeNode.eulerAngles = rotation
            group.addChildNode(tubeNode)
        }
    }
    
    private func createSpeakerSystemGeometry(asset: StagingAsset, group: SCNNode) {
        let speakerMaterial = SCNMaterial()
        speakerMaterial.diffuse.contents = UXColor.black
        speakerMaterial.roughness.contents = 0.8
        
        switch asset.name.lowercased() {
        case let name where name.contains("line array"):
            createLineArrayModule(asset: asset, group: group, material: speakerMaterial)
        case let name where name.contains("subwoofer"):
            createSubwoofer(asset: asset, group: group, material: speakerMaterial)
        case let name where name.contains("monitor wedge"):
            createMonitorWedge(asset: asset, group: group, material: speakerMaterial)
        case let name where name.contains("main speaker stack"):
            createMainSpeakerStack(asset: asset, group: group, material: speakerMaterial)
        case let name where name.contains("side fill"):
            createSideFillSpeaker(asset: asset, group: group, material: speakerMaterial)
        case let name where name.contains("delay tower"):
            createDelayTower(asset: asset, group: group, material: speakerMaterial)
        default:
            createGenericSpeaker(asset: asset, group: group, material: speakerMaterial)
        }
    }
    
    private func createLineArrayModule(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Main enclosure - typically rectangular for line arrays
        let enclosure = SCNBox(width: CGFloat(asset.size.x), 
                              height: CGFloat(asset.size.y), 
                              length: CGFloat(asset.size.z), 
                              chamferRadius: 0.02)
        enclosure.materials = [material]
        let enclosureNode = SCNNode(geometry: enclosure)
        enclosureNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(enclosureNode)
        
        // Driver array on front face
        let driverMaterial = SCNMaterial()
        driverMaterial.diffuse.contents = UXColor.darkGray
        driverMaterial.metalness.contents = 0.3
        
        // Multiple small drivers in a line
        let numDrivers = 4
        for i in 0..<numDrivers {
            let driverY = (CGFloat(i) - CGFloat(numDrivers-1)/2) * 0.04 + CGFloat(asset.size.y/2)
            
            let driver = SCNCylinder(radius: 0.025, height: 0.005)
            driver.materials = [driverMaterial]
            let driverNode = SCNNode(geometry: driver)
            driverNode.position = SCNVector3(0, driverY, CGFloat(asset.size.z/2) + 0.003)
            driverNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
            group.addChildNode(driverNode)
        }
        
        // Rigging points
        createRiggingPoints(for: asset, group: group)
    }
    
    private func createSubwoofer(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Large cube-like enclosure
        let enclosure = SCNBox(width: CGFloat(asset.size.x), 
                              height: CGFloat(asset.size.y), 
                              length: CGFloat(asset.size.z), 
                              chamferRadius: 0.05)
        enclosure.materials = [material]
        let enclosureNode = SCNNode(geometry: enclosure)
        enclosureNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(enclosureNode)
        
        // Large woofer driver
        let driverMaterial = SCNMaterial()
        driverMaterial.diffuse.contents = UXColor.darkGray
        driverMaterial.metalness.contents = 0.3
        
        let woofer = SCNCylinder(radius: CGFloat(min(asset.size.x, asset.size.z)) * 0.35, height: 0.02)
        woofer.materials = [driverMaterial]
        let wooferNode = SCNNode(geometry: woofer)
        wooferNode.position = SCNVector3(0, CGFloat(asset.size.y/2), CGFloat(asset.size.z/2) + 0.01)
        wooferNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(wooferNode)
        
        // Port (for bass reflex)
        let port = SCNCylinder(radius: 0.05, height: 0.1)
        let portMaterial = SCNMaterial()
        portMaterial.diffuse.contents = UXColor.black
        portMaterial.metalness.contents = 0.8
        port.materials = [portMaterial]
        let portNode = SCNNode(geometry: port)
        portNode.position = SCNVector3(CGFloat(asset.size.x/3), CGFloat(asset.size.y/2), CGFloat(asset.size.z/2) + 0.05)
        portNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(portNode)
        
        // Handles on sides
        createSpeakerHandles(for: asset, group: group)
    }
    
    private func createMonitorWedge(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Wedge-shaped enclosure (angled)
        let wedgeAngle: Float = -15 * Float.pi / 180 // 15 degrees
        
        let enclosure = SCNBox(width: CGFloat(asset.size.x), 
                              height: CGFloat(asset.size.y), 
                              length: CGFloat(asset.size.z), 
                              chamferRadius: 0.03)
        enclosure.materials = [material]
        let enclosureNode = SCNNode(geometry: enclosure)
        enclosureNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        enclosureNode.eulerAngles = SCNVector3(wedgeAngle, 0, 0) // Angle upward
        group.addChildNode(enclosureNode)
        
        // Driver facing upward at angle
        let driverMaterial = SCNMaterial()
        driverMaterial.diffuse.contents = UXColor.darkGray
        
        let driver = SCNCylinder(radius: CGFloat(asset.size.x) * 0.25, height: 0.01)
        driver.materials = [driverMaterial]
        let driverNode = SCNNode(geometry: driver)
        driverNode.position = SCNVector3(0, CGFloat(asset.size.y/2), CGFloat(asset.size.z/2) + 0.005)
        driverNode.eulerAngles = SCNVector3(Float.pi/2 + wedgeAngle, 0, 0)
        group.addChildNode(driverNode)
        
        // Horn tweeter
        let horn = SCNCone(topRadius: 0.02, bottomRadius: 0.06, height: 0.03)
        horn.materials = [driverMaterial]
        let hornNode = SCNNode(geometry: horn)
        hornNode.position = SCNVector3(CGFloat(asset.size.x/4), CGFloat(asset.size.y/2), CGFloat(asset.size.z/2) + 0.015)
        hornNode.eulerAngles = SCNVector3(Float.pi/2 + wedgeAngle, 0, 0)
        group.addChildNode(hornNode)
    }
    
    private func createMainSpeakerStack(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Stack of multiple speaker boxes
        let numBoxes = 3
        let boxHeight = CGFloat(asset.size.y) / CGFloat(numBoxes)
        
        for i in 0..<numBoxes {
            let boxY = CGFloat(i) * boxHeight + boxHeight/2
            
            let box = SCNBox(width: CGFloat(asset.size.x), 
                           height: boxHeight - 0.02, // Small gap between boxes
                           length: CGFloat(asset.size.z), 
                           chamferRadius: 0.03)
            box.materials = [material]
            let boxNode = SCNNode(geometry: box)
            boxNode.position = SCNVector3(0, boxY, 0)
            group.addChildNode(boxNode)
            
            // Different drivers for each box
            let driverMaterial = SCNMaterial()
            driverMaterial.diffuse.contents = UXColor.darkGray
            
            if i == 0 { // Bottom box - subwoofers
                let woofer = SCNCylinder(radius: CGFloat(asset.size.x) * 0.25, height: 0.01)
                woofer.materials = [driverMaterial]
                let wooferNode = SCNNode(geometry: woofer)
                wooferNode.position = SCNVector3(0, boxY, CGFloat(asset.size.z/2) + 0.005)
                wooferNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
                group.addChildNode(wooferNode)
            } else { // Mid/high boxes
                let midDriver = SCNCylinder(radius: CGFloat(asset.size.x) * 0.15, height: 0.01)
                midDriver.materials = [driverMaterial]
                let midNode = SCNNode(geometry: midDriver)
                midNode.position = SCNVector3(-CGFloat(asset.size.x/4), boxY, CGFloat(asset.size.z/2) + 0.005)
                midNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
                group.addChildNode(midNode)
                
                let tweeter = SCNCylinder(radius: CGFloat(asset.size.x) * 0.08, height: 0.01)
                tweeter.materials = [driverMaterial]
                let tweeterNode = SCNNode(geometry: tweeter)
                tweeterNode.position = SCNVector3(CGFloat(asset.size.x/4), boxY, CGFloat(asset.size.z/2) + 0.005)
                tweeterNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
                group.addChildNode(tweeterNode)
            }
        }
    }
    
    private func createSideFillSpeaker(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Similar to main speaker but smaller and typically mounted on a pole
        createGenericSpeaker(asset: asset, group: group, material: material)
        
        // Add mounting pole
        let poleMaterial = SCNMaterial()
        poleMaterial.diffuse.contents = UXColor.darkGray
        poleMaterial.metalness.contents = 0.8
        
        let pole = SCNCylinder(radius: 0.02, height: CGFloat(asset.size.y) + 0.5)
        pole.materials = [poleMaterial]
        let poleNode = SCNNode(geometry: pole)
        poleNode.position = SCNVector3(0, -0.25, 0)
        group.addChildNode(poleNode)
    }
    
    private func createDelayTower(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Tall tower with speakers mounted at different heights
        let poleMaterial = SCNMaterial()
        poleMaterial.diffuse.contents = UXColor.darkGray
        poleMaterial.metalness.contents = 0.8
        
        // Main tower pole
        let pole = SCNCylinder(radius: CGFloat(asset.size.x/2), height: CGFloat(asset.size.y))
        pole.materials = [poleMaterial]
        let poleNode = SCNNode(geometry: pole)
        poleNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(poleNode)
        
        // Speakers mounted at different heights
        let numSpeakers = 4
        for i in 0..<numSpeakers {
            let speakerY = CGFloat(asset.size.y) * (0.3 + 0.5 * CGFloat(i) / CGFloat(numSpeakers - 1))
            
            let speaker = SCNBox(width: 0.4, height: 0.2, length: 0.3, chamferRadius: 0.02)
            speaker.materials = [material]
            let speakerNode = SCNNode(geometry: speaker)
            speakerNode.position = SCNVector3(CGFloat(asset.size.x/2) + 0.2, speakerY, 0)
            group.addChildNode(speakerNode)
            
            // Driver
            let driver = SCNCylinder(radius: 0.08, height: 0.01)
            let driverMaterial = SCNMaterial()
            driverMaterial.diffuse.contents = UXColor.darkGray
            driver.materials = [driverMaterial]
            let driverNode = SCNNode(geometry: driver)
            driverNode.position = SCNVector3(CGFloat(asset.size.x/2) + 0.35, speakerY, 0)
            driverNode.eulerAngles = SCNVector3(0, 0, Float.pi/2)
            group.addChildNode(driverNode)
        }
    }
    
    private func createGenericSpeaker(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Basic speaker box
        let enclosure = SCNBox(width: CGFloat(asset.size.x), 
                              height: CGFloat(asset.size.y), 
                              length: CGFloat(asset.size.z), 
                              chamferRadius: 0.03)
        enclosure.materials = [material]
        let enclosureNode = SCNNode(geometry: enclosure)
        enclosureNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(enclosureNode)
        
        // Basic driver
        let driverMaterial = SCNMaterial()
        driverMaterial.diffuse.contents = UXColor.darkGray
        let driver = SCNCylinder(radius: CGFloat(min(asset.size.x, asset.size.z)) * 0.25, height: 0.01)
        driver.materials = [driverMaterial]
        let driverNode = SCNNode(geometry: driver)
        driverNode.position = SCNVector3(0, CGFloat(asset.size.y/2), CGFloat(asset.size.z/2) + 0.005)
        driverNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(driverNode)
    }
    
    private func createRiggingPoints(for asset: StagingAsset, group: SCNNode) {
        let riggingMaterial = SCNMaterial()
        riggingMaterial.diffuse.contents = UXColor.systemYellow
        riggingMaterial.metalness.contents = 0.8
        
        // Top rigging points
        let pointPositions = [
            SCNVector3(-CGFloat(asset.size.x/3), CGFloat(asset.size.y), 0),
            SCNVector3(CGFloat(asset.size.x/3), CGFloat(asset.size.y), 0)
        ]
        
        for position in pointPositions {
            let riggingPoint = SCNSphere(radius: 0.02)
            riggingPoint.materials = [riggingMaterial]
            let pointNode = SCNNode(geometry: riggingPoint)
            pointNode.position = position
            group.addChildNode(pointNode)
        }
    }
    
    private func createSpeakerHandles(for asset: StagingAsset, group: SCNNode) {
        let handleMaterial = SCNMaterial()
        handleMaterial.diffuse.contents = UXColor.darkGray
        handleMaterial.metalness.contents = 0.8
        
        let handlePositions = [
            SCNVector3(-CGFloat(asset.size.x/2) - 0.02, CGFloat(asset.size.y/2), 0),
            SCNVector3(CGFloat(asset.size.x/2) + 0.02, CGFloat(asset.size.y/2), 0)
        ]
        
        for position in handlePositions {
            let handle = SCNTorus(ringRadius: 0.04, pipeRadius: 0.01)
            handle.materials = [handleMaterial]
            let handleNode = SCNNode(geometry: handle)
            handleNode.position = position
            handleNode.eulerAngles = SCNVector3(0, Float.pi/2, 0)
            group.addChildNode(handleNode)
        }
    }
    
    private func createRiggingGeometry(asset: StagingAsset, group: SCNNode) {
        let riggingMaterial = SCNMaterial()
        riggingMaterial.diffuse.contents = UXColor.systemYellow
        riggingMaterial.metalness.contents = 0.9
        riggingMaterial.roughness.contents = 0.2
        
        switch asset.name.lowercased() {
        case let name where name.contains("chain hoist"):
            createChainHoist(asset: asset, group: group, material: riggingMaterial)
        case let name where name.contains("rigging point"):
            createRiggingPoint(asset: asset, group: group, material: riggingMaterial)
        case let name where name.contains("shackle"):
            createShackle(asset: asset, group: group, material: riggingMaterial)
        case let name where name.contains("span set"):
            createSpanSet(asset: asset, group: group, material: riggingMaterial)
        case let name where name.contains("bridle"):
            createBridleAssembly(asset: asset, group: group, material: riggingMaterial)
        default:
            createGenericRigging(asset: asset, group: group, material: riggingMaterial)
        }
    }
    
    private func createChainHoist(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Motor housing
        let housing = SCNBox(width: CGFloat(asset.size.x), 
                           height: CGFloat(asset.size.y) * 0.4, 
                           length: CGFloat(asset.size.z), 
                           chamferRadius: 0.02)
        let housingMaterial = SCNMaterial()
        housingMaterial.diffuse.contents = UXColor.black
        housingMaterial.metalness.contents = 0.8
        housing.materials = [housingMaterial]
        
        let housingNode = SCNNode(geometry: housing)
        housingNode.position = SCNVector3(0, CGFloat(asset.size.y) * 0.8, 0)
        group.addChildNode(housingNode)
        
        // Chain
        let chainLength = CGFloat(asset.size.y) * 0.6
        let chain = SCNCylinder(radius: 0.01, height: chainLength)
        chain.materials = [material]
        let chainNode = SCNNode(geometry: chain)
        chainNode.position = SCNVector3(0, chainLength/2, 0)
        group.addChildNode(chainNode)
        
        // Hook at bottom
        let hook = SCNTorus(ringRadius: 0.03, pipeRadius: 0.008)
        hook.materials = [material]
        let hookNode = SCNNode(geometry: hook)
        hookNode.position = SCNVector3(0, 0, 0)
        group.addChildNode(hookNode)
        
        // Rigging point at top
        let riggingPoint = SCNSphere(radius: 0.02)
        riggingPoint.materials = [material]
        let pointNode = SCNNode(geometry: riggingPoint)
        pointNode.position = SCNVector3(0, CGFloat(asset.size.y), 0)
        group.addChildNode(pointNode)
    }
    
    private func createRiggingPoint(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Certified rigging point
        let point = SCNSphere(radius: CGFloat(asset.size.x/2))
        point.materials = [material]
        let pointNode = SCNNode(geometry: point)
        group.addChildNode(pointNode)
        
        // Safety rating plate
        let plate = SCNBox(width: CGFloat(asset.size.x) * 1.5, 
                          height: 0.01, 
                          length: CGFloat(asset.size.z) * 1.5, 
                          chamferRadius: 0.001)
        let plateMaterial = SCNMaterial()
        plateMaterial.diffuse.contents = UXColor.systemRed
        plate.materials = [plateMaterial]
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(0, CGFloat(asset.size.y/2) + 0.005, 0)
        group.addChildNode(plateNode)
    }
    
    private func createShackle(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // U-shaped shackle
        let shackleRadius = CGFloat(asset.size.x/2)
        let shackle = SCNTorus(ringRadius: shackleRadius, pipeRadius: CGFloat(asset.size.z))
        shackle.materials = [material]
        let shackleNode = SCNNode(geometry: shackle)
        shackleNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(shackleNode)
        
        // Pin
        let pin = SCNCylinder(radius: CGFloat(asset.size.z) * 0.8, height: shackleRadius * 2.2)
        pin.materials = [material]
        let pinNode = SCNNode(geometry: pin)
        pinNode.position = SCNVector3(0, 0, 0)
        pinNode.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        group.addChildNode(pinNode)
    }
    
    private func createSpanSet(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Flat rigging strap
        let strap = SCNBox(width: CGFloat(asset.size.x), 
                          height: CGFloat(asset.size.y), 
                          length: CGFloat(asset.size.z), 
                          chamferRadius: 0.005)
        let strapMaterial = SCNMaterial()
        strapMaterial.diffuse.contents = UXColor.systemPurple
        strap.materials = [strapMaterial]
        let strapNode = SCNNode(geometry: strap)
        group.addChildNode(strapNode)
        
        // End loops
        let loopRadius = CGFloat(asset.size.y) * 2
        for x in [-CGFloat(asset.size.x/2), CGFloat(asset.size.x/2)] {
            let loop = SCNTorus(ringRadius: loopRadius, pipeRadius: CGFloat(asset.size.y))
            loop.materials = [strapMaterial]
            let loopNode = SCNNode(geometry: loop)
            loopNode.position = SCNVector3(x, 0, 0)
            loopNode.eulerAngles = SCNVector3(0, 0, Float.pi/2)
            group.addChildNode(loopNode)
        }
    }
    
    private func createBridleAssembly(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Central attachment point
        let center = SCNSphere(radius: 0.03)
        center.materials = [material]
        let centerNode = SCNNode(geometry: center)
        group.addChildNode(centerNode)
        
        // Bridle legs to corners
        let corners = [
            SCNVector3(CGFloat(asset.size.x/2), CGFloat(asset.size.y/2), 0),
            SCNVector3(-CGFloat(asset.size.x/2), CGFloat(asset.size.y/2), 0),
            SCNVector3(0, CGFloat(asset.size.y/2), CGFloat(asset.size.z/2)),
            SCNVector3(0, CGFloat(asset.size.y/2), -CGFloat(asset.size.z/2))
        ]
        
        for corner in corners {
            // Cable from center to corner
            let length = sqrt(pow(corner.x, 2) + pow(corner.y, 2) + pow(corner.z, 2))
            let cable = SCNCylinder(radius: 0.005, height: CGFloat(length))
            cable.materials = [material]
            let cableNode = SCNNode(geometry: cable)
            cableNode.position = SCNVector3(corner.x/2, corner.y/2, corner.z/2)
            cableNode.look(at: corner, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
            group.addChildNode(cableNode)
            
            // Corner attachment
            let attachment = SCNSphere(radius: 0.02)
            attachment.materials = [material]
            let attachmentNode = SCNNode(geometry: attachment)
            attachmentNode.position = corner
            group.addChildNode(attachmentNode)
        }
    }
    
    private func createGenericRigging(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        let rigging = SCNBox(width: CGFloat(asset.size.x), 
                           height: CGFloat(asset.size.y), 
                           length: CGFloat(asset.size.z), 
                           chamferRadius: 0.01)
        rigging.materials = [material]
        let riggingNode = SCNNode(geometry: rigging)
        riggingNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(riggingNode)
    }
    
    private func createStagingPlatformGeometry(asset: StagingAsset, group: SCNNode) {
        let stagingMaterial = SCNMaterial()
        stagingMaterial.diffuse.contents = UXColor.systemBrown
        stagingMaterial.roughness.contents = 0.6
        stagingMaterial.metalness.contents = 0.1
        
        switch asset.name.lowercased() {
        case let name where name.contains("stage deck"):
            createStageDeck(asset: asset, group: group, material: stagingMaterial)
        case let name where name.contains("riser"):
            createStageRiser(asset: asset, group: group, material: stagingMaterial)
        case let name where name.contains("catwalk"):
            createCatwalk(asset: asset, group: group, material: stagingMaterial)
        case let name where name.contains("steps"):
            createStageSteps(asset: asset, group: group, material: stagingMaterial)
        case let name where name.contains("orchestra shell"):
            createOrchestraShell(asset: asset, group: group, material: stagingMaterial)
        default:
            createGenericStagingPlatform(asset: asset, group: group, material: stagingMaterial)
        }
    }
    
    private func createStageDeck(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Main deck platform
        let deck = SCNBox(width: CGFloat(asset.size.x), 
                         height: CGFloat(asset.size.y), 
                         length: CGFloat(asset.size.z), 
                         chamferRadius: 0.01)
        deck.materials = [material]
        let deckNode = SCNNode(geometry: deck)
        deckNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(deckNode)
        
        // Support legs underneath
        let legMaterial = SCNMaterial()
        legMaterial.diffuse.contents = UXColor.darkGray
        legMaterial.metalness.contents = 0.8
        
        let legPositions = [
            SCNVector3(CGFloat(asset.size.x/2) - 0.1, CGFloat(asset.size.y/4), CGFloat(asset.size.z/2) - 0.1),
            SCNVector3(-CGFloat(asset.size.x/2) + 0.1, CGFloat(asset.size.y/4), CGFloat(asset.size.z/2) - 0.1),
            SCNVector3(CGFloat(asset.size.x/2) - 0.1, CGFloat(asset.size.y/4), -CGFloat(asset.size.z/2) + 0.1),
            SCNVector3(-CGFloat(asset.size.x/2) + 0.1, CGFloat(asset.size.y/4), -CGFloat(asset.size.z/2) + 0.1)
        ]
        
        for position in legPositions {
            let leg = SCNCylinder(radius: 0.03, height: CGFloat(asset.size.y/2))
            leg.materials = [legMaterial]
            let legNode = SCNNode(geometry: leg)
            legNode.position = position
            group.addChildNode(legNode)
        }
        
        // Edge trim
        createDeckEdgeTrim(asset: asset, group: group)
    }
    
    private func createStageRiser(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Higher platform than regular deck
        createStageDeck(asset: asset, group: group, material: material)
        
        // Additional front fascia
        let fascia = SCNBox(width: CGFloat(asset.size.x), 
                           height: CGFloat(asset.size.y) - 0.05, 
                           length: 0.02, 
                           chamferRadius: 0.01)
        let fasciaMaterial = SCNMaterial()
        fasciaMaterial.diffuse.contents = UXColor.black
        fascia.materials = [fasciaMaterial]
        let fasciaNode = SCNNode(geometry: fascia)
        fasciaNode.position = SCNVector3(0, CGFloat(asset.size.y/2) - 0.025, CGFloat(asset.size.z/2) + 0.01)
        group.addChildNode(fasciaNode)
    }
    
    private func createCatwalk(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Main walkway
        let walkway = SCNBox(width: CGFloat(asset.size.x), 
                           height: CGFloat(asset.size.y), 
                           length: CGFloat(asset.size.z), 
                           chamferRadius: 0.01)
        walkway.materials = [material]
        let walkwayNode = SCNNode(geometry: walkway)
        walkwayNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(walkwayNode)
        
        // Safety railings
        let railMaterial = SCNMaterial()
        railMaterial.diffuse.contents = UXColor.systemYellow
        railMaterial.metalness.contents = 0.8
        
        // Side railings
        for side in [-1, 1] {
            let railZ = Float(side) * Float(asset.size.z/2)
            
            // Top rail
            let topRail = SCNCylinder(radius: 0.02, height: CGFloat(asset.size.x))
            topRail.materials = [railMaterial]
            let topRailNode = SCNNode(geometry: topRail)
            topRailNode.position = SCNVector3(0, CGFloat(asset.size.y) + 0.9, CGFloat(railZ))
            topRailNode.eulerAngles = SCNVector3(0, 0, Float.pi/2)
            group.addChildNode(topRailNode)
            
            // Support posts
            let numPosts = max(2, Int(asset.size.x / 1.5))
            for i in 0..<numPosts {
                let postX = (CGFloat(i) / CGFloat(numPosts - 1)) * CGFloat(asset.size.x) - CGFloat(asset.size.x/2)
                
                let post = SCNCylinder(radius: 0.02, height: 0.9)
                post.materials = [railMaterial]
                let postNode = SCNNode(geometry: post)
                postNode.position = SCNVector3(postX, CGFloat(asset.size.y) + 0.45, CGFloat(railZ))
                group.addChildNode(postNode)
            }
        }
    }
    
    private func createStageSteps(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        let numSteps = Int(asset.size.y / 0.2) // 20cm per step
        let stepHeight = CGFloat(asset.size.y) / CGFloat(numSteps)
        let stepDepth = CGFloat(asset.size.z) / CGFloat(numSteps)
        
        for i in 0..<numSteps {
            let stepY = CGFloat(i) * stepHeight + stepHeight/2
            let stepZ = CGFloat(asset.size.z/2) - CGFloat(i) * stepDepth - stepDepth/2
            
            let step = SCNBox(width: CGFloat(asset.size.x), 
                            height: stepHeight, 
                            length: stepDepth, 
                            chamferRadius: 0.01)
            step.materials = [material]
            let stepNode = SCNNode(geometry: step)
            stepNode.position = SCNVector3(0, stepY, stepZ)
            group.addChildNode(stepNode)
        }
        
        // Handrail
        let railMaterial = SCNMaterial()
        railMaterial.diffuse.contents = UXColor.systemBlue
        railMaterial.metalness.contents = 0.8
        
        let handrail = SCNCylinder(radius: 0.02, height: CGFloat(asset.size.z))
        handrail.materials = [railMaterial]
        let handrailNode = SCNNode(geometry: handrail)
        handrailNode.position = SCNVector3(CGFloat(asset.size.x/2) + 0.1, CGFloat(asset.size.y) * 0.8, 0)
        handrailNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(handrailNode)
    }
    
    private func createOrchestraShell(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Curved acoustic panel
        let shellMaterial = SCNMaterial()
        shellMaterial.diffuse.contents = UXColor.systemBrown
        shellMaterial.roughness.contents = 0.4
        
        // Main curved panel - approximate with angled flat panel
        let panel = SCNBox(width: CGFloat(asset.size.x), 
                          height: CGFloat(asset.size.y), 
                          length: CGFloat(asset.size.z), 
                          chamferRadius: 0.05)
        panel.materials = [shellMaterial]
        let panelNode = SCNNode(geometry: panel)
        panelNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        panelNode.eulerAngles = SCNVector3(0, Float.pi/8, 0) // Slight curve simulation
        group.addChildNode(panelNode)
        
        // Support frame
        let frameMaterial = SCNMaterial()
        frameMaterial.diffuse.contents = UXColor.darkGray
        frameMaterial.metalness.contents = 0.8
        
        // Vertical supports
        for x in [-CGFloat(asset.size.x/2), CGFloat(asset.size.x/2)] {
            let support = SCNCylinder(radius: 0.03, height: CGFloat(asset.size.y))
            support.materials = [frameMaterial]
            let supportNode = SCNNode(geometry: support)
            supportNode.position = SCNVector3(x, CGFloat(asset.size.y/2), -CGFloat(asset.size.z/2) - 0.05)
            group.addChildNode(supportNode)
        }
    }
    
    private func createGenericStagingPlatform(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        let platform = SCNBox(width: CGFloat(asset.size.x), 
                             height: CGFloat(asset.size.y), 
                             length: CGFloat(asset.size.z), 
                             chamferRadius: 0.02)
        platform.materials = [material]
        let platformNode = SCNNode(geometry: platform)
        platformNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(platformNode)
    }
    
    private func createDeckEdgeTrim(asset: StagingAsset, group: SCNNode) {
        let trimMaterial = SCNMaterial()
        trimMaterial.diffuse.contents = UXColor.darkGray
        trimMaterial.metalness.contents = 0.8
        
        let trimHeight: CGFloat = 0.03
        let trimDepth: CGFloat = 0.02
        
        // Front and back trim
        for z in [-CGFloat(asset.size.z/2), CGFloat(asset.size.z/2)] {
            let trim = SCNBox(width: CGFloat(asset.size.x), 
                            height: trimHeight, 
                            length: trimDepth, 
                            chamferRadius: 0.005)
            trim.materials = [trimMaterial]
            let trimNode = SCNNode(geometry: trim)
            trimNode.position = SCNVector3(0, CGFloat(asset.size.y) + trimHeight/2, z)
            group.addChildNode(trimNode)
        }
        
        // Left and right trim
        for x in [-CGFloat(asset.size.x/2), CGFloat(asset.size.x/2)] {
            let trim = SCNBox(width: trimDepth, 
                            height: trimHeight, 
                            length: CGFloat(asset.size.z), 
                            chamferRadius: 0.005)
            trim.materials = [trimMaterial]
            let trimNode = SCNNode(geometry: trim)
            trimNode.position = SCNVector3(x, CGFloat(asset.size.y) + trimHeight/2, 0)
            group.addChildNode(trimNode)
        }
    }
    
    private func createEffectsGeometry(asset: StagingAsset, group: SCNNode) {
        let effectsMaterial = SCNMaterial()
        effectsMaterial.diffuse.contents = UXColor.systemPurple
        effectsMaterial.roughness.contents = 0.7
        
        switch asset.name.lowercased() {
        case let name where name.contains("fog machine"):
            createFogMachine(asset: asset, group: group, material: effectsMaterial)
        case let name where name.contains("haze machine"):
            createHazeMachine(asset: asset, group: group, material: effectsMaterial)
        case let name where name.contains("pyro"):
            createPyroLauncher(asset: asset, group: group, material: effectsMaterial)
        case let name where name.contains("confetti"):
            createConfettiCannon(asset: asset, group: group, material: effectsMaterial)
        case let name where name.contains("wind"):
            createWindMachine(asset: asset, group: group, material: effectsMaterial)
        case let name where name.contains("bubble"):
            createBubbleMachine(asset: asset, group: group, material: effectsMaterial)
        default:
            createGenericEffectsMachine(asset: asset, group: group, material: effectsMaterial)
        }
    }
    
    private func createFogMachine(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Main machine body
        let body = SCNBox(width: CGFloat(asset.size.x), 
                         height: CGFloat(asset.size.y), 
                         length: CGFloat(asset.size.z), 
                         chamferRadius: 0.05)
        body.materials = [material]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(bodyNode)
        
        // Output nozzle
        let nozzle = SCNCylinder(radius: 0.04, height: 0.15)
        let nozzleMaterial = SCNMaterial()
        nozzleMaterial.diffuse.contents = UXColor.black
        nozzleMaterial.metalness.contents = 0.8
        nozzle.materials = [nozzleMaterial]
        let nozzleNode = SCNNode(geometry: nozzle)
        nozzleNode.position = SCNVector3(0, CGFloat(asset.size.y/2), CGFloat(asset.size.z/2) + 0.075)
        nozzleNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(nozzleNode)
        
        // Control panel
        let panel = SCNBox(width: 0.15, height: 0.08, length: 0.02, chamferRadius: 0.01)
        let panelMaterial = SCNMaterial()
        panelMaterial.diffuse.contents = UXColor.black
        panelMaterial.emission.contents = UXColor.systemBlue
        panelMaterial.emission.intensity = 0.3
        panel.materials = [panelMaterial]
        let panelNode = SCNNode(geometry: panel)
        panelNode.position = SCNVector3(CGFloat(asset.size.x/2) + 0.01, CGFloat(asset.size.y/2), 0)
        group.addChildNode(panelNode)
    }
    
    private func createHazeMachine(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Similar to fog machine but smaller and more subtle
        createFogMachine(asset: asset, group: group, material: material)
        
        // Add "HAZE" label
        let label = SCNBox(width: 0.1, height: 0.02, length: 0.001, chamferRadius: 0.001)
        let labelMaterial = SCNMaterial()
        labelMaterial.diffuse.contents = UXColor.white
        labelMaterial.emission.contents = UXColor.white
        labelMaterial.emission.intensity = 0.5
        label.materials = [labelMaterial]
        let labelNode = SCNNode(geometry: label)
        labelNode.position = SCNVector3(0, CGFloat(asset.size.y) + 0.01, CGFloat(asset.size.z/4))
        group.addChildNode(labelNode)
    }
    
    private func createPyroLauncher(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Cylindrical launcher
        let launcher = SCNCylinder(radius: CGFloat(asset.size.x/2), height: CGFloat(asset.size.y))
        let launcherMaterial = SCNMaterial()
        launcherMaterial.diffuse.contents = UXColor.systemRed
        launcherMaterial.metalness.contents = 0.8
        launcher.materials = [launcherMaterial]
        let launcherNode = SCNNode(geometry: launcher)
        launcherNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(launcherNode)
        
        // Warning labels
        let warning = SCNBox(width: 0.08, height: 0.08, length: 0.001, chamferRadius: 0.001)
        let warningMaterial = SCNMaterial()
        warningMaterial.diffuse.contents = UXColor.systemYellow
        warningMaterial.emission.contents = UXColor.systemRed
        warningMaterial.emission.intensity = 0.8
        warning.materials = [warningMaterial]
        let warningNode = SCNNode(geometry: warning)
        warningNode.position = SCNVector3(0, CGFloat(asset.size.y/2), CGFloat(asset.size.x/2) + 0.001)
        group.addChildNode(warningNode)
        
        // Base with safety features
        let base = SCNCylinder(radius: CGFloat(asset.size.x/2) + 0.05, height: 0.05)
        let baseMaterial = SCNMaterial()
        baseMaterial.diffuse.contents = UXColor.black
        baseMaterial.metalness.contents = 0.9
        base.materials = [baseMaterial]
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, 0.025, 0)
        group.addChildNode(baseNode)
    }
    
    private func createConfettiCannon(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Smaller cylindrical cannon
        let cannon = SCNCylinder(radius: CGFloat(asset.size.x/2), height: CGFloat(asset.size.y))
        let cannonMaterial = SCNMaterial()
        cannonMaterial.diffuse.contents = UXColor.systemBlue
        cannonMaterial.metalness.contents = 0.6
        cannon.materials = [cannonMaterial]
        let cannonNode = SCNNode(geometry: cannon)
        cannonNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(cannonNode)
        
        // Colorful accent rings
        let colors = [UXColor.systemRed, UXColor.systemYellow, UXColor.systemGreen]
        for (i, color) in colors.enumerated() {
            let ring = SCNTorus(ringRadius: CGFloat(asset.size.x/2) + 0.01, pipeRadius: 0.01)
            let ringMaterial = SCNMaterial()
            ringMaterial.diffuse.contents = color
            ringMaterial.emission.contents = color
            ringMaterial.emission.intensity = 0.5
            ring.materials = [ringMaterial]
            let ringNode = SCNNode(geometry: ring)
            ringNode.position = SCNVector3(0, CGFloat(asset.size.y) * (0.3 + 0.2 * CGFloat(i)), 0)
            group.addChildNode(ringNode)
        }
    }
    
    private func createWindMachine(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Main fan housing
        let housing = SCNBox(width: CGFloat(asset.size.x), 
                           height: CGFloat(asset.size.y), 
                           length: CGFloat(asset.size.z), 
                           chamferRadius: 0.1)
        let housingMaterial = SCNMaterial()
        housingMaterial.diffuse.contents = UXColor.systemGray
        housingMaterial.metalness.contents = 0.8
        housing.materials = [housingMaterial]
        let housingNode = SCNNode(geometry: housing)
        housingNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(housingNode)
        
        // Fan blades (simplified as a disc)
        let fan = SCNCylinder(radius: CGFloat(min(asset.size.x, asset.size.y)) * 0.4, height: 0.02)
        let fanMaterial = SCNMaterial()
        fanMaterial.diffuse.contents = UXColor.lightGray
        fanMaterial.transparency = 0.7
        fan.materials = [fanMaterial]
        let fanNode = SCNNode(geometry: fan)
        fanNode.position = SCNVector3(0, CGFloat(asset.size.y/2), CGFloat(asset.size.z/2) + 0.01)
        fanNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(fanNode)
        
        // Protective grille
        let grille = SCNTorus(ringRadius: CGFloat(min(asset.size.x, asset.size.y)) * 0.4, pipeRadius: 0.01)
        let grilleMaterial = SCNMaterial()
        grilleMaterial.diffuse.contents = UXColor.darkGray
        grilleMaterial.metalness.contents = 0.9
        grille.materials = [grilleMaterial]
        let grilleNode = SCNNode(geometry: grille)
        grilleNode.position = SCNVector3(0, CGFloat(asset.size.y/2), CGFloat(asset.size.z/2) + 0.02)
        grilleNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        group.addChildNode(grilleNode)
    }
    
    private func createBubbleMachine(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        // Main machine body
        let body = SCNBox(width: CGFloat(asset.size.x), 
                         height: CGFloat(asset.size.y), 
                         length: CGFloat(asset.size.z), 
                         chamferRadius: 0.05)
        let bodyMaterial = SCNMaterial()
        bodyMaterial.diffuse.contents = UXColor.systemTeal
        bodyMaterial.roughness.contents = 0.3
        bodyMaterial.metalness.contents = 0.2
        body.materials = [bodyMaterial]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(bodyNode)
        
        // Bubble output holes
        let numHoles = 6
        for i in 0..<numHoles {
            let angle = Float(i) * 2 * Float.pi / Float(numHoles)
            let radius = CGFloat(asset.size.x) * 0.3
            let holeX = radius * cos(CGFloat(angle))
            let holeZ = radius * sin(CGFloat(angle))
            
            let hole = SCNCylinder(radius: 0.01, height: 0.02)
            let holeMaterial = SCNMaterial()
            holeMaterial.diffuse.contents = UXColor.black
            hole.materials = [holeMaterial]
            let holeNode = SCNNode(geometry: hole)
            holeNode.position = SCNVector3(holeX, CGFloat(asset.size.y) + 0.01, holeZ)
            group.addChildNode(holeNode)
        }
        
        // Fluid reservoir (transparent)
        let reservoir = SCNBox(width: CGFloat(asset.size.x) * 0.6, 
                              height: CGFloat(asset.size.y) * 0.3, 
                              length: CGFloat(asset.size.z) * 0.6, 
                              chamferRadius: 0.02)
        let reservoirMaterial = SCNMaterial()
        reservoirMaterial.diffuse.contents = UXColor.systemBlue
        reservoirMaterial.transparency = 0.3
        reservoir.materials = [reservoirMaterial]
        let reservoirNode = SCNNode(geometry: reservoir)
        reservoirNode.position = SCNVector3(0, CGFloat(asset.size.y) * 0.75, 0)
        group.addChildNode(reservoirNode)
    }
    
    private func createGenericEffectsMachine(asset: StagingAsset, group: SCNNode, material: SCNMaterial) {
        let machine = SCNBox(width: CGFloat(asset.size.x), 
                           height: CGFloat(asset.size.y), 
                           length: CGFloat(asset.size.z), 
                           chamferRadius: 0.05)
        machine.materials = [material]
        let machineNode = SCNNode(geometry: machine)
        machineNode.position = SCNVector3(0, CGFloat(asset.size.y/2), 0)
        group.addChildNode(machineNode)
        
        // Generic control panel
        let panel = SCNBox(width: 0.1, height: 0.05, length: 0.01, chamferRadius: 0.005)
        let panelMaterial = SCNMaterial()
        panelMaterial.diffuse.contents = UXColor.black
        panelMaterial.emission.contents = UXColor.systemGreen
        panelMaterial.emission.intensity = 0.3
        panel.materials = [panelMaterial]
        let panelNode = SCNNode(geometry: panel)
        panelNode.position = SCNVector3(CGFloat(asset.size.x/2) + 0.005, CGFloat(asset.size.y/2), 0)
        group.addChildNode(panelNode)
    }
    
    func deleteSelectedObjects() {
        let selectedObjs = studioObjects.filter { $0.isSelected }
        
        for obj in selectedObjs {
            deleteObject(obj)
        }
        
        print("🗑️ Deleted \(selectedObjs.count) selected objects")
    }
    
    // MARK: - Debug and Testing Methods
    
    func testSelectionSystem() {
        print("🧪 TESTING SELECTION SYSTEM")
        print("   Total objects: \(studioObjects.count)")
        
        for (index, obj) in studioObjects.enumerated() {
            print("   Object \(index): \(obj.name)")
            print("     - Node name: \(obj.node.name ?? "unnamed")")
            print("     - Node position: \(obj.node.position)")
            print("     - Object position: \(obj.position)")
            print("     - Node bounds: \(obj.node.boundingBox)")
            print("     - Has geometry: \(obj.node.geometry != nil)")
            print("     - Has highlight: \(obj.node.childNodes.contains { $0.name?.contains("selection_outline") == true })")
            print("     - Is selected: \(obj.isSelected)")
            
            // Check highlight position if it exists
            if let highlight = obj.node.childNodes.first(where: { $0.name?.contains("selection_outline") == true }) {
                print("     - Highlight position: \(highlight.position)")
            }
            
            // Force highlight setup if missing
            if !obj.node.childNodes.contains(where: { $0.name?.contains("selection_outline") == true }) {
                print("     - ⚠️ Missing selection outline, setting up now...")
                obj.setupHighlightAfterGeometry()
            }
        }
        
        // Test selection on first object
        if let firstObj = studioObjects.first {
            print("🎯 Testing selection on: \(firstObj.name)")
            firstObj.setSelected(true)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                firstObj.setSelected(false)
                print("🔄 Deselected test object")
            }
        }
    }
    
    func resetObjectHighlights() {
        print("🔄 Resetting all object highlights...")
        for obj in studioObjects {
            // Remove existing highlight
            obj.node.childNodes.forEach { child in
                if child.name?.contains("selection_outline") == true {
                    child.removeFromParentNode()
                }
            }
            
            // Recreate highlight
            obj.setupHighlightAfterGeometry()
        }
        print("✅ Reset highlights for \(studioObjects.count) objects")
    }
}
