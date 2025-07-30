import Foundation
import SceneKit
import CoreGraphics
import CoreVideo
import QuartzCore

// MARK: - Static variables for debugging
private var ledWallUpdateCount = 0

// MARK: - Live-camera texture helpers for LED walls
// These are utility methods that complement the main implementation in StudioSharedTypes.swift
extension StudioObject {

    /// Force an immediate material refresh for LED walls
    /// This is useful when you need to ensure SceneKit picks up material changes
    @MainActor
    func refreshLEDWallMaterial() {
        guard type == .ledWall else { return }
        
        // FIXED: Always refresh material for proper video updates
        guard let screenNode = findScreenNode() else {
            return
        }
        
        guard let geometry = screenNode.geometry,
              let material = geometry.materials.first else {
            return
        }
        
        // Update essential properties
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        
        // PERFORMANCE: Less frequent debug logging only
        if ledWallUpdateCount % 100 == 1 {
            print("✅ Force refreshed LED wall material for: \(name)")
        }
    }
    
    /// Find the screen node within the LED wall structure
    private func findScreenNode() -> SCNNode? {
        // PERFORMANCE: Cache screen node lookup if possible
        if let cachedScreenNode = objc_getAssociatedObject(self, &ScreenNodeCacheKey) as? SCNNode,
           cachedScreenNode.parent != nil {
            return cachedScreenNode
        }
        
        // LED walls have a group structure: main node -> group node -> screen node
        var screenNode: SCNNode?
        
        // First, look for any child node named "screen"
        if let foundNode = node.childNodes.first(where: { findScreenInNode($0) != nil }) {
            screenNode = findScreenInNode(foundNode)
        }
        
        // Fallback: look for the first node with geometry (the actual screen surface)
        if screenNode == nil {
            screenNode = findFirstGeometryNode(in: node)
        }
        
        // PERFORMANCE: Cache the screen node for future lookups
        if let screenNode = screenNode {
            objc_setAssociatedObject(self, &ScreenNodeCacheKey, screenNode, .OBJC_ASSOCIATION_RETAIN)
        }
        
        return screenNode
    }
    
    private func findScreenInNode(_ searchNode: SCNNode) -> SCNNode? {
        // Direct screen node
        if searchNode.name == "screen" {
            return searchNode
        }
        
        // Look in children
        for child in searchNode.childNodes {
            if child.name == "screen" {
                return child
            }
            // Recursively search deeper
            if let found = findScreenInNode(child) {
                return found
            }
        }
        
        return nil
    }
    
    private func findFirstGeometryNode(in searchNode: SCNNode) -> SCNNode? {
        // If this node has plane geometry (LED wall screen), use it
        if let geometry = searchNode.geometry as? SCNPlane {
            return searchNode
        }
        
        // Search children for plane geometry
        for child in searchNode.childNodes {
            if let geometry = child.geometry as? SCNPlane {
                return child
            }
            // Recursively search deeper
            if let found = findFirstGeometryNode(in: child) {
                return found
            }
        }
        
        return nil
    }
    
    /// Debug information about the LED wall's current material state
    func debugLEDWallMaterial() -> String {
        guard type == .ledWall else { return "Not an LED wall" }
        
        guard let screenNode = findScreenNode() else {
            return "❌ LED Wall '\(name)': No screen node found"
        }
        
        guard let geometry = screenNode.geometry,
              let material = geometry.materials.first else {
            return "❌ LED Wall '\(name)': No geometry or material found"
        }
        
        var debug = "🔍 LED Wall Material Debug for '\(name)':\n"
        debug += "  - Screen node found: ✅ '\(screenNode.name ?? "unnamed")'\n"
        debug += "  - Has diffuse content: \(material.diffuse.contents != nil)\n"
        debug += "  - Diffuse content type: \(Swift.type(of: material.diffuse.contents))\n"
        debug += "  - Has emission content: \(material.emission.contents != nil)\n"
        debug += "  - Emission intensity: \(material.emission.intensity)\n"
        debug += "  - Lighting model: \(material.lightingModel.rawValue)\n"
        debug += "  - Double sided: \(material.isDoubleSided)\n"
        
        return debug
    }
    
