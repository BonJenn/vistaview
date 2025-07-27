import Foundation
import SceneKit
import SwiftUI
import VideoToolbox

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

// MARK: - Tool Enum
enum StudioTool: CaseIterable {
    case select, ledWall, camera, setPiece, light
    
    var name: String {
        switch self {
        case .select:  return "Select"
        case .ledWall: return "LED Wall"
        case .camera:  return "Camera"
        case .setPiece:return "Set Piece"
        case .light:   return "Light"
        }
    }
    
    var icon: String {
        switch self {
        case .select:  return "cursorarrow"
        case .ledWall: return "tv"
        case .camera:  return "video"
        case .setPiece:return "cube.box"
        case .light:   return "lightbulb"
        }
    }
}

// MARK: - Studio Categories

enum StudioCategory: String, CaseIterable {
    case newsStudio = "News Studio"
    case talkShow = "Talk Show Studio"
    case podcast = "Podcast Studio"
    case concert = "Concert Studio"
    
    var icon: String {
        switch self {
        case .newsStudio: return "📺"
        case .talkShow: return "🎙️"
        case .podcast: return "🎧"
        case .concert: return "🎵"
        }
    }
    
    var subcategories: [SetPieceSubcategory] {
        switch self {
        case .newsStudio, .talkShow, .podcast, .concert:
            return [.ledWalls, .furniture, .lighting, .props]
        }
    }
}

enum SetPieceSubcategory: String, CaseIterable {
    case ledWalls = "LED Walls"
    case furniture = "Furniture"
    case lighting = "Lighting"
    case props = "Props"
    
    var icon: String {
        switch self {
        case .ledWalls: return "display"
        case .furniture: return "chair"
        case .lighting: return "lightbulb"
        case .props: return "cube"
        }
    }
}

// MARK: - LED Wall Content Types
enum LEDWallContentType: String, CaseIterable {
    case none = "None"
    case cameraFeed = "Camera Feed"
    case staticImage = "Static Image"
    case videoFile = "Video File"
    case colorPattern = "Color Pattern"
    case testPattern = "Test Pattern"
    
    var displayName: String {
        return self.rawValue
    }
    
    var icon: String {
        switch self {
        case .none: return "tv.slash"
        case .cameraFeed: return "camera.tv"
        case .staticImage: return "photo.tv"
        case .videoFile: return "video.tv"
        case .colorPattern: return "paintpalette.tv"
        case .testPattern: return "checkerboard.rectangle"
        }
    }
}

// MARK: - Asset Protocol & Types
protocol StudioAsset {
    var id: UUID { get }
    var name: String { get }
    var icon: String { get }
    var color: PlatformColor { get }
}

struct LEDWallAsset: StudioAsset {
    let id = UUID()
    let name: String
    let width: CGFloat
    let height: CGFloat
    let resolution: CGSize
    let pixelPitch: Float
    let brightness: Float
    let description: String
    
    var icon: String { "tv" }
    var color: PlatformColor { .systemBlue }
    
    init(name: String, 
         width: CGFloat, 
         height: CGFloat,
         resolution: CGSize = CGSize(width: 1920, height: 1080),
         pixelPitch: Float = 2.5,
         brightness: Float = 5000,
         description: String = "") {
        self.name = name
        self.width = width
        self.height = height
        self.resolution = resolution
        self.pixelPitch = pixelPitch
        self.brightness = brightness
        self.description = description
    }
    
    static let predefinedWalls: [LEDWallAsset] = [
        LEDWallAsset(name: "Broadcast Main (16:9)", width: 16, height: 9, 
                    resolution: CGSize(width: 3840, height: 2160), pixelPitch: 1.5, brightness: 6000),
        LEDWallAsset(name: "Side Panel", width: 6, height: 8,
                    resolution: CGSize(width: 1920, height: 2560), pixelPitch: 2.0, brightness: 5500),
        LEDWallAsset(name: "Lower Thirds Strip", width: 12, height: 2,
                    resolution: CGSize(width: 3840, height: 640), pixelPitch: 1.2, brightness: 7000),
        LEDWallAsset(name: "Curved Backdrop", width: 20, height: 8,
                    resolution: CGSize(width: 5120, height: 2048), pixelPitch: 2.5, brightness: 4500),
        LEDWallAsset(name: "Portable Panel", width: 2, height: 2,
                    resolution: CGSize(width: 1024, height: 1024), pixelPitch: 2.0, brightness: 4000)
    ]
}

