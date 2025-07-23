//
//  SetPiecePanelView.swift
//  Vistaview - Functional Drag & Drop Set Pieces
//

import SwiftUI
import SceneKit

struct SetPiecePanelView: View {
    @EnvironmentObject var studioManager: VirtualStudioManager
    @State private var selectedCategory: StudioCategory = .newsStudio
    @State private var expandedSubcategories: Set<SetPieceSubcategory> = [.ledWalls, .furniture, .lighting, .props]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("📺 Set Pieces")
                    .font(.headline)
                    .foregroundColor(.white)
                    .fixedSize()
                Spacer()
                Button(action: {
                    expandedSubcategories.removeAll()
                }) {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))
            
            // Category Tabs
            categoryTabs
            
            Divider()
            
            // Set Pieces Content  
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedCategory.subcategories, id: \.self) { subcategory in
                        SetPieceSubcategorySection(
                            subcategory: subcategory,
                            category: selectedCategory,
                            isExpanded: expandedSubcategories.contains(subcategory),
                            onToggle: {
                                if expandedSubcategories.contains(subcategory) {
                                    expandedSubcategories.remove(subcategory)
                                } else {
                                    expandedSubcategories.insert(subcategory)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
        }
    }
    
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StudioCategory.allCases, id: \.self) { category in
                    Button(action: {
                        selectedCategory = category
                        expandedSubcategories = Set(category.subcategories)
                    }) {
                        HStack(spacing: 6) {
                            Text(category.icon)
                                .font(.system(size: 14))
                            
                            Text(category.rawValue)
                                .font(.caption)
                                .fontWeight(selectedCategory == category ? .semibold : .regular)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedCategory == category ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(selectedCategory == category ? .white : .primary)
                        .cornerRadius(16)
                        .fixedSize()
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 44)
    }
}

struct SetPieceSubcategorySection: View {
    let subcategory: SetPieceSubcategory
    let category: StudioCategory
    let isExpanded: Bool
    let onToggle: () -> Void
    
    @EnvironmentObject var studioManager: VirtualStudioManager
    
    var setPieces: [SetPieceAsset] {
        SetPieceAsset.pieces(for: category, subcategory: subcategory)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Subcategory Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: subcategory.icon)
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text(subcategory.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(setPieces.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        .fixedSize()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Set Piece Grid
            if isExpanded {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4)
                ], spacing: 8) {
                    ForEach(setPieces) { setPiece in
                        FunctionalDraggableSetPiece(setPiece: setPiece)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
        }
    }
}

struct FunctionalDraggableSetPiece: View {
    let setPiece: SetPieceAsset
    @EnvironmentObject var studioManager: VirtualStudioManager
    @State private var isDragging = false
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail
            Image(systemName: setPiece.thumbnailImage)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            
            // Name
            Text(setPiece.name)
                .font(.caption2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Size Info
            Text("\(setPiece.size.x, specifier: "%.1f")×\(setPiece.size.y, specifier: "%.1f")×\(setPiece.size.z, specifier: "%.1f")m")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(isDragging ? Color.blue.opacity(0.3) : Color.gray.opacity(0.05))
        .cornerRadius(8)
        .scaleEffect(isDragging ? 0.95 : 1.0)
        .offset(dragOffset)
        .animation(.easeInOut(duration: 0.1), value: isDragging)
        .onDrag {
            print("🚀 Starting drag for: \(setPiece.name) (ID: \(setPiece.id.uuidString))")
            let provider = NSItemProvider(object: setPiece.id.uuidString as NSString)
            provider.suggestedName = setPiece.name
            return provider
        } preview: {
            DragPreviewView(setPiece: setPiece)
        }
        .onTapGesture(count: 2) {
            addToSceneAtRandomPosition()
        }
        .onTapGesture(count: 1) {
            withAnimation(.easeInOut(duration: 0.1)) {
                isDragging = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isDragging = false
                }
            }
        }
    }
    
    private func addToSceneAtRandomPosition() {
        let position = SCNVector3(
            Float.random(in: -3...3),
            0,
            Float.random(in: -3...3)
        )
        studioManager.addSetPieceFromAsset(setPiece, at: position)
    }
}

struct DragPreviewView: View {
    let setPiece: SetPieceAsset
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: setPiece.thumbnailImage)
                .font(.system(size: 32))
                .foregroundColor(.blue)
                .frame(width: 60, height: 60)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(12)
            
            Text(setPiece.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.8))
                .cornerRadius(6)
                .lineLimit(1)
        }
        .opacity(0.9)
        .scaleEffect(1.1)
    }
}