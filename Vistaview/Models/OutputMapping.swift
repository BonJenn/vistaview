import Foundation
import SwiftUI
import Metal
import simd

// MARK: - Output Mapping Data Models

struct OutputMapping: Codable, Equatable {
    var position: CGPoint = .zero
    var size: CGSize = CGSize(width: 1.0, height: 1.0) // Normalized 0-1
    var rotation: Float = 0.0 // In degrees
    var scale: CGFloat = 1.0
    var aspectRatioLocked: Bool = true
    var opacity: Float = 1.0
    
    // Screen resolution context
    var outputResolution: CGSize = CGSize(width: 1920, height: 1080)
    
    init() {}
    
    init(position: CGPoint, size: CGSize, rotation: Float = 0.0, scale: CGFloat = 1.0) {
        self.position = position
        self.size = size
        self.rotation = rotation
        self.scale = scale
    }
    
    // MARK: - Computed Properties
    
    var bounds: CGRect {
        return CGRect(origin: position, size: scaledSize)
    }
    
    var scaledSize: CGSize {
        return CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
    }
    
    var center: CGPoint {
        return CGPoint(
            x: position.x + scaledSize.width / 2,
            y: position.y + scaledSize.height / 2
        )
    }
    
    // MARK: - Transform Matrix
    
    var transformMatrix: simd_float4x4 {
        let translation = simd_float4x4(translation: simd_float3(
            Float(position.x),
            Float(position.y),
            0.0
        ))
        
        let rotation = simd_float4x4(rotationZ: self.rotation * .pi / 180.0)
        
        let scale = simd_float4x4(scale: simd_float3(
            Float(self.scale * size.width),
            Float(self.scale * size.height),
            1.0
        ))
        
        return translation * rotation * scale
    }
    
    // MARK: - Convenience Methods
    
    mutating func fitToScreen() {
        position = .zero
        size = CGSize(width: 1.0, height: 1.0)
        scale = 1.0
        rotation = 0.0
    }
    
    mutating func centerOutput(in containerSize: CGSize) {
        position = CGPoint(
            x: (containerSize.width - scaledSize.width) / 2,
            y: (containerSize.height - scaledSize.height) / 2
        )
    }
    
    mutating func setSize(_ newSize: CGSize, maintainAspectRatio: Bool = false) {
        if maintainAspectRatio && aspectRatioLocked {
            let aspectRatio = size.width / size.height
            if newSize.width / aspectRatio <= newSize.height {
                size = CGSize(width: newSize.width, height: newSize.width / aspectRatio)
            } else {
                size = CGSize(width: newSize.height * aspectRatio, height: newSize.height)
            }
        } else {
            size = newSize
        }
    }
    
    // MARK: - Edge Snapping
    
    mutating func snapToEdges(in containerSize: CGSize, threshold: CGFloat = 10.0) {
        let bounds = self.bounds
        
        // Snap to left edge
        if abs(bounds.minX) < threshold {
            position.x = 0
        }
        
        // Snap to right edge
        if abs(containerSize.width - bounds.maxX) < threshold {
            position.x = containerSize.width - bounds.width
        }
        
        // Snap to top edge
        if abs(bounds.minY) < threshold {
            position.y = 0
        }
        
        // Snap to bottom edge
        if abs(containerSize.height - bounds.maxY) < threshold {
            position.y = containerSize.height - bounds.height
        }
        
        // Snap to center
        let centerX = containerSize.width / 2
        let centerY = containerSize.height / 2
        
        if abs(self.center.x - centerX) < threshold {
            position.x = centerX - bounds.width / 2
        }
        
        if abs(self.center.y - centerY) < threshold {
            position.y = centerY - bounds.height / 2
        }
    }
}

// MARK: - Output Mapping Preset

struct OutputMappingPreset: Codable, Identifiable, Equatable {
    let id = UUID()
    var name: String
    var mapping: OutputMapping
    var description: String?
    var tags: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    init(name: String, mapping: OutputMapping, description: String? = nil) {
        self.name = name
        self.mapping = mapping
        self.description = description
    }
    
    mutating func updateMapping(_ newMapping: OutputMapping) {
        self.mapping = newMapping
        self.updatedAt = Date()
    }
}

// MARK: - Preset Collection

struct OutputMappingPresetCollection: Codable {
    var presets: [OutputMappingPreset] = []
    var version: String = "1.0"
    var exportedAt: Date = Date()
    var appVersion: String = "1.0"
    
    mutating func addPreset(_ preset: OutputMappingPreset) {
        presets.append(preset)
    }
    
    mutating func removePreset(withID id: UUID) {
        presets.removeAll { $0.id == id }
    }
    
    mutating func updatePreset(_ preset: OutputMappingPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        }
    }
}

// MARK: - SIMD Extensions

extension simd_float4x4 {
    init(translation vector: simd_float3) {
        self.init(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(vector.x, vector.y, vector.z, 1)
        )
    }
    
    init(scale vector: simd_float3) {
        self.init(
            simd_float4(vector.x, 0, 0, 0),
            simd_float4(0, vector.y, 0, 0),
            simd_float4(0, 0, vector.z, 0),
            simd_float4(0, 0, 0, 1)
        )
    }
    
    init(rotationZ angle: Float) {
        let cos = cosf(angle)
        let sin = sinf(angle)
        self.init(
            simd_float4(cos, sin, 0, 0),
            simd_float4(-sin, cos, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        )
    }
}