struct CameraAsset: StudioAsset {
    let id = UUID()
    let name: String
    let type: String
    let focalLength: CGFloat
    let fieldOfView: Float
    let description: String
    
    var icon: String { "video" }
    var color: PlatformColor { .systemOrange }
    
    init(name: String,
         type: String = "Broadcast",
         focalLength: CGFloat = 50,
         fieldOfView: Float = 60,
         description: String = "") {
        self.name = name
        self.type = type
        self.focalLength = focalLength
        self.fieldOfView = fieldOfView
        self.description = description
    }
    
    static let predefinedCameras: [CameraAsset] = [
        CameraAsset(name: "Main Camera", focalLength: 50, fieldOfView: 60),
        CameraAsset(name: "Wide Shot", focalLength: 24, fieldOfView: 84),
        CameraAsset(name: "Close Up", focalLength: 85, fieldOfView: 28),
        CameraAsset(name: "Medium Shot", focalLength: 35, fieldOfView: 63),
        CameraAsset(name: "Overhead", focalLength: 28, fieldOfView: 75)
    ]
}

struct LightAsset: StudioAsset {
    let id = UUID()
    let name: String
    let lightType: String
    let intensity: Float
    let beamAngle: Float?
    let description: String
    
    var icon: String { "lightbulb" }
    var color: PlatformColor { .systemYellow }
    
    init(name: String,
         lightType: String = "omni",
         intensity: Float = 1000,
         beamAngle: Float? = nil,
         description: String = "") {
        self.name = name
        self.lightType = lightType
        self.intensity = intensity
        self.beamAngle = beamAngle
        self.description = description
    }
    
    static let predefinedLights: [LightAsset] = [
        LightAsset(name: "Key Light (Warm)", lightType: "directional", intensity: 1500),
        LightAsset(name: "Key Light (Cool)", lightType: "directional", intensity: 1500),
        LightAsset(name: "Soft Fill Light", lightType: "omni", intensity: 800),
        LightAsset(name: "Background Wash", lightType: "directional", intensity: 1200),
        LightAsset(name: "Color Accent", lightType: "spot", intensity: 2000, beamAngle: 30),
        LightAsset(name: "Moving Head Light", lightType: "spot", intensity: 3000, beamAngle: 25),
        LightAsset(name: "Stage Wash", lightType: "directional", intensity: 2500),
        LightAsset(name: "Ambient Room Light", lightType: "omni", intensity: 400)
    ]
}

struct SetPieceAsset: StudioAsset, Identifiable {
    let id = UUID()
    let name: String
    let category: StudioCategory
    let subcategory: SetPieceSubcategory
    let size: SCNVector3
    let description: String
    let thumbnailImage: String
    
    var icon: String { thumbnailImage }
    var color: PlatformColor {
        switch subcategory {
        case .furniture: return .systemBrown
        case .props:     return .systemGreen
        case .lighting:  return .systemYellow
        case .ledWalls:  return .systemBlue
        }
    }
    
    init(name: String, 
         category: StudioCategory, 
         subcategory: SetPieceSubcategory,
         size: SCNVector3 = SCNVector3(1, 1, 1),
         description: String = "",
         thumbnailImage: String = "cube") {
        self.name = name
        self.category = category
        self.subcategory = subcategory
        self.size = size
        self.description = description
        self.thumbnailImage = thumbnailImage
    }
    
