import SwiftUI
import AppKit

struct LocalKeyEventMonitor: NSViewRepresentable {
    final class View: NSView {
        var onKeyDown: (NSEvent) -> Void = { _ in }
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            onKeyDown(event)
        }
        override func viewDidMoveToWindow() {
            window?.makeFirstResponder(self)
        }
    }
    
    let onKeyDown: (NSEvent) -> Void
    
    func makeNSView(context: Context) -> View {
        let v = View()
        v.onKeyDown = onKeyDown
        return v
    }
    func updateNSView(_ nsView: View, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}