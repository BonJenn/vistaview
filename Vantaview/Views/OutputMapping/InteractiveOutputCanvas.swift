import SwiftUI

struct InteractiveOutputCanvas: View {
    @ObservedObject var mappingManager: OutputMappingManager
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    @State private var isResizing = false
    @State private var resizeHandle: ResizeHandle = .none
    @State private var lastMappingPosition = CGPoint.zero
    @State private var lastMappingSize = CGSize.zero
    
    private let handleSize: CGFloat = 8
    private let minSize: CGFloat = 20
    
    enum ResizeHandle {
        case none, topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Canvas Background
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .overlay(
                        // Grid overlay
                        Path { path in
                            let gridSize: CGFloat = 20
                            for x in stride(from: 0, through: geometry.size.width, by: gridSize) {
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                            }
                            for y in stride(from: 0, through: geometry.size.height, by: gridSize) {
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                            }
                        }
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
                
                // Guidelines (when dragging or resizing)
                if isDragging || isResizing {
                    guidelines(in: geometry.size)
                }
                
                // Output Mapping Rectangle
                outputMappingRect(in: geometry.size)
                    .onAppear {
                        updateMappingFromGeometry(geometry.size)
                    }
                    .onChange(of: geometry.size) { oldSize, newSize in
                        updateMappingFromGeometry(newSize)
                    }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .clipped()
    }
    
    // MARK: - Output Mapping Rectangle
    
    @ViewBuilder
    private func outputMappingRect(in canvasSize: CGSize) -> some View {
        let mapping = mappingManager.currentMapping
        let rect = mappingRectInCanvas(mapping, canvasSize: canvasSize)
        
        ZStack {
            // Main rectangle
            Rectangle()
                .fill(Color.blue.opacity(0.3))
                .overlay(
                    Rectangle()
                        .stroke(Color.blue, lineWidth: 2)
                )
                .overlay(
                    // Center cross indicator
                    Path { path in
                        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
                        path.move(to: CGPoint(x: center.x - 10, y: center.y))
                        path.addLine(to: CGPoint(x: center.x + 10, y: center.y))
                        path.move(to: CGPoint(x: center.x, y: center.y - 10))
                        path.addLine(to: CGPoint(x: center.x, y: center.y + 10))
                    }
                    .stroke(Color.blue, lineWidth: 1)
                )
                .position(
                    x: rect.midX + dragOffset.width,
                    y: rect.midY + dragOffset.height
                )
                .frame(width: rect.width, height: rect.height)
                .rotationEffect(.degrees(Double(mapping.rotation)))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                mappingManager.isDragging = true
                                lastMappingPosition = mapping.position
                            }
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            let newPosition = CGPoint(
                                x: max(0, min(1, lastMappingPosition.x + value.translation.width / canvasSize.width)),
                                y: max(0, min(1, lastMappingPosition.y + value.translation.height / canvasSize.height))
                            )
                            
                            mappingManager.setPosition(newPosition)
                            
                            isDragging = false
                            mappingManager.isDragging = false
                            dragOffset = .zero
                        }
                )
            
