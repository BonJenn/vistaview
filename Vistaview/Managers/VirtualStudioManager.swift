import Foundation
import SceneKit
import SwiftUI

@MainActor
class VirtualStudioManager: ObservableObject {
    let scene = SCNScene()
    
    @Published var studioObjects: [StudioObject] = []
    @Published var virtualCameras: [VirtualCamera] = []
    @Published var selectedCamera: VirtualCamera?
    
    private var floorNode: SCNNode = SCNNode() // Initialize with empty node
    private var lightNodes: [SCNNode] = []
    
    init() {
        // Create floor after initialization
        setupScene()
    }
    
    // MARK: - Scene Setup
    
    private func setupScene() {
        // Create floor
        floorNode = createFloor()
        scene.rootNode.addChildNode(floorNode)
        
        // Add default lighting
        setupDefaultLighting()
        
        // Add default camera
        addDefaultCamera()
        
        // Create sample studio setup
        createDefaultStudio()
    }
    
    private func createFloor() -> SCNNode {
        let floor = SCNFloor()
        floor.reflectivity = 0.1
        floor.reflectionFalloffEnd = 50
        
        let floorMaterial = SCNMaterial()
        floorMaterial.diffuse.contents = NSColor.darkGray
        floorMaterial.specular.contents = NSColor.white
        floor.materials = [floorMaterial]
        
        let floorNode = SCNNode(geometry: floor)
        floorNode.name = "Floor"
        
        // Add grid pattern
        addGridToFloor(floorNode)
        
        return floorNode
    }
    
    private func addGridToFloor(_ floorNode: SCNNode) {
        let gridSize: Float = 100
        let gridSpacing: Float = 1
        
        for i in stride(from: -gridSize, through: gridSize, by: gridSpacing) {
            // X lines
            let xLine = createLine(
                from: SCNVector3(i, 0.001, -gridSize),
                to: SCNVector3(i, 0.001, gridSize),
                color: .gray
            )
            floorNode.addChildNode(xLine)
            
            // Z lines
            let zLine = createLine(
                from: SCNVector3(-gridSize, 0.001, i),
                to: SCNVector3(gridSize, 0.001, i),
                color: .gray
            )
            floorNode.addChildNode(zLine)
        }
        
        // Add major axis lines
        let xAxis = createLine(
            from: SCNVector3(-gridSize, 0.002, 0),
            to: SCNVector3(gridSize, 0.002, 0),
            color: .red
        )
        floorNode.addChildNode(xAxis)
        
        let zAxis = createLine(
            from: SCNVector3(0, 0.002, -gridSize),
            to: SCNVector3(0, 0.002, gridSize),
            color: .blue
        )
        floorNode.addChildNode(zAxis)
    }
    
