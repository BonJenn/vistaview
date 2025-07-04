import Foundation

struct PresetEffect: Codable, Hashable {
    var type: String
    var amount: Float
}

struct Preset: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var effects: [PresetEffect]
    var blurAmount: Float
    var isBlurEnabled: Bool
}
