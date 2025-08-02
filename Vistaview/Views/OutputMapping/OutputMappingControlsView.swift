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
                                            // Add comprehensive safety check before starting external output
                                            print("🖥️ External display button clicked: \(display.name)")
                                            
                                            // Validate initialization first
                                            guard externalDisplayManager.isProperlyInitialized else {
                                                print("❌ ExternalDisplayManager not properly initialized")
                                                
                                                // Show user-friendly message
                                                DispatchQueue.main.async {
                                                    let alert = NSAlert()
                                                    alert.messageText = "System Not Ready"
                                                    alert.informativeText = "The external display system is still initializing. Please wait a moment and try again."
                                                    alert.alertStyle = .informational
                                                    alert.addButton(withTitle: "OK")
                                                    alert.runModal()
                                                }
                                                return
                                            }
                                            
                                            if externalDisplayManager.selectedDisplay?.id == display.id && externalDisplayManager.isFullScreenActive {
                                                print("🖥️ Stopping current external output")
                                                externalDisplayManager.stopFullScreenOutput()
                                            } else {
                                                print("🖥️ Starting external output on: \(display.name)")
                                                
                                                // Start external output on main queue with safety
                                                DispatchQueue.main.async {
                                                    externalDisplayManager.startFullScreenOutput(on: display)
                                                }
                                            }
                                        }) {
                                            HStack {
                                                Text(display.name)
                                                Spacer()
                                                Text(display.displayDescription)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                
                                                // Add status indicator
                                                if externalDisplayManager.selectedDisplay?.id == display.id && externalDisplayManager.isFullScreenActive {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.green)
                                                        .font(.caption)
                                                }
                                            }
                                        }
                                        .disabled(!externalDisplayManager.isProperlyInitialized)
                                    }
                                    
                                    Divider()
                                    
                                    // Add refresh and debug buttons
                                    Button("🔄 Refresh Displays") {
                                        externalDisplayManager.refreshDisplays()
                                    }
                                    
                                    Button("🔧 Debug Info") {
                                        print("🔧 DEBUG INFO:")
                                        print("  Properly initialized: \(externalDisplayManager.isProperlyInitialized)")
                                        print("  Available displays: \(externalDisplayManager.availableDisplays.count)")
                                        print("  External displays: \(externalDisplayManager.getExternalDisplays().count)")
                                        print("  Active external output: \(externalDisplayManager.isFullScreenActive)")
                                        
                                        if let selected = externalDisplayManager.selectedDisplay {
                                            print("  Selected display: \(selected.name)")
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
                            
                            // DEBUG: Test button
                            Button("🧪 Test Window") {
                                testCreateWindow()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption2)
                            
                            // AGGRESSIVE: Force External Window
                            Button("🚨 FORCE External") {
                                forceCreateExternalWindow()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption2)
                            .foregroundColor(.red)
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
    
    // DEBUG: Test function
    private func testCreateWindow() {
        print("🧪 Creating test window...")
        
        // Try to put test window on external display
        let targetScreen = externalDisplayManager.getExternalDisplays().first
        let screenToUse = NSScreen.screens.first { screen in
            guard let target = targetScreen else { return false }
            return abs(screen.frame.origin.x - target.bounds.origin.x) < 100.0
        } ?? NSScreen.main!
        
        let screenFrame = screenToUse.frame
        let windowSize = CGSize(width: 400, height: 300)
        let windowOrigin = CGPoint(
            x: screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2,
            y: screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
        )
        
        let testWindow = NSWindow(
            contentRect: CGRect(origin: windowOrigin, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
            screen: screenToUse
        )
        
        testWindow.title = "🧪 Test Window (External Display)"
        testWindow.backgroundColor = .systemGreen
        testWindow.level = .floating
        
        // Add simple content
        let label = NSTextField(labelWithString: "Test Window on External Display\nIf you see this on your external display,\nwindow positioning works!")
        label.alignment = .center
        label.frame = CGRect(x: 50, y: 50, width: 300, height: 150)
        
        let contentView = NSView(frame: testWindow.contentRect(forFrameRect: testWindow.frame))
        contentView.addSubview(label)
        testWindow.contentView = contentView
        
        testWindow.makeKeyAndOrderFront(nil)
        testWindow.orderFrontRegardless()
        
        print("🧪 Test window created on screen: \(screenToUse.localizedName)")
        
        // Auto-close after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            testWindow.close()
            print("🧪 Test window closed")
        }
    }
    
    // AGGRESSIVE: Force create window on external display
    private func forceCreateExternalWindow() {
        print("🚨 FORCING external window creation...")
        
        // Get all screens
        let allScreens = NSScreen.screens
        print("🖥️ Available screens: \(allScreens.count)")
        
        for (index, screen) in allScreens.enumerated() {
            print("  Screen \(index): \(screen.localizedName) - Frame: \(screen.frame)")
        }
        
        // Find external screens (anything not main)
        let externalScreens = allScreens.filter { $0 != NSScreen.main }
        print("🖥️ External screens: \(externalScreens.count)")
        
        guard let targetScreen = externalScreens.first else {
            print("❌ No external screen found - using main with offset")
            createTestWindowOnMainWithOffset()
            return
        }
        
        print("🎯 Creating window on: \(targetScreen.localizedName)")
        
        // Create FULL SCREEN window on external display
        let screenFrame = targetScreen.frame
        let windowRect = CGRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y,
            width: screenFrame.width,
            height: screenFrame.height
        )
        
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        
        window.title = "🚨 FORCED EXTERNAL WINDOW"
        window.backgroundColor = .systemRed
        window.level = .floating
        window.hasShadow = true
        
        // AGGRESSIVE positioning
        window.setFrame(windowRect, display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        // Add content to verify it worked
        let label = NSTextField(labelWithString: """
        🚨 FORCED EXTERNAL WINDOW 🚨
        
        If you see this on your EXTERNAL display,
        then window positioning is working!
        
        Screen: \(targetScreen.localizedName)
        Frame: \(windowRect)
        
        This window will close in 15 seconds.
        """)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = .white
        
        let contentView = NSView(frame: windowRect)
        contentView.addSubview(label)
        label.frame = CGRect(x: 50, y: 50, width: windowRect.width - 100, height: windowRect.height - 100)
        
        window.contentView = contentView
        
        // Force positioning multiple times
        for i in 1...5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) {
                window.setFrame(windowRect, display: true, animate: false)
                print("🎯 Force attempt \(i) - Window on: \(window.screen?.localizedName ?? "unknown")")
            }
        }
        
        // Auto-close after 15 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            window.close()
            print("🚨 Forced window closed")
        }
    }
    
    private func createTestWindowOnMainWithOffset() {
        guard let mainScreen = NSScreen.main else { return }
        
        let mainFrame = mainScreen.frame
        let windowSize = CGSize(width: 800, height: 600)
        
        // Position window to the right of main screen (simulating external)
        let windowRect = CGRect(
            x: mainFrame.maxX + 100,  // To the right of main screen
            y: mainFrame.origin.y + 100,
            width: windowSize.width,
            height: windowSize.height
        )
        
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "🧪 Simulated External Window"
        window.backgroundColor = .systemBlue
        window.level = .floating
        
        let label = NSTextField(labelWithString: """
        🧪 SIMULATED EXTERNAL WINDOW
        
        This window is positioned to the right
        of your main screen to simulate an
        external display.
        
        If your cursor moves off the right edge
        of your main screen and appears here,
        the positioning logic is working.
        """)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 16)
        
        let contentView = NSView(frame: windowRect)
        contentView.addSubview(label)
        label.frame = CGRect(x: 50, y: 50, width: windowSize.width - 100, height: windowSize.height - 100)
        
        window.contentView = contentView
        window.setFrame(windowRect, display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        
        // Auto-close after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            window.close()
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