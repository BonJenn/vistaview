//
//  InteractiveOutputMappingCanvas.swift
//  Vantaview
//

import SwiftUI
import AppKit

struct InteractiveOutputMappingCanvas: View {
    @ObservedObject var outputMappingManager: OutputMappingManager
    @ObservedObject var productionManager: UnifiedProductionManager
    
    @State private var isDragging = false
    @State private var isResizing = false
    @State private var dragOffset = CGSize.zero
    @State private var resizeHandle: ResizeHandle?
    
    private var mapping: OutputMapping {
        outputMappingManager.currentMapping
    }
    
    private var canvasSize: CGSize {
        outputMappingManager.canvasSize
    }
    
    enum ResizeHandle: String, CaseIterable {
        case topLeft = "TL"
        case topRight = "TR" 
        case bottomLeft = "BL"
        case bottomRight = "BR"
        case top = "T"
        case bottom = "B"
        case left = "L"
        case right = "R"
        
        var cursor: NSCursor {
            switch self {
            case .topLeft, .topRight, .bottomLeft, .bottomRight: return .crosshair
            case .top, .bottom: return .resizeUpDown
            case .left, .right: return .resizeLeftRight
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with grid
                if outputMappingManager.showGrid {
                    GridOverlay(size: geometry.size, opacity: outputMappingManager.gridOpacity)
                }
                
                // Live preview of current program source
                if outputMappingManager.livePreviewEnabled {
                    LivePreviewLayer(
                        productionManager: productionManager,
                        geometry: geometry,
                        mapping: mapping,
                        opacity: outputMappingManager.previewOpacity
                    )
                }
                
                // Transform box visualization
                TransformBox(
                    mapping: mapping,
                    geometry: geometry,
                    isDragging: $isDragging,
                    isResizing: $isResizing,
                    dragOffset: $dragOffset,
                    resizeHandle: $resizeHandle,
                    outputMappingManager: outputMappingManager
                )
                
                // Real-time info overlay
                VStack {
                    HStack {
                        InfoPill(
                            title: "Position",
                            value: "\(Int(mapping.position.x * canvasSize.width)), \(Int(mapping.position.y * canvasSize.height))",
                            color: .blue
                        )
                        
                        InfoPill(
                            title: "Size",
                            value: "\(Int(mapping.scaledSize.width * canvasSize.width))×\(Int(mapping.scaledSize.height * canvasSize.height))",
                            color: .green
                        )
                        
                        Spacer()
                        
                        if isDragging || isResizing {
                            InfoPill(
                                title: "Live Edit",
                                value: "Active",
                                color: .orange
                            )
                        }
                    }
                    .padding(12)
                    
                    Spacer()
                }
            }
        }
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

struct LivePreviewLayer: View {
    @ObservedObject var productionManager: UnifiedProductionManager
    let geometry: GeometryProxy
    let mapping: OutputMapping
    let opacity: CGFloat
    
