//
//  BlenderStyleToolbar.swift
//  Vantaview - Blender-inspired object placement toolbar
//

import SwiftUI
import SceneKit

struct BlenderStyleToolbar: View {
    @Binding var selectedTool: StudioTool
    @Binding var showingAddMenu: Bool
    let onAddObject: (StudioTool, any StudioAsset) -> Void
    
    // Toolbar state
    @State private var isCollapsed = false
    @State private var showingAssetPicker = false
    @State private var selectedAssetType: StudioTool?
    
    // Layout constants
    private let toolbarWidth: CGFloat = 52
    private let buttonSize: CGFloat = 44
    private let spacing: CGFloat = 4
    private let cornerRadius: CGFloat = 8
    
    var body: some View {
        VStack {
            HStack {
                // Left toolbar
                VStack(spacing: spacing) {
                    // Collapse/Expand button
                    ToolbarButton(
                        icon: isCollapsed ? "chevron.down" : "chevron.up",
                        isSelected: false,
                        action: { 
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isCollapsed.toggle()
                            }
                        }
                    )
                    
                    if !isCollapsed {
                        Divider()
                            .frame(height: 1)
                            .background(.white.opacity(0.2))
                        
                        // Selection tool
                        ToolbarButton(
                            icon: "cursorarrow",
                            isSelected: selectedTool == .select,
                            tooltip: "Select (V)",
                            action: { selectedTool = .select }
                        )
                        
                        Divider()
                            .frame(height: 1)
                            .background(.white.opacity(0.2))
                        
                        // Add menu button (Shift+A equivalent)
                        ToolbarButton(
                            icon: "plus",
                            isSelected: showingAddMenu,
                            tooltip: "Add (Shift+A)",
                            action: { 
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    showingAddMenu.toggle()
                                }
                            }
                        )
                        
                        // Quick add buttons
                        Group {
                            ToolbarButton(
                                icon: "tv",
                                isSelected: selectedTool == .ledWall,
                                tooltip: "LED Wall (L)",
                                action: { selectedTool = .ledWall }
                            )
                            
                            ToolbarButton(
                                icon: "video",
                                isSelected: selectedTool == .camera,
                                tooltip: "Camera (C)",
                                action: { selectedTool = .camera }
                            )
                            
                            ToolbarButton(
                                icon: "lightbulb",
                                isSelected: selectedTool == .light,
                                tooltip: "Light (Shift+L)",
                                action: { selectedTool = .light }
                            )
                            
                            ToolbarButton(
                                icon: "cube.box",
                                isSelected: selectedTool == .setPiece,
                                tooltip: "Set Piece (S)",
                                action: { selectedTool = .setPiece }
                            )
                        }
                    }
                    
                    Spacer()
                }
                .frame(width: toolbarWidth)
                .padding(.vertical, 8)
                .background(.black.opacity(0.8))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
                
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.top, 16)
            
            Spacer()
        }
        .overlay(
            // Add Menu (Blender Shift+A style)
            addMenuOverlay
        )
    }
    
    @ViewBuilder
    private var addMenuOverlay: some View {
        if showingAddMenu {
            VStack {
                HStack {
                    AddMenuView(
                        selectedTool: $selectedTool,
                        isPresented: $showingAddMenu,
                        onAddObject: onAddObject
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
                    
                    Spacer()
                }
                .padding(.leading, toolbarWidth + 24)
                .padding(.top, 120)
                
                Spacer()
            }
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingAddMenu = false
                        }
                    }
            )
        }
    }
}

struct ToolbarButton: View {
    let icon: String
    let isSelected: Bool
    let tooltip: String?
    let action: () -> Void
    
    @State private var isHovered = false
    