    static let predefinedPieces: [SetPieceAsset] = [
        // News Studio - LED Walls
        SetPieceAsset(name: "Wide Backdrop (16:9)", category: .newsStudio, subcategory: .ledWalls, 
                     size: SCNVector3(16, 9, 0.2), thumbnailImage: "tv"),
        SetPieceAsset(name: "Corner Display", category: .newsStudio, subcategory: .ledWalls,
                     size: SCNVector3(4, 3, 0.2), thumbnailImage: "display"),
        SetPieceAsset(name: "Lower Thirds Wall", category: .newsStudio, subcategory: .ledWalls,
                     size: SCNVector3(12, 2, 0.2), thumbnailImage: "rectangle"),
        
        // News Studio - Furniture
        SetPieceAsset(name: "News Desk", category: .newsStudio, subcategory: .furniture,
                     size: SCNVector3(3, 1.2, 1.5), thumbnailImage: "rectangle.fill"),
        SetPieceAsset(name: "Anchor Chair", category: .newsStudio, subcategory: .furniture,
                     size: SCNVector3(0.8, 1.2, 0.8), thumbnailImage: "chair.fill"),
        SetPieceAsset(name: "Guest Chair", category: .newsStudio, subcategory: .furniture,
                     size: SCNVector3(0.7, 1.1, 0.7), thumbnailImage: "chair"),
        SetPieceAsset(name: "Standing Podium", category: .newsStudio, subcategory: .furniture,
                     size: SCNVector3(1.2, 1.3, 0.6), thumbnailImage: "rectangle.portrait"),
        
        // News Studio - Props
        SetPieceAsset(name: "Teleprompter", category: .newsStudio, subcategory: .props,
                     size: SCNVector3(0.5, 1.5, 0.3), thumbnailImage: "tv.circle"),
        SetPieceAsset(name: "Monitor Stand", category: .newsStudio, subcategory: .props,
                     size: SCNVector3(0.6, 1.4, 0.4), thumbnailImage: "display"),
        SetPieceAsset(name: "Coffee Table", category: .newsStudio, subcategory: .props,
                     size: SCNVector3(1.2, 0.5, 0.8), thumbnailImage: "rectangle.roundedtop"),
        
        // Talk Show - LED Walls
        SetPieceAsset(name: "Curved Backdrop", category: .talkShow, subcategory: .ledWalls,
                     size: SCNVector3(20, 8, 0.3), thumbnailImage: "tv"),
        SetPieceAsset(name: "Side Accent Wall", category: .talkShow, subcategory: .ledWalls,
                     size: SCNVector3(6, 8, 0.2), thumbnailImage: "display"),
        SetPieceAsset(name: "Audience Backdrop", category: .talkShow, subcategory: .ledWalls,
                     size: SCNVector3(15, 6, 0.2), thumbnailImage: "rectangle"),
        
        // Talk Show - Furniture  
        SetPieceAsset(name: "Host Desk", category: .talkShow, subcategory: .furniture,
                     size: SCNVector3(2.5, 1.1, 1.2), thumbnailImage: "rectangle.fill"),
        SetPieceAsset(name: "Guest Sofa", category: .talkShow, subcategory: .furniture,
                     size: SCNVector3(2.5, 0.9, 1.0), thumbnailImage: "sofa"),
        SetPieceAsset(name: "Bar Stools", category: .talkShow, subcategory: .furniture,
                     size: SCNVector3(0.5, 1.1, 0.5), thumbnailImage: "chair.fill"),
        
        // Podcast Studio - LED Walls
        SetPieceAsset(name: "Intimate Backdrop", category: .podcast, subcategory: .ledWalls,
                     size: SCNVector3(8, 6, 0.2), thumbnailImage: "tv"),
        SetPieceAsset(name: "Brand Wall", category: .podcast, subcategory: .ledWalls,
                     size: SCNVector3(4, 4, 0.2), thumbnailImage: "square"),
        
        // Podcast Studio - Furniture
        SetPieceAsset(name: "Round Table", category: .podcast, subcategory: .furniture,
                     size: SCNVector3(1.5, 0.8, 1.5), thumbnailImage: "circle.fill"),
        SetPieceAsset(name: "Podcast Chair", category: .podcast, subcategory: .furniture,
                     size: SCNVector3(0.7, 1.0, 0.7), thumbnailImage: "chair"),
        
        // Podcast Studio - Props
        SetPieceAsset(name: "Microphone Arm", category: .podcast, subcategory: .props,
                     size: SCNVector3(0.1, 1.0, 0.8), thumbnailImage: "mic"),
        SetPieceAsset(name: "Bookshelf", category: .podcast, subcategory: .props,
                     size: SCNVector3(2.0, 2.0, 0.4), thumbnailImage: "books.vertical"),
        
        // Concert Studio - LED Walls
        SetPieceAsset(name: "Massive Backdrop", category: .concert, subcategory: .ledWalls,
                     size: SCNVector3(30, 15, 0.5), thumbnailImage: "tv"),
        SetPieceAsset(name: "Side Tower", category: .concert, subcategory: .ledWalls,
                     size: SCNVector3(4, 12, 0.3), thumbnailImage: "rectangle.portrait"),
        SetPieceAsset(name: "Floor LED Strip", category: .concert, subcategory: .ledWalls,
                     size: SCNVector3(20, 0.1, 1), thumbnailImage: "minus.rectangle"),
        
        // Concert Studio - Furniture
        SetPieceAsset(name: "Performance Stage", category: .concert, subcategory: .furniture,
                     size: SCNVector3(8, 0.5, 6), thumbnailImage: "rectangle.fill"),
        SetPieceAsset(name: "DJ Booth", category: .concert, subcategory: .furniture,
                     size: SCNVector3(2, 1.2, 1.5), thumbnailImage: "rectangle.portrait.fill"),
        
        // Concert Studio - Props
        SetPieceAsset(name: "Speaker Stack", category: .concert, subcategory: .props,
                     size: SCNVector3(1, 3, 1), thumbnailImage: "speaker.3"),
        SetPieceAsset(name: "Fog Machine", category: .concert, subcategory: .props,
                     size: SCNVector3(0.8, 0.4, 0.6), thumbnailImage: "cloud")
    ]
    
