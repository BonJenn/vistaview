//
//  SetPiecePanelView.swift
//  Vantaview - Raycast-Inspired Set Pieces Panel
//

import SwiftUI
import SceneKit

struct SetPiecePanelView: View {
    @EnvironmentObject var studioManager: VirtualStudioManager
    @State private var selectedCategory: StudioCategory = .newsStudio
    @State private var expandedSubcategories: Set<SetPieceSubcategory> = [.ledWalls, .furniture, .lighting, .props]
    @State private var searchText = ""

    private let spacing1: CGFloat = 4
    private let spacing2: CGFloat = 8
    private let spacing3: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            panelHeader

            searchField

            Divider()
                .background(.tertiary.opacity(0.3))

            categoryTabs

            Divider()
                .background(.tertiary.opacity(0.3))

            setPiecesContent
        }
        .background(.ultraThinMaterial)
    }

    private var panelHeader: some View {
        HStack(spacing: spacing2) {
            Image(systemName: "cube.box.fill")
                .font(.system(.callout, design: .default, weight: .semibold))
                .foregroundColor(.blue)

            Text("Asset Library")
                .font(.system(.title3, design: .default, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedSubcategories.isEmpty {
                        expandedSubcategories = Set(selectedCategory.subcategories)
                    } else {
                        expandedSubcategories.removeAll()
                    }
                }
            }) {
                Image(systemName: expandedSubcategories.isEmpty ? "plus.circle" : "minus.circle")
                    .font(.system(.callout, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, spacing3)
        .padding(.vertical, 12)
        .background(.black.opacity(0.1))
    }

    private var searchField: some View {
        HStack(spacing: spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(.callout, design: .default, weight: .medium))
                .foregroundColor(.secondary)

            TextField("Search assets...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .default, weight: .regular))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, spacing3)
        .padding(.vertical, spacing2)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
        .padding(.horizontal, spacing3)
        .padding(.vertical, spacing2)
        .contentShape(Rectangle())
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing2) {
                ForEach(StudioCategory.allCases, id: \.self) { category in
                    categoryChip(category: category)
                }
            }
            .padding(.horizontal, spacing3)
        }
        .frame(height: 44)
    }

    private func categoryChip(category: StudioCategory) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
                expandedSubcategories = Set(category.subcategories)
            }
        }) {
            HStack(spacing: 6) {
                Text(category.icon)
                    .font(.system(size: 14))

                Text(category.rawValue)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedCategory == category ? .blue : Color.gray.opacity(0.3))
            .foregroundColor(selectedCategory == category ? .white : .primary)
            .cornerRadius(16)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .scaleEffect(selectedCategory == category ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: selectedCategory == category)
    }

    private var setPiecesContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing2) {
                ForEach(selectedCategory.subcategories, id: \.self) { subcategory in
                    if searchText.isEmpty || hasMatchingAssets(subcategory) {
                        RaycastSetPieceSubcategorySection(
                            subcategory: subcategory,
                            category: selectedCategory,
                            isExpanded: expandedSubcategories.contains(subcategory),
                            searchText: searchText,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedSubcategories.contains(subcategory) {
                                        expandedSubcategories.remove(subcategory)
                                    } else {
                                        expandedSubcategories.insert(subcategory)
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, spacing2)
            .padding(.vertical, spacing3)
        }
    }

    private func hasMatchingAssets(_ subcategory: SetPieceSubcategory) -> Bool {
        let pieces = SetPieceAsset.pieces(for: selectedCategory, subcategory: subcategory)
        return pieces.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

struct RaycastSetPieceSubcategorySection: View {
    let subcategory: SetPieceSubcategory
    let category: StudioCategory
    let isExpanded: Bool
    let searchText: String
    let onToggle: () -> Void

    @EnvironmentObject var studioManager: VirtualStudioManager

    private let spacing1: CGFloat = 4
    private let spacing2: CGFloat = 8
    private let spacing3: CGFloat = 16

    var setPieces: [SetPieceAsset] {
        let allPieces = SetPieceAsset.pieces(for: category, subcategory: subcategory)
        if searchText.isEmpty {
            return allPieces
        }
        return allPieces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing1) {
            subcategoryHeader

            if isExpanded && !setPieces.isEmpty {
                setPieceGrid
            }
        }
    }

    private var subcategoryHeader: some View {
        Button(action: onToggle) {
            HStack(spacing: spacing2) {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)

                Image(systemName: subcategory.icon)
                    .font(.system(.callout, design: .default, weight: .medium))
                    .foregroundColor(.blue)

                Text(subcategory.rawValue)
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Text("\(setPieces.count)")
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.4))
                    .cornerRadius(10)
            }
            .padding(.horizontal, spacing3)
            .padding(.vertical, spacing2)
            .background(.tertiary.opacity(0.2))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // Add subtle hover effect if needed
        }
    }

    private var setPieceGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: spacing1),
            GridItem(.flexible(), spacing: spacing1)
        ], spacing: spacing2) {
            ForEach(setPieces) { setPiece in
                RaycastDraggableSetPiece(setPiece: setPiece)
            }
        }
        .padding(.horizontal, spacing3)
        .padding(.top, spacing1)
    }
}

