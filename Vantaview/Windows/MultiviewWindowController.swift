import AppKit
import SwiftUI

@MainActor
final class MultiviewWindowController: NSWindowController {
    static let shared = MultiviewWindowController()
    
    private var hosting: NSHostingView<AnyView>?
    
    func show(with productionManager: UnifiedProductionManager, viewModel: MultiviewViewModel) {
        if window == nil {
            let content = MultiviewDrawer(viewModel: viewModel, productionManager: productionManager)
                .padding()
            let hosting = NSHostingView(rootView: AnyView(content))
            let win = NSWindow(
                contentRect: NSRect(x: 200, y: 200, width: 900, height: 500),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Multiview"
            win.contentView = hosting
            self.hosting = hosting
            self.window = win
        }
        self.showWindow(nil)
        self.window?.makeKeyAndOrderFront(nil)
    }
    
    override func close() {
        super.close()
        hosting = nil
    }
}