import SceneKit
import CoreGraphics
import simd

// Convenience initializers & helpers to kill every CGFloat ↔︎ Float mismatch

extension SCNVector3 {
    /// From CGFloats
    init(cgX: CGFloat, cgY: CGFloat, cgZ: CGFloat) {
        self.init(Float(cgX), Float(cgY), Float(cgZ))
    }
    
    /// From SIMD float3
    init(_ v: simd_float3) { 
        self.init(v.x, v.y, v.z) 
    }
}

// Handy SIMD ↔︎ SceneKit bridges
extension simd_float3 {
    init(_ v: SCNVector3) { 
        self.init(Float(v.x), Float(v.y), Float(v.z)) 
    }
}