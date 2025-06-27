import Foundation

public struct Effect: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var intensity: Float

    public init(id: UUID = UUID(), name: String, isEnabled: Bool, intensity: Float) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.intensity = intensity
    }
}
