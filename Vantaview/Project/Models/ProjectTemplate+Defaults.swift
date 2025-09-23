import Foundation

extension ProjectTemplate {
    var studioModeDefault: Bool {
        switch self {
        case .gaming:
            return false
        default:
            return true
        }
    }
}