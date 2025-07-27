//
//  VisibleObjectBrowser.swift
//  Vistaview - Always visible object browser with draggable thumbnails
//

import SwiftUI
import SceneKit

struct VisibleObjectBrowser: View {
    @State private var selectedCategory: ObjectCategory = .all
    
    enum ObjectCategory: String, CaseIterable {
        case all = "All"
        case ledWalls = "LED Walls"
        case cameras = "Cameras" 
        case lighting = "Lighting"
        case setPieces = "Set Pieces"
        
        var icon: String {
            switch self {
            case .all: return "rectangle.3.group"
            case .ledWalls: return "tv"
            case .cameras: return "video"
            case .lighting: return "lightbulb"
            case .setPieces: return "cube.box"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .purple
            case .ledWalls: return .blue
            case .cameras: return .orange
            case .lighting: return .yellow
            case .setPieces: return .green
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cube.box.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Studio Objects")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.black.opacity(0.8))
            
            // Category selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ObjectCategory.allCases, id: \.rawValue) { category in
                        CategoryButton(
                            category: category,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
            .background(.black.opacity(0.6))
            
            // Object grid
            ScrollView(.vertical) {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 12)
                ], spacing: 12) {
                    ForEach(assetsForCategory, id: \.id) { asset in
                        ObjectCard(asset: asset)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(.black.opacity(0.4))
        }
        .background(.regularMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
    
    private var assetsForCategory: [any StudioAsset] {
        switch selectedCategory {
        case .all:
            let all: [any StudioAsset] = LEDWallAsset.predefinedWalls + 
                                        CameraAsset.predefinedCameras + 
                                        LightAsset.predefinedLights + 
                                        SetPieceAsset.predefinedPieces
            return all
        case .ledWalls:
            return LEDWallAsset.predefinedWalls
        case .cameras:
            return CameraAsset.predefinedCameras
        case .lighting:
            return LightAsset.predefinedLights
        case .setPieces:
            return SetPieceAsset.predefinedPieces
        }
    }
}

struct CategoryButton: View {
    let category: VisibleObjectBrowser.ObjectCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .medium))
                
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? category.color : .white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? .clear : .white.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ObjectCard: View {
    let asset: any StudioAsset
    
    @State private var isDragging = false
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Large thumbnail
            ZStack {
                // Background with asset color
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(asset.color).opacity(0.3),
                                Color(asset.color).opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                // Asset icon
                Image(systemName: asset.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(Color(asset.color))
                
                // Type indicator dot
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color(asset.color))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                            )
                    }
                    Spacer()
                }
                .padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(asset.color).opacity(isHovered ? 0.8 : 0.3), lineWidth: isHovered ? 2 : 1)
            )
            
            // Asset name
            Text(asset.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32)
        }
        .frame(width: 100)
        .scaleEffect(isDragging ? 1.1 : (isHovered ? 1.05 : 1.0))
        .opacity(isDragging ? 0.8 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .draggable(asset.id.uuidString) {
            // Drag preview
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(asset.color).opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: asset.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(asset.color))
                }
                
                Text(asset.name)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(12)
            .background(.black.opacity(0.9))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(asset.color), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
        }
        .onDrag {
            isDragging = true
            return NSItemProvider(object: asset.id.uuidString as NSString)
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { _ in
                    if !isDragging {
                        isDragging = true
                    }
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}

#Preview {
    VisibleObjectBrowser()
        .frame(width: 400, height: 600)
        .background(.black)
}