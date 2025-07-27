//
//  VisibleObjectBrowser.swift
//  Vistaview - Always visible object browser with draggable thumbnails
//

import SwiftUI
import SceneKit

struct VisibleObjectBrowser: View {
    @State private var selectedCategory: ObjectCategory = .all
    @EnvironmentObject var studioManager: VirtualStudioManager // Add this to get access to studio manager
    
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
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Click to add")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Drag to position")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
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
                        ObjectCard(asset: asset, studioManager: studioManager)
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
    let studioManager: VirtualStudioManager
    
    @State private var isDragging = false
    @State private var isHovered = false
    @State private var isPressed = false
    
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
                
                // Add + button overlay when hovered (but not when dragging)
                if isHovered && !isDragging {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.8))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
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
        .scaleEffect(isPressed ? 0.95 : (isHovered && !isDragging ? 1.05 : (isDragging ? 1.1 : 1.0)))
        .opacity(isDragging ? 0.8 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            // Only handle tap if not dragging
            guard !isDragging else { return }
            
            // Visual feedback
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
            }
            
            // Add object to scene
            addObjectToScene()
        }
        .draggable(asset.id.uuidString) {
            // Enhanced drag preview
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(asset.color).opacity(0.9))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: asset.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Text(asset.name)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
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
            print("🎯 Starting drag for: \(asset.name) with ID: \(asset.id.uuidString)")
            isDragging = true
            
            // Use the simple NSItemProvider with NSString
            return NSItemProvider(object: asset.id.uuidString as NSString)
        }
        .onChange(of: isDragging) { _, newValue in
            // Reset drag state after a delay when drag ends
            if !newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isDragging = false
                }
            }
        }
    }
    
    private func addObjectToScene() {
        // Generate a semi-random position in front of the camera
        let randomOffset = Float.random(in: -2...2)
        let position = SCNVector3(randomOffset, 0, -5)
        
        print("🎯 Adding \(asset.name) to scene at \(position)")
        
        // Add the appropriate object type
        switch asset {
        case let ledWallAsset as LEDWallAsset:
            studioManager.addLEDWall(from: ledWallAsset, at: position)
            
        case let cameraAsset as CameraAsset:
            let camera = VirtualCamera(name: cameraAsset.name, position: position)
            camera.focalLength = Float(cameraAsset.focalLength)
            studioManager.virtualCameras.append(camera)
            studioManager.scene.rootNode.addChildNode(camera.node)
            
        case let lightAsset as LightAsset:
            studioManager.addLight(from: lightAsset, at: position)
            
        case let setPieceAsset as SetPieceAsset:
            studioManager.addSetPiece(from: setPieceAsset, at: position)
            
        default:
            print("⚠️ Unknown asset type: \(type(of: asset))")
        }
    }
}

#Preview {
    VisibleObjectBrowser()
        .frame(width: 400, height: 600)
        .background(.black)
}