    private func createLine(from start: SCNVector3, to end: SCNVector3, color: NSColor) -> SCNNode {
        let line = SCNGeometry()
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        line.materials = [material]
        
        let lineNode = SCNNode(geometry: line)
        
        // Create line geometry using SCNBox (simple approach)
        let distance = sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2) + pow(end.z - start.z, 2))
        let box = SCNBox(width: 0.01, height: 0.01, length: CGFloat(distance), chamferRadius: 0)
        box.materials = [material]
        
        lineNode.geometry = box
        lineNode.position = SCNVector3(
            (start.x + end.x) / 2,
            (start.y + end.y) / 2,
            (start.z + end.z) / 2
        )
        
        return lineNode
    }
    
    private func setupDefaultLighting() {
        // Ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 300
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        // Key light
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 1000
        keyLight.castsShadow = true
        let keyLightNode = SCNNode()
        keyLightNode.light = keyLight
        keyLightNode.position = SCNVector3(10, 15, 10)
        keyLightNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(keyLightNode)
        lightNodes.append(keyLightNode)
    }
    
    private func addDefaultCamera() {
        let defaultCamera = VirtualCamera(
            name: "Overview",
            position: SCNVector3(0, 5, 10),
            target: SCNVector3(0, 0, 0)
        )
        virtualCameras.append(defaultCamera)
        selectedCamera = defaultCamera
        
        // Set scene camera
        scene.rootNode.addChildNode(defaultCamera.node)
    }
    
    private func createDefaultStudio() {
        // Add a sample LED wall
        let ledWall = LEDWallAsset.predefinedWalls[0]
        addLEDWall(from: ledWall)
        
        // Add a sample camera
        let camera = CameraAsset.predefinedCameras[0]
        addCamera(from: camera)
    }
    
    // MARK: - Object Management
    
    func addLEDWall(from asset: LEDWallAsset) {
        let ledWall = StudioObject(
            id: UUID(),
            name: asset.name,
            type: .ledWall,
            position: SCNVector3(0, asset.height/2, -5),
            rotation: SCNVector3(0, 0, 0),
            scale: SCNVector3(1, 1, 1)
        )
        
        let geometry = SCNBox(
            width: CGFloat(asset.width),
            height: CGFloat(asset.height),
            length: 0.1,
            chamferRadius: 0
        )
        
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.black
        material.emission.contents = NSColor.blue.withAlphaComponent(0.3)
        geometry.materials = [material]
        
        ledWall.node.geometry = geometry
        ledWall.node.name = "LEDWall_\(ledWall.id)"
        
        scene.rootNode.addChildNode(ledWall.node)
        studioObjects.append(ledWall)
    }
    
    func addCamera(from asset: CameraAsset) {
        let cameraObj = StudioObject(
            id: UUID(),
            name: asset.name,
            type: .camera,
            position: SCNVector3(0, 1.5, 5),
            rotation: SCNVector3(0, 180, 0),
            scale: SCNVector3(1, 1, 1)
        )
        
        // Create camera representation
        let cameraGeometry = SCNBox(width: 0.3, height: 0.2, length: 0.5, chamferRadius: 0.02)
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.darkGray
        cameraGeometry.materials = [material]
        
        cameraObj.node.geometry = cameraGeometry
        cameraObj.node.name = "Camera_\(cameraObj.id)"
        
        // Add camera cone to show field of view
        let cone = SCNPyramid(width: 2, height: 2, length: 3)
        let coneMaterial = SCNMaterial()
        coneMaterial.diffuse.contents = NSColor.yellow.withAlphaComponent(0.2)
        coneMaterial.isDoubleSided = true
        cone.materials = [coneMaterial]
        
        let coneNode = SCNNode(geometry: cone)
        coneNode.position = SCNVector3(0, 0, -1.5)
        coneNode.eulerAngles = SCNVector3(0, 0, Float.pi)
        cameraObj.node.addChildNode(coneNode)
        
        scene.rootNode.addChildNode(cameraObj.node)
        studioObjects.append(cameraObj)
        
        // Add to virtual cameras
        let virtualCam = VirtualCamera(
            name: asset.name,
            position: cameraObj.position,
            target: SCNVector3(0, 0, 0)
        )
        virtualCameras.append(virtualCam)
    }
    
    func addSetPiece(from asset: SetPieceAsset) {
        let setPiece = StudioObject(
            id: UUID(),
            name: asset.name,
            type: .setPiece,
            position: SCNVector3(Float.random(in: -3...3), 0.5, Float.random(in: -3...3)),
            rotation: SCNVector3(0, Float.random(in: 0...360), 0),
            scale: SCNVector3(1, 1, 1)
        )
        
        let geometry = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.1)
        let material = SCNMaterial()
        material.diffuse.contents = asset.color
        geometry.materials = [material]
        
        setPiece.node.geometry = geometry
        setPiece.node.name = "SetPiece_\(setPiece.id)"
        
        scene.rootNode.addChildNode(setPiece.node)
        studioObjects.append(setPiece)
    }
    
    func addCamera() {
        let newCamera = VirtualCamera(
            name: "Camera \(virtualCameras.count + 1)",
            position: SCNVector3(0, 2, 8),
            target: SCNVector3(0, 0, 0)
        )
        
        virtualCameras.append(newCamera)
        scene.rootNode.addChildNode(newCamera.node)
    }
    
    func addObject(type: StudioTool, at position: SCNVector3) {
        switch type {
        case .ledWall:
            let asset = LEDWallAsset.predefinedWalls.randomElement()!
            addLEDWall(from: asset)
        case .camera:
            let asset = CameraAsset.predefinedCameras.randomElement()!
            addCamera(from: asset)
        case .setPiece:
            let asset = SetPieceAsset.predefinedPieces.randomElement()!
            addSetPiece(from: asset)
        default:
            break
        }
    }
    
    func deleteObject(_ object: StudioObject) {
        object.node.removeFromParentNode()
        studioObjects.removeAll { $0.id == object.id }
    }
    
    func getObject(from node: SCNNode) -> StudioObject? {
        return studioObjects.first { $0.node == node }
    }
    
    func selectCamera(_ camera: VirtualCamera) {
        selectedCamera = camera
        
        // Update all cameras' active state
        for cam in virtualCameras {
            cam.isActive = (cam.id == camera.id)
        }
    }
    
    // MARK: - Utility Functions
    
    func worldPosition(from screenPoint: CGPoint, in sceneView: SCNView) -> SCNVector3 {
        let results = sceneView.hitTest(screenPoint, options: [
            SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue
        ])
        
        if let hit = results.first(where: { $0.node == floorNode }) {
            return hit.worldCoordinates
        }
        
        // Fallback: project to floor plane
        return SCNVector3(0, 0, 0)
    }
    
    func resetView() {
        // Reset to default camera position
        if let defaultCam = virtualCameras.first {
            selectedCamera = defaultCam
        }
    }
    
    func exportScene() {
        // TODO: Export scene to file
        print("Exporting scene...")
    }
    
    func importScene() {
        // TODO: Import scene from file
        print("Importing scene...")
    }
    
    func renderPreview() {
        // TODO: Render high-quality preview
        print("Rendering preview...")
    }
}

