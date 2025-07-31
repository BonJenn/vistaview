import SwiftUI

struct OutputMappingPanel: View {
    @ObservedObject var mappingManager: OutputMappingManager
    @State private var showPresetManager = false
    @State private var showExportImport = false
    @State private var newPresetName = ""
    @State private var showNewPresetDialog = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "rectangle.resize")
                    .foregroundColor(.blue)
                Text("Output Mapping")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { showExportImport.toggle() }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export/Import Presets")
                
                Button(action: { mappingManager.hidePanel() }) {
                    Image(systemName: "xmark")
                }
                .help("Close Panel")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Quick Controls
                    quickControlsSection
                    
                    Divider()
                    
                    // Position & Size
                    positionSizeSection
                    
                    Divider()
                    
                    // Scale & Rotation
                    scaleRotationSection
                    
                    Divider()
                    
                    // Presets
                    presetsSection
                    
                    Divider()
                    
                    // Advanced Settings
                    advancedSection
                }
                .padding()
            }
        }
        .frame(width: 350, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 10)
        .sheet(isPresented: $showPresetManager) {
            PresetManagerView(mappingManager: mappingManager)
        }
        .sheet(isPresented: $showExportImport) {
            ExportImportView(mappingManager: mappingManager)
        }
        .alert("Save Current Mapping", isPresented: $showNewPresetDialog) {
            TextField("Preset Name", text: $newPresetName)
            Button("Save") {
                if !newPresetName.isEmpty {
                    mappingManager.saveCurrentAsPreset(name: newPresetName)
                    newPresetName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newPresetName = ""
            }
        } message: {
            Text("Enter a name for this output mapping preset.")
        }
    }
    
    // MARK: - Quick Controls Section
    
    @ViewBuilder
    private var quickControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Controls")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 8) {
                Button("Fit to Screen") {
                    mappingManager.fitToScreen()
                }
                .buttonStyle(.bordered)
                
                Button("Center") {
                    mappingManager.centerOutput()
                }
                .buttonStyle(.bordered)
                
                Button("Reset") {
                    mappingManager.resetMapping()
                }
                .buttonStyle(.bordered)
            }
            
            HStack {
                Toggle("Enable Output Mapping", isOn: $mappingManager.isEnabled)
                    .toggleStyle(.switch)
                
                Spacer()
                
                Text(mappingManager.isEnabled ? "ON" : "OFF")
                    .font(.caption)
                    .foregroundColor(mappingManager.isEnabled ? .green : .red)
                    .fontWeight(.medium)
            }
        }
    }
    
    // MARK: - Position & Size Section
    
    @ViewBuilder
    private var positionSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Position & Size")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: { mappingManager.toggleAspectRatioLock() }) {
                    Image(systemName: mappingManager.currentMapping.aspectRatioLocked ? "lock.fill" : "lock.open")
                        .foregroundColor(mappingManager.currentMapping.aspectRatioLocked ? .blue : .gray)
                }
                .help("Lock Aspect Ratio")
            }
            
            // Position Controls
            HStack {
                Text("X:")
                    .frame(width: 20, alignment: .leading)
                TextField("X", value: Binding(
                    get: { Double(mappingManager.pixelPosition().x) },
                    set: { newValue in
                        let normalizedX = CGFloat(newValue) / mappingManager.canvasSize.width
                        mappingManager.setPosition(CGPoint(
                            x: normalizedX,
                            y: mappingManager.currentMapping.position.y
                        ))
                    }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                
                Text("Y:")
                    .frame(width: 20, alignment: .leading)
                TextField("Y", value: Binding(
                    get: { Double(mappingManager.pixelPosition().y) },
                    set: { newValue in
                        let normalizedY = CGFloat(newValue) / mappingManager.canvasSize.height
                        mappingManager.setPosition(CGPoint(
                            x: mappingManager.currentMapping.position.x,
                            y: normalizedY
                        ))
                    }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
            }
            
            // Size Controls
            HStack {
                Text("W:")
                    .frame(width: 20, alignment: .leading)
                TextField("Width", value: Binding(
                    get: { Double(mappingManager.pixelSize().width) },
                    set: { newValue in
                        let normalizedWidth = CGFloat(newValue) / mappingManager.canvasSize.width
                        let normalizedHeight = mappingManager.currentMapping.aspectRatioLocked ? 
                            normalizedWidth * (mappingManager.currentMapping.size.height / mappingManager.currentMapping.size.width) :
                            mappingManager.currentMapping.size.height
                        
                        mappingManager.setSize(CGSize(
                            width: normalizedWidth,
                            height: normalizedHeight
                        ))
                    }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                
                Text("H:")
                    .frame(width: 20, alignment: .leading)
                TextField("Height", value: Binding(
                    get: { Double(mappingManager.pixelSize().height) },
                    set: { newValue in
                        let normalizedHeight = CGFloat(newValue) / mappingManager.canvasSize.height
                        let normalizedWidth = mappingManager.currentMapping.aspectRatioLocked ? 
                            normalizedHeight * (mappingManager.currentMapping.size.width / mappingManager.currentMapping.size.height) :
                            mappingManager.currentMapping.size.width
                        
                        mappingManager.setSize(CGSize(
                            width: normalizedWidth,
                            height: normalizedHeight
                        ))
                    }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
            }
            
            // Quick Size Buttons
            HStack(spacing: 4) {
                ForEach([("25%", 0.25), ("50%", 0.5), ("75%", 0.75), ("100%", 1.0)], id: \.0) { label, scale in
                    Button(label) {
                        mappingManager.setSize(CGSize(width: scale, height: scale))
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
    }
    
    // MARK: - Scale & Rotation Section
    
    @ViewBuilder
    private var scaleRotationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scale & Rotation")
                .font(.subheadline)
                .fontWeight(.medium)
            
            // Scale Control
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Scale:")
                    Spacer()
                    Text("\(mappingManager.currentMapping.scale, specifier: "%.2f")x")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(
                    value: Binding(
                        get: { mappingManager.currentMapping.scale },
                        set: { mappingManager.setScale($0) }
                    ),
                    in: 0.1...3.0,
                    step: 0.05
                ) {
                    Text("Scale")
                } minimumValueLabel: {
                    Text("0.1x")
                        .font(.caption2)
                } maximumValueLabel: {
                    Text("3.0x")
                        .font(.caption2)
                }
            }
            
            // Rotation Control
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Rotation:")
                    Spacer()
                    Text("\(mappingManager.currentMapping.rotation, specifier: "%.1f")°")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(
                    value: Binding(
                        get: { mappingManager.currentMapping.rotation },
                        set: { mappingManager.setRotation($0) }
                    ),
                    in: -180...180,
                    step: 1.0
                ) {
                    Text("Rotation")
                } minimumValueLabel: {
                    Text("-180°")
                        .font(.caption2)
                } maximumValueLabel: {
                    Text("180°")
                        .font(.caption2)
                }
            }
            
            // Opacity Control
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Opacity:")
                    Spacer()
                    Text("\(mappingManager.currentMapping.opacity, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(
                    value: Binding(
                        get: { mappingManager.currentMapping.opacity },
                        set: { mappingManager.setOpacity($0) }
                    ),
                    in: 0...1,
                    step: 0.01
                ) {
                    Text("Opacity")
                } minimumValueLabel: {
                    Text("0%")
                        .font(.caption2)
                } maximumValueLabel: {
                    Text("100%")
                        .font(.caption2)
                }
            }
        }
    }
    
    // MARK: - Presets Section
    
    @ViewBuilder
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Presets")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: { showNewPresetDialog = true }) {
                    Image(systemName: "plus")
                }
                .help("Save Current as Preset")
                
                Button(action: { showPresetManager = true }) {
                    Image(systemName: "gear")
                }
                .help("Manage Presets")
            }
            
            // Preset Selector
            Menu {
                if mappingManager.presets.isEmpty {
                    Text("No Presets")
                        .disabled(true)
                } else {
                    ForEach(mappingManager.presets) { preset in
                        Button(preset.name) {
                            mappingManager.applyPreset(preset)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(mappingManager.selectedPreset?.name ?? "Select Preset")
                        .foregroundColor(mappingManager.selectedPreset != nil ? .primary : .secondary)
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
        }
    }
    
    // MARK: - Advanced Section
    
    @ViewBuilder
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                Toggle("Snap to Edges", isOn: $mappingManager.snapToEdges)
                    .toggleStyle(.switch)
                
                Spacer()
                
                if mappingManager.snapToEdges {
                    Text("±\(Int(mappingManager.snapThreshold))px")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if mappingManager.snapToEdges {
                Slider(
                    value: $mappingManager.snapThreshold,
                    in: 5...50,
                    step: 5
                ) {
                    Text("Snap Threshold")
                }
            }
            
            Divider()
            
            // Control Integration
            VStack(alignment: .leading, spacing: 4) {
                Text("External Control")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    Toggle("OSC", isOn: $mappingManager.oscEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                    
                    Toggle("MIDI", isOn: $mappingManager.midiEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                    
                    if mappingManager.oscEnabled || mappingManager.midiEnabled {
                        Toggle("Learn", isOn: $mappingManager.learnMode)
                            .toggleStyle(.switch)
                            .scaleEffect(0.8)
                    }
                }
            }
            
            // Status Info
            Text(mappingManager.mappingDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }
}

// MARK: - Preview

#Preview {
    let manager = OutputMappingManager(metalDevice: MTLCreateSystemDefaultDevice()!)
    return OutputMappingPanel(mappingManager: manager)
}