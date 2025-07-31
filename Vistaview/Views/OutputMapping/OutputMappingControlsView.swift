import SwiftUI

struct OutputMappingControlsView: View {
    @ObservedObject var outputMappingManager: OutputMappingManager
    @ObservedObject var externalDisplayManager: ExternalDisplayManager
    @State private var showMappingPanel = false
    @State private var showInteractiveCanvas = false
    
    var body: some View {
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
            
            // Quick Controls
            VStack(spacing: 12) {
                // Enable/Disable Toggle
                HStack {
                    Toggle("Enable Output Mapping", isOn: $outputMappingManager.isEnabled)
                        .toggleStyle(.switch)
                    
                    Spacer()
                }
                
                if outputMappingManager.isEnabled {
                    // Current Mapping Status
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Current Mapping:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if let preset = outputMappingManager.selectedPreset {
                                Text(preset.name)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            } else {
                                Text("Custom")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Text(outputMappingManager.mappingDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    // Quick Action Buttons
                    HStack(spacing: 8) {
                        Button("Fit Screen") {
                            outputMappingManager.fitToScreen()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        
                        Button("Center") {
                            outputMappingManager.centerOutput()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        
                        Button("Reset") {
                            outputMappingManager.resetMapping()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    
                    // External Display Controls
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "tv")
                                .foregroundColor(.purple)
                            Text("External Display")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            if externalDisplayManager.isFullScreenActive {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("ACTIVE")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        if !externalDisplayManager.availableDisplays.isEmpty {
                            Menu {
                                ForEach(externalDisplayManager.availableDisplays.filter { !$0.isMain }) { display in
                                    Button(display.name) {
                                        if externalDisplayManager.isFullScreenActive {
                                            externalDisplayManager.stopFullScreenOutput()
                                        } else {
                                            externalDisplayManager.startFullScreenOutput(on: display)
                                        }
                                    }
                                }
                                
                                if externalDisplayManager.isFullScreenActive {
                                    Divider()
                                    Button("Stop External Output") {
                                        externalDisplayManager.stopFullScreenOutput()
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(externalDisplayManager.selectedDisplay?.name ?? "Select Display")
                                        .foregroundColor(externalDisplayManager.selectedDisplay != nil ? .primary : .secondary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                            }
                            .menuStyle(.borderlessButton)
                        } else {
                            Text("No external displays detected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Preset Selector
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Presets:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Menu {
                            if outputMappingManager.presets.isEmpty {
                                Text("No Presets")
                                    .disabled(true)
                            } else {
                                ForEach(outputMappingManager.presets) { preset in
                                    Button(preset.name) {
                                        outputMappingManager.applyPreset(preset)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button("Save Current as Preset...") {
                                // This will be handled by the main panel
                                showMappingPanel = true
                            }
                        } label: {
                            HStack {
                                Text(outputMappingManager.selectedPreset?.name ?? "Select Preset")
                                    .foregroundColor(outputMappingManager.selectedPreset != nil ? .primary : .secondary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .menuStyle(.borderlessButton)
                    }
                    
                    Divider()
                    
                    // Panel Access Buttons
                    VStack(spacing: 8) {
                        Button(action: { showMappingPanel.toggle() }) {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text("Detailed Controls")
                                Spacer()
                                Image(systemName: showMappingPanel ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { showInteractiveCanvas.toggle() }) {
                            HStack {
                                Image(systemName: "viewfinder")
                                Text("Visual Editor")
                                Spacer()
                                Image(systemName: showInteractiveCanvas ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Spacer()
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