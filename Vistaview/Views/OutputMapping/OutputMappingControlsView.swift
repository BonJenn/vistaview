import SwiftUI

struct OutputMappingControlsView: View {
    @ObservedObject var outputMappingManager: OutputMappingManager
    @ObservedObject var externalDisplayManager: ExternalDisplayManager
    @State private var showMappingPanel = false
    @State private var showInteractiveCanvas = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "rectangle.resize")
                        .foregroundColor(.blue)
                    Text("Output Mapping")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Status indicator
                    Circle()
                        .fill(outputMappingManager.isEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    
                    Text(outputMappingManager.isEnabled ? "ON" : "OFF")
                        .font(.caption2)
                        .foregroundColor(outputMappingManager.isEnabled ? .green : .gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Scrollable Content
                VStack(spacing: 10) {
                    // Enable/Disable Toggle
                    HStack {
                        Toggle("Enable Output Mapping", isOn: $outputMappingManager.isEnabled)
                            .toggleStyle(.switch)
                        
                        Spacer()
                    }
                    
                    if outputMappingManager.isEnabled {
                        // Current Mapping Status (Compact)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Mapping:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if let preset = outputMappingManager.selectedPreset {
                                    Text(preset.name)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(3)
                                } else {
                                    Text("Custom")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        // Quick Action Buttons (Compact)
                        HStack(spacing: 6) {
                            Button("Fit") {
                                outputMappingManager.fitToScreen()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption2)
                            
                            Button("Center") {
                                outputMappingManager.centerOutput()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption2)
                            
                            Button("Reset") {
                                outputMappingManager.resetMapping()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption2)
                        }
                        
                        Divider()
                        
                        // External Display Controls (Compact)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "tv")
                                    .foregroundColor(.purple)
                                    .font(.caption)
                                Text("External Display")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                // Status indicator
                                HStack(spacing: 2) {
                                    Circle()
                                        .fill(externalDisplayManager.isFullScreenActive ? Color.green : Color.gray)
                                        .frame(width: 4, height: 4)
                                    Text(externalDisplayManager.isFullScreenActive ? "ON" : "OFF")
                                        .font(.caption2)
                                        .foregroundColor(externalDisplayManager.isFullScreenActive ? .green : .gray)
                                }
                            }
                            
                            // Display selector (Compact)
                            if !externalDisplayManager.availableDisplays.isEmpty {
                                Menu {
                                    ForEach(externalDisplayManager.getExternalDisplays()) { display in
                                        Button(action: {
                                            if externalDisplayManager.selectedDisplay?.id == display.id && externalDisplayManager.isFullScreenActive {
                                                externalDisplayManager.stopFullScreenOutput()
                                            } else {
                                                externalDisplayManager.startFullScreenOutput(on: display)
                                            }
                                        }) {
                                            HStack {
                                                Text(display.name)
                                                Spacer()
                                                Text(display.displayDescription)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(externalDisplayManager.selectedDisplay?.name ?? "Select Display")
                                            .font(.caption)
                                            .foregroundColor(externalDisplayManager.selectedDisplay != nil ? .primary : .secondary)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(4)
                                }
                                .menuStyle(.borderlessButton)
                                .disabled(externalDisplayManager.getExternalDisplays().isEmpty)
                                
                                // Control buttons (Compact)
                                if externalDisplayManager.isFullScreenActive {
                                    HStack(spacing: 6) {
                                        Button("Full Screen") {
                                            externalDisplayManager.toggleFullScreen()
                                        }
                                        .buttonStyle(.bordered)
                                        .font(.caption2)
                                        
                                        Button("Stop") {
                                            externalDisplayManager.stopFullScreenOutput()
                                        }
                                        .buttonStyle(.bordered)
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                    }
                                }
                            } else {
                                Text("No external displays")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        // Tool Access Buttons (Compact)
                        VStack(spacing: 6) {
                            Button(action: { showMappingPanel.toggle() }) {
                                HStack {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.caption)
                                    Text("Detailed Controls")
                                        .font(.caption)
                                    Spacer()
                                    Image(systemName: showMappingPanel ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: { showInteractiveCanvas.toggle() }) {
                                HStack {
                                    Image(systemName: "viewfinder")
                                        .font(.caption)
                                    Text("Visual Editor")
                                        .font(.caption)
                                    Spacer()
                                    Image(systemName: showInteractiveCanvas ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .popover(isPresented: $showMappingPanel, arrowEdge: .trailing) {
            OutputMappingPanel(mappingManager: outputMappingManager)
        }
        .popover(isPresented: $showInteractiveCanvas, arrowEdge: .trailing) {
            VStack {
                HStack {
                    Text("Interactive Output Canvas")
                        .font(.headline)
                    Spacer()
                    Button("Close") {
                        showInteractiveCanvas = false
                    }
                }
                .padding()
                
                InteractiveOutputCanvas(mappingManager: outputMappingManager)
                    .frame(width: 600, height: 400)
                    .padding()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let manager = OutputMappingManager(metalDevice: MTLCreateSystemDefaultDevice()!)
    let externalManager = ExternalDisplayManager()
    OutputMappingControlsView(
        outputMappingManager: manager,
        externalDisplayManager: externalManager
    )
}