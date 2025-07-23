//
//  DropFeedbackOverlay.swift
//  Vistaview - Visual Drop Feedback
//

import SwiftUI
import SceneKit

struct DropFeedbackOverlay: View {
    @State private var dropLocation: CGPoint?
    @State private var isDraggingOver = false
    
    var body: some View {
        ZStack {
            // Semi-transparent overlay when dragging
            if isDraggingOver {
                Rectangle()
                    .fill(Color.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                            .animation(.easeInOut(duration: 0.5).repeatForever(), value: isDraggingOver)
                    )
            }
            
            // Drop target indicator
            if let location = dropLocation {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 20, height: 20)
                    .position(location)
                    .animation(.easeInOut(duration: 0.2), value: dropLocation)
            }
        }
        .allowsHitTesting(false) // Don't interfere with interactions
        .onReceive(NotificationCenter.default.publisher(for: .dragEntered)) { _ in
            isDraggingOver = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .dragExited)) { _ in
            isDraggingOver = false
            dropLocation = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .dragUpdated)) { notification in
            if let point = notification.object as? CGPoint {
                dropLocation = point
            }
        }
    }
}

// MARK: - Drag Feedback Notifications

extension Notification.Name {
    static let dragEntered = Notification.Name("dragEntered")
    static let dragExited = Notification.Name("dragExited")
    static let dragUpdated = Notification.Name("dragUpdated")
}