import Foundation

struct Studio: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let icon: String
    
    init(id: String, name: String, description: String, icon: String) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
    }
}
