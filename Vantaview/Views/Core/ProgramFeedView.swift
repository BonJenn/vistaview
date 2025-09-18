//
//  ProgramFeedView.swift
//  Vantaview
//

import SwiftUI
import Metal

struct ProgramFeedView: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    @State private var renderer: ProgramRenderer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let currentTexture = productionManager.programCurrentTexture {
                    // Use MetalView or similar to display the texture
                    MetalTextureView(texture: currentTexture)
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .overlay(
                            Text("Program Output")
                                .foregroundColor(.white)
                                .font(.caption)
                        )
                        .aspectRatio(16/9, contentMode: .fit)
                }
            }
        }
        .onAppear {
            // The new async architecture handles rendering automatically
        }
    }
}

// Simple Metal texture view for displaying textures
struct MetalTextureView: View {
    let texture: MTLTexture
    
    var body: some View {
        // This would need a proper Metal view implementation
        // For now, show a placeholder
        Rectangle()
            .fill(Color.blue.opacity(0.3))
            .overlay(
                Text("Metal Texture View\n\(texture.width)×\(texture.height)")
                    .multilineTextAlignment(.center)
                    .font(.caption)
                    .foregroundColor(.white)
            )
    }
}

#Preview {
    Text("Program Feed View")
}