    static func pieces(for category: StudioCategory, subcategory: SetPieceSubcategory) -> [SetPieceAsset] {
        return predefinedPieces.filter { $0.category == category && $0.subcategory == subcategory }
    }
}

// MARK: - Scene Objects
@MainActor
final class StudioObject: Identifiable, ObservableObject {
    let id: UUID
    @Published var name: String
    @Published var type: StudioTool
    @Published var position: SCNVector3
    @Published var rotation: SCNVector3
    @Published var scale: SCNVector3
    @Published var isVisible: Bool = true
    @Published var isSelected: Bool = false
    @Published var isHighlighted: Bool = false
    
    // LED Wall specific properties
    @Published var ledWallContentType: LEDWallContentType = .none
    @Published var connectedCameraFeedID: UUID?
    
    let node: SCNNode
    private var highlightNode: SCNNode?
    
    // Computed property for convenience
    var isDisplayingCameraFeed: Bool {
        return ledWallContentType == .cameraFeed && connectedCameraFeedID != nil
    }
    
    init(id: UUID = UUID(),
         name: String,
         type: StudioTool,
         position: SCNVector3,
         rotation: SCNVector3 = SCNVector3Zero,
         scale: SCNVector3 = SCNVector3(1,1,1)) {
        self.id = id
        self.name = name
        self.type = type
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.node = SCNNode()
        
        updateNodeTransform()
        // Don't setup highlight here - it will be called after geometry is set
    }
    
    func setupHighlightAfterGeometry() {
        setupHighlightNode()
    }
    
    func updateNodeTransform() {
        node.position = position
        node.eulerAngles = rotation
        node.scale = scale
        node.isHidden = !isVisible
        
        // Update highlight visibility
        updateHighlight()
    }
    
    func updateFromNode() {
        position = node.position
        rotation = node.eulerAngles
        scale = node.scale
        isVisible = !node.isHidden
    }
    
    func setSelected(_ selected: Bool) {
        isSelected = selected
        updateHighlight()
    }
    
    func setHighlighted(_ highlighted: Bool) {
        isHighlighted = highlighted
        updateHighlight()
    }
    
    // MARK: - LED Wall Content Management
    
    /// Connect a camera feed to this LED wall
    func connectCameraFeed(_ feedID: UUID) {
        guard type == .ledWall else {
            print("⚠️ Attempted to connect camera feed to non-LED wall object: \(name)")
            return
        }
        
        connectedCameraFeedID = feedID
        ledWallContentType = .cameraFeed
        print("✅ Connected camera feed \(feedID) to LED wall: \(name)")
    }
    
