import Foundation
import SwiftUI

@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()
    
    let recordingService = RecordingService()
    
    private init() { }
}