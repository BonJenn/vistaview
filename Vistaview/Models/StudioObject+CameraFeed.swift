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
    @MainActor
    func refreshLEDWallMaterial() {
        guard type == .ledWall,
              let geometry = node.geometry,
              let material = geometry.materials.first else { return }
        
        // Force SceneKit to refresh the material by accessing rendering properties
        geometry.firstMaterial?.isDoubleSided = true
        
        // Ensure optimal settings for video content
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        
        material.emission.wrapS = .clamp
        material.emission.wrapT = .clamp
        material.emission.magnificationFilter = .linear
        material.emission.minificationFilter = .linear
        
        // Force a render update
        material.diffuse.contentsTransform = SCNMatrix4Identity
        material.emission.contentsTransform = SCNMatrix4Identity
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
    @MainActor
    func optimizeLEDWallForVideo() {
        guard type == .ledWall,
              let geometry = node.geometry else { return }
        
        // Ensure we have a material
        if geometry.materials.isEmpty {
            let material = SCNMaterial()
            geometry.materials = [material]
        }
        
        guard let material = geometry.materials.first else { return }
        
        // Configure for optimal video display on macOS
        material.lightingModel = .constant // Unlit for LED-like appearance
        material.isDoubleSided = true // Show on both sides
        
        // Set up texture filtering for smooth video
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        
        // Configure emission properties for LED-like brightness
        material.emission.magnificationFilter = .linear
        material.emission.minificationFilter = .linear
        material.emission.wrapS = .clamp
        material.emission.wrapT = .clamp
        material.emission.intensity = 0.8 // Bright like real LED wall
        
        // Disable unnecessary properties for better performance
        material.ambient.contents = nil
        material.specular.contents = nil
        material.reflective.contents = nil
        material.normal.contents = nil
        
        // Enable transparency handling if needed
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        
        print("✅ Optimized LED wall material for video: \(name)")
    }
    
    /// Test the LED wall with a solid color (useful for debugging)
    @MainActor
    func testLEDWallWithColor(_ color: CGColor) {
        guard type == .ledWall,
              let geometry = node.geometry,
              let material = geometry.materials.first else { return }
        
        let platformColor = NSColor(cgColor: color) ?? NSColor.red
        
        // Apply test color
        material.diffuse.contents = platformColor
        material.emission.contents = platformColor
        material.emission.intensity = 0.5
        material.lightingModel = .constant
        
        print("🎨 Applied test color to LED wall: \(name)")
        
        // Force refresh
        refreshLEDWallMaterial()
    }
    
    /// Update LED wall with camera feed content - IMPROVED VERSION
    @MainActor
    func updateCameraFeedContent(pixelBuffer: CVPixelBuffer) {
        guard type == .ledWall,
              isDisplayingCameraFeed,
              let geometry = node.geometry,
              let material = geometry.materials.first else { 
            print("❌ Cannot update camera feed - LED wall not properly configured")
            return 
        }
        
        // Convert CVPixelBuffer to NSImage for better SceneKit compatibility on macOS
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.cacheIntermediates: false])
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("❌ Failed to convert pixel buffer to CGImage")
            return
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        // Update material with NSImage
        material.diffuse.contents = nsImage
        material.emission.contents = nsImage
        material.emission.intensity = 0.8 // Bright like LED wall
        material.lightingModel = .constant // Unlit/emissive
        
        // Force material update
        refreshLEDWallMaterial()
        
        print("✅ LED wall '\(name)' updated with CVPixelBuffer content via NSImage")
    }
    
    /// Update LED wall with camera feed CGImage - IMPROVED VERSION
    @MainActor
    func updateCameraFeedContent(cgImage: CGImage) {
        guard type == .ledWall,
              isDisplayingCameraFeed,
              let geometry = node.geometry,
              let material = geometry.materials.first else { 
            print("❌ Cannot update camera feed - LED wall not properly configured")
            return 
        }
        
        // Convert CGImage to NSImage for SceneKit on macOS
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        // Update material properties
        material.diffuse.contents = nsImage
        material.emission.contents = nsImage
        material.emission.intensity = 0.8 // Bright like LED wall
        material.lightingModel = .constant // Unlit/emissive for glow effect
        
        // Force refresh to ensure SceneKit picks up the change
        refreshLEDWallMaterial()
        
        // Debug log occasionally
        ledWallUpdateCount += 1
        if ledWallUpdateCount % 150 == 1 {
            print("📺 LED wall '\(name)' updated with CGImage content (update #\(ledWallUpdateCount))")
            print("   - Image size: \(cgImage.width)x\(cgImage.height)")
            print("   - NSImage size: \(nsImage.size)")
            print("   - Material emission intensity: \(material.emission.intensity)")
            print("   - Lighting model: \(material.lightingModel.rawValue)")
        }
    }
    
    /// Update LED wall with NSImage directly (most compatible for SceneKit on macOS)
    @MainActor
    func updateCameraFeedContent(nsImage: NSImage) {
        guard type == .ledWall,
              isDisplayingCameraFeed,
              let geometry = node.geometry,
              let material = geometry.materials.first else { 
            print("❌ Cannot update camera feed - LED wall not properly configured")
            return 
        }
        
        // Direct NSImage assignment - most reliable on macOS
        material.diffuse.contents = nsImage
        material.emission.contents = nsImage
        material.emission.intensity = 0.8 // Bright like LED wall
        material.lightingModel = .constant // Unlit/emissive
        
        // Ensure material is set up for video
        material.isDoubleSided = true
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        
        // Force refresh
        refreshLEDWallMaterial()
        
        print("📺 LED wall '\(name)' updated with NSImage content: \(nsImage.size)")
    }
}