    init(icon: String, isSelected: Bool, tooltip: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.isSelected = isSelected
        self.tooltip = tooltip
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isSelected ? .black : .white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? .white : (isHovered ? .white.opacity(0.15) : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? .clear : .white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip ?? "")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct AddMenuView: View {
    @Binding var selectedTool: StudioTool
    @Binding var isPresented: Bool
    let onAddObject: (StudioTool, any StudioAsset) -> Void
    
    @State private var selectedCategory: AddMenuCategory = .studioObjects
    @State private var hoveredAsset: (any StudioAsset)?
    
    enum AddMenuCategory: String, CaseIterable {
        case studioObjects = "Studio Objects"
        case ledWalls = "LED Walls"
        case cameras = "Cameras"
        case lighting = "Lighting"
        case setPieces = "Set Pieces"
        
        var icon: String {
            switch self {
            case .studioObjects: return "plus.app"
            case .ledWalls: return "tv"
            case .cameras: return "video"
            case .lighting: return "lightbulb"
            case .setPieces: return "cube.box"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Cancel") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isPresented = false
                    }
                }
                .foregroundColor(.white.opacity(0.7))
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.9))
            
            Divider()
                .background(.white.opacity(0.2))
            
            HStack(spacing: 0) {
                // Category sidebar
                VStack(spacing: 2) {
                    ForEach(AddMenuCategory.allCases, id: \.rawValue) { category in
                        AddMenuCategoryButton(
                            category: category,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                    
                    Spacer()
                }
                .frame(width: 140)
                .background(.black.opacity(0.6))
                
                Divider()
                    .background(.white.opacity(0.2))
                
                // Content area
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 8)
                    ], spacing: 8) {
                        ForEach(assetsForCategory, id: \.id) { asset in
                            AddMenuAssetCard(
                                asset: asset,
                                isHovered: hoveredAsset?.id == asset.id,
                                onHover: { hovering in
                                    hoveredAsset = hovering ? asset : nil
                                },
                                onTap: {
                                    handleAssetSelection(asset)
                                }
                            )
                        }
                    }
                    .padding(12)
                }
                .frame(width: 320, height: 280)
                .background(.black.opacity(0.8))
            }
        }
        .frame(width: 460, height: 320)
        .background(.black.opacity(0.95))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
    }
    
    private var assetsForCategory: [any StudioAsset] {
        switch selectedCategory {
        case .studioObjects:
            return [LEDWallAsset.predefinedWalls.first!, CameraAsset.predefinedCameras.first!, LightAsset.predefinedLights.first!, SetPieceAsset.predefinedPieces.first!]
        case .ledWalls:
            return LEDWallAsset.predefinedWalls
        case .cameras:
            return CameraAsset.predefinedCameras
        case .lighting:
            return LightAsset.predefinedLights
        case .setPieces:
            return Array(SetPieceAsset.predefinedPieces.prefix(12)) // Show first 12 for performance
        }
    }
    
    private func handleAssetSelection(_ asset: any StudioAsset) {
        // Determine tool type from asset
        let toolType: StudioTool
        switch asset {
        case is LEDWallAsset:
            toolType = .ledWall
        case is CameraAsset:
            toolType = .camera
        case is LightAsset:
            toolType = .light
        case is SetPieceAsset:
            toolType = .setPiece
        default:
            toolType = .select
        }
        
        selectedTool = toolType
        onAddObject(toolType, asset)
        
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}

struct AddMenuCategoryButton: View {
    let category: AddMenuView.AddMenuCategory
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 16)
                
                Text(category.rawValue)
                    .font(.system(size: 12, weight: .medium))
                
                Spacer()
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? .white : (isHovered ? .white.opacity(0.1) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct AddMenuAssetCard: View {
    let asset: any StudioAsset
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            // Icon
            Image(systemName: asset.icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Color(asset.color))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color(asset.color).opacity(0.15))
                )
            
            // Name
            Text(asset.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28)
        }
        .frame(width: 110, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? .white.opacity(0.1) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHovered ? .white.opacity(0.3) : .white.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                onHover(hovering)
            }
        }
    }
}

#Preview {
    BlenderStyleToolbar(
        selectedTool: .constant(.select),
        showingAddMenu: .constant(false),
        onAddObject: { _, _ in }
    )
    .frame(width: 400, height: 600)
    .background(.black)
}