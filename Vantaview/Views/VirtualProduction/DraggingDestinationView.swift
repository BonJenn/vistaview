//
//  DraggingDestinationView.swift
//  Vantaview - Dedicated Drag & Drop Handler
//

import AppKit
import SceneKit

class DraggingDestinationView: NSView {
    weak var coordinator: Enhanced3DViewport.Coordinator?
    weak var scnView: SCNView?
    private var isDragActive = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupDragAndDrop()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDragAndDrop()
    }
    
    private func setupDragAndDrop() {
        registerForDraggedTypes([.string])
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    // MARK: - Hit Testing Override
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only intercept hits during active drag operations
        if isDragActive {
            return super.hitTest(point)
        } else {
            // Pass through to underlying SCNView for normal camera controls
            return nil
        }
    }
    
    // MARK: - Mouse Event Forwarding
    
    override func mouseDown(with event: NSEvent) {
        // Forward to SCNView if not in drag mode
        if !isDragActive {
            scnView?.mouseDown(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Forward to SCNView if not in drag mode
        if !isDragActive {
            scnView?.mouseDragged(with: event)
        } else {
            super.mouseDragged(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        // Forward to SCNView if not in drag mode
        if !isDragActive {
            scnView?.mouseUp(with: event)
        } else {
            super.mouseUp(with: event)
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        // Always forward right-click events
        scnView?.rightMouseDown(with: event)
    }
    
    override func rightMouseUp(with event: NSEvent) {
        // Always forward right-click events
        scnView?.rightMouseUp(with: event)
    }
    
    override func scrollWheel(with event: NSEvent) {
        // Always forward scroll events for zooming
        scnView?.scrollWheel(with: event)
    }
    
    // MARK: - NSDraggingDestination
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragActive = true
        
        // Visual feedback - highlight drop zone
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.1).cgColor
        
        // Send notification for overlay
        NotificationCenter.default.post(name: .dragEntered, object: nil)
        
        return .copy
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Update drop location
        let location = sender.draggingLocation
        NotificationCenter.default.post(name: .dragUpdated, object: location)
        
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragActive = false
        
        // Remove visual feedback
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // Send notification for overlay
        NotificationCenter.default.post(name: .dragExited, object: nil)
    }
    
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragActive = false
        
        // Remove visual feedback
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // Get drag data
        guard let data = sender.draggingPasteboard.data(forType: .string),
              let setPieceID = String(data: data, encoding: .utf8),
              let scnView = scnView,
              let coordinator = coordinator else {
            print("❌ Drop failed: Missing data or views")
            return false
        }
        
        // Find the set piece
        guard let setPiece = SetPieceAsset.predefinedPieces.first(where: { $0.id.uuidString == setPieceID }) else {
            print("❌ Drop failed: SetPiece not found for ID: \(setPieceID)")
            return false
        }
        
        // Get drop location in view coordinates
        let dropLocation = sender.draggingLocation
        print("🎯 Drop location in view: \(dropLocation)")
        
        // Convert to world coordinates
        Task { @MainActor in
            let worldPosition = coordinator.convertScreenToWorld(point: dropLocation, in: scnView)
            
            // Apply grid snapping if enabled
            var finalPosition = worldPosition
            if coordinator.snapToGrid {
                let gridStep = CGFloat(coordinator.gridSize)
                finalPosition = SCNVector3(
                    round(worldPosition.x / gridStep) * gridStep,
                    worldPosition.y,
                    round(worldPosition.z / gridStep) * gridStep
                )
            }
            
            print("🌍 World position: \(finalPosition)")
            
            // Add to scene
            coordinator.parent.studioManager.addSetPieceFromAsset(setPiece, at: finalPosition)
            
            print("✅ Successfully dropped \(setPiece.name) at \(finalPosition)")
        }
        
        return true
    }
    
    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isDragActive = false
        
        // Final cleanup
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}