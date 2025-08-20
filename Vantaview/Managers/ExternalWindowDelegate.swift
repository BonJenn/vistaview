import Foundation
import AppKit

class ExternalWindowDelegate: NSObject, NSWindowDelegate {
    weak var manager: ExternalDisplayManager?
    
    init(manager: ExternalDisplayManager) {
        self.manager = manager
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        print("🖥️ External window is closing")
        manager?.stopFullScreenOutput()
    }
    
    func windowDidEnterFullScreen(_ notification: Notification) {
        print("🖥️ External window entered full-screen")
    }
    
    func windowDidExitFullScreen(_ notification: Notification) {
        print("🖥️ External window exited full-screen")
    }
    
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        print("🖥️ External window resized to: \(window.frame.size)")
    }
}