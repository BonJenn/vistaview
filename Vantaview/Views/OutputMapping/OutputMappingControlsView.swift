import SwiftUI

struct OutputMappingControlsView: View {
    @ObservedObject var outputMappingManager: OutputMappingManager
    @ObservedObject var externalDisplayManager: ExternalDisplayManager
    @ObservedObject var productionManager: UnifiedProductionManager
    
    @State private var showTransform = true
    @State private var showVisualEditor = true
    @State private var showExternalDisplay = true
    @State private var showPerformance = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Output Mapping")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    outputMappingManager.isEnabled.toggle()
                }) {
                    Image(systemName: outputMappingManager.isEnabled ? "eye" : "eye.slash")
                        .foregroundColor(outputMappingManager.isEnabled ? .green : .red)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle output mapping")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 12) {
                    DisclosureGroup(isExpanded: $showTransform) {
                        AdvancedXYWHControls(outputMappingManager: outputMappingManager)
                            .padding(.top, 8)
                    } label: {
                        Label("Transform Controls", systemImage: "slider.horizontal.3")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal)
                    
                    DisclosureGroup(isExpanded: $showVisualEditor) {
                        VStack(spacing: 8) {
                            HStack {
                                Toggle("Live Preview", isOn: $outputMappingManager.livePreviewEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                                
                                Spacer()
                                
                                Toggle("Grid", isOn: $outputMappingManager.showGrid)
                                    .toggleStyle(SwitchToggleStyle(tint: .gray))
                                
                                Toggle("Gizmo", isOn: $outputMappingManager.showGizmo)
                                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                            }
                            .font(.caption)
                            
                            InteractiveOutputMappingCanvas(
                                outputMappingManager: outputMappingManager,
                                productionManager: productionManager
                            )
                            .frame(height: 200)
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("Visual Editor", systemImage: "square.dashed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal)
                    
                    DisclosureGroup(isExpanded: $showExternalDisplay) {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: externalDisplayManager.isFullScreenActive ? "tv.fill" : "tv")
                                    .foregroundColor(externalDisplayManager.isFullScreenActive ? .green : .gray)
                                
                                Text(externalDisplayManager.isFullScreenActive ? "Live Output Active" : "No Output")
                                    .font(.caption)
                                
                                Spacer()
                                
                                if let display = externalDisplayManager.selectedDisplay {
                                    Text(display.displayDescription)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if !externalDisplayManager.isFullScreenActive {
                                Button("Start External Output") {
                                    if let firstExternal = externalDisplayManager.getExternalDisplays().first {
                                        externalDisplayManager.startFullScreenOutput(on: firstExternal)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(externalDisplayManager.getExternalDisplays().isEmpty)
                            } else {
                                Button("Stop Output") {
                                    externalDisplayManager.stopFullScreenOutput()
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("External Display", systemImage: "rectangle.on.rectangle")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal)
                    
                    DisclosureGroup(isExpanded: $showPerformance) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Update Rate:")
                                Spacer()
                                Text("120 FPS")
                                    .foregroundColor(.green)
                            }
                            .font(.caption2)
                            
                            HStack {
                                Text("Processing:")
                                Spacer()
                                Text(outputMappingManager.hasSignificantMapping ? "GPU Active" : "Bypassed")
                                    .foregroundColor(outputMappingManager.hasSignificantMapping ? .orange : .gray)
                            }
                            .font(.caption2)
                            
                            HStack {
                                Text("Live Preview:")
                                Spacer()
                                Text(outputMappingManager.livePreviewEnabled ? "On" : "Off")
                                    .foregroundColor(outputMappingManager.livePreviewEnabled ? .green : .gray)
                            }
                            .font(.caption2)
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("Performance", systemImage: "speedometer")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let manager = OutputMappingManager(metalDevice: MTLCreateSystemDefaultDevice()!)
    let externalManager = ExternalDisplayManager()
    let production = UnifiedProductionManager()
    OutputMappingControlsView(
        outputMappingManager: manager,
        externalDisplayManager: externalManager,
        productionManager: production
    )
}