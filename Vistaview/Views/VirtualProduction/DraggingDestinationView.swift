//
//  DraggingDestinationView.swift
//  Vistaview - Dedicated Drag & Drop Handler
//

import AppKit
import SceneKit

class DraggingDestinationView: NSView {
    weak var coordinator: Enhanced3DViewport.Coordinator?
    weak var scnView: SCNView?
    
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
    
    // MARK: - NSDraggingDestination
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
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
        // Remove visual feedback
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // Send notification for overlay
        NotificationCenter.default.post(name: .dragExited, object: nil)
    }
    
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
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
        // Final cleanup
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}