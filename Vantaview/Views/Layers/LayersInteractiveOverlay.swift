import SwiftUI

struct LayersInteractiveOverlay: View {
    @EnvironmentObject var layerManager: LayerStackManager

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(layerManager.layers.sorted(by: { $0.zIndex < $1.zIndex })) { layer in
                    LayerHandleView(
                        layer: layer,
                        canvasSize: size,
                        isSelected: layerManager.selectedLayerID == layer.id,
                        onSelect: { layerManager.selectedLayerID = layer.id },
                        onUpdate: { updated in layerManager.update(updated) }
                    )
                }
            }
        }
        .allowsHitTesting(true)
    }
}

private struct LayerHandleView: View {
    var layer: CompositedLayer
    var canvasSize: CGSize
    var isSelected: Bool
    var onSelect: () -> Void
    var onUpdate: (CompositedLayer) -> Void

    @State private var dragStartCenter = CGPoint.zero
    @State private var dragStartSize = CGSize.zero
    @State private var activeHandle: Handle?

    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private var rect: CGRect {
        let w = layer.sizeNorm.width * canvasSize.width
        let h = layer.sizeNorm.height * canvasSize.height
        let cx = layer.centerNorm.x * canvasSize.width
        let cy = layer.centerNorm.y * canvasSize.height
        return CGRect(x: cx - w/2, y: cy - h/2, width: w, height: h)
    }

    private func handlePosition(_ h: Handle) -> CGPoint {
        let r = rect
        switch h {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .top: return CGPoint(x: r.midX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .right: return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: return CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .left: return CGPoint(x: r.minX, y: r.midY)
        }
    }

    var body: some View {
        ZStack {
            // Select/move gesture area
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    Rectangle()
                        .stroke(isSelected ? Color.orange : Color.white.opacity(0.6), lineWidth: isSelected ? 2 : 1)
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .contentShape(Rectangle())
                .gesture(dragMoveGesture())
                .onTapGesture {
                    onSelect()
                }

            if isSelected {
                ForEach(Handle.allCases, id: \.self) { h in
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 1))
                        .position(handlePosition(h))
                        .gesture(dragResizeGesture(handle: h))
                }
            }
        }
        .animation(.easeOut(duration: 0.08), value: isSelected)
    }

    private func dragMoveGesture() -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeHandle != nil { return }
                if dragStartCenter == .zero {
                    dragStartCenter = layer.centerNorm
                    onSelect()
                }
                let dx = value.translation.width / canvasSize.width
                let dy = value.translation.height / canvasSize.height
                var updated = layer
                updated.centerNorm = CGPoint(
                    x: clamp01(dragStartCenter.x + dx),
                    y: clamp01(dragStartCenter.y + dy)
                )
                onUpdate(updated)
            }
            .onEnded { _ in
                dragStartCenter = .zero
            }
    }

    private func dragResizeGesture(handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartSize == .zero {
                    dragStartSize = layer.sizeNorm
                    dragStartCenter = layer.centerNorm
                    activeHandle = handle
                    onSelect()
                }
                var dW: CGFloat = value.translation.width / canvasSize.width
                var dH: CGFloat = value.translation.height / canvasSize.height

                // Corner handles scale both axes; edges scale one axis
                var newSize = dragStartSize
                var newCenter = dragStartCenter

                switch handle {
                case .topLeft:
                    newSize.width = clampMin(dragStartSize.width - dW)
                    newSize.height = clampMin(dragStartSize.height - dH)
                    newCenter.x = clamp01(dragStartCenter.x + dW / 2)
                    newCenter.y = clamp01(dragStartCenter.y + dH / 2)
                case .top:
                    newSize.height = clampMin(dragStartSize.height - dH)
                    newCenter.y = clamp01(dragStartCenter.y + dH / 2)
                case .topRight:
                    newSize.width = clampMin(dragStartSize.width + dW)
                    newSize.height = clampMin(dragStartSize.height - dH)
                    newCenter.x = clamp01(dragStartCenter.x + dW / 2)
                    newCenter.y = clamp01(dragStartCenter.y + dH / 2)
                case .right:
                    newSize.width = clampMin(dragStartSize.width + dW)
                    newCenter.x = clamp01(dragStartCenter.x + dW / 2)
                case .bottomRight:
                    newSize.width = clampMin(dragStartSize.width + dW)
                    newSize.height = clampMin(dragStartSize.height + dH)
                    newCenter.x = clamp01(dragStartCenter.x + dW / 2)
                    newCenter.y = clamp01(dragStartCenter.y + dH / 2)
                case .bottom:
                    newSize.height = clampMin(dragStartSize.height + dH)
                    newCenter.y = clamp01(dragStartCenter.y + dH / 2)
                case .bottomLeft:
                    newSize.width = clampMin(dragStartSize.width - dW)
                    newSize.height = clampMin(dragStartSize.height + dH)
                    newCenter.x = clamp01(dragStartCenter.x + dW / 2)
                    newCenter.y = clamp01(dragStartCenter.y + dH / 2)
                case .left:
                    newSize.width = clampMin(dragStartSize.width - dW)
                    newCenter.x = clamp01(dragStartCenter.x + dW / 2)
                }

                var updated = layer
                updated.sizeNorm = CGSize(width: clamp01(newSize.width), height: clamp01(newSize.height))
                updated.centerNorm = newCenter
                onUpdate(updated)
            }
            .onEnded { _ in
                dragStartSize = .zero
                dragStartCenter = .zero
                activeHandle = nil
            }
    }

    private func clamp01(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
    private func clampMin(_ v: CGFloat, _ minVal: CGFloat = 0.05) -> CGFloat { max(v, minVal) }
}