    var body: some View {
        Group {
            switch productionManager.previewProgramManager.programSource {
            case .camera(let feed):
                if let nsImage = feed.previewNSImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(.gray)
                        .overlay(
                            Text("Loading Camera...")
                                .foregroundColor(.white)
                        )
                }
                
            case .media(let mediaFile, _):
                if mediaFile.fileType == .image {
                    AsyncImage(url: mediaFile.url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                } else {
                    Rectangle()
                        .fill(.purple.opacity(0.3))
                        .overlay(
                            VStack {
                                Image(systemName: "play.circle")
                                    .font(.largeTitle)
                                Text(mediaFile.name)
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                        )
                }
                
            case .virtual(let camera):
                Rectangle()
                    .fill(.teal.opacity(0.3))
                    .overlay(
                        VStack {
                            Image(systemName: "video.3d")
                                .font(.largeTitle)
                            Text(camera.name)
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    )
                
            case .none:
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .overlay(
                        Text("No Source")
                            .foregroundColor(.white)
                    )
            }
        }
        .opacity(opacity)
        .frame(
            width: mapping.scaledSize.width * geometry.size.width,
            height: mapping.scaledSize.height * geometry.size.height,
            alignment: .center
        )
        .position(
            x: (mapping.position.x + mapping.scaledSize.width / 2) * geometry.size.width,
            y: (mapping.position.y + mapping.scaledSize.height / 2) * geometry.size.height
        )
        .rotationEffect(.degrees(Double(mapping.rotation)), anchor: .center)
    }
}

struct TransformBox: View {
    let mapping: OutputMapping
    let geometry: GeometryProxy
    @Binding var isDragging: Bool
    @Binding var isResizing: Bool
    @Binding var dragOffset: CGSize
    @Binding var resizeHandle: InteractiveOutputMappingCanvas.ResizeHandle?
    @ObservedObject var outputMappingManager: OutputMappingManager
    
    private var boxFrame: CGRect {
        CGRect(
            x: mapping.position.x * geometry.size.width,
            y: mapping.position.y * geometry.size.height,
            width: mapping.scaledSize.width * geometry.size.width,
            height: mapping.scaledSize.height * geometry.size.height
        )
    }
    
    var body: some View {
        ZStack {
            // Main bounding box
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    Rectangle()
                        .stroke(outputMappingManager.boundsColor, lineWidth: isDragging ? 3 : 2)
                        .background(
                            Rectangle()
                                .fill(outputMappingManager.boundsColor.opacity(isDragging ? 0.1 : 0.05))
                        )
                )
                .frame(width: boxFrame.width, height: boxFrame.height)
                .position(
                    x: boxFrame.midX,
                    y: boxFrame.midY
                )
                .opacity(outputMappingManager.showBounds ? 1 : 0)
            
            // Resize handles
            if outputMappingManager.showGizmo {
                ForEach(InteractiveOutputMappingCanvas.ResizeHandle.allCases, id: \.rawValue) { handle in
                    ResizeHandleView(
                        handle: handle,
                        boxFrame: boxFrame,
                        geometry: geometry,
                        isActive: resizeHandle == handle,
                        outputMappingManager: outputMappingManager
                    )
                }
            }
            
            // Center cross
            if outputMappingManager.showCenterCross {
                Path { path in
                    let center = CGPoint(x: boxFrame.midX, y: boxFrame.midY)
                    path.move(to: CGPoint(x: center.x - 10, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + 10, y: center.y))
                    path.move(to: CGPoint(x: center.x, y: center.y - 10))
                    path.addLine(to: CGPoint(x: center.x, y: center.y + 10))
                }
                .stroke(Color.white, lineWidth: 2)
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging && !isResizing {
                        isDragging = true
                        dragOffset = value.translation
                    }
                    
                    if isDragging {
                        let normalizedDelta = CGSize(
                            width: value.translation.width / geometry.size.width,
                            height: value.translation.height / geometry.size.height
                        )
                        
                        let live = outputMappingManager.currentMapping
                        outputMappingManager.setPosition(CGPoint(
                            x: live.position.x + normalizedDelta.width,
                            y: live.position.y + normalizedDelta.height
                        ))
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    dragOffset = .zero
                }
        )
    }
}

struct ResizeHandleView: View {
    let handle: InteractiveOutputMappingCanvas.ResizeHandle
    let boxFrame: CGRect
    let geometry: GeometryProxy
    let isActive: Bool
    @ObservedObject var outputMappingManager: OutputMappingManager
    
    private var handlePosition: CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: boxFrame.minX, y: boxFrame.minY)
        case .topRight: return CGPoint(x: boxFrame.maxX, y: boxFrame.minY)
        case .bottomLeft: return CGPoint(x: boxFrame.minX, y: boxFrame.maxY)
        case .bottomRight: return CGPoint(x: boxFrame.maxX, y: boxFrame.maxY)
        case .top: return CGPoint(x: boxFrame.midX, y: boxFrame.minY)
        case .bottom: return CGPoint(x: boxFrame.midX, y: boxFrame.maxY)
        case .left: return CGPoint(x: boxFrame.minX, y: boxFrame.midY)
        case .right: return CGPoint(x: boxFrame.maxX, y: boxFrame.midY)
        }
    }
    
    var body: some View {
        Circle()
            .fill(isActive ? Color.orange : Color.white)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.black, lineWidth: 1)
            )
            .position(handlePosition)
            .cursor(handle.cursor)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        handleResize(handle, value)
                    }
            )
    }
    
    private func handleResize(_ handle: InteractiveOutputMappingCanvas.ResizeHandle, _ value: DragGesture.Value) {
        let deltaX = value.translation.width / geometry.size.width
        let deltaY = value.translation.height / geometry.size.height
        
        let mapping = outputMappingManager.currentMapping
        
        switch handle {
        case .topLeft:
            outputMappingManager.setPosition(CGPoint(
                x: mapping.position.x + deltaX,
                y: mapping.position.y + deltaY
            ))
            outputMappingManager.setSize(CGSize(
                width: mapping.size.width - deltaX,
                height: mapping.size.height - deltaY
            ))
            
        case .bottomRight:
            outputMappingManager.setSize(CGSize(
                width: mapping.size.width + deltaX,
                height: mapping.size.height + deltaY
            ))
            
        case .right:
            outputMappingManager.setWidth(mapping.size.width + deltaX)
            
        case .bottom:
            outputMappingManager.setHeight(mapping.size.height + deltaY)
            
        // Add other handles as needed
        default:
            break
        }
    }
}

struct GridOverlay: View {
    let size: CGSize
    let opacity: CGFloat
    
    var body: some View {
        Canvas { context, _ in
            let gridSpacing: CGFloat = 50
            
            // Vertical lines
            for x in stride(from: 0, through: size.width, by: gridSpacing) {
                let line = Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(line, with: .color(.white.opacity(opacity)), lineWidth: 0.5)
            }
            
            // Horizontal lines
            for y in stride(from: 0, through: size.height, by: gridSpacing) {
                let line = Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(line, with: .color(.white.opacity(opacity)), lineWidth: 0.5)
            }
        }
    }
}

struct InfoPill: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.5), lineWidth: 1)
        )
    }
}