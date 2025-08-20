import Foundation

enum StreamStatus: String, Codable {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Live"
    case error = "Error"
    
    var displayText: String {
        return self.rawValue
    }
}