// MARK: - Data Models

class StudioObject: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    let type: StudioObjectType
    @Published var position: SCNVector3
    @Published var rotation: SCNVector3
    @Published var scale: SCNVector3
    
    let node: SCNNode
    
    init(id: UUID = UUID(), name: String, type: StudioObjectType, position: SCNVector3, rotation: SCNVector3, scale: SCNVector3) {
        self.id = id
        self.name = name
        self.type = type
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.node = SCNNode()
        
        updateNodeTransform()
    }
    
    private func updateNodeTransform() {
        node.position = position
        node.eulerAngles = rotation
        node.scale = scale
    }
}

enum StudioObjectType {
    case ledWall, camera, setPiece, light
}

class VirtualCamera: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var position: SCNVector3
    @Published var target: SCNVector3
    @Published var isActive: Bool = false
    
    let node: SCNNode
    let camera: SCNCamera
    
    init(name: String, position: SCNVector3, target: SCNVector3) {
        self.name = name
        self.position = position
        self.target = target
        
        self.camera = SCNCamera()
        self.node = SCNNode()
        
        camera.fieldOfView = 60
        camera.zNear = 0.1
        camera.zFar = 1000
        
        node.camera = camera
        node.position = position
        node.look(at: target)
    }
}

// MARK: - Asset Definitions

struct LEDWallAsset: StudioAsset {
    let id = UUID()
    let name: String
    let width: Float
    let height: Float
    let pixelPitch: Float
    let resolution: CGSize
    
    var icon: String { "tv" }
    var color: Color { .blue }
    
    static let predefinedWalls = [
        LEDWallAsset(name: "Standard 4x3", width: 4, height: 3, pixelPitch: 2.6, resolution: CGSize(width: 1920, height: 1080)),
        LEDWallAsset(name: "Wide 6x3", width: 6, height: 3, pixelPitch: 2.6, resolution: CGSize(width: 2880, height: 1080)),
        LEDWallAsset(name: "Tall 4x5", width: 4, height: 5, pixelPitch: 2.6, resolution: CGSize(width: 1920, height: 1600)),
        LEDWallAsset(name: "Massive 8x4", width: 8, height: 4, pixelPitch: 3.9, resolution: CGSize(width: 3840, height: 1920))
    ]
}

struct CameraAsset: StudioAsset {
    let id = UUID()
    let name: String
    let type: String
    let focalLength: Float
    
    var icon: String { "video" }
    var color: Color { .orange }
    
    static let predefinedCameras = [
        CameraAsset(name: "Camera 1", type: "Broadcast", focalLength: 24),
        CameraAsset(name: "Camera 2", type: "Cinema", focalLength: 35),
        CameraAsset(name: "Camera 3", type: "Wide", focalLength: 16),
        CameraAsset(name: "Camera 4", type: "Telephoto", focalLength: 85)
    ]
}

struct SetPieceAsset: StudioAsset {
    let id = UUID()
    let name: String
    let category: String
    let size: SCNVector3
    
    var icon: String { "cube.box" }
    var color: Color {
        switch category {
        case "Furniture": return .brown
        case "Props": return .green
        case "Staging": return .purple
        default: return .gray
        }
    }
    
    static let predefinedPieces = [
        SetPieceAsset(name: "Desk", category: "Furniture", size: SCNVector3(2, 0.8, 1)),
        SetPieceAsset(name: "Chair", category: "Furniture", size: SCNVector3(0.6, 1.2, 0.6)),
        SetPieceAsset(name: "Plant", category: "Props", size: SCNVector3(0.5, 1.5, 0.5)),
        SetPieceAsset(name: "Podium", category: "Staging", size: SCNVector3(1, 1.2, 0.8)),
        SetPieceAsset(name: "Backdrop", category: "Staging", size: SCNVector3(4, 3, 0.1)),
        SetPieceAsset(name: "Truss", category: "Staging", size: SCNVector3(6, 0.3, 0.3))
    ]
}
