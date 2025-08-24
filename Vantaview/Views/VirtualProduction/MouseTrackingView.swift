//
//  MouseTrackingView.swift
//  Vantaview - Mouse tracking for cursor-based operations
//

import SwiftUI
import AppKit

class MouseTrackingNSView: NSView {
    var onMouseMove: ((NSPoint) -> Void)?
    var onMouseDown: ((NSPoint) -> Void)?
    var onMouseUp: ((NSPoint) -> Void)?
    var onMouseDrag: ((NSPoint) -> Void)?
    
    private var isMouseDown = false
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove existing tracking areas
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        
        // Add comprehensive mouse tracking
        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .mouseEnteredAndExited,
            .activeInKeyWindow,
            .inVisibleRect
        ]
        
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        
        addTrackingArea(trackingArea)
    }
    
    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onMouseMove?(location)
    }
    
    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        let location = convert(event.locationInWindow, from: nil)
        onMouseDown?(location)
    }
    
    override func mouseUp(with event: NSEvent) {
        isMouseDown = false
        let location = convert(event.locationInWindow, from: nil)
        onMouseUp?(location)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onMouseDrag?(location)
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
}

struct MouseTrackingView: NSViewRepresentable {
    @Binding var mousePosition: CGPoint
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?
    var onMouseDrag: ((CGPoint) -> Void)?
    
    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        
        view.onMouseMove = { location in
            DispatchQueue.main.async {
                self.mousePosition = CGPoint(x: location.x, y: location.y)
            }
        }
        
        view.onMouseDown = { location in
            DispatchQueue.main.async {
                let point = CGPoint(x: location.x, y: location.y)
                self.mousePosition = point
                self.onMouseDown?(point)
            }
        }
        
        view.onMouseUp = { location in
            DispatchQueue.main.async {
                let point = CGPoint(x: location.x, y: location.y)
                self.mousePosition = point
                self.onMouseUp?(point)
            }
        }
        
        view.onMouseDrag = { location in
            DispatchQueue.main.async {
                let point = CGPoint(x: location.x, y: location.y)
                self.mousePosition = point
                self.onMouseDrag?(point)
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {
        // Update callbacks if needed
    }
}

// MARK: - SwiftUI Integration Extension

extension View {
    func mouseTracking(
        position: Binding<CGPoint>,
        onMouseDown: ((CGPoint) -> Void)? = nil,
        onMouseUp: ((CGPoint) -> Void)? = nil,
        onMouseDrag: ((CGPoint) -> Void)? = nil
    ) -> some View {
        self.overlay(
            MouseTrackingView(
                mousePosition: position,
                onMouseDown: onMouseDown,
                onMouseUp: onMouseUp,
                onMouseDrag: onMouseDrag
            )
            .allowsHitTesting(false) // Allow underlying views to receive clicks
        )
    }
}