            // Resize handles
            if !isDragging {
                resizeHandles(rect: rect, canvasSize: canvasSize)
            }
        }
    }
    
    // MARK: - Resize Handles
    
    @ViewBuilder
    private func resizeHandles(rect: CGRect, canvasSize: CGSize) -> some View {
        Group {
            // Corner handles
            resizeHandle(.topLeft, at: CGPoint(x: rect.minX, y: rect.minY))
            resizeHandle(.topRight, at: CGPoint(x: rect.maxX, y: rect.minY))
            resizeHandle(.bottomLeft, at: CGPoint(x: rect.minX, y: rect.maxY))
            resizeHandle(.bottomRight, at: CGPoint(x: rect.maxX, y: rect.maxY))
            
            // Edge handles
            resizeHandle(.top, at: CGPoint(x: rect.midX, y: rect.minY))
            resizeHandle(.bottom, at: CGPoint(x: rect.midX, y: rect.maxY))
            resizeHandle(.left, at: CGPoint(x: rect.minX, y: rect.midY))
            resizeHandle(.right, at: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
    
    @ViewBuilder
    private func resizeHandle(_ handle: ResizeHandle, at point: CGPoint) -> some View {
        Rectangle()
            .fill(Color.white)
            .overlay(
                Rectangle()
                    .stroke(Color.blue, lineWidth: 1)
            )
            .frame(width: handleSize, height: handleSize)
            .position(point)
#if os(macOS)
            .onHover { hovering in
                if hovering {
                    cursorForHandle(handle).set()
                }
            }
#endif
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                            mappingManager.isResizing = true
                            resizeHandle = handle
                            lastMappingPosition = mappingManager.currentMapping.position
                            lastMappingSize = mappingManager.currentMapping.size
                        }
                        
                        handleResize(value.translation, handle: handle, canvasSize: mappingManager.canvasSize)
                    }
                    .onEnded { _ in
                        isResizing = false
                        mappingManager.isResizing = false
                        resizeHandle = .none
                    }
            )
    }
    
    // MARK: - Guidelines
    
    @ViewBuilder
    private func guidelines(in canvasSize: CGSize) -> some View {
        let mapping = mappingManager.currentMapping
        let rect = mappingRectInCanvas(mapping, canvasSize: canvasSize)
        
        Path { path in
            // Center guidelines
            let centerX = canvasSize.width / 2
            let centerY = canvasSize.height / 2
            
            // Vertical center line
            if abs(rect.midX - centerX) < mappingManager.snapThreshold {
                path.move(to: CGPoint(x: centerX, y: 0))
                path.addLine(to: CGPoint(x: centerX, y: canvasSize.height))
            }
            
            // Horizontal center line
            if abs(rect.midY - centerY) < mappingManager.snapThreshold {
                path.move(to: CGPoint(x: 0, y: centerY))
                path.addLine(to: CGPoint(x: canvasSize.width, y: centerY))
            }
            
            // Edge guidelines
            if abs(rect.minX) < mappingManager.snapThreshold {
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: canvasSize.height))
            }
            
            if abs(rect.maxX - canvasSize.width) < mappingManager.snapThreshold {
                path.move(to: CGPoint(x: canvasSize.width, y: 0))
                path.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height))
            }
            
            if abs(rect.minY) < mappingManager.snapThreshold {
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: canvasSize.width, y: 0))
            }
            
            if abs(rect.maxY - canvasSize.height) < mappingManager.snapThreshold {
                path.move(to: CGPoint(x: 0, y: canvasSize.height))
                path.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height))
            }
        }
        .stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
    }
    
    // MARK: - Helper Functions
    
    private func mappingRectInCanvas(_ mapping: OutputMapping, canvasSize: CGSize) -> CGRect {
        return CGRect(
            x: mapping.position.x * canvasSize.width,
            y: mapping.position.y * canvasSize.height,
            width: mapping.size.width * canvasSize.width * mapping.scale,
            height: mapping.size.height * canvasSize.height * mapping.scale
        )
    }
    
    private func updateMappingFromGeometry(_ size: CGSize) {
        if mappingManager.canvasSize != size {
            mappingManager.canvasSize = size
        }
    }
    
    private func cursorForHandle(_ handle: ResizeHandle) -> NSCursor {
        switch handle {
        case .topLeft, .bottomRight:
            return NSCursor.resizeNorthwestSoutheast
        case .topRight, .bottomLeft:
            return NSCursor.resizeNortheastSouthwest
        case .top, .bottom:
            return NSCursor.resizeUpDown
        case .left, .right:
            return NSCursor.resizeLeftRight
        case .none:
            return NSCursor.arrow
        }
    }
    
    private func handleResize(_ translation: CGSize, handle: ResizeHandle, canvasSize: CGSize) {
        var newPosition = lastMappingPosition
        var newSize = lastMappingSize
        
        let deltaX = translation.width / canvasSize.width
        let deltaY = translation.height / canvasSize.height
        
        switch handle {
        case .topLeft:
            newPosition.x = max(0, lastMappingPosition.x + deltaX)
            newPosition.y = max(0, lastMappingPosition.y + deltaY)
            newSize.width = max(0.05, lastMappingSize.width - deltaX)
            newSize.height = max(0.05, lastMappingSize.height - deltaY)
            
        case .topRight:
            newPosition.y = max(0, lastMappingPosition.y + deltaY)
            newSize.width = max(0.05, lastMappingSize.width + deltaX)
            newSize.height = max(0.05, lastMappingSize.height - deltaY)
            
        case .bottomLeft:
            newPosition.x = max(0, lastMappingPosition.x + deltaX)
            newSize.width = max(0.05, lastMappingSize.width - deltaX)
            newSize.height = max(0.05, lastMappingSize.height + deltaY)
            
        case .bottomRight:
            newSize.width = max(0.05, lastMappingSize.width + deltaX)
            newSize.height = max(0.05, lastMappingSize.height + deltaY)
            
        case .top:
            newPosition.y = max(0, lastMappingPosition.y + deltaY)
            newSize.height = max(0.05, lastMappingSize.height - deltaY)
            
        case .bottom:
            newSize.height = max(0.05, lastMappingSize.height + deltaY)
            
        case .left:
            newPosition.x = max(0, lastMappingPosition.x + deltaX)
            newSize.width = max(0.05, lastMappingSize.width - deltaX)
            
        case .right:
            newSize.width = max(0.05, lastMappingSize.width + deltaX)
            
        case .none:
            break
        }
        
        // Maintain aspect ratio if locked
        if mappingManager.currentMapping.aspectRatioLocked {
            let aspectRatio = lastMappingSize.width / lastMappingSize.height
            
            switch handle {
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                // For corner handles, adjust based on the larger dimension change
                if abs(deltaX) > abs(deltaY) {
                    newSize.height = newSize.width / aspectRatio
                } else {
                    newSize.width = newSize.height * aspectRatio
                }
            case .left, .right:
                newSize.height = newSize.width / aspectRatio
            case .top, .bottom:
                newSize.width = newSize.height * aspectRatio
            case .none:
                break
            }
        }
        
        // Ensure bounds stay within canvas
        newPosition.x = max(0, min(1 - newSize.width, newPosition.x))
        newPosition.y = max(0, min(1 - newSize.height, newPosition.y))
        newSize.width = min(1 - newPosition.x, newSize.width)
        newSize.height = min(1 - newPosition.y, newSize.height)
        
        mappingManager.setPosition(newPosition)
        mappingManager.setSize(newSize)
    }
}

// MARK: - NSCursor Extension

extension NSCursor {
    static var resizeNorthwestSoutheast: NSCursor {
        return NSCursor(image: NSImage(systemSymbolName: "arrow.up.left.and.down.right", accessibilityDescription: nil)!, hotSpot: NSPoint(x: 8, y: 8))
    }
    
    static var resizeNortheastSouthwest: NSCursor {
        return NSCursor(image: NSImage(systemSymbolName: "arrow.up.right.and.down.left", accessibilityDescription: nil)!, hotSpot: NSPoint(x: 8, y: 8))
    }
}

// MARK: - Preview

#Preview {
    let manager = OutputMappingManager(metalDevice: MTLCreateSystemDefaultDevice()!)
    return InteractiveOutputCanvas(mappingManager: manager)
        .frame(width: 400, height: 300)
}