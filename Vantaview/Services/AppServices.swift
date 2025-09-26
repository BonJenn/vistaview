import Foundation
import SwiftUI

@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()
    
    let recordingService = RecordingService()
    private var productionManager: UnifiedProductionManager?
    
    private init() { }
    
    func setProductionManager(_ manager: UnifiedProductionManager) {
        self.productionManager = manager
        recordingService.setProductionManager(manager)
    }
    
    func getProductionManager() -> UnifiedProductionManager? {
        return productionManager
    }
}