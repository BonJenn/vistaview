//
//  OverlayManager.swift
//  Vantaview
//

import Foundation
import SwiftUI

@MainActor
final class OverlayManager: ObservableObject {
    @Published var overlays: [OverlayItem] = []
    
    func addTextOverlay() {
        let overlay = TextOverlay(id: UUID(), text: "Sample Text")
        overlays.append(.text(overlay))
        objectWillChange.send()
    }
    
    func addCountdownOverlay(seconds: Int) {
        let overlay = CountdownOverlay(id: UUID(), duration: seconds)
        overlays.append(.countdown(overlay))
        objectWillChange.send()
    }
    
    func remove(_ id: UUID) {
        overlays.removeAll { overlay in
            switch overlay {
            case .text(let text):
                return text.id == id
            case .countdown(let countdown):
                return countdown.id == id
            }
        }
        objectWillChange.send()
    }
}

// MARK: - Supporting Types

enum OverlayItem: Identifiable {
    case text(TextOverlay)
    case countdown(CountdownOverlay)
    
    var id: UUID {
        switch self {
        case .text(let overlay):
            return overlay.id
        case .countdown(let overlay):
            return overlay.id
        }
    }
}

struct TextOverlay: Identifiable {
    let id: UUID
    var text: String
}

struct CountdownOverlay: Identifiable {
    let id: UUID
    var duration: Int
}