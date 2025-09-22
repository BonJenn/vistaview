import Foundation
import Metal

final class TextureRefBox: @unchecked Sendable {
    let texture: MTLTexture
    init(_ t: MTLTexture) { self.texture = t }
}

// Tracks shared GPU frames per source per display hostTime tick.
// Goal: avoid duplicate YUV->RGB conversion and FX when the same media is shown in two panes.
actor MediaFrameRegistry {
    static let shared = MediaFrameRegistry()
    
    struct FrameEntry {
        var producing: Bool
        var texture: TextureRefBox?
        var lastAccessHostTime: UInt64
    }
    
    // sourceKey -> (hostTime -> entry)
    private var table: [String: [UInt64: FrameEntry]] = [:]
    private let maxFramesPerSource = 6
    
    func acquireFrameSlot(sourceKey: String, hostTime: UInt64) -> (produce: Bool, shared: MTLTexture?) {
        // Prune old frames for this source
        pruneIfNeeded(for: sourceKey)
        
        var map = table[sourceKey] ?? [:]
        
        if let entry = map[hostTime] {
            if let tex = entry.texture?.texture {
                table[sourceKey] = map // write-back unchanged
                return (false, tex)
            } else {
                // Someone else is already producing this frame; skip work this tick.
                return (false, nil)
            }
        } else {
            // Reserve a production slot for this tick.
            map[hostTime] = FrameEntry(producing: true, texture: nil, lastAccessHostTime: hostTime)
            table[sourceKey] = map
            return (true, nil)
        }
    }
    
    func publish(sourceKey: String, hostTime: UInt64, texture: MTLTexture?) {
        guard var map = table[sourceKey] else { return }
        var entry = map[hostTime] ?? FrameEntry(producing: false, texture: nil, lastAccessHostTime: hostTime)
        entry.producing = false
        if let texture {
            entry.texture = TextureRefBox(texture)
        }
        entry.lastAccessHostTime = hostTime
        map[hostTime] = entry
        table[sourceKey] = map
        pruneIfNeeded(for: sourceKey)
    }
    
    func cancelProduction(sourceKey: String, hostTime: UInt64) {
        guard var map = table[sourceKey] else { return }
        if var entry = map[hostTime] {
            entry.producing = false
            map[hostTime] = entry
            table[sourceKey] = map
        }
    }
    
    private func pruneIfNeeded(for sourceKey: String) {
        guard var map = table[sourceKey] else { return }
        if map.count <= maxFramesPerSource { return }
        let sortedKeys = map.keys.sorted()
        let toRemove = sortedKeys.prefix(max(0, map.count - maxFramesPerSource))
        for k in toRemove {
            map.removeValue(forKey: k)
        }
        table[sourceKey] = map
    }
}