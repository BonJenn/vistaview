import Foundation
import UniformTypeIdentifiers
import SwiftUI

struct CameraFeedDragItem: Codable, Transferable, Identifiable {
    let id = UUID()
    let feedId: UUID
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: CameraFeedDragItem.self, contentType: .data)
    }
}