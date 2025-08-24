//
//  InteractionDebugOverlay.swift
//  Vantaview - Debug Camera & Drag Interactions
//

import SwiftUI

struct InteractionDebugOverlay: View {
    @State private var isDragging = false
    @State private var isTransforming = false
    @State private var dragLocation: CGPoint?
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Interaction status
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isDragging ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text("Drag & Drop")
                            .font(.caption2)
                            .foregroundColor(isDragging ? .green : .gray)
                    }
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isTransforming ? .orange : .gray)
                            .frame(width: 8, height: 8)
                        Text("Transforming")
                            .font(.caption2)
                            .foregroundColor(isTransforming ? .orange : .gray)
                    }
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(!isDragging && !isTransforming ? .blue : .gray)
                            .frame(width: 8, height: 8)
                        Text("Camera Control")
                            .font(.caption2)
                            .foregroundColor(!isDragging && !isTransforming ? .blue : .gray)
                    }
                    
                    // Mouse position during drag
                    if let location = dragLocation {
                        Text("Drop: (\(Int(location.x)), \(Int(location.y)))")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding(12)
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: .dragEntered)) { _ in
            isDragging = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .dragExited)) { _ in
            isDragging = false
            dragLocation = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .dragUpdated)) { notification in
            if let point = notification.object as? CGPoint {
                dragLocation = point
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .transformStarted)) { _ in
            isTransforming = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .transformEnded)) { _ in
            isTransforming = false
        }
    }
}

// MARK: - Transform Notifications

extension Notification.Name {
    static let transformStarted = Notification.Name("transformStarted")
    static let transformEnded = Notification.Name("transformEnded")
}