    /// Ensure LED wall material is optimally configured for video content
    @MainActor
    func optimizeLEDWallForVideo() {
        guard type == .ledWall else { return }
        
        guard let screenNode = findScreenNode() else {
            print("❌ Cannot optimize - no screen node found for: \(name)")
            return
        }
        
        // Ensure we have geometry
        if screenNode.geometry == nil {
            let plane = SCNPlane(width: 4, height: 3) // Default size
            screenNode.geometry = plane
            print("📐 Created default plane geometry for: \(name)")
        }
        
        guard let geometry = screenNode.geometry else { return }
        
        // Ensure we have a material
        if geometry.materials.isEmpty {
            let material = SCNMaterial()
            geometry.materials = [material]
            print("🎨 Created new material for: \(name)")
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
        material.emission.intensity = 0.8 // FIXED: Back to higher intensity for better visibility
        
        // Disable unnecessary properties for better performance
        material.ambient.contents = nil
        material.specular.contents = nil
        material.reflective.contents = nil
        material.normal.contents = nil
        material.multiply.contents = nil
        
        // Enable transparency handling if needed
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        
        // Set initial content to black
        material.diffuse.contents = NSColor.black
        material.emission.contents = NSColor.black
        
        print("✅ Optimized LED wall material for video: \(name)")
    }
    
    /// Test the LED wall with a solid color (useful for debugging)
    @MainActor
    func testLEDWallWithColor(_ color: CGColor) {
        guard type == .ledWall else { return }
        
        guard let screenNode = findScreenNode(),
              let geometry = screenNode.geometry,
              let material = geometry.materials.first else {
            print("❌ Cannot test color - screen node/material not found for: \(name)")
            return
        }
        
        let platformColor = NSColor(cgColor: color) ?? NSColor.red
        
        // Apply test color
        material.diffuse.contents = platformColor
        material.emission.contents = platformColor
        material.emission.intensity = 0.8 // FIXED: Back to higher intensity for visibility
        material.lightingModel = .constant
        
        print("🎨 Applied test color to LED wall: \(name)")
        
        // Force refresh
        refreshLEDWallMaterial()
    }
    
    /// Update LED wall with camera feed content - FIXED VERSION
    @MainActor
    func updateCameraFeedContent(pixelBuffer: CVPixelBuffer) {
        guard type == .ledWall,
              isDisplayingCameraFeed else {
            return
        }
        
        guard let screenNode = findScreenNode(),
              let geometry = screenNode.geometry,
              let material = geometry.materials.first else {
            return
        }
        
        // Convert CVPixelBuffer to NSImage efficiently
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        // Update material with NSImage
        material.diffuse.contents = nsImage
        material.emission.contents = nsImage
        material.emission.intensity = 0.8 // FIXED: Back to higher intensity for visibility
        material.lightingModel = .constant // Unlit/emissive
        
        // FIXED: Always force SceneKit to notice the change for smooth updates
        screenNode.geometry = screenNode.geometry
        
        ledWallUpdateCount += 1
        
        // Debug logging occasionally
        if ledWallUpdateCount % 300 == 1 {
            print("✅ LED wall '\(name)' updated with CVPixelBuffer content (update #\(ledWallUpdateCount))")
        }
    }
    
    /// Update LED wall with camera feed CGImage - FIXED VERSION
    @MainActor
    func updateCameraFeedContent(cgImage: CGImage) {
        guard type == .ledWall,
              isDisplayingCameraFeed else {
            return
        }
        
        guard let screenNode = findScreenNode(),
              let geometry = screenNode.geometry,
              let material = geometry.materials.first else {
            return
        }
        
        // Convert CGImage to NSImage for SceneKit on macOS
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        // Update material properties
        material.diffuse.contents = nsImage
        material.emission.contents = nsImage
        material.emission.intensity = 0.8 // FIXED: Back to higher intensity for visibility
        material.lightingModel = .constant // Unlit/emissive for glow effect
        
        // FIXED: Always force SceneKit to notice the change for smooth updates
        screenNode.geometry = screenNode.geometry
        
        ledWallUpdateCount += 1
        if ledWallUpdateCount % 300 == 1 {
            print("📺 LED wall '\(name)' updated with CGImage content (update #\(ledWallUpdateCount))")
        }
    }
    
    /// Update LED wall with NSImage directly (most compatible for SceneKit on macOS)
    @MainActor
    func updateCameraFeedContent(nsImage: NSImage) {
        guard type == .ledWall,
              isDisplayingCameraFeed else {
            return
        }
        
        guard let screenNode = findScreenNode(),
              let geometry = screenNode.geometry,
              let material = geometry.materials.first else {
            return
        }
        
        // Direct NSImage assignment - most reliable on macOS
        material.diffuse.contents = nsImage
        material.emission.contents = nsImage
        material.emission.intensity = 0.8 // FIXED: Back to higher intensity for visibility
        material.lightingModel = .constant // Unlit/emissive
        
        // Ensure material is set up for video
        material.isDoubleSided = true
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        
        // FIXED: Always force SceneKit to notice the change for smooth updates
        screenNode.geometry = screenNode.geometry
        
        // Less frequent debug logging
        if ledWallUpdateCount % 100 == 1 {
            print("📺 LED wall '\(name)' updated with NSImage content: \(nsImage.size)")
        }
    }
}

// PERFORMANCE: Associated object key for caching screen nodes
private var ScreenNodeCacheKey: UInt8 = 0