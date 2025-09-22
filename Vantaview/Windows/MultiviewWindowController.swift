import AppKit
import SwiftUI

@MainActor
final class MultiviewWindowController: NSWindowController {
    static let shared = MultiviewWindowController()
    
    private var hosting: NSHostingView<AnyView>?
    private weak var viewModelRef: MultiviewViewModel?
    
    func show(with productionManager: UnifiedProductionManager, viewModel: MultiviewViewModel) {
        self.viewModelRef = viewModel
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
            win.delegate = self
            self.hosting = hosting
            self.window = win
        } else {
            // UPDATE existing content to new VM if needed
            if let hosting = self.hosting {
                hosting.rootView = AnyView(
                    MultiviewDrawer(viewModel: viewModel, productionManager: productionManager).padding()
                )
            }
            // Ensure delegate and ref are up to date
            self.window?.delegate = self
        }
        self.showWindow(nil)
        self.window?.makeKeyAndOrderFront(nil)
    }
    
    override func close() {
        super.close()
        hosting = nil
    }
}

extension MultiviewWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // When user closes the window via X, restore inline multiview
        if let vm = viewModelRef {
            vm.isPoppedOut = false
        }
        viewModelRef = nil
    }
}