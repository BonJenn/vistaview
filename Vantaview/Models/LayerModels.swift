import Foundation
import CoreGraphics
import SwiftUI

enum LayerSource: Equatable, Identifiable {
    case camera(UUID)
    case media(MediaFile)
    case title(TitleOverlay)

    var id: String {
        switch self {
        case .camera(let id): return "camera-\(id.uuidString)"
        case .media(let file): return "media-\(file.id)"
        case .title(let overlay): return "title-\(overlay.id.uuidString)"
        }
    }
}

struct RGBAColor: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    static let white = RGBAColor(r: 1, g: 1, b: 1, a: 1)
    static let black = RGBAColor(r: 0, g: 0, b: 0, a: 1)
}

struct TitleOverlay: Equatable, Identifiable {
    let id: UUID
    var text: String
    var fontSize: CGFloat
    var color: RGBAColor
    var alignment: TextAlignment
    var autoFit: Bool

    init(
        id: UUID = UUID(),
        text: String = "Title",
        fontSize: CGFloat = 48,
        color: RGBAColor = .white,
        alignment: TextAlignment = .center,
        autoFit: Bool = true
    ) {
        self.id = id
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
        self.autoFit = autoFit
    }
}

struct PiPChromaKeySettings: Equatable {
    var enabled: Bool = false
    var keyR: Float = 0.0
    var keyG: Float = 1.0
    var keyB: Float = 0.0
    var strength: Float = 0.45
    var softness: Float = 0.22
    var balance: Float = 0.55
    var matteShift: Float = 0.0
    var edgeSoftness: Float = 0.28
    var blackClip: Float = 0.04
    var whiteClip: Float = 0.97
    var spillStrength: Float = 0.7
    var spillDesat: Float = 0.35
    var despillBias: Float = 0.2
    var lightWrap: Float = 0.15
    var viewMatte: Bool = false
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

    var chromaKey: PiPChromaKeySettings = PiPChromaKeySettings()

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
        audioPan: Float = 0.0,
        chromaKey: PiPChromaKeySettings = PiPChromaKeySettings()
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
        self.chromaKey = chromaKey
    }
}