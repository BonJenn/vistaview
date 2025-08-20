import SwiftUI

struct ExternalDisplaySetupGuide: View {
    @ObservedObject var externalDisplayManager: ExternalDisplayManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "tv.and.hifispeaker")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text("External Display Setup")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Configure your external displays for live output")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Step 1: Connect Display
                    setupStep(
                        number: "1",
                        title: "Connect External Display",
                        description: "Connect your external monitor, projector, or capture device to your Mac.",
                        icon: "cable.connector",
                        color: .blue
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Use HDMI, DisplayPort, USB-C, or Thunderbolt")
                            Text("• Ensure display is powered on and recognized by macOS")
                            Text("• Check System Settings > Displays if needed")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    // Step 2: Detect Display
                    setupStep(
                        number: "2",
                        title: "Detect Display",
                        description: "Vistaview automatically scans for connected displays every 5 seconds.",
                        icon: "magnifyingglass.circle",
                        color: .green
                    ) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Status:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(externalDisplayManager.displayConnectionStatus)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text("Last scan: \(externalDisplayManager.lastScanTime.formatted(.dateTime.hour().minute().second()))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Refresh Now") {
                                externalDisplayManager.refreshDisplays()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Step 3: Available Displays
                    if !externalDisplayManager.availableDisplays.isEmpty {
                        setupStep(
                            number: "3",
                            title: "Available Displays",
                            description: "Choose from your connected displays:",
                            icon: "list.bullet.rectangle",
                            color: .purple
                        ) {
                            VStack(spacing: 8) {
                                ForEach(externalDisplayManager.availableDisplays) { display in
                                    HStack {
                                        Circle()
                                            .fill(display.statusColor)
                                            .frame(width: 8, height: 8)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(display.name)
                                                .font(.callout)
                                                .fontWeight(.medium)
                                            
                                            Text("\(display.displayDescription) • \(display.colorSpace)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if display.isMain {
                                            Text("Main")
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.1))
                                                .foregroundColor(.blue)
                                                .cornerRadius(4)
                                        } else if display.isActive {
                                            Button("Use This Display") {
                                                externalDisplayManager.startFullScreenOutput(on: display)
                                                dismiss()
                                            }
                                            .buttonStyle(.borderedProminent)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    
                    // Step 4: Configure Output Mapping
                    setupStep(
                        number: "4",
                        title: "Configure Output Mapping",
                        description: "Adjust how your video content appears on the external display.",
                        icon: "rectangle.resize",
                        color: .orange
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Available Options:")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 16) {
                                featureTag("Position & Scale", icon: "arrow.up.left.and.down.right")
                                featureTag("Rotation", icon: "rotate.right")
                                featureTag("Opacity", icon: "eye")
                            }
                            
                            HStack(spacing: 16) {
                                featureTag("Presets", icon: "bookmark")
                                featureTag("Visual Editor", icon: "viewfinder")
                                featureTag("Live Preview", icon: "play.rectangle")
                            }
                        }
                    }
                    
                    // Step 5: Tips & Best Practices
                    setupStep(
                        number: "5",
                        title: "Tips & Best Practices",
                        description: "Get the best results from your external display setup.",
                        icon: "lightbulb",
                        color: .yellow
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            tipItem("Use high-refresh displays (60Hz+) for smooth video output")
                            tipItem("Match color profiles between displays for consistent colors")
                            tipItem("Test your setup before important events or streams")
                            tipItem("Save mapping presets for different display configurations")
                            tipItem("Monitor performance with the FPS counter on external display")
                        }
                    }
                }
                .padding()
            }
            
            // Action Buttons
            HStack {
                Button("Close Guide") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if !externalDisplayManager.getExternalDisplays().isEmpty {
                    Button("Start Using External Display") {
                        if let firstExternal = externalDisplayManager.getExternalDisplays().first {
                            externalDisplayManager.startFullScreenOutput(on: firstExternal)
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    @ViewBuilder
    private func setupStep<Content: View>(
        number: String,
        title: String,
        description: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Step number
                Text(number)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(Circle())
                
                // Icon
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                // Title and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Step content
            content()
                .padding(.leading, 44) // Align with title
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func featureTag(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .foregroundColor(.blue)
        .cornerRadius(4)
    }
    
    @ViewBuilder
    private func tipItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.yellow)
                .fontWeight(.bold)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    let manager = ExternalDisplayManager()
    ExternalDisplaySetupGuide(externalDisplayManager: manager)
}