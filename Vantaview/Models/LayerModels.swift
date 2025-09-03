import Foundation
import CoreGraphics

enum LayerSource: Equatable, Identifiable {
    case camera(UUID)
    case media(MediaFile)

    var id: String {
        switch self {
        case .camera(let id): return "camera-\(id.uuidString)"
        case .media(let file): return "media-\(file.id)"
        }
    }
}

struct CompositedLayer: Identifiable, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var zIndex: Int

    // Normalized center and size (0..1 in both axes)
    var centerNorm: CGPoint
    var sizeNorm: CGSize
    var rotationDegrees: Float
    var opacity: Float

    var source: LayerSource

    var audioMuted: Bool = false
    var audioGain: Float = 1.0
    var audioSolo: Bool = false
    var audioPan: Float = 0.0  // -1 (left) ... 0 (center) ... +1 (right)

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        zIndex: Int = 0,
        centerNorm: CGPoint = CGPoint(x: 0.8, y: 0.8),
        sizeNorm: CGSize = CGSize(width: 0.25, height: 0.25),
        rotationDegrees: Float = 0,
        opacity: Float = 1.0,
        source: LayerSource,
        audioMuted: Bool = false,
        audioGain: Float = 1.0,
        audioSolo: Bool = false,
        audioPan: Float = 0.0
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.zIndex = zIndex
        self.centerNorm = centerNorm
        self.sizeNorm = sizeNorm
        self.rotationDegrees = rotationDegrees
        self.opacity = opacity
        self.source = source
        self.audioMuted = audioMuted
        self.audioGain = audioGain
        self.audioSolo = audioSolo
        self.audioPan = audioPan
    }
}