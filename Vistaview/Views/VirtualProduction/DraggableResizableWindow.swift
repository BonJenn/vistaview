//
//  DraggableResizableWindow.swift
//  Vistaview - SIMPLE draggable window that actually works
//

import SwiftUI

struct DraggableResizableWindow<Content: View>: View {
    let title: String
    let content: () -> Content
    
    @State private var windowPosition = CGSize(width: 200, height: 200)
    @State private var dragOffset = CGSize.zero
    @State private var windowSize = CGSize(width: 300, height: 500)
    @State private var isMinimized = false
    @State private var isVisible = true
    @State private var isDragging = false
    
    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                // DRAGGABLE TITLE BAR - DEAD SIMPLE
                Color.black.opacity(0.9)
                    .frame(height: 40)
                    .overlay(
                        HStack {
                            // Window controls
                            HStack(spacing: 6) {
                                Button("✕") { isVisible = false }
                                    .foregroundColor(.red)
                                Button("−") { isMinimized.toggle() }
                                    .foregroundColor(.yellow)
                            }
                            .font(.system(size: 12, weight: .bold))
                            
                            Spacer()
                            
                            Text(title)
                                .foregroundColor(.white)
                                .font(.headline)
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                    )
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                }
                                // Use translation as temporary offset, don't accumulate
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                // Only accumulate at the end
                                windowPosition.width += value.translation.width
                                windowPosition.height += value.translation.height
                                dragOffset = .zero
                                isDragging = false
                            }
                    )
                
                // Window content
                if !isMinimized {
                    ZStack {
                        content()
                            .frame(width: windowSize.width, height: windowSize.height - 40)
                            .background(.black.opacity(0.8))
                        
                        // Simple resize handle at bottom-right
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Rectangle()
                                    .fill(.white.opacity(0.3))
                                    .frame(width: 20, height: 20)
                                    .background(.blue.opacity(0.5))
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                let newWidth = max(250, windowSize.width + value.translation.width)
                                                let newHeight = max(200, windowSize.height + value.translation.height)
                                                windowSize = CGSize(width: newWidth, height: newHeight)
                                            }
                                    )
                            }
                        }
                    }
                }
            }
            .frame(width: windowSize.width, height: isMinimized ? 40 : windowSize.height)
            .background(.regularMaterial)
            .cornerRadius(12)
            .offset(x: windowPosition.width + dragOffset.width, y: windowPosition.height + dragOffset.height)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDragging)
        }
    }
}

#Preview {
    DraggableResizableWindow(title: "Studio Objects") {
        VStack {
            Text("SIMPLE TEST")
                .foregroundColor(.white)
                .font(.title)
            
            Text("Drag the title bar!")
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding()
    }
    .frame(width: 800, height: 600)
    .background(.black)
}