import Foundation
import SceneKit
import CoreGraphics
import CoreVideo

// MARK: - Static variables for debugging
private var ledWallUpdateCount = 0

// MARK: - Live-camera texture helpers for LED walls
// These are utility methods that complement the main implementation in StudioSharedTypes.swift
extension StudioObject {

    /// Force an immediate material refresh for LED walls
    /// This is useful when you need to ensure SceneKit picks up material changes
    func refreshLEDWallMaterial() {
        guard type == .ledWall,
              let geometry = node.geometry,
              let material = geometry.materials.first else { return }
        
        // Force SceneKit to refresh by touching the transform
        material.diffuse.contentsTransform = SCNMatrix4Identity
        material.emission.contentsTransform = SCNMatrix4Identity
        
        // Ensure optimal settings for video content
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        
        material.emission.wrapS = .clamp
        material.emission.wrapT = .clamp
        material.emission.magnificationFilter = .linear
        material.emission.minificationFilter = .linear
    }
    
    /// Debug information about the LED wall's current material state
    func debugLEDWallMaterial() -> String {
        guard type == .ledWall,
              let geometry = node.geometry,
              let material = geometry.materials.first else { 
            return "No material found" 
        }
        
        var debug = "LED Wall Material Debug for '\(name)':\n"
        debug += "  - Has diffuse content: \(material.diffuse.contents != nil)\n"
        debug += "  - Diffuse content type: \(Swift.type(of: material.diffuse.contents))\n"
        debug += "  - Has emission content: \(material.emission.contents != nil)\n"
        debug += "  - Emission intensity: \(material.emission.intensity)\n"
        debug += "  - Lighting model: \(material.lightingModel.rawValue)\n"
        debug += "  - Double sided: \(material.isDoubleSided)\n"
        debug += "  - Magnification filter: \(material.diffuse.magnificationFilter.rawValue)\n"
        debug += "  - Wrap S: \(material.diffuse.wrapS.rawValue)\n"
        debug += "  - Wrap T: \(material.diffuse.wrapT.rawValue)\n"
        
        return debug
    }
    
    /// Ensure LED wall material is optimally configured for video content
    func optimizeLEDWallForVideo() {
        guard type == .ledWall,
              let geometry = node.geometry else { return }
        
        // Ensure we have a material
        if geometry.materials.isEmpty {
            let material = SCNMaterial()
            geometry.materials = [material]
        }
        
        guard let material = geometry.materials.first else { return }
        
        // Configure for optimal video display
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true
        
        // Set up texture filtering for smooth video
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        
        // Configure emission properties for LED-like appearance
        material.emission.magnificationFilter = .linear
        material.emission.minificationFilter = .linear
        material.emission.wrapS = .clamp
        material.emission.wrapT = .clamp
        
        // Disable unnecessary properties for better performance
        material.ambient.contents = nil
        material.specular.contents = nil
        material.reflective.contents = nil
        
        print("✅ Optimized LED wall material for video: \(name)")
    }
    
    /// Test the LED wall with a solid color (useful for debugging)
    func testLEDWallWithColor(_ color: CGColor) {
        guard type == .ledWall,
              let geometry = node.geometry,
              let material = geometry.materials.first else { return }
        
        #if os(macOS)
        let platformColor = NSColor(cgColor: color) ?? NSColor.red
        #else
        let platformColor = UIColor(cgColor: color) ?? UIColor.red
        #endif
        
        material.diffuse.contents = platformColor
        material.emission.contents = platformColor
        material.emission.intensity = 0.5
        
        print("🎨 Applied test color to LED wall: \(name)")
    }
    
    /// Update LED wall with camera feed content
    func updateCameraFeedContent(pixelBuffer: CVPixelBuffer) {
        guard type == .ledWall,
              isDisplayingCameraFeed,
              let geometry = node.geometry,
              let material = geometry.materials.first else { 
            print("❌ Cannot update camera feed - LED wall not properly configured")
            return 
        }
        
        print("🎬 Updating LED wall '\(name)' with pixel buffer content")
        
        // Convert pixel buffer to texture content
        #if os(macOS)
        // On macOS, we can use the CVPixelBuffer directly
        material.diffuse.contents = pixelBuffer
        material.emission.contents = pixelBuffer
        material.emission.intensity = 0.6 // Make it brighter like a real LED wall
        
        // Ensure the material is set to unlit so it glows
        material.lightingModel = .constant
        #else
        // On iOS, convert to UIImage if needed
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            material.diffuse.contents = uiImage
            material.emission.contents = uiImage
            material.emission.intensity = 0.6
            material.lightingModel = .constant
        }
        #endif
        
        // Force material update
        refreshLEDWallMaterial()
        
        print("✅ LED wall material updated with camera content")
    }
    
    /// Update LED wall with camera feed CGImage
    func updateCameraFeedContent(cgImage: CGImage) {
        guard type == .ledWall,
              isDisplayingCameraFeed,
              let geometry = node.geometry,
              let material = geometry.materials.first else { 
            print("❌ Cannot update camera feed - LED wall not properly configured")
            return 
        }
        
        #if os(macOS)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        material.diffuse.contents = nsImage
        material.emission.contents = nsImage
        #else
        let uiImage = UIImage(cgImage: cgImage)
        material.diffuse.contents = uiImage
        material.emission.contents = uiImage
        #endif
        
        material.emission.intensity = 0.6 // Bright like LED wall
        material.lightingModel = .constant // Unlit/emissive
        
        // Force refresh
        refreshLEDWallMaterial()
        
        // Debug log occasionally
        ledWallUpdateCount += 1
        if ledWallUpdateCount % 150 == 1 {
            print("📺 LED wall '\(name)' updated with CGImage content (update #\(ledWallUpdateCount))")
            print("   - Image size: \(cgImage.width)x\(cgImage.height)")
            print("   - Material emission intensity: \(material.emission.intensity)")
        }
    }
}