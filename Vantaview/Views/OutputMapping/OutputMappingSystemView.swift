import SwiftUI

struct OutputMappingSystemView: View {
    @ObservedObject var outputMappingManager: OutputMappingManager
    @State private var showAdvancedControls = false
    @State private var showControllerSettings = false
    @State private var showHotkeyList = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with status
            headerView
            
            Divider()
            
            // Main content
            ScrollView {
                VStack(spacing: 16) {
                    // Output mapping controls
                    outputMappingSection
                    
                    // Control integration section
                    if showAdvancedControls {
                        controlIntegrationSection
                    }
                    
                    // Preset management
                    presetManagementSection
                    
                    // System status
                    systemStatusSection
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 600)
        .sheet(isPresented: $showControllerSettings) {
            ControllerSettingsView(
                oscController: outputMappingManager.oscController,
                midiController: outputMappingManager.midiController,
                hotkeyController: outputMappingManager.hotkeyController
            )
        }
        .sheet(isPresented: $showHotkeyList) {
            HotkeyListView(hotkeyController: outputMappingManager.hotkeyController)
        }
    }
    
    // MARK: - Header View
    
    @ViewBuilder
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "rectangle.resize")
                        .foregroundColor(.blue)
                    Text("Output Mapping System")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Text(outputMappingManager.mappingDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // System status indicators
            HStack(spacing: 8) {
                StatusIndicator(
                    icon: "rectangle.resize",
                    isActive: outputMappingManager.isEnabled,
                    label: "Mapping"
                )
                
                StatusIndicator(
                    icon: "network",
                    isActive: outputMappingManager.oscController.isConnected,
                    label: "OSC"
                )
                
                StatusIndicator(
                    icon: "pianokeys",
                    isActive: outputMappingManager.midiController.isConnected,
                    label: "MIDI"
                )
                
                StatusIndicator(
                    icon: "keyboard",
                    isActive: outputMappingManager.hotkeyController.isEnabled,
                    label: "Keys"
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Output Mapping Section
    
    @ViewBuilder
    private var outputMappingSection: some View {
        GroupBox("Output Mapping") {
            VStack(alignment: .leading, spacing: 12) {
                // Enable/disable toggle
                HStack {
                    Toggle("Enable Output Mapping", isOn: $outputMappingManager.isEnabled)
                        .toggleStyle(.switch)
                    
                    Spacer()
                    
                    Button("Show Advanced") {
                        showAdvancedControls.toggle()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                }
                
                if outputMappingManager.isEnabled {
                    // Quick controls
                    HStack(spacing: 8) {
                        Button("Fit Screen") {
                            outputMappingManager.fitToScreen()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Center") {
                            outputMappingManager.centerOutput()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Reset") {
                            outputMappingManager.resetMapping()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Visual Editor") {
                            outputMappingManager.showMappingPanel = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    // Current mapping display
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Position: \(Int(outputMappingManager.pixelPosition().x)), \(Int(outputMappingManager.pixelPosition().y))")
                                .font(.caption)
                            Text("Size: \(Int(outputMappingManager.pixelSize().width))×\(Int(outputMappingManager.pixelSize().height))")
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Scale: \(outputMappingManager.currentMapping.scale, specifier: "%.2f")x")
                                .font(.caption)
                            Text("Rotation: \(outputMappingManager.currentMapping.rotation, specifier: "%.1f")°")
                                .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                    .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Control Integration Section
    
    @ViewBuilder
    private var controlIntegrationSection: some View {
        GroupBox("External Control") {
            VStack(alignment: .leading, spacing: 12) {
                // OSC Control
                HStack {
                    Toggle("OSC Control", isOn: $outputMappingManager.oscEnabled)
                        .toggleStyle(.switch)
                    
                    if outputMappingManager.oscEnabled {
                        Text("Port: \(outputMappingManager.oscController.port)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if outputMappingManager.oscController.isConnected {
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                // MIDI Control
                HStack {
                    Toggle("MIDI Control", isOn: $outputMappingManager.midiEnabled)
                        .toggleStyle(.switch)
                    
                    if outputMappingManager.midiEnabled {
                        if let device = outputMappingManager.midiController.selectedDevice {
                            Text(device.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(outputMappingManager.midiController.availableDevices.count) devices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                // Hotkeys
                HStack {
                    Toggle("Hotkeys", isOn: $outputMappingManager.hotkeyEnabled)
                        .toggleStyle(.switch)
                    
                    if outputMappingManager.hotkeyEnabled {
                        Text("\(outputMappingManager.hotkeyController.registeredHotkeys.count) shortcuts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("View Shortcuts") {
                        showHotkeyList = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                
                // Learn Mode
                if outputMappingManager.oscEnabled || outputMappingManager.midiEnabled {
                    HStack {
                        Toggle("Learn Mode", isOn: $outputMappingManager.learnMode)
                            .toggleStyle(.switch)
                        
                        Text("Map hardware controls to parameters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
                
                // Controller Settings
                HStack {
                    Spacer()
                    Button("Controller Settings") {
                        showControllerSettings = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    // MARK: - Preset Management Section
    
    @ViewBuilder
    private var presetManagementSection: some View {
        GroupBox("Presets") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Current Preset:")
                        .font(.subheadline)
                    
                    if let preset = outputMappingManager.selectedPreset {
                        Text(preset.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    } else {
                        Text("Custom")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                }
                
                // Preset quick selector
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(Array(outputMappingManager.presets.prefix(6))) { preset in
                        Button(preset.name) {
                            outputMappingManager.applyPreset(preset)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
                
                if outputMappingManager.presets.count > 6 {
                    Text("+ \(outputMappingManager.presets.count - 6) more presets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                
                HStack {
                    Button("Manage Presets") {
                        // Open preset manager
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Save Current") {
                        // Save current mapping as preset
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    // MARK: - System Status Section
    
    @ViewBuilder
    private var systemStatusSection: some View {
        GroupBox("System Status") {
            VStack(alignment: .leading, spacing: 8) {
                StatusRow(
                    label: "Output Resolution",
                    value: "\(Int(outputMappingManager.canvasSize.width))×\(Int(outputMappingManager.canvasSize.height))",
                    status: .info
                )
                
                StatusRow(
                    label: "Metal Device",
                    value: outputMappingManager.metalDevice.name,
                    status: .success
                )
                
                StatusRow(
                    label: "Snap to Edges",
                    value: outputMappingManager.snapToEdges ? "±\(Int(outputMappingManager.snapThreshold))px" : "Off",
                    status: outputMappingManager.snapToEdges ? .success : .neutral
                )
                
                if outputMappingManager.oscEnabled {
                    StatusRow(
                        label: "OSC Port",
                        value: "\(outputMappingManager.oscController.port)",
                        status: outputMappingManager.oscController.isConnected ? .success : .warning
                    )
                }
                
                if outputMappingManager.midiEnabled {
                    StatusRow(
                        label: "MIDI Devices",
                        value: "\(outputMappingManager.midiController.availableDevices.count) available",
                        status: outputMappingManager.midiController.isConnected ? .success : .warning
                    )
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StatusIndicator: View {
    let icon: String
    let isActive: Bool
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .foregroundColor(isActive ? .green : .gray)
                .font(.caption)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(isActive ? .green : .gray)
        }
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    let status: StatusType
    
    enum StatusType {
        case success, warning, error, info, neutral
        
        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            case .info: return .blue
            case .neutral: return .secondary
            }
        }
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .foregroundColor(status.color)
        }
    }
}

// MARK: - Supporting Modal Views

struct ControllerSettingsView: View {
    @ObservedObject var oscController: OSCController
    @ObservedObject var midiController: MIDIController
    @ObservedObject var hotkeyController: HotkeyController
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Controller Settings")
                    .font(.title2)
                    .padding()
                
                // Implementation details for controller configuration
                Text("Configure OSC, MIDI, and Hotkey settings here")
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationTitle("Controllers")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct HotkeyListView: View {
    @ObservedObject var hotkeyController: HotkeyController
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(hotkeyController.registeredHotkeys, id: \.self) { hotkey in
                    Text(hotkey)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("Keyboard Shortcuts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

// MARK: - Preview

#Preview {
    let manager = OutputMappingManager(metalDevice: MTLCreateSystemDefaultDevice()!)
    return OutputMappingSystemView(outputMappingManager: manager)
}