    /// Disconnect the current camera feed
    func disconnectCameraFeed() {
        guard type == .ledWall else { return }
        
        connectedCameraFeedID = nil
        ledWallContentType = .none
        print("🔌 Disconnected camera feed from LED wall: \(name)")
        
        // Clear the material content
        if let geometry = node.geometry,
           let material = geometry.materials.first {
            material.diffuse.contents = PlatformColor.darkGray
            material.emission.contents = nil
            material.emission.intensity = 0
        }
    }
    
    /// Set static content on the LED wall
    func setLEDWallContent(type: LEDWallContentType, content: Any? = nil) {
        guard self.type == .ledWall else {
            print("⚠️ Attempted to set content on non-LED wall object: \(name)")
            return
        }
        
        ledWallContentType = type
        
        // Clear camera feed connection if switching to other content
        if type != .cameraFeed {
            connectedCameraFeedID = nil
        }
        
        // Apply content to material if provided
        if let content = content,
           let geometry = node.geometry,
           let material = geometry.materials.first {
            
            switch type {
            case .staticImage, .videoFile:
                material.diffuse.contents = content
                material.emission.contents = content
                material.emission.intensity = 0.3
                
            case .colorPattern, .testPattern:
                material.diffuse.contents = content
                material.emission.contents = content
                material.emission.intensity = 0.5
                
            case .none:
                material.diffuse.contents = PlatformColor.darkGray
                material.emission.contents = nil
                material.emission.intensity = 0
                
            case .cameraFeed:
                // Camera feed content is handled separately by the feed manager
                break
            }
        }
        
        print("🎬 Set LED wall content type to \(type.displayName) for: \(name)")
    }
    
    private func setupHighlightNode() {
        // Try to get actual geometry bounds, fallback to default size
        var highlightSize = SCNVector3(1.2, 1.2, 1.2) // Default size
        
        if let geometry = node.geometry {
            let boundingBox = geometry.boundingBox
            let size = SCNVector3(
                boundingBox.max.x - boundingBox.min.x,
                boundingBox.max.y - boundingBox.min.y,
                boundingBox.max.z - boundingBox.min.z
            )
            
            // Use actual object size + padding for highlight
            let padding: Float = 0.5 // Increased padding for more visible outline
            highlightSize = SCNVector3(
                max(1.0, Float(size.x) + padding),
                max(1.0, Float(size.y) + padding),
                max(1.0, Float(size.z) + padding)
            )
        }
        
        // Create a MUCH more prominent selection outline with thick, bright lines
        let highlightGeometry = SCNBox(
            width: CGFloat(highlightSize.x),
            height: CGFloat(highlightSize.y),
            length: CGFloat(highlightSize.z),
            chamferRadius: 0.1 // Add slight chamfer for better visibility
        )
        
        let highlightMaterial = SCNMaterial()
        highlightMaterial.fillMode = .lines // Wireframe outline
        
        // Use MUCH brighter, more saturated colors based on object type
        let highlightColor = colorForObjectType()
        highlightMaterial.diffuse.contents = highlightColor
        highlightMaterial.emission.contents = highlightColor // Make it glow!
        highlightMaterial.emission.intensity = 2.0 // Very bright emission
        highlightMaterial.transparency = 1.0 // Fully opaque
        highlightMaterial.isDoubleSided = true
        
        // Add much stronger glow effect
        highlightMaterial.multiply.contents = highlightColor
        highlightMaterial.multiply.intensity = 1.5
        
        highlightGeometry.materials = [highlightMaterial]
        
        highlightNode = SCNNode(geometry: highlightGeometry)
        highlightNode?.isHidden = true
        
        // Add MUCH more dramatic pulsing animation
        let pulseAnimation = CABasicAnimation(keyPath: "emission.intensity")
        pulseAnimation.fromValue = 1.5
        pulseAnimation.toValue = 3.0 // Much brighter pulse
        pulseAnimation.duration = 0.8
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        highlightNode?.addAnimation(pulseAnimation, forKey: "pulseAnimation")
        
        node.addChildNode(highlightNode!)
        
        print("🔧 Setup ENHANCED highlight node with size: \(highlightSize) and BRIGHT color: \(highlightColor)")
    }
    
