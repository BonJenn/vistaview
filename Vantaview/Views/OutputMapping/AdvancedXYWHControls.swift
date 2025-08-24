//
//  AdvancedXYWHControls.swift
//  Vantaview
//

import SwiftUI
import AppKit

struct AdvancedXYWHControls: View {
    @ObservedObject var outputMappingManager: OutputMappingManager
    
    @State private var isShiftPressed = false
    @State private var hoveredParameter: MappingParameter?
    
    private var currentMapping: OutputMapping {
        outputMappingManager.currentMapping
    }
    
    private var canvasSize: CGSize {
        outputMappingManager.canvasSize
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Transform")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    outputMappingManager.precisionMode.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "scope")
                        Text(outputMappingManager.precisionMode ? "PREC" : "NORM")
                    }
                    .font(.caption2)
                    .foregroundColor(outputMappingManager.precisionMode ? .orange : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle precision mode (Shift key)")
            }
            
            VStack(spacing: 8) {
                // Position Controls
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("X")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrubbableValueField(
                            value: Binding(
                                get: { currentMapping.position.x * canvasSize.width },
                                set: { outputMappingManager.setPositionX($0 / canvasSize.width) }
                            ),
                            range: 0...(canvasSize.width - currentMapping.size.width * canvasSize.width),
                            format: "%.0f",
                            suffix: "px",
                            color: .blue,
                            isActive: outputMappingManager.isScrubbingX,
                            onScrubStart: {
                                outputMappingManager.startScrubbing(for: .positionX, initialValue: currentMapping.position.x)
                            },
                            onScrubEnd: {
                                outputMappingManager.stopScrubbing()
                            }
                        )
                        .onHover { isHovering in
                            hoveredParameter = isHovering ? .positionX : nil
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Y")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrubbableValueField(
                            value: Binding(
                                get: { currentMapping.position.y * canvasSize.height },
                                set: { outputMappingManager.setPositionY($0 / canvasSize.height) }
                            ),
                            range: 0...(canvasSize.height - currentMapping.size.height * canvasSize.height),
                            format: "%.0f",
                            suffix: "px",
                            color: .green,
                            isActive: outputMappingManager.isScrubbingY,
                            onScrubStart: {
                                outputMappingManager.startScrubbing(for: .positionY, initialValue: currentMapping.position.y)
                            },
                            onScrubEnd: {
                                outputMappingManager.stopScrubbing()
                            }
                        )
                        .onHover { isHovering in
                            hoveredParameter = isHovering ? .positionY : nil
                        }
                    }
                }
                
                // Size Controls
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("W")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrubbableValueField(
                            value: Binding(
                                get: { currentMapping.size.width * canvasSize.width },
                                set: { outputMappingManager.setWidth($0 / canvasSize.width) }
                            ),
                            range: 10...(canvasSize.width - currentMapping.position.x * canvasSize.width),
                            format: "%.0f",
                            suffix: "px",
                            color: .purple,
                            isActive: outputMappingManager.isScrubbingW,
                            onScrubStart: {
                                outputMappingManager.startScrubbing(for: .width, initialValue: currentMapping.size.width)
                            },
                            onScrubEnd: {
                                outputMappingManager.stopScrubbing()
                            }
                        )
                        .onHover { isHovering in
                            hoveredParameter = isHovering ? .width : nil
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("H")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrubbableValueField(
                            value: Binding(
                                get: { currentMapping.size.height * canvasSize.height },
                                set: { outputMappingManager.setHeight($0 / canvasSize.height) }
                            ),
                            range: 10...(canvasSize.height - currentMapping.position.y * canvasSize.height),
                            format: "%.0f",
                            suffix: "px",
                            color: .orange,
                            isActive: outputMappingManager.isScrubbingH,
                            onScrubStart: {
                                outputMappingManager.startScrubbing(for: .height, initialValue: currentMapping.size.height)
                            },
                            onScrubEnd: {
                                outputMappingManager.stopScrubbing()
                            }
                        )
                        .onHover { isHovering in
                            hoveredParameter = isHovering ? .height : nil
                        }
                    }
                    
                    // Aspect Ratio Lock
                    Button(action: {
                        outputMappingManager.currentMapping.aspectRatioLocked.toggle()
                        outputMappingManager.objectWillChange.send()
                    }) {
                        Image(systemName: outputMappingManager.currentMapping.aspectRatioLocked ? "link" : "link.slash")
                            .foregroundColor(outputMappingManager.currentMapping.aspectRatioLocked ? .blue : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Lock aspect ratio")
                }
                
                // Quick Action Buttons
                HStack(spacing: 8) {
                    Button("Center") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            outputMappingManager.centerOutput()
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    
                    Button("Fit") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            outputMappingManager.fitToScreen()
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    
                    Button("Reset") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            outputMappingManager.resetMapping()
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                
                // Advanced Controls
                VStack(spacing: 6) {
                    HStack {
                        Text("Scale")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)
                        
                        Slider(
                            value: Binding(
                                get: { outputMappingManager.currentMapping.scale },
                                set: { outputMappingManager.setScale($0) }
                            ),
                            in: 0.1...3.0
                        )
                        .accentColor(.pink)
                        
                        Text("\(Int(outputMappingManager.currentMapping.scale * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                    
                    HStack {
                        Text("Opacity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)
                        
                        Slider(
                            value: Binding(
                                get: { outputMappingManager.currentMapping.opacity },
                                set: { outputMappingManager.setOpacity($0) }
                            ),
                            in: 0...1
                        )
                        .accentColor(.cyan)
                        
                        Text("\(Int(outputMappingManager.currentMapping.opacity * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                }
            }
            
            // Status Info
            if let hoveredParam = hoveredParameter {
                HStack {
                    Text("Hover to scrub \(hoveredParam.rawValue)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Spacer()
                    Text("Shift = Precision")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .onAppear {
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                updateModifierKeys()
                return event
            }
        }
        .onDisappear {
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
        }
    }
    
    @State private var flagsMonitor: Any?
    
    private func updateModifierKeys() {
        let modifiers = NSEvent.modifierFlags
        let shiftPressed = modifiers.contains(.shift)
        
        if shiftPressed != isShiftPressed {
            isShiftPressed = shiftPressed
            outputMappingManager.setPrecisionMode(shiftPressed)
        }
    }
}

struct ScrubbableValueField: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: String
    let suffix: String
    let color: Color
    let isActive: Bool
    let onScrubStart: () -> Void
    let onScrubEnd: () -> Void
    
    @State private var isDragging = false
    @State private var dragStartX: CGFloat = 0
    @State private var dragStartValue: CGFloat = 0
    @State private var isEditing = false
    @State private var editText = ""
    
    var body: some View {
        HStack(spacing: 4) {
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 60)
                    .onSubmit {
                        if let parsed = Double(editText) {
                            let newValue = CGFloat(parsed)
                            value = max(range.lowerBound, min(range.upperBound, newValue))
                        }
                        isEditing = false
                    }
                    .onExitCommand {
                        isEditing = false
                    }
            } else {
                Text(String(format: format, value) + suffix)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(isActive ? color : .primary)
                    .frame(width: 60, alignment: .trailing)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isActive ? color.opacity(0.2) : Color.gray.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isActive ? color : Color.clear, lineWidth: 1)
                            )
                    )
                    .scaleEffect(isDragging ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isDragging)
            }
        }
        .cursor(isDragging ? .resizeLeftRight : .pointingHand)
        .onTapGesture(count: 2) {
            // Double-click to edit
            editText = String(format: "%.0f", value)
            isEditing = true
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { dragValue in
                    if !isDragging {
                        isDragging = true
                        dragStartX = dragValue.startLocation.x
                        dragStartValue = value
                        onScrubStart()
                    }
                    
                    let deltaX = dragValue.location.x - dragStartX
                    let sensitivity: CGFloat = NSEvent.modifierFlags.contains(.shift) ? 0.2 : 1.0
                    let newValue = dragStartValue + deltaX * sensitivity
                    
                    value = max(range.lowerBound, min(range.upperBound, newValue))
                }
                .onEnded { _ in
                    isDragging = false
                    onScrubEnd()
                }
        )
    }
}

// Custom cursor extension
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { isHovering in
            if isHovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}