struct RaycastDraggableSetPiece: View {
    let setPiece: SetPieceAsset
    @EnvironmentObject var studioManager: VirtualStudioManager
    @State private var isDragging = false
    @State private var isHovered = false

    private let spacing1: CGFloat = 4
    private let spacing2: CGFloat = 8

    var body: some View {
        VStack(spacing: spacing1) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.blue.opacity(0.1))
                    .frame(height: 44)

                Image(systemName: setPiece.thumbnailImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.blue)
            }

            Text(setPiece.name)
                .font(.system(.caption, design: .default, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 2) {
                Text("\(setPiece.size.x, specifier: "%.1f")")
                    .foregroundColor(.red.opacity(0.8))
                Text("×")
                    .foregroundColor(.secondary)
                Text("\(setPiece.size.y, specifier: "%.1f")")
                    .foregroundColor(.green.opacity(0.8))
                Text("×")
                    .foregroundColor(.secondary)
                Text("\(setPiece.size.z, specifier: "%.1f")")
                    .foregroundColor(.blue.opacity(0.8))
                Text("m")
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, spacing2)
        .padding(.horizontal, spacing1)
        .background(backgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isHovered ? 1 : 0)
        )
        .scaleEffect(isDragging ? 0.95 : (isHovered ? 1.02 : 1.0))
        .shadow(color: .black.opacity(isDragging ? 0.2 : 0), radius: isDragging ? 8 : 0, y: isDragging ? 4 : 0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag {
            isDragging = true
            let provider = NSItemProvider(object: setPiece.id.uuidString as NSString)
            provider.suggestedName = setPiece.name

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isDragging = false
            }

            return provider
        } preview: {
            RaycastDragPreviewView(setPiece: setPiece)
        }
        .onTapGesture(count: 2) {
            addToSceneAtRandomPosition()
        }
        .contextMenu {
            RaycastSetPieceContextMenu(setPiece: setPiece)
        }
    }

    private var backgroundColor: Color {
        if isDragging {
            return .blue.opacity(0.3)
        } else if isHovered {
            return Color.gray.opacity(0.3)
        } else {
            return Color.gray.opacity(0.1)
        }
    }

    private var borderColor: Color {
        if isDragging {
            return .blue
        } else if isHovered {
            return .blue.opacity(0.5)
        } else {
            return .clear
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

struct RaycastDragPreviewView: View {
    let setPiece: SetPieceAsset

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.blue.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: setPiece.thumbnailImage)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.blue)
            }

            Text(setPiece.name)
                .font(.system(.body, design: .default, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thickMaterial)
                .cornerRadius(8)
                .lineLimit(1)
        }
        .opacity(0.95)
        .scaleEffect(1.1)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
    }
}

struct RaycastSetPieceContextMenu: View {
    let setPiece: SetPieceAsset
    @EnvironmentObject var studioManager: VirtualStudioManager

    var body: some View {
        Group {
            Button("Add to Scene") {
                let position = SCNVector3(0, 0, 0)
                studioManager.addSetPieceFromAsset(setPiece, at: position)
            }
            .keyboardShortcut(.return)

            Button("Add Random Position") {
                let position = SCNVector3(
                    Float.random(in: -5...5),
                    0,
                    Float.random(in: -5...5)
                )
                studioManager.addSetPieceFromAsset(setPiece, at: position)
            }
            .keyboardShortcut("r")

            Divider()

            Button("Copy Asset Info") {
                let info = "\(setPiece.name) - \(setPiece.size.x)×\(setPiece.size.y)×\(setPiece.size.z)m"
                print("Copied: \(info)")
            }
            .keyboardShortcut("c", modifiers: [.command])
        }
    }
}