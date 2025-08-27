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

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        zIndex: Int = 0,
        centerNorm: CGPoint = CGPoint(x: 0.8, y: 0.8),
        sizeNorm: CGSize = CGSize(width: 0.25, height: 0.25),
        rotationDegrees: Float = 0,
        opacity: Float = 1.0,
        source: LayerSource
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
    }
}