    private func colorForObjectType() -> PlatformColor {
        switch type {
        case .ledWall:
            return .systemBlue.withAlphaComponent(1.0) // Bright blue
        case .camera:
            return .systemOrange.withAlphaComponent(1.0) // Bright orange
        case .light:
            return .systemYellow.withAlphaComponent(1.0) // Bright yellow
        case .setPiece:
            return .systemGreen.withAlphaComponent(1.0) // Bright green
        case .select:
            return .systemPurple.withAlphaComponent(1.0) // Bright purple
        }
    }
    
    private func updateHighlight() {
        let shouldShow = isSelected || isHighlighted
        highlightNode?.isHidden = !shouldShow
        
        // Update animation state with MUCH more dramatic effects
        if shouldShow && isSelected {
            // VERY bright pulsing for selected objects
            highlightNode?.removeAnimation(forKey: "pulseAnimation")
            
            let pulseAnimation = CABasicAnimation(keyPath: "emission.intensity")
            pulseAnimation.fromValue = 2.0
            pulseAnimation.toValue = 4.0 // VERY bright
            pulseAnimation.duration = 0.6
            pulseAnimation.autoreverses = true
            pulseAnimation.repeatCount = .infinity
            pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            highlightNode?.addAnimation(pulseAnimation, forKey: "pulseAnimation")
            
            // Add scale pulsing too for extra visibility
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = 1.0
            scaleAnimation.toValue = 1.02
            scaleAnimation.duration = 0.6
            scaleAnimation.autoreverses = true
            scaleAnimation.repeatCount = .infinity
            scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            highlightNode?.addAnimation(scaleAnimation, forKey: "scaleAnimation")
            
        } else if shouldShow && isHighlighted {
            // Bright steady glow for highlighted (hovered) objects
            highlightNode?.removeAnimation(forKey: "pulseAnimation")
            highlightNode?.removeAnimation(forKey: "scaleAnimation")
            
            let glowAnimation = CABasicAnimation(keyPath: "emission.intensity")
            glowAnimation.fromValue = 1.0
            glowAnimation.toValue = 2.5
            glowAnimation.duration = 0.3
            glowAnimation.autoreverses = true
            glowAnimation.repeatCount = .infinity
            glowAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            highlightNode?.addAnimation(glowAnimation, forKey: "glowAnimation")
        } else {
            // Remove all animations when not selected/highlighted
            highlightNode?.removeAllAnimations()
        }
        
        print("👁️ ENHANCED highlight visibility for \(name): \(shouldShow) (selected: \(isSelected), highlighted: \(isHighlighted))")
    }
}

@MainActor
final class VirtualCamera: Identifiable, ObservableObject {
    let id = UUID()
    @Published var name: String
    @Published var position: SCNVector3
    @Published var rotation: SCNVector3
    @Published var isActive: Bool = false
    @Published var focalLength: Float = 50.0
    @Published var isVisible: Bool = true
    
    let node: SCNNode
    private let camera: SCNCamera
    
    init(name: String, position: SCNVector3) {
        self.name = name
        self.position = position
        self.rotation = SCNVector3(0, 0, 0)
        
        self.camera = SCNCamera()
        self.node = SCNNode()
        
        setupCamera()
        updateTransform()
    }
    
    private func setupCamera() {
        camera.fieldOfView = 60
        camera.zNear = 0.1
        camera.zFar = 1000
        camera.focalLength = CGFloat(focalLength)
        
        node.camera = camera
        node.name = name
        
        // Add visual representation (small cube for camera)
        let geometry = SCNBox(width: 0.5, height: 0.3, length: 0.8, chamferRadius: 0.05)
        let material = SCNMaterial()
        material.diffuse.contents = PlatformColor.systemBlue
        geometry.materials = [material]
        
        let visualNode = SCNNode(geometry: geometry)
        node.addChildNode(visualNode)
    }
    
    func updateTransform() {
        node.position = position
        node.eulerAngles = rotation
        node.isHidden = !isVisible
    }
    
    func updateFromNode() {
        position = node.position
        rotation = node.eulerAngles
        isVisible = !node.isHidden
    }
    
    func activate() {
        isActive = true
    }
    
    func deactivate() {
        isActive = false
    }
}