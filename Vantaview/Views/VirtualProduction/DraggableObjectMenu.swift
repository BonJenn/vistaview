//
//  DraggableObjectMenu.swift
//  Vantaview - Draggable object menu with visual thumbnails
//

import SwiftUI
import SceneKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct DraggableObjectMenu: View {
    @Binding var isExpanded: Bool
    let onObjectDrop: (any StudioAsset, CGPoint) -> Void
    
    @State private var selectedCategory: AssetCategory = .ledWalls
    @State private var draggedAsset: (any StudioAsset)?
    
    // Menu state
    @State private var menuHeight: CGFloat = 60
    private let maxMenuHeight: CGFloat = 300
    private let minMenuHeight: CGFloat = 60
    
    enum AssetCategory: String, CaseIterable {
        case ledWalls = "LED Walls"
        case cameras = "Cameras"
        case lighting = "Lighting"
        case setPieces = "Set Pieces"
        case all = "All Objects"
        
        var icon: String {
            switch self {
            case .ledWalls: return "tv"
            case .cameras: return "video"
            case .lighting: return "lightbulb"
            case .setPieces: return "cube.box"
            case .all: return "rectangle.3.group"
            }
        }
        
        var color: Color {
            switch self {
            case .ledWalls: return .blue
            case .cameras: return .orange
            case .lighting: return .yellow
            case .setPieces: return .green
            case .all: return .purple
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Draggable object menu
            VStack(spacing: 0) {
                // Handle bar and header
                menuHeader
                
                if isExpanded {
                    // Category tabs
                    categoryTabs
                    
                    Divider()
                        .background(.white.opacity(0.2))
                    
                    // Scrollable asset grid
                    assetGrid
                }
            }
            .frame(height: isExpanded ? maxMenuHeight : minMenuHeight)
            .background(.black.opacity(0.9))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: -5)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
    
    private var menuHeader: some View {
        VStack(spacing: 8) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.4))
                .frame(width: 40, height: 4)
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
            
            // Title
            HStack {
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Studio Objects")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Expand/collapse indicator
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var categoryTabs: some View {
        HStack(spacing: 4) {
            ForEach(AssetCategory.allCases, id: \.rawValue) { category in
                CategoryTab(
                    category: category,
                    isSelected: selectedCategory == category,
                    action: { selectedCategory = category }
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var assetGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [
                GridItem(.flexible(minimum: 80, maximum: 100)),
                GridItem(.flexible(minimum: 80, maximum: 100))
            ], spacing: 12) {
                ForEach(assetsForCategory, id: \.id) { asset in
                    DraggableAssetCard(
                        asset: asset,
                        onDragStart: { draggedAsset = asset },
                        onDragEnd: { draggedAsset = nil }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 180)
    }
    
    private var assetsForCategory: [any StudioAsset] {
        switch selectedCategory {
        case .ledWalls:
            return LEDWallAsset.predefinedWalls
        case .cameras:
            return CameraAsset.predefinedCameras
        case .lighting:
            return LightAsset.predefinedLights
        case .setPieces:
            return Array(SetPieceAsset.predefinedPieces.prefix(20))
        case .all:
            let all: [any StudioAsset] = LEDWallAsset.predefinedWalls + 
                                        CameraAsset.predefinedCameras + 
                                        LightAsset.predefinedLights + 
                                        Array(SetPieceAsset.predefinedPieces.prefix(20))
            return all
        }
    }
}

struct CategoryTab: View {
    let category: DraggableObjectMenu.AssetCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .medium))
                
                Text(category.rawValue)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? category.color : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? .clear : .white.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DraggableAssetCard: View {
    let asset: any StudioAsset
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    
    @State private var isDragging = false
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        VStack(spacing: 6) {
            // Asset thumbnail/icon
            AssetThumbnailView(asset: asset)
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(asset.color).opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(asset.color).opacity(0.3), lineWidth: 1)
                )
            
            // Asset name
            Text(asset.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 24)
        }
        .frame(width: 80, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isDragging ? .white.opacity(0.1) : .clear)
        )
        .scaleEffect(isDragging ? 1.1 : 1.0)
        .offset(dragOffset)
        .opacity(isDragging ? 0.8 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        .draggable(asset.id.uuidString) {
            // Drag preview
            VStack(spacing: 4) {
                AssetThumbnailView(asset: asset)
                    .frame(width: 40, height: 40)
                
                Text(asset.name)
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            .padding(8)
            .background(.black.opacity(0.8))
            .cornerRadius(8)
        }
        .onDrag {
            onDragStart()
            isDragging = true
            return NSItemProvider(object: asset.id.uuidString as NSString)
        } preview: {
            AssetDragPreview(asset: asset)
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                    if !isDragging {
                        isDragging = true
                        onDragStart()
                    }
                }
                .onEnded { _ in
                    dragOffset = .zero
                    isDragging = false
                    onDragEnd()
                }
        )
    }
}

struct AssetThumbnailView: View {
    let asset: any StudioAsset
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(asset.color).opacity(0.3),
                    Color(asset.color).opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Asset icon
            Image(systemName: asset.icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Color(asset.color))
            
            // Asset type indicator
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    Circle()
                        .fill(Color(asset.color))
                        .frame(width: 8, height: 8)
                        .padding(4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AssetDragPreview: View {
    let asset: any StudioAsset
    
    var body: some View {
        VStack(spacing: 6) {
            AssetThumbnailView(asset: asset)
                .frame(width: 50, height: 50)
            
            Text(asset.name)
                .font(.caption2.weight(.medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(8)
        .background(.black.opacity(0.9))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(asset.color), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    DraggableObjectMenu(
        isExpanded: .constant(true),
        onObjectDrop: { _, _ in }
    )
    .frame(width: 400, height: 400)
    .background(.black)
}