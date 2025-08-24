//
//  KeyboardFeedbackOverlay.swift
//  Vantaview - Visual feedback for keyboard shortcuts
//

import SwiftUI

@MainActor
class KeyboardFeedbackController: ObservableObject {
    @Published var isVisible = false
    @Published var currentMessage = ""
    @Published var currentColor = Color.white
    
    private var hideTimer: Timer?
    
    func showFeedback(_ message: String, color: Color = .white, duration: TimeInterval = 2.0) {
        currentMessage = message
        currentColor = color
        isVisible = true
        
        // Cancel existing timer
        hideTimer?.invalidate()
        
        // Set new timer to hide feedback
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.3)) {
                    self.isVisible = false
                }
            }
        }
    }
    
    func hideFeedback() {
        hideTimer?.invalidate()
        withAnimation(.easeOut(duration: 0.3)) {
            isVisible = false
        }
    }
}

struct KeyboardFeedbackOverlay: View {
    @ObservedObject var controller: KeyboardFeedbackController
    
    var body: some View {
        if controller.isVisible {
            VStack {
                HStack {
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(controller.currentColor)
                        
                        Text(controller.currentMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.black.opacity(0.85))
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(controller.currentColor, lineWidth: 2)
                    )
                    .shadow(color: controller.currentColor.opacity(0.3), radius: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer()
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.9).combined(with: .opacity),
                removal: .scale(scale: 0.9).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: controller.isVisible)
        }
    }
}