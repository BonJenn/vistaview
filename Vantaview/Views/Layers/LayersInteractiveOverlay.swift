import SwiftUI
#if os(macOS)
import AppKit
#endif

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
                    .environmentObject(layerManager)
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

    @EnvironmentObject private var layerManager: LayerStackManager

    @State private var dragStartCenter = CGPoint.zero
    @State private var dragStartSize = CGSize.zero
    @State private var activeHandle: Handle?
    @State private var isEditingTitle = false
    @State private var editText: String = ""
    @FocusState private var titleFocused: Bool

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

    // Measure text precisely (macOS) and return tight bounding size
    private func measuredTextSize(_ text: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGSize {
        #if os(macOS)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .paragraphStyle: paragraph
        ]
        let bound = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let rect = (text as NSString).boundingRect(
            with: bound,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        // Add a small font-metric fudge to ensure no descender clipping
        let ascent = NSFont.systemFont(ofSize: fontSize, weight: .bold).ascender
        let descent = abs(NSFont.systemFont(ofSize: fontSize, weight: .bold).descender)
        let leading: CGFloat = 2
        let lineHeight = ascent + descent + leading
        let h = max(rect.height, lineHeight)
        return CGSize(width: ceil(rect.width), height: ceil(h))
        #else
        return CGSize(width: 200, height: fontSize * 1.35)
        #endif
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
                .highPriorityGesture(
                    TapGesture(count: 2).onEnded {
                        onSelect()
                        if case .title(let overlay) = layer.source {
                            editText = overlay.text
                            isEditingTitle = true
                            layerManager.beginEditingLayer(layer.id)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                titleFocused = true
                            }
                        }
                    }
                )
                .simultaneousGesture(
                    TapGesture(count: 1).onEnded { onSelect() }
                )
                .gesture(dragMoveGesture())

            // Live-updating, precisely-sized editor (no clipping, single visible layer)
            if isSelected, isEditingTitle, case .title(let overlay) = layer.source {
                let textSize = measuredTextSize(
                    editText.isEmpty ? " " : editText,
                    fontSize: overlay.fontSize,
                    maxWidth: canvasSize.width * 0.95
                )
                let padW: CGFloat = 22
                let padH: CGFloat = 22
                let fieldW = max(60, textSize.width + padW)
                let fieldH = max(overlay.fontSize + padH * 0.5, textSize.height + padH)

                TextField("", text: Binding(
                    get: { editText },
                    set: { editText = $0 }
                ))
                .focused($titleFocused)
                .textFieldStyle(PlainTextFieldStyle()) // avoid border-induced clipping
                .font(.system(size: overlay.fontSize, weight: .bold))
                .foregroundColor(Color.white)
                .frame(width: fieldW, height: fieldH, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.blue.opacity(0.6), lineWidth: 2)
                )
                .position(x: rect.midX, y: rect.midY)
                .onChange(of: editText) { _, newValue in
                    var updated = layer
                    if case .title(var ov) = updated.source {
                        ov.text = newValue
                        updated.source = .title(ov)

                        if ov.autoFit {
                            // Auto-fit layer to measured size
                            let tSize = measuredTextSize(newValue.isEmpty ? " " : newValue, fontSize: ov.fontSize, maxWidth: canvasSize.width * 0.95)
                            let desiredW = tSize.width + padW
                            let desiredH = tSize.height + padH
                            let minW = max(canvasSize.width * 0.05, 24)
                            let minH = max(canvasSize.height * 0.05, 20)
                            let wNorm = min(1.0, max(minW, desiredW) / canvasSize.width)
                            let hNorm = min(1.0, max(minH, desiredH) / canvasSize.height)
                            updated.sizeNorm = CGSize(width: wNorm, height: hNorm)
                        }
                        onUpdate(updated)
                    }
                }
                .onChange(of: layer) { _, _ in
                    if case .title(let ov) = layer.source, ov.autoFit {
                        // Refit on external changes (e.g. font size)
                        var updated = layer
                        let text = isEditingTitle ? editText : ov.text
                        let tSize = measuredTextSize(text.isEmpty ? " " : text, fontSize: ov.fontSize, maxWidth: canvasSize.width * 0.95)
                        let desiredW = tSize.width + padW
                        let desiredH = tSize.height + padH
                        let minW = max(canvasSize.width * 0.05, 24)
                        let minH = max(canvasSize.height * 0.05, 20)
                        let wNorm = min(1.0, max(minW, desiredW) / canvasSize.width)
                        let hNorm = min(1.0, max(minH, desiredH) / canvasSize.height)
                        updated.sizeNorm = CGSize(width: wNorm, height: hNorm)
                        onUpdate(updated)
                    }
                }
                .onSubmit {
                    isEditingTitle = false
                    layerManager.endEditing()
                }
                .onExitCommand {
                    isEditingTitle = false
                    layerManager.endEditing()
                }
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